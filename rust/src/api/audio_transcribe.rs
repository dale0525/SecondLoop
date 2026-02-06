use std::path::Path;

use anyhow::{anyhow, Result};
use base64::{engine::general_purpose::STANDARD, Engine as _};
use reqwest::blocking::{multipart, Client};
use serde::Deserialize;
use serde_json::Value;

use crate::db;

fn key_from_bytes(bytes: Vec<u8>) -> Result<[u8; 32]> {
    if bytes.len() != 32 {
        return Err(anyhow!("invalid key length"));
    }
    let mut key = [0u8; 32];
    key.copy_from_slice(&bytes);
    Ok(key)
}

fn openai_audio_transcriptions_url(base_url: &str) -> String {
    format!("{}/audio/transcriptions", base_url.trim_end_matches('/'))
}

fn openai_chat_completions_url(base_url: &str) -> String {
    format!("{}/chat/completions", base_url.trim_end_matches('/'))
}

fn file_ext_for_mime_type(mime_type: &str) -> &'static str {
    match mime_type.trim().to_lowercase().as_str() {
        "audio/mp4" => "m4a",
        "audio/mpeg" => "mp3",
        "audio/wav" | "audio/wave" | "audio/x-wav" => "wav",
        "audio/flac" => "flac",
        "audio/ogg" | "audio/opus" => "ogg",
        "audio/aac" => "aac",
        _ => "bin",
    }
}

fn audio_input_format_by_mime_type(mime_type: &str) -> &'static str {
    match mime_type.trim().to_lowercase().as_str() {
        "audio/mpeg" => "mp3",
        "audio/wav" | "audio/wave" | "audio/x-wav" => "wav",
        "audio/ogg" | "audio/opus" => "ogg",
        "audio/flac" => "flac",
        "audio/aac" => "aac",
        "audio/mp4" | "audio/m4a" | "audio/x-m4a" => "m4a",
        _ => "mp3",
    }
}

fn multimodal_transcribe_prompt(lang: &str) -> String {
    let trimmed = lang.trim();
    if trimmed.is_empty() {
        "Transcribe the provided audio and return plain text only.".to_string()
    } else {
        format!(
            "Transcribe the provided audio in language \"{trimmed}\" and return plain text only."
        )
    }
}

fn normalize_transcript_text(text: &str) -> String {
    let mut trimmed = text.trim().to_string();
    if trimmed.is_empty() {
        return String::new();
    }

    if trimmed.starts_with("```") {
        if let Some(idx) = trimmed.find('\n') {
            let rest = trimmed[idx + 1..].trim();
            if let Some(stripped) = rest.strip_suffix("```") {
                trimmed = stripped.trim().to_string();
            } else {
                trimmed = rest.to_string();
            }
        }
    }

    if let Ok(Value::String(value)) = serde_json::from_str::<Value>(&trimmed) {
        return value.trim().to_string();
    }
    if let Ok(Value::Object(map)) = serde_json::from_str::<Value>(&trimmed) {
        if let Some(Value::String(text)) = map.get("text") {
            let v = text.trim();
            if !v.is_empty() {
                return v.to_string();
            }
        }
        if let Some(Value::String(text)) = map.get("transcript") {
            let v = text.trim();
            if !v.is_empty() {
                return v.to_string();
            }
        }
    }

    trimmed
}

fn chat_message_content_to_text(value: &Value) -> String {
    match value {
        Value::Null => String::new(),
        Value::String(text) => text.to_string(),
        Value::Array(items) => items
            .iter()
            .filter_map(|item| match item {
                Value::Object(map) => map
                    .get("text")
                    .and_then(Value::as_str)
                    .map(|text| text.to_string()),
                _ => None,
            })
            .collect::<Vec<_>>()
            .join("\n"),
        Value::Object(map) => map
            .get("text")
            .and_then(Value::as_str)
            .map(|text| text.to_string())
            .unwrap_or_default(),
        _ => value.to_string(),
    }
}

fn extract_transcript_text(response: &Value) -> String {
    let direct_text = response
        .get("text")
        .and_then(Value::as_str)
        .unwrap_or_default()
        .trim()
        .to_string();
    let direct_transcript = response
        .get("transcript")
        .and_then(Value::as_str)
        .unwrap_or_default()
        .trim()
        .to_string();

    let mut text = normalize_transcript_text(if !direct_text.is_empty() {
        &direct_text
    } else {
        &direct_transcript
    });
    if !text.is_empty() {
        return text;
    }

    if let Some(Value::Array(choices)) = response.get("choices") {
        if let Some(Value::Object(first_choice)) = choices.first() {
            if let Some(Value::Object(message)) = first_choice.get("message") {
                if let Some(content) = message.get("content") {
                    text = normalize_transcript_text(&chat_message_content_to_text(content));
                }
            } else if let Some(content) = first_choice.get("content") {
                text = normalize_transcript_text(&chat_message_content_to_text(content));
            }
        }
    }

    text
}

#[derive(Debug, Deserialize)]
struct OpenAiAudioTranscribeResponse {
    #[serde(default)]
    text: Option<String>,
    #[serde(default)]
    transcript: Option<String>,
    #[serde(default)]
    usage: Option<OpenAiUsage>,
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

#[flutter_rust_bridge::frb]
pub fn audio_transcribe_byok_profile(
    app_dir: String,
    key: Vec<u8>,
    profile_id: String,
    local_day: String,
    lang: String,
    mime_type: String,
    audio_bytes: Vec<u8>,
) -> Result<String> {
    let key = key_from_bytes(key)?;
    if audio_bytes.is_empty() {
        return Err(anyhow!("audio_bytes is empty"));
    }
    let mime_type = mime_type.trim();
    if mime_type.is_empty() {
        return Err(anyhow!("mime_type is required"));
    }
    let profile_id = profile_id.trim();
    if profile_id.is_empty() {
        return Err(anyhow!("profile_id is required"));
    }

    let conn = db::open(Path::new(&app_dir))?;
    let profile = db::load_llm_profile_config_by_id(&conn, &key, profile_id)?
        .ok_or_else(|| anyhow!("llm profile not found: {profile_id}"))?;

    if profile.provider_type != "openai-compatible" {
        return Err(anyhow!(
            "audio transcribe byok v1 only supports provider_type=openai-compatible (got {})",
            profile.provider_type
        ));
    }

    let base_url = profile
        .base_url
        .ok_or_else(|| anyhow!("missing base_url for llm profile: {profile_id}"))?;
    let api_key = profile
        .api_key
        .ok_or_else(|| anyhow!("missing api_key for llm profile: {profile_id}"))?;
    let model_name = profile.model_name.trim().to_string();
    if model_name.is_empty() {
        return Err(anyhow!("missing model_name for llm profile: {profile_id}"));
    }

    let url = openai_audio_transcriptions_url(&base_url);
    let ext = file_ext_for_mime_type(mime_type);
    let file_part = multipart::Part::bytes(audio_bytes)
        .file_name(format!("audio.{ext}"))
        .mime_str(mime_type)?;
    let form = multipart::Form::new()
        .text("model", model_name)
        .text("response_format", "verbose_json")
        .text("language", lang.trim().to_string())
        .text("timestamp_granularities[]", "segment")
        .part("file", file_part);

    let client = Client::new();
    let response = client
        .post(url)
        .bearer_auth(api_key)
        .header("x-secondloop-purpose", "audio_transcribe")
        .multipart(form)
        .send()?;

    if !response.status().is_success() {
        let status = response.status();
        let body = response.text().unwrap_or_default();
        return Err(anyhow!(
            "openai-compatible audio transcribe request failed: HTTP {status} {body}"
        ));
    }

    let raw = response.text().unwrap_or_default();
    let mut json: Value =
        serde_json::from_str(&raw).map_err(|e| anyhow!("invalid transcribe json: {e}"))?;
    let parsed: OpenAiAudioTranscribeResponse = serde_json::from_value(json.clone())
        .map_err(|e| anyhow!("invalid transcribe response shape: {e}"))?;

    let text = parsed
        .text
        .or(parsed.transcript)
        .unwrap_or_default()
        .trim()
        .to_string();
    if text.is_empty() {
        return Err(anyhow!("audio transcribe response has empty text"));
    }
    if json.get("text").is_none() {
        json["text"] = Value::String(text);
    }

    let trimmed_day = local_day.trim();
    if !trimmed_day.is_empty() {
        let usage = parsed.usage.unwrap_or(OpenAiUsage {
            prompt_tokens: None,
            completion_tokens: None,
            total_tokens: None,
        });
        let _ = db::record_llm_usage_daily(
            &conn,
            trimmed_day,
            profile_id,
            "audio_transcribe",
            usage.prompt_tokens,
            usage.completion_tokens,
            usage.total_tokens,
        );
    }

    Ok(json.to_string())
}

#[flutter_rust_bridge::frb]
pub fn audio_transcribe_byok_profile_multimodal(
    app_dir: String,
    key: Vec<u8>,
    profile_id: String,
    local_day: String,
    lang: String,
    mime_type: String,
    audio_bytes: Vec<u8>,
) -> Result<String> {
    let key = key_from_bytes(key)?;
    if audio_bytes.is_empty() {
        return Err(anyhow!("audio_bytes is empty"));
    }
    let mime_type = mime_type.trim();
    if mime_type.is_empty() {
        return Err(anyhow!("mime_type is required"));
    }
    let profile_id = profile_id.trim();
    if profile_id.is_empty() {
        return Err(anyhow!("profile_id is required"));
    }

    let conn = db::open(Path::new(&app_dir))?;
    let profile = db::load_llm_profile_config_by_id(&conn, &key, profile_id)?
        .ok_or_else(|| anyhow!("llm profile not found: {profile_id}"))?;

    if profile.provider_type != "openai-compatible" {
        return Err(anyhow!(
            "audio transcribe byok multimodal only supports provider_type=openai-compatible (got {})",
            profile.provider_type
        ));
    }

    let base_url = profile
        .base_url
        .ok_or_else(|| anyhow!("missing base_url for llm profile: {profile_id}"))?;
    let api_key = profile
        .api_key
        .ok_or_else(|| anyhow!("missing api_key for llm profile: {profile_id}"))?;
    let model_name = profile.model_name.trim().to_string();
    if model_name.is_empty() {
        return Err(anyhow!("missing model_name for llm profile: {profile_id}"));
    }

    let payload = serde_json::json!({
        "model": model_name,
        "messages": [
            {
                "role": "user",
                "content": [
                    {
                        "type": "text",
                        "text": multimodal_transcribe_prompt(&lang),
                    },
                    {
                        "type": "input_audio",
                        "input_audio": {
                            "data": STANDARD.encode(&audio_bytes),
                            "format": audio_input_format_by_mime_type(mime_type),
                        }
                    }
                ]
            }
        ],
        "stream": false,
    });

    let client = Client::new();
    let response = client
        .post(openai_chat_completions_url(&base_url))
        .bearer_auth(api_key)
        .header("x-secondloop-purpose", "audio_transcribe")
        .json(&payload)
        .send()?;

    if !response.status().is_success() {
        let status = response.status();
        let body = response.text().unwrap_or_default();
        return Err(anyhow!(
            "openai-compatible audio transcribe multimodal request failed: HTTP {status} {body}"
        ));
    }

    let raw = response.text().unwrap_or_default();
    let mut json: Value =
        serde_json::from_str(&raw).map_err(|e| anyhow!("invalid transcribe json: {e}"))?;

    let text = extract_transcript_text(&json).trim().to_string();
    if text.is_empty() {
        return Err(anyhow!("audio transcribe response has empty text"));
    }
    if json.get("text").is_none() {
        json["text"] = Value::String(text);
    }

    let trimmed_day = local_day.trim();
    if !trimmed_day.is_empty() {
        let usage = json
            .get("usage")
            .cloned()
            .and_then(|raw| serde_json::from_value::<OpenAiUsage>(raw).ok())
            .unwrap_or(OpenAiUsage {
                prompt_tokens: None,
                completion_tokens: None,
                total_tokens: None,
            });
        let _ = db::record_llm_usage_daily(
            &conn,
            trimmed_day,
            profile_id,
            "audio_transcribe",
            usage.prompt_tokens,
            usage.completion_tokens,
            usage.total_tokens,
        );
    }

    Ok(json.to_string())
}
