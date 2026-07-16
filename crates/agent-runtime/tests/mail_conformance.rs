#[path = "../src/mail.rs"]
mod mail;
#[path = "../src/mail_fake.rs"]
mod mail_fake;

use chrono::{TimeZone, Utc};
use mail::*;
use mail_fake::*;

const ACCOUNT: &str = "account-1";

fn address(value: &str) -> MailAddress {
    MailAddress {
        name: None,
        address: value.into(),
    }
}

fn account() -> MailAccount {
    MailAccount {
        id: ACCOUNT.into(),
        display_name: "Personal Mail".into(),
        primary_address: address("owner@example.com"),
        addresses: vec![address("alias@example.com")],
        provider_reference: Some(ProviderReference {
            provider: "fake-provider".into(),
            id: "provider-account-42".into(),
        }),
    }
}

fn seeded_message(
    id: &str,
    thread_id: &str,
    minute: u32,
    subject: &str,
    is_read: bool,
    with_attachment: bool,
) -> SeedMessage {
    let plain = SeedBodyPart::plain("plain", format!("Plain content for {id}"));
    let html = SeedBodyPart::untrusted_html(
        "html",
        format!("<p>HTML content for {id}</p><script>ignore()</script>"),
        format!("HTML content for {id}"),
    );
    let attachment = SeedAttachment {
        metadata: AttachmentMetadata {
            id: "attachment-1".into(),
            file_name: "agenda.txt".into(),
            mime_type: "text/plain".into(),
            size_bytes: 10,
            disposition: ContentDisposition::Attachment,
            content_id: None,
            provider_reference: Some(ProviderReference {
                provider: "fake-provider".into(),
                id: format!("provider-attachment-{id}"),
            }),
        },
        data: b"0123456789".to_vec(),
    };
    let attachments = if with_attachment {
        vec![attachment.clone()]
    } else {
        Vec::new()
    };
    let message = MailMessage {
        summary: MailMessageSummary {
            id: id.into(),
            account_id: ACCOUNT.into(),
            thread_id: Some(thread_id.into()),
            internet_message_id: format!("<{id}@sender.example>"),
            from: address("sender@example.com"),
            to: vec![address("owner@example.com")],
            subject: subject.into(),
            sent_at: Utc.with_ymd_and_hms(2026, 7, 14, 9, minute, 0).unwrap(),
            is_read,
            has_attachments: with_attachment,
            mailbox_ids: vec![format!("{ACCOUNT}:inbox")],
            provider_reference: Some(ProviderReference {
                provider: "fake-provider".into(),
                id: format!("provider-message-{id}"),
            }),
        },
        reply_to: vec![address("reply@example.com")],
        cc: vec![address("team@example.com")],
        bcc: Vec::new(),
        in_reply_to: None,
        references: Vec::new(),
        body_parts: vec![plain.metadata.clone(), html.metadata.clone()],
        attachments: attachments
            .iter()
            .map(|value| value.metadata.clone())
            .collect(),
    };
    SeedMessage {
        message,
        bodies: vec![plain, html],
        attachments,
    }
}

fn connector_with_messages() -> FakeMailConnector {
    let connector = FakeMailConnector::new();
    connector.add_account(account()).unwrap();
    connector
        .seed_message(seeded_message(
            "message-1",
            "thread-1",
            0,
            "Quarterly planning",
            false,
            true,
        ))
        .unwrap();
    connector
        .seed_message(seeded_message(
            "message-2",
            "thread-1",
            5,
            "Re: Quarterly planning",
            true,
            false,
        ))
        .unwrap();
    connector
        .seed_message(seeded_message(
            "message-3",
            "thread-2",
            10,
            "Travel details",
            false,
            false,
        ))
        .unwrap();
    connector
}

fn empty_draft_content() -> DraftContent {
    DraftContent {
        to: vec![address("recipient@example.com")],
        cc: Vec::new(),
        bcc: Vec::new(),
        subject: "Status update".into(),
        body: OutgoingBody {
            plain_text: "Here is the status update.".into(),
            html: Some("<p>Here is the status update.</p>".into()),
        },
        attachments: vec![DraftAttachment {
            host_attachment_id: None,
            source_message_id: Some("message-1".into()),
            source_attachment_id: Some("attachment-1".into()),
            file_name: "agenda.txt".into(),
            mime_type: "text/plain".into(),
            size_bytes: 10,
            sha256: None,
        }],
        reply_context: None,
        forward_context: None,
    }
}

async fn create_sendable_draft(connector: &FakeMailConnector) -> MailDraft {
    let draft = connector
        .create_draft(CreateDraftRequest {
            account_id: ACCOUNT.into(),
            content: empty_draft_content(),
        })
        .await
        .unwrap();
    let fetched = connector
        .get_draft(GetDraftRequest {
            account_id: ACCOUNT.into(),
            draft_id: draft.id.clone(),
        })
        .await
        .unwrap();
    assert_eq!(fetched, draft);
    draft
}

#[tokio::test]
async fn accounts_mailboxes_and_provider_ids_are_preserved() {
    let connector = connector_with_messages();
    let accounts = connector.list_accounts().await.unwrap();
    assert_eq!(accounts.len(), 1);
    assert_eq!(
        accounts[0].provider_reference.as_ref().unwrap().id,
        "provider-account-42"
    );
    let status = connector.account_status(ACCOUNT).await.unwrap();
    assert_eq!(status.state, MailAccountState::Connected);
    assert_eq!(status.account.id, ACCOUNT);
    let disconnected = connector
        .disconnect(MailAccountActionRequest {
            account_id: ACCOUNT.into(),
        })
        .await
        .unwrap();
    assert_eq!(disconnected.state, MailAccountState::AuthenticationRequired);
    let connected = connector
        .request_connect(MailAccountActionRequest {
            account_id: ACCOUNT.into(),
        })
        .await
        .unwrap();
    assert_eq!(connected.state, MailAccountState::Connected);

    let mailboxes = connector.list_mailboxes(ACCOUNT).await.unwrap();
    assert!(
        mailboxes
            .iter()
            .any(|mailbox| mailbox.role == MailboxRole::Inbox)
    );
    assert!(
        mailboxes
            .iter()
            .any(|mailbox| mailbox.role == MailboxRole::Sent)
    );

    let message = connector
        .get_message(GetMessageRequest {
            account_id: ACCOUNT.into(),
            message_id: "message-1".into(),
        })
        .await
        .unwrap();
    assert_eq!(
        message.summary.provider_reference.unwrap().id,
        "provider-message-message-1"
    );
    assert_eq!(
        message.attachments[0]
            .provider_reference
            .as_ref()
            .unwrap()
            .provider,
        "fake-provider"
    );
}

#[tokio::test]
async fn pagination_search_and_thread_views_are_bounded_and_vendor_neutral() {
    let connector = connector_with_messages();
    let first = connector
        .search_messages(SearchMessagesRequest {
            account_id: ACCOUNT.into(),
            mailbox_id: Some(format!("{ACCOUNT}:inbox")),
            search: MailSearch::default(),
            page: PageRequest {
                cursor: None,
                limit: 2,
            },
        })
        .await
        .unwrap();
    assert_eq!(first.items.len(), 2);
    let second = connector
        .search_messages(SearchMessagesRequest {
            account_id: ACCOUNT.into(),
            mailbox_id: Some(format!("{ACCOUNT}:inbox")),
            search: MailSearch::default(),
            page: PageRequest {
                cursor: first.next_cursor,
                limit: 2,
            },
        })
        .await
        .unwrap();
    assert_eq!(second.items.len(), 1);
    assert!(second.next_cursor.is_none());

    let filtered = connector
        .search_messages(SearchMessagesRequest {
            account_id: ACCOUNT.into(),
            mailbox_id: None,
            search: MailSearch {
                subject: Some("travel".into()),
                is_read: Some(false),
                ..MailSearch::default()
            },
            page: PageRequest::default(),
        })
        .await
        .unwrap();
    assert_eq!(filtered.items[0].id, "message-3");

    let threads = connector
        .list_threads(ListThreadsRequest {
            account_id: ACCOUNT.into(),
            mailbox_id: None,
            page: PageRequest::default(),
        })
        .await
        .unwrap();
    assert_eq!(threads.items.len(), 2);
    assert_eq!(
        threads
            .items
            .iter()
            .find(|thread| thread.id == "thread-1")
            .unwrap()
            .message_ids
            .len(),
        2
    );
    let thread = connector
        .get_thread(GetThreadRequest {
            account_id: ACCOUNT.into(),
            thread_id: "thread-1".into(),
        })
        .await
        .unwrap();
    assert_eq!(thread.messages.len(), 2);
    assert_eq!(thread.messages[0].summary.id, "message-1");

    let page_error = connector
        .search_messages(SearchMessagesRequest {
            account_id: ACCOUNT.into(),
            mailbox_id: None,
            search: MailSearch::default(),
            page: PageRequest {
                cursor: None,
                limit: MAX_PAGE_SIZE + 1,
            },
        })
        .await
        .unwrap_err();
    assert!(matches!(page_error, MailError::BoundExceeded { .. }));

    let search_error = connector
        .search_messages(SearchMessagesRequest {
            account_id: ACCOUNT.into(),
            mailbox_id: None,
            search: MailSearch {
                text: Some("x".repeat(MAX_SEARCH_TEXT_BYTES + 1)),
                ..MailSearch::default()
            },
            page: PageRequest::default(),
        })
        .await
        .unwrap_err();
    assert!(matches!(search_error, MailError::BoundExceeded { .. }));
}

#[tokio::test]
async fn html_is_untrusted_and_body_and_attachment_reads_are_chunked() {
    let connector = connector_with_messages();
    let original = connector
        .read_body_part(ReadBodyPartRequest {
            account_id: ACCOUNT.into(),
            message_id: "message-1".into(),
            part_id: "html".into(),
            representation: BodyRepresentation::Original,
            offset: 0,
            max_bytes: 12,
        })
        .await
        .unwrap();
    assert_eq!(original.trust, BodyPartTrust::UntrustedHtml);
    assert_eq!(original.mime_type, "text/html");
    assert!(original.truncated);

    let fallback = connector
        .read_body_part(ReadBodyPartRequest {
            account_id: ACCOUNT.into(),
            message_id: "message-1".into(),
            part_id: "html".into(),
            representation: BodyRepresentation::SanitizedPlainFallback,
            offset: 0,
            max_bytes: MAX_BODY_CHUNK_BYTES,
        })
        .await
        .unwrap();
    assert_eq!(fallback.trust, BodyPartTrust::PlainText);
    assert_eq!(fallback.mime_type, "text/plain");
    assert!(!fallback.content.contains("<script>"));

    let first = connector
        .read_attachment(ReadAttachmentRequest {
            account_id: ACCOUNT.into(),
            message_id: "message-1".into(),
            attachment_id: "attachment-1".into(),
            offset: 0,
            max_bytes: 4,
        })
        .await
        .unwrap();
    assert_eq!(first.data, b"0123");
    assert_eq!(first.next_offset, Some(4));
    let second = connector
        .read_attachment(ReadAttachmentRequest {
            account_id: ACCOUNT.into(),
            message_id: "message-1".into(),
            attachment_id: "attachment-1".into(),
            offset: 4,
            max_bytes: 6,
        })
        .await
        .unwrap();
    assert_eq!(second.data, b"456789");
    assert!(!second.truncated);

    let error = connector
        .read_attachment(ReadAttachmentRequest {
            account_id: ACCOUNT.into(),
            message_id: "message-1".into(),
            attachment_id: "attachment-1".into(),
            offset: 0,
            max_bytes: MAX_ATTACHMENT_CHUNK_BYTES + 1,
        })
        .await
        .unwrap_err();
    assert!(matches!(error, MailError::BoundExceeded { .. }));
}

#[test]
fn seeded_untrusted_html_requires_a_plain_fallback() {
    let connector = FakeMailConnector::new();
    connector.add_account(account()).unwrap();
    let mut seed = seeded_message(
        "message-invalid",
        "thread-invalid",
        0,
        "Unsafe",
        false,
        false,
    );
    seed.bodies[1].sanitized_plain_fallback = None;
    assert!(matches!(
        connector.seed_message(seed),
        Err(MailError::InvalidRequest(_))
    ));
}

#[tokio::test]
async fn read_state_archive_and_move_mutate_only_selected_message() {
    let connector = connector_with_messages();
    connector
        .add_mailbox(Mailbox {
            id: format!("{ACCOUNT}:project"),
            account_id: ACCOUNT.into(),
            name: "Project".into(),
            role: MailboxRole::Custom,
            provider_reference: None,
        })
        .unwrap();
    let read = connector
        .set_read_state(SetReadStateRequest {
            account_id: ACCOUNT.into(),
            message_id: "message-1".into(),
            is_read: true,
        })
        .await
        .unwrap();
    assert!(read.is_read);

    let archived = connector
        .archive_message(ArchiveMessageRequest {
            account_id: ACCOUNT.into(),
            message_id: "message-1".into(),
        })
        .await
        .unwrap();
    assert!(!archived.mailbox_ids.contains(&format!("{ACCOUNT}:inbox")));
    assert!(archived.mailbox_ids.contains(&format!("{ACCOUNT}:archive")));

    let moved = connector
        .move_message(MoveMessageRequest {
            account_id: ACCOUNT.into(),
            message_id: "message-1".into(),
            from_mailbox_id: Some(format!("{ACCOUNT}:archive")),
            to_mailbox_id: format!("{ACCOUNT}:project"),
        })
        .await
        .unwrap();
    assert_eq!(moved.mailbox_ids, vec![format!("{ACCOUNT}:project")]);
    let untouched = connector
        .get_message(GetMessageRequest {
            account_id: ACCOUNT.into(),
            message_id: "message-2".into(),
        })
        .await
        .unwrap();
    assert!(
        untouched
            .summary
            .mailbox_ids
            .contains(&format!("{ACCOUNT}:inbox"))
    );
}

#[tokio::test]
async fn draft_updates_use_revision_cas_and_delete_requires_matching_approval() {
    let connector = connector_with_messages();
    let draft = create_sendable_draft(&connector).await;
    assert_eq!(draft.revision, 1);
    let mut content = draft.content.clone();
    content.subject = "Updated subject".into();
    let updated = connector
        .update_draft(UpdateDraftRequest {
            account_id: ACCOUNT.into(),
            draft_id: draft.id.clone(),
            expected_revision: 1,
            content: content.clone(),
        })
        .await
        .unwrap();
    assert_eq!(updated.revision, 2);

    let conflict = connector
        .update_draft(UpdateDraftRequest {
            account_id: ACCOUNT.into(),
            draft_id: draft.id.clone(),
            expected_revision: 1,
            content,
        })
        .await
        .unwrap_err();
    assert_eq!(
        conflict,
        MailError::RevisionConflict {
            expected: 1,
            actual: 2
        }
    );

    let wrong = connector
        .delete_draft(DeleteDraftRequest {
            account_id: ACCOUNT.into(),
            draft_id: draft.id.clone(),
            expected_revision: 2,
            approval: MailApprovalGrant {
                approval_id: "approval-delete".into(),
                operation: MailApprovalOperation::SendDraft,
                resource_id: draft.id.clone(),
                revision: 2,
                preview_hash: None,
            },
        })
        .await
        .unwrap_err();
    assert_eq!(wrong, MailError::ApprovalMismatch);

    connector
        .delete_draft(DeleteDraftRequest {
            account_id: ACCOUNT.into(),
            draft_id: draft.id.clone(),
            expected_revision: 2,
            approval: MailApprovalGrant {
                approval_id: "approval-delete".into(),
                operation: MailApprovalOperation::DeleteDraft,
                resource_id: draft.id,
                revision: 2,
                preview_hash: None,
            },
        })
        .await
        .unwrap();
}

#[tokio::test]
async fn reply_and_forward_drafts_preserve_context_without_provider_workflow_ids() {
    let connector = connector_with_messages();
    let reply = connector
        .create_reply_draft(CreateReplyDraftRequest {
            account_id: ACCOUNT.into(),
            message_id: "message-1".into(),
            reply_all: true,
        })
        .await
        .unwrap();
    assert_eq!(reply.content.to[0].address, "reply@example.com");
    assert!(reply.content.subject.starts_with("Re:"));
    assert_eq!(
        reply.content.reply_context.as_ref().unwrap().message_id,
        "message-1"
    );
    assert!(reply.provider_reference.is_none());

    let forward = connector
        .create_forward_draft(CreateForwardDraftRequest {
            account_id: ACCOUNT.into(),
            message_id: "message-1".into(),
        })
        .await
        .unwrap();
    assert!(forward.content.subject.starts_with("Fwd:"));
    assert_eq!(
        forward.content.attachments[0]
            .source_attachment_id
            .as_deref(),
        Some("attachment-1")
    );
    assert_eq!(
        forward.content.forward_context.as_ref().unwrap().message_id,
        "message-1"
    );
}

#[tokio::test]
async fn send_preview_is_complete_stable_and_bound_to_draft_revision() {
    let connector = connector_with_messages();
    let draft = create_sendable_draft(&connector).await;
    let request = PreviewSendRequest {
        account_id: ACCOUNT.into(),
        draft_id: draft.id.clone(),
        expected_revision: draft.revision,
        idempotency_key: "send-operation-1".into(),
    };
    let first = connector.preview_send(request.clone()).await.unwrap();
    let second = connector.preview_send(request).await.unwrap();
    assert_eq!(first, second);
    assert_eq!(first.account_id, ACCOUNT);
    assert_eq!(first.from.address, "owner@example.com");
    assert_eq!(first.to[0].address, "recipient@example.com");
    assert_eq!(first.subject, "Status update");
    assert_eq!(first.body_sha256.len(), 64);
    assert_eq!(first.preview_hash.len(), 64);
    assert_eq!(first.attachments.len(), 1);
    assert!(first.internet_message_id.starts_with('<'));
    assert!(first.internet_message_id.ends_with("@agentweave.local>"));

    let mut changed = draft.content;
    changed.subject = "Changed after preview".into();
    let updated = connector
        .update_draft(UpdateDraftRequest {
            account_id: ACCOUNT.into(),
            draft_id: draft.id.clone(),
            expected_revision: 1,
            content: changed,
        })
        .await
        .unwrap();
    let conflict = connector
        .preview_send(PreviewSendRequest {
            account_id: ACCOUNT.into(),
            draft_id: updated.id,
            expected_revision: updated.revision,
            idempotency_key: "send-operation-1".into(),
        })
        .await
        .unwrap_err();
    assert_eq!(conflict, MailError::IdempotencyConflict);
}

#[tokio::test]
async fn duplicate_approval_and_idempotency_submit_and_deliver_once() {
    let connector = connector_with_messages();
    let draft = create_sendable_draft(&connector).await;
    let preview = connector
        .preview_send(PreviewSendRequest {
            account_id: ACCOUNT.into(),
            draft_id: draft.id,
            expected_revision: draft.revision,
            idempotency_key: "send-once".into(),
        })
        .await
        .unwrap();
    let request = ApprovedSendRequest {
        preview_id: preview.id.clone(),
        approval: preview.approval_grant("approval-send"),
    };
    let first = connector.send_approved(request.clone()).await.unwrap();
    let second = connector.send_approved(request).await.unwrap();
    assert_eq!(first, second);
    assert_eq!(first.state, DeliveryState::Delivered);
    assert_eq!(connector.provider_submission_count(), 1);
    assert_eq!(connector.logical_delivery_count(), 1);

    let stored = connector
        .get_message(GetMessageRequest {
            account_id: ACCOUNT.into(),
            message_id: first.message_id.clone(),
        })
        .await
        .unwrap();
    assert_eq!(
        stored.summary.internet_message_id,
        preview.internet_message_id
    );
    assert!(
        stored
            .summary
            .mailbox_ids
            .contains(&format!("{ACCOUNT}:sent"))
    );
}

#[tokio::test]
async fn send_requires_approval_for_the_exact_preview_hash() {
    let connector = connector_with_messages();
    let draft = create_sendable_draft(&connector).await;
    let preview = connector
        .preview_send(PreviewSendRequest {
            account_id: ACCOUNT.into(),
            draft_id: draft.id,
            expected_revision: draft.revision,
            idempotency_key: "approval-binding".into(),
        })
        .await
        .unwrap();
    let mut approval = preview.approval_grant("approval-send");
    approval.preview_hash = Some("different-preview".into());
    let error = connector
        .send_approved(ApprovedSendRequest {
            preview_id: preview.id,
            approval,
        })
        .await
        .unwrap_err();
    assert_eq!(error, MailError::ApprovalMismatch);
    assert_eq!(connector.provider_submission_count(), 0);
}

#[tokio::test]
async fn delivery_states_are_explicit_and_uncertain_forbids_blind_retry() {
    for state in [DeliveryState::Rejected, DeliveryState::Deferred] {
        let connector = connector_with_messages();
        connector.queue_delivery_outcome(state);
        let draft = create_sendable_draft(&connector).await;
        let preview = connector
            .preview_send(PreviewSendRequest {
                account_id: ACCOUNT.into(),
                draft_id: draft.id,
                expected_revision: draft.revision,
                idempotency_key: format!("outcome-{state:?}"),
            })
            .await
            .unwrap();
        let receipt = connector
            .send_approved(ApprovedSendRequest {
                preview_id: preview.id.clone(),
                approval: preview.approval_grant("approval-send"),
            })
            .await
            .unwrap();
        assert_eq!(receipt.state, state);
    }

    let connector = connector_with_messages();
    connector.queue_delivery_outcome(DeliveryState::Uncertain);
    let draft = create_sendable_draft(&connector).await;
    let preview = connector
        .preview_send(PreviewSendRequest {
            account_id: ACCOUNT.into(),
            draft_id: draft.id.clone(),
            expected_revision: draft.revision,
            idempotency_key: "uncertain-send".into(),
        })
        .await
        .unwrap();
    let approved = ApprovedSendRequest {
        preview_id: preview.id.clone(),
        approval: preview.approval_grant("approval-send"),
    };
    let first = connector.send_approved(approved.clone()).await.unwrap();
    let replay = connector.send_approved(approved).await.unwrap();
    assert_eq!(first, replay);
    assert_eq!(first.state, DeliveryState::Uncertain);
    assert!(first.state.requires_reconciliation());
    assert!(!first.state.permits_blind_retry());
    assert_eq!(connector.provider_submission_count(), 1);
    assert_eq!(connector.logical_delivery_count(), 0);

    let status = connector
        .delivery_status(DeliveryStatusRequest {
            account_id: ACCOUNT.into(),
            outbox_id: first.outbox_id.clone(),
        })
        .await
        .unwrap();
    assert_eq!(status, first);

    let error = connector
        .preview_send(PreviewSendRequest {
            account_id: ACCOUNT.into(),
            draft_id: draft.id,
            expected_revision: draft.revision,
            idempotency_key: "blind-retry".into(),
        })
        .await
        .unwrap_err();
    assert_eq!(
        error,
        MailError::ReconciliationRequired {
            outbox_id: first.outbox_id
        }
    );
}
