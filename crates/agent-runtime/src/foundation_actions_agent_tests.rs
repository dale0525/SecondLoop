use super::*;
use crate::connector::ConnectorRuntime;
use crate::connector_tools::EphemeralConnectorContextProvider;
use crate::mail::{CreateDraftRequest, DraftContent, MailAccount, MailAddress, OutgoingBody};
use crate::mail_connector_transport::MailConnectorTransport;
use crate::mail_fake::FakeMailConnector;
use serde_json::json;
use std::time::Duration as StdDuration;

#[test]
fn agent_preview_request_rejects_runtime_owned_parameters() {
    let valid = json!({
        "accountId": "primary",
        "draftId": "draft-1",
        "expectedRevision": 1
    });
    assert!(serde_json::from_value::<AgentMailSendPreviewRequest>(valid).is_ok());

    for forbidden in ["sessionId", "turnId", "idempotencyKey", "approvalId"] {
        let mut invalid = json!({
            "accountId": "primary",
            "draftId": "draft-1",
            "expectedRevision": 1
        });
        invalid[forbidden] = json!("attacker-controlled");
        assert!(
            serde_json::from_value::<AgentMailSendPreviewRequest>(invalid).is_err(),
            "{forbidden} must remain Runtime-owned"
        );
    }
}

#[test]
fn trusted_turn_context_requires_session_and_turn_ids() {
    assert!(FoundationActionTurnContext::new("", "turn-1").is_err());
    assert!(FoundationActionTurnContext::new("session-1", " ").is_err());
    let context = FoundationActionTurnContext::new("session-1", "turn-1").unwrap();
    assert_eq!(context.session_id(), "session-1");
    assert_eq!(context.turn_id(), "turn-1");
}

#[tokio::test]
async fn agent_preview_creates_stable_session_bound_action_without_sending() {
    let storage = Storage::connect("sqlite::memory:").await.unwrap();
    let mail = Arc::new(FakeMailConnector::new());
    mail.add_account(MailAccount {
        id: "primary".into(),
        display_name: "Work Mail".into(),
        primary_address: MailAddress {
            name: Some("Local User".into()),
            address: "local@example.test".into(),
        },
        addresses: Vec::new(),
        provider_reference: None,
    })
    .unwrap();
    let runtime = Arc::new(ConnectorRuntime::new(None, 256 * 1024).unwrap());
    runtime
        .register(
            MailConnectorTransport::descriptor("Fake Mail", true),
            Arc::new(MailConnectorTransport::new(mail.clone())),
        )
        .await
        .unwrap();
    let scope = CredentialScope {
        app_id: "com.example.agent".into(),
        tenant_id: "tenant-1".into(),
        user_id: "user-1".into(),
    };
    let provider = Arc::new(
        EphemeralConnectorContextProvider::fail_closed(scope.clone(), StdDuration::from_secs(5))
            .unwrap(),
    );
    let tools = ConnectorToolRuntime::load(runtime, provider.clone()).unwrap();
    let draft = tools
        .execute_trusted_host_action(
            "mail_draft_create",
            "create-draft",
            serde_json::to_value(CreateDraftRequest {
                account_id: "primary".into(),
                content: DraftContent {
                    to: vec![MailAddress {
                        name: Some("Recipient".into()),
                        address: "recipient@example.test".into(),
                    }],
                    cc: Vec::new(),
                    bcc: Vec::new(),
                    subject: "Runtime approval".into(),
                    body: OutgoingBody {
                        plain_text: "Please review".into(),
                        html: None,
                    },
                    attachments: Vec::new(),
                    reply_context: None,
                    forward_context: None,
                },
            })
            .unwrap(),
        )
        .await
        .unwrap();
    let draft_id = draft["output"]["id"].as_str().unwrap().to_string();
    let service = MailActionService::new(&storage, tools, provider, scope, "agent-preview-test-v1")
        .await
        .unwrap();
    let context = FoundationActionTurnContext::new("session-1", "turn-1").unwrap();
    let invalid_revision = AgentMailSendPreviewRequest {
        account_id: "primary".into(),
        draft_id: draft_id.clone(),
        expected_revision: 0,
    };
    assert!(
        service
            .request_send_from_agent_preview(invalid_revision, &context, "call-invalid", Utc::now())
            .await
            .is_err()
    );
    let request = AgentMailSendPreviewRequest {
        account_id: "primary".into(),
        draft_id: draft_id.clone(),
        expected_revision: 1,
    };
    let now = Utc::now();

    let first = service
        .request_send_from_agent_preview(request.clone(), &context, "call-1", now)
        .await
        .unwrap();
    let replay = service
        .request_send_from_agent_preview(request.clone(), &context, "call-1", now)
        .await
        .unwrap();
    let another_call = service
        .request_send_from_agent_preview(request, &context, "call-2", now)
        .await
        .unwrap();

    assert_eq!(first.action.status, ActionStatus::WaitingApproval);
    assert_eq!(first.action.action_id, replay.action.action_id);
    assert_eq!(
        first.approval.binding.session_id.as_deref(),
        Some("session-1")
    );
    assert_eq!(
        first.preview.as_ref().unwrap().idempotency_key,
        replay.preview.as_ref().unwrap().idempotency_key
    );
    assert_ne!(
        first.preview.as_ref().unwrap().idempotency_key,
        another_call.preview.as_ref().unwrap().idempotency_key
    );
    assert_eq!(service.list_actions().await.unwrap().len(), 2);
    assert_eq!(mail.provider_submission_count(), 0);
}
