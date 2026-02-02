use anyhow::{anyhow, Result};
use base64::{engine::general_purpose::STANDARD, Engine as _};
use reqwest::blocking::Client;
use serde::{Deserialize, Serialize};
use serde_json::Value;

pub fn cloud_gateway_chat_completions_url(gateway_base_url: &str) -> String {
    format!(
        "{}/v1/chat/completions",
        gateway_base_url.trim_end_matches('/')
    )
}

#[derive(Debug, Serialize)]
struct OpenAiChatCompletionsRequest {
    model: String,
    messages: Vec<OpenAiChatMessage>,
    stream: bool,
}

#[derive(Debug, Serialize)]
struct OpenAiChatMessage {
    role: String,
    content: Vec<OpenAiChatContentPart>,
}

#[derive(Debug, Serialize)]
#[serde(tag = "type")]
enum OpenAiChatContentPart {
    #[serde(rename = "text")]
    Text { text: String },
    #[serde(rename = "image_url")]
    ImageUrl { image_url: OpenAiImageUrl },
}

#[derive(Debug, Serialize)]
struct OpenAiImageUrl {
    url: String,
}

#[derive(Debug, Deserialize)]
struct OpenAiChatCompletionsResponse {
    choices: Vec<OpenAiChatChoice>,
}

#[derive(Debug, Deserialize)]
struct OpenAiChatChoice {
    message: OpenAiChatChoiceMessage,
}

#[derive(Debug, Deserialize)]
struct OpenAiChatChoiceMessage {
    content: Option<String>,
}

fn annotation_prompt(lang: &str) -> String {
    format!(
        "Describe the image and respond ONLY as JSON with keys: caption_long (string), tags (array of strings), ocr_text (string|null). Language: {lang}."
    )
}

pub struct CloudGatewayMediaAnnotationClient {
    client: Client,
    gateway_base_url: String,
    id_token: String,
    model_name: String,
}

impl CloudGatewayMediaAnnotationClient {
    pub fn new(gateway_base_url: String, id_token: String, model_name: String) -> Self {
        Self {
            client: Client::new(),
            gateway_base_url,
            id_token,
            model_name,
        }
    }

    pub fn annotate_image(&self, lang: &str, mime_type: &str, image_bytes: &[u8]) -> Result<Value> {
        if image_bytes.is_empty() {
            return Err(anyhow!("image_bytes is empty"));
        }
        let mime_type = mime_type.trim();
        if mime_type.is_empty() {
            return Err(anyhow!("mime_type is required"));
        }

        let image_b64 = STANDARD.encode(image_bytes);
        let data_url = format!("data:{mime_type};base64,{image_b64}");

        let req = OpenAiChatCompletionsRequest {
            model: self.model_name.clone(),
            messages: vec![OpenAiChatMessage {
                role: "user".to_string(),
                content: vec![
                    OpenAiChatContentPart::Text {
                        text: annotation_prompt(lang),
                    },
                    OpenAiChatContentPart::ImageUrl {
                        image_url: OpenAiImageUrl { url: data_url },
                    },
                ],
            }],
            stream: false,
        };

        let url = cloud_gateway_chat_completions_url(&self.gateway_base_url);
        let resp = self
            .client
            .post(url)
            .bearer_auth(&self.id_token)
            .header("x-secondloop-purpose", "media_annotation")
            .json(&req)
            .send()?;

        if !resp.status().is_success() {
            let status = resp.status();
            let body = resp.text().unwrap_or_default();
            return Err(anyhow!(
                "cloud-gateway media annotation request failed: HTTP {status} {body}"
            ));
        }

        let body = resp.text().unwrap_or_default();
        let parsed: OpenAiChatCompletionsResponse = serde_json::from_str(&body)
            .map_err(|e| anyhow!("invalid chat completions json: {e}"))?;

        let choice = parsed
            .choices
            .into_iter()
            .next()
            .ok_or_else(|| anyhow!("openai-compatible response has no choices"))?;

        let content = choice.message.content.unwrap_or_default();
        let payload: Value = serde_json::from_str(&content)
            .map_err(|e| anyhow!("annotation content is not valid json: {e}"))?;
        Ok(payload)
    }
}
