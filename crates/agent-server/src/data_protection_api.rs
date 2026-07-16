use crate::api::{ApiError, AppState};
use crate::data_protection::{DataProtectionService, MAX_BACKUP_BYTES, disabled_status};
use agent_runtime::data_protection::DataProtectionError;
use axum::{
    Json, Router,
    body::{Body, to_bytes},
    extract::{Request, State},
    http::{StatusCode, header},
    response::Response,
    routing::{get, post},
};
use std::sync::Arc;

pub(crate) fn router() -> Router<Arc<AppState>> {
    Router::new()
        .route(
            "/foundation/data-protection/status",
            get(data_protection_status),
        )
        .route("/foundation/data-protection/backup", get(create_backup))
        .route("/foundation/data-protection/restore", post(stage_restore))
}

async fn data_protection_status(
    State(state): State<Arc<AppState>>,
) -> Json<crate::data_protection::DataProtectionStatus> {
    Json(
        state
            .data_protection()
            .map(DataProtectionService::status)
            .unwrap_or_else(|| disabled_status(state.storage().protection_status().state())),
    )
}

async fn create_backup(State(state): State<Arc<AppState>>) -> Result<Response, ApiError> {
    let backup = service(&state)?.create_backup().await.map_err(map_error)?;
    Response::builder()
        .status(StatusCode::OK)
        .header(header::CONTENT_TYPE, "application/vnd.agentweave.backup")
        .header(header::CACHE_CONTROL, "no-store")
        .header(
            "x-agentweave-backup-created-at",
            backup.metadata.created_at.to_rfc3339(),
        )
        .header(
            "x-agentweave-backup-sha256",
            &backup.metadata.envelope_sha256,
        )
        .header("x-agentweave-backup-bytes", backup.bytes.len().to_string())
        .body(Body::from(backup.bytes))
        .map_err(|error| ApiError::Internal(error.into()))
}

async fn stage_restore(
    State(state): State<Arc<AppState>>,
    request: Request,
) -> Result<Json<crate::data_protection::RestoreReceipt>, ApiError> {
    validate_content_length(request.headers().get(header::CONTENT_LENGTH))?;
    let restore_key = restore_key(request.headers().get("x-agentweave-backup-key"))?;
    let bytes = to_bytes(request.into_body(), MAX_BACKUP_BYTES)
        .await
        .map_err(|_| ApiError::PayloadTooLarge("backup exceeds size limit"))?;
    let service = service(&state)?;
    let restore = match restore_key {
        Some(key) => service.stage_restore_with_key(&bytes, key).await,
        None => service.stage_restore(&bytes).await,
    };
    restore.map(Json).map_err(map_error)
}

fn validate_content_length(value: Option<&axum::http::HeaderValue>) -> Result<(), ApiError> {
    let Some(value) = value else {
        return Ok(());
    };
    let length = value
        .to_str()
        .ok()
        .and_then(|value| value.parse::<usize>().ok())
        .ok_or(ApiError::BadRequest("backup content length is invalid"))?;
    if length > MAX_BACKUP_BYTES {
        Err(ApiError::PayloadTooLarge("backup exceeds size limit"))
    } else {
        Ok(())
    }
}

fn restore_key(
    value: Option<&axum::http::HeaderValue>,
) -> Result<Option<agent_runtime::credential::SecretMaterial>, ApiError> {
    let Some(value) = value else {
        return Ok(None);
    };
    let decoded = value
        .to_str()
        .ok()
        .filter(|value| {
            value.len() == 64
                && value
                    .bytes()
                    .all(|byte| byte.is_ascii_digit() || matches!(byte, b'a'..=b'f'))
        })
        .and_then(|value| hex::decode(value).ok())
        .filter(|value| value.len() == 32)
        .ok_or(ApiError::BadRequest("backup key is invalid"))?;
    agent_runtime::credential::SecretMaterial::new(decoded)
        .map(Some)
        .map_err(|_| ApiError::BadRequest("backup key is invalid"))
}

fn service(state: &AppState) -> Result<DataProtectionService, ApiError> {
    state
        .data_protection()
        .cloned()
        .ok_or(ApiError::NotFound("Data Protection is disabled"))
}

fn map_error(error: anyhow::Error) -> ApiError {
    match error.downcast_ref::<DataProtectionError>() {
        Some(DataProtectionError::AppMismatch) => {
            ApiError::Conflict("backup belongs to another App")
        }
        Some(DataProtectionError::InvalidRequest)
        | Some(DataProtectionError::AuthenticationFailed) => {
            ApiError::BadRequest("backup is invalid or cannot be authenticated")
        }
        None if error.to_string().contains("already pending") => {
            ApiError::Conflict("a database restore is already pending")
        }
        None if error.to_string().contains("size limit") => {
            ApiError::PayloadTooLarge("backup exceeds size limit")
        }
        None if error.to_string().contains("integrity check")
            || error.to_string().contains("schema is incompatible") =>
        {
            ApiError::BadRequest("backup database is invalid or incompatible")
        }
        _ => ApiError::Internal(error),
    }
}
