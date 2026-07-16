use super::*;
use crate::mail::{
    DraftContent, MailAddress, MailDraft, OutgoingBody, ProviderReference, SendPreview,
};

fn address(value: &str) -> MailAddress {
    MailAddress {
        name: None,
        address: value.into(),
    }
}

fn draft() -> MailDraft {
    MailDraft {
        id: "draft-1".into(),
        account_id: "primary".into(),
        revision: 3,
        content: DraftContent {
            to: vec![address("recipient@example.com")],
            cc: vec![],
            bcc: vec![],
            subject: "Status".into(),
            body: OutgoingBody {
                plain_text: "Complete".into(),
                html: None,
            },
            attachments: vec![],
            reply_context: None,
            forward_context: None,
        },
        provider_reference: Some(ProviderReference {
            provider: "imap".into(),
            id: "remote-draft".into(),
        }),
    }
}

fn send_preview() -> SendPreview {
    SendPreview {
        id: "preview-1".into(),
        draft_id: "draft-1".into(),
        draft_revision: 3,
        account_id: "primary".into(),
        from: address("sender@example.com"),
        to: vec![address("recipient@example.com")],
        cc: vec![],
        bcc: vec![],
        subject: "Status".into(),
        body_sha256: "1".repeat(64),
        attachments: vec![crate::mail::DraftAttachment {
            host_attachment_id: Some("00000000-0000-4000-8000-000000000001".into()),
            source_message_id: None,
            source_attachment_id: None,
            file_name: "brief.txt".into(),
            mime_type: "text/plain".into(),
            size_bytes: 16,
            sha256: Some("3".repeat(64)),
        }],
        reply_context: None,
        forward_context: None,
        outbox_id: "outbox-1".into(),
        internet_message_id: "<message@example.com>".into(),
        idempotency_key: "send-1".into(),
        preview_hash: "2".repeat(64),
    }
}

#[test]
fn canonical_draft_binds_exact_content_and_rejects_drift() {
    let mut envelope = CanonicalMailDraftEnvelope::from_draft(draft()).unwrap();
    envelope.content.subject = "Changed".into();
    assert!(envelope.validate().is_err());

    let mut value =
        serde_json::to_value(CanonicalMailDraftEnvelope::from_draft(draft()).unwrap()).unwrap();
    value["approvalId"] = serde_json::json!("unexpected");
    assert!(serde_json::from_value::<CanonicalMailDraftEnvelope>(value).is_err());
}

#[test]
fn canonical_send_round_trips_through_foundation_envelope() {
    let canonical = CanonicalMailSendEnvelope::from_preview(send_preview()).unwrap();
    let envelope = canonical.clone().into_foundation_action().unwrap();
    assert_eq!(envelope.kind, MAIL_SEND_ACTION_KIND);
    assert_eq!(envelope.operation, MAIL_SEND_OPERATION);
    assert_eq!(
        envelope.preview.details["attachments"][0]["fileName"],
        "brief.txt"
    );
    assert_eq!(
        CanonicalMailSendEnvelope::from_foundation_action(&envelope).unwrap(),
        canonical
    );
}

#[test]
fn canonical_send_rejects_cross_field_and_preview_drift() {
    let canonical = CanonicalMailSendEnvelope::from_preview(send_preview()).unwrap();
    let mut envelope = canonical.clone().into_foundation_action().unwrap();
    envelope.account_id = "other".into();
    envelope.payload_sha256 = immutable_arguments_hash(&envelope.payload).unwrap();
    assert!(CanonicalMailSendEnvelope::from_foundation_action(&envelope).is_err());

    let mut drifted = canonical;
    drifted.preview.subject = "Changed".into();
    assert!(drifted.validate().is_err());
}
