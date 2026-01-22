use std::io::{BufRead, BufReader, Read};

use anyhow::{anyhow, Result};
use reqwest::blocking::Client;
use reqwest::header;
use serde::Deserialize;
use serde::Serialize;

use super::ChatDelta;

#[derive(Debug, Deserialize)]
struct OpenAiStreamChunk {
    #[serde(default)]
    choices: Vec<OpenAiStreamChoice>,
}

#[derive(Debug, Deserialize)]
struct OpenAiStreamChoice {
    delta: OpenAiDelta,
}

#[derive(Debug, Deserialize)]
struct OpenAiChatCompletionsResponse {
    choices: Vec<OpenAiChatCompletionsChoice>,
}

#[derive(Debug, Deserialize)]
struct OpenAiChatCompletionsChoice {
    message: OpenAiChatCompletionsMessage,
}

#[derive(Debug, Deserialize)]
struct OpenAiChatCompletionsMessage {
    #[serde(default)]
    role: Option<String>,
    #[serde(default)]
    content: Option<String>,
}

#[derive(Debug, Deserialize)]
struct OpenAiDelta {
    #[serde(default)]
    role: Option<String>,
    #[serde(default)]
    content: Option<String>,
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

        let mut resp = self
            .client
            .post(url)
            .bearer_auth(&self.api_key)
            .header(header::ACCEPT, "text/event-stream")
            .json(&req)
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
            break;
        }

        let chunk: OpenAiStreamChunk = serde_json::from_str(data)?;
        let choice = match chunk.choices.first() {
            Some(v) => v,
            None => continue,
        };

        let role = choice.delta.role.clone();
        let text_delta = choice.delta.content.clone().unwrap_or_default();
        if role.is_none() && text_delta.is_empty() {
            continue;
        }

        on_event(ChatDelta {
            role,
            text_delta,
            done: false,
        })?;
    }

    Ok(())
}

pub fn read_chat_completions_json(
    reader: impl Read,
    mut on_event: impl FnMut(ChatDelta) -> Result<()>,
) -> Result<()> {
    let resp: OpenAiChatCompletionsResponse = serde_json::from_reader(reader)?;
    let choice = resp
        .choices
        .into_iter()
        .next()
        .ok_or_else(|| anyhow!("openai-compatible response has no choices"))?;

    let role = choice.message.role;
    let text_delta = choice.message.content.unwrap_or_default();

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
