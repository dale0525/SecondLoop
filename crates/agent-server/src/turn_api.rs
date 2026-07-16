use crate::api::{ApiError, AppState, ModelConnectionTestRequest, UserMessageRequest};
use agent_runtime::{
    events::RuntimeEvent,
    session::{
        ConversationEventRecord, ConversationTurn, ConversationTurnStatus, Message,
        messages_to_model_history,
    },
    skill_policy::ActorContext,
    turn::RuntimeEventObserver,
    turn_storage::{ConversationTurnCompletion, TURN_REQUEST_CONFLICT_MESSAGE},
};
use axum::{
    Json, Router,
    extract::{Path, Query, State},
    http::StatusCode,
    response::{IntoResponse, Response},
    routing::{get, post},
};
use serde::{Deserialize, Serialize};
use std::{collections::BTreeMap, sync::Arc, time::Duration};
use tokio::sync::{Mutex, mpsc};
use tokio_util::sync::CancellationToken;

const MAX_CONTENT_BYTES: usize = 1024 * 1024;
const MAX_WAIT_MS: u64 = 25_000;
const DEFAULT_EVENT_LIMIT: usize = 100;

#[derive(Clone, Default)]
pub(crate) struct TurnCoordinator {
    inner: Arc<Mutex<ActiveTurns>>,
}

#[derive(Default)]
struct ActiveTurns {
    by_session: BTreeMap<String, String>,
    cancellations: BTreeMap<String, CancellationToken>,
}

impl TurnCoordinator {
    async fn register(&self, session_id: &str, turn_id: &str) -> Option<CancellationToken> {
        let mut active = self.inner.lock().await;
        if active.by_session.contains_key(session_id) {
            return None;
        }
        let cancellation = CancellationToken::new();
        active
            .by_session
            .insert(session_id.to_string(), turn_id.to_string());
        active
            .cancellations
            .insert(turn_id.to_string(), cancellation.clone());
        Some(cancellation)
    }

    async fn cancel(&self, session_id: &str, turn_id: &str) -> bool {
        let active = self.inner.lock().await;
        if active.by_session.get(session_id).map(String::as_str) != Some(turn_id) {
            return false;
        }
        let Some(cancellation) = active.cancellations.get(turn_id) else {
            return false;
        };
        cancellation.cancel();
        true
    }

    async fn remove(&self, session_id: &str, turn_id: &str) {
        let mut active = self.inner.lock().await;
        if active.by_session.get(session_id).map(String::as_str) == Some(turn_id) {
            active.by_session.remove(session_id);
        }
        active.cancellations.remove(turn_id);
    }
}

pub(crate) fn routes() -> Router<Arc<AppState>> {
    Router::new()
        .route("/sessions/{session_id}/turns", post(start_turn))
        .route(
            "/sessions/{session_id}/turns/{turn_id}/events",
            get(list_turn_events),
        )
        .route(
            "/sessions/{session_id}/turns/{turn_id}/cancel",
            post(cancel_turn),
        )
}

#[derive(Clone, Debug, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
struct StartTurnRequest {
    request_id: String,
    content: String,
    #[serde(default)]
    model_settings: Option<ModelConnectionTestRequest>,
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
struct StartTurnResponse {
    turn: ConversationTurn,
    user_message: Message,
    reused: bool,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
struct TurnEventsQuery {
    #[serde(default = "default_after")]
    after: i64,
    #[serde(default = "default_event_limit")]
    limit: usize,
    #[serde(default)]
    wait_ms: u64,
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
struct TurnEventsResponse {
    turn: ConversationTurn,
    events: Vec<ConversationEventRecord>,
    next_cursor: i64,
    has_more: bool,
}

#[derive(Debug, Serialize)]
struct CancelTurnResponse {
    accepted: bool,
    turn: ConversationTurn,
}

async fn start_turn(
    Path(session_id): Path<String>,
    State(state): State<Arc<AppState>>,
    Json(request): Json<StartTurnRequest>,
) -> Result<Response, ApiError> {
    validate_start_request(&request)?;
    let conversation_lock = state.conversation_lock(&session_id).await;
    let guard = conversation_lock.lock_owned().await;
    if !state
        .storage()
        .session_exists_scoped(state.conversation_scope(), &session_id)
        .await
        .map_err(ApiError::Internal)?
    {
        return Err(ApiError::NotFound("session not found"));
    }
    let history = state
        .storage()
        .list_scoped_messages(state.conversation_scope(), &session_id)
        .await
        .map_err(ApiError::Internal)?;
    let history = messages_to_model_history(&history).map_err(ApiError::Internal)?;
    let started = state
        .storage()
        .begin_scoped_turn(
            state.conversation_scope(),
            &session_id,
            &request.request_id,
            &request.content,
        )
        .await
        .map_err(|error| {
            if error.to_string() == TURN_REQUEST_CONFLICT_MESSAGE {
                ApiError::Conflict(TURN_REQUEST_CONFLICT_MESSAGE)
            } else {
                ApiError::Internal(error)
            }
        })?;
    if !started.created {
        return Ok(Json(StartTurnResponse {
            turn: started.turn,
            user_message: started.user_message,
            reused: true,
        })
        .into_response());
    }
    let Some(cancellation) = state
        .turn_coordinator()
        .register(&session_id, &started.turn.id)
        .await
    else {
        return Ok((
            StatusCode::CONFLICT,
            Json(serde_json::json!({ "error": "session already has a running turn" })),
        )
            .into_response());
    };
    let response = StartTurnResponse {
        turn: started.turn.clone(),
        user_message: started.user_message,
        reused: false,
    };
    tokio::spawn(run_turn(
        state,
        session_id,
        started.turn.id,
        request,
        history,
        cancellation,
        guard,
    ));
    Ok((StatusCode::ACCEPTED, Json(response)).into_response())
}

async fn run_turn(
    state: Arc<AppState>,
    session_id: String,
    turn_id: String,
    request: StartTurnRequest,
    history: Vec<serde_json::Value>,
    cancellation: CancellationToken,
    _guard: tokio::sync::OwnedMutexGuard<()>,
) {
    let (sender, mut receiver) = mpsc::unbounded_channel();
    let observer: RuntimeEventObserver = Arc::new(move |event| {
        let _ = sender.send(event);
    });
    let user_request = UserMessageRequest {
        content: request.content,
        model_settings: request.model_settings,
    };
    let execution = crate::api::run_agent_turn_observed_for_actor(
        &state,
        &session_id,
        &turn_id,
        &user_request,
        ActorContext::anonymous(),
        history,
        observer,
    );
    tokio::pin!(execution);
    let outcome = loop {
        tokio::select! {
            biased;
            _ = cancellation.cancelled() => break TurnOutcome::Cancelled,
            event = receiver.recv() => {
                let Some(event) = event else { continue };
                if is_terminal_event(&event) { continue; }
                if state.storage().append_scoped_turn_event(
                    state.conversation_scope(),
                    &session_id,
                    &turn_id,
                    &event,
                ).await.is_err() {
                    break TurnOutcome::Failed("could not persist turn progress".into());
                }
            }
            result = &mut execution => break match result {
                Ok(events) => TurnOutcome::Events(events),
                Err(_) => TurnOutcome::Failed("agent turn failed".into()),
            },
        }
    };
    while let Ok(event) = receiver.try_recv() {
        if is_terminal_event(&event) {
            continue;
        }
        if state
            .storage()
            .append_scoped_turn_event(state.conversation_scope(), &session_id, &turn_id, &event)
            .await
            .is_err()
        {
            break;
        }
    }
    let (status, terminal, assistant, failure) = finalize_outcome(&turn_id, outcome);
    if let Err(error) = state
        .storage()
        .finish_scoped_turn(
            state.conversation_scope(),
            &session_id,
            &turn_id,
            ConversationTurnCompletion {
                status,
                terminal_event: &terminal,
                assistant_content: assistant.as_deref(),
                failure_message: failure.as_deref(),
            },
        )
        .await
    {
        tracing::error!(?error, turn_id, "failed to finalize conversation turn");
    }
    state.turn_coordinator().remove(&session_id, &turn_id).await;
}

enum TurnOutcome {
    Events(Vec<RuntimeEvent>),
    Cancelled,
    Failed(String),
}

fn finalize_outcome(
    turn_id: &str,
    outcome: TurnOutcome,
) -> (
    ConversationTurnStatus,
    RuntimeEvent,
    Option<String>,
    Option<String>,
) {
    match outcome {
        TurnOutcome::Cancelled => (
            ConversationTurnStatus::Cancelled,
            RuntimeEvent::TurnCancelled {
                turn_id: turn_id.into(),
            },
            None,
            None,
        ),
        TurnOutcome::Failed(message) => (
            ConversationTurnStatus::Failed,
            RuntimeEvent::TurnFailed {
                turn_id: turn_id.into(),
                message: message.clone(),
            },
            None,
            Some(message),
        ),
        TurnOutcome::Events(events) => {
            let assistant = assistant_text(&events);
            match events.iter().rev().find(|event| is_terminal_event(event)) {
                Some(RuntimeEvent::TurnFinished { .. }) => (
                    ConversationTurnStatus::Completed,
                    RuntimeEvent::TurnFinished {
                        turn_id: turn_id.into(),
                    },
                    assistant,
                    None,
                ),
                Some(RuntimeEvent::TurnCancelled { .. }) => (
                    ConversationTurnStatus::Cancelled,
                    RuntimeEvent::TurnCancelled {
                        turn_id: turn_id.into(),
                    },
                    assistant,
                    None,
                ),
                Some(RuntimeEvent::TurnFailed { message, .. }) => (
                    ConversationTurnStatus::Failed,
                    RuntimeEvent::TurnFailed {
                        turn_id: turn_id.into(),
                        message: message.clone(),
                    },
                    assistant,
                    Some(message.clone()),
                ),
                _ => {
                    let message = "agent turn ended without a terminal event".to_string();
                    (
                        ConversationTurnStatus::Failed,
                        RuntimeEvent::TurnFailed {
                            turn_id: turn_id.into(),
                            message: message.clone(),
                        },
                        assistant,
                        Some(message),
                    )
                }
            }
        }
    }
}

async fn list_turn_events(
    Path((session_id, turn_id)): Path<(String, String)>,
    State(state): State<Arc<AppState>>,
    Query(query): Query<TurnEventsQuery>,
) -> Result<Json<TurnEventsResponse>, ApiError> {
    if query.after < -1 || !(1..=100).contains(&query.limit) || query.wait_ms > MAX_WAIT_MS {
        return Err(ApiError::BadRequest("turn event query is invalid"));
    }
    let deadline = tokio::time::Instant::now() + Duration::from_millis(query.wait_ms);
    let mut after = query.after;
    loop {
        let page = state
            .storage()
            .list_scoped_turn_events_page(
                state.conversation_scope(),
                &session_id,
                &turn_id,
                after,
                query.limit,
            )
            .await
            .map_err(ApiError::Internal)?
            .ok_or(ApiError::NotFound("turn not found"))?;
        after = page.next_cursor;
        let events = crate::event_visibility::user_visible_events(page.events);
        if !events.is_empty()
            || page.has_more
            || page.turn.status.is_terminal()
            || query.wait_ms == 0
            || tokio::time::Instant::now() >= deadline
        {
            return Ok(Json(TurnEventsResponse {
                turn: page.turn,
                events,
                next_cursor: after,
                has_more: page.has_more,
            }));
        }
        tokio::time::sleep(Duration::from_millis(50)).await;
    }
}

async fn cancel_turn(
    Path((session_id, turn_id)): Path<(String, String)>,
    State(state): State<Arc<AppState>>,
) -> Result<Json<CancelTurnResponse>, ApiError> {
    let turn = state
        .storage()
        .get_scoped_turn(state.conversation_scope(), &session_id, &turn_id)
        .await
        .map_err(ApiError::Internal)?
        .ok_or(ApiError::NotFound("turn not found"))?;
    let accepted =
        !turn.status.is_terminal() && state.turn_coordinator().cancel(&session_id, &turn_id).await;
    Ok(Json(CancelTurnResponse { accepted, turn }))
}

fn validate_start_request(request: &StartTurnRequest) -> Result<(), ApiError> {
    if request.content.trim().is_empty()
        || request.content.len() > MAX_CONTENT_BYTES
        || request.request_id.is_empty()
        || request.request_id.len() > 128
        || !request
            .request_id
            .bytes()
            .all(|byte| byte.is_ascii_alphanumeric() || matches!(byte, b'-' | b'_' | b'.'))
    {
        return Err(ApiError::BadRequest("turn request is invalid"));
    }
    Ok(())
}

fn assistant_text(events: &[RuntimeEvent]) -> Option<String> {
    events.iter().find_map(|event| match event {
        RuntimeEvent::AssistantMessageFinished { text } => Some(text.clone()),
        _ => None,
    })
}

fn is_terminal_event(event: &RuntimeEvent) -> bool {
    matches!(
        event,
        RuntimeEvent::TurnFinished { .. }
            | RuntimeEvent::TurnCancelled { .. }
            | RuntimeEvent::TurnFailed { .. }
    )
}

const fn default_after() -> i64 {
    -1
}

const fn default_event_limit() -> usize {
    DEFAULT_EVENT_LIMIT
}

#[cfg(test)]
#[path = "turn_api_tests.rs"]
mod tests;
