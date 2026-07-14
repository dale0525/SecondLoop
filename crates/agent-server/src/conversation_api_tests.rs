use super::*;
use crate::api;
use agent_runtime::storage::Storage;
use axum::{
    body::{Body, to_bytes},
    http::{Request, StatusCode},
};
use serde_json::{Value, json};
use tower::ServiceExt;

#[tokio::test]
async fn session_lifecycle_paginates_loads_and_checks_mutation_versions() {
    let storage = Storage::connect("sqlite::memory:").await.unwrap();
    let app = api::router(Arc::new(AppState::new(storage)));
    let mut created = Vec::new();
    for title in ["Alpha", "Beta", "Gamma"] {
        let response = app
            .clone()
            .oneshot(json_request("POST", "/sessions", json!({ "title": title })))
            .await
            .unwrap();
        assert_eq!(response.status(), StatusCode::OK);
        created.push(read_json(response).await);
    }

    let first_page = read_json(
        app.clone()
            .oneshot(empty_request("GET", "/sessions?limit=2"))
            .await
            .unwrap(),
    )
    .await;
    assert_eq!(first_page["items"].as_array().unwrap().len(), 2);
    let cursor = first_page["nextCursor"].as_str().unwrap();
    let second_page = read_json(
        app.clone()
            .oneshot(empty_request(
                "GET",
                &format!("/sessions?limit=2&cursor={cursor}"),
            ))
            .await
            .unwrap(),
    )
    .await;
    assert_eq!(second_page["items"].as_array().unwrap().len(), 1);
    assert!(second_page["nextCursor"].is_null());

    let session = &created[0];
    let session_id = session["id"].as_str().unwrap();
    let loaded = read_json(
        app.clone()
            .oneshot(empty_request("GET", &format!("/sessions/{session_id}")))
            .await
            .unwrap(),
    )
    .await;
    assert_eq!(loaded["session"]["title"], "Alpha");
    assert_eq!(loaded["messages"], json!([]));
    assert_eq!(loaded["events"], json!([]));

    let expected = session["updated_at"].as_str().unwrap();
    let renamed_response = app
        .clone()
        .oneshot(json_request(
            "PATCH",
            &format!("/sessions/{session_id}"),
            json!({ "title": "Renamed", "expectedUpdatedAt": expected }),
        ))
        .await
        .unwrap();
    assert_eq!(renamed_response.status(), StatusCode::OK);
    let renamed = read_json(renamed_response).await;
    assert_eq!(renamed["title"], "Renamed");

    let stale_response = app
        .clone()
        .oneshot(json_request(
            "PATCH",
            &format!("/sessions/{session_id}"),
            json!({ "title": "Stale", "expectedUpdatedAt": expected }),
        ))
        .await
        .unwrap();
    assert_eq!(stale_response.status(), StatusCode::CONFLICT);
    assert_eq!(
        read_json(stale_response).await["authoritative"]["title"],
        "Renamed"
    );

    let stale_delete = app
        .clone()
        .oneshot(empty_request(
            "DELETE",
            &format!(
                "/sessions/{session_id}?expectedUpdatedAt={}",
                expected.replace('+', "%2B")
            ),
        ))
        .await
        .unwrap();
    assert_eq!(stale_delete.status(), StatusCode::CONFLICT);

    let current = renamed["updated_at"].as_str().unwrap();
    let deleted = app
        .clone()
        .oneshot(empty_request(
            "DELETE",
            &format!(
                "/sessions/{session_id}?expectedUpdatedAt={}",
                current.replace('+', "%2B")
            ),
        ))
        .await
        .unwrap();
    assert_eq!(deleted.status(), StatusCode::NO_CONTENT);
    let missing = app
        .oneshot(empty_request("GET", &format!("/sessions/{session_id}")))
        .await
        .unwrap();
    assert_eq!(missing.status(), StatusCode::NOT_FOUND);
}

#[tokio::test]
async fn session_contract_rejects_invalid_bounds_and_cursors() {
    let storage = Storage::connect("sqlite::memory:").await.unwrap();
    let app = api::router(Arc::new(AppState::new(storage)));
    for request in [
        empty_request("GET", "/sessions?limit=0"),
        empty_request("GET", "/sessions?cursor=not-hex"),
        json_request("POST", "/sessions", json!({ "title": "\n" })),
    ] {
        let response = app.clone().oneshot(request).await.unwrap();
        assert_eq!(response.status(), StatusCode::BAD_REQUEST);
    }
}

fn json_request(method: &str, uri: &str, body: Value) -> Request<Body> {
    Request::builder()
        .method(method)
        .uri(uri)
        .header("content-type", "application/json")
        .body(Body::from(body.to_string()))
        .unwrap()
}

fn empty_request(method: &str, uri: &str) -> Request<Body> {
    Request::builder()
        .method(method)
        .uri(uri)
        .body(Body::empty())
        .unwrap()
}

async fn read_json(response: axum::response::Response) -> Value {
    let bytes = to_bytes(response.into_body(), 1024 * 1024).await.unwrap();
    serde_json::from_slice(&bytes).unwrap()
}
