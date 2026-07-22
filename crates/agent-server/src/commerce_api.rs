use crate::api::AppState;
use axum::extract::State;
use axum::http::StatusCode;
use axum::response::{IntoResponse, Response};
use axum::{Json, Router, routing::get, routing::post};
use serde::Deserialize;
use serde_json::{Value, json};
use std::sync::Arc;
use url::Url;
use uuid::Uuid;

const MAX_RESPONSE_BYTES: usize = 256 * 1024;
const MANAGED_ENTITLEMENT_ID: &str = "agentweave.entitlements.cloudflare_policy";

pub(crate) fn routes() -> Router<Arc<AppState>> {
    Router::new()
        .route("/commerce/status", get(status))
        .route("/commerce/checkout", post(checkout))
        .route("/commerce/customer-portal", post(customer_portal))
        .route(
            "/commerce/customer-portal/verified",
            post(customer_portal_verified),
        )
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
struct CheckoutRequest {
    plan_id: String,
}

async fn status(State(state): State<Arc<AppState>>) -> Result<Json<Value>, CommerceApiError> {
    proxy(&state, reqwest::Method::GET, "status", None).await
}

async fn checkout(
    State(state): State<Arc<AppState>>,
    Json(request): Json<CheckoutRequest>,
) -> Result<Json<Value>, CommerceApiError> {
    if request.plan_id.is_empty()
        || request.plan_id.len() > 128
        || request.plan_id.chars().any(char::is_control)
    {
        return Err(CommerceApiError::invalid("commerce_plan_invalid"));
    }
    let nonce = Uuid::new_v4().simple().to_string();
    proxy(
        &state,
        reqwest::Method::POST,
        "checkout",
        Some(json!({
            "planId": request.plan_id,
            "requestId": format!("request_{}", Uuid::new_v4().simple()),
            "requestNonce": nonce,
        })),
    )
    .await
}

async fn customer_portal(
    State(state): State<Arc<AppState>>,
) -> Result<Json<Value>, CommerceApiError> {
    let nonce = Uuid::new_v4().simple().to_string();
    let Json(mut value) = proxy(
        &state,
        reqwest::Method::POST,
        "customer-portal",
        Some(json!({"requestNonce": nonce.clone()})),
    )
    .await?;
    value
        .as_object_mut()
        .ok_or_else(|| CommerceApiError::unavailable("commerce_invalid_response"))?
        .insert("verificationNonce".into(), json!(nonce));
    Ok(Json(value))
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
struct CustomerPortalVerifiedRequest {
    verification_nonce: String,
}

async fn customer_portal_verified(
    State(state): State<Arc<AppState>>,
    Json(request): Json<CustomerPortalVerifiedRequest>,
) -> Result<Json<Value>, CommerceApiError> {
    if request.verification_nonce.len() < 16
        || request.verification_nonce.len() > 256
        || !request
            .verification_nonce
            .bytes()
            .all(|byte| byte.is_ascii_alphanumeric() || matches!(byte, b'_' | b'-'))
    {
        return Err(CommerceApiError::invalid("commerce_invalid_request"));
    }
    proxy(
        &state,
        reqwest::Method::POST,
        "customer-portal/verified",
        Some(json!({"requestNonce": request.verification_nonce})),
    )
    .await
}

async fn proxy(
    state: &AppState,
    method: reqwest::Method,
    endpoint: &str,
    body: Option<Value>,
) -> Result<Json<Value>, CommerceApiError> {
    let base = entitlement_base_url(state)?;
    let url = base
        .join(&format!("agentweave/commerce/v1/{endpoint}"))
        .map_err(|_| CommerceApiError::unavailable("commerce_not_configured"))?;
    let assertion = state
        .identity_runtime()
        .ok_or_else(|| CommerceApiError::unauthorized("commerce_unauthenticated"))?
        .gateway_test_assertion()
        .await
        .map_err(|_| CommerceApiError::unauthorized("commerce_unauthenticated"))?;
    let client = reqwest::Client::builder()
        .redirect(reqwest::redirect::Policy::none())
        .timeout(std::time::Duration::from_secs(15))
        .build()
        .map_err(|_| CommerceApiError::unavailable("commerce_unavailable"))?;
    let mut request = client
        .request(method, url)
        .bearer_auth(assertion.expose_secret())
        .header("accept", "application/json");
    if let Some(body) = body {
        request = request.json(&body);
    }
    let response = request
        .send()
        .await
        .map_err(|_| CommerceApiError::unavailable("commerce_unavailable"))?;
    if response.status().is_redirection() {
        return Err(CommerceApiError::unavailable("commerce_invalid_response"));
    }
    let status = response.status();
    let declared = response
        .content_length()
        .and_then(|value| usize::try_from(value).ok());
    if declared.is_some_and(|length| length > MAX_RESPONSE_BYTES) {
        return Err(CommerceApiError::unavailable("commerce_invalid_response"));
    }
    let bytes = response
        .bytes()
        .await
        .map_err(|_| CommerceApiError::unavailable("commerce_unavailable"))?;
    if bytes.is_empty() || bytes.len() > MAX_RESPONSE_BYTES {
        return Err(CommerceApiError::unavailable("commerce_invalid_response"));
    }
    let value: Value = serde_json::from_slice(&bytes)
        .map_err(|_| CommerceApiError::unavailable("commerce_invalid_response"))?;
    if !status.is_success() {
        let code = value
            .get("code")
            .and_then(Value::as_str)
            .filter(|code| valid_error_code(code))
            .unwrap_or("commerce_unavailable");
        return Err(CommerceApiError::new(status, code));
    }
    Ok(Json(value))
}

fn entitlement_base_url(state: &AppState) -> Result<Url, CommerceApiError> {
    let provider = state
        .host_discovery()
        .and_then(|discovery| discovery.access.entitlements.provider.as_ref())
        .filter(|provider| provider.id.as_str() == MANAGED_ENTITLEMENT_ID)
        .ok_or_else(|| CommerceApiError::unavailable("commerce_not_configured"))?;
    let value = provider
        .public_config
        .get("baseUrl")
        .and_then(Value::as_str)
        .ok_or_else(|| CommerceApiError::unavailable("commerce_not_configured"))?;
    let mut url =
        Url::parse(value).map_err(|_| CommerceApiError::unavailable("commerce_not_configured"))?;
    if url.scheme() != "https"
        || url.host_str().is_none()
        || !url.username().is_empty()
        || url.password().is_some()
        || url.query().is_some()
        || url.fragment().is_some()
    {
        return Err(CommerceApiError::unavailable("commerce_not_configured"));
    }
    url.set_path("/");
    Ok(url)
}

fn valid_error_code(value: &str) -> bool {
    value.starts_with("commerce_")
        && value.len() <= 128
        && value
            .bytes()
            .all(|byte| byte.is_ascii_lowercase() || byte.is_ascii_digit() || byte == b'_')
}

struct CommerceApiError {
    status: StatusCode,
    code: String,
}

impl CommerceApiError {
    fn new(status: StatusCode, code: &str) -> Self {
        Self {
            status,
            code: code.into(),
        }
    }

    fn invalid(code: &str) -> Self {
        Self::new(StatusCode::UNPROCESSABLE_ENTITY, code)
    }

    fn unauthorized(code: &str) -> Self {
        Self::new(StatusCode::UNAUTHORIZED, code)
    }

    fn unavailable(code: &str) -> Self {
        Self::new(StatusCode::SERVICE_UNAVAILABLE, code)
    }
}

impl IntoResponse for CommerceApiError {
    fn into_response(self) -> Response {
        (
            self.status,
            Json(json!({
                "code": self.code,
                "message": "The billing operation could not be completed.",
            })),
        )
            .into_response()
    }
}
