use std::io::{BufRead, BufReader, Read};

use anyhow::{anyhow, Result};
use reqwest::blocking::Client;
use reqwest::header;
use serde::Deserialize;
use serde::Serialize;

use super::ChatDelta;

fn normalize_role(role: Option<&str>) -> Option<String> {
    let role = role?.trim();
    if role.is_empty() {
        return None;
    }
    match role {
        "model" => Some("assistant".to_string()),
        other => Some(other.to_string()),
    }
}

#[derive(Debug, Deserialize)]
struct GeminiGenerateContentResponse {
    #[serde(default)]
    candidates: Vec<GeminiCandidate>,
}

#[derive(Debug, Deserialize)]
struct GeminiCandidate {
    #[serde(default)]
    content: Option<GeminiContent>,
    #[serde(default, rename = "finishReason")]
    finish_reason: Option<String>,
}

#[derive(Debug, Deserialize)]
struct GeminiContent {
    #[serde(default)]
    role: Option<String>,
    #[serde(default)]
    parts: Vec<GeminiPart>,
}

#[derive(Debug, Deserialize)]
struct GeminiPart {
    #[serde(default)]
    text: Option<String>,
}

#[derive(Debug, Serialize)]
struct GeminiGenerateContentRequest {
    contents: Vec<GeminiRequestContent>,
}

#[derive(Debug, Serialize)]
struct GeminiRequestContent {
    role: String,
    parts: Vec<GeminiRequestPart>,
}

#[derive(Debug, Serialize)]
struct GeminiRequestPart {
    text: String,
}

pub fn generate_content_url(base_url: &str, model_name: &str, api_key: &str) -> String {
    format!(
        "{}/models/{}:generateContent?key={}",
        base_url.trim_end_matches('/'),
        model_name,
        api_key
    )
}

pub fn stream_generate_content_url(base_url: &str, model_name: &str, api_key: &str) -> String {
    format!(
        "{}/models/{}:streamGenerateContent?alt=sse&key={}",
        base_url.trim_end_matches('/'),
        model_name,
        api_key
    )
}

fn build_generate_content_request(prompt: &str) -> GeminiGenerateContentRequest {
    GeminiGenerateContentRequest {
        contents: vec![GeminiRequestContent {
            role: "user".to_string(),
            parts: vec![GeminiRequestPart {
                text: prompt.to_string(),
            }],
        }],
    }
}

pub struct GeminiCompatibleProvider {
    client: Client,
    base_url: String,
    api_key: String,
    model_name: String,
}

impl GeminiCompatibleProvider {
    pub fn new(base_url: String, api_key: String, model_name: String) -> Self {
        Self {
            client: Client::new(),
            base_url,
            api_key,
            model_name,
        }
    }
}

impl crate::rag::AnswerProvider for GeminiCompatibleProvider {
    fn stream_answer(
        &self,
        prompt: &str,
        on_event: &mut dyn FnMut(ChatDelta) -> Result<()>,
    ) -> Result<()> {
        let url = stream_generate_content_url(&self.base_url, &self.model_name, &self.api_key);
        let req = build_generate_content_request(prompt);

        let mut resp = self
            .client
            .post(url)
            .header(header::ACCEPT, "text/event-stream")
            .json(&req)
            .send()?;

        if !resp.status().is_success() {
            let status = resp.status();
            let body = resp.text().unwrap_or_default();
            return Err(anyhow!("gemini request failed: HTTP {status} {body}"));
        }

        let content_type = resp
            .headers()
            .get(header::CONTENT_TYPE)
            .and_then(|v| v.to_str().ok())
            .unwrap_or_default()
            .to_ascii_lowercase();

        if content_type.contains("text/event-stream") {
            read_generate_content_sse(&mut resp, on_event)?;
        } else {
            read_generate_content_json(&mut resp, on_event)?;
        }
        Ok(())
    }
}

pub fn parse_generate_content_sse(reader: impl Read) -> Result<Vec<ChatDelta>> {
    let mut out = Vec::new();
    read_generate_content_sse(reader, |ev| {
        out.push(ev);
        Ok(())
    })?;
    Ok(out)
}

pub fn parse_generate_content_json(reader: impl Read) -> Result<Vec<ChatDelta>> {
    let mut out = Vec::new();
    read_generate_content_json(reader, |ev| {
        out.push(ev);
        Ok(())
    })?;
    Ok(out)
}

pub fn read_generate_content_sse(
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

        let chunk: GeminiGenerateContentResponse = serde_json::from_str(data)?;
        let candidate = match chunk.candidates.first() {
            Some(v) => v,
            None => continue,
        };

        let role = candidate
            .content
            .as_ref()
            .and_then(|c| normalize_role(c.role.as_deref()));
        if !role_emitted {
            if let Some(role) = role {
                on_event(ChatDelta {
                    role: Some(role),
                    text_delta: String::new(),
                    done: false,
                })?;
                role_emitted = true;
            }
        }

        if let Some(content) = candidate.content.as_ref() {
            for part in &content.parts {
                let text = part.text.clone().unwrap_or_default();
                if text.is_empty() {
                    continue;
                }
                on_event(ChatDelta {
                    role: None,
                    text_delta: text,
                    done: false,
                })?;
            }
        }

        if candidate.finish_reason.is_some() {
            on_event(ChatDelta {
                role: None,
                text_delta: String::new(),
                done: true,
            })?;
            done_emitted = true;
            break;
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

pub fn read_generate_content_json(
    reader: impl Read,
    mut on_event: impl FnMut(ChatDelta) -> Result<()>,
) -> Result<()> {
    let resp: GeminiGenerateContentResponse = serde_json::from_reader(reader)?;
    let candidate = resp
        .candidates
        .into_iter()
        .next()
        .ok_or_else(|| anyhow!("gemini response has no candidates"))?;

    let role = candidate
        .content
        .as_ref()
        .and_then(|c| normalize_role(c.role.as_deref()));

    let mut text = String::new();
    if let Some(content) = candidate.content {
        for part in content.parts {
            if let Some(part_text) = part.text {
                text.push_str(&part_text);
            }
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
