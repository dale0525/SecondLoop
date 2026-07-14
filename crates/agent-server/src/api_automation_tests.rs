use super::*;
use agent_runtime::automation::{NotificationRequest, NotificationStore};
use agent_runtime::automation_tools::{AutomationScope, AutomationToolRuntime};
use axum::body::{Body, to_bytes};
use axum::http::{Request, StatusCode, header};
use chrono::{Duration, Utc};
use serde_json::{Value, json};
use tower::ServiceExt;

#[tokio::test]
async fn automation_api_manages_scoped_schedules_and_notification_delivery() {
    let storage = Storage::connect("sqlite::memory:").await.unwrap();
    let notifications = NotificationStore::from_storage(&storage).await.unwrap();
    let notification = notifications
        .enqueue(
            NotificationRequest {
                app_id: "dev.agentweave.default".into(),
                tenant_id: "local".into(),
                user_id: "local-user".into(),
                channel: "desktop".into(),
                title: "Daily brief".into(),
                body: "Two updates are ready.".into(),
                dedupe_key: "brief-1".into(),
                not_before: Utc::now() - Duration::seconds(1),
                quiet_hours: None,
                data: json!({"route": "briefing"}),
            },
            Utc::now(),
        )
        .await
        .unwrap();
    let tools = AutomationToolRuntime::from_storage(
        &storage,
        AutomationScope::new("dev.agentweave.default", "local", "local-user").unwrap(),
    )
    .await
    .unwrap();
    let state = AppState::new(storage.clone())
        .with_automation_foundation(tools)
        .with_default_automation(&storage)
        .await
        .unwrap();
    let app = router(Arc::new(state));

    let created = app
        .clone()
        .oneshot(json_request(
            "/foundation/schedules",
            json!({
                "name": "Morning brief",
                "schedule": {
                    "kind": "one_shot",
                    "at": (Utc::now() + Duration::hours(1)).to_rfc3339()
                },
                "misfire": {"kind": "fire_once"},
                "payload": {"task": "briefing"},
                "idempotencyKey": "morning-brief-1"
            }),
        ))
        .await
        .unwrap();
    assert_eq!(created.status(), StatusCode::OK);
    let created = read_json(created).await;
    let job_id = created["id"].as_str().unwrap();
    let version = created["version"].as_i64().unwrap();

    let listed = app
        .clone()
        .oneshot(get_request("/foundation/schedules?limit=5"))
        .await
        .unwrap();
    assert_eq!(listed.status(), StatusCode::OK);
    assert_eq!(read_json(listed).await.as_array().unwrap().len(), 1);

    let paused = app
        .clone()
        .oneshot(json_request(
            &format!("/foundation/schedules/{job_id}"),
            json!({"expectedVersion": version, "status": "paused"}),
        ))
        .await
        .unwrap();
    assert_eq!(paused.status(), StatusCode::OK);
    assert_eq!(read_json(paused).await["status"], "paused");

    let queued = app
        .clone()
        .oneshot(json_request(
            "/foundation/notifications",
            json!({
                "channel":"desktop",
                "title":"Follow up",
                "body":"Prepare the response",
                "dedupeKey":"follow-up-1",
                "notBefore":(Utc::now() + Duration::hours(2)).to_rfc3339(),
                "data":{}
            }),
        ))
        .await
        .unwrap();
    assert_eq!(queued.status(), StatusCode::OK);
    let queued = read_json(queued).await;
    let queued_id = queued["notification_id"].as_str().unwrap();
    let cancelled = app
        .clone()
        .oneshot(json_request(
            &format!("/foundation/notifications/{queued_id}/cancel"),
            json!({}),
        ))
        .await
        .unwrap();
    assert_eq!(cancelled.status(), StatusCode::OK);
    assert_eq!(read_json(cancelled).await["status"], "cancelled");

    let claimed = app
        .clone()
        .oneshot(get_request(
            "/foundation/notifications/claim?channel=desktop&worker=desktop-test&limit=5",
        ))
        .await
        .unwrap();
    assert_eq!(claimed.status(), StatusCode::OK);
    let claimed = read_json(claimed).await;
    assert_eq!(claimed[0]["notification_id"], notification.notification_id);
    assert_eq!(claimed[0]["status"], "delivering");

    let finished = app
        .oneshot(json_request(
            &format!("/foundation/notifications/{}", notification.notification_id),
            json!({
                "worker": "desktop-test",
                "outcome": {"kind": "delivered", "delivery_id": "desktop:1"}
            }),
        ))
        .await
        .unwrap();
    assert_eq!(finished.status(), StatusCode::OK);
    assert_eq!(read_json(finished).await, json!(true));
}

#[tokio::test]
async fn automation_api_rejects_caller_scope_and_isolates_foreign_records() {
    let storage = Storage::connect("sqlite::memory:").await.unwrap();
    let notifications = NotificationStore::from_storage(&storage).await.unwrap();
    notifications
        .enqueue(
            NotificationRequest {
                app_id: "another.app".into(),
                tenant_id: "local".into(),
                user_id: "local-user".into(),
                channel: "desktop".into(),
                title: "Foreign".into(),
                body: "Must remain isolated.".into(),
                dedupe_key: "foreign-1".into(),
                not_before: Utc::now() - Duration::seconds(1),
                quiet_hours: None,
                data: json!({}),
            },
            Utc::now(),
        )
        .await
        .unwrap();
    let tools = AutomationToolRuntime::from_storage(
        &storage,
        AutomationScope::new("dev.agentweave.default", "local", "local-user").unwrap(),
    )
    .await
    .unwrap();
    let state = AppState::new(storage.clone())
        .with_automation_foundation(tools)
        .with_default_automation(&storage)
        .await
        .unwrap();
    let app = router(Arc::new(state));

    let foreign = app
        .clone()
        .oneshot(json_request(
            "/foundation/schedules",
            json!({
                "app_id": "another.app",
                "tenant_id": "local",
                "user_id": "local-user",
                "name": "Foreign",
                "schedule": {
                    "kind": "one_shot",
                    "at": (Utc::now() + Duration::hours(1)).to_rfc3339()
                },
                "misfire": {"kind": "fire_once"},
                "payload": {},
                "idempotencyKey":"foreign-1"
            }),
        ))
        .await
        .unwrap();
    assert_eq!(foreign.status(), StatusCode::UNPROCESSABLE_ENTITY);

    let invalid_limit = app
        .clone()
        .oneshot(get_request("/foundation/schedules?limit=0"))
        .await
        .unwrap();
    assert_eq!(invalid_limit.status(), StatusCode::BAD_REQUEST);

    let foreign_claim = app
        .oneshot(get_request(
            "/foundation/notifications/claim?channel=desktop&worker=desktop-test&limit=5",
        ))
        .await
        .unwrap();
    assert_eq!(foreign_claim.status(), StatusCode::OK);
    assert!(
        read_json(foreign_claim)
            .await
            .as_array()
            .unwrap()
            .is_empty()
    );
    assert_eq!(
        notifications
            .claim_due("foreign-worker", Utc::now(), Duration::seconds(30), 5)
            .await
            .unwrap()
            .len(),
        1
    );
}

fn json_request(uri: &str, body: Value) -> Request<Body> {
    Request::builder()
        .method("POST")
        .uri(uri)
        .header(header::CONTENT_TYPE, "application/json")
        .body(Body::from(body.to_string()))
        .unwrap()
}

fn get_request(uri: &str) -> Request<Body> {
    Request::builder().uri(uri).body(Body::empty()).unwrap()
}

async fn read_json(response: axum::response::Response) -> Value {
    let bytes = to_bytes(response.into_body(), usize::MAX).await.unwrap();
    serde_json::from_slice(&bytes).unwrap()
}
