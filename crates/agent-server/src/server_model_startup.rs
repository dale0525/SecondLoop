use model_gateway::provider::{EndpointType, ProviderProfile};
use std::collections::BTreeMap;

const DEFAULT_MODEL_BASE_URL: &str = "http://127.0.0.1:11434/v1";
const DEFAULT_MODEL_NAME: &str = "local-agent-model";

pub(super) fn model_profile_from_env() -> ProviderProfile {
    ProviderProfile {
        id: "default".into(),
        name: "Default".into(),
        endpoint_type: model_endpoint_type_from_env(),
        base_url: std::env::var("AGENTWEAVE_MODEL_BASE_URL")
            .unwrap_or_else(|_| DEFAULT_MODEL_BASE_URL.into()),
        model: std::env::var("AGENTWEAVE_MODEL_NAME").unwrap_or_else(|_| DEFAULT_MODEL_NAME.into()),
        api_key: std::env::var("AGENTWEAVE_MODEL_API_KEY").ok(),
        headers: BTreeMap::new(),
    }
}

fn model_endpoint_type_from_env() -> EndpointType {
    match std::env::var("AGENTWEAVE_MODEL_ENDPOINT_TYPE")
        .unwrap_or_else(|_| "chat_completions".into())
        .as_str()
    {
        "responses" => EndpointType::Responses,
        "completion" => EndpointType::Completion,
        _ => EndpointType::ChatCompletions,
    }
}
