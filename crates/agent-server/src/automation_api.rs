use crate::api::{ApiError, AppState};
use agent_runtime::automation::{
    NotificationDeliveryOutcome, NotificationRecord, NotificationScope, NotificationStatus,
    NotificationStore, QuietHours,
};
use agent_runtime::scheduler::{MisfirePolicy, ScheduleSpec, ScheduledJob, ScheduledJobStatus};
use agent_runtime::storage::Storage;
use axum::{
    Json, Router,
    extract::{Extension, Path, Query, State},
    routing::{get, post},
};
use chrono::{Duration, Utc};
use serde::Deserialize;
use serde_json::{Value, json};
use std::sync::Arc;

#[derive(Clone)]
pub(crate) struct AutomationApiState {
    notifications: NotificationStore,
}

impl AutomationApiState {
    pub(crate) async fn from_storage(storage: &Storage) -> anyhow::Result<Self> {
        Ok(Self {
            notifications: NotificationStore::from_storage(storage).await?,
        })
    }
}

pub(crate) fn router() -> Router<Arc<AppState>> {
    Router::new()
        .route(
            "/foundation/schedules",
            get(list_schedules).post(create_schedule),
        )
        .route(
            "/foundation/schedules/{job_id}",
            get(get_schedule).post(set_schedule_status),
        )
        .route(
            "/foundation/notifications",
            get(list_notifications).post(enqueue_notification),
        )
        .route("/foundation/notifications/claim", get(claim_notifications))
        .route(
            "/foundation/notifications/{notification_id}",
            get(get_notification).post(finish_notification),
        )
        .route(
            "/foundation/notifications/{notification_id}/cancel",
            post(cancel_notification),
        )
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
struct ScheduleListQuery {
    #[serde(default = "default_limit")]
    limit: usize,
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
struct SetScheduleStatusRequest {
    expected_version: i64,
    status: ScheduledJobStatus,
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
struct CreateScheduleRequest {
    name: String,
    schedule: ScheduleSpec,
    misfire: MisfirePolicy,
    #[serde(default)]
    payload: Value,
    idempotency_key: String,
}

#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
struct NotificationListQuery {
    status: Option<NotificationStatus>,
    #[serde(default = "default_limit")]
    limit: usize,
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
struct EnqueueNotificationRequest {
    channel: String,
    title: String,
    body: String,
    dedupe_key: String,
    not_before: chrono::DateTime<Utc>,
    quiet_hours: Option<QuietHours>,
    #[serde(default)]
    data: Value,
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
struct NotificationClaimQuery {
    channel: String,
    worker: String,
    #[serde(default = "default_limit")]
    limit: usize,
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
struct FinishNotificationRequest {
    worker: String,
    outcome: NotificationDeliveryOutcome,
}

async fn list_schedules(
    State(state): State<Arc<AppState>>,
    Extension(security): Extension<crate::identity_api::RequestSecurityContext>,
    Query(query): Query<ScheduleListQuery>,
) -> Result<Json<Vec<ScheduledJob>>, ApiError> {
    validate_limit(query.limit)?;
    automation_runtime(&state, &security)?
        .execute("schedule_list", json!({"limit":query.limit}))
        .await
        .map_err(map_automation_error)
        .and_then(decode)
        .map(Json)
}

async fn create_schedule(
    State(state): State<Arc<AppState>>,
    Extension(security): Extension<crate::identity_api::RequestSecurityContext>,
    Json(request): Json<CreateScheduleRequest>,
) -> Result<Json<ScheduledJob>, ApiError> {
    automation_runtime(&state, &security)?
        .execute(
            "schedule_create",
            json!({
                "name":request.name,
                "schedule":request.schedule,
                "misfire":request.misfire,
                "payload":request.payload,
                "idempotencyKey":request.idempotency_key,
            }),
        )
        .await
        .map_err(map_automation_error)
        .and_then(decode)
        .map(Json)
}

async fn get_schedule(
    State(state): State<Arc<AppState>>,
    Extension(security): Extension<crate::identity_api::RequestSecurityContext>,
    Path(job_id): Path<String>,
) -> Result<Json<ScheduledJob>, ApiError> {
    let value = automation_runtime(&state, &security)?
        .execute("schedule_get", json!({"id":job_id}))
        .await
        .map_err(map_automation_error)?;
    let job: Option<ScheduledJob> = decode(value)?;
    job.map(Json)
        .ok_or(ApiError::NotFound("scheduled job not found"))
}

async fn set_schedule_status(
    State(state): State<Arc<AppState>>,
    Extension(security): Extension<crate::identity_api::RequestSecurityContext>,
    Path(job_id): Path<String>,
    Json(request): Json<SetScheduleStatusRequest>,
) -> Result<Json<ScheduledJob>, ApiError> {
    let value = automation_runtime(&state, &security)?
        .execute(
            "schedule_set_status",
            json!({
                "id":job_id,
                "expectedVersion":request.expected_version,
                "status":request.status,
            }),
        )
        .await
        .map_err(map_automation_error)?;
    let job: Option<ScheduledJob> = decode(value)?;
    job.map(Json)
        .ok_or(ApiError::NotFound("scheduled job not found"))
}

async fn list_notifications(
    State(state): State<Arc<AppState>>,
    Extension(security): Extension<crate::identity_api::RequestSecurityContext>,
    Query(query): Query<NotificationListQuery>,
) -> Result<Json<Vec<NotificationRecord>>, ApiError> {
    let value = automation_runtime(&state, &security)?
        .execute(
            "notification_list",
            json!({"status":query.status,"limit":query.limit}),
        )
        .await
        .map_err(map_automation_error)?;
    decode(value).map(Json)
}

async fn get_notification(
    State(state): State<Arc<AppState>>,
    Extension(security): Extension<crate::identity_api::RequestSecurityContext>,
    Path(notification_id): Path<String>,
) -> Result<Json<NotificationRecord>, ApiError> {
    let value = automation_runtime(&state, &security)?
        .execute("notification_get", json!({"id":notification_id}))
        .await
        .map_err(map_automation_error)?;
    let record: Option<NotificationRecord> = decode(value)?;
    record
        .map(Json)
        .ok_or(ApiError::NotFound("notification not found"))
}

async fn enqueue_notification(
    State(state): State<Arc<AppState>>,
    Extension(security): Extension<crate::identity_api::RequestSecurityContext>,
    Json(request): Json<EnqueueNotificationRequest>,
) -> Result<Json<NotificationRecord>, ApiError> {
    let value = automation_runtime(&state, &security)?
        .execute(
            "notification_enqueue",
            json!({
                "channel":request.channel,
                "title":request.title,
                "body":request.body,
                "dedupeKey":request.dedupe_key,
                "notBefore":request.not_before,
                "quietHours":request.quiet_hours,
                "data":request.data,
            }),
        )
        .await
        .map_err(map_automation_error)?;
    decode(value).map(Json)
}

async fn cancel_notification(
    State(state): State<Arc<AppState>>,
    Extension(security): Extension<crate::identity_api::RequestSecurityContext>,
    Path(notification_id): Path<String>,
) -> Result<Json<NotificationRecord>, ApiError> {
    let value = automation_runtime(&state, &security)?
        .execute("notification_cancel", json!({"id":notification_id}))
        .await
        .map_err(map_automation_error)?;
    let record: Option<NotificationRecord> = decode(value)?;
    record
        .map(Json)
        .ok_or(ApiError::NotFound("notification not found"))
}

async fn claim_notifications(
    State(state): State<Arc<AppState>>,
    Extension(security): Extension<crate::identity_api::RequestSecurityContext>,
    Query(query): Query<NotificationClaimQuery>,
) -> Result<Json<Vec<NotificationRecord>>, ApiError> {
    validate_limit(query.limit)?;
    state
        .automation()
        .ok_or(ApiError::NotFound("Automation Foundation is disabled"))?
        .notifications
        .claim_due_for_scope_and_channel(
            &query.worker,
            NotificationScope {
                app_id: &security.conversation_scope().app_id,
                tenant_id: &security.conversation_scope().tenant_id,
                user_id: &security.conversation_scope().user_id,
            },
            &query.channel,
            Utc::now(),
            Duration::seconds(60),
            query.limit,
        )
        .await
        .map(Json)
        .map_err(ApiError::Internal)
}

async fn finish_notification(
    State(state): State<Arc<AppState>>,
    Extension(security): Extension<crate::identity_api::RequestSecurityContext>,
    Path(notification_id): Path<String>,
    Json(request): Json<FinishNotificationRequest>,
) -> Result<Json<bool>, ApiError> {
    state
        .automation()
        .ok_or(ApiError::NotFound("Automation Foundation is disabled"))?
        .notifications
        .finish_for_scope(
            &notification_id,
            &request.worker,
            NotificationScope {
                app_id: &security.conversation_scope().app_id,
                tenant_id: &security.conversation_scope().tenant_id,
                user_id: &security.conversation_scope().user_id,
            },
            request.outcome,
            Utc::now(),
        )
        .await
        .map(Json)
        .map_err(ApiError::Internal)
}

fn automation_runtime(
    state: &AppState,
    security: &crate::identity_api::RequestSecurityContext,
) -> Result<agent_runtime::automation_tools::AutomationToolRuntime, ApiError> {
    state
        .automation_tools_for(security)
        .map_err(ApiError::Internal)?
        .ok_or(ApiError::NotFound("Automation Foundation is disabled"))
}

fn decode<T: serde::de::DeserializeOwned>(value: Value) -> Result<T, ApiError> {
    serde_json::from_value(value).map_err(|error| ApiError::Internal(error.into()))
}

fn map_automation_error(error: anyhow::Error) -> ApiError {
    let message = error.to_string();
    if message.contains("version conflict") || message.contains("idempotency conflict") {
        ApiError::Conflict("automation state conflict")
    } else if message.contains("invalid")
        || message.contains("required")
        || message.contains("too long")
        || message.contains("cannot be cancelled")
        || message.contains("exceeds limit")
    {
        ApiError::BadRequest("automation request is invalid")
    } else {
        ApiError::Internal(error)
    }
}

fn validate_limit(limit: usize) -> Result<(), ApiError> {
    if (1..=100).contains(&limit) {
        Ok(())
    } else {
        Err(ApiError::BadRequest("limit must be between 1 and 100"))
    }
}

fn default_limit() -> usize {
    25
}
