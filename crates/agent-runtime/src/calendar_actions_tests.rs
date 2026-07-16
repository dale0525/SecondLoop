use super::*;
use crate::approval::ApprovalDecision;
use crate::calendar::{CalendarEventContent, FakeCalendarConnector};
use crate::calendar_connector_transport::CalendarConnectorTransport;
use crate::connector::ConnectorRuntime;
use chrono::Duration as ChronoDuration;
use std::time::Duration as StdDuration;

async fn service() -> (CalendarActionService, ConnectorToolRuntime) {
    let storage = Storage::connect("sqlite::memory:").await.unwrap();
    let scope = CredentialScope {
        app_id: "com.example.app".into(),
        tenant_id: "local".into(),
        user_id: "user".into(),
    };
    let runtime = Arc::new(ConnectorRuntime::new(None, 256 * 1024).unwrap());
    runtime
        .register(
            CalendarConnectorTransport::descriptor("Fake Calendar", true),
            Arc::new(
                CalendarConnectorTransport::new(
                    Arc::new(FakeCalendarConnector::default()),
                    scope.clone(),
                )
                .unwrap(),
            ),
        )
        .await
        .unwrap();
    let context = Arc::new(
        EphemeralConnectorContextProvider::fail_closed(scope.clone(), StdDuration::from_secs(2))
            .unwrap(),
    );
    let tools = ConnectorToolRuntime::load(runtime, context.clone()).unwrap();
    let service =
        CalendarActionService::new(&storage, tools.clone(), context, scope, "calendar-test-v1")
            .await
            .unwrap();
    (service, tools)
}

#[tokio::test]
async fn approved_calendar_action_executes_exactly_once() {
    let (service, tools) = service().await;
    let start = Utc::now() + ChronoDuration::hours(1);
    let preview_result = tools
        .execute(
            "calendar_event_create_preview",
            "preview-1",
            serde_json::json!({
                "accountId": "primary",
                "content": CalendarEventContent {
                    calendar_id: "primary".into(),
                    title: "Planning".into(),
                    description: None,
                    start,
                    end: start + ChronoDuration::hours(1),
                    timezone: "Asia/Shanghai".into(),
                    location: None,
                    attendees: Vec::new(),
                    recurrence: None,
                },
                "idempotencyKey": "create-1"
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
async fn unapproved_calendar_apply_fails_closed() {
    let (_, tools) = service().await;
    let denied = tools
        .execute(
            CALENDAR_APPLY_OPERATION,
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
