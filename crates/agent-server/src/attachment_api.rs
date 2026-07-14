use crate::api::{ApiError, AppState};
use agent_runtime::attachments::{AttachmentError, AttachmentMetadata, MAX_ATTACHMENT_BYTES};
use axum::{
    Json, Router,
    body::{Body, to_bytes},
    extract::{Path, Query, Request, State},
    http::{HeaderMap, HeaderValue, StatusCode, header},
    response::Response,
    routing::get,
};
use serde::Deserialize;
use serde_json::json;
use std::sync::Arc;

const IDEMPOTENCY_KEY: &str = "idempotency-key";

pub(crate) fn router() -> Router<Arc<AppState>> {
    Router::new()
        .route(
            "/foundation/attachments",
            get(list_attachments).post(import_attachment),
        )
        .route(
            "/foundation/attachments/{attachment_id}",
            get(get_attachment).delete(delete_attachment),
        )
        .route(
            "/foundation/attachments/{attachment_id}/content",
            get(get_attachment_content),
        )
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
struct AttachmentListQuery {
    #[serde(default = "default_limit")]
    limit: usize,
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
struct AttachmentImportQuery {
    file_name: String,
}

async fn list_attachments(
    State(state): State<Arc<AppState>>,
    Query(query): Query<AttachmentListQuery>,
) -> Result<Json<Vec<AttachmentMetadata>>, ApiError> {
    let runtime = attachment_runtime(&state)?;
    runtime
        .store()
        .list(&runtime.scope(), query.limit)
        .await
        .map(Json)
        .map_err(map_attachment_error)
}

async fn import_attachment(
    State(state): State<Arc<AppState>>,
    Query(query): Query<AttachmentImportQuery>,
    request: Request,
) -> Result<Json<AttachmentMetadata>, ApiError> {
    let runtime = attachment_runtime(&state)?;
    let mime_type = required_header(request.headers(), header::CONTENT_TYPE.as_str())?.to_string();
    let idempotency_key = required_header(request.headers(), IDEMPOTENCY_KEY)?.to_string();
    reject_oversized_content_length(request.headers())?;
    let bytes = to_bytes(request.into_body(), MAX_ATTACHMENT_BYTES)
        .await
        .map_err(|_| ApiError::PayloadTooLarge("attachment exceeds size limit"))?;
    runtime
        .store()
        .import(
            &runtime.scope(),
            &query.file_name,
            &mime_type,
            &bytes,
            &idempotency_key,
        )
        .await
        .map(Json)
        .map_err(map_attachment_error)
}

async fn get_attachment(
    State(state): State<Arc<AppState>>,
    Path(attachment_id): Path<String>,
) -> Result<Json<AttachmentMetadata>, ApiError> {
    let runtime = attachment_runtime(&state)?;
    runtime
        .store()
        .get(&runtime.scope(), &attachment_id)
        .await
        .map_err(map_attachment_error)?
        .map(Json)
        .ok_or(ApiError::NotFound("attachment not found"))
}

async fn get_attachment_content(
    State(state): State<Arc<AppState>>,
    Path(attachment_id): Path<String>,
) -> Result<Response, ApiError> {
    let runtime = attachment_runtime(&state)?;
    let metadata = runtime
        .store()
        .get(&runtime.scope(), &attachment_id)
        .await
        .map_err(map_attachment_error)?
        .ok_or(ApiError::NotFound("attachment not found"))?;
    let content = runtime
        .store()
        .content(&runtime.scope(), &attachment_id)
        .await
        .map_err(map_attachment_error)?;
    let content_type = HeaderValue::from_str(&metadata.mime_type)
        .map_err(|error| ApiError::Internal(error.into()))?;
    Response::builder()
        .status(StatusCode::OK)
        .header(header::CONTENT_TYPE, content_type)
        .header(header::CACHE_CONTROL, "no-store")
        .header("x-content-type-options", "nosniff")
        .body(Body::from(content))
        .map_err(|error| ApiError::Internal(error.into()))
}

async fn delete_attachment(
    State(state): State<Arc<AppState>>,
    Path(attachment_id): Path<String>,
) -> Result<Json<serde_json::Value>, ApiError> {
    let runtime = attachment_runtime(&state)?;
    let deleted = runtime
        .store()
        .delete(&runtime.scope(), &attachment_id)
        .await
        .map_err(map_attachment_error)?;
    if !deleted {
        return Err(ApiError::NotFound("attachment not found"));
    }
    Ok(Json(json!({"deleted": true})))
}

fn attachment_runtime(
    state: &AppState,
) -> Result<agent_runtime::attachment_tools::AttachmentToolRuntime, ApiError> {
    state
        .attachment_tools()
        .ok_or(ApiError::NotFound("Attachments Foundation is disabled"))
}

fn required_header<'a>(headers: &'a HeaderMap, name: &str) -> Result<&'a str, ApiError> {
    headers
        .get(name)
        .ok_or(ApiError::BadRequest("attachment header is required"))?
        .to_str()
        .map_err(|_| ApiError::BadRequest("attachment header is invalid"))
}

fn reject_oversized_content_length(headers: &HeaderMap) -> Result<(), ApiError> {
    let Some(value) = headers.get(header::CONTENT_LENGTH) else {
        return Ok(());
    };
    let value = value
        .to_str()
        .ok()
        .and_then(|value| value.parse::<usize>().ok())
        .ok_or(ApiError::BadRequest("attachment content length is invalid"))?;
    if value > MAX_ATTACHMENT_BYTES {
        Err(ApiError::PayloadTooLarge("attachment exceeds size limit"))
    } else {
        Ok(())
    }
}

fn map_attachment_error(error: AttachmentError) -> ApiError {
    match error {
        AttachmentError::InvalidRequest(_) => ApiError::BadRequest("attachment request is invalid"),
        AttachmentError::NotFound => ApiError::NotFound("attachment not found"),
        AttachmentError::IdempotencyConflict => {
            ApiError::Conflict("attachment idempotency conflict")
        }
        AttachmentError::TooLarge => ApiError::PayloadTooLarge("attachment exceeds size limit"),
        AttachmentError::Unavailable => {
            ApiError::Internal(anyhow::anyhow!("attachment store is unavailable"))
        }
    }
}

fn default_limit() -> usize {
    25
}
