use crate::attachments::{AttachmentError, AttachmentScope, SqliteAttachmentStore};
use crate::mail::{DraftAttachment, MailError, MailResult};
use async_trait::async_trait;
use sha2::{Digest, Sha256};

pub struct ResolvedDraftAttachment {
    pub metadata: DraftAttachment,
    pub data: Vec<u8>,
}

#[async_trait]
pub trait MailAttachmentSource: Send + Sync {
    async fn resolve(
        &self,
        account_id: &str,
        attachment: &DraftAttachment,
    ) -> MailResult<ResolvedDraftAttachment>;
}

#[derive(Clone)]
pub struct StoredMailAttachmentSource {
    store: SqliteAttachmentStore,
    scope: AttachmentScope,
}

impl StoredMailAttachmentSource {
    pub fn new(store: SqliteAttachmentStore, scope: AttachmentScope) -> Self {
        Self { store, scope }
    }
}

#[async_trait]
impl MailAttachmentSource for StoredMailAttachmentSource {
    async fn resolve(
        &self,
        account_id: &str,
        attachment: &DraftAttachment,
    ) -> MailResult<ResolvedDraftAttachment> {
        if account_id.trim().is_empty() {
            return Err(MailError::InvalidRequest(
                "Mail attachment account is required".into(),
            ));
        }
        attachment.validate()?;
        let attachment_id = attachment.host_attachment_id.as_deref().ok_or_else(|| {
            MailError::Unsupported("attachment is not backed by the Host Attachment Store".into())
        })?;
        let metadata = self
            .store
            .get(&self.scope, attachment_id)
            .await
            .map_err(mail_attachment_error)?
            .ok_or_else(|| MailError::NotFound("outgoing attachment".into()))?;
        if metadata.file_name != attachment.file_name
            || metadata.mime_type != attachment.mime_type
            || metadata.size_bytes != attachment.size_bytes
            || attachment.sha256.as_deref() != Some(&metadata.sha256)
        {
            return Err(MailError::InvalidRequest(
                "outgoing attachment metadata changed after draft creation".into(),
            ));
        }
        let data = self
            .store
            .content(&self.scope, attachment_id)
            .await
            .map_err(mail_attachment_error)?;
        let data_sha256 = hex::encode(Sha256::digest(&data));
        if data.len() as u64 != metadata.size_bytes || data_sha256 != metadata.sha256 {
            return Err(MailError::Connector(
                "outgoing attachment integrity check failed".into(),
            ));
        }
        Ok(ResolvedDraftAttachment {
            metadata: attachment.clone(),
            data,
        })
    }
}

fn mail_attachment_error(error: AttachmentError) -> MailError {
    match error {
        AttachmentError::NotFound => MailError::NotFound("outgoing attachment".into()),
        AttachmentError::InvalidRequest(_) => {
            MailError::InvalidRequest("outgoing attachment reference is invalid".into())
        }
        AttachmentError::TooLarge
        | AttachmentError::IdempotencyConflict
        | AttachmentError::Unavailable => {
            MailError::Connector("Host Attachment Store is unavailable".into())
        }
    }
}

#[cfg(test)]
#[path = "mail_attachments_tests.rs"]
mod tests;
