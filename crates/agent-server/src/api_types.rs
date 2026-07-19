use agent_runtime::{events::RuntimeEvent, session::Message};
use axum::{
    Json,
    http::StatusCode,
    response::{IntoResponse, Response},
};
use model_gateway::provider::EndpointType;
use serde::{Deserialize, Serialize};

#[derive(Debug, Serialize)]
pub struct AppDiagnosticsResponse {
    pub app_id: String,
    pub version: String,
    pub display_name: String,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct UserMessageRequest {
    pub content: String,
    #[serde(default)]
    pub model_settings: Option<ModelConnectionTestRequest>,
}

#[derive(Debug, Serialize)]
pub struct UserMessageResponse {
    pub accepted: bool,
    pub user_message: Message,
    pub assistant_message: Message,
    pub events: Vec<RuntimeEvent>,
}

#[derive(Clone, Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ModelConnectionTestRequest {
    #[serde(default)]
    pub api_key: Option<String>,
    pub base_url: String,
    pub endpoint_type: EndpointType,
    pub model_name: String,
}

#[derive(Debug, Serialize)]
pub struct ModelConnectionTestResponse {
    pub ok: bool,
    pub message: String,
}

#[derive(Debug, Serialize)]
pub struct ErrorResponse {
    pub error: String,
}

#[derive(Debug)]
pub(crate) enum ApiError {
    BadRequest(&'static str),
    Conflict(&'static str),
    ConnectionFailed(anyhow::Error),
    NotFound(&'static str),
    PayloadTooLarge(&'static str),
    Internal(anyhow::Error),
}

impl IntoResponse for ApiError {
    fn into_response(self) -> Response {
        let (status, error) = match self {
            Self::BadRequest(message) => (StatusCode::BAD_REQUEST, message.to_string()),
            Self::Conflict(message) => (StatusCode::CONFLICT, message.to_string()),
            Self::ConnectionFailed(error) => (
                StatusCode::BAD_GATEWAY,
                format!("connection failed: {error}"),
            ),
            Self::NotFound(message) => (StatusCode::NOT_FOUND, message.to_string()),
            Self::PayloadTooLarge(message) => (StatusCode::PAYLOAD_TOO_LARGE, message.to_string()),
            Self::Internal(error) => {
                tracing::error!(?error, "agent-server request failed");
                (
                    StatusCode::INTERNAL_SERVER_ERROR,
                    "internal server error".to_string(),
                )
            }
        };

        (status, Json(ErrorResponse { error })).into_response()
    }
}
