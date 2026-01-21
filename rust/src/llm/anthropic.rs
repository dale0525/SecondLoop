use std::io::{BufRead, BufReader, Read};

use anyhow::{anyhow, Result};
use reqwest::blocking::Client;
use reqwest::header;
use serde::Deserialize;
use serde::Serialize;

use super::ChatDelta;

#[derive(Debug, Serialize)]
struct AnthropicMessagesRequest {
    model: String,
    max_tokens: u32,
    messages: Vec<AnthropicMessage>,
    stream: bool,
}

#[derive(Debug, Serialize)]
struct AnthropicMessage {
    role: String,
    content: String,
}

#[derive(Debug, Deserialize)]
struct AnthropicMessagesResponse {
    #[serde(default)]
    role: Option<String>,
    #[serde(default)]
    content: Vec<AnthropicContentBlock>,
}

#[derive(Debug, Deserialize)]
struct AnthropicContentBlock {
    #[serde(rename = "type")]
    block_type: String,
    #[serde(default)]
    text: Option<String>,
}

pub fn messages_url(base_url: &str) -> String {
    format!("{}/messages", base_url.trim_end_matches('/'))
}

fn build_messages_request(
    prompt: &str,
    model_name: &str,
    max_tokens: u32,
) -> AnthropicMessagesRequest {
    AnthropicMessagesRequest {
        model: model_name.to_string(),
        max_tokens,
        messages: vec![AnthropicMessage {
            role: "user".to_string(),
            content: prompt.to_string(),
        }],
        stream: true,
    }
}

pub struct AnthropicCompatibleProvider {
    client: Client,
    base_url: String,
    api_key: String,
    model_name: String,
    max_tokens: u32,
}

impl AnthropicCompatibleProvider {
    pub fn new(base_url: String, api_key: String, model_name: String, max_tokens: u32) -> Self {
        Self {
            client: Client::new(),
            base_url,
            api_key,
            model_name,
            max_tokens,
        }
    }
}

impl crate::rag::AnswerProvider for AnthropicCompatibleProvider {
    fn stream_answer(
        &self,
        prompt: &str,
        on_event: &mut dyn FnMut(ChatDelta) -> Result<()>,
    ) -> Result<()> {
        let url = messages_url(&self.base_url);
        let req = build_messages_request(prompt, &self.model_name, self.max_tokens);

        let mut resp = self
            .client
            .post(url)
            .header(header::ACCEPT, "text/event-stream")
            .header("x-api-key", &self.api_key)
            .header("anthropic-version", "2023-06-01")
            .json(&req)
            .send()?;

        if !resp.status().is_success() {
            let status = resp.status();
            let body = resp.text().unwrap_or_default();
            return Err(anyhow!("anthropic request failed: HTTP {status} {body}"));
        }

        let content_type = resp
            .headers()
            .get(header::CONTENT_TYPE)
            .and_then(|v| v.to_str().ok())
            .unwrap_or_default()
            .to_ascii_lowercase();

        if content_type.contains("text/event-stream") {
            read_messages_sse(&mut resp, on_event)?;
        } else {
            read_messages_json(&mut resp, on_event)?;
        }

        Ok(())
    }
}

pub fn parse_messages_sse(reader: impl Read) -> Result<Vec<ChatDelta>> {
    let mut out = Vec::new();
    read_messages_sse(reader, |ev| {
        out.push(ev);
        Ok(())
    })?;
    Ok(out)
}

pub fn parse_messages_json(reader: impl Read) -> Result<Vec<ChatDelta>> {
    let mut out = Vec::new();
    read_messages_json(reader, |ev| {
        out.push(ev);
        Ok(())
    })?;
    Ok(out)
}

pub fn read_messages_sse(
    reader: impl Read,
    mut on_event: impl FnMut(ChatDelta) -> Result<()>,
) -> Result<()> {
    let mut buf_reader = BufReader::new(reader);
    let mut line = String::new();
    let mut role_emitted = false;
    let mut done_emitted = false;

    loop {
        line.clear();
        if buf_reader.read_line(&mut line)? == 0 {
            break;
        }

        let line = line.trim_end();
        if line.is_empty() {
            continue;
        }

        let data = match line.strip_prefix("data:") {
            Some(v) => v.trim(),
            None => continue,
        };

        if data == "[DONE]" {
            on_event(ChatDelta {
                role: None,
                text_delta: String::new(),
                done: true,
            })?;
            done_emitted = true;
            break;
        }

        let v: serde_json::Value = serde_json::from_str(data)?;
        let ty = v.get("type").and_then(|v| v.as_str()).unwrap_or_default();

        match ty {
            "message_start" => {
                if role_emitted {
                    continue;
                }
                let role = v
                    .get("message")
                    .and_then(|m| m.get("role"))
                    .and_then(|r| r.as_str())
                    .unwrap_or_default();
                if role.is_empty() {
                    continue;
                }
                on_event(ChatDelta {
                    role: Some(role.to_string()),
                    text_delta: String::new(),
                    done: false,
                })?;
                role_emitted = true;
            }
            "content_block_delta" => {
                let delta_type = v
                    .get("delta")
                    .and_then(|d| d.get("type"))
                    .and_then(|t| t.as_str())
                    .unwrap_or_default();
                if delta_type != "text_delta" {
                    continue;
                }
                let text = v
                    .get("delta")
                    .and_then(|d| d.get("text"))
                    .and_then(|t| t.as_str())
                    .unwrap_or_default();
                if text.is_empty() {
                    continue;
                }
                on_event(ChatDelta {
                    role: None,
                    text_delta: text.to_string(),
                    done: false,
                })?;
            }
            "message_stop" => {
                on_event(ChatDelta {
                    role: None,
                    text_delta: String::new(),
                    done: true,
                })?;
                done_emitted = true;
                break;
            }
            _ => {}
        }
    }

    if !done_emitted {
        on_event(ChatDelta {
            role: None,
            text_delta: String::new(),
            done: true,
        })?;
    }

    Ok(())
}

pub fn read_messages_json(
    reader: impl Read,
    mut on_event: impl FnMut(ChatDelta) -> Result<()>,
) -> Result<()> {
    let resp: AnthropicMessagesResponse = serde_json::from_reader(reader)?;
    let role = resp.role.or_else(|| Some("assistant".to_string()));

    let mut text = String::new();
    for block in resp.content {
        if block.block_type != "text" {
            continue;
        }
        if let Some(t) = block.text {
            text.push_str(&t);
        }
    }

    if role.is_some() || !text.is_empty() {
        on_event(ChatDelta {
            role,
            text_delta: text,
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
