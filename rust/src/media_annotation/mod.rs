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

fn openai_compatible_chat_completions_url(base_url: &str) -> String {
    format!("{}/chat/completions", base_url.trim_end_matches('/'))
}

#[derive(Debug, Serialize)]
struct MediaAnnotationChatCompletionsRequest {
    model: String,
    messages: Vec<MediaAnnotationChatMessage>,
    stream: bool,
}

#[derive(Debug, Serialize)]
struct MediaAnnotationChatMessage {
    role: String,
    content: Vec<MediaAnnotationChatContentPart>,
}

#[derive(Debug, Serialize)]
#[serde(tag = "type")]
enum MediaAnnotationChatContentPart {
    #[serde(rename = "text")]
    Text { text: String },
    #[serde(rename = "image_url")]
    ImageUrl { image_url: MediaAnnotationImageUrl },
}

#[derive(Debug, Serialize)]
struct MediaAnnotationImageUrl {
    url: String,
}

#[derive(Debug, Deserialize)]
struct MediaAnnotationChatCompletionsResponse {
    choices: Vec<MediaAnnotationChatChoice>,
    #[serde(default)]
    usage: Option<OpenAiUsage>,
}

#[derive(Debug, Deserialize)]
struct MediaAnnotationChatChoice {
    message: MediaAnnotationChatChoiceMessage,
}

#[derive(Debug, Deserialize)]
struct MediaAnnotationChatChoiceMessage {
    content: Option<OpenAiChatMessageContent>,
}

#[derive(Debug, Deserialize)]
#[serde(untagged)]
enum OpenAiChatMessageContent {
    Text(String),
    Parts(Vec<OpenAiChatMessagePart>),
    Json(Value),
}

#[derive(Debug, Deserialize)]
struct OpenAiChatMessagePart {
    #[serde(rename = "type")]
    kind: Option<String>,
    #[serde(default)]
    text: Option<String>,
}

impl OpenAiChatMessageContent {
    fn into_text(self) -> String {
        match self {
            OpenAiChatMessageContent::Text(value) => value,
            OpenAiChatMessageContent::Parts(parts) => parts
                .into_iter()
                .filter_map(|part| match (part.kind.as_deref(), part.text) {
                    (Some("text"), Some(text)) => Some(text),
                    (_, Some(text)) => Some(text),
                    _ => None,
                })
                .collect::<Vec<_>>()
                .join(""),
            OpenAiChatMessageContent::Json(value) => value.to_string(),
        }
    }
}

fn normalize_annotation_content(text: String) -> String {
    let trimmed = text.trim().to_string();
    if trimmed.starts_with("```") {
        if let Some(idx) = trimmed.find('\n') {
            let rest = trimmed[idx + 1..].trim();
            if rest.ends_with("```") {
                if let Some(end_idx) = rest.rfind("```") {
                    return rest[..end_idx].trim().to_string();
                }
            }
            return rest.to_string();
        }
    }

    if let (Some(start), Some(end)) = (trimmed.find('{'), trimmed.rfind('}')) {
        if start < end {
            return trimmed[start..=end].to_string();
        }
    }

    trimmed
}

#[derive(Debug, Deserialize)]
struct OpenAiUsage {
    #[serde(default)]
    prompt_tokens: Option<i64>,
    #[serde(default)]
    completion_tokens: Option<i64>,
    #[serde(default)]
    total_tokens: Option<i64>,
}

fn annotation_prompt(lang: &str) -> String {
    format!(
        "Describe the image and respond ONLY as JSON with keys: caption_long (string), tags (array of strings), ocr_text (string|null). Language: {lang}."
    )
}

#[derive(Clone, Debug)]
pub struct MediaAnnotationUsage {
    pub input_tokens: Option<i64>,
    pub output_tokens: Option<i64>,
    pub total_tokens: Option<i64>,
}

fn build_request(
    model_name: &str,
    lang: &str,
    mime_type: &str,
    image_bytes: &[u8],
) -> Result<MediaAnnotationChatCompletionsRequest> {
    if image_bytes.is_empty() {
        return Err(anyhow!("image_bytes is empty"));
    }
    let mime_type = mime_type.trim();
    if mime_type.is_empty() {
        return Err(anyhow!("mime_type is required"));
    }
    let model_name = model_name.trim();
    if model_name.is_empty() {
        return Err(anyhow!("model_name is required"));
    }

    let image_b64 = STANDARD.encode(image_bytes);
    let data_url = format!("data:{mime_type};base64,{image_b64}");

    Ok(MediaAnnotationChatCompletionsRequest {
        model: model_name.to_string(),
        messages: vec![MediaAnnotationChatMessage {
            role: "user".to_string(),
            content: vec![
                MediaAnnotationChatContentPart::Text {
                    text: annotation_prompt(lang),
                },
                MediaAnnotationChatContentPart::ImageUrl {
                    image_url: MediaAnnotationImageUrl { url: data_url },
                },
            ],
        }],
        stream: false,
    })
}

fn parse_response(body: &str) -> Result<(Value, MediaAnnotationUsage)> {
    let parsed: MediaAnnotationChatCompletionsResponse =
        serde_json::from_str(body).map_err(|e| anyhow!("invalid chat completions json: {e}"))?;

    let choice = parsed
        .choices
        .into_iter()
        .next()
        .ok_or_else(|| anyhow!("openai-compatible response has no choices"))?;

    let content = choice
        .message
        .content
        .map(OpenAiChatMessageContent::into_text)
        .unwrap_or_default();
    let normalized = normalize_annotation_content(content);
    let payload: Value = serde_json::from_str(&normalized)
        .map_err(|e| anyhow!("annotation content is not valid json: {e}"))?;

    let usage = parsed.usage.map(|u| MediaAnnotationUsage {
        input_tokens: u.prompt_tokens,
        output_tokens: u.completion_tokens,
        total_tokens: u.total_tokens,
    });

    Ok((
        payload,
        usage.unwrap_or(MediaAnnotationUsage {
            input_tokens: None,
            output_tokens: None,
            total_tokens: None,
        }),
    ))
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
        let req = build_request(&self.model_name, lang, mime_type, image_bytes)?;

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
        let (payload, _usage) = parse_response(&body)?;
        Ok(payload)
    }
}

pub struct OpenAiCompatibleMediaAnnotationClient {
    client: Client,
    base_url: String,
    api_key: String,
    model_name: String,
}

impl OpenAiCompatibleMediaAnnotationClient {
    pub fn new(base_url: String, api_key: String, model_name: String) -> Self {
        Self {
            client: Client::new(),
            base_url,
            api_key,
            model_name,
        }
    }

    pub fn annotate_image_with_usage(
        &self,
        lang: &str,
        mime_type: &str,
        image_bytes: &[u8],
    ) -> Result<(Value, MediaAnnotationUsage)> {
        let req = build_request(&self.model_name, lang, mime_type, image_bytes)?;

        let url = openai_compatible_chat_completions_url(&self.base_url);
        let resp = self
            .client
            .post(url)
            .bearer_auth(&self.api_key)
            .json(&req)
            .send()?;

        if !resp.status().is_success() {
            let status = resp.status();
            let body = resp.text().unwrap_or_default();
            return Err(anyhow!(
                "openai-compatible media annotation request failed: HTTP {status} {body}"
            ));
        }

        let body = resp.text().unwrap_or_default();
        parse_response(&body)
    }
}
