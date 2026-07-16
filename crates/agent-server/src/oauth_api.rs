use crate::api::{ApiError, AppState};
use agent_runtime::oauth::{
    OAuthAuthorizationRequest, OAuthAuthorizationStatus, OAuthCallbackRequest, OAuthSecretString,
};
use axum::{
    Json, Router,
    extract::{Path, RawQuery, State},
    http::{StatusCode, header},
    response::{Html, IntoResponse, Response},
    routing::{get, post},
};
use chrono::Utc;
use std::sync::Arc;

const MAX_CALLBACK_QUERY_BYTES: usize = 32 * 1024;
const CALLBACK_SUCCESS_HTML: &str = "<!doctype html><html><head><meta charset=\"utf-8\"><title>Authorization complete</title></head><body><main><h1>Authorization complete</h1><p>You can return to the app.</p></main></body></html>";
const CALLBACK_FAILURE_HTML: &str = "<!doctype html><html><head><meta charset=\"utf-8\"><title>Authorization not completed</title></head><body><main><h1>Authorization not completed</h1><p>Return to the app and try again.</p></main></body></html>";

pub(crate) fn protected_router() -> Router<Arc<AppState>> {
    Router::new()
        .route("/host/oauth/authorizations", post(start_authorization))
        .route(
            "/host/oauth/authorizations/{authorization_id}",
            get(authorization_status).delete(cancel_authorization),
        )
}

pub(crate) fn callback_router() -> Router<Arc<AppState>> {
    Router::new().route("/oauth/callback", get(oauth_callback))
}

async fn start_authorization(
    State(state): State<Arc<AppState>>,
    Json(request): Json<OAuthAuthorizationRequest>,
) -> Result<Response, ApiError> {
    let broker = broker(&state)?;
    broker
        .start(request, Utc::now())
        .await
        .map(no_store_json)
        .map_err(map_start_error)
}

async fn authorization_status(
    Path(authorization_id): Path<String>,
    State(state): State<Arc<AppState>>,
) -> Result<Response, ApiError> {
    validate_authorization_id(&authorization_id)?;
    broker(&state)?
        .status(&authorization_id)
        .await
        .map_err(ApiError::Internal)?
        .map(no_store_json)
        .ok_or(ApiError::NotFound("OAuth authorization was not found"))
}

async fn cancel_authorization(
    Path(authorization_id): Path<String>,
    State(state): State<Arc<AppState>>,
) -> Result<Response, ApiError> {
    validate_authorization_id(&authorization_id)?;
    broker(&state)?
        .cancel(&authorization_id, Utc::now())
        .await
        .map_err(ApiError::Internal)?
        .map(no_store_json)
        .ok_or(ApiError::NotFound("OAuth authorization was not found"))
}

async fn oauth_callback(
    State(state): State<Arc<AppState>>,
    RawQuery(raw_query): RawQuery,
) -> Response {
    let request = match parse_callback_query(raw_query.as_deref()) {
        Ok(request) => request,
        Err(CallbackQueryError::Invalid) => {
            return callback_page(StatusCode::BAD_REQUEST, false);
        }
        Err(CallbackQueryError::TooLarge) => {
            return callback_page(StatusCode::PAYLOAD_TOO_LARGE, false);
        }
    };
    let Some(broker) = state.oauth_broker() else {
        return callback_page(StatusCode::NOT_FOUND, false);
    };
    match broker.callback(request, Utc::now()).await {
        Ok(view) => callback_page(
            StatusCode::OK,
            view.status == OAuthAuthorizationStatus::Completed,
        ),
        Err(_) => callback_page(StatusCode::BAD_REQUEST, false),
    }
}

fn broker(state: &AppState) -> Result<&agent_runtime::oauth::OAuthBroker, ApiError> {
    state
        .oauth_broker()
        .ok_or(ApiError::NotFound("OAuth authorization is disabled"))
}

fn no_store_json<T: serde::Serialize>(value: T) -> Response {
    (
        [
            (header::CACHE_CONTROL, "no-store"),
            (header::PRAGMA, "no-cache"),
        ],
        Json(value),
    )
        .into_response()
}

fn validate_authorization_id(value: &str) -> Result<(), ApiError> {
    if !value.is_empty()
        && value.len() <= 255
        && value
            .bytes()
            .all(|byte| byte.is_ascii_alphanumeric() || b"._-".contains(&byte))
    {
        Ok(())
    } else {
        Err(ApiError::BadRequest(
            "OAuth authorization identifier is invalid",
        ))
    }
}

fn map_start_error(error: anyhow::Error) -> ApiError {
    let message = error.to_string();
    if message == "OAuth provider is unavailable" {
        ApiError::NotFound("OAuth provider is unavailable")
    } else if message.starts_with("OAuth provider is invalid")
        || message.starts_with("OAuth Connector")
        || message.starts_with("OAuth capability")
        || matches!(
            message.as_str(),
            "provider_invalid_request"
                | "permission_insufficient"
                | "authorization_denied"
                | "provider_unavailable"
        )
    {
        ApiError::BadRequest("OAuth authorization request is invalid")
    } else {
        ApiError::Internal(error)
    }
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
enum CallbackQueryError {
    Invalid,
    TooLarge,
}

fn parse_callback_query(
    raw_query: Option<&str>,
) -> Result<OAuthCallbackRequest, CallbackQueryError> {
    let raw_query = raw_query.ok_or(CallbackQueryError::Invalid)?;
    if raw_query.len() > MAX_CALLBACK_QUERY_BYTES {
        return Err(CallbackQueryError::TooLarge);
    }
    if !valid_percent_escapes(raw_query.as_bytes()) {
        return Err(CallbackQueryError::Invalid);
    }
    let mut state = None;
    let mut code = None;
    let mut error = None;
    let mut pair_count = 0_usize;
    for (key, value) in url::form_urlencoded::parse(raw_query.as_bytes()) {
        pair_count += 1;
        if pair_count > 64 {
            return Err(CallbackQueryError::Invalid);
        }
        match key.as_ref() {
            "state" => {
                if state.replace(value.into_owned()).is_some() {
                    return Err(CallbackQueryError::Invalid);
                }
            }
            "code" => {
                if code.replace(value.into_owned()).is_some() {
                    return Err(CallbackQueryError::Invalid);
                }
            }
            "error" => {
                if error.replace(value.into_owned()).is_some() {
                    return Err(CallbackQueryError::Invalid);
                }
            }
            _ => {}
        }
    }
    let state = state.ok_or(CallbackQueryError::Invalid)?;
    if state.len() != 64 || !state.bytes().all(|byte| byte.is_ascii_hexdigit()) {
        return Err(CallbackQueryError::Invalid);
    }
    let code = code
        .map(OAuthSecretString::new)
        .transpose()
        .map_err(|_| CallbackQueryError::Invalid)?;
    Ok(OAuthCallbackRequest { state, code, error })
}

fn valid_percent_escapes(value: &[u8]) -> bool {
    let mut index = 0;
    while index < value.len() {
        if value[index] == b'%' {
            if index + 2 >= value.len()
                || !value[index + 1].is_ascii_hexdigit()
                || !value[index + 2].is_ascii_hexdigit()
            {
                return false;
            }
            index += 3;
        } else {
            index += 1;
        }
    }
    true
}

fn callback_page(status: StatusCode, success: bool) -> Response {
    let html = if success {
        CALLBACK_SUCCESS_HTML
    } else {
        CALLBACK_FAILURE_HTML
    };
    (
        status,
        [
            (header::CACHE_CONTROL, "no-store"),
            (header::CONTENT_SECURITY_POLICY, "default-src 'none'"),
            (header::REFERRER_POLICY, "no-referrer"),
            (header::X_CONTENT_TYPE_OPTIONS, "nosniff"),
            (header::X_FRAME_OPTIONS, "DENY"),
        ],
        Html(html),
    )
        .into_response()
}

#[cfg(test)]
#[path = "oauth_api_tests.rs"]
mod tests;
