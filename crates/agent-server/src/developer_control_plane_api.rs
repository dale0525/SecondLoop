use crate::api::AppState;
use crate::developer_control_plane::DeveloperControlPlane;
use crate::developer_control_plane_deployment::{
    DeploymentPlanInput, DeploymentReferenceInput, DeploymentSecretInput,
};
use crate::developer_control_plane_oauth::CloudflareOAuthClientSelection;
use crate::developer_firebase::FirebaseOAuthClientSelection;
use crate::developer_gateway_projection::{GatewayProjectPlanInput, project_gateway_plan};
use agent_devkit::{DevkitError, DevkitErrorCode, RemoteMutationRisk};
use axum::response::{IntoResponse, Response};
use axum::{
    Json, Router,
    extract::State,
    http::StatusCode,
    routing::{delete, get, post},
};
use serde::{Deserialize, Serialize};
use serde_json::Value;
use std::collections::BTreeMap;
use std::sync::Arc;
use url::Url;
use zeroize::Zeroize;

const MAX_PUBLIC_CONFIG_BYTES: usize = 256 * 1024;
const MAX_SECRET_BYTES: usize = 64 * 1024;

pub(crate) fn routes() -> Router<Arc<AppState>> {
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
        .route("/dev/control/gateway/plan", post(plan_deployment))
        .route("/dev/control/gateway/apply", post(apply_deployment))
        .route("/dev/control/gateway/inspect", post(inspect_deployment))
        .route("/dev/control/gateway/test", post(test_deployment))
        .route("/dev/control/gateway/rotate", post(rotate_secret))
        .route("/dev/control/gateway/rollback", post(rollback))
        .route("/dev/control/gateway/destroy/plan", post(plan_destroy))
        .route("/dev/control/gateway/destroy/apply", post(apply_destroy))
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
struct DeveloperControlStatus {
    authorization: crate::developer_control_plane_oauth::DeveloperAuthorizationStatus,
    firebase_authorization: crate::developer_firebase::FirebaseAuthorizationStatus,
    gateway_template: Option<GatewayTemplateStatus>,
    sensitive_bindings: BTreeMap<String, String>,
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
struct GatewayTemplateStatus {
    version: String,
    sha256: String,
}

async fn status(
    State(state): State<Arc<AppState>>,
) -> Result<Json<DeveloperControlStatus>, ControlPlaneApiError> {
    let control = control_plane(&state)?;
    Ok(Json(DeveloperControlStatus {
        authorization: control.authorization_status().await?,
        firebase_authorization: control.firebase_authorization_status().await?,
        gateway_template: control
            .gateway_template()
            .map(|template| GatewayTemplateStatus {
                version: template.version().into(),
                sha256: template.sha256().into(),
            }),
        sensitive_bindings: control.sensitive_binding_revisions().await?,
    }))
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
struct StartFirebaseAuthorizationRequest {
    client: FirebaseOAuthClientSelection,
    redirect_uri: String,
}

async fn start_firebase_authorization(
    State(state): State<Arc<AppState>>,
    Json(request): Json<StartFirebaseAuthorizationRequest>,
) -> Result<Json<crate::developer_firebase::FirebaseAuthorizationStart>, ControlPlaneApiError> {
    let redirect_uri = parse_url(&request.redirect_uri, "Firebase OAuth callback URI")?;
    Ok(Json(
        control_plane(&state)?
            .start_firebase_authorization(request.client, redirect_uri)
            .await?,
    ))
}

async fn complete_firebase_authorization(
    State(state): State<Arc<AppState>>,
    Json(request): Json<AuthorizationCallbackRequest>,
) -> Result<Json<crate::developer_firebase::FirebaseAuthorizationStatus>, ControlPlaneApiError> {
    Ok(Json(
        control_plane(&state)?
            .complete_firebase_authorization(&request.callback_url)
            .await?,
    ))
}

async fn cancel_firebase_authorization(
    State(state): State<Arc<AppState>>,
) -> Result<Json<crate::developer_firebase::FirebaseAuthorizationStatus>, ControlPlaneApiError> {
    Ok(Json(
        control_plane(&state)?
            .cancel_firebase_authorization()
            .await?,
    ))
}

async fn disconnect_firebase_authorization(
    State(state): State<Arc<AppState>>,
) -> Result<Json<crate::developer_firebase::FirebaseAuthorizationStatus>, ControlPlaneApiError> {
    Ok(Json(
        control_plane(&state)?
            .disconnect_firebase_authorization()
            .await?,
    ))
}

async fn list_firebase_projects(
    State(state): State<Arc<AppState>>,
) -> Result<Json<Vec<crate::developer_firebase::FirebaseProjectSummary>>, ControlPlaneApiError> {
    Ok(Json(control_plane(&state)?.list_firebase_projects().await?))
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
struct ConfigureFirebaseProjectRequest {
    project_id: String,
}

async fn configure_firebase_project(
    State(state): State<Arc<AppState>>,
    Json(request): Json<ConfigureFirebaseProjectRequest>,
) -> Result<Json<crate::developer_firebase::FirebaseConfigurationReceipt>, ControlPlaneApiError> {
    Ok(Json(
        control_plane(&state)?
            .configure_firebase_project(&request.project_id)
            .await?,
    ))
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
struct StartAuthorizationRequest {
    client: CloudflareOAuthClientSelection,
    redirect_uri: String,
}

async fn start_authorization(
    State(state): State<Arc<AppState>>,
    Json(request): Json<StartAuthorizationRequest>,
) -> Result<
    Json<crate::developer_control_plane_oauth::DeveloperAuthorizationStart>,
    ControlPlaneApiError,
> {
    let redirect_uri = parse_url(&request.redirect_uri, "Cloudflare OAuth callback URI")?;
    Ok(Json(
        control_plane(&state)?
            .start_authorization(request.client, redirect_uri)
            .await?,
    ))
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
struct AuthorizationCallbackRequest {
    callback_url: String,
}

async fn complete_authorization(
    State(state): State<Arc<AppState>>,
    Json(request): Json<AuthorizationCallbackRequest>,
) -> Result<
    Json<crate::developer_control_plane_oauth::DeveloperAuthorizationCallbackReceipt>,
    ControlPlaneApiError,
> {
    Ok(Json(
        control_plane(&state)?
            .complete_authorization_callback(&request.callback_url)
            .await?,
    ))
}

async fn disconnect_authorization(
    State(state): State<Arc<AppState>>,
) -> Result<
    Json<crate::developer_control_plane_oauth::DeveloperAuthorizationStatus>,
    ControlPlaneApiError,
> {
    Ok(Json(
        control_plane(&state)?.disconnect_authorization().await?,
    ))
}

async fn cancel_pending_authorization(
    State(state): State<Arc<AppState>>,
) -> Result<
    Json<crate::developer_control_plane_oauth::DeveloperAuthorizationStatus>,
    ControlPlaneApiError,
> {
    Ok(Json(
        control_plane(&state)?
            .cancel_pending_authorization()
            .await?,
    ))
}

async fn list_accounts(
    State(state): State<Arc<AppState>>,
) -> Result<Json<Vec<agent_devkit::DeveloperAccount>>, ControlPlaneApiError> {
    Ok(Json(
        control_plane(&state)?.list_authorization_accounts().await?,
    ))
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
struct SelectAccountRequest {
    account_id: String,
}

async fn select_account(
    State(state): State<Arc<AppState>>,
    Json(request): Json<SelectAccountRequest>,
) -> Result<
    Json<crate::developer_control_plane_oauth::DeveloperAuthorizationStatus>,
    ControlPlaneApiError,
> {
    Ok(Json(
        control_plane(&state)?
            .select_authorization_account(&request.account_id)
            .await?,
    ))
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
struct PlanDeploymentRequest {
    project: GatewayProjectPlanInput,
    sensitive_inputs: BTreeMap<String, SecretInputRequest>,
    #[serde(default)]
    idempotency_key: Option<String>,
    #[serde(default)]
    expected_remote_version: Option<String>,
    #[serde(default)]
    expected_remote_etag: Option<String>,
}

impl std::fmt::Debug for PlanDeploymentRequest {
    fn fmt(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        formatter
            .debug_struct("PlanDeploymentRequest")
            .field(
                "sensitive_input_names",
                &self.sensitive_inputs.keys().collect::<Vec<_>>(),
            )
            .finish_non_exhaustive()
    }
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
struct SecretInputRequest {
    revision: String,
    #[serde(default)]
    value: Option<SensitiveText>,
}

async fn plan_deployment(
    State(state): State<Arc<AppState>>,
    Json(request): Json<PlanDeploymentRequest>,
) -> Result<
    Json<crate::developer_control_plane_deployment::DeploymentPlanSummary>,
    ControlPlaneApiError,
> {
    for provider in [
        &request.project.providers.identity,
        &request.project.providers.entitlement,
        &request.project.providers.gateway,
    ] {
        bounded_json(&provider.public_config, "provider public configuration")?;
    }
    let http = identity_oidc::ReqwestOidcHttpClient::new().map_err(|_| {
        ControlPlaneApiError::new(
            StatusCode::SERVICE_UNAVAILABLE,
            "identity_discovery_unavailable",
            "Identity discovery is unavailable",
            None,
            false,
        )
    })?;
    let projection = project_gateway_plan(request.project, &http).await?;
    if request.sensitive_inputs.len() != projection.secret_bindings.len()
        || request
            .sensitive_inputs
            .keys()
            .any(|name| !projection.secret_bindings.contains_key(name))
    {
        return Err(invalid_request(
            "deployment sensitive inputs do not match the selected plugins",
        ));
    }
    let secrets = request
        .sensitive_inputs
        .into_iter()
        .map(|(slot, secret)| {
            let name = projection
                .secret_bindings
                .get(&slot)
                .cloned()
                .ok_or_else(|| invalid_request("deployment sensitive input slot is unavailable"))?;
            let value = secret.value.map(SensitiveText::into_bytes).transpose()?;
            Ok((
                name,
                DeploymentSecretInput {
                    revision: secret.revision,
                    value,
                },
            ))
        })
        .collect::<Result<_, ControlPlaneApiError>>()?;
    Ok(Json(
        control_plane(&state)?
            .plan_deployment(DeploymentPlanInput {
                account_id: projection.target.account_id,
                deployment_id: projection.target.deployment_id,
                worker_name: projection.target.worker_name,
                environment: projection.target.environment,
                gateway_config: projection.gateway_config,
                entitlement_bootstrap: projection.entitlement_bootstrap,
                secrets,
                idempotency_key: request.idempotency_key,
                expected_remote_version: request.expected_remote_version,
                expected_remote_etag: request.expected_remote_etag,
            })
            .await?,
    ))
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
struct PlanHashRequest {
    plan_hash: String,
}

async fn apply_deployment(
    State(state): State<Arc<AppState>>,
    Json(request): Json<PlanHashRequest>,
) -> Result<
    Json<crate::developer_control_plane_deployment::DeploymentApplyReceipt>,
    ControlPlaneApiError,
> {
    validate_plan_hash(&request.plan_hash)?;
    Ok(Json(
        control_plane(&state)?
            .apply_deployment(&request.plan_hash)
            .await?,
    ))
}

async fn inspect_deployment(
    State(state): State<Arc<AppState>>,
    Json(reference): Json<DeploymentReferenceInput>,
) -> Result<
    Json<crate::developer_control_plane_deployment::DeploymentObservation>,
    ControlPlaneApiError,
> {
    Ok(Json(
        control_plane(&state)?.inspect_deployment(reference).await?,
    ))
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
struct TestDeploymentRequest {
    target: DeploymentReferenceInput,
}

async fn test_deployment(
    State(state): State<Arc<AppState>>,
    Json(request): Json<TestDeploymentRequest>,
) -> Result<
    Json<crate::developer_control_plane_deployment::DeploymentTestReceipt>,
    ControlPlaneApiError,
> {
    let identity = state
        .identity_runtime()
        .ok_or_else(|| {
            ControlPlaneApiError::new(
                StatusCode::UNPROCESSABLE_ENTITY,
                "identity_not_configured",
                "The selected identity plugin must be configured before gateway verification",
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
                "Sign in with the selected identity plugin before gateway verification",
                None,
                false,
            )
        })?;
    Ok(Json(
        control_plane(&state)?
            .test_deployment(
                request.target,
                "authorization",
                identity.expose_secret().as_bytes().to_vec(),
            )
            .await?,
    ))
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
struct RotateSecretRequest {
    target: DeploymentReferenceInput,
    binding_name: String,
    revision: String,
    value: SensitiveText,
    #[serde(default)]
    idempotency_key: Option<String>,
    #[serde(default)]
    expected_remote_version: Option<String>,
    #[serde(default)]
    expected_remote_etag: Option<String>,
}

async fn rotate_secret(
    State(state): State<Arc<AppState>>,
    Json(request): Json<RotateSecretRequest>,
) -> Result<
    Json<crate::developer_control_plane_deployment::SecretRotationPublicReceipt>,
    ControlPlaneApiError,
> {
    Ok(Json(
        control_plane(&state)?
            .rotate_deployment_secret(
                request.target,
                request.binding_name,
                request.revision,
                request.value.into_bytes()?,
                request.idempotency_key,
                request.expected_remote_version,
                request.expected_remote_etag,
            )
            .await?,
    ))
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
struct RollbackRequest {
    target: DeploymentReferenceInput,
    restore_version: String,
    #[serde(default)]
    idempotency_key: Option<String>,
    #[serde(default)]
    expected_remote_version: Option<String>,
    #[serde(default)]
    expected_remote_etag: Option<String>,
}

async fn rollback(
    State(state): State<Arc<AppState>>,
    Json(request): Json<RollbackRequest>,
) -> Result<
    Json<crate::developer_control_plane_deployment::RollbackPublicReceipt>,
    ControlPlaneApiError,
> {
    Ok(Json(
        control_plane(&state)?
            .rollback_deployment(
                request.target,
                request.restore_version,
                request.idempotency_key,
                request.expected_remote_version,
                request.expected_remote_etag,
            )
            .await?,
    ))
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
struct DestroyPlanRequest {
    target: DeploymentReferenceInput,
    #[serde(default)]
    idempotency_key: Option<String>,
    #[serde(default)]
    expected_remote_version: Option<String>,
    #[serde(default)]
    expected_remote_etag: Option<String>,
}

async fn plan_destroy(
    State(state): State<Arc<AppState>>,
    Json(request): Json<DestroyPlanRequest>,
) -> Result<Json<crate::developer_control_plane_deployment::DestroyPlanSummary>, ControlPlaneApiError>
{
    Ok(Json(
        control_plane(&state)?
            .plan_destroy(
                request.target,
                request.idempotency_key,
                request.expected_remote_version,
                request.expected_remote_etag,
            )
            .await?,
    ))
}

async fn apply_destroy(
    State(state): State<Arc<AppState>>,
    Json(request): Json<PlanHashRequest>,
) -> Result<
    Json<crate::developer_control_plane_deployment::DestroyPublicReceipt>,
    ControlPlaneApiError,
> {
    validate_plan_hash(&request.plan_hash)?;
    Ok(Json(
        control_plane(&state)?
            .apply_destroy(&request.plan_hash)
            .await?,
    ))
}

struct SensitiveText(String);

impl<'de> Deserialize<'de> for SensitiveText {
    fn deserialize<D>(deserializer: D) -> Result<Self, D::Error>
    where
        D: serde::Deserializer<'de>,
    {
        let value = String::deserialize(deserializer)?;
        if value.is_empty() || value.len() > MAX_SECRET_BYTES || value.chars().any(char::is_control)
        {
            return Err(serde::de::Error::custom("sensitive input is invalid"));
        }
        Ok(Self(value))
    }
}

impl SensitiveText {
    fn into_bytes(mut self) -> Result<Vec<u8>, ControlPlaneApiError> {
        if self.0.is_empty() || self.0.len() > MAX_SECRET_BYTES {
            return Err(invalid_request("sensitive input size is invalid"));
        }
        Ok(std::mem::take(&mut self.0).into_bytes())
    }
}

impl std::fmt::Debug for SensitiveText {
    fn fmt(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        formatter.write_str("SensitiveText([REDACTED])")
    }
}

impl Drop for SensitiveText {
    fn drop(&mut self) {
        self.0.zeroize();
    }
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

fn parse_url(value: &str, label: &str) -> Result<Url, ControlPlaneApiError> {
    if value.is_empty() || value.len() > 16 * 1024 || value.chars().any(char::is_control) {
        return Err(invalid_request(&format!("{label} is invalid")));
    }
    Url::parse(value).map_err(|_| invalid_request(&format!("{label} is invalid")))
}

fn bounded_json(value: &Value, label: &str) -> Result<(), ControlPlaneApiError> {
    let bytes =
        serde_json::to_vec(value).map_err(|_| invalid_request(&format!("{label} is invalid")))?;
    if bytes.is_empty() || bytes.len() > MAX_PUBLIC_CONFIG_BYTES {
        return Err(invalid_request(&format!("{label} size is invalid")));
    }
    Ok(())
}

fn validate_plan_hash(value: &str) -> Result<(), ControlPlaneApiError> {
    if value.len() != 64 || !value.bytes().all(|byte| byte.is_ascii_hexdigit()) {
        return Err(invalid_request("deployment plan hash is invalid"));
    }
    Ok(())
}

fn invalid_request(message: &str) -> ControlPlaneApiError {
    ControlPlaneApiError::new(
        StatusCode::UNPROCESSABLE_ENTITY,
        "invalid_request",
        message,
        None,
        false,
    )
}

pub(crate) struct ControlPlaneApiError {
    status: StatusCode,
    body: ControlPlaneErrorBody,
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
struct ControlPlaneErrorBody {
    code: String,
    message: String,
    retry_after_ms: Option<u64>,
    remote_mutation_possible: bool,
}

impl ControlPlaneApiError {
    fn new(
        status: StatusCode,
        code: &str,
        message: &str,
        retry_after_ms: Option<u64>,
        remote_mutation_possible: bool,
    ) -> Self {
        Self {
            status,
            body: ControlPlaneErrorBody {
                code: code.into(),
                message: message.chars().take(500).collect(),
                retry_after_ms,
                remote_mutation_possible,
            },
        }
    }
}

impl From<DevkitError> for ControlPlaneApiError {
    fn from(error: DevkitError) -> Self {
        let status = match error.code {
            DevkitErrorCode::InvalidConfiguration
            | DevkitErrorCode::InvalidPlan
            | DevkitErrorCode::PlanIntegrityFailed
            | DevkitErrorCode::Unsupported => StatusCode::UNPROCESSABLE_ENTITY,
            DevkitErrorCode::InvalidAuthorization => StatusCode::UNAUTHORIZED,
            DevkitErrorCode::PermissionInsufficient
            | DevkitErrorCode::OriginRejected
            | DevkitErrorCode::RedirectRejected => StatusCode::FORBIDDEN,
            DevkitErrorCode::ConcurrentModification
            | DevkitErrorCode::AlreadyExists
            | DevkitErrorCode::DriftDetected => StatusCode::CONFLICT,
            DevkitErrorCode::NotFound => StatusCode::NOT_FOUND,
            DevkitErrorCode::RateLimited => StatusCode::TOO_MANY_REQUESTS,
            DevkitErrorCode::Timeout => StatusCode::GATEWAY_TIMEOUT,
            DevkitErrorCode::Unavailable | DevkitErrorCode::SensitiveInputUnavailable => {
                StatusCode::SERVICE_UNAVAILABLE
            }
            DevkitErrorCode::RemoteProtocol | DevkitErrorCode::VerificationFailed => {
                StatusCode::BAD_GATEWAY
            }
            DevkitErrorCode::Internal => StatusCode::INTERNAL_SERVER_ERROR,
        };
        let message = if error.code == DevkitErrorCode::Internal {
            "Developer control-plane operation failed"
        } else {
            &error.safe_message
        };
        Self::new(
            status,
            devkit_error_code(error.code),
            message,
            error.retry_after_ms,
            error.remote_mutation_risk == RemoteMutationRisk::Possible,
        )
    }
}

fn devkit_error_code(code: DevkitErrorCode) -> &'static str {
    match code {
        DevkitErrorCode::InvalidConfiguration => "invalid_configuration",
        DevkitErrorCode::InvalidAuthorization => "invalid_authorization",
        DevkitErrorCode::PermissionInsufficient => "permission_insufficient",
        DevkitErrorCode::InvalidPlan => "invalid_plan",
        DevkitErrorCode::PlanIntegrityFailed => "plan_integrity_failed",
        DevkitErrorCode::ConcurrentModification => "concurrent_modification",
        DevkitErrorCode::NotFound => "not_found",
        DevkitErrorCode::AlreadyExists => "already_exists",
        DevkitErrorCode::RateLimited => "rate_limited",
        DevkitErrorCode::Timeout => "timeout",
        DevkitErrorCode::Unavailable => "unavailable",
        DevkitErrorCode::RedirectRejected => "redirect_rejected",
        DevkitErrorCode::OriginRejected => "origin_rejected",
        DevkitErrorCode::RemoteProtocol => "remote_protocol",
        DevkitErrorCode::DriftDetected => "drift_detected",
        DevkitErrorCode::VerificationFailed => "verification_failed",
        DevkitErrorCode::Unsupported => "unsupported",
        DevkitErrorCode::SensitiveInputUnavailable => "sensitive_input_unavailable",
        DevkitErrorCode::Internal => "internal",
    }
}

impl IntoResponse for ControlPlaneApiError {
    fn into_response(self) -> Response {
        (self.status, Json(self.body)).into_response()
    }
}
