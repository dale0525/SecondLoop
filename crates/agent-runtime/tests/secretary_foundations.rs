use agent_runtime::approval::{ApprovalBinding, ApprovalDecision, ApprovalRisk};
use agent_runtime::connector::{ConnectorRuntime, connector_action_hash};
use agent_runtime::connector_tools::{ConnectorToolRuntime, EphemeralConnectorContextProvider};
use agent_runtime::credential::CredentialScope;
use agent_runtime::durable_run::{DurableRunStore, QueueActionRequest, RunScope, RunStatus};
use agent_runtime::foundation_action_envelope::FoundationActionEnvelope;
use agent_runtime::foundation_actions::MailActionService;
use agent_runtime::mail::*;
use agent_runtime::mail_action_envelope::{CanonicalMailSendEnvelope, MAIL_SEND_ACTION_KIND};
use agent_runtime::mail_connector_transport::{MAIL_CONNECTOR_ID, MailConnectorTransport};
use agent_runtime::mail_fake::{FakeMailConnector, SeedBodyPart, SeedMessage};
use agent_runtime::memory::*;
use agent_runtime::memory_sqlite::SqliteMemoryProvider;
use agent_runtime::storage::Storage;
use chrono::{Duration, Utc};
use serde_json::json;
use std::collections::BTreeSet;
use std::sync::Arc;
use tempfile::TempDir;

fn memory_scope() -> MemoryScope {
    MemoryScope::new("com.example.secretary-agent", "local", "local-user").unwrap()
}

fn memory_draft() -> MemoryDraft {
    MemoryDraft {
        kind: MemoryKind::parse(MemoryKind::PREFERENCE).unwrap(),
        value: MemoryValue::new("会议默认安排在下午").unwrap(),
        evidence: vec![MemoryEvidence {
            source: MemoryEvidenceSource::ExplicitUserAction,
            source_id: Some("session-1:turn-1".into()),
            excerpt: Some("以后默认把会议安排在下午".into()),
            observed_at: Utc::now(),
        }],
        confidence: MemoryConfidence::from_basis_points(10_000).unwrap(),
        sensitivity: MemorySensitivity::Personal,
        retention: MemoryRetention::Persistent,
        conflict_key: Some("meeting-time-preference".into()),
        supersedes: None,
    }
}

fn address(name: &str, address: &str) -> MailAddress {
    MailAddress {
        name: Some(name.into()),
        address: address.into(),
    }
}

fn seeded_mail() -> Arc<FakeMailConnector> {
    let connector = Arc::new(FakeMailConnector::new());
    connector
        .add_account(MailAccount {
            id: "primary".into(),
            display_name: "工作邮箱".into(),
            primary_address: address("用户", "owner@example.test"),
            addresses: Vec::new(),
            provider_reference: None,
        })
        .unwrap();
    let body = SeedBodyPart::plain("plain", "请确认周四项目评审是否可以安排在下午三点。");
    connector
        .seed_message(SeedMessage {
            message: MailMessage {
                summary: MailMessageSummary {
                    id: "message-1".into(),
                    account_id: "primary".into(),
                    thread_id: Some("thread-1".into()),
                    internet_message_id: "<message-1@example.test>".into(),
                    from: address("项目负责人", "lead@example.test"),
                    to: vec![address("用户", "owner@example.test")],
                    subject: "项目评审时间".into(),
                    sent_at: Utc::now(),
                    is_read: false,
                    has_attachments: false,
                    mailbox_ids: vec!["primary:inbox".into()],
                    provider_reference: None,
                },
                reply_to: Vec::new(),
                cc: Vec::new(),
                bcc: Vec::new(),
                in_reply_to: None,
                references: Vec::new(),
                body_parts: vec![body.metadata.clone()],
                attachments: Vec::new(),
            },
            bodies: vec![body],
            attachments: Vec::new(),
        })
        .unwrap();
    connector
}

async fn connector_tools(
    mail: Arc<FakeMailConnector>,
) -> (ConnectorToolRuntime, Arc<EphemeralConnectorContextProvider>) {
    let runtime = Arc::new(ConnectorRuntime::new(None, 256 * 1024).unwrap());
    runtime
        .register(
            MailConnectorTransport::descriptor("Fake Mail", true),
            Arc::new(MailConnectorTransport::new(mail)),
        )
        .await
        .unwrap();
    let context = Arc::new(
        EphemeralConnectorContextProvider::fail_closed(
            CredentialScope {
                app_id: "com.example.secretary-agent".into(),
                tenant_id: "local".into(),
                user_id: "local-user".into(),
            },
            std::time::Duration::from_secs(2),
        )
        .unwrap(),
    );
    (
        ConnectorToolRuntime::load(runtime, context.clone()).unwrap(),
        context,
    )
}

#[tokio::test]
async fn remember_read_draft_approve_and_send_exactly_once() {
    let directory = TempDir::new().unwrap();
    let memory_url = format!(
        "sqlite://{}?mode=rwc",
        directory.path().join("memory.db").display()
    );
    let memory = SqliteMemoryProvider::connect(&memory_url).await.unwrap();
    let proposal = memory
        .propose(memory_scope(), memory_draft())
        .await
        .unwrap();
    let committed = memory
        .confirm(memory_scope(), proposal.record.id, proposal.record.version)
        .await
        .unwrap();
    assert_eq!(committed.record.state, MemoryState::Committed);
    let recalled = memory
        .pre_turn_recall(MemoryRecallRequest {
            scope: memory_scope(),
            query: "下午".into(),
            kinds: BTreeSet::new(),
            limit: 5,
        })
        .await
        .unwrap();
    assert_eq!(recalled.len(), 1);

    let mail = seeded_mail();
    let (tools, context) = connector_tools(mail.clone()).await;
    let thread = tools
        .execute(
            "mail_thread_get",
            "call-read",
            json!({"accountId": "primary", "threadId": "thread-1"}),
        )
        .await
        .unwrap();
    assert_eq!(
        thread["output"]["messages"][0]["summary"]["id"],
        "message-1"
    );

    let draft_arguments = json!({
        "accountId": "primary",
        "content": {
            "to": [{"name": "项目负责人", "address": "lead@example.test"}],
            "cc": [],
            "bcc": [],
            "subject": "Re: 项目评审时间",
            "body": {"plainText": "可以，按我的偏好安排在周四下午三点。", "html": null},
            "attachments": [],
            "replyContext": {
                "messageId": "message-1",
                "internetMessageId": "<message-1@example.test>",
                "threadId": "thread-1"
            },
            "forwardContext": null
        }
    });
    let draft = tools
        .execute("mail_draft_create", "call-draft", draft_arguments)
        .await
        .unwrap();
    let draft_id = draft["output"]["id"].as_str().unwrap();
    let preview = tools
        .execute(
            "mail_send_preview",
            "call-preview",
            json!({
                "accountId": "primary",
                "draftId": draft_id,
                "expectedRevision": 1,
                "idempotencyKey": "secretary-e2e-send-1"
            }),
        )
        .await
        .unwrap();
    let preview: SendPreview = serde_json::from_value(preview["output"].clone()).unwrap();

    let run_url = format!(
        "sqlite://{}?mode=rwc",
        directory.path().join("runs.db").display()
    );
    let store = DurableRunStore::connect(&run_url).await.unwrap();
    let now = Utc::now();
    let run = store
        .create_run(
            RunScope {
                app_id: "com.example.secretary-agent".into(),
                agent_id: "secretary".into(),
                tenant_id: "local".into(),
                user_id: "local-user".into(),
                session_id: Some("session-1".into()),
            },
            "Send the reviewed reply",
            now,
        )
        .await
        .unwrap();
    assert!(
        store
            .transition_run(&run.run_id, 1, RunStatus::Running, json!({}), now)
            .await
            .unwrap()
    );
    let step = store
        .add_step(&run.run_id, 0, "mail_send", json!({}), now)
        .await
        .unwrap();
    let action_arguments = json!({
        "previewId": preview.id,
        "previewHash": preview.preview_hash,
        "accountId": preview.account_id,
        "draftId": preview.draft_id,
        "draftRevision": preview.draft_revision
    });
    let action = store
        .queue_action(
            QueueActionRequest {
                run_id: &run.run_id,
                step_id: &step.step_id,
                action_name: "mail_send",
                arguments: action_arguments,
                resource_target: "mail-account:primary",
                idempotency_key: &preview.idempotency_key,
                approval_required: true,
            },
            now,
        )
        .await
        .unwrap();
    let binding = ApprovalBinding {
        actor_id: "local-user".into(),
        app_id: "com.example.secretary-agent".into(),
        run_id: run.run_id,
        action_id: action.action_id.clone(),
        action_name: action.action_name.clone(),
        arguments_sha256: action.arguments_sha256.clone(),
        resource_target: action.resource_target.clone(),
        policy_version: "secretary-policy-v1".into(),
        risk: ApprovalRisk::ExternalWrite,
        risk_summary: "从工作邮箱向项目负责人发送一封回复".into(),
        session_id: Some("session-1".into()),
        expires_at: now + Duration::minutes(10),
    };
    let approval = store.request_approval(binding.clone(), now).await.unwrap();
    assert!(
        store
            .bind_action_approval(&action.action_id, &approval.approval_id, now)
            .await
            .unwrap()
    );
    store
        .resolve_approval(
            &approval.approval_id,
            ApprovalDecision::ApproveOnce,
            "local-user",
            now,
        )
        .await
        .unwrap();
    assert!(
        store
            .consume_approval(&approval.approval_id, &binding, now)
            .await
            .unwrap()
    );

    let send_arguments = serde_json::to_value(ApprovedSendRequest {
        preview_id: preview.id.clone(),
        approval: preview.approval_grant(approval.approval_id),
    })
    .unwrap();
    let action_hash =
        connector_action_hash(MAIL_CONNECTOR_ID, "mail_send", &send_arguments).unwrap();
    context
        .grant_once(&action_hash, preview.idempotency_key.clone())
        .unwrap();
    let first = tools
        .execute("mail_send", "call-send-1", send_arguments.clone())
        .await
        .unwrap();
    assert_eq!(first["replayed"], false);
    assert_eq!(first["output"]["state"], "delivered");

    context
        .grant_once(&action_hash, preview.idempotency_key)
        .unwrap();
    let resumed = tools
        .execute("mail_send", "call-send-2", send_arguments)
        .await
        .unwrap();
    assert_eq!(resumed["replayed"], true);
    assert_eq!(mail.provider_submission_count(), 1);
    assert_eq!(mail.logical_delivery_count(), 1);
}

#[tokio::test]
async fn trusted_host_mail_approval_survives_restart_and_resumes_once() {
    let directory = TempDir::new().unwrap();
    let database_url = format!(
        "sqlite://{}?mode=rwc",
        directory.path().join("framework.db").display()
    );
    let storage = Storage::connect(&database_url).await.unwrap();
    let mail = seeded_mail();
    let (tools, context) = connector_tools(mail.clone()).await;
    let draft = tools
        .execute(
            "mail_draft_create",
            "durable-draft",
            json!({
                "accountId": "primary",
                "content": {
                    "to": [{"name": "项目负责人", "address": "lead@example.test"}],
                    "cc": [],
                    "bcc": [],
                    "subject": "Re: 项目评审时间",
                    "body": {"plainText": "周四下午三点可以。", "html": null},
                    "attachments": [],
                    "replyContext": null,
                    "forwardContext": null
                }
            }),
        )
        .await
        .unwrap();
    let preview = tools
        .execute(
            "mail_send_preview",
            "durable-preview",
            json!({
                "accountId": "primary",
                "draftId": draft["output"]["id"],
                "expectedRevision": 1,
                "idempotencyKey": "host-durable-send-1"
            }),
        )
        .await
        .unwrap();
    let preview: SendPreview = serde_json::from_value(preview["output"].clone()).unwrap();
    let service = MailActionService::new(
        &storage,
        tools,
        context,
        CredentialScope {
            app_id: "com.example.secretary-agent".into(),
            tenant_id: "local".into(),
            user_id: "local-user".into(),
        },
        "test-policy-v1",
    )
    .await
    .unwrap();
    let pending = service
        .request_send(preview, Some("session-1".into()), Utc::now())
        .await
        .unwrap();
    assert_eq!(pending.action.action_name, MAIL_SEND_ACTION_KIND);
    let canonical = FoundationActionEnvelope::from_action(&pending.action).unwrap();
    CanonicalMailSendEnvelope::from_foundation_action(&canonical).unwrap();
    assert_eq!(
        pending.action.status,
        agent_runtime::durable_run::ActionStatus::WaitingApproval
    );
    assert_eq!(service.list_actions().await.unwrap().len(), 1);

    drop(service);
    let (resumed_tools, resumed_context) = connector_tools(mail.clone()).await;
    let resumed = MailActionService::new(
        &storage,
        resumed_tools,
        resumed_context,
        CredentialScope {
            app_id: "com.example.secretary-agent".into(),
            tenant_id: "local".into(),
            user_id: "local-user".into(),
        },
        "test-policy-v1",
    )
    .await
    .unwrap();
    let completed = resumed
        .resolve(
            &pending.approval.approval_id,
            ApprovalDecision::ApproveOnce,
            "local-user",
            Utc::now(),
        )
        .await
        .unwrap();
    assert_eq!(
        completed.action.status,
        agent_runtime::durable_run::ActionStatus::Succeeded
    );
    assert_eq!(
        completed.action.result.as_ref().unwrap()["state"],
        "delivered"
    );
    let replay = resumed
        .resolve(
            &pending.approval.approval_id,
            ApprovalDecision::ApproveOnce,
            "local-user",
            Utc::now(),
        )
        .await
        .unwrap();
    assert_eq!(
        replay.action.status,
        agent_runtime::durable_run::ActionStatus::Succeeded
    );
    assert_eq!(mail.provider_submission_count(), 1);
    assert_eq!(mail.logical_delivery_count(), 1);
}
