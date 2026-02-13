use anyhow::{anyhow, Result};
use base64::{engine::general_purpose::STANDARD, Engine as _};
use reqwest::blocking::Client;
use reqwest::header;
use serde::{Deserialize, Serialize};
use serde_json::Map;
use serde_json::Value;
use std::io::{BufRead, BufReader};
use std::time::Duration;

use sha2::{Digest, Sha256};

const OCR_MARKDOWN_LANG_PREFIX: &str = "ocr_markdown:";
const DETACHED_JOB_STATUS_TIMEOUT_SECONDS: u64 = 12;
const SECONDLOOP_CLOUD_REQUEST_ID_KEY: &str = "secondloop_cloud_request_id";

fn build_request_id(
    model_name: &str,
    lang: &str,
    mime_type: &str,
    image_bytes: &[u8],
    prompt_mode: MediaAnnotationPromptMode,
) -> String {
    let mut hasher = Sha256::new();
    hasher.update(b"secondloop_media_annotation_detached_v1");
    hasher.update(model_name.trim().as_bytes());
    hasher.update([0]);
    hasher.update(lang.trim().as_bytes());
    hasher.update([0]);
    hasher.update(mime_type.trim().to_ascii_lowercase().as_bytes());
    hasher.update([0]);
    match prompt_mode {
        MediaAnnotationPromptMode::Annotation => hasher.update(b"annotation"),
        MediaAnnotationPromptMode::OcrMarkdown => hasher.update(b"ocr_markdown"),
    }
    hasher.update([0]);
    hasher.update(image_bytes.len().to_le_bytes());
    hasher.update(image_bytes);

    let digest = hasher.finalize();
    let mut suffix = String::with_capacity(32);
    for b in &digest[..16] {
        suffix.push_str(&format!("{b:02x}"));
    }

    format!("req_ma_{suffix}")
}

pub fn cloud_gateway_chat_completions_url(gateway_base_url: &str) -> String {
    format!(
        "{}/v1/chat/completions",
        gateway_base_url.trim_end_matches('/')
    )
}

fn openai_compatible_chat_completions_url(base_url: &str) -> String {
    format!("{}/chat/completions", base_url.trim_end_matches('/'))
}

fn cloud_gateway_chat_job_status_url(gateway_base_url: &str, request_id: &str) -> String {
    format!(
        "{}/v1/chat/jobs/{request_id}",
        gateway_base_url.trim_end_matches('/')
    )
}

#[derive(Debug, Serialize)]
struct MediaAnnotationChatCompletionsRequest {
    model: String,
    messages: Vec<MediaAnnotationChatMessage>,
    stream: bool,
    #[serde(skip_serializing_if = "Option::is_none")]
    stream_options: Option<MediaAnnotationStreamOptions>,
}

#[derive(Debug, Serialize)]
struct MediaAnnotationStreamOptions {
    include_usage: bool,
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
        "Describe the image and respond ONLY as JSON with keys: tag (array of strings), summary (string), full_text (string). summary should be concise. full_text should contain readable text from the image when available, otherwise use an empty string. If text with visual layout is present, full_text should use Markdown and preserve layout (headings, lists, tables, line breaks) as much as possible. Language: {lang}."
    )
}

fn ocr_markdown_prompt(lang: &str) -> String {
    format!(
        "Perform OCR on the provided file/image and respond ONLY as JSON with keys: tag (array of strings), summary (string), full_text (string). Put recognized text in full_text using Markdown and preserve original layout as much as possible (headings, lists, tables, line breaks). If no readable text exists, set full_text to an empty string. summary must be a short overview. Language: {lang}. Do not wrap JSON in markdown fences."
    )
}

fn extract_first_non_empty_string(map: &Map<String, Value>, keys: &[&str]) -> String {
    for key in keys {
        let Some(value) = map.get(*key) else {
            continue;
        };
        let Some(text) = value.as_str() else {
            continue;
        };
        let trimmed = text.trim();
        if !trimmed.is_empty() {
            return trimmed.to_string();
        }
    }
    String::new()
}

fn push_unique_tag(out: &mut Vec<String>, candidate: &str) {
    let trimmed = candidate.trim();
    if trimmed.is_empty() {
        return;
    }
    if out
        .iter()
        .any(|existing| existing.eq_ignore_ascii_case(trimmed))
    {
        return;
    }
    out.push(trimmed.to_string());
}

fn collect_tag_values(value: &Value, out: &mut Vec<String>) {
    match value {
        Value::Array(items) => {
            for item in items {
                if let Some(tag) = item.as_str() {
                    push_unique_tag(out, tag);
                }
            }
        }
        Value::String(tag) => push_unique_tag(out, tag),
        _ => {}
    }
}

fn normalized_tags(map: &Map<String, Value>) -> Vec<String> {
    let mut tags = Vec::<String>::new();
    if let Some(value) = map.get("tag") {
        collect_tag_values(value, &mut tags);
    }
    if let Some(value) = map.get("tags") {
        collect_tag_values(value, &mut tags);
    }
    tags
}

fn normalize_annotation_payload(payload: Value) -> Result<Value> {
    let mut map = match payload {
        Value::Object(map) => map,
        _ => return Err(anyhow!("annotation content json must be an object")),
    };

    let tags = normalized_tags(&map);
    let summary = extract_first_non_empty_string(&map, &["summary", "caption_long"]);
    let full_text = extract_first_non_empty_string(&map, &["full_text", "ocr_text"]);

    let tags_json = Value::Array(tags.iter().map(|tag| Value::String(tag.clone())).collect());

    map.insert("tag".to_string(), tags_json.clone());
    map.insert("summary".to_string(), Value::String(summary.clone()));
    map.insert("full_text".to_string(), Value::String(full_text.clone()));

    map.insert("tags".to_string(), tags_json);
    map.insert("caption_long".to_string(), Value::String(summary));
    if full_text.is_empty() {
        map.insert("ocr_text".to_string(), Value::Null);
    } else {
        map.insert("ocr_text".to_string(), Value::String(full_text));
    }

    Ok(Value::Object(map))
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
enum MediaAnnotationPromptMode {
    Annotation,
    OcrMarkdown,
}

fn parse_prompt_mode_and_lang(raw_lang: &str) -> (MediaAnnotationPromptMode, String) {
    let trimmed = raw_lang.trim();
    if let Some(rest) = trimmed.strip_prefix(OCR_MARKDOWN_LANG_PREFIX) {
        let normalized = rest.trim();
        if normalized.is_empty() {
            return (MediaAnnotationPromptMode::OcrMarkdown, "und".to_string());
        }
        return (
            MediaAnnotationPromptMode::OcrMarkdown,
            normalized.to_string(),
        );
    }

    if trimmed.is_empty() {
        return (MediaAnnotationPromptMode::Annotation, "und".to_string());
    }

    (MediaAnnotationPromptMode::Annotation, trimmed.to_string())
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
) -> Result<(
    MediaAnnotationChatCompletionsRequest,
    MediaAnnotationPromptMode,
)> {
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
    let (prompt_mode, normalized_lang) = parse_prompt_mode_and_lang(lang);

    let image_b64 = STANDARD.encode(image_bytes);
    let data_url = format!("data:{mime_type};base64,{image_b64}");
    let prompt = match prompt_mode {
        MediaAnnotationPromptMode::Annotation => annotation_prompt(&normalized_lang),
        MediaAnnotationPromptMode::OcrMarkdown => ocr_markdown_prompt(&normalized_lang),
    };

    Ok((
        MediaAnnotationChatCompletionsRequest {
            model: model_name.to_string(),
            messages: vec![MediaAnnotationChatMessage {
                role: "user".to_string(),
                content: vec![
                    MediaAnnotationChatContentPart::Text { text: prompt },
                    MediaAnnotationChatContentPart::ImageUrl {
                        image_url: MediaAnnotationImageUrl { url: data_url },
                    },
                ],
            }],
            stream: true,
            stream_options: Some(MediaAnnotationStreamOptions {
                include_usage: true,
            }),
        },
        prompt_mode,
    ))
}

fn extract_text_from_json_value(value: &Value) -> String {
    match value {
        Value::String(text) => text.clone(),
        Value::Array(items) => items
            .iter()
            .map(extract_text_from_json_value)
            .collect::<Vec<_>>()
            .join(""),
        Value::Object(map) => {
            let from_text = map
                .get("text")
                .map(extract_text_from_json_value)
                .unwrap_or_default();
            if !from_text.is_empty() {
                return from_text;
            }
            map.get("content")
                .map(extract_text_from_json_value)
                .unwrap_or_default()
        }
        _ => String::new(),
    }
}

fn extract_stream_delta_text(value: &Value) -> String {
    if let Some(content) = value.pointer("/choices/0/delta/content") {
        let out = extract_text_from_json_value(content);
        if !out.is_empty() {
            return out;
        }
    }
    if let Some(content) = value.pointer("/choices/0/message/content") {
        let out = extract_text_from_json_value(content);
        if !out.is_empty() {
            return out;
        }
    }
    if let Some(content) = value.pointer("/output/0/content") {
        let out = extract_text_from_json_value(content);
        if !out.is_empty() {
            return out;
        }
    }
    if let Some(text) = value.pointer("/choices/0/delta/text") {
        let out = extract_text_from_json_value(text);
        if !out.is_empty() {
            return out;
        }
    }
    if let Some(delta) = value.get("delta") {
        let out = extract_text_from_json_value(delta);
        if !out.is_empty() {
            return out;
        }
    }
    if let Some(text) = value.get("text") {
        let out = extract_text_from_json_value(text);
        if !out.is_empty() {
            return out;
        }
    }
    if let Some(output_text) = value.get("output_text") {
        let out = extract_text_from_json_value(output_text);
        if !out.is_empty() {
            return out;
        }
    }
    String::new()
}

fn usage_from_openai_usage(usage: OpenAiUsage) -> MediaAnnotationUsage {
    let total = usage.total_tokens.or_else(|| {
        let input = usage.prompt_tokens.unwrap_or(0);
        let output = usage.completion_tokens.unwrap_or(0);
        if input == 0 && output == 0 {
            None
        } else {
            Some(input + output)
        }
    });
    MediaAnnotationUsage {
        input_tokens: usage.prompt_tokens,
        output_tokens: usage.completion_tokens,
        total_tokens: total,
    }
}

fn parse_usage_from_json(value: &Value) -> Option<MediaAnnotationUsage> {
    let parsed = serde_json::from_value::<OpenAiUsage>(value.clone()).ok()?;
    let usage = usage_from_openai_usage(parsed);
    if usage.input_tokens.is_none() && usage.output_tokens.is_none() && usage.total_tokens.is_none()
    {
        return None;
    }
    Some(usage)
}

fn default_usage() -> MediaAnnotationUsage {
    MediaAnnotationUsage {
        input_tokens: None,
        output_tokens: None,
        total_tokens: None,
    }
}

fn parse_annotation_payload_text(raw: &str) -> Result<Value> {
    let normalized = normalize_annotation_content(raw.to_string());
    if normalized.trim().is_empty() {
        return Err(anyhow!("annotation stream returned empty content"));
    }

    let payload: Value = serde_json::from_str(&normalized)
        .map_err(|e| anyhow!("annotation content is not valid json: {e}"))?;
    normalize_annotation_payload(payload)
}

fn maybe_extract_detached_job_result_text(status_payload: &Value) -> Option<String> {
    let status = status_payload
        .get("status")
        .and_then(Value::as_str)
        .unwrap_or_default()
        .trim()
        .to_ascii_lowercase();

    if status != "completed" {
        return None;
    }

    let result_text = status_payload
        .get("result_text")
        .and_then(Value::as_str)
        .unwrap_or_default()
        .trim();

    if result_text.is_empty() {
        return None;
    }

    Some(result_text.to_string())
}

fn attach_cloud_request_id(mut payload: Value, request_id: &str) -> Value {
    if let Value::Object(map) = &mut payload {
        map.insert(
            SECONDLOOP_CLOUD_REQUEST_ID_KEY.to_string(),
            Value::String(request_id.to_string()),
        );
    }
    payload
}

fn parse_response_json(body: &str) -> Result<(Value, MediaAnnotationUsage)> {
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
    let payload = parse_annotation_payload_text(&content)?;

    let usage = parsed.usage.map(usage_from_openai_usage);

    Ok((payload, usage.unwrap_or_else(default_usage)))
}

fn parse_response_sse_reader<R: BufRead>(reader: &mut R) -> Result<(Value, MediaAnnotationUsage)> {
    let mut data_lines: Vec<String> = Vec::new();
    let mut all_text = String::new();
    let mut usage: Option<MediaAnnotationUsage> = None;
    let mut done_seen = false;

    let mut process_event = |lines: &mut Vec<String>, done: &mut bool| {
        if lines.is_empty() {
            return;
        }
        let payload = lines.join("\n");
        lines.clear();

        let trimmed = payload.trim();
        if trimmed.is_empty() {
            return;
        }
        if trimmed == "[DONE]" {
            *done = true;
            return;
        }

        let value: Value = match serde_json::from_str(trimmed) {
            Ok(v) => v,
            Err(_) => return,
        };

        if let Some(raw_usage) = value.get("usage") {
            if let Some(parsed_usage) = parse_usage_from_json(raw_usage) {
                usage = Some(parsed_usage);
            }
        }

        let delta = extract_stream_delta_text(&value);
        if !delta.is_empty() {
            all_text.push_str(&delta);
        }
    };

    loop {
        let mut line = String::new();
        match reader.read_line(&mut line) {
            Ok(0) => {
                process_event(&mut data_lines, &mut done_seen);
                break;
            }
            Ok(_) => {
                let trimmed = line.trim_end_matches(&['\r', '\n'][..]);
                if trimmed.is_empty() {
                    process_event(&mut data_lines, &mut done_seen);
                    if done_seen {
                        break;
                    }
                    continue;
                }
                if let Some(rest) = trimmed.strip_prefix("data:") {
                    data_lines.push(rest.trim().to_string());
                }
            }
            Err(err) => {
                process_event(&mut data_lines, &mut done_seen);
                if !done_seen {
                    return Err(anyhow!("failed to read annotation SSE stream: {err}"));
                }
                break;
            }
        }
    }

    let payload = parse_annotation_payload_text(&all_text)?;

    Ok((payload, usage.unwrap_or_else(default_usage)))
}

fn parse_response_from_http_response(
    resp: reqwest::blocking::Response,
) -> Result<(Value, MediaAnnotationUsage)> {
    let content_type = resp
        .headers()
        .get(header::CONTENT_TYPE)
        .and_then(|v| v.to_str().ok())
        .unwrap_or_default()
        .to_ascii_lowercase();

    if content_type.contains("text/event-stream") {
        let mut reader = BufReader::new(resp);
        return parse_response_sse_reader(&mut reader);
    }

    let body = resp.text().unwrap_or_default();
    parse_response_json(&body)
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

    fn try_recover_detached_payload(&self, request_id: &str) -> Option<Value> {
        let status_url = cloud_gateway_chat_job_status_url(&self.gateway_base_url, request_id);

        let resp = self
            .client
            .get(status_url)
            .bearer_auth(&self.id_token)
            .header(header::ACCEPT, "application/json")
            .timeout(Duration::from_secs(DETACHED_JOB_STATUS_TIMEOUT_SECONDS))
            .send()
            .ok()?;

        if !resp.status().is_success() {
            return None;
        }

        let body = resp.text().ok()?;
        let status_payload: Value = serde_json::from_str(&body).ok()?;
        let result_text = maybe_extract_detached_job_result_text(&status_payload)?;
        let payload = parse_annotation_payload_text(&result_text).ok()?;
        Some(attach_cloud_request_id(payload, request_id))
    }

    pub fn annotate_image(&self, lang: &str, mime_type: &str, image_bytes: &[u8]) -> Result<Value> {
        let (req, prompt_mode) = build_request(&self.model_name, lang, mime_type, image_bytes)?;
        let request_timeout = crate::llm::timeouts::media_annotation_timeout_for_image_bytes(
            image_bytes.len(),
            prompt_mode == MediaAnnotationPromptMode::OcrMarkdown,
        );
        let purpose = match prompt_mode {
            MediaAnnotationPromptMode::Annotation => "media_annotation",
            MediaAnnotationPromptMode::OcrMarkdown => "ask_ai",
        };
        let request_id =
            build_request_id(&self.model_name, lang, mime_type, image_bytes, prompt_mode);

        if let Some(payload) = self.try_recover_detached_payload(&request_id) {
            return Ok(payload);
        }

        let url = cloud_gateway_chat_completions_url(&self.gateway_base_url);
        let resp = match self
            .client
            .post(url)
            .bearer_auth(&self.id_token)
            .header("x-secondloop-purpose", purpose)
            .header("x-secondloop-request-id", &request_id)
            .header("x-secondloop-detach-policy", "continue_on_disconnect")
            .header(header::ACCEPT, "text/event-stream")
            .json(&req)
            .timeout(request_timeout)
            .send()
        {
            Ok(resp) => resp,
            Err(err) => {
                if let Some(payload) = self.try_recover_detached_payload(&request_id) {
                    return Ok(payload);
                }
                return Err(err.into());
            }
        };

        if !resp.status().is_success() {
            let status = resp.status();
            let body = resp.text().unwrap_or_default();
            return Err(anyhow!(
                "cloud-gateway media annotation request failed: HTTP {status} {body}"
            ));
        }

        match parse_response_from_http_response(resp) {
            Ok((payload, _usage)) => Ok(attach_cloud_request_id(payload, &request_id)),
            Err(err) => {
                if let Some(payload) = self.try_recover_detached_payload(&request_id) {
                    return Ok(payload);
                }
                Err(err)
            }
        }
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
        let (req, prompt_mode) = build_request(&self.model_name, lang, mime_type, image_bytes)?;
        let request_timeout = crate::llm::timeouts::media_annotation_timeout_for_image_bytes(
            image_bytes.len(),
            prompt_mode == MediaAnnotationPromptMode::OcrMarkdown,
        );

        let url = openai_compatible_chat_completions_url(&self.base_url);
        let resp = self
            .client
            .post(url)
            .bearer_auth(&self.api_key)
            .header(header::ACCEPT, "text/event-stream")
            .json(&req)
            .timeout(request_timeout)
            .send()?;

        if !resp.status().is_success() {
            let status = resp.status();
            let body = resp.text().unwrap_or_default();
            return Err(anyhow!(
                "openai-compatible media annotation request failed: HTTP {status} {body}"
            ));
        }

        parse_response_from_http_response(resp)
    }
}
