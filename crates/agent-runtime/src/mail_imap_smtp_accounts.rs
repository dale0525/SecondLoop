use crate::credential::{
    ConnectorAccount, CredentialScope, CredentialVault, ProviderCredential, SecretId,
    SecretMaterial,
};
use crate::mail::*;
use crate::mail_attachments::MailAttachmentSource;
use crate::mail_imap_smtp::{ImapSmtpMailConfig, ImapSmtpMailConnector};
use crate::storage::Storage;
use async_trait::async_trait;
use chrono::Utc;
use sha2::{Digest, Sha256};
use sqlx::{Row, SqlitePool};
use std::collections::{BTreeMap, BTreeSet};
use std::sync::{Arc, RwLock};
use uuid::Uuid;

pub const IMAP_SMTP_CONNECTOR_ID: &str = "agentweave.connector.mail.imap-smtp";
pub const IMAP_SMTP_PROVIDER_ID: &str = "imap-smtp";

fn granted_scopes() -> BTreeSet<String> {
    BTreeSet::from([
        "mail.message.read".into(),
        "mail.message.organize".into(),
        "mail.message.send".into(),
    ])
}

#[derive(Clone)]
pub struct SqliteImapSmtpMailAccountStore {
    pool: SqlitePool,
}

impl SqliteImapSmtpMailAccountStore {
    pub async fn from_storage(storage: &Storage) -> anyhow::Result<Self> {
        let store = Self {
            pool: storage.pool().clone(),
        };
        sqlx::query(
            r#"CREATE TABLE IF NOT EXISTS imap_smtp_mail_accounts (
                app_id TEXT NOT NULL,
                tenant_id TEXT NOT NULL,
                user_id TEXT NOT NULL,
                account_id TEXT NOT NULL,
                config_json TEXT NOT NULL,
                updated_at TEXT NOT NULL,
                PRIMARY KEY(app_id, tenant_id, user_id, account_id)
            )"#,
        )
        .execute(&store.pool)
        .await?;
        Ok(store)
    }

    pub async fn list(&self, scope: &CredentialScope) -> anyhow::Result<Vec<ImapSmtpMailConfig>> {
        scope.validate()?;
        let rows = sqlx::query(
            "SELECT account_id, config_json FROM imap_smtp_mail_accounts WHERE app_id = ? AND tenant_id = ? AND user_id = ? ORDER BY account_id",
        )
        .bind(&scope.app_id)
        .bind(&scope.tenant_id)
        .bind(&scope.user_id)
        .fetch_all(&self.pool)
        .await?;
        rows.into_iter()
            .map(|row| config_from_row(scope, row))
            .collect()
    }

    pub async fn get(
        &self,
        scope: &CredentialScope,
        account_id: &str,
    ) -> anyhow::Result<Option<ImapSmtpMailConfig>> {
        validate_account_id(account_id)?;
        scope.validate()?;
        let row = sqlx::query(
            "SELECT account_id, config_json FROM imap_smtp_mail_accounts WHERE app_id = ? AND tenant_id = ? AND user_id = ? AND account_id = ?",
        )
        .bind(&scope.app_id)
        .bind(&scope.tenant_id)
        .bind(&scope.user_id)
        .bind(account_id)
        .fetch_optional(&self.pool)
        .await?;
        row.map(|row| config_from_row(scope, row)).transpose()
    }

    pub async fn upsert(&self, config: &ImapSmtpMailConfig) -> anyhow::Result<()> {
        config.validate()?;
        let json = serde_json::to_string(config)?;
        sqlx::query(
            r#"INSERT INTO imap_smtp_mail_accounts(app_id, tenant_id, user_id, account_id, config_json, updated_at)
               VALUES (?, ?, ?, ?, ?, ?)
               ON CONFLICT(app_id, tenant_id, user_id, account_id) DO UPDATE SET config_json = excluded.config_json, updated_at = excluded.updated_at"#,
        )
        .bind(&config.credential_scope.app_id)
        .bind(&config.credential_scope.tenant_id)
        .bind(&config.credential_scope.user_id)
        .bind(&config.account.id)
        .bind(json)
        .bind(Utc::now().to_rfc3339())
        .execute(&self.pool)
        .await?;
        Ok(())
    }

    pub async fn delete(&self, scope: &CredentialScope, account_id: &str) -> anyhow::Result<bool> {
        validate_account_id(account_id)?;
        scope.validate()?;
        let result = sqlx::query(
            "DELETE FROM imap_smtp_mail_accounts WHERE app_id = ? AND tenant_id = ? AND user_id = ? AND account_id = ?",
        )
        .bind(&scope.app_id)
        .bind(&scope.tenant_id)
        .bind(&scope.user_id)
        .bind(account_id)
        .execute(&self.pool)
        .await?;
        Ok(result.rows_affected() == 1)
    }
}

fn config_from_row(
    expected_scope: &CredentialScope,
    row: sqlx::sqlite::SqliteRow,
) -> anyhow::Result<ImapSmtpMailConfig> {
    let account_id: String = row.try_get("account_id")?;
    let config: ImapSmtpMailConfig = serde_json::from_str(row.try_get("config_json")?)?;
    config.validate()?;
    anyhow::ensure!(
        &config.credential_scope == expected_scope && config.account.id == account_id,
        "persisted mail account identity does not match its storage scope"
    );
    Ok(config)
}

#[derive(Clone, Default)]
pub struct ManagedImapSmtpMailConnector {
    connectors: Arc<RwLock<BTreeMap<String, Arc<ImapSmtpMailConnector>>>>,
    preview_accounts: Arc<RwLock<BTreeMap<String, String>>>,
}

impl ManagedImapSmtpMailConnector {
    pub fn new() -> Self {
        Self::default()
    }

    pub fn upsert_account(
        &self,
        config: ImapSmtpMailConfig,
        vault: Arc<CredentialVault>,
    ) -> anyhow::Result<bool> {
        self.upsert_account_with_attachment_source(config, vault, None)
    }

    pub fn upsert_account_with_attachment_source(
        &self,
        config: ImapSmtpMailConfig,
        vault: Arc<CredentialVault>,
        attachment_source: Option<Arc<dyn MailAttachmentSource>>,
    ) -> anyhow::Result<bool> {
        let account_id = config.account.id.clone();
        let mut connector = ImapSmtpMailConnector::new(config, vault)?;
        if let Some(source) = attachment_source {
            connector = connector.with_attachment_source(source);
        }
        let connector = Arc::new(connector);
        Ok(self.upsert_connector(account_id, connector))
    }

    fn upsert_connector(&self, account_id: String, connector: Arc<ImapSmtpMailConnector>) -> bool {
        self.connectors
            .write()
            .expect("managed mail connector lock poisoned")
            .insert(account_id, connector)
            .is_some()
    }

    pub fn remove_account(&self, account_id: &str) -> bool {
        let removed = self
            .connectors
            .write()
            .expect("managed mail connector lock poisoned")
            .remove(account_id)
            .is_some();
        if removed {
            self.preview_accounts
                .write()
                .expect("managed mail preview lock poisoned")
                .retain(|_, owner| owner != account_id);
        }
        removed
    }

    pub fn contains_account(&self, account_id: &str) -> bool {
        self.connectors
            .read()
            .expect("managed mail connector lock poisoned")
            .contains_key(account_id)
    }

    fn connector(&self, account_id: &str) -> MailResult<Arc<ImapSmtpMailConnector>> {
        self.connectors
            .read()
            .expect("managed mail connector lock poisoned")
            .get(account_id)
            .cloned()
            .ok_or_else(|| MailError::NotFound(account_id.to_string()))
    }
}

macro_rules! dispatch_request {
    ($self:ident, $request:ident, $method:ident) => {{
        let connector = $self.connector(&$request.account_id)?;
        connector.$method($request).await
    }};
}

#[async_trait]
impl MailConnector for ManagedImapSmtpMailConnector {
    async fn list_accounts(&self) -> MailResult<Vec<MailAccount>> {
        let connectors = self
            .connectors
            .read()
            .expect("managed mail connector lock poisoned")
            .values()
            .cloned()
            .collect::<Vec<_>>();
        let mut accounts = Vec::with_capacity(connectors.len());
        for connector in connectors {
            accounts.extend(connector.list_accounts().await?);
        }
        accounts.sort_by(|left, right| left.id.cmp(&right.id));
        Ok(accounts)
    }

    async fn account_status(&self, account_id: &str) -> MailResult<MailAccountStatus> {
        self.connector(account_id)?.account_status(account_id).await
    }

    async fn request_connect(
        &self,
        request: MailAccountActionRequest,
    ) -> MailResult<MailAccountStatus> {
        dispatch_request!(self, request, request_connect)
    }

    async fn disconnect(&self, request: MailAccountActionRequest) -> MailResult<MailAccountStatus> {
        dispatch_request!(self, request, disconnect)
    }

    async fn list_mailboxes(&self, account_id: &str) -> MailResult<Vec<Mailbox>> {
        self.connector(account_id)?.list_mailboxes(account_id).await
    }

    async fn list_threads(&self, request: ListThreadsRequest) -> MailResult<Page<MailThread>> {
        dispatch_request!(self, request, list_threads)
    }

    async fn get_thread(&self, request: GetThreadRequest) -> MailResult<MailThreadDetail> {
        dispatch_request!(self, request, get_thread)
    }

    async fn search_messages(
        &self,
        request: SearchMessagesRequest,
    ) -> MailResult<Page<MailMessageSummary>> {
        dispatch_request!(self, request, search_messages)
    }

    async fn get_message(&self, request: GetMessageRequest) -> MailResult<MailMessage> {
        dispatch_request!(self, request, get_message)
    }

    async fn read_body_part(&self, request: ReadBodyPartRequest) -> MailResult<BodyPartContent> {
        dispatch_request!(self, request, read_body_part)
    }

    async fn read_attachment(&self, request: ReadAttachmentRequest) -> MailResult<AttachmentChunk> {
        dispatch_request!(self, request, read_attachment)
    }

    async fn set_read_state(&self, request: SetReadStateRequest) -> MailResult<MailMessageSummary> {
        dispatch_request!(self, request, set_read_state)
    }

    async fn archive_message(
        &self,
        request: ArchiveMessageRequest,
    ) -> MailResult<MailMessageSummary> {
        dispatch_request!(self, request, archive_message)
    }

    async fn move_message(&self, request: MoveMessageRequest) -> MailResult<MailMessageSummary> {
        dispatch_request!(self, request, move_message)
    }

    async fn create_draft(&self, request: CreateDraftRequest) -> MailResult<MailDraft> {
        dispatch_request!(self, request, create_draft)
    }

    async fn create_reply_draft(&self, request: CreateReplyDraftRequest) -> MailResult<MailDraft> {
        dispatch_request!(self, request, create_reply_draft)
    }

    async fn create_forward_draft(
        &self,
        request: CreateForwardDraftRequest,
    ) -> MailResult<MailDraft> {
        dispatch_request!(self, request, create_forward_draft)
    }

    async fn get_draft(&self, request: GetDraftRequest) -> MailResult<MailDraft> {
        dispatch_request!(self, request, get_draft)
    }

    async fn update_draft(&self, request: UpdateDraftRequest) -> MailResult<MailDraft> {
        dispatch_request!(self, request, update_draft)
    }

    async fn delete_draft(&self, request: DeleteDraftRequest) -> MailResult<()> {
        dispatch_request!(self, request, delete_draft)
    }

    async fn preview_send(&self, request: PreviewSendRequest) -> MailResult<SendPreview> {
        let account_id = request.account_id.clone();
        let preview = self.connector(&account_id)?.preview_send(request).await?;
        self.preview_accounts
            .write()
            .expect("managed mail preview lock poisoned")
            .insert(preview.id.clone(), account_id);
        Ok(preview)
    }

    async fn send_approved(&self, request: ApprovedSendRequest) -> MailResult<DeliveryReceipt> {
        let account_id = self
            .preview_accounts
            .read()
            .expect("managed mail preview lock poisoned")
            .get(&request.preview_id)
            .cloned()
            .ok_or_else(|| MailError::NotFound(request.preview_id.clone()))?;
        self.connector(&account_id)?.send_approved(request).await
    }

    async fn delivery_status(&self, request: DeliveryStatusRequest) -> MailResult<DeliveryReceipt> {
        dispatch_request!(self, request, delivery_status)
    }
}

#[derive(Clone)]
pub struct ImapSmtpMailAccountManager {
    store: SqliteImapSmtpMailAccountStore,
    vault: Arc<CredentialVault>,
    connector: Arc<ManagedImapSmtpMailConnector>,
    attachment_source: Option<Arc<dyn MailAttachmentSource>>,
}

impl ImapSmtpMailAccountManager {
    pub fn new(
        store: SqliteImapSmtpMailAccountStore,
        vault: Arc<CredentialVault>,
        connector: Arc<ManagedImapSmtpMailConnector>,
    ) -> Self {
        Self {
            store,
            vault,
            connector,
            attachment_source: None,
        }
    }

    pub fn with_attachment_source(mut self, source: Arc<dyn MailAttachmentSource>) -> Self {
        self.attachment_source = Some(source);
        self
    }

    pub async fn load_accounts(
        &self,
        scope: &CredentialScope,
    ) -> anyhow::Result<Vec<ImapSmtpMailConfig>> {
        let configs = self.store.list(scope).await?;
        let mut prepared = Vec::with_capacity(configs.len());
        for config in &configs {
            let account = self
                .vault
                .get_connector_account(scope, IMAP_SMTP_CONNECTOR_ID, &config.account.id)
                .await?
                .ok_or_else(|| {
                    anyhow::anyhow!(
                        "credential metadata is unavailable for mail account {}",
                        config.account.id
                    )
                })?;
            anyhow::ensure!(
                account.connector_id == IMAP_SMTP_CONNECTOR_ID
                    && account.credential_id == config.credential_secret_id.as_str(),
                "mail account credential metadata is inconsistent"
            );
            let credential = self
                .vault
                .get_provider_credential(scope, &account.credential_id)
                .await?
                .ok_or_else(|| {
                    anyhow::anyhow!(
                        "provider credential is unavailable for mail account {}",
                        config.account.id
                    )
                })?;
            anyhow::ensure!(
                credential.provider_id == IMAP_SMTP_PROVIDER_ID
                    && credential.access_secret_id == config.credential_secret_id,
                "mail account provider credential metadata is inconsistent"
            );
            anyhow::ensure!(
                self.vault
                    .connector_credential_configured(
                        scope,
                        IMAP_SMTP_CONNECTOR_ID,
                        &config.account.id,
                    )
                    .await?,
                "mail account credential is unavailable"
            );
            let mut connector = ImapSmtpMailConnector::new(config.clone(), self.vault.clone())?;
            if let Some(source) = &self.attachment_source {
                connector = connector.with_attachment_source(source.clone());
            }
            prepared.push((config.account.id.clone(), Arc::new(connector)));
        }
        for (account_id, connector) in prepared {
            self.connector.upsert_connector(account_id, connector);
        }
        Ok(configs)
    }

    pub async fn configure(
        &self,
        mut config: ImapSmtpMailConfig,
        password: SecretMaterial,
    ) -> anyhow::Result<ImapSmtpMailConfig> {
        config.credential_scope.validate()?;
        validate_account_id(&config.account.id)?;
        config.credential_secret_id = mail_secret_id(&config.credential_scope, &config.account.id)?;
        config.validate()?;
        let mut prepared = ImapSmtpMailConnector::new(config.clone(), self.vault.clone())?;
        if let Some(source) = &self.attachment_source {
            prepared = prepared.with_attachment_source(source.clone());
        }
        let prepared = Arc::new(prepared);

        let previous = self
            .store
            .get(&config.credential_scope, &config.account.id)
            .await?;
        let previous_binding = self
            .vault
            .get_connector_account(
                &config.credential_scope,
                IMAP_SMTP_CONNECTOR_ID,
                &config.account.id,
            )
            .await?;
        self.store.upsert(&config).await?;
        let credential_id = config.credential_secret_id.as_str().to_string();
        let credential = ProviderCredential {
            credential_id: credential_id.clone(),
            provider_id: IMAP_SMTP_PROVIDER_ID.into(),
            provider_subject: config.account.id.clone(),
            access_secret_id: config.credential_secret_id.clone(),
            refresh_secret_id: None,
            granted_scopes: granted_scopes(),
            expires_at: None,
            revoked_at: None,
        };
        if let Err(error) = self
            .vault
            .save_provider_credential(&config.credential_scope, credential, password, None)
            .await
        {
            compensate_config(&self.store, &config, previous).await?;
            return Err(error);
        }
        let account = ConnectorAccount {
            account_id: config.account.id.clone(),
            connector_id: IMAP_SMTP_CONNECTOR_ID.into(),
            credential_id: credential_id.clone(),
            scope: config.credential_scope.clone(),
            allowed_scopes: granted_scopes(),
        };
        if let Err(error) = self.vault.register_account_persistent(account).await {
            let credential_cleanup = self
                .vault
                .revoke_provider_credential(&config.credential_scope, &credential_id, Utc::now())
                .await;
            let compensation = compensate_config(&self.store, &config, previous).await;
            return match compensation {
                Ok(()) if credential_cleanup.is_ok() => Err(error),
                Ok(()) => Err(error.context("mail credential cleanup remains pending")),
                Err(compensation) => Err(error.context(format!(
                    "mail configuration compensation failed: {compensation:#}"
                ))),
            };
        }
        if let Some(previous) = previous_binding
            && previous.credential_id != credential_id
            && let Err(error) = self
                .vault
                .revoke_provider_credential(
                    &config.credential_scope,
                    &previous.credential_id,
                    Utc::now(),
                )
                .await
        {
            tracing::warn!(error = %error, "retired Mail credential cleanup remains pending");
        }
        self.connector
            .upsert_connector(config.account.id.clone(), prepared);
        Ok(config)
    }

    pub async fn delete(&self, scope: &CredentialScope, account_id: &str) -> anyhow::Result<bool> {
        scope.validate()?;
        validate_account_id(account_id)?;
        let previous = self.store.get(scope, account_id).await?;
        let previous_binding = self
            .vault
            .get_connector_account(scope, IMAP_SMTP_CONNECTOR_ID, account_id)
            .await?;
        let config_deleted = self.store.delete(scope, account_id).await?;
        let connector_deleted = self.connector.remove_account(account_id);
        let credential_deleted = match self
            .vault
            .remove_connector_account(scope, IMAP_SMTP_CONNECTOR_ID, account_id)
            .await
        {
            Ok(Some((credential_id, remaining))) => {
                if remaining == 0
                    && let Err(error) = self
                        .vault
                        .revoke_provider_credential(scope, &credential_id, Utc::now())
                        .await
                {
                    let revoked = self
                        .vault
                        .get_provider_credential(scope, &credential_id)
                        .await?
                        .is_some_and(|credential| credential.revoked_at.is_some());
                    if revoked {
                        tracing::warn!(error = %error, "deleted Mail credential cleanup remains pending");
                    } else {
                        if let Some(binding) = previous_binding.clone() {
                            self.vault.register_account_persistent(binding).await?;
                        }
                        compensate_deleted_account(
                            &self.store,
                            &self.connector,
                            self.vault.clone(),
                            previous,
                            connector_deleted,
                            self.attachment_source.clone(),
                        )
                        .await?;
                        return Err(error);
                    }
                }
                true
            }
            Ok(None) => false,
            Err(error) => {
                let compensation = compensate_deleted_account(
                    &self.store,
                    &self.connector,
                    self.vault.clone(),
                    previous,
                    connector_deleted,
                    self.attachment_source.clone(),
                )
                .await;
                return match compensation {
                    Ok(()) => Err(error),
                    Err(compensation) => Err(error.context(format!(
                        "mail deletion compensation failed: {compensation:#}"
                    ))),
                };
            }
        };
        Ok(config_deleted || connector_deleted || credential_deleted)
    }

    pub async fn list(&self, scope: &CredentialScope) -> anyhow::Result<Vec<ImapSmtpMailConfig>> {
        self.store.list(scope).await
    }

    pub async fn get(
        &self,
        scope: &CredentialScope,
        account_id: &str,
    ) -> anyhow::Result<Option<ImapSmtpMailConfig>> {
        self.store.get(scope, account_id).await
    }

    pub async fn credential_configured(
        &self,
        scope: &CredentialScope,
        account_id: &str,
    ) -> anyhow::Result<bool> {
        self.vault
            .connector_credential_configured(scope, IMAP_SMTP_CONNECTOR_ID, account_id)
            .await
    }
}

pub fn mail_secret_id(scope: &CredentialScope, account_id: &str) -> anyhow::Result<SecretId> {
    scope.validate()?;
    validate_account_id(account_id)?;
    let identity = serde_json::to_vec(&(
        "agentweave.mail.imap-smtp.v1",
        &scope.app_id,
        &scope.tenant_id,
        &scope.user_id,
        account_id,
    ))?;
    SecretId::parse(&format!(
        "mail.imap-smtp.{}.{}",
        hex::encode(Sha256::digest(identity)),
        Uuid::new_v4()
    ))
}

async fn compensate_config(
    store: &SqliteImapSmtpMailAccountStore,
    attempted: &ImapSmtpMailConfig,
    previous: Option<ImapSmtpMailConfig>,
) -> anyhow::Result<()> {
    match previous {
        Some(previous) => store.upsert(&previous).await,
        None => store
            .delete(&attempted.credential_scope, &attempted.account.id)
            .await
            .map(|_| ()),
    }
}

async fn compensate_deleted_account(
    store: &SqliteImapSmtpMailAccountStore,
    connector: &ManagedImapSmtpMailConnector,
    vault: Arc<CredentialVault>,
    previous: Option<ImapSmtpMailConfig>,
    connector_deleted: bool,
    attachment_source: Option<Arc<dyn MailAttachmentSource>>,
) -> anyhow::Result<()> {
    if let Some(config) = previous {
        store.upsert(&config).await?;
        if connector_deleted {
            connector.upsert_account_with_attachment_source(config, vault, attachment_source)?;
        }
    }
    Ok(())
}

fn validate_account_id(account_id: &str) -> anyhow::Result<()> {
    anyhow::ensure!(!account_id.trim().is_empty(), "account id is required");
    anyhow::ensure!(account_id.len() <= 255, "account id is too long");
    Ok(())
}

#[cfg(test)]
#[path = "mail_imap_smtp_accounts_tests.rs"]
mod tests;
