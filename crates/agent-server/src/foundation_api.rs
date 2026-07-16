use crate::api::{ApiError, AppState};
use agent_runtime::credential::{CredentialScope, SecretMaterial};
use agent_runtime::mail::{MailAccount, MailAddress, ProviderReference};
use agent_runtime::mail_imap_smtp::{ImapSmtpMailConfig, MailTlsMode};
use agent_runtime::mail_imap_smtp_accounts::IMAP_SMTP_PROVIDER_ID;
use axum::{
    Json, Router,
    extract::{Path, Query, State},
    routing::{get, post},
};
use serde::{Deserialize, Deserializer, Serialize};
use std::{fmt, sync::Arc};
use zeroize::Zeroize;

pub(crate) fn router() -> Router<Arc<AppState>> {
    Router::new()
        .route("/foundation/memory", get(list_memories))
        .route("/foundation/memory/export", get(export_memories))
        .route(
            "/foundation/memory/{memory_id}",
            get(get_memory).delete(forget_memory),
        )
        .route("/foundation/mail/accounts", get(list_mail_accounts))
        .route(
            "/foundation/mail/account-configurations",
            get(list_mail_account_configurations),
        )
        .route(
            "/foundation/mail/account-configurations/{account_id}",
            get(get_mail_account_configuration)
                .put(put_mail_account_configuration)
                .delete(delete_mail_account_configuration),
        )
        .route(
            "/foundation/mail/accounts/{account_id}",
            get(get_mail_account_status)
                .post(connect_mail_account)
                .delete(disconnect_mail_account),
        )
        .route(
            "/foundation/mail/send-approvals",
            post(request_mail_send_approval),
        )
        .route("/foundation/calendar/events", get(list_calendar_events))
        .route(
            "/foundation/calendar/events/{event_id}",
            get(get_calendar_event),
        )
        .route(
            "/foundation/calendar/free-busy",
            get(get_calendar_free_busy),
        )
        .route(
            "/foundation/calendar/create-approvals",
            post(request_calendar_create_approval),
        )
        .route(
            "/foundation/calendar/update-approvals",
            post(request_calendar_update_approval),
        )
        .route(
            "/foundation/calendar/cancel-approvals",
            post(request_calendar_cancel_approval),
        )
        .route("/foundation/contacts", get(resolve_contacts))
        .route("/foundation/contacts/{contact_id}", get(get_contact))
        .route(
            "/foundation/contacts/update-approvals",
            post(request_contact_update_approval),
        )
        .route("/foundation/actions", get(list_foundation_actions))
        .route(
            "/foundation/actions/{approval_id}",
            post(resolve_foundation_action),
        )
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
struct MemoryListQuery {
    #[serde(default)]
    query: String,
    #[serde(default = "default_memory_limit")]
    limit: usize,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
struct ForgetMemoryRequest {
    expected_version: u64,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
struct MailSendApprovalRequest {
    account_id: String,
    draft_id: String,
    expected_revision: u64,
    idempotency_key: String,
    session_id: Option<String>,
}

struct RedactedPassword(Vec<u8>);

impl<'de> Deserialize<'de> for RedactedPassword {
    fn deserialize<D>(deserializer: D) -> Result<Self, D::Error>
    where
        D: Deserializer<'de>,
    {
        String::deserialize(deserializer)
            .map(String::into_bytes)
            .map(Self)
    }
}

impl fmt::Debug for RedactedPassword {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter.write_str("RedactedPassword([REDACTED])")
    }
}

impl Drop for RedactedPassword {
    fn drop(&mut self) {
        self.0.zeroize();
    }
}

impl RedactedPassword {
    fn validate(&self) -> Result<(), ApiError> {
        if self.0.is_empty()
            || self.0.len() > 64 * 1024
            || std::str::from_utf8(&self.0)
                .map(str::trim)
                .map_or(true, str::is_empty)
        {
            return Err(ApiError::BadRequest(
                "Mail account configuration is invalid",
            ));
        }
        Ok(())
    }

    fn into_secret(mut self) -> anyhow::Result<SecretMaterial> {
        SecretMaterial::new(std::mem::take(&mut self.0))
    }
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
struct MailAccountConfigurationRequest {
    display_name: String,
    primary_name: Option<String>,
    primary_address: String,
    username: String,
    password: RedactedPassword,
    imap_host: String,
    imap_port: u16,
    imap_tls: MailTlsMode,
    smtp_host: String,
    smtp_port: u16,
    smtp_tls: MailTlsMode,
    archive_mailbox: Option<String>,
    sent_mailbox: Option<String>,
    drafts_mailbox: Option<String>,
    trash_mailbox: Option<String>,
    #[serde(default)]
    allow_insecure_localhost: bool,
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
struct MailAccountConfigurationResponse {
    id: String,
    display_name: String,
    primary_name: Option<String>,
    primary_address: String,
    username: String,
    imap_host: String,
    imap_port: u16,
    imap_tls: MailTlsMode,
    smtp_host: String,
    smtp_port: u16,
    smtp_tls: MailTlsMode,
    archive_mailbox: Option<String>,
    sent_mailbox: Option<String>,
    drafts_mailbox: Option<String>,
    trash_mailbox: Option<String>,
    allow_insecure_localhost: bool,
    credential_configured: bool,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
struct CalendarRangeQuery {
    account_id: String,
    start: chrono::DateTime<chrono::Utc>,
    end: chrono::DateTime<chrono::Utc>,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
struct CalendarEventQuery {
    account_id: String,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
struct CalendarCreateApprovalRequest {
    account_id: String,
    content: agent_runtime::calendar::CalendarEventContent,
    idempotency_key: String,
    session_id: Option<String>,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
struct CalendarUpdateApprovalRequest {
    account_id: String,
    event_id: String,
    expected_version: u64,
    content: agent_runtime::calendar::CalendarEventContent,
    idempotency_key: String,
    session_id: Option<String>,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
struct CalendarCancelApprovalRequest {
    account_id: String,
    event_id: String,
    expected_version: u64,
    idempotency_key: String,
    session_id: Option<String>,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
struct ContactsResolveQuery {
    account_id: String,
    query: String,
    #[serde(default = "default_contacts_limit")]
    limit: usize,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
struct ContactQuery {
    account_id: String,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
struct ContactUpdateApprovalRequest {
    account_id: String,
    contact_id: String,
    expected_version: u64,
    replacement: agent_runtime::contacts::ContactRecord,
    idempotency_key: String,
    session_id: Option<String>,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
struct ResolveFoundationActionRequest {
    decision: agent_runtime::approval::ApprovalDecision,
}

async fn list_memories(
    State(state): State<Arc<AppState>>,
    Query(query): Query<MemoryListQuery>,
) -> Result<Json<serde_json::Value>, ApiError> {
    if query.limit == 0 || query.limit > 100 {
        return Err(ApiError::BadRequest(
            "memory limit must be between 1 and 100",
        ));
    }
    let runtime = state
        .memory_tools()
        .ok_or(ApiError::NotFound("Memory Foundation is disabled"))?;
    runtime
        .execute(
            "memory_search",
            serde_json::json!({"query": query.query, "limit": query.limit}),
        )
        .await
        .map(Json)
        .map_err(ApiError::Internal)
}

async fn get_memory(
    State(state): State<Arc<AppState>>,
    Path(memory_id): Path<String>,
) -> Result<Json<serde_json::Value>, ApiError> {
    let runtime = state
        .memory_tools()
        .ok_or(ApiError::NotFound("Memory Foundation is disabled"))?;
    let value = runtime
        .execute(
            "memory_get",
            serde_json::json!({"id": memory_id, "includeTombstone": false}),
        )
        .await
        .map_err(ApiError::Internal)?;
    if value.is_null() {
        return Err(ApiError::NotFound("memory not found"));
    }
    Ok(Json(value))
}

async fn forget_memory(
    State(state): State<Arc<AppState>>,
    Path(memory_id): Path<String>,
    Json(request): Json<ForgetMemoryRequest>,
) -> Result<Json<serde_json::Value>, ApiError> {
    let runtime = state
        .memory_tools()
        .ok_or(ApiError::NotFound("Memory Foundation is disabled"))?;
    runtime
        .execute(
            "memory_forget",
            serde_json::json!({
                "id": memory_id,
                "expectedVersion": request.expected_version,
                "reason": "user_request"
            }),
        )
        .await
        .map(Json)
        .map_err(ApiError::Internal)
}

async fn export_memories(
    State(state): State<Arc<AppState>>,
) -> Result<Json<serde_json::Value>, ApiError> {
    let runtime = state
        .memory_tools()
        .ok_or(ApiError::NotFound("Memory Foundation is disabled"))?;
    runtime
        .execute(
            "memory_export",
            serde_json::json!({
                "includeProposals": false,
                "includeTombstones": false
            }),
        )
        .await
        .map(Json)
        .map_err(ApiError::Internal)
}

async fn list_mail_accounts(
    State(state): State<Arc<AppState>>,
) -> Result<Json<serde_json::Value>, ApiError> {
    execute_mail_read(&state, "mail_accounts_list", serde_json::json!({})).await
}

async fn list_mail_account_configurations(
    State(state): State<Arc<AppState>>,
) -> Result<Json<Vec<MailAccountConfigurationResponse>>, ApiError> {
    let manager = state.mail_account_manager().ok_or(ApiError::NotFound(
        "Mail account configuration is unavailable",
    ))?;
    let scope = mail_credential_scope(&state);
    let configs = manager.list(&scope).await.map_err(ApiError::Internal)?;
    let mut response = Vec::with_capacity(configs.len());
    for config in configs {
        response.push(
            mail_configuration_response(manager.as_ref(), &scope, config)
                .await
                .map_err(ApiError::Internal)?,
        );
    }
    Ok(Json(response))
}

async fn get_mail_account_configuration(
    State(state): State<Arc<AppState>>,
    Path(account_id): Path<String>,
) -> Result<Json<MailAccountConfigurationResponse>, ApiError> {
    validate_mail_account_id(&account_id)?;
    let manager = state.mail_account_manager().ok_or(ApiError::NotFound(
        "Mail account configuration is unavailable",
    ))?;
    let scope = mail_credential_scope(&state);
    let config = manager
        .get(&scope, &account_id)
        .await
        .map_err(ApiError::Internal)?
        .ok_or(ApiError::NotFound(
            "Mail account configuration was not found",
        ))?;
    mail_configuration_response(manager.as_ref(), &scope, config)
        .await
        .map(Json)
        .map_err(ApiError::Internal)
}

async fn put_mail_account_configuration(
    State(state): State<Arc<AppState>>,
    Path(account_id): Path<String>,
    Json(request): Json<MailAccountConfigurationRequest>,
) -> Result<Json<MailAccountConfigurationResponse>, ApiError> {
    validate_mail_account_id(&account_id)?;
    let manager = state.mail_account_manager().ok_or(ApiError::NotFound(
        "Mail account configuration is unavailable",
    ))?;
    let scope = mail_credential_scope(&state);
    let (config, password) = mail_configuration(&account_id, scope.clone(), request)?;
    let config = manager
        .configure(config, password)
        .await
        .map_err(ApiError::Internal)?;
    mail_configuration_response(manager.as_ref(), &scope, config)
        .await
        .map(Json)
        .map_err(ApiError::Internal)
}

async fn delete_mail_account_configuration(
    State(state): State<Arc<AppState>>,
    Path(account_id): Path<String>,
) -> Result<Json<serde_json::Value>, ApiError> {
    validate_mail_account_id(&account_id)?;
    let manager = state.mail_account_manager().ok_or(ApiError::NotFound(
        "Mail account configuration is unavailable",
    ))?;
    manager
        .delete(&mail_credential_scope(&state), &account_id)
        .await
        .map(|deleted| Json(serde_json::json!({"deleted": deleted})))
        .map_err(ApiError::Internal)
}

async fn get_mail_account_status(
    State(state): State<Arc<AppState>>,
    Path(account_id): Path<String>,
) -> Result<Json<serde_json::Value>, ApiError> {
    execute_mail_read(
        &state,
        "mail_account_status",
        serde_json::json!({"accountId": account_id}),
    )
    .await
}

async fn connect_mail_account(
    State(state): State<Arc<AppState>>,
    Path(account_id): Path<String>,
) -> Result<Json<serde_json::Value>, ApiError> {
    execute_mail_host_action(
        &state,
        "mail_account_connect",
        serde_json::json!({"accountId": account_id}),
    )
    .await
}

async fn disconnect_mail_account(
    State(state): State<Arc<AppState>>,
    Path(account_id): Path<String>,
) -> Result<Json<serde_json::Value>, ApiError> {
    execute_mail_host_action(
        &state,
        "mail_account_disconnect",
        serde_json::json!({"accountId": account_id}),
    )
    .await
}

async fn request_mail_send_approval(
    State(state): State<Arc<AppState>>,
    Json(request): Json<MailSendApprovalRequest>,
) -> Result<Json<agent_runtime::foundation_actions::PendingFoundationAction>, ApiError> {
    let preview = execute_mail_read(
        &state,
        "mail_send_preview",
        serde_json::json!({
            "accountId": request.account_id,
            "draftId": request.draft_id,
            "expectedRevision": request.expected_revision,
            "idempotencyKey": request.idempotency_key,
        }),
    )
    .await?
    .0;
    let preview =
        serde_json::from_value(preview).map_err(|error| ApiError::Internal(error.into()))?;
    state
        .mail_actions()
        .ok_or(ApiError::NotFound("Foundation action service is disabled"))?
        .request_send(preview, request.session_id, chrono::Utc::now())
        .await
        .map(Json)
        .map_err(ApiError::Internal)
}

async fn list_calendar_events(
    State(state): State<Arc<AppState>>,
    Query(query): Query<CalendarRangeQuery>,
) -> Result<Json<serde_json::Value>, ApiError> {
    execute_connector_read(
        &state,
        "calendar_events_list",
        serde_json::json!({
            "accountId": query.account_id,
            "start": query.start,
            "end": query.end,
        }),
        "Calendar Foundation is disabled",
    )
    .await
}

async fn get_calendar_event(
    State(state): State<Arc<AppState>>,
    Path(event_id): Path<String>,
    Query(query): Query<CalendarEventQuery>,
) -> Result<Json<serde_json::Value>, ApiError> {
    execute_connector_read(
        &state,
        "calendar_event_get",
        serde_json::json!({
            "accountId": query.account_id,
            "eventId": event_id,
        }),
        "Calendar Foundation is disabled",
    )
    .await
}

async fn get_calendar_free_busy(
    State(state): State<Arc<AppState>>,
    Query(query): Query<CalendarRangeQuery>,
) -> Result<Json<serde_json::Value>, ApiError> {
    execute_connector_read(
        &state,
        "calendar_free_busy",
        serde_json::json!({
            "accountId": query.account_id,
            "start": query.start,
            "end": query.end,
        }),
        "Calendar Foundation is disabled",
    )
    .await
}

async fn request_calendar_create_approval(
    State(state): State<Arc<AppState>>,
    Json(request): Json<CalendarCreateApprovalRequest>,
) -> Result<Json<agent_runtime::calendar_actions::PendingCalendarAction>, ApiError> {
    request_calendar_approval(
        &state,
        "calendar_event_create_preview",
        serde_json::json!({
            "accountId": request.account_id,
            "content": request.content,
            "idempotencyKey": request.idempotency_key,
        }),
        request.session_id,
    )
    .await
}

async fn request_calendar_update_approval(
    State(state): State<Arc<AppState>>,
    Json(request): Json<CalendarUpdateApprovalRequest>,
) -> Result<Json<agent_runtime::calendar_actions::PendingCalendarAction>, ApiError> {
    request_calendar_approval(
        &state,
        "calendar_event_update_preview",
        serde_json::json!({
            "accountId": request.account_id,
            "eventId": request.event_id,
            "expectedVersion": request.expected_version,
            "content": request.content,
            "idempotencyKey": request.idempotency_key,
        }),
        request.session_id,
    )
    .await
}

async fn request_calendar_cancel_approval(
    State(state): State<Arc<AppState>>,
    Json(request): Json<CalendarCancelApprovalRequest>,
) -> Result<Json<agent_runtime::calendar_actions::PendingCalendarAction>, ApiError> {
    request_calendar_approval(
        &state,
        "calendar_event_cancel_preview",
        serde_json::json!({
            "accountId": request.account_id,
            "eventId": request.event_id,
            "expectedVersion": request.expected_version,
            "idempotencyKey": request.idempotency_key,
        }),
        request.session_id,
    )
    .await
}

async fn request_calendar_approval(
    state: &AppState,
    preview_tool: &str,
    arguments: serde_json::Value,
    session_id: Option<String>,
) -> Result<Json<agent_runtime::calendar_actions::PendingCalendarAction>, ApiError> {
    let preview = execute_connector_read(
        state,
        preview_tool,
        arguments,
        "Calendar Foundation is disabled",
    )
    .await?
    .0;
    let preview =
        serde_json::from_value(preview).map_err(|error| ApiError::Internal(error.into()))?;
    state
        .calendar_actions()
        .ok_or(ApiError::NotFound(
            "Calendar Foundation action service is disabled",
        ))?
        .request(preview, session_id, chrono::Utc::now())
        .await
        .map(Json)
        .map_err(ApiError::Internal)
}

async fn resolve_contacts(
    State(state): State<Arc<AppState>>,
    Query(query): Query<ContactsResolveQuery>,
) -> Result<Json<serde_json::Value>, ApiError> {
    if !(1..=50).contains(&query.limit) {
        return Err(ApiError::BadRequest(
            "contact limit must be between 1 and 50",
        ));
    }
    execute_connector_read(
        &state,
        "contacts_resolve",
        serde_json::json!({
            "accountId": query.account_id,
            "query": query.query,
            "limit": query.limit,
        }),
        "Contacts Foundation is disabled",
    )
    .await
}

async fn get_contact(
    State(state): State<Arc<AppState>>,
    Path(contact_id): Path<String>,
    Query(query): Query<ContactQuery>,
) -> Result<Json<serde_json::Value>, ApiError> {
    execute_connector_read(
        &state,
        "contact_get",
        serde_json::json!({
            "accountId": query.account_id,
            "contactId": contact_id,
        }),
        "Contacts Foundation is disabled",
    )
    .await
}

async fn request_contact_update_approval(
    State(state): State<Arc<AppState>>,
    Json(request): Json<ContactUpdateApprovalRequest>,
) -> Result<Json<agent_runtime::contacts_actions::PendingContactAction>, ApiError> {
    let preview = execute_connector_read(
        &state,
        "contact_update_preview",
        serde_json::json!({
            "accountId": request.account_id,
            "contactId": request.contact_id,
            "expectedVersion": request.expected_version,
            "replacement": request.replacement,
            "idempotencyKey": request.idempotency_key,
        }),
        "Contacts Foundation is disabled",
    )
    .await?
    .0;
    let preview =
        serde_json::from_value(preview).map_err(|error| ApiError::Internal(error.into()))?;
    state
        .contacts_actions()
        .ok_or(ApiError::NotFound(
            "Contacts Foundation action service is disabled",
        ))?
        .request(preview, request.session_id, chrono::Utc::now())
        .await
        .map(Json)
        .map_err(ApiError::Internal)
}

async fn list_foundation_actions(
    State(state): State<Arc<AppState>>,
) -> Result<Json<Vec<serde_json::Value>>, ApiError> {
    let mut actions = Vec::new();
    let mut enabled = false;
    if let Some(service) = state.mail_actions() {
        enabled = true;
        for action in service.list_actions().await.map_err(ApiError::Internal)? {
            actions.push(
                serde_json::to_value(action).map_err(|error| ApiError::Internal(error.into()))?,
            );
        }
    }
    if let Some(service) = state.calendar_actions() {
        enabled = true;
        for action in service.list_actions().await.map_err(ApiError::Internal)? {
            actions.push(
                serde_json::to_value(action).map_err(|error| ApiError::Internal(error.into()))?,
            );
        }
    }
    if let Some(service) = state.contacts_actions() {
        enabled = true;
        for action in service.list_actions().await.map_err(ApiError::Internal)? {
            actions.push(
                serde_json::to_value(action).map_err(|error| ApiError::Internal(error.into()))?,
            );
        }
    }
    if !enabled {
        return Err(ApiError::NotFound("Foundation action service is disabled"));
    }
    actions.sort_by(|left, right| {
        right["approval"]["created_at"]
            .as_str()
            .cmp(&left["approval"]["created_at"].as_str())
    });
    Ok(Json(actions))
}

async fn resolve_foundation_action(
    State(state): State<Arc<AppState>>,
    Path(approval_id): Path<String>,
    Json(request): Json<ResolveFoundationActionRequest>,
) -> Result<Json<agent_runtime::foundation_actions::FoundationActionResolution>, ApiError> {
    if let Some(service) = state.contacts_actions()
        && service
            .handles_approval(&approval_id)
            .await
            .map_err(ApiError::Internal)?
    {
        return service
            .resolve(
                &approval_id,
                request.decision,
                "local-user",
                chrono::Utc::now(),
            )
            .await
            .map(Json)
            .map_err(ApiError::Internal);
    }
    if let Some(service) = state.calendar_actions()
        && service
            .handles_approval(&approval_id)
            .await
            .map_err(ApiError::Internal)?
    {
        return service
            .resolve(
                &approval_id,
                request.decision,
                "local-user",
                chrono::Utc::now(),
            )
            .await
            .map(Json)
            .map_err(ApiError::Internal);
    }
    if let Some(service) = state.mail_actions()
        && service
            .handles_approval(&approval_id)
            .await
            .map_err(ApiError::Internal)?
    {
        return service
            .resolve(
                &approval_id,
                request.decision,
                "local-user",
                chrono::Utc::now(),
            )
            .await
            .map(Json)
            .map_err(ApiError::Internal);
    }
    Err(ApiError::NotFound("Foundation action was not found"))
}

async fn execute_mail_read(
    state: &AppState,
    tool: &str,
    arguments: serde_json::Value,
) -> Result<Json<serde_json::Value>, ApiError> {
    execute_connector_read(state, tool, arguments, "Mail Foundation is disabled").await
}

async fn execute_connector_read(
    state: &AppState,
    tool: &str,
    arguments: serde_json::Value,
    disabled_message: &'static str,
) -> Result<Json<serde_json::Value>, ApiError> {
    let runtime = state
        .connector_tools()
        .ok_or(ApiError::NotFound(disabled_message))?;
    let envelope = runtime
        .execute(tool, &uuid::Uuid::new_v4().to_string(), arguments)
        .await
        .map_err(ApiError::Internal)?;
    envelope
        .get("output")
        .cloned()
        .map(Json)
        .ok_or_else(|| ApiError::Internal(anyhow::anyhow!("connector output is missing")))
}

async fn execute_mail_host_action(
    state: &AppState,
    tool: &str,
    arguments: serde_json::Value,
) -> Result<Json<serde_json::Value>, ApiError> {
    let runtime = state
        .connector_tools()
        .ok_or(ApiError::NotFound("Mail Foundation is disabled"))?;
    let envelope = runtime
        .execute_trusted_host_action(tool, &uuid::Uuid::new_v4().to_string(), arguments)
        .await
        .map_err(ApiError::Internal)?;
    envelope
        .get("output")
        .cloned()
        .map(Json)
        .ok_or_else(|| ApiError::Internal(anyhow::anyhow!("connector output is missing")))
}

fn mail_credential_scope(state: &AppState) -> CredentialScope {
    CredentialScope {
        app_id: state.app_prompt().identity.app_id.clone(),
        tenant_id: "local".into(),
        user_id: "local-user".into(),
    }
}

fn mail_configuration(
    account_id: &str,
    scope: CredentialScope,
    request: MailAccountConfigurationRequest,
) -> Result<(ImapSmtpMailConfig, SecretMaterial), ApiError> {
    for value in [
        &request.display_name,
        &request.primary_address,
        &request.username,
        &request.imap_host,
        &request.smtp_host,
    ] {
        if value.trim().is_empty() || value.len() > 512 {
            return Err(ApiError::BadRequest(
                "Mail account configuration is invalid",
            ));
        }
    }
    for value in [
        request.primary_name.as_ref(),
        request.archive_mailbox.as_ref(),
        request.sent_mailbox.as_ref(),
        request.drafts_mailbox.as_ref(),
        request.trash_mailbox.as_ref(),
    ]
    .into_iter()
    .flatten()
    {
        if value.len() > 512 {
            return Err(ApiError::BadRequest(
                "Mail account configuration is invalid",
            ));
        }
    }
    request.password.validate()?;
    let password = request
        .password
        .into_secret()
        .map_err(|_| ApiError::BadRequest("Mail account configuration is invalid"))?;
    let credential_secret_id =
        agent_runtime::mail_imap_smtp_accounts::mail_secret_id(&scope, account_id)
            .map_err(|_| ApiError::BadRequest("Mail account configuration is invalid"))?;
    let config = ImapSmtpMailConfig {
        account: MailAccount {
            id: account_id.to_string(),
            display_name: request.display_name,
            primary_address: MailAddress {
                name: request.primary_name.filter(|value| !value.is_empty()),
                address: request.primary_address,
            },
            addresses: Vec::new(),
            provider_reference: Some(ProviderReference {
                provider: IMAP_SMTP_PROVIDER_ID.into(),
                id: account_id.to_string(),
            }),
        },
        credential_scope: scope,
        credential_secret_id,
        imap_host: request.imap_host,
        imap_port: request.imap_port,
        imap_tls: request.imap_tls,
        smtp_host: request.smtp_host,
        smtp_port: request.smtp_port,
        smtp_tls: request.smtp_tls,
        username: request.username,
        archive_mailbox: request.archive_mailbox.filter(|value| !value.is_empty()),
        sent_mailbox: request.sent_mailbox.filter(|value| !value.is_empty()),
        drafts_mailbox: request.drafts_mailbox.filter(|value| !value.is_empty()),
        trash_mailbox: request.trash_mailbox.filter(|value| !value.is_empty()),
        allow_insecure_localhost: request.allow_insecure_localhost,
        connect_timeout_seconds: 15,
        operation_timeout_seconds: 30,
    };
    config
        .validate()
        .map_err(|_| ApiError::BadRequest("Mail account configuration is invalid"))?;
    Ok((config, password))
}

async fn mail_configuration_response(
    manager: &agent_runtime::mail_imap_smtp_accounts::ImapSmtpMailAccountManager,
    scope: &CredentialScope,
    config: ImapSmtpMailConfig,
) -> anyhow::Result<MailAccountConfigurationResponse> {
    let credential_configured = manager
        .credential_configured(scope, &config.account.id)
        .await?;
    Ok(MailAccountConfigurationResponse {
        id: config.account.id,
        display_name: config.account.display_name,
        primary_name: config.account.primary_address.name,
        primary_address: config.account.primary_address.address,
        username: config.username,
        imap_host: config.imap_host,
        imap_port: config.imap_port,
        imap_tls: config.imap_tls,
        smtp_host: config.smtp_host,
        smtp_port: config.smtp_port,
        smtp_tls: config.smtp_tls,
        archive_mailbox: config.archive_mailbox,
        sent_mailbox: config.sent_mailbox,
        drafts_mailbox: config.drafts_mailbox,
        trash_mailbox: config.trash_mailbox,
        allow_insecure_localhost: config.allow_insecure_localhost,
        credential_configured,
    })
}

fn validate_mail_account_id(account_id: &str) -> Result<(), ApiError> {
    if account_id.is_empty()
        || account_id.len() > 255
        || !account_id
            .bytes()
            .all(|byte| byte.is_ascii_alphanumeric() || b"._:-".contains(&byte))
    {
        return Err(ApiError::BadRequest("Mail account identifier is invalid"));
    }
    Ok(())
}

fn default_memory_limit() -> usize {
    50
}

fn default_contacts_limit() -> usize {
    20
}

#[cfg(test)]
#[path = "foundation_api_mail_configuration_tests.rs"]
mod mail_configuration_tests;
