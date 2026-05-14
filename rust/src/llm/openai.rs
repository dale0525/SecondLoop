use std::io::{BufRead, BufReader, Read};

use anyhow::{anyhow, Result};
use reqwest::blocking::Client;
use reqwest::header;
use serde::Serialize;
use serde_json::Value;

use super::todo_followup::{parse_todo_followup_prompt, TodoFollowupGenerationMode};
use super::ChatDelta;

const REASONING_DELTA_ROLE_PREFIX: &str = "secondloop_reasoning_delta:";

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

fn reasoning_role(reasoning_delta: String) -> Option<String> {
    if reasoning_delta.trim().is_empty() {
        None
    } else {
        Some(format!("{REASONING_DELTA_ROLE_PREFIX}{reasoning_delta}"))
    }
}

fn extract_reasoning_delta(value: &Value) -> String {
    for path in [
        "/choices/0/delta/reasoning_content",
        "/choices/0/message/reasoning_content",
        "/choices/0/delta/reasoning",
        "/choices/0/message/reasoning",
        "/reasoning",
    ] {
        if let Some(reasoning) = value.pointer(path) {
            let out = extract_text_from_json_value(reasoning);
            if !out.is_empty() {
                return out;
            }
        }
    }
    String::new()
}

fn is_reasoning_delta_event(value: &Value, event_type: Option<&str>) -> bool {
    let event_name = event_type
        .or_else(|| value.get("type").and_then(Value::as_str))
        .unwrap_or_default();
    matches!(event_name, "response.reasoning_text.delta")
}

#[derive(Debug)]
struct ParsedSseEvent {
    role: Option<String>,
    text_delta: String,
    done: bool,
}

pub fn chat_completions_url(base_url: &str) -> String {
    format!("{}/chat/completions", base_url.trim_end_matches('/'))
}

#[derive(Debug, Serialize)]
struct OpenAiChatCompletionsRequest {
    model: String,
    messages: Vec<OpenAiChatMessage>,
    #[serde(skip_serializing_if = "Option::is_none")]
    temperature: Option<f32>,
    #[serde(skip_serializing_if = "Option::is_none")]
    web_search_options: Option<OpenAiWebSearchOptions>,
    stream: bool,
}

#[derive(Debug, Serialize)]
struct OpenAiWebSearchOptions {
    search_context_size: String,
}

#[derive(Debug, Serialize)]
struct OpenAiChatMessage {
    role: String,
    content: String,
}

pub struct OpenAiCompatibleProvider {
    client: Client,
    base_url: String,
    api_key: String,
    model_name: String,
    temperature: Option<f32>,
}

impl OpenAiCompatibleProvider {
    pub fn new(
        base_url: String,
        api_key: String,
        model_name: String,
        temperature: Option<f32>,
    ) -> Self {
        Self {
            client: Client::new(),
            base_url,
            api_key,
            model_name,
            temperature,
        }
    }
}

impl crate::rag::AnswerProvider for OpenAiCompatibleProvider {
    fn stream_answer(
        &self,
        prompt: &str,
        on_event: &mut dyn FnMut(ChatDelta) -> Result<()>,
    ) -> Result<()> {
        let (todo_followup_mode, prompt_body) = parse_todo_followup_prompt(prompt);
        let url = chat_completions_url(&self.base_url);
        let req = OpenAiChatCompletionsRequest {
            model: self.model_name.clone(),
            messages: vec![OpenAiChatMessage {
                role: "user".to_string(),
                content: prompt_body,
            }],
            temperature: self.temperature,
            web_search_options: match todo_followup_mode {
                Some(TodoFollowupGenerationMode::WebSearch) => Some(OpenAiWebSearchOptions {
                    search_context_size: "medium".to_string(),
                }),
                _ => None,
            },
            stream: true,
        };

        let request_timeout =
            crate::llm::timeouts::ask_ai_timeout_for_prompt_chars(prompt.chars().count());
        let _request_guard = super::request_limiter::acquire_remote_llm_request_slot();

        let mut resp = self
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
            return Err(anyhow::anyhow!(
                "openai-compatible request failed: HTTP {status} {body}"
            ));
        }

        let content_type = resp
            .headers()
            .get(header::CONTENT_TYPE)
            .and_then(|v| v.to_str().ok())
            .unwrap_or_default()
            .to_ascii_lowercase();

        if content_type.contains("text/event-stream") {
            read_chat_completions_sse(&mut resp, on_event)?;
        } else {
            read_chat_completions_json(&mut resp, on_event)?;
        }
        Ok(())
    }
}

pub fn parse_chat_completions_sse(reader: impl Read) -> Result<Vec<ChatDelta>> {
    let mut out = Vec::new();
    read_chat_completions_sse(reader, |ev| {
        out.push(ev);
        Ok(())
    })?;
    Ok(out)
}

pub fn parse_chat_completions_json(reader: impl Read) -> Result<Vec<ChatDelta>> {
    let mut out = Vec::new();
    read_chat_completions_json(reader, |ev| {
        out.push(ev);
        Ok(())
    })?;
    Ok(out)
}

pub fn read_chat_completions_sse(
    reader: impl Read,
    mut on_event: impl FnMut(ChatDelta) -> Result<()>,
) -> Result<()> {
    let mut buf_reader = BufReader::new(reader);
    let mut line = String::new();
    let mut data_lines: Vec<String> = Vec::new();
    let mut event_type: Option<String> = None;
    let mut raw_stream_body = String::new();
    let mut saw_data_line = false;

    fn emit_parsed_event(
        event: ParsedSseEvent,
        on_event: &mut impl FnMut(ChatDelta) -> Result<()>,
    ) -> Result<()> {
        if !event.done && event.role.is_none() && event.text_delta.is_empty() {
            return Ok(());
        }
        on_event(ChatDelta {
            role: event.role,
            text_delta: event.text_delta,
            done: event.done,
        })
    }

    fn extract_role(value: &Value) -> Option<String> {
        value
            .pointer("/choices/0/delta/role")
            .and_then(Value::as_str)
            .map(ToString::to_string)
            .or_else(|| {
                value
                    .pointer("/choices/0/message/role")
                    .and_then(Value::as_str)
                    .map(ToString::to_string)
            })
            .or_else(|| {
                value
                    .pointer("/output/0/role")
                    .and_then(Value::as_str)
                    .map(ToString::to_string)
            })
            .or_else(|| {
                value
                    .get("role")
                    .and_then(Value::as_str)
                    .map(ToString::to_string)
            })
    }

    fn extract_delta_text(value: &Value) -> String {
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

    fn parse_sse_payload(data: &str, event_type: Option<&str>) -> Vec<ParsedSseEvent> {
        if data.trim().is_empty() {
            return Vec::new();
        }
        if data.trim() == "[DONE]" {
            return vec![ParsedSseEvent {
                role: None,
                text_delta: String::new(),
                done: true,
            }];
        }

        let parsed_value: Value = match serde_json::from_str(data) {
            Ok(value) => value,
            Err(_) => return Vec::new(),
        };

        let explicit_done = event_type == Some("done")
            || parsed_value
                .get("type")
                .and_then(Value::as_str)
                .is_some_and(|t| t == "response.completed" || t == "done");

        let role = extract_role(&parsed_value);
        let is_reasoning_event = is_reasoning_delta_event(&parsed_value, event_type);
        let reasoning_delta = if is_reasoning_event {
            parsed_value
                .pointer("/delta")
                .map(extract_text_from_json_value)
                .unwrap_or_default()
        } else {
            extract_reasoning_delta(&parsed_value)
        };
        let text_delta = if is_reasoning_event {
            String::new()
        } else {
            extract_delta_text(&parsed_value)
        };
        if reasoning_delta.trim().is_empty() {
            return vec![ParsedSseEvent {
                role,
                text_delta,
                done: explicit_done,
            }];
        }

        let mut events = Vec::new();
        if let Some(role) = role {
            events.push(ParsedSseEvent {
                role: Some(role),
                text_delta: String::new(),
                done: false,
            });
        }
        if let Some(role) = reasoning_role(reasoning_delta) {
            events.push(ParsedSseEvent {
                role: Some(role),
                text_delta: String::new(),
                done: false,
            });
        }
        if !text_delta.is_empty() {
            events.push(ParsedSseEvent {
                role: None,
                text_delta,
                done: false,
            });
        }
        if explicit_done {
            events.push(ParsedSseEvent {
                role: None,
                text_delta: String::new(),
                done: true,
            });
        }

        events
    }

    fn flush_sse_event(
        data_lines: &mut Vec<String>,
        event_type: &mut Option<String>,
        on_event: &mut impl FnMut(ChatDelta) -> Result<()>,
    ) -> Result<bool> {
        if data_lines.is_empty() {
            *event_type = None;
            return Ok(false);
        }

        let payload = data_lines.join("\n");
        let mut done = false;
        for parsed in parse_sse_payload(&payload, event_type.as_deref()) {
            done = done || parsed.done;
            emit_parsed_event(parsed, on_event)?;
        }

        data_lines.clear();
        *event_type = None;
        Ok(done)
    }

    loop {
        line.clear();
        if buf_reader.read_line(&mut line)? == 0 {
            break;
        }
        raw_stream_body.push_str(&line);

        let line = line.trim_end();
        if line.is_empty() {
            if flush_sse_event(&mut data_lines, &mut event_type, &mut on_event)? {
                return Ok(());
            }
            continue;
        }

        if line.starts_with(':') {
            continue;
        }
        if let Some(v) = line.strip_prefix("event:") {
            event_type = Some(v.trim().to_string());
            continue;
        }
        if let Some(v) = line.strip_prefix("data:") {
            saw_data_line = true;
            data_lines.push(v.trim_start().to_string());
            continue;
        }
    }

    let _ = flush_sse_event(&mut data_lines, &mut event_type, &mut on_event)?;

    if !saw_data_line {
        let trimmed = raw_stream_body.trim();
        if trimmed.starts_with('{') || trimmed.starts_with('[') {
            read_chat_completions_json(trimmed.as_bytes(), on_event)?;
        }
    }

    Ok(())
}

pub fn read_chat_completions_json(
    reader: impl Read,
    mut on_event: impl FnMut(ChatDelta) -> Result<()>,
) -> Result<()> {
    let root: Value = serde_json::from_reader(reader)?;

    if let Some(role) = reasoning_role(extract_reasoning_delta(&root)) {
        on_event(ChatDelta {
            role: Some(role),
            text_delta: String::new(),
            done: false,
        })?;
    }

    let role = root
        .pointer("/choices/0/message/role")
        .and_then(Value::as_str)
        .map(ToString::to_string)
        .or_else(|| {
            root.pointer("/output/0/role")
                .and_then(Value::as_str)
                .map(ToString::to_string)
        });

    let mut text_delta = root
        .pointer("/choices/0/message/content")
        .map(extract_text_from_json_value)
        .unwrap_or_default();
    if text_delta.is_empty() {
        text_delta = root
            .pointer("/output/0/content")
            .map(extract_text_from_json_value)
            .unwrap_or_default();
    }
    if text_delta.is_empty() {
        text_delta = root
            .get("output_text")
            .map(extract_text_from_json_value)
            .unwrap_or_default();
    }
    if text_delta.is_empty() {
        text_delta = root
            .get("text")
            .map(extract_text_from_json_value)
            .unwrap_or_default();
    }

    if role.is_none() && text_delta.is_empty() {
        return Err(anyhow!("openai-compatible response has no text"));
    }

    if role.is_some() || !text_delta.is_empty() {
        on_event(ChatDelta {
            role,
            text_delta,
            done: false,
        })?;
    }

    on_event(ChatDelta {
        role: None,
        text_delta: String::new(),
        done: true,
    })?;

    Ok(())
}
