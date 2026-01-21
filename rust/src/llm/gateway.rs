use anyhow::{anyhow, Result};
use reqwest::blocking::Client;
use reqwest::header;
use serde::Serialize;

use super::ChatDelta;

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
}

impl CloudGatewayProvider {
    pub fn new(
        gateway_base_url: String,
        id_token: String,
        model_name: String,
        temperature: Option<f32>,
    ) -> Self {
        Self {
            client: Client::new(),
            gateway_base_url,
            id_token,
            model_name,
            temperature,
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

        let mut resp = self
            .client
            .post(url)
            .bearer_auth(&self.id_token)
            .header(header::ACCEPT, "text/event-stream")
            .json(&req)
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
