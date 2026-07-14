use crate::api::{ApiError, AppState};
use agent_runtime::session::{
    ConversationEventRecord, ConversationTurn, Message, Session, SessionMutation, SessionPageCursor,
};
use axum::{
    Json, Router,
    extract::{Path, Query, State},
    http::StatusCode,
    response::{IntoResponse, Response},
    routing::get,
};
use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use std::sync::Arc;

const DEFAULT_PAGE_LIMIT: usize = 50;
const MAX_PAGE_LIMIT: usize = 100;
const MAX_CURSOR_BYTES: usize = 2_048;
const MAX_TITLE_BYTES: usize = 256;

pub(crate) fn routes() -> Router<Arc<AppState>> {
    Router::new()
        .route("/sessions", get(list_sessions).post(create_session))
        .route(
            "/sessions/{session_id}",
            get(load_session)
                .patch(update_session_title)
                .delete(delete_session),
        )
        .route("/sessions/{session_id}/messages", get(get_messages))
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
struct CreateSessionRequest {
    title: Option<String>,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
struct ListSessionsQuery {
    cursor: Option<String>,
    limit: Option<usize>,
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
struct SessionPageResponse {
    items: Vec<Session>,
    next_cursor: Option<String>,
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
struct SessionDetailResponse {
    session: Session,
    messages: Vec<Message>,
    events: Vec<ConversationEventRecord>,
    turns: Vec<ConversationTurn>,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
struct UpdateSessionRequest {
    title: String,
    expected_updated_at: DateTime<Utc>,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
struct DeleteSessionQuery {
    expected_updated_at: DateTime<Utc>,
}

#[derive(Debug, Deserialize, Serialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
struct SessionCursorWire {
    snapshot_at: DateTime<Utc>,
    updated_at: DateTime<Utc>,
    created_at: DateTime<Utc>,
    id: String,
}

async fn create_session(
    State(state): State<Arc<AppState>>,
    Json(request): Json<CreateSessionRequest>,
) -> Result<Json<Session>, ApiError> {
    let title = validate_title(request.title.as_deref().unwrap_or("New Session"))?;
    state
        .storage()
        .create_scoped_session(state.conversation_scope(), &title)
        .await
        .map(Json)
        .map_err(ApiError::Internal)
}

async fn list_sessions(
    State(state): State<Arc<AppState>>,
    Query(query): Query<ListSessionsQuery>,
) -> Result<Json<SessionPageResponse>, ApiError> {
    let limit = query.limit.unwrap_or(DEFAULT_PAGE_LIMIT);
    if !(1..=MAX_PAGE_LIMIT).contains(&limit) {
        return Err(ApiError::BadRequest("session page limit is invalid"));
    }
    let cursor = query.cursor.as_deref().map(decode_cursor).transpose()?;
    let page = state
        .storage()
        .list_scoped_sessions_page(state.conversation_scope(), cursor.as_ref(), limit)
        .await
        .map_err(ApiError::Internal)?;
    Ok(Json(SessionPageResponse {
        items: page.items,
        next_cursor: page.next_cursor.as_ref().map(encode_cursor).transpose()?,
    }))
}

async fn load_session(
    Path(session_id): Path<String>,
    State(state): State<Arc<AppState>>,
) -> Result<Json<SessionDetailResponse>, ApiError> {
    let lock = state.conversation_lock(&session_id).await;
    let _guard = lock.lock().await;
    let session = state
        .storage()
        .get_scoped_session(state.conversation_scope(), &session_id)
        .await
        .map_err(ApiError::Internal)?
        .ok_or(ApiError::NotFound("session not found"))?;
    let messages = state
        .storage()
        .list_scoped_messages(state.conversation_scope(), &session_id)
        .await
        .map_err(ApiError::Internal)?;
    let events = state
        .storage()
        .list_conversation_events(state.conversation_scope(), &session_id)
        .await
        .map_err(ApiError::Internal)?;
    let turns = state
        .storage()
        .list_scoped_turns(state.conversation_scope(), &session_id)
        .await
        .map_err(ApiError::Internal)?;
    Ok(Json(SessionDetailResponse {
        session,
        messages,
        events,
        turns,
    }))
}

async fn get_messages(
    Path(session_id): Path<String>,
    State(state): State<Arc<AppState>>,
) -> Result<Json<Vec<Message>>, ApiError> {
    let session = state
        .storage()
        .get_scoped_session(state.conversation_scope(), &session_id)
        .await
        .map_err(ApiError::Internal)?;
    if session.is_none() {
        return Err(ApiError::NotFound("session not found"));
    }
    state
        .storage()
        .list_scoped_messages(state.conversation_scope(), &session_id)
        .await
        .map(Json)
        .map_err(ApiError::Internal)
}

async fn update_session_title(
    Path(session_id): Path<String>,
    State(state): State<Arc<AppState>>,
    Json(request): Json<UpdateSessionRequest>,
) -> Result<Response, ApiError> {
    let title = validate_title(&request.title)?;
    let lock = state.conversation_lock(&session_id).await;
    let _guard = lock.lock().await;
    let outcome = state
        .storage()
        .update_scoped_session_title(
            state.conversation_scope(),
            &session_id,
            &title,
            request.expected_updated_at,
        )
        .await
        .map_err(ApiError::Internal)?;
    mutation_response(outcome)
}

async fn delete_session(
    Path(session_id): Path<String>,
    State(state): State<Arc<AppState>>,
    Query(query): Query<DeleteSessionQuery>,
) -> Result<Response, ApiError> {
    let lock = state.conversation_lock(&session_id).await;
    let _guard = lock.lock().await;
    let current = state
        .storage()
        .get_scoped_session(state.conversation_scope(), &session_id)
        .await
        .map_err(ApiError::Internal)?
        .ok_or(ApiError::NotFound("session not found"))?;
    if current.updated_at != query.expected_updated_at {
        return Ok(conflict_response(current));
    }
    if let Some(memory) = state.memory_tools() {
        memory
            .on_session_end(&session_id, Vec::new())
            .await
            .map_err(ApiError::Internal)?;
    }
    let outcome = state
        .storage()
        .delete_scoped_session_if_unchanged(
            state.conversation_scope(),
            &session_id,
            query.expected_updated_at,
        )
        .await
        .map_err(ApiError::Internal)?;
    match outcome {
        SessionMutation::Applied(_) => Ok(StatusCode::NO_CONTENT.into_response()),
        SessionMutation::Conflict(authoritative) => Ok(conflict_response(authoritative)),
        SessionMutation::NotFound => Err(ApiError::NotFound("session not found")),
    }
}

fn mutation_response(outcome: SessionMutation) -> Result<Response, ApiError> {
    match outcome {
        SessionMutation::Applied(session) => Ok(Json(session).into_response()),
        SessionMutation::Conflict(authoritative) => Ok(conflict_response(authoritative)),
        SessionMutation::NotFound => Err(ApiError::NotFound("session not found")),
    }
}

fn conflict_response(authoritative: Session) -> Response {
    (
        StatusCode::CONFLICT,
        Json(serde_json::json!({
            "error": "session changed; reload and retry",
            "authoritative": authoritative,
        })),
    )
        .into_response()
}

fn validate_title(value: &str) -> Result<String, ApiError> {
    let title = value.trim();
    if title.is_empty() || title.len() > MAX_TITLE_BYTES || title.chars().any(char::is_control) {
        return Err(ApiError::BadRequest("session title is invalid"));
    }
    Ok(title.to_string())
}

fn encode_cursor(cursor: &SessionPageCursor) -> Result<String, ApiError> {
    let wire = SessionCursorWire {
        snapshot_at: cursor.snapshot_at,
        updated_at: cursor.updated_at,
        created_at: cursor.created_at,
        id: cursor.id.clone(),
    };
    serde_json::to_vec(&wire)
        .map(hex::encode)
        .map_err(|error| ApiError::Internal(error.into()))
}

fn decode_cursor(value: &str) -> Result<SessionPageCursor, ApiError> {
    if value.is_empty() || value.len() > MAX_CURSOR_BYTES {
        return Err(ApiError::BadRequest("session cursor is invalid"));
    }
    let bytes =
        hex::decode(value).map_err(|_| ApiError::BadRequest("session cursor is invalid"))?;
    let wire: SessionCursorWire = serde_json::from_slice(&bytes)
        .map_err(|_| ApiError::BadRequest("session cursor is invalid"))?;
    if wire.id.is_empty()
        || wire.id.len() > 255
        || wire.updated_at > wire.snapshot_at
        || wire.created_at > wire.updated_at
    {
        return Err(ApiError::BadRequest("session cursor is invalid"));
    }
    Ok(SessionPageCursor {
        snapshot_at: wire.snapshot_at,
        updated_at: wire.updated_at,
        created_at: wire.created_at,
        id: wire.id,
    })
}

#[cfg(test)]
#[path = "conversation_api_tests.rs"]
mod tests;
