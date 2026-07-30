use super::*;
use crate::local_transport::{TRANSPORT_HEADER, TransportAuth};
use agent_runtime::storage::Storage;
use axum::{
    body::Body,
    http::{Request, StatusCode},
};
use tower::ServiceExt;

const TOKEN: &str = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQ";

async fn recovery_router() -> Router {
    let state = Arc::new(
        AppState::new(Storage::connect("sqlite::memory:").await.unwrap())
            .with_skills_root(PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("tests")),
    );
    router_for_transport(state, TransportAuth::new(TOKEN).unwrap())
}

fn request(method: &str, path: &str, authenticated: bool) -> Request<Body> {
    let mut request = Request::builder().method(method).uri(path);
    if authenticated {
        request = request.header(TRANSPORT_HEADER, TOKEN);
    }
    request.body(Body::empty()).unwrap()
}

#[tokio::test]
async fn recovery_router_requires_transport_authentication() {
    let response = recovery_router()
        .await
        .oneshot(request("GET", "/health", false))
        .await
        .unwrap();

    assert_eq!(response.status(), StatusCode::UNAUTHORIZED);
}

#[tokio::test]
async fn recovery_router_exposes_only_repair_capabilities() {
    let app = recovery_router().await;
    for (method, path, expected) in [
        ("GET", "/health", StatusCode::OK),
        ("GET", "/host/bootstrap", StatusCode::SERVICE_UNAVAILABLE),
        ("GET", "/dev/providers", StatusCode::OK),
        ("GET", "/dev/skills", StatusCode::OK),
        (
            "GET",
            "/dev/control/status",
            StatusCode::SERVICE_UNAVAILABLE,
        ),
    ] {
        let response = app
            .clone()
            .oneshot(request(method, path, true))
            .await
            .unwrap();
        assert_eq!(response.status(), expected, "{method} {path}");
    }

    for (method, path) in [
        ("GET", "/sessions"),
        ("POST", "/turns"),
        ("GET", "/dev/tools"),
        ("POST", "/dev/skills/reload"),
        ("POST", "/dev/control/gateway/plan"),
        ("POST", "/dev/control/access/apply"),
    ] {
        let response = app
            .clone()
            .oneshot(request(method, path, true))
            .await
            .unwrap();
        assert_eq!(response.status(), StatusCode::NOT_FOUND, "{method} {path}");
    }
}
