use super::*;
use crate::{credential_sqlite::SqliteCredentialMetadataStore, storage::Storage};
use std::sync::atomic::{AtomicBool, Ordering};

#[derive(Default)]
struct FailingDeleteStore {
    fail_delete: AtomicBool,
    inner: InMemorySecretStore,
}

#[async_trait]
impl SecretStore for FailingDeleteStore {
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
        if self.fail_delete.load(Ordering::SeqCst) {
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

fn provider_credential(
    credential_id: &str,
    access_secret_id: &str,
    refresh_secret_id: &str,
) -> ProviderCredential {
    ProviderCredential {
        credential_id: credential_id.into(),
        provider_id: "workspace".into(),
        provider_subject: "user@example.test".into(),
        access_secret_id: SecretId::parse(access_secret_id).unwrap(),
        refresh_secret_id: Some(SecretId::parse(refresh_secret_id).unwrap()),
        granted_scopes: BTreeSet::from(["calendar.read".into()]),
        expires_at: None,
        revoked_at: None,
    }
}

fn scope(app_id: &str) -> CredentialScope {
    CredentialScope {
        app_id: app_id.into(),
        tenant_id: "tenant".into(),
        user_id: "user".into(),
    }
}

#[tokio::test]
async fn secrets_are_scoped_rotatable_and_redacted() {
    let store = InMemorySecretStore::default();
    let id = SecretId::parse("mail.account.primary").unwrap();
    store
        .save(
            &scope("com.example.a"),
            &id,
            SecretMaterial::new("old").unwrap(),
        )
        .await
        .unwrap();
    assert!(
        store
            .load(&scope("com.example.b"), &id)
            .await
            .unwrap()
            .is_none()
    );
    store
        .rotate(
            &scope("com.example.a"),
            &id,
            SecretMaterial::new("new").unwrap(),
        )
        .await
        .unwrap();
    let loaded = store
        .load(&scope("com.example.a"), &id)
        .await
        .unwrap()
        .unwrap();
    assert_eq!(loaded.expose_bytes(), b"new");
    assert_eq!(format!("{loaded:?}"), "SecretMaterial([REDACTED])");
}

#[tokio::test]
async fn vault_only_leases_exact_connector_account_and_scopes() {
    let store = Arc::new(InMemorySecretStore::default());
    let id = SecretId::parse("mail.account.primary").unwrap();
    let account_scope = scope("com.example.mail");
    store
        .save(
            &account_scope,
            &id,
            SecretMaterial::new("credential").unwrap(),
        )
        .await
        .unwrap();
    let vault = CredentialVault::new(store);
    vault
        .register_provider_credential(
            &account_scope,
            ProviderCredential {
                access_secret_id: id,
                credential_id: "fake-principal".into(),
                expires_at: None,
                granted_scopes: BTreeSet::from(["contacts.read".into(), "mail.read".into()]),
                provider_id: "fake".into(),
                provider_subject: "provider-user".into(),
                refresh_secret_id: None,
                revoked_at: None,
            },
        )
        .unwrap();
    vault
        .register_account(ConnectorAccount {
            account_id: "primary".into(),
            allowed_scopes: BTreeSet::from(["mail.read".into()]),
            connector_id: "mail.fake".into(),
            credential_id: "fake-principal".into(),
            scope: account_scope.clone(),
        })
        .unwrap();
    vault
        .register_account(ConnectorAccount {
            account_id: "primary".into(),
            allowed_scopes: BTreeSet::from(["contacts.read".into()]),
            connector_id: "contacts.fake".into(),
            credential_id: "fake-principal".into(),
            scope: account_scope.clone(),
        })
        .unwrap();

    assert!(
        vault
            .lease_for_connector(
                &account_scope,
                "mail.fake",
                "primary",
                &BTreeSet::from(["mail.read".into()])
            )
            .await
            .is_ok()
    );
    assert!(
        vault
            .lease_for_connector(
                &account_scope,
                "contacts.fake",
                "primary",
                &BTreeSet::from(["contacts.read".into()])
            )
            .await
            .is_ok()
    );
    assert!(
        vault
            .lease_for_connector(&account_scope, "calendar.fake", "primary", &BTreeSet::new())
            .await
            .is_err()
    );
}

#[test]
fn serialized_metadata_never_contains_secret_material() {
    let account = ConnectorAccount {
        account_id: "primary".into(),
        allowed_scopes: BTreeSet::new(),
        connector_id: "mail.fake".into(),
        credential_id: "fake-principal".into(),
        scope: scope("com.example.mail"),
    };
    let json = serde_json::to_string(&account).unwrap();
    assert!(json.contains("fake-principal"));
    assert!(!json.contains("mail.account.primary"));
    assert!(!json.contains("credential-value"));
}

#[tokio::test]
async fn credential_rotation_and_revocation_retry_durable_secret_cleanup() {
    let storage = Storage::connect("sqlite::memory:").await.unwrap();
    let metadata = SqliteCredentialMetadataStore::from_storage(&storage)
        .await
        .unwrap();
    let secrets = Arc::new(FailingDeleteStore::default());
    let account_scope = scope("com.example.oauth");
    let vault = CredentialVault::new_persistent(secrets.clone(), metadata.clone());
    vault
        .save_provider_credential(
            &account_scope,
            provider_credential("principal", "access.old", "refresh.old"),
            SecretMaterial::new("old-access").unwrap(),
            Some(SecretMaterial::new("old-refresh").unwrap()),
        )
        .await
        .unwrap();

    secrets.fail_delete.store(true, Ordering::SeqCst);
    vault
        .replace_provider_credential(
            &account_scope,
            provider_credential("principal", "access.new", "refresh.new"),
            SecretMaterial::new("new-access").unwrap(),
            Some(SecretMaterial::new("new-refresh").unwrap()),
        )
        .await
        .unwrap();
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
            .load(&account_scope, &SecretId::parse("access.old").unwrap())
            .await
            .unwrap()
            .is_some()
    );

    secrets.fail_delete.store(false, Ordering::SeqCst);
    let resumed = CredentialVault::new_persistent(secrets.clone(), metadata.clone());
    resumed
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
            .load(&account_scope, &SecretId::parse("access.old").unwrap())
            .await
            .unwrap()
            .is_none()
    );
    assert!(
        secrets
            .load(&account_scope, &SecretId::parse("access.new").unwrap())
            .await
            .unwrap()
            .is_some()
    );

    secrets.fail_delete.store(true, Ordering::SeqCst);
    assert!(
        resumed
            .revoke_provider_credential(&account_scope, "principal", Utc::now())
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
    secrets.fail_delete.store(false, Ordering::SeqCst);
    assert!(
        resumed
            .revoke_provider_credential(&account_scope, "principal", Utc::now())
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
            .load(&account_scope, &SecretId::parse("access.new").unwrap())
            .await
            .unwrap()
            .is_none()
    );
}
