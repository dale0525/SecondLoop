use super::*;

struct BlockingCredentialSaveStore {
    block_once: AtomicBool,
    entered: tokio::sync::Semaphore,
    inner: InMemorySecretStore,
    release: tokio::sync::Semaphore,
}

impl BlockingCredentialSaveStore {
    fn new() -> Self {
        Self {
            block_once: AtomicBool::new(true),
            entered: tokio::sync::Semaphore::new(0),
            inner: InMemorySecretStore::default(),
            release: tokio::sync::Semaphore::new(0),
        }
    }

    async fn wait_until_blocked(&self) {
        self.entered.acquire().await.unwrap().forget();
    }

    fn release_save(&self) {
        self.release.add_permits(1);
    }
}

#[async_trait]
impl SecretStore for BlockingCredentialSaveStore {
    async fn save(
        &self,
        scope: &CredentialScope,
        secret_id: &SecretId,
        value: SecretMaterial,
    ) -> anyhow::Result<()> {
        if secret_id.as_str().ends_with(".access") && self.block_once.swap(false, Ordering::SeqCst)
        {
            self.entered.add_permits(1);
            self.release.acquire().await.unwrap().forget();
        }
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

#[tokio::test]
async fn stale_owner_cannot_activate_credentials_after_recovery_claim() {
    let storage = Storage::connect("sqlite::memory:").await.unwrap();
    let metadata = crate::credential_sqlite::SqliteCredentialMetadataStore::from_storage(&storage)
        .await
        .unwrap();
    let secrets = Arc::new(BlockingCredentialSaveStore::new());
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
    let now = Utc::now();
    let start = broker.start(authorization_request(), now).await.unwrap();
    let credential_id: String = sqlx::query_scalar(
        "SELECT credential_id FROM oauth_broker_sessions WHERE authorization_id = ?",
    )
    .bind(&start.authorization_id)
    .fetch_one(storage.pool())
    .await
    .unwrap();
    let callback_broker = broker.clone();
    let callback_state = callback_state(&start);
    let callback = tokio::spawn(async move {
        callback_broker
            .callback(
                OAuthCallbackRequest {
                    state: callback_state,
                    code: Some(OAuthSecretString::new("provider-code".into()).unwrap()),
                    error: None,
                },
                now,
            )
            .await
    });
    secrets.wait_until_blocked().await;

    let recovering = OAuthBroker::new(
        &storage,
        scope(),
        "http://127.0.0.1:49152/oauth/callback",
        vault.clone(),
        vec![Arc::new(FakeProvider::new())],
    )
    .await
    .unwrap();
    recovering
        .cleanup_stale(now + ChronoDuration::seconds(EXCHANGE_LEASE_SECONDS + 1))
        .await
        .unwrap();
    secrets.release_save();

    let result = callback.await.unwrap().unwrap();
    assert_eq!(result.status, OAuthAuthorizationStatus::Failed);
    let session = recovering
        .store
        .get(&scope(), &start.authorization_id)
        .await
        .unwrap()
        .unwrap();
    assert!(session.credential_id.is_none());
    let credentials: i64 =
        sqlx::query_scalar("SELECT COUNT(*) FROM credential_records WHERE credential_id = ?")
            .bind(&credential_id)
            .fetch_one(storage.pool())
            .await
            .unwrap();
    assert_eq!(credentials, 0);
    assert!(
        vault
            .list_connector_accounts(&scope(), None)
            .await
            .unwrap()
            .is_empty()
    );
    for secret_id in [
        recovery_access_secret_id(&credential_id).unwrap(),
        recovery_refresh_secret_id(&credential_id).unwrap(),
    ] {
        assert!(secrets.load(&scope(), &secret_id).await.unwrap().is_none());
    }
    sqlx::query("UPDATE credential_secret_cleanup SET not_before = ?")
        .bind((Utc::now() - ChronoDuration::seconds(1)).to_rfc3339())
        .execute(storage.pool())
        .await
        .unwrap();
    vault
        .cleanup_pending_secret_material(&scope())
        .await
        .unwrap();
    let pending: i64 = sqlx::query_scalar(
        "SELECT COUNT(*) FROM credential_secret_cleanup WHERE cleaned_at IS NULL",
    )
    .fetch_one(storage.pool())
    .await
    .unwrap();
    assert_eq!(pending, 0);
    let tombstones: i64 = sqlx::query_scalar(
        "SELECT COUNT(*) FROM credential_secret_cleanup WHERE phase = 'cleanup' AND cleaned_at IS NOT NULL",
    )
    .fetch_one(storage.pool())
    .await
    .unwrap();
    assert_eq!(tombstones, 2);
}
#[tokio::test]
async fn preparing_sessions_recover_before_or_after_pkce_secret_persistence() {
    let (storage, secrets, vault, broker) = harness(Arc::new(FakeProvider::new())).await;
    let now = Utc::now() - ChronoDuration::minutes(5);
    let mut authorizations = Vec::new();
    for (suffix, state_character, persist_secret) in [("before", "a", false), ("after", "b", true)]
    {
        let authorization_id = format!("preparing-{suffix}");
        let credential_id = format!("oauth.{authorization_id}");
        let pkce_secret_id = SecretId::parse(&format!("oauth.pkce.{authorization_id}")).unwrap();
        let session = OAuthAuthorizationSession {
            authorization_id: authorization_id.clone(),
            exchange_owner_id: Some(broker.owner_id.clone()),
            credential_id: Some(credential_id),
            provider_id: "workspace".into(),
            connector_ids: BTreeSet::from(["calendar".into(), "contacts".into()]),
            requested_capabilities: BTreeSet::from(["read".into()]),
            requested_scopes: scopes(),
            connector_scopes: BTreeMap::from([
                ("calendar".into(), BTreeSet::from(["calendar.read".into()])),
                ("contacts".into(), BTreeSet::from(["contacts.read".into()])),
            ]),
            status: OAuthAuthorizationStatus::Preparing,
            bindings: Vec::new(),
            error_code: None,
            expires_at: now + ChronoDuration::minutes(10),
            created_at: now,
            updated_at: now,
        };
        broker
            .store
            .create(
                &scope(),
                &session,
                &state_character.repeat(64),
                &pkce_secret_id,
                &broker.owner_id,
                now + ChronoDuration::seconds(EXCHANGE_LEASE_SECONDS),
            )
            .await
            .unwrap();
        if persist_secret {
            vault
                .save_oauth_pkce_verifier(
                    &scope(),
                    &pkce_secret_id,
                    SecretMaterial::new("preparing-verifier").unwrap(),
                )
                .await
                .unwrap();
        }
        authorizations.push((authorization_id, pkce_secret_id));
    }
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
    for (authorization_id, pkce_secret_id) in authorizations {
        let recovered = restarted.status(&authorization_id).await.unwrap().unwrap();
        assert_eq!(recovered.status, OAuthAuthorizationStatus::Failed);
        assert_eq!(
            recovered.error_code.as_deref(),
            Some("authorization_interrupted")
        );
        assert!(
            secrets
                .load(&scope(), &pkce_secret_id)
                .await
                .unwrap()
                .is_none()
        );
        let states: i64 = sqlx::query_scalar(
            "SELECT COUNT(*) FROM oauth_broker_states WHERE authorization_id = ?",
        )
        .bind(&authorization_id)
        .fetch_one(storage.pool())
        .await
        .unwrap();
        assert_eq!(states, 0);
    }
}

#[tokio::test]
async fn broker_restart_recovers_interrupted_exchanges_and_partial_credentials() {
    let (storage, _secrets, vault, broker) = harness(Arc::new(FakeProvider::new())).await;
    let now = Utc::now() - ChronoDuration::minutes(5);
    let materialized_start = broker.start(authorization_request(), now).await.unwrap();
    let (materialized_session, materialized_pkce_id) = match broker
        .store
        .consume_state(
            &scope(),
            &callback_state(&materialized_start),
            &broker.owner_id,
            now + ChronoDuration::seconds(EXCHANGE_LEASE_SECONDS),
            now,
        )
        .await
        .unwrap()
    {
        OAuthStateConsumption::Ready {
            session,
            pkce_secret_id,
        } => (*session, pkce_secret_id),
        OAuthStateConsumption::Expired { .. } => panic!("fresh OAuth state expired"),
    };
    let credential_id = materialized_session.credential_id.clone().unwrap();
    vault
        .save_provider_credential(
            &scope(),
            ProviderCredential {
                credential_id: credential_id.clone(),
                provider_id: "workspace".into(),
                provider_subject: "interrupted@example.test".into(),
                access_secret_id: SecretId::parse("oauth.access.interrupted").unwrap(),
                refresh_secret_id: Some(SecretId::parse("oauth.refresh.interrupted").unwrap()),
                granted_scopes: scopes(),
                expires_at: Some(now + ChronoDuration::hours(1)),
                revoked_at: None,
            },
            SecretMaterial::new("interrupted-access").unwrap(),
            Some(SecretMaterial::new("interrupted-refresh").unwrap()),
        )
        .await
        .unwrap();
    vault
        .register_account_persistent_exclusive(ConnectorAccount {
            account_id: "interrupted-account".into(),
            connector_id: "calendar".into(),
            credential_id: credential_id.clone(),
            scope: scope(),
            allowed_scopes: BTreeSet::from(["calendar.read".into()]),
        })
        .await
        .unwrap();

    let empty_start = broker.start(authorization_request(), now).await.unwrap();
    let empty_pkce_id = match broker
        .store
        .consume_state(
            &scope(),
            &callback_state(&empty_start),
            &broker.owner_id,
            now + ChronoDuration::seconds(EXCHANGE_LEASE_SECONDS),
            now,
        )
        .await
        .unwrap()
    {
        OAuthStateConsumption::Ready { pkce_secret_id, .. } => pkce_secret_id,
        OAuthStateConsumption::Expired { .. } => panic!("fresh OAuth state expired"),
    };
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

    for authorization_id in [
        &materialized_start.authorization_id,
        &empty_start.authorization_id,
    ] {
        let failed = restarted.status(authorization_id).await.unwrap().unwrap();
        assert_eq!(failed.status, OAuthAuthorizationStatus::Failed);
        assert_eq!(
            failed.error_code.as_deref(),
            Some("authorization_interrupted")
        );
        let status_json = serde_json::to_string(&failed).unwrap();
        assert!(!status_json.contains("credentialId"));
        assert!(!status_json.contains(&credential_id));
    }
    assert!(
        vault
            .list_connector_accounts(&scope(), None)
            .await
            .unwrap()
            .is_empty()
    );
    let recovered = vault
        .get_provider_credential(&scope(), &credential_id)
        .await
        .unwrap()
        .unwrap();
    assert!(recovered.revoked_at.is_some());
    for pkce_secret_id in [materialized_pkce_id, empty_pkce_id] {
        assert!(
            vault
                .consume_oauth_pkce_verifier(&scope(), &pkce_secret_id)
                .await
                .is_err()
        );
    }
}

#[tokio::test]
async fn second_broker_does_not_recover_an_active_exchange_lease() {
    let (storage, _secrets, vault, broker) = harness(Arc::new(FakeProvider::new())).await;
    let now = Utc::now();
    let start = broker.start(authorization_request(), now).await.unwrap();
    let consumed = broker
        .store
        .consume_state(
            &scope(),
            &callback_state(&start),
            &broker.owner_id,
            now + ChronoDuration::seconds(EXCHANGE_LEASE_SECONDS),
            now,
        )
        .await
        .unwrap();
    assert!(matches!(consumed, OAuthStateConsumption::Ready { .. }));

    let second = OAuthBroker::new(
        &storage,
        scope(),
        "http://127.0.0.1:49152/oauth/callback",
        vault,
        vec![Arc::new(FakeProvider::new())],
    )
    .await
    .unwrap();
    let active = second
        .store
        .get(&scope(), &start.authorization_id)
        .await
        .unwrap()
        .unwrap();
    assert_eq!(active.status, OAuthAuthorizationStatus::Exchanging);
    assert_eq!(
        active.exchange_owner_id.as_deref(),
        Some(broker.owner_id.as_str())
    );

    second
        .cleanup_stale(now + ChronoDuration::seconds(EXCHANGE_LEASE_SECONDS + 1))
        .await
        .unwrap();
    let recovered = second
        .store
        .get(&scope(), &start.authorization_id)
        .await
        .unwrap()
        .unwrap();
    assert_eq!(recovered.status, OAuthAuthorizationStatus::Failed);
    assert_eq!(
        recovered.error_code.as_deref(),
        Some("authorization_interrupted")
    );
}

#[tokio::test]
async fn cleanup_failure_keeps_a_durable_recovery_pointer_until_retry_succeeds() {
    let (storage, secrets, vault, broker) = failing_cleanup_harness().await;
    complete(&broker, Utc::now()).await;
    let now = Utc::now();
    let start = broker.start(authorization_request(), now).await.unwrap();
    secrets.fail_provider_delete.store(true, Ordering::SeqCst);
    assert!(
        broker
            .callback(
                OAuthCallbackRequest {
                    state: callback_state(&start),
                    code: Some(OAuthSecretString::new("provider-code".into()).unwrap()),
                    error: None,
                },
                now,
            )
            .await
            .is_err()
    );

    let recoverable = broker
        .store
        .get(&scope(), &start.authorization_id)
        .await
        .unwrap()
        .unwrap();
    assert_eq!(recoverable.status, OAuthAuthorizationStatus::Failed);
    assert_eq!(
        recoverable.error_code.as_deref(),
        Some("connector_binding_failed")
    );
    assert!(recoverable.credential_id.is_some());
    assert_eq!(
        vault
            .list_connector_accounts(&scope(), None)
            .await
            .unwrap()
            .len(),
        2
    );
    let pending: i64 = sqlx::query_scalar(
        "SELECT COUNT(*) FROM credential_secret_cleanup WHERE cleaned_at IS NULL",
    )
    .fetch_one(storage.pool())
    .await
    .unwrap();
    assert!(pending > 0);

    secrets.fail_provider_delete.store(false, Ordering::SeqCst);
    broker
        .cleanup_stale(now + ChronoDuration::seconds(EXCHANGE_LEASE_SECONDS + 1))
        .await
        .unwrap();
    let recovered = broker
        .store
        .get(&scope(), &start.authorization_id)
        .await
        .unwrap()
        .unwrap();
    assert_eq!(recovered.status, OAuthAuthorizationStatus::Failed);
    assert!(recovered.credential_id.is_none());
    let pending: i64 = sqlx::query_scalar(
        "SELECT COUNT(*) FROM credential_secret_cleanup WHERE cleaned_at IS NULL",
    )
    .fetch_one(storage.pool())
    .await
    .unwrap();
    assert_eq!(pending, 0);
    let tombstones: i64 = sqlx::query_scalar(
        "SELECT COUNT(*) FROM credential_secret_cleanup WHERE cleaned_at IS NOT NULL",
    )
    .fetch_one(storage.pool())
    .await
    .unwrap();
    assert!(tombstones > 0);
    assert_eq!(
        vault
            .list_connector_accounts(&scope(), None)
            .await
            .unwrap()
            .len(),
        2
    );
}

#[tokio::test]
async fn provider_exchange_and_refresh_operations_time_out() {
    let (_storage, _secrets, vault, broker) =
        harness(Arc::new(FakeProvider::with_stalled_exchange())).await;
    let now = Utc::now();
    let start = broker.start(authorization_request(), now).await.unwrap();
    let failed = broker
        .callback(
            OAuthCallbackRequest {
                state: callback_state(&start),
                code: Some(OAuthSecretString::new("provider-code".into()).unwrap()),
                error: None,
            },
            now,
        )
        .await
        .unwrap();
    assert_eq!(failed.status, OAuthAuthorizationStatus::Failed);
    assert_eq!(
        failed.error_code.as_deref(),
        Some("provider_exchange_timeout")
    );
    assert!(
        vault
            .list_connector_accounts(&scope(), None)
            .await
            .unwrap()
            .is_empty()
    );

    let (storage, _secrets, vault, broker) = harness(Arc::new(FakeProvider::new())).await;
    complete(&broker, Utc::now()).await;
    let account = vault
        .list_connector_accounts(&scope(), Some("calendar"))
        .await
        .unwrap()
        .pop()
        .unwrap();
    drop(broker);
    let stalled = OAuthBroker::new(
        &storage,
        scope(),
        "http://127.0.0.1:49152/oauth/callback",
        vault,
        vec![Arc::new(FakeProvider::with_stalled_refresh())],
    )
    .await
    .unwrap();
    let error = stalled
        .refresh_credential(&account.credential_id)
        .await
        .unwrap_err();
    assert_eq!(error.to_string(), "provider_refresh_timeout");
}
