use super::*;
use crate::credential::{InMemorySecretStore, SecretStore};
use std::sync::{
    Mutex,
    atomic::{AtomicBool, Ordering},
};
use url::Url;

#[derive(Default)]
struct FailingProviderDeleteStore {
    fail_provider_delete: AtomicBool,
    inner: InMemorySecretStore,
}

#[async_trait]
impl SecretStore for FailingProviderDeleteStore {
    async fn save(
        &self,
        scope: &CredentialScope,
        secret_id: &SecretId,
        value: SecretMaterial,
    ) -> anyhow::Result<()> {
        self.inner.save(scope, secret_id, value).await
    }

    async fn load(
        &self,
        scope: &CredentialScope,
        secret_id: &SecretId,
    ) -> anyhow::Result<Option<SecretMaterial>> {
        self.inner.load(scope, secret_id).await
    }

    async fn delete(&self, scope: &CredentialScope, secret_id: &SecretId) -> anyhow::Result<bool> {
        if self.fail_provider_delete.load(Ordering::SeqCst)
            && matches!(
                secret_id.as_str().rsplit('.').next(),
                Some("access" | "refresh")
            )
        {
            anyhow::bail!("injected provider secret deletion failure");
        }
        self.inner.delete(scope, secret_id).await
    }

    async fn rotate(
        &self,
        scope: &CredentialScope,
        secret_id: &SecretId,
        value: SecretMaterial,
    ) -> anyhow::Result<()> {
        self.inner.rotate(scope, secret_id, value).await
    }
}

#[derive(Default)]
struct ProviderCalls {
    exchanges: usize,
    refreshes: usize,
}

struct FakeProvider {
    calls: Mutex<ProviderCalls>,
    authorization_origin: String,
    authorization_url_origin: String,
    inject_reserved_parameter: bool,
    refresh_scopes: BTreeSet<String>,
    stall_exchange: bool,
    stall_refresh: bool,
}

impl FakeProvider {
    fn new() -> Self {
        Self {
            calls: Mutex::new(ProviderCalls::default()),
            authorization_origin: "https://accounts.example.test".into(),
            authorization_url_origin: "https://accounts.example.test".into(),
            inject_reserved_parameter: false,
            refresh_scopes: scopes(),
            stall_exchange: false,
            stall_refresh: false,
        }
    }

    fn with_url_origin(origin: &str) -> Self {
        Self {
            authorization_url_origin: origin.into(),
            ..Self::new()
        }
    }

    fn with_refresh_scopes(refresh_scopes: BTreeSet<String>) -> Self {
        Self {
            refresh_scopes,
            ..Self::new()
        }
    }

    fn with_reserved_parameter() -> Self {
        Self {
            inject_reserved_parameter: true,
            ..Self::new()
        }
    }

    fn with_stalled_exchange() -> Self {
        Self {
            stall_exchange: true,
            ..Self::new()
        }
    }

    fn with_stalled_refresh() -> Self {
        Self {
            stall_refresh: true,
            ..Self::new()
        }
    }
}

#[async_trait]
impl OAuthProvider for FakeProvider {
    fn provider_id(&self) -> &str {
        "workspace"
    }

    fn authorization_origin(&self) -> &str {
        &self.authorization_origin
    }

    fn authorization_plan(
        &self,
        connector_ids: &BTreeSet<String>,
        capabilities: &BTreeSet<String>,
    ) -> Result<OAuthAuthorizationPlan, OAuthProviderError> {
        if capabilities != &BTreeSet::from(["read".into()]) {
            return Err(OAuthProviderError::new(
                OAuthProviderErrorCode::InvalidRequest,
            ));
        }
        let mut connector_scopes = BTreeMap::new();
        for connector_id in connector_ids {
            let scope = match connector_id.as_str() {
                "calendar" => "calendar.read",
                "contacts" => "contacts.read",
                _ => {
                    return Err(OAuthProviderError::new(
                        OAuthProviderErrorCode::InvalidRequest,
                    ));
                }
            };
            connector_scopes.insert(connector_id.clone(), BTreeSet::from([scope.into()]));
        }
        Ok(OAuthAuthorizationPlan {
            requested_scopes: connector_scopes.values().flatten().cloned().collect(),
            connector_scopes,
        })
    }

    fn authorization_url(
        &self,
        _request: OAuthAuthorizationUrlRequest,
    ) -> Result<String, OAuthProviderError> {
        let mut value = format!("{}/authorize?client_id=test", self.authorization_url_origin);
        if self.inject_reserved_parameter {
            value.push_str("&state=attacker-controlled");
        }
        Ok(value)
    }

    async fn exchange_code(
        &self,
        request: OAuthCodeExchangeRequest,
    ) -> Result<OAuthTokenGrant, OAuthProviderError> {
        if self.stall_exchange {
            tokio::time::sleep(PROVIDER_OPERATION_TIMEOUT + Duration::from_millis(50)).await;
        }
        assert_eq!(request.code.expose(), "provider-code");
        assert_eq!(request.pkce_verifier.expose().len(), 64);
        self.calls.lock().unwrap().exchanges += 1;
        Ok(OAuthTokenGrant {
            provider_subject: "user@example.test".into(),
            access_token: SecretMaterial::new("access-token").unwrap(),
            refresh_token: Some(SecretMaterial::new("refresh-token").unwrap()),
            granted_scopes: scopes(),
            expires_at: Some(Utc::now() + ChronoDuration::hours(1)),
        })
    }

    async fn refresh_token(
        &self,
        request: OAuthRefreshRequest,
    ) -> Result<OAuthTokenGrant, OAuthProviderError> {
        if self.stall_refresh {
            tokio::time::sleep(PROVIDER_OPERATION_TIMEOUT + Duration::from_millis(50)).await;
        }
        assert_eq!(request.refresh_token.expose(), "refresh-token");
        self.calls.lock().unwrap().refreshes += 1;
        Ok(OAuthTokenGrant {
            provider_subject: "user@example.test".into(),
            access_token: SecretMaterial::new("rotated-access-token").unwrap(),
            refresh_token: None,
            granted_scopes: self.refresh_scopes.clone(),
            expires_at: Some(Utc::now() + ChronoDuration::hours(1)),
        })
    }
}

fn scope() -> CredentialScope {
    CredentialScope {
        app_id: "com.example.oauth".into(),
        tenant_id: "local".into(),
        user_id: "user".into(),
    }
}

fn scopes() -> BTreeSet<String> {
    BTreeSet::from(["calendar.read".into(), "contacts.read".into()])
}

fn authorization_request() -> OAuthAuthorizationRequest {
    OAuthAuthorizationRequest {
        provider_id: "workspace".into(),
        connector_ids: BTreeSet::from(["calendar".into(), "contacts".into()]),
        requested_capabilities: BTreeSet::from(["read".into()]),
    }
}

async fn harness(
    provider: Arc<FakeProvider>,
) -> (
    Storage,
    Arc<InMemorySecretStore>,
    Arc<CredentialVault>,
    OAuthBroker,
) {
    let storage = Storage::connect("sqlite::memory:").await.unwrap();
    let metadata = crate::credential_sqlite::SqliteCredentialMetadataStore::from_storage(&storage)
        .await
        .unwrap();
    let secrets = Arc::new(InMemorySecretStore::default());
    let vault = Arc::new(CredentialVault::new_persistent(secrets.clone(), metadata));
    let broker = OAuthBroker::new(
        &storage,
        scope(),
        "http://127.0.0.1:49152/oauth/callback",
        vault.clone(),
        vec![provider],
    )
    .await
    .unwrap();
    (storage, secrets, vault, broker)
}

async fn failing_cleanup_harness() -> (
    Storage,
    Arc<FailingProviderDeleteStore>,
    Arc<CredentialVault>,
    OAuthBroker,
) {
    let storage = Storage::connect("sqlite::memory:").await.unwrap();
    let metadata = crate::credential_sqlite::SqliteCredentialMetadataStore::from_storage(&storage)
        .await
        .unwrap();
    let secrets = Arc::new(FailingProviderDeleteStore::default());
    let vault = Arc::new(CredentialVault::new_persistent(secrets.clone(), metadata));
    let broker = OAuthBroker::new(
        &storage,
        scope(),
        "http://127.0.0.1:49152/oauth/callback",
        vault.clone(),
        vec![Arc::new(FakeProvider::new())],
    )
    .await
    .unwrap();
    (storage, secrets, vault, broker)
}

fn callback_state(start: &OAuthAuthorizationStart) -> String {
    Url::parse(&start.authorization_url)
        .unwrap()
        .query_pairs()
        .find_map(|(key, value)| (key == "state").then(|| value.into_owned()))
        .unwrap()
}

async fn complete(broker: &OAuthBroker, now: DateTime<Utc>) -> OAuthAuthorizationView {
    let start = broker.start(authorization_request(), now).await.unwrap();
    broker
        .callback(
            OAuthCallbackRequest {
                state: callback_state(&start),
                code: Some(OAuthSecretString::new("provider-code".into()).unwrap()),
                error: None,
            },
            now + ChronoDuration::seconds(1),
        )
        .await
        .unwrap()
}

#[tokio::test]
async fn broker_keeps_pkce_and_tokens_out_of_persistent_status() {
    let provider = Arc::new(FakeProvider::new());
    let (storage, _secrets, vault, broker) = harness(provider.clone()).await;
    let now = Utc::now();
    let start = broker.start(authorization_request(), now).await.unwrap();
    assert_eq!(start.authorization_origin, "https://accounts.example.test");
    assert_eq!(start.status, OAuthAuthorizationStatus::Pending);
    let authorization_url = Url::parse(&start.authorization_url).unwrap();
    let pairs = authorization_url.query_pairs().collect::<Vec<_>>();
    for (name, expected) in [
        ("response_type", "code"),
        ("redirect_uri", "http://127.0.0.1:49152/oauth/callback"),
        ("code_challenge_method", "S256"),
        ("scope", "calendar.read contacts.read"),
    ] {
        assert_eq!(
            pairs
                .iter()
                .filter(|(key, _)| key == name)
                .map(|(_, value)| value.as_ref())
                .collect::<Vec<_>>(),
            vec![expected]
        );
    }
    assert_eq!(pairs.iter().filter(|(key, _)| key == "state").count(), 1);
    assert_eq!(
        pairs
            .iter()
            .filter(|(key, _)| key == "code_challenge")
            .count(),
        1
    );
    let state = callback_state(&start);
    assert_eq!(state.len(), 64);
    let pending = broker
        .status(&start.authorization_id)
        .await
        .unwrap()
        .unwrap();
    assert_eq!(pending.status, OAuthAuthorizationStatus::Pending);

    let completed = broker
        .callback(
            OAuthCallbackRequest {
                state: state.clone(),
                code: Some(OAuthSecretString::new("provider-code".into()).unwrap()),
                error: None,
            },
            now + ChronoDuration::seconds(1),
        )
        .await
        .unwrap();
    assert_eq!(completed.status, OAuthAuthorizationStatus::Completed);
    assert_eq!(completed.bindings.len(), 2);
    assert_eq!(provider.calls.lock().unwrap().exchanges, 1);
    assert!(
        broker
            .callback(
                OAuthCallbackRequest {
                    state,
                    code: Some(OAuthSecretString::new("provider-code".into()).unwrap()),
                    error: None,
                },
                now + ChronoDuration::seconds(2),
            )
            .await
            .is_err()
    );

    let accounts = vault.list_connector_accounts(&scope(), None).await.unwrap();
    assert_eq!(accounts.len(), 2);
    assert_eq!(accounts[0].account_id, accounts[1].account_id);
    for account in accounts {
        let leased = vault
            .lease_for_connector(
                &scope(),
                &account.connector_id,
                &account.account_id,
                &account.allowed_scopes,
            )
            .await
            .unwrap();
        assert_eq!(leased.expose_bytes(), b"access-token");
    }

    let persisted = sqlx::query_scalar::<_, String>(
        r#"SELECT group_concat(value, '|') FROM (
            SELECT authorization_id AS value FROM oauth_broker_sessions
            UNION ALL SELECT provider_id FROM oauth_broker_sessions
            UNION ALL SELECT connector_ids_json FROM oauth_broker_sessions
            UNION ALL SELECT requested_capabilities_json FROM oauth_broker_sessions
            UNION ALL SELECT requested_scopes_json FROM oauth_broker_sessions
            UNION ALL SELECT bindings_json FROM oauth_broker_sessions
            UNION ALL SELECT credential_id FROM credential_records
            UNION ALL SELECT access_secret_id FROM credential_records
            UNION ALL SELECT refresh_secret_id FROM credential_records
        )"#,
    )
    .fetch_one(storage.pool())
    .await
    .unwrap();
    for forbidden in ["provider-code", "access-token", "refresh-token"] {
        assert!(!persisted.contains(forbidden));
    }
    let status_json = serde_json::to_string(&completed).unwrap();
    for forbidden in [
        "authorizationUrl",
        "state",
        "verifier",
        "token",
        "credentialId",
    ] {
        assert!(!status_json.contains(forbidden));
    }
}

#[tokio::test]
async fn denial_cancel_expiry_and_origin_mismatch_fail_closed() {
    let (_storage, _secrets, _vault, broker) = harness(Arc::new(FakeProvider::new())).await;
    let now = Utc::now();
    let denied_start = broker.start(authorization_request(), now).await.unwrap();
    let denied = broker
        .callback(
            OAuthCallbackRequest {
                state: callback_state(&denied_start),
                code: None,
                error: Some("access_denied".into()),
            },
            now + ChronoDuration::seconds(1),
        )
        .await
        .unwrap();
    assert_eq!(denied.status, OAuthAuthorizationStatus::Denied);
    assert_eq!(denied.error_code.as_deref(), Some("access_denied"));

    let unavailable_start = broker.start(authorization_request(), now).await.unwrap();
    let unavailable = broker
        .callback(
            OAuthCallbackRequest {
                state: callback_state(&unavailable_start),
                code: None,
                error: Some("temporarily_unavailable".into()),
            },
            now + ChronoDuration::seconds(1),
        )
        .await
        .unwrap();
    assert_eq!(unavailable.status, OAuthAuthorizationStatus::Failed);
    assert_eq!(
        unavailable.error_code.as_deref(),
        Some("provider_temporarily_unavailable")
    );

    let cancelled_start = broker.start(authorization_request(), now).await.unwrap();
    let cancelled = broker
        .cancel(&cancelled_start.authorization_id, now)
        .await
        .unwrap()
        .unwrap();
    assert_eq!(cancelled.status, OAuthAuthorizationStatus::Cancelled);
    assert!(
        broker
            .callback(
                OAuthCallbackRequest {
                    state: callback_state(&cancelled_start),
                    code: Some(OAuthSecretString::new("provider-code".into()).unwrap()),
                    error: None,
                },
                now,
            )
            .await
            .is_err()
    );

    let expired_start = broker
        .start(
            authorization_request(),
            Utc::now() - ChronoDuration::minutes(20),
        )
        .await
        .unwrap();
    let expired = broker
        .status(&expired_start.authorization_id)
        .await
        .unwrap()
        .unwrap();
    assert_eq!(expired.status, OAuthAuthorizationStatus::Expired);

    let bad_provider = Arc::new(FakeProvider::with_url_origin(
        "https://attacker.example.test",
    ));
    let (_storage, _secrets, _vault, bad_broker) = harness(bad_provider).await;
    assert!(
        bad_broker
            .start(authorization_request(), now)
            .await
            .is_err()
    );

    let (_storage, _secrets, _vault, reserved_broker) =
        harness(Arc::new(FakeProvider::with_reserved_parameter())).await;
    assert!(
        reserved_broker
            .start(authorization_request(), now)
            .await
            .is_err()
    );
}

#[tokio::test]
async fn broker_restart_expires_sessions_and_scrubs_pkce_verifiers() {
    let (storage, _secrets, vault, broker) = harness(Arc::new(FakeProvider::new())).await;
    let start = broker
        .start(
            authorization_request(),
            Utc::now() - ChronoDuration::minutes(20),
        )
        .await
        .unwrap();
    let secret_id = SecretId::parse(
        &sqlx::query_scalar::<_, String>(
            "SELECT pkce_secret_id FROM oauth_broker_states WHERE authorization_id = ?",
        )
        .bind(&start.authorization_id)
        .fetch_one(storage.pool())
        .await
        .unwrap(),
    )
    .unwrap();
    drop(broker);

    let restarted = OAuthBroker::new(
        &storage,
        scope(),
        "http://127.0.0.1:49152/oauth/callback",
        vault.clone(),
        vec![Arc::new(FakeProvider::new())],
    )
    .await
    .unwrap();

    let expired = restarted
        .status(&start.authorization_id)
        .await
        .unwrap()
        .unwrap();
    assert_eq!(expired.status, OAuthAuthorizationStatus::Expired);
    let states: i64 =
        sqlx::query_scalar("SELECT COUNT(*) FROM oauth_broker_states WHERE authorization_id = ?")
            .bind(&start.authorization_id)
            .fetch_one(storage.pool())
            .await
            .unwrap();
    assert_eq!(states, 0);
    assert!(
        vault
            .consume_oauth_pkce_verifier(&scope(), &secret_id)
            .await
            .is_err()
    );
}

#[tokio::test]
async fn callback_marks_consumed_session_failed_when_provider_is_unavailable() {
    let provider = Arc::new(FakeProvider::new());
    let (storage, _secrets, _vault, broker) = harness(provider.clone()).await;
    let now = Utc::now();
    let start = broker.start(authorization_request(), now).await.unwrap();
    sqlx::query(
        r#"UPDATE oauth_broker_sessions SET provider_id = 'unavailable'
        WHERE authorization_id = ?"#,
    )
    .bind(&start.authorization_id)
    .execute(storage.pool())
    .await
    .unwrap();

    let failed = broker
        .callback(
            OAuthCallbackRequest {
                state: callback_state(&start),
                code: Some(OAuthSecretString::new("provider-code".into()).unwrap()),
                error: None,
            },
            now + ChronoDuration::seconds(1),
        )
        .await
        .unwrap();

    assert_eq!(failed.status, OAuthAuthorizationStatus::Failed);
    assert_eq!(failed.error_code.as_deref(), Some("provider_unavailable"));
    assert_eq!(provider.calls.lock().unwrap().exchanges, 0);
}

#[tokio::test]
async fn completion_persistence_failure_rolls_back_bindings_and_credential() {
    let (storage, _secrets, vault, broker) = harness(Arc::new(FakeProvider::new())).await;
    sqlx::query(
        r#"CREATE TRIGGER reject_oauth_completion
        BEFORE UPDATE OF status ON oauth_broker_sessions
        WHEN NEW.status = 'completed'
        BEGIN
            SELECT RAISE(ABORT, 'injected completion failure');
        END"#,
    )
    .execute(storage.pool())
    .await
    .unwrap();
    let now = Utc::now();
    let start = broker.start(authorization_request(), now).await.unwrap();

    let failed = broker
        .callback(
            OAuthCallbackRequest {
                state: callback_state(&start),
                code: Some(OAuthSecretString::new("provider-code".into()).unwrap()),
                error: None,
            },
            now + ChronoDuration::seconds(1),
        )
        .await
        .unwrap();

    assert_eq!(failed.status, OAuthAuthorizationStatus::Failed);
    assert_eq!(
        failed.error_code.as_deref(),
        Some("authorization_persistence_failed")
    );
    assert!(
        vault
            .list_connector_accounts(&scope(), None)
            .await
            .unwrap()
            .is_empty()
    );
    let revoked: i64 =
        sqlx::query_scalar("SELECT COUNT(*) FROM credential_records WHERE revoked_at IS NOT NULL")
            .fetch_one(storage.pool())
            .await
            .unwrap();
    assert_eq!(revoked, 1);
}

#[tokio::test]
async fn duplicate_authorization_preserves_existing_bindings_and_credential() {
    let provider = Arc::new(FakeProvider::new());
    let (storage, _secrets, vault, broker) = harness(provider).await;
    let first = complete(&broker, Utc::now()).await;
    let existing_accounts = vault.list_connector_accounts(&scope(), None).await.unwrap();
    let existing_credential_id = existing_accounts[0].credential_id.clone();

    let second_start = broker
        .start(authorization_request(), Utc::now())
        .await
        .unwrap();
    let failed = broker
        .callback(
            OAuthCallbackRequest {
                state: callback_state(&second_start),
                code: Some(OAuthSecretString::new("provider-code".into()).unwrap()),
                error: None,
            },
            Utc::now(),
        )
        .await
        .unwrap();

    assert_eq!(failed.status, OAuthAuthorizationStatus::Failed);
    assert_eq!(
        failed.error_code.as_deref(),
        Some("connector_binding_failed")
    );
    let preserved = vault.list_connector_accounts(&scope(), None).await.unwrap();
    assert_eq!(preserved.len(), 2);
    assert!(
        preserved
            .iter()
            .all(|account| account.credential_id == existing_credential_id)
    );
    let leased = vault
        .lease_for_connector(
            &scope(),
            "calendar",
            &first.bindings[0].account_id,
            &BTreeSet::from(["calendar.read".into()]),
        )
        .await
        .unwrap();
    assert_eq!(leased.expose_bytes(), b"access-token");
    let revoked: i64 =
        sqlx::query_scalar("SELECT COUNT(*) FROM credential_records WHERE revoked_at IS NOT NULL")
            .fetch_one(storage.pool())
            .await
            .unwrap();
    assert_eq!(revoked, 1);
}

#[tokio::test]
async fn refresh_is_serialized_and_rejects_scope_downgrade() {
    let provider = Arc::new(FakeProvider::new());
    let (_storage, _secrets, vault, broker) = harness(provider.clone()).await;
    let completed = complete(&broker, Utc::now()).await;
    let account = vault
        .list_connector_accounts(&scope(), Some("calendar"))
        .await
        .unwrap()
        .pop()
        .unwrap();
    let receipt = broker
        .refresh_credential(&account.credential_id)
        .await
        .unwrap();
    assert_eq!(receipt.granted_scopes, scopes());
    let leased = vault
        .lease_for_connector(
            &scope(),
            "calendar",
            &completed.bindings[0].account_id,
            &BTreeSet::from(["calendar.read".into()]),
        )
        .await
        .unwrap();
    assert_eq!(leased.expose_bytes(), b"rotated-access-token");
    assert_eq!(provider.calls.lock().unwrap().refreshes, 1);

    let downgraded = Arc::new(FakeProvider::with_refresh_scopes(BTreeSet::from([
        "calendar.read".into(),
    ])));
    let (_storage, _secrets, vault, broker) = harness(downgraded).await;
    complete(&broker, Utc::now()).await;
    let account = vault
        .list_connector_accounts(&scope(), Some("calendar"))
        .await
        .unwrap()
        .pop()
        .unwrap();
    assert!(
        broker
            .refresh_credential(&account.credential_id)
            .await
            .is_err()
    );
    let leased = vault
        .lease_for_connector(
            &scope(),
            "calendar",
            &account.account_id,
            &BTreeSet::from(["calendar.read".into()]),
        )
        .await
        .unwrap();
    assert_eq!(leased.expose_bytes(), b"access-token");
}

#[path = "oauth_recovery_tests.rs"]
mod recovery_tests;
