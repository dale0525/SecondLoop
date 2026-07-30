use super::*;
use axum::{
    Router,
    routing::{delete, get, post},
};

pub(crate) fn recovery_routes() -> Router<Arc<AppState>> {
    Router::new()
        .route("/dev/control/status", get(status))
        .route(
            "/dev/control/cloudflare/authorization",
            post(start_authorization).delete(disconnect_authorization),
        )
        .route(
            "/dev/control/cloudflare/authorization/callback",
            post(complete_authorization),
        )
        .route(
            "/dev/control/cloudflare/authorization/pending",
            delete(cancel_pending_authorization),
        )
        .route(
            "/dev/control/cloudflare/accounts",
            get(list_accounts).post(select_account),
        )
        .route(
            "/dev/control/firebase/authorization",
            post(start_firebase_authorization).delete(disconnect_firebase_authorization),
        )
        .route(
            "/dev/control/firebase/authorization/callback",
            post(complete_firebase_authorization),
        )
        .route(
            "/dev/control/firebase/authorization/pending",
            delete(cancel_firebase_authorization),
        )
        .route(
            "/dev/control/firebase/projects",
            get(list_firebase_projects).post(configure_firebase_project),
        )
}

pub(crate) fn routes() -> Router<Arc<AppState>> {
    recovery_routes()
        .route("/dev/control/gateway/plan", post(plan_deployment))
        .route("/dev/control/access/plan", post(plan_access_bundle))
        .route("/dev/control/access/apply", post(apply_access_bundle))
        .route("/dev/control/access/test", post(test_access_bundle))
        .route(
            "/dev/control/commerce/creem/bootstrap",
            post(bootstrap_commerce_webhook),
        )
        .route("/dev/control/gateway/apply", post(apply_deployment))
        .route("/dev/control/gateway/inspect", post(inspect_deployment))
        .route("/dev/control/gateway/test", post(test_deployment))
        .route("/dev/control/gateway/rotate", post(rotate_secret))
        .route("/dev/control/gateway/rollback", post(rollback))
        .route("/dev/control/gateway/destroy/plan", post(plan_destroy))
        .route("/dev/control/gateway/destroy/apply", post(apply_destroy))
        .merge(crate::developer_control_plane_bundle_lifecycle_api::routes())
}
