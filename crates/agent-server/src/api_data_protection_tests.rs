use crate::api::{AppState, router};
use crate::data_protection::{MAX_BACKUP_BYTES, apply_pending_restore};
use agent_runtime::credential::SecretMaterial;
use agent_runtime::storage::Storage;
use axum::body::{Body, to_bytes};
use axum::http::{Method, Request, StatusCode, header};
use serde_json::Value;
use std::sync::Arc;
use tower::ServiceExt;

#[tokio::test]
async fn data_protection_api_exports_and_stages_an_authenticated_backup() {
    let root = tempfile::tempdir().unwrap();
    let database = root.path().join("agentweave.db");
    let url = format!("sqlite://{}?mode=rwc", database.display());
    let storage = Storage::connect(&url).await.unwrap();
    let original = storage.create_session("Original").await.unwrap();
    let state = Arc::new(
        AppState::new(storage.clone())
            .with_test_data_protection(&database, SecretMaterial::new(vec![7; 32]).unwrap())
            .unwrap(),
    );
    let app = router(state.clone());

    let status = app
        .clone()
        .oneshot(request(
            Method::GET,
            "/foundation/data-protection/status",
            Body::empty(),
        ))
        .await
        .unwrap();
    assert_eq!(status.status(), StatusCode::OK);
    assert_eq!(read_json(status).await["enabled"], true);

    let backup = app
        .clone()
        .oneshot(request(
            Method::GET,
            "/foundation/data-protection/backup",
            Body::empty(),
        ))
        .await
        .unwrap();
    assert_eq!(backup.status(), StatusCode::OK);
    assert_eq!(
        backup.headers()[header::CONTENT_TYPE],
        "application/vnd.agentweave.backup"
    );
    let backup = to_bytes(backup.into_body(), MAX_BACKUP_BYTES)
        .await
        .unwrap();
    storage.create_session("Later").await.unwrap();

    let restore = app
        .oneshot(request(
            Method::POST,
            "/foundation/data-protection/restore",
            Body::from(backup),
        ))
        .await
        .unwrap();
    assert_eq!(restore.status(), StatusCode::OK);
    assert_eq!(read_json(restore).await["restartRequired"], true);

    drop(state);
    storage.close().await;
    assert!(apply_pending_restore(&database).await.unwrap());
    let restored = Storage::connect(&url).await.unwrap();
    let sessions = restored.list_sessions().await.unwrap();
    assert_eq!(sessions.len(), 1);
    assert_eq!(sessions[0].id, original.id);
}

#[tokio::test]
async fn data_protection_api_fails_closed_when_disabled_or_oversized() {
    let storage = Storage::connect("sqlite::memory:").await.unwrap();
    let app = router(Arc::new(AppState::new(storage)));
    let status = app
        .clone()
        .oneshot(request(
            Method::GET,
            "/foundation/data-protection/status",
            Body::empty(),
        ))
        .await
        .unwrap();
    assert_eq!(read_json(status).await["enabled"], false);
    let disabled = app
        .oneshot(request(
            Method::GET,
            "/foundation/data-protection/backup",
            Body::empty(),
        ))
        .await
        .unwrap();
    assert_eq!(disabled.status(), StatusCode::NOT_FOUND);

    let root = tempfile::tempdir().unwrap();
    let database = root.path().join("agentweave.db");
    let url = format!("sqlite://{}?mode=rwc", database.display());
    let storage = Storage::connect(&url).await.unwrap();
    let protected = router(Arc::new(
        AppState::new(storage)
            .with_test_data_protection(&database, SecretMaterial::new(vec![7; 32]).unwrap())
            .unwrap(),
    ));
    let oversized = Request::builder()
        .method(Method::POST)
        .uri("/foundation/data-protection/restore")
        .header(header::CONTENT_LENGTH, MAX_BACKUP_BYTES + 1)
        .body(Body::empty())
        .unwrap();
    assert_eq!(
        protected.oneshot(oversized).await.unwrap().status(),
        StatusCode::PAYLOAD_TOO_LARGE
    );
}

fn request(method: Method, uri: &str, body: Body) -> Request<Body> {
    Request::builder()
        .method(method)
        .uri(uri)
        .body(body)
        .unwrap()
}

async fn read_json(response: axum::response::Response) -> Value {
    let bytes = to_bytes(response.into_body(), 64 * 1024).await.unwrap();
    serde_json::from_slice(&bytes).unwrap()
}
