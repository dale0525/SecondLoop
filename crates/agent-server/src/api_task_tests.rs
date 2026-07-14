use super::*;
use agent_runtime::task_tools::TaskToolRuntime;
use agent_runtime::tasks::{TaskProvider, TaskScope};
use axum::body::{Body, to_bytes};
use axum::http::{Method, Request, StatusCode, header};
use serde_json::{Value, json};
use tower::ServiceExt;

#[tokio::test]
async fn task_api_is_persistent_idempotent_scoped_and_versioned() {
    let storage = Storage::connect("sqlite::memory:").await.unwrap();
    let provider = Arc::new(storage.local_task_provider());
    provider.initialize().await.unwrap();
    let runtime = TaskToolRuntime::new(
        provider,
        TaskScope::new("agentweave.default", "local", "local-user").unwrap(),
    )
    .unwrap();
    let app = router(Arc::new(
        AppState::new(storage).with_task_foundation(runtime),
    ));

    let created = app
        .clone()
        .oneshot(json_request(
            Method::POST,
            "/foundation/tasks",
            json!({
                "content": task_content("Prepare brief"),
                "idempotencyKey": "task-api-1"
            }),
        ))
        .await
        .unwrap();
    assert_eq!(created.status(), StatusCode::OK);
    let created = read_json(created).await;
    let task_id = created["id"].as_str().unwrap();
    assert_eq!(created["version"], 1);

    let repeated = app
        .clone()
        .oneshot(json_request(
            Method::POST,
            "/foundation/tasks",
            json!({
                "content": task_content("Prepare brief"),
                "idempotencyKey": "task-api-1"
            }),
        ))
        .await
        .unwrap();
    assert_eq!(repeated.status(), StatusCode::OK);
    assert_eq!(read_json(repeated).await["id"], task_id);

    let conflict = app
        .clone()
        .oneshot(json_request(
            Method::POST,
            "/foundation/tasks",
            json!({
                "content": task_content("Different content"),
                "idempotencyKey": "task-api-1"
            }),
        ))
        .await
        .unwrap();
    assert_eq!(conflict.status(), StatusCode::CONFLICT);

    let listed = app
        .clone()
        .oneshot(
            Request::builder()
                .uri("/foundation/tasks?status=open&limit=1")
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(listed.status(), StatusCode::OK);
    let listed = read_json(listed).await;
    assert_eq!(listed["tasks"].as_array().unwrap().len(), 1);
    assert!(listed.get("nextCursor").is_some());

    let stale = app
        .clone()
        .oneshot(json_request(
            Method::PATCH,
            &format!("/foundation/tasks/{task_id}"),
            json!({"content": task_content("Stale"), "expectedVersion": 9}),
        ))
        .await
        .unwrap();
    assert_eq!(stale.status(), StatusCode::CONFLICT);

    let completed = app
        .clone()
        .oneshot(json_request(
            Method::POST,
            &format!("/foundation/tasks/{task_id}/status"),
            json!({"expectedVersion": 1, "status": "completed"}),
        ))
        .await
        .unwrap();
    assert_eq!(completed.status(), StatusCode::OK);
    let completed = read_json(completed).await;
    assert_eq!(completed["status"], "completed");
    assert_eq!(completed["version"], 2);

    let deleted = app
        .clone()
        .oneshot(json_request(
            Method::DELETE,
            &format!("/foundation/tasks/{task_id}"),
            json!({"expectedVersion": 2}),
        ))
        .await
        .unwrap();
    assert_eq!(deleted.status(), StatusCode::OK);
    assert_eq!(read_json(deleted).await["deleted"], true);

    let missing = app
        .oneshot(
            Request::builder()
                .uri(format!("/foundation/tasks/{task_id}"))
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(missing.status(), StatusCode::NOT_FOUND);
}

fn task_content(title: &str) -> Value {
    json!({
        "title": title,
        "notes": null,
        "dueAt": null,
        "timezone": null,
        "recurrence": null,
        "priority": "normal",
        "tags": ["work"]
    })
}

fn json_request(method: Method, uri: &str, body: Value) -> Request<Body> {
    Request::builder()
        .method(method)
        .uri(uri)
        .header(header::CONTENT_TYPE, "application/json")
        .body(Body::from(body.to_string()))
        .unwrap()
}

async fn read_json(response: axum::response::Response) -> Value {
    let bytes = to_bytes(response.into_body(), usize::MAX).await.unwrap();
    serde_json::from_slice(&bytes).unwrap()
}
