use agent_runtime::{
    events::RuntimeEvent,
    turn::{ModelClient, ModelEventStream},
};
use async_trait::async_trait;
use model_gateway::{
    provider::ProviderProfile,
    responses::{GatewayHttpClient, GatewayRequest},
};
use std::{collections::BTreeMap, sync::Arc};

use super::{ApiError, ModelConnectionTestRequest};

#[derive(Clone)]
pub(super) struct SharedModelClient(pub(super) Arc<dyn ModelClient>);

#[async_trait]
impl ModelClient for SharedModelClient {
    async fn stream(&self, request: GatewayRequest) -> anyhow::Result<ModelEventStream> {
        self.0.stream(request).await
    }
}

pub(super) enum TurnModelClient {
    Shared(SharedModelClient),
    Override(GatewayHttpClient),
}

#[async_trait]
impl ModelClient for TurnModelClient {
    async fn stream(&self, request: GatewayRequest) -> anyhow::Result<ModelEventStream> {
        match self {
            Self::Shared(client) => client.stream(request).await,
            Self::Override(client) => client.stream(request).await,
        }
    }
}

pub(super) fn provider_profile_from_request(
    request: ModelConnectionTestRequest,
) -> Result<ProviderProfile, ApiError> {
    let base_url = request.base_url.trim();
    if base_url.is_empty() {
        return Err(ApiError::BadRequest("base URL is required"));
    }
    let model = request.model_name.trim();
    if model.is_empty() {
        return Err(ApiError::BadRequest("model name is required"));
    }
    Ok(ProviderProfile {
        id: "settings-test".into(),
        name: "Settings Test".into(),
        endpoint_type: request.endpoint_type,
        base_url: base_url.to_string(),
        model: model.to_string(),
        api_key: request.api_key.and_then(|api_key| {
            let trimmed = api_key.trim();
            (!trimmed.is_empty()).then(|| trimmed.to_string())
        }),
        headers: BTreeMap::new(),
    })
}

pub(super) fn test_connection_gateway_request() -> GatewayRequest {
    GatewayRequest {
        input: vec![serde_json::json!({
            "role": "user",
            "content": "Reply with ok to confirm this connection."
        })],
        tools: Vec::new(),
    }
}

pub(super) fn agent_turn_error(error: anyhow::Error) -> ApiError {
    let message = error.to_string();
    if message.contains("model_endpoint_does_not_support_tools") {
        ApiError::BadRequest("model endpoint does not support runtime tools")
    } else if message.contains("upstream model request failed") {
        ApiError::ConnectionFailed(error)
    } else {
        ApiError::Internal(error)
    }
}

pub(super) fn assistant_text_from_events(events: &[RuntimeEvent]) -> Option<String> {
    events.iter().find_map(|event| {
        if let RuntimeEvent::AssistantMessageFinished { text } = event {
            Some(text.clone())
        } else {
            None
        }
    })
}
