use super::*;
use crate::connector::ConnectorRuntime;
use crate::contacts::{ContactIdentity, FakeContactsConnector};
use crate::contacts_connector_transport::ContactsConnectorTransport;
use std::time::Duration as StdDuration;

fn contact() -> ContactRecord {
    ContactRecord {
        id: "contact-1".into(),
        display_name: "Alex Chen".into(),
        identities: vec![ContactIdentity {
            kind: "email".into(),
            value: "alex@example.test".into(),
            label: None,
        }],
        organization: None,
        relationship: None,
        version: 1,
        provider_id: Some("provider-1".into()),
        updated_at: Utc::now(),
    }
}

async fn service() -> (ContactsActionService, ConnectorToolRuntime) {
    let storage = Storage::connect("sqlite::memory:").await.unwrap();
    let scope = CredentialScope {
        app_id: "com.example.app".into(),
        tenant_id: "local".into(),
        user_id: "user".into(),
    };
    let connector = Arc::new(FakeContactsConnector::default());
    connector
        .seed(
            crate::contacts::ContactScope {
                app_id: scope.app_id.clone(),
                tenant_id: scope.tenant_id.clone(),
                user_id: scope.user_id.clone(),
                account_id: "primary".into(),
            },
            contact(),
        )
        .unwrap();
    let runtime = Arc::new(ConnectorRuntime::new(None, 256 * 1024).unwrap());
    runtime
        .register(
            ContactsConnectorTransport::descriptor("Fake Contacts", true),
            Arc::new(ContactsConnectorTransport::new(connector, scope.clone()).unwrap()),
        )
        .await
        .unwrap();
    let context = Arc::new(
        EphemeralConnectorContextProvider::fail_closed(scope.clone(), StdDuration::from_secs(2))
            .unwrap(),
    );
    let tools = ConnectorToolRuntime::load(runtime, context.clone()).unwrap();
    let service =
        ContactsActionService::new(&storage, tools.clone(), context, scope, "contacts-test-v1")
            .await
            .unwrap();
    (service, tools)
}

#[tokio::test]
async fn approved_contact_update_executes_exactly_once() {
    let (service, tools) = service().await;
    let preview_result = tools
        .execute(
            "contact_update_preview",
            "preview-1",
            serde_json::json!({
                "accountId": "primary",
                "contactId": "contact-1",
                "expectedVersion": 1,
                "replacement": ContactRecord {
                    display_name: "Alex Chen".into(),
                    identities: vec![ContactIdentity {
                        kind: "email".into(),
                        value: "new@example.test".into(),
                        label: None,
                    }],
                    ..contact()
                },
                "idempotencyKey": "update-1"
            }),
        )
        .await
        .unwrap();
    let preview = serde_json::from_value(preview_result["output"].clone()).unwrap();
    let pending = service.request(preview, None, Utc::now()).await.unwrap();
    let first = service
        .resolve(
            &pending.approval.approval_id,
            ApprovalDecision::ApproveOnce,
            "user",
            Utc::now(),
        )
        .await
        .unwrap();
    let second = service
        .resolve(
            &pending.approval.approval_id,
            ApprovalDecision::ApproveOnce,
            "user",
            Utc::now(),
        )
        .await
        .unwrap();
    assert_eq!(first.action.status, ActionStatus::Succeeded);
    assert_eq!(second.action.status, ActionStatus::Succeeded);
    assert!(second.connector_result.is_none());
}

#[tokio::test]
async fn unapproved_contact_apply_fails_closed() {
    let (_, tools) = service().await;
    let denied = tools
        .execute(
            CONTACT_UPDATE_OPERATION,
            "direct-apply",
            serde_json::json!({
                "accountId": "primary",
                "approval": {
                    "previewId": "preview",
                    "previewHash": "a".repeat(64),
                    "approvalId": "approval"
                }
            }),
        )
        .await;
    assert!(denied.is_err());
}
