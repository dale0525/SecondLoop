use anyhow::{anyhow, Result};
use reqwest::blocking::Client;
use reqwest::header;
use serde::Serialize;
use uuid::Uuid;

use super::ChatDelta;

const REQUEST_ID_ROLE_PREFIX: &str = "secondloop_request_id:";

pub fn gateway_chat_completions_url(gateway_base_url: &str) -> String {
    format!(
        "{}/v1/chat/completions",
        gateway_base_url.trim_end_matches('/')
    )
}

#[derive(Debug, Serialize)]
struct GatewayChatCompletionsRequest {
    model: String,
    messages: Vec<GatewayChatMessage>,
    #[serde(skip_serializing_if = "Option::is_none")]
    temperature: Option<f32>,
    stream: bool,
}

#[derive(Debug, Serialize)]
struct GatewayChatMessage {
    role: String,
    content: String,
}

pub struct CloudGatewayProvider {
    client: Client,
    gateway_base_url: String,
    id_token: String,
    model_name: String,
    temperature: Option<f32>,
    purpose_header: String,
}

fn build_request_id() -> String {
    format!("req_{}", Uuid::new_v4().simple())
}

impl CloudGatewayProvider {
    pub fn new(
        gateway_base_url: String,
        id_token: String,
        model_name: String,
        temperature: Option<f32>,
    ) -> Self {
        Self::new_with_purpose(
            gateway_base_url,
            id_token,
            model_name,
            temperature,
            "ask_ai".to_string(),
        )
    }

    pub fn new_with_purpose(
        gateway_base_url: String,
        id_token: String,
        model_name: String,
        temperature: Option<f32>,
        purpose_header: String,
    ) -> Self {
        Self {
            client: Client::new(),
            gateway_base_url,
            id_token,
            model_name,
            temperature,
            purpose_header,
        }
    }
}

impl crate::rag::AnswerProvider for CloudGatewayProvider {
    fn stream_answer(
        &self,
        prompt: &str,
        on_event: &mut dyn FnMut(ChatDelta) -> Result<()>,
    ) -> Result<()> {
        let url = gateway_chat_completions_url(&self.gateway_base_url);
        let req = GatewayChatCompletionsRequest {
            model: self.model_name.clone(),
            messages: vec![GatewayChatMessage {
                role: "user".to_string(),
                content: prompt.to_string(),
            }],
            temperature: self.temperature,
            stream: true,
        };

        let request_timeout =
            crate::llm::timeouts::ask_ai_timeout_for_prompt_chars(prompt.chars().count());
        let request_id = build_request_id();

        on_event(ChatDelta {
            role: Some(format!("{REQUEST_ID_ROLE_PREFIX}{request_id}")),
            text_delta: String::new(),
            done: false,
        })?;

        let mut resp = self
            .client
            .post(url)
            .bearer_auth(&self.id_token)
            .header("x-secondloop-purpose", &self.purpose_header)
            .header("x-secondloop-request-id", &request_id)
            .header("x-secondloop-detach-policy", "continue_on_disconnect")
            .header(header::ACCEPT, "text/event-stream")
            .json(&req)
            .timeout(request_timeout)
            .send()?;

        if !resp.status().is_success() {
            let status = resp.status();
            let body = resp.text().unwrap_or_default();
            return Err(anyhow!(
                "cloud-gateway request failed: HTTP {status} {body}"
            ));
        }

        let content_type = resp
            .headers()
            .get(header::CONTENT_TYPE)
            .and_then(|v| v.to_str().ok())
            .unwrap_or_default()
            .to_ascii_lowercase();

        if content_type.contains("text/event-stream") {
            super::openai::read_chat_completions_sse(&mut resp, on_event)?;
        } else {
            super::openai::read_chat_completions_json(&mut resp, on_event)?;
        }

        Ok(())
    }
}
