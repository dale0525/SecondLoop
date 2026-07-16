use crate::approval::immutable_arguments_hash;
use crate::foundation_action_envelope::{
    FoundationActionEffect, FoundationActionEnvelope, FoundationActionPreview,
    FoundationActionResource,
};
use crate::mail::{
    DraftContent, MAX_DRAFT_ATTACHMENTS, MAX_DRAFT_ATTACHMENTS_TOTAL_BYTES, MAX_RECIPIENTS,
    MailDraft, SendPreview,
};
use crate::mail_connector_transport::MAIL_CONNECTOR_ID;
use serde::{Deserialize, Serialize};
use serde_json::{Value, json};

pub const MAIL_DRAFT_ENVELOPE_VERSION: u32 = 1;
pub const MAIL_SEND_ENVELOPE_VERSION: u32 = 1;
pub const MAIL_SEND_ACTION_KIND: &str = "mail.send";
pub const MAIL_SEND_OPERATION: &str = "mail_send";

#[derive(Clone, Debug, Deserialize, Serialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct CanonicalMailDraftEnvelope {
    pub schema_version: u32,
    pub account_id: String,
    pub draft_id: String,
    pub revision: u64,
    pub content: DraftContent,
    pub content_sha256: String,
}

impl CanonicalMailDraftEnvelope {
    pub fn from_draft(draft: MailDraft) -> anyhow::Result<Self> {
        let content_sha256 = immutable_arguments_hash(&serde_json::to_value(&draft.content)?)?;
        let envelope = Self {
            schema_version: MAIL_DRAFT_ENVELOPE_VERSION,
            account_id: draft.account_id,
            draft_id: draft.id,
            revision: draft.revision,
            content: draft.content,
            content_sha256,
        };
        envelope.validate()?;
        Ok(envelope)
    }

    pub fn validate(&self) -> anyhow::Result<()> {
        anyhow::ensure!(
            self.schema_version == MAIL_DRAFT_ENVELOPE_VERSION,
            "unsupported canonical Mail draft version"
        );
        validate_text(&self.account_id, 255, "Mail draft account id")?;
        validate_text(&self.draft_id, 512, "Mail draft id")?;
        anyhow::ensure!(self.revision > 0, "Mail draft revision is invalid");
        self.content
            .validate()
            .map_err(|error| anyhow::anyhow!(error.to_string()))?;
        anyhow::ensure!(
            self.content_sha256 == immutable_arguments_hash(&serde_json::to_value(&self.content)?)?,
            "Mail draft content hash does not match content"
        );
        Ok(())
    }
}

#[derive(Clone, Debug, Deserialize, Serialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct CanonicalMailSendEnvelope {
    pub schema_version: u32,
    pub preview: SendPreview,
    pub preview_sha256: String,
}

impl CanonicalMailSendEnvelope {
    pub fn from_preview(preview: SendPreview) -> anyhow::Result<Self> {
        let preview_sha256 = immutable_arguments_hash(&serde_json::to_value(&preview)?)?;
        let envelope = Self {
            schema_version: MAIL_SEND_ENVELOPE_VERSION,
            preview,
            preview_sha256,
        };
        envelope.validate()?;
        Ok(envelope)
    }

    pub fn validate(&self) -> anyhow::Result<()> {
        anyhow::ensure!(
            self.schema_version == MAIL_SEND_ENVELOPE_VERSION,
            "unsupported canonical Mail send version"
        );
        validate_send_preview(&self.preview)?;
        anyhow::ensure!(
            self.preview_sha256 == immutable_arguments_hash(&serde_json::to_value(&self.preview)?)?,
            "Mail send preview hash does not match preview"
        );
        Ok(())
    }

    pub fn into_foundation_action(self) -> anyhow::Result<FoundationActionEnvelope> {
        self.validate()?;
        let preview = FoundationActionPreview::new(
            mail_send_risk_summary(&self.preview),
            mail_send_preview_details(&self.preview),
        )?;
        FoundationActionEnvelope::new(
            MAIL_SEND_ACTION_KIND,
            MAIL_CONNECTOR_ID,
            MAIL_SEND_OPERATION,
            self.preview.account_id.clone(),
            FoundationActionResource::new(
                "draft",
                self.preview.draft_id.clone(),
                Some(self.preview.draft_revision.to_string()),
            )?,
            FoundationActionEffect::ExternalWrite,
            self.preview.idempotency_key.clone(),
            serde_json::to_value(self)?,
            preview,
        )
    }

    pub fn from_foundation_action(envelope: &FoundationActionEnvelope) -> anyhow::Result<Self> {
        envelope.validate()?;
        anyhow::ensure!(
            envelope.kind == MAIL_SEND_ACTION_KIND
                && envelope.connector_id == MAIL_CONNECTOR_ID
                && envelope.operation == MAIL_SEND_OPERATION
                && envelope.effect == FoundationActionEffect::ExternalWrite
                && envelope.resource.resource_type == "draft",
            "Foundation Action is not a canonical Mail send"
        );
        let send: Self = serde_json::from_value(envelope.payload.clone())?;
        send.validate()?;
        anyhow::ensure!(
            envelope.account_id == send.preview.account_id
                && envelope.resource.resource_id == send.preview.draft_id
                && envelope.resource.expected_revision.as_deref()
                    == Some(send.preview.draft_revision.to_string().as_str())
                && envelope.idempotency_key == send.preview.idempotency_key
                && envelope.preview.summary == mail_send_risk_summary(&send.preview)
                && envelope.preview.details == mail_send_preview_details(&send.preview),
            "canonical Mail send binding is invalid"
        );
        Ok(send)
    }
}

pub fn mail_send_risk_summary(preview: &SendPreview) -> String {
    let recipients = preview
        .to
        .iter()
        .chain(&preview.cc)
        .chain(&preview.bcc)
        .map(|address| address.address.as_str())
        .take(8)
        .collect::<Vec<_>>()
        .join(", ");
    format!(
        "Send mail from account {} to {} with subject {:?}",
        preview.account_id, recipients, preview.subject
    )
    .chars()
    .take(1024)
    .collect()
}

fn mail_send_preview_details(preview: &SendPreview) -> Value {
    json!({
        "from": preview.from,
        "to": preview.to,
        "cc": preview.cc,
        "bcc": preview.bcc,
        "subject": preview.subject,
        "bodySha256": preview.body_sha256,
        "attachments": preview.attachments,
        "replyContext": preview.reply_context,
        "forwardContext": preview.forward_context,
        "outboxId": preview.outbox_id,
        "internetMessageId": preview.internet_message_id,
        "previewHash": preview.preview_hash,
    })
}

fn validate_send_preview(preview: &SendPreview) -> anyhow::Result<()> {
    for (value, max, name) in [
        (preview.id.as_str(), 512, "Mail preview id"),
        (preview.account_id.as_str(), 255, "Mail preview account id"),
        (preview.draft_id.as_str(), 512, "Mail preview draft id"),
        (preview.outbox_id.as_str(), 512, "Mail preview outbox id"),
        (
            preview.internet_message_id.as_str(),
            998,
            "Mail preview Message-ID",
        ),
        (
            preview.idempotency_key.as_str(),
            256,
            "Mail preview idempotency key",
        ),
    ] {
        validate_text(value, max, name)?;
    }
    anyhow::ensure!(
        preview.draft_revision > 0,
        "Mail preview revision is invalid"
    );
    validate_sha256(&preview.body_sha256, "Mail body hash")?;
    validate_sha256(&preview.preview_hash, "Mail preview hash")?;
    let recipients = preview.to.len() + preview.cc.len() + preview.bcc.len();
    anyhow::ensure!(
        (1..=MAX_RECIPIENTS).contains(&recipients),
        "Mail preview recipient count is invalid"
    );
    anyhow::ensure!(
        preview.attachments.len() <= MAX_DRAFT_ATTACHMENTS,
        "Mail preview attachment count is invalid"
    );
    let mut total_bytes = 0_u64;
    for attachment in &preview.attachments {
        attachment
            .validate()
            .map_err(|error| anyhow::anyhow!(error.to_string()))?;
        total_bytes = total_bytes.saturating_add(attachment.size_bytes);
    }
    anyhow::ensure!(
        total_bytes <= MAX_DRAFT_ATTACHMENTS_TOTAL_BYTES,
        "Mail preview attachment bytes exceed limit"
    );
    Ok(())
}

fn validate_sha256(value: &str, name: &str) -> anyhow::Result<()> {
    anyhow::ensure!(
        value.len() == 64 && value.bytes().all(|byte| byte.is_ascii_hexdigit()),
        "{name} is invalid"
    );
    Ok(())
}

fn validate_text(value: &str, max: usize, name: &str) -> anyhow::Result<()> {
    anyhow::ensure!(!value.trim().is_empty(), "{name} is required");
    anyhow::ensure!(value.len() <= max, "{name} is too long");
    anyhow::ensure!(
        !value.chars().any(char::is_control),
        "{name} contains control characters"
    );
    Ok(())
}

#[cfg(test)]
#[path = "mail_action_envelope_tests.rs"]
mod tests;
