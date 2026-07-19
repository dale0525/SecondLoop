use super::*;
use axum::{
    body::{Body, to_bytes},
    http::{Request, StatusCode, header},
};
use serde_json::{Value, json};
use tower::ServiceExt;

#[tokio::test]
async fn app_managed_model_access_rejects_request_overrides_before_turn_execution() {
    let storage = Storage::connect("sqlite::memory:").await.unwrap();
    let state = AppState::new_with_agent(storage, Arc::new(DeterministicAgent))
        .with_host_discovery(Some(app_managed_discovery()))
        .unwrap();
    let app = router(Arc::new(state));

    let response = app
        .oneshot(json_request(
            "/sessions/not-created/messages",
            json!({
                "content": "Override the managed model",
                "modelSettings": {
                    "apiKey": "attacker-value",
                    "baseUrl": "https://attacker.example/v1",
                    "endpointType": "responses",
                    "modelName": "attacker-model"
                }
            }),
        ))
        .await
        .unwrap();

    assert_eq!(response.status(), StatusCode::BAD_REQUEST);
    assert_eq!(
        read_json(response).await["error"],
        "model settings are managed by the Agent App"
    );
}

fn app_managed_discovery() -> AgentAppHostDiscovery {
    serde_json::from_value(json!({
        "schemaVersion": 2,
        "manifestSha256": "a".repeat(64),
        "runtimeVersion": "0.1.0",
        "platform": "desktop",
        "identity": {
            "appId": "dev.agentweave.default",
            "packageId": "dev.agentweave.default.app",
            "version": "0.1.0",
            "displayName": "AgentWeave",
            "shortName": null,
            "description": null,
            "accentColor": null
        },
        "features": [],
        "requirements": {
            "packages": [],
            "capabilities": [],
            "runtimeTools": [],
            "connectors": []
        },
        "policy": {
            "externalSideEffects": "require_approval",
            "network": "declared_only",
            "backgroundExecution": "disabled",
            "memoryPersistence": "local_only",
            "skillManagement": "disabled"
        },
        "access": {
            "modelAccess": {
                "configurationPolicy": "app_managed",
                "profile": {
                    "providerId": "example.gateway",
                    "endpointType": "responses",
                    "baseUrl": "https://gateway.example.test/v1",
                    "modelName": "managed-model",
                    "authentication": "user_identity",
                    "headers": {}
                }
            },
            "identity": {
                "mode": "required",
                "provider": {
                    "id": "agentweave.identity.oidc",
                    "version": "^1.0.0",
                    "publicConfig": {"issuer": "https://identity.example.test"}
                }
            },
            "entitlements": {
                "mode": "required",
                "provider": {
                    "id": "agentweave.entitlements.http",
                    "version": "^1.0.0",
                    "publicConfig": {"endpoint": "https://access.example.test"}
                }
            }
        }
    }))
    .unwrap()
}

fn json_request(uri: &str, body: Value) -> Request<Body> {
    Request::builder()
        .method("POST")
        .uri(uri)
        .header(header::CONTENT_TYPE, "application/json")
        .body(Body::from(body.to_string()))
        .unwrap()
}

async fn read_json(response: axum::response::Response) -> Value {
    let body = to_bytes(response.into_body(), usize::MAX).await.unwrap();
    serde_json::from_slice(&body).unwrap()
}
