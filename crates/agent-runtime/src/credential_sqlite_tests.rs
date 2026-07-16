use super::*;
use crate::credential::{CredentialVault, InMemorySecretStore, SecretMaterial, SecretStore};
use chrono::Duration;
use std::sync::{
    Arc,
    atomic::{AtomicUsize, Ordering},
};

#[derive(Default)]
struct FlakySecretStore {
    delete_failures: AtomicUsize,
    inner: InMemorySecretStore,
}

impl FlakySecretStore {
    fn fail_next_deletes(&self, count: usize) {
        self.delete_failures.store(count, Ordering::SeqCst);
    }
}

#[async_trait::async_trait]
impl SecretStore for FlakySecretStore {
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
        if self
            .delete_failures
            .fetch_update(Ordering::SeqCst, Ordering::SeqCst, |remaining| {
                remaining.checked_sub(1)
            })
            .is_ok()
        {
            anyhow::bail!("injected secret deletion failure");
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

fn scope(app_id: &str) -> CredentialScope {
    CredentialScope {
        app_id: app_id.into(),
        tenant_id: "tenant".into(),
        user_id: "user".into(),
    }
}

fn credential(secret_id: &SecretId) -> ProviderCredential {
    ProviderCredential {
        access_secret_id: secret_id.clone(),
        credential_id: "workspace-principal".into(),
        expires_at: Some(Utc::now() + Duration::minutes(10)),
        granted_scopes: BTreeSet::from(["calendar.read".into(), "contacts.read".into()]),
        provider_id: "workspace".into(),
        provider_subject: "provider-user-1".into(),
        refresh_secret_id: None,
        revoked_at: None,
    }
}

fn binding(
    account_scope: &CredentialScope,
    connector_id: &str,
    allowed_scope: &str,
) -> ConnectorAccount {
    ConnectorAccount {
        account_id: "primary".into(),
        allowed_scopes: BTreeSet::from([allowed_scope.into()]),
        connector_id: connector_id.into(),
        credential_id: "workspace-principal".into(),
        scope: account_scope.clone(),
    }
}

#[tokio::test]
async fn shared_principal_bindings_survive_and_revoke_only_after_last_unbind() {
    let storage = Storage::connect("sqlite::memory:").await.unwrap();
    let metadata = SqliteCredentialMetadataStore::from_storage(&storage)
        .await
        .unwrap();
    let secrets = Arc::new(InMemorySecretStore::default());
    let vault = CredentialVault::new_persistent(secrets.clone(), metadata.clone());
    let account_scope = scope("app-a");
    let secret_id = SecretId::parse("workspace.access").unwrap();
    secrets
        .save(
            &account_scope,
            &secret_id,
            SecretMaterial::new("access-token").unwrap(),
        )
        .await
        .unwrap();
    vault
        .register_provider_credential_persistent(&account_scope, credential(&secret_id))
        .await
        .unwrap();
    for account in [
        binding(&account_scope, "calendar", "calendar.read"),
        binding(&account_scope, "contacts", "contacts.read"),
    ] {
        vault.register_account_persistent(account).await.unwrap();
    }
    let mut overbroad = binding(&account_scope, "mail", "mail.send");
    overbroad.allowed_scopes.insert("calendar.read".into());
    assert!(vault.register_account_persistent(overbroad).await.is_err());

    let resumed = CredentialVault::new_persistent(secrets.clone(), metadata);
    assert_eq!(
        resumed
            .list_connector_accounts(&account_scope, None)
            .await
            .unwrap()
            .len(),
        2
    );
    assert_eq!(
        resumed
            .list_connector_accounts(&account_scope, Some("calendar"))
            .await
            .unwrap()
            .len(),
        1
    );
    for (connector_id, required) in [("calendar", "calendar.read"), ("contacts", "contacts.read")] {
        let leased = resumed
            .lease_for_connector(
                &account_scope,
                connector_id,
                "primary",
                &BTreeSet::from([required.into()]),
            )
            .await
            .unwrap();
        assert_eq!(leased.expose_bytes(), b"access-token");
    }
    let (_, remaining) = resumed
        .remove_connector_account(&account_scope, "calendar", "primary")
        .await
        .unwrap()
        .unwrap();
    assert_eq!(remaining, 1);
    assert!(
        resumed
            .revoke_provider_credential(&account_scope, "workspace-principal", Utc::now())
            .await
            .is_err()
    );
    let (_, remaining) = resumed
        .remove_connector_account(&account_scope, "contacts", "primary")
        .await
        .unwrap()
        .unwrap();
    assert_eq!(remaining, 0);
    assert!(
        resumed
            .revoke_provider_credential(&account_scope, "workspace-principal", Utc::now())
            .await
            .unwrap()
    );
    assert!(
        secrets
            .load(&account_scope, &secret_id)
            .await
            .unwrap()
            .is_none()
    );
}

#[tokio::test]
async fn legacy_account_schema_migrates_without_exposing_secret_material() {
    let storage = Storage::connect("sqlite::memory:").await.unwrap();
    sqlx::query(
        r#"CREATE TABLE connector_accounts (
            app_id TEXT NOT NULL, tenant_id TEXT NOT NULL, user_id TEXT NOT NULL,
            account_id TEXT NOT NULL, connector_id TEXT NOT NULL, provider_id TEXT NOT NULL,
            secret_id TEXT NOT NULL, granted_scopes_json TEXT NOT NULL, expires_at TEXT,
            updated_at TEXT NOT NULL,
            PRIMARY KEY(app_id, tenant_id, user_id, account_id)
        )"#,
    )
    .execute(storage.pool())
    .await
    .unwrap();
    sqlx::query(
        r#"INSERT INTO connector_accounts VALUES (
            'app-a', 'tenant', 'user', 'primary', 'mail', 'imap-smtp',
            'mail.password', '["mail.read"]', NULL, '2026-07-15T00:00:00Z'
        )"#,
    )
    .execute(storage.pool())
    .await
    .unwrap();
    let metadata = SqliteCredentialMetadataStore::from_storage(&storage)
        .await
        .unwrap();
    let secrets = Arc::new(InMemorySecretStore::default());
    let account_scope = scope("app-a");
    let secret_id = SecretId::parse("mail.password").unwrap();
    secrets
        .save(
            &account_scope,
            &secret_id,
            SecretMaterial::new("password").unwrap(),
        )
        .await
        .unwrap();
    let resumed = CredentialVault::new_persistent(secrets, metadata);
    let leased = resumed
        .lease_for_connector(
            &account_scope,
            "mail",
            "primary",
            &BTreeSet::from(["mail.read".into()]),
        )
        .await
        .unwrap();
    assert_eq!(leased.expose_bytes(), b"password");
}

#[tokio::test]
async fn oauth_state_is_single_use_and_pkce_secret_is_scrubbed() {
    let storage = Storage::connect("sqlite::memory:").await.unwrap();
    let metadata = SqliteCredentialMetadataStore::from_storage(&storage)
        .await
        .unwrap();
    let secrets = Arc::new(InMemorySecretStore::default());
    let vault = CredentialVault::new_persistent(secrets.clone(), metadata);
    let account_scope = scope("app-a");
    let verifier_id = SecretId::parse("oauth.state.verifier").unwrap();
    vault
        .begin_oauth_authorization(
            &account_scope,
            OAuthAuthorizationState {
                state_id: "state-1".into(),
                connector_id: "calendar".into(),
                account_id: "primary".into(),
                pkce_verifier_secret_id: verifier_id.clone(),
                redirect_uri: "http://127.0.0.1/callback".into(),
                requested_scopes: BTreeSet::from(["calendar.read".into()]),
                expires_at: Utc::now() + Duration::minutes(5),
            },
            SecretMaterial::new("verifier").unwrap(),
        )
        .await
        .unwrap();
    let (_, verifier) = vault
        .consume_oauth_authorization(&account_scope, "state-1", Utc::now())
        .await
        .unwrap();
    assert_eq!(verifier.expose_bytes(), b"verifier");
    assert!(
        secrets
            .load(&account_scope, &verifier_id)
            .await
            .unwrap()
            .is_none()
    );
    assert!(
        vault
            .consume_oauth_authorization(&account_scope, "state-1", Utc::now())
            .await
            .is_err()
    );
}

#[tokio::test]
async fn revoked_credential_secret_cleanup_retries_after_store_failure() {
    let storage = Storage::connect("sqlite::memory:").await.unwrap();
    let metadata = SqliteCredentialMetadataStore::from_storage(&storage)
        .await
        .unwrap();
    let secrets = Arc::new(FlakySecretStore::default());
    let vault = CredentialVault::new_persistent(secrets.clone(), metadata.clone());
    let account_scope = scope("app-a");
    let access_id = SecretId::parse("workspace.access.retry").unwrap();
    let refresh_id = SecretId::parse("workspace.refresh.retry").unwrap();
    let mut provider_credential = credential(&access_id);
    provider_credential.refresh_secret_id = Some(refresh_id.clone());
    vault
        .save_provider_credential(
            &account_scope,
            provider_credential,
            SecretMaterial::new("access-token").unwrap(),
            Some(SecretMaterial::new("refresh-token").unwrap()),
        )
        .await
        .unwrap();

    secrets.fail_next_deletes(1);
    assert!(
        vault
            .revoke_provider_credential(&account_scope, "workspace-principal", Utc::now())
            .await
            .is_err()
    );
    assert_eq!(
        metadata
            .pending_secret_cleanup(&account_scope)
            .await
            .unwrap()
            .len(),
        2
    );
    assert!(
        secrets
            .load(&account_scope, &access_id)
            .await
            .unwrap()
            .is_some()
    );

    assert!(
        vault
            .revoke_provider_credential(&account_scope, "workspace-principal", Utc::now())
            .await
            .unwrap()
    );
    assert!(
        metadata
            .pending_secret_cleanup(&account_scope)
            .await
            .unwrap()
            .is_empty()
    );
    assert!(
        secrets
            .load(&account_scope, &access_id)
            .await
            .unwrap()
            .is_none()
    );
    assert!(
        secrets
            .load(&account_scope, &refresh_id)
            .await
            .unwrap()
            .is_none()
    );
}

#[tokio::test]
async fn rotated_credential_keeps_durable_cleanup_for_retired_secrets() {
    let storage = Storage::connect("sqlite::memory:").await.unwrap();
    let metadata = SqliteCredentialMetadataStore::from_storage(&storage)
        .await
        .unwrap();
    let secrets = Arc::new(FlakySecretStore::default());
    let vault = CredentialVault::new_persistent(secrets.clone(), metadata.clone());
    let account_scope = scope("app-a");
    let old_access = SecretId::parse("workspace.access.old").unwrap();
    let old_refresh = SecretId::parse("workspace.refresh.old").unwrap();
    let mut initial = credential(&old_access);
    initial.refresh_secret_id = Some(old_refresh.clone());
    vault
        .save_provider_credential(
            &account_scope,
            initial,
            SecretMaterial::new("old-access").unwrap(),
            Some(SecretMaterial::new("old-refresh").unwrap()),
        )
        .await
        .unwrap();

    let new_access = SecretId::parse("workspace.access.new").unwrap();
    let new_refresh = SecretId::parse("workspace.refresh.new").unwrap();
    let mut replacement = credential(&new_access);
    replacement.refresh_secret_id = Some(new_refresh.clone());
    secrets.fail_next_deletes(1);
    vault
        .replace_provider_credential(
            &account_scope,
            replacement,
            SecretMaterial::new("new-access").unwrap(),
            Some(SecretMaterial::new("new-refresh").unwrap()),
        )
        .await
        .unwrap();

    let current = vault
        .get_provider_credential(&account_scope, "workspace-principal")
        .await
        .unwrap()
        .unwrap();
    assert_eq!(current.access_secret_id, new_access);
    assert_eq!(current.refresh_secret_id.as_ref(), Some(&new_refresh));
    assert_eq!(
        metadata
            .pending_secret_cleanup(&account_scope)
            .await
            .unwrap()
            .len(),
        2
    );
    assert!(
        secrets
            .load(&account_scope, &old_access)
            .await
            .unwrap()
            .is_some()
    );

    vault
        .cleanup_pending_secret_material(&account_scope)
        .await
        .unwrap();
    assert!(
        metadata
            .pending_secret_cleanup(&account_scope)
            .await
            .unwrap()
            .is_empty()
    );
    assert!(
        secrets
            .load(&account_scope, &old_access)
            .await
            .unwrap()
            .is_none()
    );
    assert!(
        secrets
            .load(&account_scope, &old_refresh)
            .await
            .unwrap()
            .is_none()
    );
    assert!(
        secrets
            .load(&account_scope, &new_access)
            .await
            .unwrap()
            .is_some()
    );
    assert!(
        secrets
            .load(&account_scope, &new_refresh)
            .await
            .unwrap()
            .is_some()
    );
}
