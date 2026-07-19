use crate::api::{ApiError, AppState};
use agent_runtime::tasks::{TaskContent, TaskError, TaskStatus};
use axum::{
    Json, Router,
    extract::{Extension, Path, Query, State},
    routing::{get, post},
};
use chrono::{DateTime, Utc};
use serde::Deserialize;
use std::sync::Arc;

pub(crate) fn router() -> Router<Arc<AppState>> {
    Router::new()
        .route("/foundation/tasks", get(list_tasks).post(create_task))
        .route(
            "/foundation/tasks/{task_id}",
            get(get_task).patch(update_task).delete(delete_task),
        )
        .route("/foundation/tasks/{task_id}/status", post(set_task_status))
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
struct TaskListQuery {
    status: Option<TaskStatus>,
    due_after: Option<DateTime<Utc>>,
    due_before: Option<DateTime<Utc>>,
    tag: Option<String>,
    text: Option<String>,
    cursor: Option<String>,
    #[serde(default = "default_limit")]
    limit: usize,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
struct CreateTaskRequest {
    content: TaskContent,
    idempotency_key: String,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
struct UpdateTaskRequest {
    content: TaskContent,
    expected_version: u64,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
struct SetTaskStatusRequest {
    expected_version: u64,
    status: TaskStatus,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
struct DeleteTaskRequest {
    expected_version: u64,
}

async fn list_tasks(
    State(state): State<Arc<AppState>>,
    Extension(security): Extension<crate::identity_api::RequestSecurityContext>,
    Query(query): Query<TaskListQuery>,
) -> Result<Json<agent_runtime::tasks::TaskPage>, ApiError> {
    let runtime = task_runtime(&state, &security)?;
    runtime
        .execute(
            "task_list",
            serde_json::json!({
                "status": query.status,
                "dueAfter": query.due_after,
                "dueBefore": query.due_before,
                "tag": query.tag,
                "text": query.text,
                "cursor": query.cursor,
                "limit": query.limit,
            }),
        )
        .await
        .map_err(map_runtime_error)
        .and_then(decode)
        .map(Json)
}

async fn get_task(
    State(state): State<Arc<AppState>>,
    Extension(security): Extension<crate::identity_api::RequestSecurityContext>,
    Path(task_id): Path<String>,
) -> Result<Json<agent_runtime::tasks::TaskRecord>, ApiError> {
    let value = task_runtime(&state, &security)?
        .execute("task_get", serde_json::json!({"id": task_id}))
        .await
        .map_err(map_runtime_error)?;
    let task: Option<agent_runtime::tasks::TaskRecord> = decode(value)?;
    task.map(Json).ok_or(ApiError::NotFound("task not found"))
}

async fn create_task(
    State(state): State<Arc<AppState>>,
    Extension(security): Extension<crate::identity_api::RequestSecurityContext>,
    Json(request): Json<CreateTaskRequest>,
) -> Result<Json<agent_runtime::tasks::TaskRecord>, ApiError> {
    execute_record(
        &state,
        &security,
        "task_create",
        serde_json::json!({
            "content": request.content,
            "idempotencyKey": request.idempotency_key,
        }),
    )
    .await
    .map(Json)
}

async fn update_task(
    State(state): State<Arc<AppState>>,
    Extension(security): Extension<crate::identity_api::RequestSecurityContext>,
    Path(task_id): Path<String>,
    Json(request): Json<UpdateTaskRequest>,
) -> Result<Json<agent_runtime::tasks::TaskRecord>, ApiError> {
    execute_record(
        &state,
        &security,
        "task_update",
        serde_json::json!({
            "id": task_id,
            "expectedVersion": request.expected_version,
            "content": request.content,
        }),
    )
    .await
    .map(Json)
}

async fn set_task_status(
    State(state): State<Arc<AppState>>,
    Extension(security): Extension<crate::identity_api::RequestSecurityContext>,
    Path(task_id): Path<String>,
    Json(request): Json<SetTaskStatusRequest>,
) -> Result<Json<agent_runtime::tasks::TaskRecord>, ApiError> {
    execute_record(
        &state,
        &security,
        "task_set_status",
        serde_json::json!({
            "id": task_id,
            "expectedVersion": request.expected_version,
            "status": request.status,
        }),
    )
    .await
    .map(Json)
}

async fn delete_task(
    State(state): State<Arc<AppState>>,
    Extension(security): Extension<crate::identity_api::RequestSecurityContext>,
    Path(task_id): Path<String>,
    Json(request): Json<DeleteTaskRequest>,
) -> Result<Json<serde_json::Value>, ApiError> {
    task_runtime(&state, &security)?
        .execute(
            "task_delete",
            serde_json::json!({
                "id": task_id,
                "expectedVersion": request.expected_version,
            }),
        )
        .await
        .map(Json)
        .map_err(map_runtime_error)
}

async fn execute_record(
    state: &AppState,
    security: &crate::identity_api::RequestSecurityContext,
    name: &str,
    arguments: serde_json::Value,
) -> Result<agent_runtime::tasks::TaskRecord, ApiError> {
    let value = task_runtime(state, security)?
        .execute(name, arguments)
        .await
        .map_err(map_runtime_error)?;
    decode(value)
}

fn task_runtime(
    state: &AppState,
    security: &crate::identity_api::RequestSecurityContext,
) -> Result<agent_runtime::task_tools::TaskToolRuntime, ApiError> {
    state
        .task_tools_for(security)
        .map_err(ApiError::Internal)?
        .ok_or(ApiError::NotFound("Tasks Foundation is disabled"))
}

fn decode<T: serde::de::DeserializeOwned>(value: serde_json::Value) -> Result<T, ApiError> {
    serde_json::from_value(value).map_err(|error| ApiError::Internal(error.into()))
}

fn map_runtime_error(error: anyhow::Error) -> ApiError {
    match error.downcast_ref::<TaskError>() {
        Some(TaskError::InvalidRequest(_)) => ApiError::BadRequest("task request is invalid"),
        Some(TaskError::NotFound) => ApiError::NotFound("task not found"),
        Some(TaskError::VersionConflict) => ApiError::Conflict("task version conflict"),
        Some(TaskError::IdempotencyConflict) => ApiError::Conflict("task idempotency conflict"),
        Some(TaskError::Unavailable) | None => ApiError::Internal(error),
    }
}

fn default_limit() -> usize {
    50
}
