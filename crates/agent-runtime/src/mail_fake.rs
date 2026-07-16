use crate::mail::*;
use async_trait::async_trait;
use chrono::Utc;
use std::collections::{BTreeMap, HashMap, HashSet, VecDeque};
use std::sync::{Arc, Mutex, MutexGuard};

#[path = "mail_fake_support.rs"]
mod support;
use support::*;

#[derive(Clone, Debug)]
pub struct SeedBodyPart {
    pub metadata: MailBodyPart,
    pub original: String,
    pub sanitized_plain_fallback: Option<String>,
}

impl SeedBodyPart {
    pub fn plain(id: impl Into<String>, content: impl Into<String>) -> Self {
        let content = content.into();
        Self {
            metadata: MailBodyPart {
                id: id.into(),
                mime_type: "text/plain".into(),
                charset: Some("utf-8".into()),
                size_bytes: content.len() as u64,
                disposition: None,
                content_id: None,
                trust: BodyPartTrust::PlainText,
                has_sanitized_plain_fallback: false,
            },
            original: content,
            sanitized_plain_fallback: None,
        }
    }

    pub fn untrusted_html(
        id: impl Into<String>,
        html: impl Into<String>,
        sanitized_plain_fallback: impl Into<String>,
    ) -> Self {
        let html = html.into();
        Self {
            metadata: MailBodyPart {
                id: id.into(),
                mime_type: "text/html".into(),
                charset: Some("utf-8".into()),
                size_bytes: html.len() as u64,
                disposition: None,
                content_id: None,
                trust: BodyPartTrust::UntrustedHtml,
                has_sanitized_plain_fallback: true,
            },
            original: html,
            sanitized_plain_fallback: Some(sanitized_plain_fallback.into()),
        }
    }

    fn validate(&self) -> MailResult<()> {
        if self.metadata.trust == BodyPartTrust::UntrustedHtml
            && self.sanitized_plain_fallback.is_none()
        {
            return Err(MailError::InvalidRequest(
                "untrusted HTML body part requires a sanitized plain fallback".into(),
            ));
        }
        if self.metadata.trust == BodyPartTrust::PlainText
            && self.metadata.mime_type != "text/plain"
        {
            return Err(MailError::InvalidRequest(
                "plain body part must use text/plain".into(),
            ));
        }
        Ok(())
    }
}

#[derive(Clone, Debug)]
pub struct SeedAttachment {
    pub metadata: AttachmentMetadata,
    pub data: Vec<u8>,
}

#[derive(Clone, Debug)]
pub struct SeedMessage {
    pub message: MailMessage,
    pub bodies: Vec<SeedBodyPart>,
    pub attachments: Vec<SeedAttachment>,
}

#[derive(Clone)]
pub struct FakeMailConnector {
    state: Arc<Mutex<FakeMailState>>,
}

#[derive(Default)]
struct FakeMailState {
    accounts: BTreeMap<String, MailAccount>,
    account_states: BTreeMap<String, MailAccountState>,
    mailboxes: BTreeMap<String, Mailbox>,
    messages: BTreeMap<String, StoredMessage>,
    drafts: BTreeMap<String, MailDraft>,
    previews: HashMap<String, PreviewRecord>,
    preview_by_key: HashMap<String, String>,
    receipts_by_key: HashMap<String, DeliveryReceipt>,
    receipts_by_outbox: HashMap<String, DeliveryReceipt>,
    uncertain_drafts: HashMap<(String, u64), String>,
    delivery_plan: VecDeque<DeliveryState>,
    next_draft: u64,
    provider_submissions: u64,
    logical_deliveries: u64,
}

#[derive(Clone)]
struct StoredMessage {
    message: MailMessage,
    bodies: HashMap<String, SeedBodyPart>,
    attachments: HashMap<String, SeedAttachment>,
}

#[derive(Clone)]
struct PreviewRecord {
    preview: SendPreview,
    content_hash: String,
    draft: MailDraft,
}

impl FakeMailConnector {
    pub fn new() -> Self {
        Self {
            state: Arc::new(Mutex::new(FakeMailState::default())),
        }
    }

    fn state(&self) -> MutexGuard<'_, FakeMailState> {
        self.state.lock().expect("fake mail state poisoned")
    }

    pub fn add_account(&self, account: MailAccount) -> MailResult<()> {
        validate_nonempty(&account.id, "account.id")?;
        validate_address(&account.primary_address)?;
        let mut state = self.state();
        if state.accounts.contains_key(&account.id) {
            return Err(MailError::InvalidRequest(format!(
                "duplicate account {}",
                account.id
            )));
        }
        let account_id = account.id.clone();
        state.accounts.insert(account_id.clone(), account);
        state
            .account_states
            .insert(account_id.clone(), MailAccountState::Connected);
        for (suffix, name, role) in [
            ("inbox", "Inbox", MailboxRole::Inbox),
            ("sent", "Sent", MailboxRole::Sent),
            ("drafts", "Drafts", MailboxRole::Drafts),
            ("archive", "Archive", MailboxRole::Archive),
            ("trash", "Trash", MailboxRole::Trash),
        ] {
            let id = format!("{account_id}:{suffix}");
            state.mailboxes.insert(
                id.clone(),
                Mailbox {
                    id,
                    account_id: account_id.clone(),
                    name: name.into(),
                    role,
                    provider_reference: None,
                },
            );
        }
        Ok(())
    }

    pub fn add_mailbox(&self, mailbox: Mailbox) -> MailResult<()> {
        let mut state = self.state();
        ensure_account(&state, &mailbox.account_id)?;
        if state
            .mailboxes
            .insert(mailbox.id.clone(), mailbox)
            .is_some()
        {
            return Err(MailError::InvalidRequest("duplicate mailbox".into()));
        }
        Ok(())
    }

    pub fn seed_message(&self, seed: SeedMessage) -> MailResult<()> {
        let mut state = self.state();
        let message = seed.message;
        ensure_account(&state, &message.summary.account_id)?;
        validate_nonempty(&message.summary.internet_message_id, "internetMessageId")?;
        let mut bodies = HashMap::new();
        for body in seed.bodies {
            body.validate()?;
            if bodies.insert(body.metadata.id.clone(), body).is_some() {
                return Err(MailError::InvalidRequest("duplicate body part".into()));
            }
        }
        if message
            .body_parts
            .iter()
            .any(|part| !bodies.contains_key(&part.id))
        {
            return Err(MailError::InvalidRequest(
                "message body metadata does not match seeded bodies".into(),
            ));
        }
        let attachments = seed
            .attachments
            .into_iter()
            .map(|attachment| (attachment.metadata.id.clone(), attachment))
            .collect::<HashMap<_, _>>();
        if message
            .attachments
            .iter()
            .any(|attachment| !attachments.contains_key(&attachment.id))
        {
            return Err(MailError::InvalidRequest(
                "message attachment metadata does not match seeded attachments".into(),
            ));
        }
        state.messages.insert(
            message.summary.id.clone(),
            StoredMessage {
                message,
                bodies,
                attachments,
            },
        );
        Ok(())
    }

    pub fn queue_delivery_outcome(&self, state: DeliveryState) {
        self.state().delivery_plan.push_back(state);
    }

    pub fn provider_submission_count(&self) -> u64 {
        self.state().provider_submissions
    }

    pub fn logical_delivery_count(&self) -> u64 {
        self.state().logical_deliveries
    }
}

impl Default for FakeMailConnector {
    fn default() -> Self {
        Self::new()
    }
}

#[async_trait]
impl MailConnector for FakeMailConnector {
    async fn list_accounts(&self) -> MailResult<Vec<MailAccount>> {
        Ok(self.state().accounts.values().cloned().collect())
    }

    async fn account_status(&self, account_id: &str) -> MailResult<MailAccountStatus> {
        let state = self.state();
        ensure_account(&state, account_id)?;
        Ok(MailAccountStatus {
            account: state
                .accounts
                .get(account_id)
                .expect("account checked above")
                .clone(),
            state: *state
                .account_states
                .get(account_id)
                .unwrap_or(&MailAccountState::Unavailable),
            detail: None,
        })
    }

    async fn request_connect(
        &self,
        request: MailAccountActionRequest,
    ) -> MailResult<MailAccountStatus> {
        let mut state = self.state();
        ensure_account(&state, &request.account_id)?;
        state
            .account_states
            .insert(request.account_id.clone(), MailAccountState::Connected);
        let account = state.accounts[&request.account_id].clone();
        Ok(MailAccountStatus {
            account,
            state: MailAccountState::Connected,
            detail: Some("Fake connector connected without credentials".into()),
        })
    }

    async fn disconnect(&self, request: MailAccountActionRequest) -> MailResult<MailAccountStatus> {
        let mut state = self.state();
        ensure_account(&state, &request.account_id)?;
        state.account_states.insert(
            request.account_id.clone(),
            MailAccountState::AuthenticationRequired,
        );
        let account = state.accounts[&request.account_id].clone();
        Ok(MailAccountStatus {
            account,
            state: MailAccountState::AuthenticationRequired,
            detail: Some("Account disconnected from the fake connector".into()),
        })
    }

    async fn list_mailboxes(&self, account_id: &str) -> MailResult<Vec<Mailbox>> {
        let state = self.state();
        ensure_account(&state, account_id)?;
        Ok(state
            .mailboxes
            .values()
            .filter(|mailbox| mailbox.account_id == account_id)
            .cloned()
            .collect())
    }

    async fn list_threads(&self, request: ListThreadsRequest) -> MailResult<Page<MailThread>> {
        request.page.validate()?;
        let state = self.state();
        ensure_account(&state, &request.account_id)?;
        if let Some(mailbox_id) = &request.mailbox_id {
            ensure_mailbox(&state, &request.account_id, mailbox_id)?;
        }
        let mut grouped: BTreeMap<String, Vec<&MailMessage>> = BTreeMap::new();
        for stored in state.messages.values() {
            let message = &stored.message;
            if message.summary.account_id != request.account_id
                || request
                    .mailbox_id
                    .as_ref()
                    .is_some_and(|id| !message.summary.mailbox_ids.contains(id))
            {
                continue;
            }
            let id = message
                .summary
                .thread_id
                .clone()
                .unwrap_or_else(|| format!("message:{}", message.summary.id));
            grouped.entry(id).or_default().push(message);
        }
        let mut threads = grouped
            .into_iter()
            .map(|(id, mut messages)| {
                messages.sort_by_key(|message| message.summary.sent_at);
                thread_from_messages(id, &request.account_id, &messages)
            })
            .collect::<Vec<_>>();
        threads.sort_by(|left, right| {
            right
                .last_message_at
                .cmp(&left.last_message_at)
                .then_with(|| left.id.cmp(&right.id))
        });
        paginate(threads, &request.page)
    }

    async fn get_thread(&self, request: GetThreadRequest) -> MailResult<MailThreadDetail> {
        let state = self.state();
        ensure_account(&state, &request.account_id)?;
        let mut messages = state
            .messages
            .values()
            .map(|stored| stored.message.clone())
            .filter(|message| {
                message.summary.account_id == request.account_id
                    && message.summary.thread_id.as_deref() == Some(&request.thread_id)
            })
            .collect::<Vec<_>>();
        if messages.is_empty() {
            return Err(MailError::NotFound(request.thread_id));
        }
        messages.sort_by_key(|message| message.summary.sent_at);
        let references = messages.iter().collect::<Vec<_>>();
        let thread = thread_from_messages(request.thread_id, &request.account_id, &references);
        Ok(MailThreadDetail { thread, messages })
    }

    async fn search_messages(
        &self,
        request: SearchMessagesRequest,
    ) -> MailResult<Page<MailMessageSummary>> {
        request.page.validate()?;
        request.search.validate()?;
        let state = self.state();
        ensure_account(&state, &request.account_id)?;
        if let Some(mailbox_id) = &request.mailbox_id {
            ensure_mailbox(&state, &request.account_id, mailbox_id)?;
        }
        let mut messages = state
            .messages
            .values()
            .map(|stored| &stored.message)
            .filter(|message| message.summary.account_id == request.account_id)
            .filter(|message| {
                request
                    .mailbox_id
                    .as_ref()
                    .is_none_or(|id| message.summary.mailbox_ids.contains(id))
            })
            .filter(|message| matches_search(message, &request.search))
            .map(|message| message.summary.clone())
            .collect::<Vec<_>>();
        messages.sort_by(|left, right| {
            right
                .sent_at
                .cmp(&left.sent_at)
                .then_with(|| left.id.cmp(&right.id))
        });
        paginate(messages, &request.page)
    }

    async fn get_message(&self, request: GetMessageRequest) -> MailResult<MailMessage> {
        let state = self.state();
        Ok(
            find_message(&state, &request.account_id, &request.message_id)?
                .message
                .clone(),
        )
    }

    async fn read_body_part(&self, request: ReadBodyPartRequest) -> MailResult<BodyPartContent> {
        request.validate()?;
        let state = self.state();
        let stored = find_message(&state, &request.account_id, &request.message_id)?;
        let body = stored
            .bodies
            .get(&request.part_id)
            .ok_or_else(|| MailError::NotFound(request.part_id.clone()))?;
        let (source, mime_type, trust) = match request.representation {
            BodyRepresentation::Original => (
                body.original.as_str(),
                body.metadata.mime_type.clone(),
                body.metadata.trust,
            ),
            BodyRepresentation::SanitizedPlainFallback => (
                body.sanitized_plain_fallback.as_deref().ok_or_else(|| {
                    MailError::Unsupported("body has no sanitized plain fallback".into())
                })?,
                "text/plain".into(),
                BodyPartTrust::PlainText,
            ),
        };
        let chunk = text_chunk(source, request.offset, request.max_bytes)?;
        Ok(BodyPartContent {
            part_id: request.part_id,
            representation: request.representation,
            mime_type,
            trust,
            content: chunk.content,
            offset: request.offset,
            next_offset: chunk.next_offset,
            truncated: chunk.truncated,
        })
    }

    async fn read_attachment(&self, request: ReadAttachmentRequest) -> MailResult<AttachmentChunk> {
        request.validate()?;
        let state = self.state();
        let stored = find_message(&state, &request.account_id, &request.message_id)?;
        let attachment = stored
            .attachments
            .get(&request.attachment_id)
            .ok_or_else(|| MailError::NotFound(request.attachment_id.clone()))?;
        let offset = usize::try_from(request.offset)
            .map_err(|_| MailError::InvalidRequest("attachment offset is too large".into()))?;
        if offset > attachment.data.len() {
            return Err(MailError::InvalidRequest(
                "attachment offset exceeds content length".into(),
            ));
        }
        let end = offset
            .saturating_add(request.max_bytes as usize)
            .min(attachment.data.len());
        let truncated = end < attachment.data.len();
        Ok(AttachmentChunk {
            attachment_id: request.attachment_id,
            data: attachment.data[offset..end].to_vec(),
            offset: request.offset,
            next_offset: truncated.then_some(end as u64),
            truncated,
        })
    }

    async fn set_read_state(&self, request: SetReadStateRequest) -> MailResult<MailMessageSummary> {
        let mut state = self.state();
        let stored = find_message_mut(&mut state, &request.account_id, &request.message_id)?;
        stored.message.summary.is_read = request.is_read;
        Ok(stored.message.summary.clone())
    }

    async fn archive_message(
        &self,
        request: ArchiveMessageRequest,
    ) -> MailResult<MailMessageSummary> {
        let mut state = self.state();
        let inbox = mailbox_for_role(&state, &request.account_id, MailboxRole::Inbox)?.id;
        let archive = mailbox_for_role(&state, &request.account_id, MailboxRole::Archive)?.id;
        let stored = find_message_mut(&mut state, &request.account_id, &request.message_id)?;
        stored.message.summary.mailbox_ids.retain(|id| id != &inbox);
        insert_unique(&mut stored.message.summary.mailbox_ids, archive);
        Ok(stored.message.summary.clone())
    }

    async fn move_message(&self, request: MoveMessageRequest) -> MailResult<MailMessageSummary> {
        let mut state = self.state();
        ensure_mailbox(&state, &request.account_id, &request.to_mailbox_id)?;
        if let Some(from) = &request.from_mailbox_id {
            ensure_mailbox(&state, &request.account_id, from)?;
        }
        let stored = find_message_mut(&mut state, &request.account_id, &request.message_id)?;
        if let Some(from) = request.from_mailbox_id {
            stored.message.summary.mailbox_ids.retain(|id| id != &from);
        } else {
            stored.message.summary.mailbox_ids.clear();
        }
        insert_unique(
            &mut stored.message.summary.mailbox_ids,
            request.to_mailbox_id,
        );
        Ok(stored.message.summary.clone())
    }

    async fn create_draft(&self, request: CreateDraftRequest) -> MailResult<MailDraft> {
        request.content.validate()?;
        let mut state = self.state();
        ensure_account(&state, &request.account_id)?;
        create_draft(&mut state, request.account_id, request.content)
    }

    async fn create_reply_draft(&self, request: CreateReplyDraftRequest) -> MailResult<MailDraft> {
        let mut state = self.state();
        let account = ensure_account(&state, &request.account_id)?.clone();
        let original = find_message(&state, &request.account_id, &request.message_id)?
            .message
            .clone();
        let mut recipients = original
            .reply_to
            .first()
            .cloned()
            .unwrap_or_else(|| original.summary.from.clone());
        if recipients.normalized() == account.primary_address.normalized() {
            recipients = original.summary.from.clone();
        }
        let mut to = vec![recipients];
        let mut cc = Vec::new();
        if request.reply_all {
            let account_addresses = account
                .addresses
                .iter()
                .chain(std::iter::once(&account.primary_address))
                .map(MailAddress::normalized)
                .collect::<HashSet<_>>();
            for address in original.summary.to.iter().chain(&original.cc) {
                if !account_addresses.contains(&address.normalized()) {
                    push_unique_address(&mut to, address.clone());
                }
            }
            for address in &original.cc {
                if !account_addresses.contains(&address.normalized()) {
                    push_unique_address(&mut cc, address.clone());
                }
            }
        }
        let content = DraftContent {
            to,
            cc,
            bcc: Vec::new(),
            subject: prefixed_subject("Re:", &original.summary.subject),
            body: OutgoingBody {
                plain_text: String::new(),
                html: None,
            },
            attachments: Vec::new(),
            reply_context: Some(ReplyContext {
                message_id: original.summary.id,
                internet_message_id: original.summary.internet_message_id,
                thread_id: original.summary.thread_id,
            }),
            forward_context: None,
        };
        create_draft(&mut state, request.account_id, content)
    }

    async fn create_forward_draft(
        &self,
        request: CreateForwardDraftRequest,
    ) -> MailResult<MailDraft> {
        let mut state = self.state();
        let original = find_message(&state, &request.account_id, &request.message_id)?
            .message
            .clone();
        let content = DraftContent {
            to: Vec::new(),
            cc: Vec::new(),
            bcc: Vec::new(),
            subject: prefixed_subject("Fwd:", &original.summary.subject),
            body: OutgoingBody {
                plain_text: String::new(),
                html: None,
            },
            attachments: original
                .attachments
                .iter()
                .map(|attachment| DraftAttachment {
                    host_attachment_id: None,
                    source_message_id: Some(original.summary.id.clone()),
                    source_attachment_id: Some(attachment.id.clone()),
                    file_name: attachment.file_name.clone(),
                    mime_type: attachment.mime_type.clone(),
                    size_bytes: attachment.size_bytes,
                    sha256: None,
                })
                .collect(),
            reply_context: None,
            forward_context: Some(ForwardContext {
                message_id: original.summary.id,
                internet_message_id: original.summary.internet_message_id,
            }),
        };
        create_draft(&mut state, request.account_id, content)
    }

    async fn get_draft(&self, request: GetDraftRequest) -> MailResult<MailDraft> {
        let state = self.state();
        Ok(find_draft(&state, &request.account_id, &request.draft_id)?.clone())
    }

    async fn update_draft(&self, request: UpdateDraftRequest) -> MailResult<MailDraft> {
        request.content.validate()?;
        let mut state = self.state();
        let draft = find_draft_mut(&mut state, &request.account_id, &request.draft_id)?;
        check_revision(draft.revision, request.expected_revision)?;
        draft.revision += 1;
        draft.content = request.content;
        Ok(draft.clone())
    }

    async fn delete_draft(&self, request: DeleteDraftRequest) -> MailResult<()> {
        let mut state = self.state();
        let draft = find_draft(&state, &request.account_id, &request.draft_id)?;
        check_revision(draft.revision, request.expected_revision)?;
        validate_approval(
            &request.approval,
            MailApprovalOperation::DeleteDraft,
            &request.draft_id,
            request.expected_revision,
            None,
        )?;
        state.drafts.remove(&request.draft_id);
        Ok(())
    }

    async fn preview_send(&self, request: PreviewSendRequest) -> MailResult<SendPreview> {
        validate_nonempty(&request.idempotency_key, "idempotencyKey")?;
        if request.idempotency_key.len() > 256 {
            return Err(MailError::BoundExceeded {
                bound: "idempotencyKey",
                actual: request.idempotency_key.len(),
                maximum: 256,
            });
        }
        let mut state = self.state();
        let account = ensure_account(&state, &request.account_id)?.clone();
        let draft = find_draft(&state, &request.account_id, &request.draft_id)?.clone();
        check_revision(draft.revision, request.expected_revision)?;
        if draft.content.to.is_empty()
            && draft.content.cc.is_empty()
            && draft.content.bcc.is_empty()
        {
            return Err(MailError::InvalidRequest(
                "send preview requires at least one recipient".into(),
            ));
        }
        if let Some(outbox_id) = state
            .uncertain_drafts
            .get(&(draft.id.clone(), draft.revision))
        {
            return Err(MailError::ReconciliationRequired {
                outbox_id: outbox_id.clone(),
            });
        }
        let content_hash = sha256_hex(
            serde_json::to_vec(&draft.content)
                .map_err(|error| MailError::InvalidRequest(error.to_string()))?,
        );
        if let Some(preview_id) = state.preview_by_key.get(&request.idempotency_key) {
            let record = state
                .previews
                .get(preview_id)
                .expect("preview index must reference a preview");
            if record.content_hash != content_hash
                || record.preview.draft_id != request.draft_id
                || record.preview.draft_revision != request.expected_revision
            {
                return Err(MailError::IdempotencyConflict);
            }
            return Ok(record.preview.clone());
        }
        let token = sha256_hex(format!(
            "{}\0{}\0{}\0{}\0{}",
            request.account_id,
            request.draft_id,
            request.expected_revision,
            request.idempotency_key,
            content_hash
        ));
        let outbox_id = format!("outbox-{}", &token[..24]);
        let internet_message_id = format!("<{}@agentweave.local>", &token[..32]);
        let preview_hash = sha256_hex(format!("{token}\0{outbox_id}\0{internet_message_id}"));
        let preview = SendPreview {
            id: format!("preview-{}", &token[..24]),
            draft_id: draft.id.clone(),
            draft_revision: draft.revision,
            account_id: draft.account_id.clone(),
            from: account.primary_address,
            to: draft.content.to.clone(),
            cc: draft.content.cc.clone(),
            bcc: draft.content.bcc.clone(),
            subject: draft.content.subject.clone(),
            body_sha256: sha256_hex(
                serde_json::to_vec(&draft.content.body)
                    .map_err(|error| MailError::InvalidRequest(error.to_string()))?,
            ),
            attachments: draft.content.attachments.clone(),
            reply_context: draft.content.reply_context.clone(),
            forward_context: draft.content.forward_context.clone(),
            outbox_id,
            internet_message_id,
            idempotency_key: request.idempotency_key.clone(),
            preview_hash,
        };
        state
            .preview_by_key
            .insert(request.idempotency_key, preview.id.clone());
        state.previews.insert(
            preview.id.clone(),
            PreviewRecord {
                preview: preview.clone(),
                content_hash,
                draft,
            },
        );
        Ok(preview)
    }

    async fn send_approved(&self, request: ApprovedSendRequest) -> MailResult<DeliveryReceipt> {
        let mut state = self.state();
        let record = state
            .previews
            .get(&request.preview_id)
            .cloned()
            .ok_or_else(|| MailError::NotFound(request.preview_id.clone()))?;
        validate_approval(
            &request.approval,
            MailApprovalOperation::SendDraft,
            &record.preview.draft_id,
            record.preview.draft_revision,
            Some(&record.preview.preview_hash),
        )?;
        if let Some(receipt) = state.receipts_by_key.get(&record.preview.idempotency_key) {
            return Ok(receipt.clone());
        }
        let current = find_draft(&state, &record.preview.account_id, &record.preview.draft_id)?;
        check_revision(current.revision, record.preview.draft_revision)?;
        let outcome = state
            .delivery_plan
            .pop_front()
            .unwrap_or(DeliveryState::Delivered);
        state.provider_submissions += 1;
        let receipt = DeliveryReceipt {
            outbox_id: record.preview.outbox_id.clone(),
            message_id: format!("sent-{}", &record.preview.preview_hash[..24]),
            internet_message_id: record.preview.internet_message_id.clone(),
            state: outcome,
            detail: None,
            submitted_at: Utc::now(),
        };
        if outcome == DeliveryState::Delivered {
            materialize_sent_message(&mut state, &record, &receipt)?;
            state.drafts.remove(&record.preview.draft_id);
            state.logical_deliveries += 1;
        } else if outcome == DeliveryState::Uncertain {
            state.uncertain_drafts.insert(
                (
                    record.preview.draft_id.clone(),
                    record.preview.draft_revision,
                ),
                receipt.outbox_id.clone(),
            );
        }
        state
            .receipts_by_key
            .insert(record.preview.idempotency_key.clone(), receipt.clone());
        state
            .receipts_by_outbox
            .insert(receipt.outbox_id.clone(), receipt.clone());
        Ok(receipt)
    }

    async fn delivery_status(&self, request: DeliveryStatusRequest) -> MailResult<DeliveryReceipt> {
        let state = self.state();
        ensure_account(&state, &request.account_id)?;
        state
            .receipts_by_outbox
            .get(&request.outbox_id)
            .cloned()
            .ok_or(MailError::NotFound(request.outbox_id))
    }
}
