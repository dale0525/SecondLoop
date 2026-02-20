use std::path::Path;

use anyhow::{anyhow, Result};
use base64::{engine::general_purpose::STANDARD, Engine as _};
use reqwest::blocking::{multipart, Client};
use reqwest::header;
use serde::{Deserialize, Serialize};
use serde_json::Value;

use crate::db;

mod local_whisper_runtime;
use local_whisper_runtime::create_local_whisper_context;

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

fn is_auto_transcribe_lang(lang: &str) -> bool {
    let trimmed = lang.trim();
    trimmed.is_empty()
        || trimmed.eq_ignore_ascii_case("auto")
        || trimmed.eq_ignore_ascii_case("und")
        || trimmed.eq_ignore_ascii_case("unknown")
}

fn multimodal_transcribe_prompt(lang: &str) -> String {
    let trimmed = lang.trim();
    if is_auto_transcribe_lang(trimmed) {
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

fn extract_chat_stream_delta_text(value: &Value) -> String {
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

fn parse_sse_data_events(raw: &str) -> Vec<String> {
    let mut data_lines: Vec<String> = Vec::new();
    let mut events: Vec<String> = Vec::new();

    let mut flush_event = |lines: &mut Vec<String>| {
        if lines.is_empty() {
            return;
        }
        let payload = lines.join("\n");
        lines.clear();
        events.push(payload);
    };

    for line in raw.lines() {
        let line = line.trim_end_matches('\r');
        if line.is_empty() {
            flush_event(&mut data_lines);
            continue;
        }
        if let Some(rest) = line.strip_prefix("data:") {
            data_lines.push(rest.trim().to_string());
        }
    }
    flush_event(&mut data_lines);
    events
}

fn parse_usage_value(value: &Value) -> Option<OpenAiUsage> {
    let parsed: OpenAiUsage = serde_json::from_value(value.clone()).ok()?;
    if parsed.prompt_tokens.is_none()
        && parsed.completion_tokens.is_none()
        && parsed.total_tokens.is_none()
    {
        return None;
    }
    Some(parsed)
}

fn parse_chat_transcribe_sse_payload(raw: &str) -> Result<(String, Option<OpenAiUsage>)> {
    let mut transcript = String::new();
    let mut usage: Option<OpenAiUsage> = None;

    for payload in parse_sse_data_events(raw) {
        let trimmed = payload.trim();
        if trimmed.is_empty() || trimmed == "[DONE]" {
            continue;
        }
        let value: Value = match serde_json::from_str(trimmed) {
            Ok(v) => v,
            Err(_) => continue,
        };

        if let Some(raw_usage) = value.get("usage") {
            if let Some(parsed) = parse_usage_value(raw_usage) {
                usage = Some(parsed);
            }
        }

        let delta = extract_chat_stream_delta_text(&value);
        if !delta.is_empty() {
            transcript.push_str(&delta);
        }
    }

    let normalized = normalize_transcript_text(&transcript);
    if normalized.is_empty() {
        return Err(anyhow!("audio transcribe response has empty text"));
    }
    Ok((normalized, usage))
}

fn parse_whisper_sse_payload(raw: &str) -> Result<Value> {
    let mut usage: Option<OpenAiUsage> = None;
    let mut delta_text = String::new();
    let mut last_payload_map: Option<serde_json::Map<String, Value>> = None;

    for payload in parse_sse_data_events(raw) {
        let trimmed = payload.trim();
        if trimmed.is_empty() || trimmed == "[DONE]" {
            continue;
        }
        let value: Value = match serde_json::from_str(trimmed) {
            Ok(v) => v,
            Err(_) => continue,
        };

        if let Some(raw_usage) = value.get("usage") {
            if let Some(parsed) = parse_usage_value(raw_usage) {
                usage = Some(parsed);
            }
        }

        let event_text = value
            .get("text")
            .or_else(|| value.get("transcript"))
            .and_then(Value::as_str)
            .map(str::to_string)
            .or_else(|| {
                let out = extract_chat_stream_delta_text(&value);
                if out.is_empty() {
                    None
                } else {
                    Some(out)
                }
            })
            .unwrap_or_default();
        if !event_text.is_empty() {
            delta_text.push_str(&event_text);
        }

        if let Value::Object(map) = value {
            last_payload_map = Some(map);
        }
    }

    let mut output = last_payload_map.unwrap_or_default();
    if !delta_text.trim().is_empty() && output.get("text").is_none() {
        output.insert(
            "text".to_string(),
            Value::String(normalize_transcript_text(&delta_text)),
        );
    }

    if output
        .get("text")
        .and_then(Value::as_str)
        .unwrap_or_default()
        .trim()
        .is_empty()
        && output
            .get("transcript")
            .and_then(Value::as_str)
            .unwrap_or_default()
            .trim()
            .is_empty()
    {
        return Err(anyhow!("audio transcribe response has empty text"));
    }

    if output.get("usage").is_none() {
        if let Some(parsed_usage) = usage {
            output.insert("usage".to_string(), serde_json::to_value(parsed_usage)?);
        }
    }

    Ok(Value::Object(output))
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

fn normalize_local_whisper_model_name(model_name: &str) -> &'static str {
    match model_name.trim().to_ascii_lowercase().as_str() {
        "tiny" => "tiny",
        "base" => "base",
        "small" => "small",
        "medium" => "medium",
        "large-v3" => "large-v3",
        "large-v3-turbo" => "large-v3-turbo",
        _ => "base",
    }
}

fn local_whisper_model_filename(model_name: &str) -> &'static str {
    match model_name {
        "tiny" => "ggml-tiny.bin",
        "base" => "ggml-base.bin",
        "small" => "ggml-small.bin",
        "medium" => "ggml-medium.bin",
        "large-v3" => "ggml-large-v3.bin",
        "large-v3-turbo" => "ggml-large-v3-turbo.bin",
        _ => "ggml-base.bin",
    }
}

fn resolve_local_whisper_model_path(
    app_dir: &str,
    model_name: &str,
) -> Result<(String, std::path::PathBuf)> {
    let normalized_model = normalize_local_whisper_model_name(model_name).to_string();
    let runtime_whisper_dir = Path::new(app_dir)
        .join("ocr")
        .join("desktop")
        .join("runtime")
        .join("whisper");

    let preferred = runtime_whisper_dir.join(local_whisper_model_filename(&normalized_model));
    if preferred.is_file() {
        return Ok((normalized_model, preferred));
    }

    if normalized_model != "base" {
        let fallback = runtime_whisper_dir.join(local_whisper_model_filename("base"));
        if fallback.is_file() {
            return Ok(("base".to_string(), fallback));
        }
    }

    Err(anyhow!(
        "audio_transcribe_local_runtime_model_missing:{}",
        normalized_model
    ))
}

fn normalize_local_whisper_lang(lang: &str) -> Option<String> {
    if is_auto_transcribe_lang(lang) {
        return None;
    }

    let normalized = lang.trim().replace('_', "-").to_ascii_lowercase();
    let primary = normalized.split('-').next().unwrap_or("").trim();
    if primary.is_empty() {
        None
    } else {
        Some(primary.to_string())
    }
}

fn decode_local_whisper_wav_bytes(wav_bytes: &[u8]) -> Result<Vec<f32>> {
    if wav_bytes.is_empty() {
        return Err(anyhow!("audio_transcribe_local_runtime_wav_empty"));
    }

    let mut reader = hound::WavReader::new(std::io::Cursor::new(wav_bytes))
        .map_err(|e| anyhow!("audio_transcribe_local_runtime_wav_invalid:{e}"))?;
    let spec = reader.spec();

    if spec.channels != 1 {
        return Err(anyhow!(
            "audio_transcribe_local_runtime_wav_channels:{}",
            spec.channels
        ));
    }
    if spec.sample_rate != 16_000 {
        return Err(anyhow!(
            "audio_transcribe_local_runtime_wav_sample_rate:{}",
            spec.sample_rate
        ));
    }

    let samples = match (spec.sample_format, spec.bits_per_sample) {
        (hound::SampleFormat::Int, 16) => {
            let pcm_i16 = reader
                .samples::<i16>()
                .collect::<std::result::Result<Vec<_>, _>>()
                .map_err(|e| anyhow!("audio_transcribe_local_runtime_wav_read_failed:{e}"))?;
            let mut pcm_f32 = vec![0.0f32; pcm_i16.len()];
            whisper_rs::convert_integer_to_float_audio(&pcm_i16, &mut pcm_f32)
                .map_err(|e| anyhow!("audio_transcribe_local_runtime_wav_convert_failed:{e}"))?;
            pcm_f32
        }
        (hound::SampleFormat::Float, 32) => reader
            .samples::<f32>()
            .collect::<std::result::Result<Vec<_>, _>>()
            .map_err(|e| anyhow!("audio_transcribe_local_runtime_wav_read_failed:{e}"))?,
        _ => {
            return Err(anyhow!(
                "audio_transcribe_local_runtime_wav_unsupported_format:{}:{}",
                spec.bits_per_sample,
                match spec.sample_format {
                    hound::SampleFormat::Int => "int",
                    hound::SampleFormat::Float => "float",
                }
            ))
        }
    };

    if samples.is_empty() {
        return Err(anyhow!("audio_transcribe_local_runtime_wav_empty"));
    }

    Ok(samples)
}

#[flutter_rust_bridge::frb]
pub fn audio_transcribe_local_whisper(
    app_dir: String,
    model_name: String,
    lang: String,
    wav_bytes: Vec<u8>,
) -> Result<String> {
    let app_dir = app_dir.trim();
    if app_dir.is_empty() {
        return Err(anyhow!("app_dir is required"));
    }

    let (resolved_model_name, model_path) = resolve_local_whisper_model_path(app_dir, &model_name)?;
    let model_path_string = model_path
        .to_str()
        .ok_or_else(|| anyhow!("audio_transcribe_local_runtime_model_path_invalid"))?
        .to_string();

    let pcm_f32 = decode_local_whisper_wav_bytes(&wav_bytes)?;

    let context = create_local_whisper_context(&model_path_string)?;
    let mut state = context
        .create_state()
        .map_err(|e| anyhow!("audio_transcribe_local_runtime_create_state_failed:{e}"))?;

    let thread_count = std::thread::available_parallelism()
        .map(|v| v.get())
        .unwrap_or(2)
        .clamp(1, 8) as i32;

    let normalized_lang = normalize_local_whisper_lang(&lang);
    let mut params =
        whisper_rs::FullParams::new(whisper_rs::SamplingStrategy::Greedy { best_of: 1 });
    params.set_n_threads(thread_count);
    params.set_translate(false);
    params.set_print_special(false);
    params.set_print_progress(false);
    params.set_print_realtime(false);
    params.set_print_timestamps(false);
    if let Some(lang_code) = normalized_lang.as_deref() {
        params.set_language(Some(lang_code));
    } else {
        params.set_language(None);
    }

    state
        .full(params, &pcm_f32)
        .map_err(|e| anyhow!("audio_transcribe_local_runtime_infer_failed:{e}"))?;

    let mut transcript_parts = Vec::new();
    let mut segments = Vec::new();
    let mut duration_ms: i64 = 0;

    for segment in state.as_iter() {
        let text = segment
            .to_str_lossy()
            .map_err(|e| anyhow!("audio_transcribe_local_runtime_segment_decode_failed:{e}"))?
            .trim()
            .to_string();
        if text.is_empty() {
            continue;
        }

        let start_ms = (segment.start_timestamp() * 10).max(0);
        let end_ms = (segment.end_timestamp() * 10).max(start_ms);
        duration_ms = duration_ms.max(end_ms);

        transcript_parts.push(text.clone());
        segments.push(serde_json::json!({
            "t_ms": start_ms,
            "text": text,
        }));
    }

    let transcript = transcript_parts.join(" ").trim().to_string();
    if transcript.is_empty() {
        return Err(anyhow!("audio_transcribe_local_runtime_empty"));
    }

    let mut payload = serde_json::Map::new();
    payload.insert("text".to_string(), Value::String(transcript));
    payload.insert(
        "duration".to_string(),
        Value::from(duration_ms as f64 / 1000.0),
    );
    payload.insert("segments".to_string(), Value::Array(segments));
    payload.insert("model".to_string(), Value::String(resolved_model_name));
    if let Some(lang_code) = normalized_lang {
        payload.insert("language".to_string(), Value::String(lang_code));
    }

    Ok(Value::Object(payload).to_string())
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

#[derive(Debug, Deserialize, Serialize)]
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
    let audio_bytes_len = audio_bytes.len();
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
    let mut form = multipart::Form::new()
        .text("model", model_name)
        .text("response_format", "verbose_json")
        .text("timestamp_granularities[]", "segment")
        .text("stream", "true")
        .part("file", file_part);
    if !is_auto_transcribe_lang(&lang) {
        form = form.text("language", lang.trim().to_string());
    }

    let request_timeout =
        crate::llm::timeouts::audio_transcribe_timeout_for_audio_bytes(audio_bytes_len, false);

    let client = Client::new();
    let response = client
        .post(url)
        .bearer_auth(api_key)
        .header("x-secondloop-purpose", "audio_transcribe")
        .header(header::ACCEPT, "text/event-stream")
        .multipart(form)
        .timeout(request_timeout)
        .send()?;

    if !response.status().is_success() {
        let status = response.status();
        let body = response.text().unwrap_or_default();
        return Err(anyhow!(
            "openai-compatible audio transcribe request failed: HTTP {status} {body}"
        ));
    }

    let content_type = response
        .headers()
        .get(header::CONTENT_TYPE)
        .and_then(|v| v.to_str().ok())
        .unwrap_or_default()
        .to_ascii_lowercase();

    let raw = response.text().unwrap_or_default();
    let mut json: Value = if content_type.contains("text/event-stream") {
        parse_whisper_sse_payload(&raw)?
    } else {
        serde_json::from_str(&raw).map_err(|e| anyhow!("invalid transcribe json: {e}"))?
    };
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
    let audio_bytes_len = audio_bytes.len();
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
        "stream": true,
        "stream_options": {
            "include_usage": true,
        },
    });

    let request_timeout =
        crate::llm::timeouts::audio_transcribe_timeout_for_audio_bytes(audio_bytes_len, true);

    let client = Client::new();
    let response = client
        .post(openai_chat_completions_url(&base_url))
        .bearer_auth(api_key)
        .header("x-secondloop-purpose", "audio_transcribe")
        .header(header::ACCEPT, "text/event-stream")
        .json(&payload)
        .timeout(request_timeout)
        .send()?;

    if !response.status().is_success() {
        let status = response.status();
        let body = response.text().unwrap_or_default();
        return Err(anyhow!(
            "openai-compatible audio transcribe multimodal request failed: HTTP {status} {body}"
        ));
    }

    let content_type = response
        .headers()
        .get(header::CONTENT_TYPE)
        .and_then(|v| v.to_str().ok())
        .unwrap_or_default()
        .to_ascii_lowercase();

    let raw = response.text().unwrap_or_default();
    let mut json: Value = if content_type.contains("text/event-stream") {
        let (text, usage) = parse_chat_transcribe_sse_payload(&raw)?;
        let mut obj = serde_json::Map::new();
        obj.insert("text".to_string(), Value::String(text));
        if let Some(parsed_usage) = usage {
            obj.insert("usage".to_string(), serde_json::to_value(parsed_usage)?);
        }
        Value::Object(obj)
    } else {
        serde_json::from_str(&raw).map_err(|e| anyhow!("invalid transcribe json: {e}"))?
    };

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

#[cfg(test)]
mod tests {
    use super::{normalize_local_whisper_lang, normalize_local_whisper_model_name};

    #[test]
    fn normalize_local_whisper_model_name_uses_supported_values() {
        assert_eq!(normalize_local_whisper_model_name("base"), "base");
        assert_eq!(normalize_local_whisper_model_name("SMALL"), "small");
        assert_eq!(
            normalize_local_whisper_model_name("large-v3-turbo"),
            "large-v3-turbo"
        );
        assert_eq!(normalize_local_whisper_model_name("unknown"), "base");
    }

    #[test]
    fn normalize_local_whisper_lang_reduces_to_primary_tag() {
        assert_eq!(
            normalize_local_whisper_lang("zh-CN"),
            Some("zh".to_string())
        );
        assert_eq!(
            normalize_local_whisper_lang("en_US"),
            Some("en".to_string())
        );
        assert_eq!(normalize_local_whisper_lang("auto"), None);
        assert_eq!(normalize_local_whisper_lang(""), None);
    }
}
