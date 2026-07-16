use async_trait::async_trait;
use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};

pub const MAX_PAGE_SIZE: u16 = 100;
pub const MAX_SEARCH_TEXT_BYTES: usize = 2_048;
pub const MAX_BODY_CHUNK_BYTES: u32 = 256 * 1_024;
pub const MAX_ATTACHMENT_CHUNK_BYTES: u32 = 256 * 1_024;
pub const MAX_OUTGOING_BODY_BYTES: usize = 2 * 1_024 * 1_024;
pub const MAX_RECIPIENTS: usize = 200;
pub const MAX_DRAFT_ATTACHMENTS: usize = 20;
pub const MAX_DRAFT_ATTACHMENT_BYTES: u64 = 16 * 1024 * 1024;
pub const MAX_DRAFT_ATTACHMENTS_TOTAL_BYTES: u64 = 32 * 1024 * 1024;

pub type MailResult<T> = Result<T, MailError>;

#[derive(Clone, Debug, thiserror::Error, PartialEq, Eq)]
pub enum MailError {
    #[error("mail resource not found: {0}")]
    NotFound(String),
    #[error("invalid mail request: {0}")]
    InvalidRequest(String),
    #[error("mail request exceeded bound '{bound}' with value {actual}; maximum is {maximum}")]
    BoundExceeded {
        bound: &'static str,
        actual: usize,
        maximum: usize,
    },
    #[error("draft revision conflict: expected {expected}, actual {actual}")]
    RevisionConflict { expected: u64, actual: u64 },
    #[error("mail approval is missing or does not match the requested operation")]
    ApprovalMismatch,
    #[error("mail idempotency key was reused for different content")]
    IdempotencyConflict,
    #[error("delivery outcome is uncertain; reconcile outbox item {outbox_id} before retrying")]
    ReconciliationRequired { outbox_id: String },
    #[error("mail operation is unsupported: {0}")]
    Unsupported(String),
    #[error("mail connector failed: {0}")]
    #[allow(dead_code)]
    Connector(String),
}

#[derive(Clone, Debug, Deserialize, Serialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct ProviderReference {
    pub provider: String,
    pub id: String,
}

#[derive(Clone, Debug, Deserialize, Serialize, PartialEq, Eq, Hash)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct MailAddress {
    pub name: Option<String>,
    pub address: String,
}

impl MailAddress {
    pub fn normalized(&self) -> String {
        self.address.trim().to_ascii_lowercase()
    }
}

#[derive(Clone, Debug, Deserialize, Serialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct MailAccount {
    pub id: String,
    pub display_name: String,
    pub primary_address: MailAddress,
    pub addresses: Vec<MailAddress>,
    pub provider_reference: Option<ProviderReference>,
}

#[derive(Clone, Copy, Debug, Deserialize, Serialize, PartialEq, Eq)]
#[serde(rename_all = "snake_case")]
pub enum MailAccountState {
    Connected,
    AuthenticationRequired,
    Unavailable,
}

#[derive(Clone, Debug, Deserialize, Serialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct MailAccountStatus {
    pub account: MailAccount,
    pub state: MailAccountState,
    pub detail: Option<String>,
}

#[derive(Clone, Debug, Deserialize, Serialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct MailAccountActionRequest {
    pub account_id: String,
}

#[derive(Clone, Copy, Debug, Deserialize, Serialize, PartialEq, Eq)]
#[serde(rename_all = "snake_case")]
pub enum MailboxRole {
    Inbox,
    Sent,
    Drafts,
    Archive,
    Trash,
    Junk,
    Custom,
}

#[derive(Clone, Debug, Deserialize, Serialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct Mailbox {
    pub id: String,
    pub account_id: String,
    pub name: String,
    pub role: MailboxRole,
    pub provider_reference: Option<ProviderReference>,
}

#[derive(Clone, Copy, Debug, Deserialize, Serialize, PartialEq, Eq)]
#[serde(rename_all = "snake_case")]
pub enum BodyPartTrust {
    PlainText,
    UntrustedHtml,
}

#[derive(Clone, Copy, Debug, Deserialize, Serialize, PartialEq, Eq)]
#[serde(rename_all = "snake_case")]
pub enum BodyRepresentation {
    Original,
    SanitizedPlainFallback,
}

#[derive(Clone, Copy, Debug, Deserialize, Serialize, PartialEq, Eq)]
#[serde(rename_all = "snake_case")]
pub enum ContentDisposition {
    Inline,
    Attachment,
}

#[derive(Clone, Debug, Deserialize, Serialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct MailBodyPart {
    pub id: String,
    pub mime_type: String,
    pub charset: Option<String>,
    pub size_bytes: u64,
    pub disposition: Option<ContentDisposition>,
    pub content_id: Option<String>,
    pub trust: BodyPartTrust,
    pub has_sanitized_plain_fallback: bool,
}

#[derive(Clone, Debug, Deserialize, Serialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct AttachmentMetadata {
    pub id: String,
    pub file_name: String,
    pub mime_type: String,
    pub size_bytes: u64,
    pub disposition: ContentDisposition,
    pub content_id: Option<String>,
    pub provider_reference: Option<ProviderReference>,
}

#[derive(Clone, Debug, Deserialize, Serialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct MailMessageSummary {
    pub id: String,
    pub account_id: String,
    pub thread_id: Option<String>,
    pub internet_message_id: String,
    pub from: MailAddress,
    pub to: Vec<MailAddress>,
    pub subject: String,
    pub sent_at: DateTime<Utc>,
    pub is_read: bool,
    pub has_attachments: bool,
    pub mailbox_ids: Vec<String>,
    pub provider_reference: Option<ProviderReference>,
}

#[derive(Clone, Debug, Deserialize, Serialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct MailMessage {
    pub summary: MailMessageSummary,
    pub reply_to: Vec<MailAddress>,
    pub cc: Vec<MailAddress>,
    pub bcc: Vec<MailAddress>,
    pub in_reply_to: Option<String>,
    pub references: Vec<String>,
    pub body_parts: Vec<MailBodyPart>,
    pub attachments: Vec<AttachmentMetadata>,
}

#[derive(Clone, Debug, Deserialize, Serialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct MailThread {
    pub id: String,
    pub account_id: String,
    pub subject: String,
    pub message_ids: Vec<String>,
    pub participants: Vec<MailAddress>,
    pub last_message_at: DateTime<Utc>,
    pub unread_count: u32,
    pub provider_reference: Option<ProviderReference>,
}

#[derive(Clone, Debug, Deserialize, Serialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct PageRequest {
    pub cursor: Option<String>,
    pub limit: u16,
}

impl PageRequest {
    pub fn validate(&self) -> MailResult<()> {
        if self.limit == 0 || self.limit > MAX_PAGE_SIZE {
            return Err(MailError::BoundExceeded {
                bound: "page.limit",
                actual: self.limit as usize,
                maximum: MAX_PAGE_SIZE as usize,
            });
        }
        if self.cursor.as_ref().is_some_and(|value| value.len() > 256) {
            return Err(MailError::BoundExceeded {
                bound: "page.cursor",
                actual: self.cursor.as_ref().map_or(0, String::len),
                maximum: 256,
            });
        }
        Ok(())
    }
}

impl Default for PageRequest {
    fn default() -> Self {
        Self {
            cursor: None,
            limit: 50,
        }
    }
}

#[derive(Clone, Debug, Deserialize, Serialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct Page<T> {
    pub items: Vec<T>,
    pub next_cursor: Option<String>,
}

#[derive(Clone, Debug, Default, Deserialize, Serialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct MailSearch {
    pub text: Option<String>,
    pub from: Option<String>,
    pub to: Option<String>,
    pub subject: Option<String>,
    pub after: Option<DateTime<Utc>>,
    pub before: Option<DateTime<Utc>>,
    pub has_attachment: Option<bool>,
    pub is_read: Option<bool>,
}

impl MailSearch {
    pub fn validate(&self) -> MailResult<()> {
        let size = [
            self.text.as_deref(),
            self.from.as_deref(),
            self.to.as_deref(),
            self.subject.as_deref(),
        ]
        .into_iter()
        .flatten()
        .map(str::len)
        .sum::<usize>();
        if size > MAX_SEARCH_TEXT_BYTES {
            return Err(MailError::BoundExceeded {
                bound: "search.text",
                actual: size,
                maximum: MAX_SEARCH_TEXT_BYTES,
            });
        }
        if self
            .after
            .zip(self.before)
            .is_some_and(|(after, before)| after > before)
        {
            return Err(MailError::InvalidRequest(
                "search.after must not be later than search.before".into(),
            ));
        }
        Ok(())
    }
}

#[derive(Clone, Debug, Deserialize, Serialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct ListThreadsRequest {
    pub account_id: String,
    pub mailbox_id: Option<String>,
    pub page: PageRequest,
}

#[derive(Clone, Debug, Deserialize, Serialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct GetThreadRequest {
    pub account_id: String,
    pub thread_id: String,
}

#[derive(Clone, Debug, Deserialize, Serialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct MailThreadDetail {
    pub thread: MailThread,
    pub messages: Vec<MailMessage>,
}

#[derive(Clone, Debug, Deserialize, Serialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct SearchMessagesRequest {
    pub account_id: String,
    pub mailbox_id: Option<String>,
    pub search: MailSearch,
    pub page: PageRequest,
}

#[derive(Clone, Debug, Deserialize, Serialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct GetMessageRequest {
    pub account_id: String,
    pub message_id: String,
}

#[derive(Clone, Debug, Deserialize, Serialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct ReadBodyPartRequest {
    pub account_id: String,
    pub message_id: String,
    pub part_id: String,
    pub representation: BodyRepresentation,
    pub offset: u64,
    pub max_bytes: u32,
}

impl ReadBodyPartRequest {
    pub fn validate(&self) -> MailResult<()> {
        validate_chunk_bound("body.maxBytes", self.max_bytes, MAX_BODY_CHUNK_BYTES)
    }
}

#[derive(Clone, Debug, Deserialize, Serialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct BodyPartContent {
    pub part_id: String,
    pub representation: BodyRepresentation,
    pub mime_type: String,
    pub trust: BodyPartTrust,
    pub content: String,
    pub offset: u64,
    pub next_offset: Option<u64>,
    pub truncated: bool,
}

#[derive(Clone, Debug, Deserialize, Serialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct ReadAttachmentRequest {
    pub account_id: String,
    pub message_id: String,
    pub attachment_id: String,
    pub offset: u64,
    pub max_bytes: u32,
}

impl ReadAttachmentRequest {
    pub fn validate(&self) -> MailResult<()> {
        validate_chunk_bound(
            "attachment.maxBytes",
            self.max_bytes,
            MAX_ATTACHMENT_CHUNK_BYTES,
        )
    }
}

#[derive(Clone, Debug, Deserialize, Serialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct AttachmentChunk {
    pub attachment_id: String,
    pub data: Vec<u8>,
    pub offset: u64,
    pub next_offset: Option<u64>,
    pub truncated: bool,
}

fn validate_chunk_bound(label: &'static str, value: u32, maximum: u32) -> MailResult<()> {
    if value == 0 || value > maximum {
        return Err(MailError::BoundExceeded {
            bound: label,
            actual: value as usize,
            maximum: maximum as usize,
        });
    }
    Ok(())
}

#[derive(Clone, Debug, Deserialize, Serialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct SetReadStateRequest {
    pub account_id: String,
    pub message_id: String,
    pub is_read: bool,
}

#[derive(Clone, Debug, Deserialize, Serialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct ArchiveMessageRequest {
    pub account_id: String,
    pub message_id: String,
}

#[derive(Clone, Debug, Deserialize, Serialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct MoveMessageRequest {
    pub account_id: String,
    pub message_id: String,
    pub from_mailbox_id: Option<String>,
    pub to_mailbox_id: String,
}

#[derive(Clone, Debug, Deserialize, Serialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct OutgoingBody {
    pub plain_text: String,
    pub html: Option<String>,
}

impl OutgoingBody {
    pub fn validate(&self) -> MailResult<()> {
        let size = self.plain_text.len() + self.html.as_ref().map_or(0, String::len);
        if size > MAX_OUTGOING_BODY_BYTES {
            return Err(MailError::BoundExceeded {
                bound: "draft.body",
                actual: size,
                maximum: MAX_OUTGOING_BODY_BYTES,
            });
        }
        Ok(())
    }
}

#[derive(Clone, Debug, Deserialize, Serialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct DraftAttachment {
    pub host_attachment_id: Option<String>,
    pub source_message_id: Option<String>,
    pub source_attachment_id: Option<String>,
    pub file_name: String,
    pub mime_type: String,
    pub size_bytes: u64,
    pub sha256: Option<String>,
}

impl DraftAttachment {
    pub fn validate(&self) -> MailResult<()> {
        let host = self.host_attachment_id.is_some();
        let message = self.source_message_id.is_some();
        let source = self.source_attachment_id.is_some();
        let host_reference = host && !message && !source;
        let message_reference = !host && message && source;
        if !host_reference && !message_reference {
            return Err(MailError::InvalidRequest(
                "draft attachment must use one exact Host or source-message reference".into(),
            ));
        }
        if self.file_name.trim().is_empty()
            || self.file_name.len() > 255
            || self.file_name.chars().any(char::is_control)
            || self.mime_type.trim().is_empty()
            || self.mime_type.len() > 255
            || !self.mime_type.is_ascii()
            || self.mime_type.chars().any(char::is_whitespace)
            || !self.mime_type.contains('/')
        {
            return Err(MailError::InvalidRequest(
                "draft attachment metadata is invalid".into(),
            ));
        }
        if self.size_bytes > MAX_DRAFT_ATTACHMENT_BYTES {
            return Err(MailError::BoundExceeded {
                bound: "draft.attachment.bytes",
                actual: usize::try_from(self.size_bytes).unwrap_or(usize::MAX),
                maximum: MAX_DRAFT_ATTACHMENT_BYTES as usize,
            });
        }
        if host
            && self.sha256.as_ref().is_none_or(|hash| {
                hash.len() != 64 || !hash.bytes().all(|byte| byte.is_ascii_hexdigit())
            })
        {
            return Err(MailError::InvalidRequest(
                "Host draft attachment requires an exact SHA-256".into(),
            ));
        }
        Ok(())
    }
}

#[derive(Clone, Debug, Deserialize, Serialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct ReplyContext {
    pub message_id: String,
    pub internet_message_id: String,
    pub thread_id: Option<String>,
}

#[derive(Clone, Debug, Deserialize, Serialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct ForwardContext {
    pub message_id: String,
    pub internet_message_id: String,
}

#[derive(Clone, Debug, Deserialize, Serialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct DraftContent {
    pub to: Vec<MailAddress>,
    pub cc: Vec<MailAddress>,
    pub bcc: Vec<MailAddress>,
    pub subject: String,
    pub body: OutgoingBody,
    pub attachments: Vec<DraftAttachment>,
    pub reply_context: Option<ReplyContext>,
    pub forward_context: Option<ForwardContext>,
}

impl DraftContent {
    pub fn validate(&self) -> MailResult<()> {
        let recipients = self.to.len() + self.cc.len() + self.bcc.len();
        if recipients > MAX_RECIPIENTS {
            return Err(MailError::BoundExceeded {
                bound: "draft.recipients",
                actual: recipients,
                maximum: MAX_RECIPIENTS,
            });
        }
        if self.reply_context.is_some() && self.forward_context.is_some() {
            return Err(MailError::InvalidRequest(
                "draft cannot be both a reply and a forward".into(),
            ));
        }
        if self.attachments.len() > MAX_DRAFT_ATTACHMENTS {
            return Err(MailError::BoundExceeded {
                bound: "draft.attachments",
                actual: self.attachments.len(),
                maximum: MAX_DRAFT_ATTACHMENTS,
            });
        }
        let mut total_bytes = 0_u64;
        for attachment in &self.attachments {
            attachment.validate()?;
            total_bytes = total_bytes.saturating_add(attachment.size_bytes);
        }
        if total_bytes > MAX_DRAFT_ATTACHMENTS_TOTAL_BYTES {
            return Err(MailError::BoundExceeded {
                bound: "draft.attachments.totalBytes",
                actual: usize::try_from(total_bytes).unwrap_or(usize::MAX),
                maximum: MAX_DRAFT_ATTACHMENTS_TOTAL_BYTES as usize,
            });
        }
        self.body.validate()
    }
}

#[derive(Clone, Debug, Deserialize, Serialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct MailDraft {
    pub id: String,
    pub account_id: String,
    pub revision: u64,
    pub content: DraftContent,
    pub provider_reference: Option<ProviderReference>,
}

#[derive(Clone, Debug, Deserialize, Serialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct CreateDraftRequest {
    pub account_id: String,
    pub content: DraftContent,
}

#[derive(Clone, Debug, Deserialize, Serialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct CreateReplyDraftRequest {
    pub account_id: String,
    pub message_id: String,
    pub reply_all: bool,
}

#[derive(Clone, Debug, Deserialize, Serialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct CreateForwardDraftRequest {
    pub account_id: String,
    pub message_id: String,
}

#[derive(Clone, Debug, Deserialize, Serialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct UpdateDraftRequest {
    pub account_id: String,
    pub draft_id: String,
    pub expected_revision: u64,
    pub content: DraftContent,
}

#[derive(Clone, Debug, Deserialize, Serialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct GetDraftRequest {
    pub account_id: String,
    pub draft_id: String,
}

#[derive(Clone, Copy, Debug, Deserialize, Serialize, PartialEq, Eq)]
#[serde(rename_all = "snake_case")]
pub enum MailApprovalOperation {
    DeleteDraft,
    SendDraft,
}

#[derive(Clone, Debug, Deserialize, Serialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct MailApprovalGrant {
    pub approval_id: String,
    pub operation: MailApprovalOperation,
    pub resource_id: String,
    pub revision: u64,
    pub preview_hash: Option<String>,
}

#[derive(Clone, Debug, Deserialize, Serialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct DeleteDraftRequest {
    pub account_id: String,
    pub draft_id: String,
    pub expected_revision: u64,
    pub approval: MailApprovalGrant,
}

#[derive(Clone, Debug, Deserialize, Serialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct PreviewSendRequest {
    pub account_id: String,
    pub draft_id: String,
    pub expected_revision: u64,
    pub idempotency_key: String,
}

#[derive(Clone, Debug, Deserialize, Serialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct SendPreview {
    pub id: String,
    pub draft_id: String,
    pub draft_revision: u64,
    pub account_id: String,
    pub from: MailAddress,
    pub to: Vec<MailAddress>,
    pub cc: Vec<MailAddress>,
    pub bcc: Vec<MailAddress>,
    pub subject: String,
    pub body_sha256: String,
    pub attachments: Vec<DraftAttachment>,
    pub reply_context: Option<ReplyContext>,
    pub forward_context: Option<ForwardContext>,
    pub outbox_id: String,
    pub internet_message_id: String,
    pub idempotency_key: String,
    pub preview_hash: String,
}

impl SendPreview {
    pub fn approval_grant(&self, approval_id: impl Into<String>) -> MailApprovalGrant {
        MailApprovalGrant {
            approval_id: approval_id.into(),
            operation: MailApprovalOperation::SendDraft,
            resource_id: self.draft_id.clone(),
            revision: self.draft_revision,
            preview_hash: Some(self.preview_hash.clone()),
        }
    }
}

#[derive(Clone, Debug, Deserialize, Serialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct ApprovedSendRequest {
    pub preview_id: String,
    pub approval: MailApprovalGrant,
}

#[derive(Clone, Copy, Debug, Deserialize, Serialize, PartialEq, Eq)]
#[serde(rename_all = "snake_case")]
pub enum DeliveryState {
    Delivered,
    Rejected,
    Deferred,
    Uncertain,
}

impl DeliveryState {
    pub fn requires_reconciliation(self) -> bool {
        self == Self::Uncertain
    }

    pub fn permits_blind_retry(self) -> bool {
        self != Self::Uncertain
    }
}

#[derive(Clone, Debug, Deserialize, Serialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct DeliveryReceipt {
    pub outbox_id: String,
    pub message_id: String,
    pub internet_message_id: String,
    pub state: DeliveryState,
    pub detail: Option<String>,
    pub submitted_at: DateTime<Utc>,
}

#[derive(Clone, Debug, Deserialize, Serialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct DeliveryStatusRequest {
    pub account_id: String,
    pub outbox_id: String,
}

pub fn sha256_hex(bytes: impl AsRef<[u8]>) -> String {
    hex::encode(Sha256::digest(bytes.as_ref()))
}

#[async_trait]
pub trait MailConnector: Send + Sync {
    async fn list_accounts(&self) -> MailResult<Vec<MailAccount>>;
    async fn account_status(&self, account_id: &str) -> MailResult<MailAccountStatus>;
    async fn request_connect(
        &self,
        request: MailAccountActionRequest,
    ) -> MailResult<MailAccountStatus>;
    async fn disconnect(&self, request: MailAccountActionRequest) -> MailResult<MailAccountStatus>;
    async fn list_mailboxes(&self, account_id: &str) -> MailResult<Vec<Mailbox>>;
    async fn list_threads(&self, request: ListThreadsRequest) -> MailResult<Page<MailThread>>;
    async fn get_thread(&self, request: GetThreadRequest) -> MailResult<MailThreadDetail>;
    async fn search_messages(
        &self,
        request: SearchMessagesRequest,
    ) -> MailResult<Page<MailMessageSummary>>;
    async fn get_message(&self, request: GetMessageRequest) -> MailResult<MailMessage>;
    async fn read_body_part(&self, request: ReadBodyPartRequest) -> MailResult<BodyPartContent>;
    async fn read_attachment(&self, request: ReadAttachmentRequest) -> MailResult<AttachmentChunk>;
    async fn set_read_state(&self, request: SetReadStateRequest) -> MailResult<MailMessageSummary>;
    async fn archive_message(
        &self,
        request: ArchiveMessageRequest,
    ) -> MailResult<MailMessageSummary>;
    async fn move_message(&self, request: MoveMessageRequest) -> MailResult<MailMessageSummary>;
    async fn create_draft(&self, request: CreateDraftRequest) -> MailResult<MailDraft>;
    async fn create_reply_draft(&self, request: CreateReplyDraftRequest) -> MailResult<MailDraft>;
    async fn create_forward_draft(
        &self,
        request: CreateForwardDraftRequest,
    ) -> MailResult<MailDraft>;
    async fn get_draft(&self, request: GetDraftRequest) -> MailResult<MailDraft>;
    async fn update_draft(&self, request: UpdateDraftRequest) -> MailResult<MailDraft>;
    async fn delete_draft(&self, request: DeleteDraftRequest) -> MailResult<()>;
    async fn preview_send(&self, request: PreviewSendRequest) -> MailResult<SendPreview>;
    async fn send_approved(&self, request: ApprovedSendRequest) -> MailResult<DeliveryReceipt>;
    async fn delivery_status(&self, request: DeliveryStatusRequest) -> MailResult<DeliveryReceipt>;
}
