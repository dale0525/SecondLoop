use super::*;
use axum::{
    body::{Body, to_bytes},
    http::{Request, StatusCode},
};
use serde_json::{Value, json};
use tower::ServiceExt;

#[tokio::test]
async fn host_bootstrap_returns_only_the_resolved_discovery_snapshot() {
    let storage = Storage::connect("sqlite::memory:").await.unwrap();
    let discovery = discovery_fixture("dev.agentweave.default", "AgentWeave");
    let app = router(Arc::new(
        AppState::new(storage)
            .with_host_discovery(Some(discovery.clone()))
            .unwrap(),
    ));

    let response = app.oneshot(get_bootstrap()).await.unwrap();

    assert_eq!(response.status(), StatusCode::OK);
    assert_eq!(
        read_json(response).await,
        serde_json::to_value(discovery).unwrap()
    );
}

#[tokio::test]
async fn host_bootstrap_rejects_a_snapshot_not_bound_to_the_active_prompt() {
    let storage = Storage::connect("sqlite::memory:").await.unwrap();
    let discovery = discovery_fixture("com.example.unrelated", "Unrelated");

    let error = AppState::new(storage)
        .with_host_discovery(Some(discovery))
        .err()
        .unwrap();

    assert_eq!(
        error.to_string(),
        "Host discovery identity does not match the active App prompt"
    );
}

#[tokio::test]
async fn host_bootstrap_fails_closed_without_a_resolved_agent_app() {
    let storage = Storage::connect("sqlite::memory:").await.unwrap();
    let app = router(Arc::new(AppState::new(storage)));

    let response = app.oneshot(get_bootstrap()).await.unwrap();

    assert_eq!(response.status(), StatusCode::NOT_FOUND);
    assert_eq!(
        read_json(response).await["error"],
        "resolved Agent App is unavailable"
    );
}

fn discovery_fixture(app_id: &str, display_name: &str) -> AgentAppHostDiscovery {
    serde_json::from_value(json!({
        "schemaVersion": 1,
        "manifestSha256": "a".repeat(64),
        "runtimeVersion": "0.1.0",
        "platform": "desktop",
        "identity": {
            "appId": app_id,
            "packageId": "com.example.secretary.app",
            "version": "0.1.0",
            "displayName": display_name,
            "shortName": null,
            "description": null,
            "accentColor": null
        },
        "features": ["memory-management"],
        "requirements": {
            "packages": [{
                "id": "agentweave.foundation.memory",
                "version": "=0.1.0"
            }],
            "capabilities": [],
            "runtimeTools": ["memory_search"],
            "connectors": []
        },
        "policy": {
            "externalSideEffects": "require_approval",
            "network": "declared_only",
            "backgroundExecution": "disabled",
            "memoryPersistence": "local_only",
            "skillManagement": "disabled"
        }
    }))
    .unwrap()
}

fn get_bootstrap() -> Request<Body> {
    Request::builder()
        .uri("/host/bootstrap")
        .body(Body::empty())
        .unwrap()
}

async fn read_json(response: Response) -> Value {
    let body = to_bytes(response.into_body(), usize::MAX).await.unwrap();
    serde_json::from_slice(&body).unwrap()
}
