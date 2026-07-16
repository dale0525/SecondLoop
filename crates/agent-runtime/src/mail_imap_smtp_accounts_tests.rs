use super::*;
use crate::credential::{InMemorySecretStore, SecretStore};
use crate::credential_sqlite::SqliteCredentialMetadataStore;
use crate::mail_imap_smtp::MailTlsMode;
use std::sync::atomic::{AtomicBool, Ordering};

struct DeleteFailingSecretStore {
    inner: InMemorySecretStore,
    fail_delete: AtomicBool,
}

#[async_trait]
impl SecretStore for DeleteFailingSecretStore {
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

fn scope(app_id: &str) -> CredentialScope {
    CredentialScope {
        app_id: app_id.into(),
        tenant_id: "local".into(),
        user_id: "user".into(),
    }
}

fn config(account_id: &str, scope: CredentialScope) -> ImapSmtpMailConfig {
    ImapSmtpMailConfig {
        account: MailAccount {
            id: account_id.into(),
            display_name: format!("Account {account_id}"),
            primary_address: MailAddress {
                name: None,
                address: format!("{account_id}@example.test"),
            },
            addresses: vec![],
            provider_reference: Some(ProviderReference {
                provider: IMAP_SMTP_PROVIDER_ID.into(),
                id: account_id.into(),
            }),
        },
        credential_scope: scope,
        credential_secret_id: SecretId::parse("caller.supplied.is.replaced").unwrap(),
        imap_host: "127.0.0.1".into(),
        imap_port: 1143,
        imap_tls: MailTlsMode::None,
        smtp_host: "127.0.0.1".into(),
        smtp_port: 1025,
        smtp_tls: MailTlsMode::None,
        username: format!("{account_id}@example.test"),
        archive_mailbox: Some("Archive".into()),
        sent_mailbox: Some("Sent".into()),
        drafts_mailbox: Some("Drafts".into()),
        trash_mailbox: Some("Trash".into()),
        allow_insecure_localhost: true,
        connect_timeout_seconds: 2,
        operation_timeout_seconds: 3,
    }
}

fn provider_credential(config: &ImapSmtpMailConfig) -> ProviderCredential {
    ProviderCredential {
        credential_id: config.credential_secret_id.as_str().to_string(),
        provider_id: IMAP_SMTP_PROVIDER_ID.into(),
        provider_subject: config.account.id.clone(),
        access_secret_id: config.credential_secret_id.clone(),
        refresh_secret_id: None,
        granted_scopes: granted_scopes(),
        expires_at: None,
        revoked_at: None,
    }
}

fn draft_content(subject: &str) -> DraftContent {
    DraftContent {
        to: vec![MailAddress {
            name: None,
            address: "recipient@example.test".into(),
        }],
        cc: vec![],
        bcc: vec![],
        subject: subject.into(),
        body: OutgoingBody {
            plain_text: "hello".into(),
            html: None,
        },
        attachments: vec![],
        reply_context: None,
        forward_context: None,
    }
}

async fn manager(
    storage: &Storage,
    secrets: Arc<InMemorySecretStore>,
) -> (
    ImapSmtpMailAccountManager,
    Arc<ManagedImapSmtpMailConnector>,
    Arc<CredentialVault>,
) {
    manager_with_store(storage, secrets).await
}

async fn manager_with_store(
    storage: &Storage,
    secrets: Arc<dyn SecretStore>,
) -> (
    ImapSmtpMailAccountManager,
    Arc<ManagedImapSmtpMailConnector>,
    Arc<CredentialVault>,
) {
    let metadata = SqliteCredentialMetadataStore::from_storage(storage)
        .await
        .unwrap();
    let vault = Arc::new(CredentialVault::new_persistent(secrets, metadata));
    let connector = Arc::new(ManagedImapSmtpMailConnector::new());
    let store = SqliteImapSmtpMailAccountStore::from_storage(storage)
        .await
        .unwrap();
    (
        ImapSmtpMailAccountManager::new(store, vault.clone(), connector.clone()),
        connector,
        vault,
    )
}

#[tokio::test]
async fn store_is_scope_bound_and_persists_only_non_secret_config() {
    let storage = Storage::connect("sqlite::memory:").await.unwrap();
    let store = SqliteImapSmtpMailAccountStore::from_storage(&storage)
        .await
        .unwrap();
    let value = config("primary", scope("app-a"));
    store.upsert(&value).await.unwrap();

    assert_eq!(store.list(&scope("app-a")).await.unwrap(), vec![value]);
    assert!(store.list(&scope("app-b")).await.unwrap().is_empty());
    let persisted: String = sqlx::query_scalar(
        "SELECT config_json FROM imap_smtp_mail_accounts WHERE account_id = 'primary'",
    )
    .fetch_one(&store.pool)
    .await
    .unwrap();
    assert!(!persisted.contains("password-value"));
    assert!(!persisted.to_ascii_lowercase().contains("password\":"));
}

#[tokio::test]
async fn manager_configures_updates_reloads_deletes_and_dispatches_by_account() {
    let storage = Storage::connect("sqlite::memory:").await.unwrap();
    let secrets = Arc::new(InMemorySecretStore::default());
    let (manager, connector, vault) = manager(&storage, secrets.clone()).await;
    let account_scope = scope("app-a");

    let primary = manager
        .configure(
            config("primary", account_scope.clone()),
            SecretMaterial::new("password-value").unwrap(),
        )
        .await
        .unwrap();
    manager
        .configure(
            config("secondary", account_scope.clone()),
            SecretMaterial::new("secondary-password").unwrap(),
        )
        .await
        .unwrap();
    assert_ne!(
        primary.credential_secret_id.as_str(),
        "caller.supplied.is.replaced"
    );
    let account = vault
        .get_connector_account(&account_scope, IMAP_SMTP_CONNECTOR_ID, "primary")
        .await
        .unwrap()
        .unwrap();
    assert_eq!(account.connector_id, IMAP_SMTP_CONNECTOR_ID);
    assert_eq!(account.allowed_scopes, granted_scopes());
    assert!(
        manager
            .credential_configured(&account_scope, "primary")
            .await
            .unwrap()
    );

    let draft = connector
        .create_draft(CreateDraftRequest {
            account_id: "secondary".into(),
            content: draft_content("secondary draft"),
        })
        .await
        .unwrap();
    assert_eq!(draft.account_id, "secondary");
    assert!(matches!(
        connector.account_status("missing").await,
        Err(MailError::NotFound(value)) if value == "missing"
    ));

    let mut updated = config("primary", account_scope.clone());
    updated.username = "updated@example.test".into();
    manager
        .configure(updated, SecretMaterial::new("new-password").unwrap())
        .await
        .unwrap();
    assert_eq!(
        manager
            .get(&account_scope, "primary")
            .await
            .unwrap()
            .unwrap()
            .username,
        "updated@example.test"
    );
    let leased = vault
        .lease_for_connector(
            &account_scope,
            IMAP_SMTP_CONNECTOR_ID,
            "primary",
            &BTreeSet::from(["mail.message.read".into()]),
        )
        .await
        .unwrap();
    assert_eq!(leased.expose_bytes(), b"new-password");

    let resumed_connector = Arc::new(ManagedImapSmtpMailConnector::new());
    let resumed_store = SqliteImapSmtpMailAccountStore::from_storage(&storage)
        .await
        .unwrap();
    let resumed =
        ImapSmtpMailAccountManager::new(resumed_store, vault.clone(), resumed_connector.clone());
    assert_eq!(
        resumed.load_accounts(&account_scope).await.unwrap().len(),
        2
    );
    assert!(resumed_connector.contains_account("primary"));

    assert!(resumed.delete(&account_scope, "primary").await.unwrap());
    assert!(!resumed_connector.contains_account("primary"));
    assert!(
        secrets
            .load(&account_scope, &primary.credential_secret_id)
            .await
            .unwrap()
            .is_none()
    );
    assert!(
        !resumed
            .credential_configured(&account_scope, "primary")
            .await
            .unwrap()
    );
    assert!(!resumed.delete(&account_scope, "primary").await.unwrap());
    assert!(resumed_connector.contains_account("secondary"));
}

#[tokio::test]
async fn configure_compensates_config_and_secret_when_metadata_fails() {
    let storage = Storage::connect("sqlite::memory:").await.unwrap();
    let secrets = Arc::new(InMemorySecretStore::default());
    let (manager, connector, _vault) = manager(&storage, secrets.clone()).await;
    let account_scope = scope("app-a");
    sqlx::query("DROP TABLE connector_accounts")
        .execute(storage.pool())
        .await
        .unwrap();

    let error = manager
        .configure(
            config("primary", account_scope.clone()),
            SecretMaterial::new("must-be-removed").unwrap(),
        )
        .await
        .unwrap_err();
    assert!(error.to_string().contains("connector_accounts"));
    assert!(
        manager
            .get(&account_scope, "primary")
            .await
            .unwrap()
            .is_none()
    );
    assert!(!connector.contains_account("primary"));
    let credential_count: i64 = sqlx::query_scalar(
            "SELECT COUNT(*) FROM credential_records WHERE app_id = ? AND tenant_id = ? AND user_id = ? AND revoked_at IS NULL",
        )
        .bind(&account_scope.app_id)
        .bind(&account_scope.tenant_id)
        .bind(&account_scope.user_id)
        .fetch_one(storage.pool())
        .await
        .unwrap();
    assert_eq!(credential_count, 0);
}

#[tokio::test]
async fn delete_commits_disconnect_when_secret_cleanup_needs_retry() {
    let storage = Storage::connect("sqlite::memory:").await.unwrap();
    let secrets = Arc::new(DeleteFailingSecretStore {
        inner: InMemorySecretStore::default(),
        fail_delete: AtomicBool::new(false),
    });
    let (manager, connector, vault) = manager_with_store(&storage, secrets.clone()).await;
    let account_scope = scope("app-a");
    manager
        .configure(
            config("primary", account_scope.clone()),
            SecretMaterial::new("password-value").unwrap(),
        )
        .await
        .unwrap();
    secrets.fail_delete.store(true, Ordering::SeqCst);

    assert!(manager.delete(&account_scope, "primary").await.unwrap());
    assert!(
        manager
            .get(&account_scope, "primary")
            .await
            .unwrap()
            .is_none()
    );
    assert!(!connector.contains_account("primary"));
    assert!(
        !vault
            .connector_credential_configured(&account_scope, IMAP_SMTP_CONNECTOR_ID, "primary",)
            .await
            .unwrap()
    );
}

#[tokio::test]
async fn startup_loading_is_fail_closed_when_any_secret_is_missing() {
    let storage = Storage::connect("sqlite::memory:").await.unwrap();
    let secrets = Arc::new(InMemorySecretStore::default());
    let (manager, connector, vault) = manager(&storage, secrets).await;
    let account_scope = scope("app-a");
    let mut valid = config("valid", account_scope.clone());
    valid.credential_secret_id = mail_secret_id(&account_scope, "valid").unwrap();
    let mut missing = config("missing", account_scope.clone());
    missing.credential_secret_id = mail_secret_id(&account_scope, "missing").unwrap();
    manager.store.upsert(&valid).await.unwrap();
    manager.store.upsert(&missing).await.unwrap();
    let valid_credential = provider_credential(&valid);
    vault
        .save_provider_credential(
            &account_scope,
            valid_credential.clone(),
            SecretMaterial::new("present").unwrap(),
            None,
        )
        .await
        .unwrap();
    vault
        .register_account_persistent(ConnectorAccount {
            account_id: "valid".into(),
            connector_id: IMAP_SMTP_CONNECTOR_ID.into(),
            credential_id: valid_credential.credential_id,
            scope: account_scope.clone(),
            allowed_scopes: granted_scopes(),
        })
        .await
        .unwrap();
    let missing_credential = provider_credential(&missing);
    vault
        .register_provider_credential_persistent(&account_scope, missing_credential.clone())
        .await
        .unwrap();
    vault
        .register_account_persistent(ConnectorAccount {
            account_id: "missing".into(),
            connector_id: IMAP_SMTP_CONNECTOR_ID.into(),
            credential_id: missing_credential.credential_id,
            scope: account_scope.clone(),
            allowed_scopes: granted_scopes(),
        })
        .await
        .unwrap();

    assert!(
        manager
            .load_accounts(&account_scope)
            .await
            .unwrap_err()
            .to_string()
            .contains("unavailable")
    );
    assert!(!connector.contains_account("valid"));
    assert!(!connector.contains_account("missing"));
}

#[tokio::test]
async fn startup_loading_rejects_connector_metadata_mismatch() {
    let storage = Storage::connect("sqlite::memory:").await.unwrap();
    let (manager, connector, vault) =
        manager(&storage, Arc::new(InMemorySecretStore::default())).await;
    let account_scope = scope("app-a");
    let mut value = config("primary", account_scope.clone());
    value.credential_secret_id = mail_secret_id(&account_scope, "primary").unwrap();
    manager.store.upsert(&value).await.unwrap();
    let credential = provider_credential(&value);
    vault
        .save_provider_credential(
            &account_scope,
            credential.clone(),
            SecretMaterial::new("present").unwrap(),
            None,
        )
        .await
        .unwrap();
    vault
        .register_account_persistent(ConnectorAccount {
            account_id: "primary".into(),
            connector_id: "different-connector".into(),
            credential_id: credential.credential_id,
            scope: account_scope.clone(),
            allowed_scopes: granted_scopes(),
        })
        .await
        .unwrap();

    let error = manager.load_accounts(&account_scope).await.unwrap_err();
    assert!(error.to_string().contains("unavailable"));
    assert!(!connector.contains_account("primary"));
}
