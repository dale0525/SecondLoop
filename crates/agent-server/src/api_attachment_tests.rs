use crate::api::{AppState, router};
use agent_runtime::attachment_tools::AttachmentToolRuntime;
use agent_runtime::attachments::{AttachmentScope, MAX_ATTACHMENT_BYTES, SqliteAttachmentStore};
use agent_runtime::storage::Storage;
use axum::body::{Body, to_bytes};
use axum::http::{Method, Request, StatusCode, header};
use serde_json::Value;
use std::sync::Arc;
use tower::ServiceExt;

#[tokio::test]
async fn attachment_api_imports_reads_lists_and_deletes_without_exposing_scope() {
    let storage = Storage::connect("sqlite::memory:").await.unwrap();
    let store = SqliteAttachmentStore::from_storage(&storage).await.unwrap();
    let scope = AttachmentScope::new("agentweave.default", "local", "local-user").unwrap();
    let other_scope = AttachmentScope::new("other.app", "local", "local-user").unwrap();
    store
        .import(
            &other_scope,
            "private.txt",
            "text/plain",
            b"other app",
            "other-import",
        )
        .await
        .unwrap();
    let app = router(Arc::new(
        AppState::new(storage).with_attachment_foundation(AttachmentToolRuntime::new(store, scope)),
    ));

    let created = app
        .clone()
        .oneshot(import_request("note.txt", "attachment-1", b"hello"))
        .await
        .unwrap();
    assert_eq!(created.status(), StatusCode::OK);
    let created = read_json(created).await;
    let attachment_id = created["id"].as_str().unwrap();
    assert_eq!(created["fileName"], "note.txt");
    assert_eq!(created["sizeBytes"], 5);

    let repeated = app
        .clone()
        .oneshot(import_request("note.txt", "attachment-1", b"hello"))
        .await
        .unwrap();
    assert_eq!(repeated.status(), StatusCode::OK);
    assert_eq!(read_json(repeated).await["id"], attachment_id);

    let conflict = app
        .clone()
        .oneshot(import_request("note.txt", "attachment-1", b"changed"))
        .await
        .unwrap();
    assert_eq!(conflict.status(), StatusCode::CONFLICT);

    let listed = app
        .clone()
        .oneshot(
            Request::builder()
                .uri("/foundation/attachments?limit=10")
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    let listed = read_json(listed).await;
    assert_eq!(listed.as_array().unwrap().len(), 1);
    assert_eq!(listed[0]["id"], attachment_id);

    let content = app
        .clone()
        .oneshot(
            Request::builder()
                .uri(format!("/foundation/attachments/{attachment_id}/content"))
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(content.status(), StatusCode::OK);
    assert_eq!(content.headers()[header::CONTENT_TYPE], "text/plain");
    assert_eq!(
        to_bytes(content.into_body(), 32).await.unwrap(),
        b"hello"[..]
    );

    let deleted = app
        .clone()
        .oneshot(
            Request::builder()
                .method(Method::DELETE)
                .uri(format!("/foundation/attachments/{attachment_id}"))
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(deleted.status(), StatusCode::OK);

    let missing = app
        .oneshot(
            Request::builder()
                .uri(format!("/foundation/attachments/{attachment_id}"))
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(missing.status(), StatusCode::NOT_FOUND);
}

#[tokio::test]
async fn attachment_api_rejects_invalid_metadata_and_oversized_content() {
    let storage = Storage::connect("sqlite::memory:").await.unwrap();
    let store = SqliteAttachmentStore::from_storage(&storage).await.unwrap();
    let scope = AttachmentScope::new("agentweave.default", "local", "local-user").unwrap();
    let app = router(Arc::new(
        AppState::new(storage).with_attachment_foundation(AttachmentToolRuntime::new(store, scope)),
    ));

    let missing_header = Request::builder()
        .method(Method::POST)
        .uri("/foundation/attachments?fileName=note.txt")
        .body(Body::from("hello"))
        .unwrap();
    assert_eq!(
        app.clone().oneshot(missing_header).await.unwrap().status(),
        StatusCode::BAD_REQUEST
    );

    let oversized = Request::builder()
        .method(Method::POST)
        .uri("/foundation/attachments?fileName=note.txt")
        .header(header::CONTENT_TYPE, "text/plain")
        .header("idempotency-key", "oversized")
        .header(header::CONTENT_LENGTH, MAX_ATTACHMENT_BYTES + 1)
        .body(Body::empty())
        .unwrap();
    assert_eq!(
        app.oneshot(oversized).await.unwrap().status(),
        StatusCode::PAYLOAD_TOO_LARGE
    );
}

fn import_request(file_name: &str, idempotency_key: &str, body: &[u8]) -> Request<Body> {
    Request::builder()
        .method(Method::POST)
        .uri(format!("/foundation/attachments?fileName={file_name}"))
        .header(header::CONTENT_TYPE, "text/plain")
        .header("idempotency-key", idempotency_key)
        .body(Body::from(body.to_vec()))
        .unwrap()
}

async fn read_json(response: axum::response::Response) -> Value {
    let bytes = to_bytes(response.into_body(), usize::MAX).await.unwrap();
    serde_json::from_slice(&bytes).unwrap()
}
