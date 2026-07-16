use crate::api::{ApiError, AppState};
use agent_runtime::oauth::{OAuthAuthorizationRequest, OAuthAuthorizationView};
use agent_runtime::structured_content::{
    StructuredActionConstraints, StructuredActionExecution, StructuredActionIntent,
    StructuredActionReceipt, StructuredContent, StructuredContentAudience,
};
use agent_runtime::structured_content_error::{StructuredContentError, StructuredContentErrorKind};
use agent_runtime::structured_content_store::StructuredActionClaim;
use axum::{
    Json, Router,
    extract::{Path, State},
    http::header,
    response::{IntoResponse, Response},
    routing::{get, post},
};
use chrono::Utc;
use serde::{Deserialize, Serialize};
use serde_json::{Value, json};
use std::collections::BTreeSet;
use std::sync::Arc;

pub(crate) fn router() -> Router<Arc<AppState>> {
    Router::new()
        .route(
            "/sessions/{session_id}/structured-content",
            get(list_structured_content),
        )
        .route(
            "/sessions/{session_id}/structured-actions/{binding_id}/accept",
            post(accept_structured_action),
        )
}

#[derive(Debug, Deserialize)]
#[serde(deny_unknown_fields)]
struct AcceptStructuredActionRequest {
    #[serde(default)]
    input: Value,
}

#[derive(Clone, Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub(crate) struct AcceptStructuredActionResponse {
    pub receipt: StructuredActionReceipt,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub host_directive: Option<StructuredActionHostDirective>,
}

#[derive(Clone, Debug, Serialize)]
#[serde(tag = "type", rename_all = "snake_case")]
pub(crate) enum StructuredActionHostDirective {
    OpenExternal {
        authorization_id: String,
        url: String,
        expected_origin: String,
    },
}

async fn list_structured_content(
    Path(session_id): Path<String>,
    State(state): State<Arc<AppState>>,
) -> Result<Json<Vec<StructuredContent>>, ApiError> {
    state
        .structured_content()
        .replay(&session_id, StructuredContentAudience::User)
        .await
        .map(Json)
        .map_err(map_structured_error)
}

async fn accept_structured_action(
    Path((session_id, binding_id)): Path<(String, String)>,
    State(state): State<Arc<AppState>>,
    Json(request): Json<AcceptStructuredActionRequest>,
) -> Result<Response, ApiError> {
    let service = state.structured_content();
    match service
        .claim_action(&session_id, &binding_id, request.input, Utc::now())
        .await
        .map_err(map_structured_error)?
    {
        StructuredActionClaim::Replay(receipt) => {
            Ok(no_store_json(AcceptStructuredActionResponse {
                receipt,
                host_directive: None,
            }))
        }
        StructuredActionClaim::Execute(execution) => {
            match execute_action(&state, &execution).await {
                Ok((result, directive)) => {
                    let receipt = service
                        .complete_action(&execution, result, Utc::now())
                        .await
                        .map_err(map_structured_error)?;
                    Ok(no_store_json(AcceptStructuredActionResponse {
                        receipt,
                        host_directive: directive,
                    }))
                }
                Err(error) => {
                    if let Err(release_error) = service.release_action(&execution, Utc::now()).await
                    {
                        tracing::warn!(?release_error, "failed to release structured action lease");
                    }
                    Err(error)
                }
            }
        }
    }
}

async fn execute_action(
    state: &AppState,
    execution: &StructuredActionExecution,
) -> Result<(Value, Option<StructuredActionHostDirective>), ApiError> {
    match execution.intent {
        StructuredActionIntent::OauthStart => execute_oauth_start(state, execution).await,
        StructuredActionIntent::OauthStatus => execute_oauth_status(state, execution).await,
        StructuredActionIntent::OauthCancel => execute_oauth_cancel(state, execution).await,
        StructuredActionIntent::ScheduleCreate => {
            execute_automation(state, "schedule_create", execution.parameters.clone()).await
        }
        StructuredActionIntent::ScheduleStatus => {
            execute_automation(state, "schedule_set_status", execution.parameters.clone()).await
        }
    }
}

async fn execute_oauth_start(
    state: &AppState,
    execution: &StructuredActionExecution,
) -> Result<(Value, Option<StructuredActionHostDirective>), ApiError> {
    let request: OAuthAuthorizationRequest =
        serde_json::from_value(execution.parameters.clone())
            .map_err(|_| ApiError::BadRequest("OAuth structured action parameters are invalid"))?;
    validate_oauth_constraints(&execution.constraints, &request)?;
    let start = state
        .oauth_broker()
        .ok_or(ApiError::NotFound("OAuth authorization is disabled"))?
        .start(request, Utc::now())
        .await
        .map_err(ApiError::Internal)?;
    let result = json!({
        "authorizationId": start.authorization_id,
        "providerId": start.provider_id,
        "connectorIds": start.connector_ids,
        "requestedCapabilities": start.requested_capabilities,
        "status": start.status,
        "expiresAt": start.expires_at,
    });
    let directive = StructuredActionHostDirective::OpenExternal {
        authorization_id: start.authorization_id,
        url: start.authorization_url,
        expected_origin: start.authorization_origin,
    };
    Ok((result, Some(directive)))
}

async fn execute_oauth_status(
    state: &AppState,
    execution: &StructuredActionExecution,
) -> Result<(Value, Option<StructuredActionHostDirective>), ApiError> {
    let parameters: OAuthAuthorizationId = serde_json::from_value(execution.parameters.clone())
        .map_err(|_| ApiError::BadRequest("OAuth structured action parameters are invalid"))?;
    ensure_owned_oauth_authorization(state, execution, &parameters.authorization_id).await?;
    let view = state
        .oauth_broker()
        .ok_or(ApiError::NotFound("OAuth authorization is disabled"))?
        .status(&parameters.authorization_id)
        .await
        .map_err(ApiError::Internal)?
        .ok_or(ApiError::NotFound("OAuth authorization was not found"))?;
    validate_oauth_view_constraints(&execution.constraints, &view)?;
    serde_json::to_value(view)
        .map(|result| (result, None))
        .map_err(|error| ApiError::Internal(error.into()))
}

async fn execute_oauth_cancel(
    state: &AppState,
    execution: &StructuredActionExecution,
) -> Result<(Value, Option<StructuredActionHostDirective>), ApiError> {
    let parameters: OAuthAuthorizationId = serde_json::from_value(execution.parameters.clone())
        .map_err(|_| ApiError::BadRequest("OAuth structured action parameters are invalid"))?;
    ensure_owned_oauth_authorization(state, execution, &parameters.authorization_id).await?;
    let broker = state
        .oauth_broker()
        .ok_or(ApiError::NotFound("OAuth authorization is disabled"))?;
    let current = broker
        .status(&parameters.authorization_id)
        .await
        .map_err(ApiError::Internal)?
        .ok_or(ApiError::NotFound("OAuth authorization was not found"))?;
    validate_oauth_view_constraints(&execution.constraints, &current)?;
    let view = broker
        .cancel(&parameters.authorization_id, Utc::now())
        .await
        .map_err(ApiError::Internal)?
        .ok_or(ApiError::NotFound("OAuth authorization was not found"))?;
    validate_oauth_view_constraints(&execution.constraints, &view)?;
    serde_json::to_value(view)
        .map(|result| (result, None))
        .map_err(|error| ApiError::Internal(error.into()))
}

async fn execute_automation(
    state: &AppState,
    tool_name: &str,
    parameters: Value,
) -> Result<(Value, Option<StructuredActionHostDirective>), ApiError> {
    let result = state
        .automation_tools()
        .ok_or(ApiError::NotFound("Automation Foundation is disabled"))?
        .execute(tool_name, parameters)
        .await
        .map_err(ApiError::Internal)?;
    sanitize_schedule_result(result).map(|result| (result, None))
}

fn sanitize_schedule_result(result: Value) -> Result<Value, ApiError> {
    let job: agent_runtime::scheduler::ScheduledJob =
        serde_json::from_value(result).map_err(|error| ApiError::Internal(error.into()))?;
    Ok(json!({
        "id": job.id,
        "name": job.request.name,
        "schedule": job.request.schedule,
        "misfire": job.request.misfire,
        "status": job.status,
        "nextRunAt": job.next_run_at,
        "version": job.version,
    }))
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
struct OAuthAuthorizationId {
    authorization_id: String,
}

fn validate_oauth_constraints(
    constraints: &StructuredActionConstraints,
    request: &OAuthAuthorizationRequest,
) -> Result<(), ApiError> {
    let providers = constraints
        .provider_ids
        .iter()
        .cloned()
        .collect::<BTreeSet<_>>();
    let connectors = constraints
        .connector_ids
        .iter()
        .cloned()
        .collect::<BTreeSet<_>>();
    let capabilities = constraints
        .capabilities
        .iter()
        .cloned()
        .collect::<BTreeSet<_>>();
    if providers != BTreeSet::from([request.provider_id.clone()])
        || connectors != request.connector_ids
        || capabilities != request.requested_capabilities
    {
        return Err(ApiError::BadRequest(
            "OAuth structured action exceeds its signed constraints",
        ));
    }
    Ok(())
}

fn validate_oauth_view_constraints(
    constraints: &StructuredActionConstraints,
    view: &OAuthAuthorizationView,
) -> Result<(), ApiError> {
    let providers = constraints
        .provider_ids
        .iter()
        .cloned()
        .collect::<BTreeSet<_>>();
    let connectors = constraints
        .connector_ids
        .iter()
        .cloned()
        .collect::<BTreeSet<_>>();
    let capabilities = constraints
        .capabilities
        .iter()
        .cloned()
        .collect::<BTreeSet<_>>();
    if providers != BTreeSet::from([view.provider_id.clone()])
        || connectors != view.connector_ids
        || capabilities != view.requested_capabilities
    {
        return Err(ApiError::BadRequest(
            "OAuth structured action exceeds its signed constraints",
        ));
    }
    Ok(())
}

async fn ensure_owned_oauth_authorization(
    state: &AppState,
    execution: &StructuredActionExecution,
    authorization_id: &str,
) -> Result<(), ApiError> {
    let owned = state
        .structured_content()
        .owns_oauth_authorization(
            &execution.session_id,
            &execution.content_id,
            authorization_id,
        )
        .await
        .map_err(ApiError::Internal)?;
    if !owned {
        return Err(ApiError::NotFound(
            "OAuth authorization was not found in this conversation",
        ));
    }
    Ok(())
}

fn no_store_json<T: Serialize>(value: T) -> Response {
    (
        [
            (header::CACHE_CONTROL, "no-store"),
            (header::PRAGMA, "no-cache"),
        ],
        Json(value),
    )
        .into_response()
}

fn map_structured_error(error: anyhow::Error) -> ApiError {
    let Some(classified) = error.downcast_ref::<StructuredContentError>() else {
        return ApiError::Internal(error);
    };
    match classified.kind() {
        StructuredContentErrorKind::Invalid => {
            ApiError::BadRequest("structured content request is invalid")
        }
        StructuredContentErrorKind::NotFound => {
            ApiError::NotFound("structured content resource was not found")
        }
        StructuredContentErrorKind::Conflict => {
            ApiError::Conflict("structured content changed; reload and try again")
        }
        StructuredContentErrorKind::Expired => ApiError::Conflict("structured action expired"),
    }
}

#[cfg(test)]
#[path = "structured_content_api_tests.rs"]
mod tests;
