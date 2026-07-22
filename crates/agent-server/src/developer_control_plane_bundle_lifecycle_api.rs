use crate::api::AppState;
use crate::developer_control_plane::DeveloperControlPlane;
use crate::developer_control_plane_api::ControlPlaneApiError;
use crate::developer_control_plane_bundle_destroy::AccessBundleDestroyPlanInput;
use crate::developer_control_plane_bundle_lifecycle::{
    AccessBundleLifecycleTargets, AccessBundleMutationInput, AccessBundleRollbackInput,
};
use axum::{Json, Router, extract::State, http::StatusCode, routing::post};
use serde::Deserialize;
use std::sync::Arc;

pub(crate) fn routes() -> Router<Arc<AppState>> {
    Router::new()
        .route("/dev/control/access/inspect", post(inspect_access_bundle))
        .route("/dev/control/access/rotate", post(rotate_access_bundle))
        .route("/dev/control/access/rollback", post(rollback_access_bundle))
        .route(
            "/dev/control/access/destroy/plan",
            post(plan_destroy_access_bundle),
        )
        .route(
            "/dev/control/access/destroy/apply",
            post(apply_destroy_access_bundle),
        )
}

async fn inspect_access_bundle(
    State(state): State<Arc<AppState>>,
    Json(targets): Json<AccessBundleLifecycleTargets>,
) -> Result<
    Json<crate::developer_control_plane_bundle_lifecycle::AccessBundleInspectReceipt>,
    ControlPlaneApiError,
> {
    Ok(Json(
        control_plane(&state)?
            .inspect_access_bundle(targets)
            .await?,
    ))
}

async fn rotate_access_bundle(
    State(state): State<Arc<AppState>>,
    Json(input): Json<AccessBundleMutationInput>,
) -> Result<
    Json<crate::developer_control_plane_bundle_lifecycle::AccessBundleRotationReceipt>,
    ControlPlaneApiError,
> {
    let identity = identity_assertion(&state).await?;
    Ok(Json(
        control_plane(&state)?
            .rotate_access_bundle_projection_secret(
                input,
                "authorization",
                identity.expose_secret().as_bytes().to_vec(),
            )
            .await?,
    ))
}

async fn rollback_access_bundle(
    State(state): State<Arc<AppState>>,
    Json(input): Json<AccessBundleRollbackInput>,
) -> Result<
    Json<crate::developer_control_plane_bundle_lifecycle::AccessBundleRollbackReceipt>,
    ControlPlaneApiError,
> {
    let identity = identity_assertion(&state).await?;
    Ok(Json(
        control_plane(&state)?
            .rollback_access_bundle(
                input,
                "authorization",
                identity.expose_secret().as_bytes().to_vec(),
            )
            .await?,
    ))
}

async fn plan_destroy_access_bundle(
    State(state): State<Arc<AppState>>,
    Json(input): Json<AccessBundleDestroyPlanInput>,
) -> Result<
    Json<crate::developer_control_plane_bundle_destroy::AccessBundleDestroyPlanSummary>,
    ControlPlaneApiError,
> {
    Ok(Json(
        control_plane(&state)?
            .plan_destroy_access_bundle(input)
            .await?,
    ))
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
struct ApplyDestroyAccessBundleRequest {
    plan_hash: String,
    confirm_commerce_projection_rebuild: bool,
}

async fn apply_destroy_access_bundle(
    State(state): State<Arc<AppState>>,
    Json(request): Json<ApplyDestroyAccessBundleRequest>,
) -> Result<
    Json<crate::developer_control_plane_bundle_destroy::AccessBundleDestroyReceipt>,
    ControlPlaneApiError,
> {
    if request.plan_hash.len() != 64
        || !request
            .plan_hash
            .bytes()
            .all(|byte| byte.is_ascii_hexdigit())
    {
        return Err(ControlPlaneApiError::new(
            StatusCode::BAD_REQUEST,
            "invalid_request",
            "The access destroy plan hash is invalid",
            None,
            false,
        ));
    }
    Ok(Json(
        control_plane(&state)?
            .apply_destroy_access_bundle(
                &request.plan_hash,
                request.confirm_commerce_projection_rebuild,
            )
            .await?,
    ))
}

async fn identity_assertion(
    state: &AppState,
) -> Result<crate::identity_api::IdentityAssertion, ControlPlaneApiError> {
    state
        .identity_runtime()
        .ok_or_else(|| {
            ControlPlaneApiError::new(
                StatusCode::UNPROCESSABLE_ENTITY,
                "identity_not_configured",
                "The selected identity plugin must be configured before access verification",
                None,
                false,
            )
        })?
        .gateway_test_assertion()
        .await
        .map_err(|_| {
            ControlPlaneApiError::new(
                StatusCode::UNAUTHORIZED,
                "identity_authorization_required",
                "Sign in with the selected identity plugin before access verification",
                None,
                false,
            )
        })
}

fn control_plane(state: &AppState) -> Result<&DeveloperControlPlane, ControlPlaneApiError> {
    state.developer_control_plane().ok_or_else(|| {
        ControlPlaneApiError::new(
            StatusCode::SERVICE_UNAVAILABLE,
            "developer_control_plane_unavailable",
            "Developer control plane is unavailable",
            None,
            false,
        )
    })
}
