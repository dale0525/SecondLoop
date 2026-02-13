use std::io::{BufRead, BufReader, Read};

use anyhow::{anyhow, Result};
use reqwest::blocking::Client;
use reqwest::header;
use serde::Serialize;
use serde_json::Value;

use super::ChatDelta;

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
    stream: bool,
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
        let url = chat_completions_url(&self.base_url);
        let req = OpenAiChatCompletionsRequest {
            model: self.model_name.clone(),
            messages: vec![OpenAiChatMessage {
                role: "user".to_string(),
                content: prompt.to_string(),
            }],
            temperature: self.temperature,
            stream: true,
        };

        let request_timeout =
            crate::llm::timeouts::ask_ai_timeout_for_prompt_chars(prompt.chars().count());

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

    fn parse_sse_payload(data: &str, event_type: Option<&str>) -> Option<ParsedSseEvent> {
        if data.trim().is_empty() {
            return None;
        }
        if data.trim() == "[DONE]" {
            return Some(ParsedSseEvent {
                role: None,
                text_delta: String::new(),
                done: true,
            });
        }

        let parsed_value: Value = match serde_json::from_str(data) {
            Ok(value) => value,
            Err(_) => return None,
        };

        let explicit_done = event_type == Some("done")
            || parsed_value
                .get("type")
                .and_then(Value::as_str)
                .is_some_and(|t| t == "response.completed" || t == "done");

        Some(ParsedSseEvent {
            role: extract_role(&parsed_value),
            text_delta: extract_delta_text(&parsed_value),
            done: explicit_done,
        })
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
        let done = if let Some(parsed) = parse_sse_payload(&payload, event_type.as_deref()) {
            let done = parsed.done;
            emit_parsed_event(parsed, on_event)?;
            done
        } else {
            false
        };

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
