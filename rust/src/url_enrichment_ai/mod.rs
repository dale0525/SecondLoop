use anyhow::{anyhow, Result};
use serde_json::{Map, Value};

use crate::llm::ChatDelta;
use crate::rag::AnswerProvider;

const MAX_PROMPT_SOURCE_CHARS: usize = 6000;
const MAX_TAGS: usize = 6;

fn build_url_enrichment_prompt(
    original_url: &str,
    final_url: &str,
    site: &str,
    title: Option<&str>,
    readable_text_excerpt: &str,
    readable_text_full: &str,
) -> String {
    let safe_title = title
        .map(str::trim)
        .filter(|value| !value.is_empty())
        .unwrap_or("(none)");
    let source = if readable_text_excerpt.trim().is_empty() {
        readable_text_full
    } else {
        readable_text_excerpt
    };

    let clipped_source: String = source.chars().take(MAX_PROMPT_SOURCE_CHARS).collect();

    format!(
        r#"You are enriching shared URL content for a note-taking app.
Return ONLY a JSON object with this schema:
{{
  "title": string,
  "summary": string,
  "tags": string[]
}}
Rules:
- "title" should be concise and accurate.
- "summary" should be 2-4 sentences, no markdown.
- "tags" should contain 0-6 short topical tags.
- Do not include any additional keys.

original_url: {}
final_url: {}
site: {}
current_title: {}
extracted_text:
{}"#,
        original_url.trim(),
        final_url.trim(),
        site.trim(),
        safe_title,
        clipped_source
    )
}

fn extract_first_json_object(raw: &str) -> Result<Value> {
    let start = raw
        .find('{')
        .ok_or_else(|| anyhow!("no json object found"))?;

    let mut depth: i32 = 0;
    let mut in_string = false;
    let mut escaped = false;

    for (index, ch) in raw[start..].char_indices() {
        if in_string {
            if escaped {
                escaped = false;
                continue;
            }
            if ch == '\\' {
                escaped = true;
                continue;
            }
            if ch == '"' {
                in_string = false;
            }
            continue;
        }

        if ch == '"' {
            in_string = true;
            continue;
        }

        if ch == '{' {
            depth += 1;
            continue;
        }

        if ch != '}' {
            continue;
        }

        depth -= 1;
        if depth != 0 {
            continue;
        }

        let end = start + index + 1;
        let snippet = raw
            .get(start..end)
            .ok_or_else(|| anyhow!("failed to slice json object"))?;
        let parsed: Value = serde_json::from_str(snippet)?;
        return Ok(parsed);
    }

    Err(anyhow!("unterminated json object"))
}

fn read_optional_trimmed_string(map: &Map<String, Value>, key: &str) -> Option<String> {
    map.get(key)
        .and_then(Value::as_str)
        .map(str::trim)
        .filter(|value| !value.is_empty())
        .map(ToString::to_string)
}

fn push_unique_tag(tags: &mut Vec<String>, candidate: &str) {
    let normalized = candidate.trim();
    if normalized.is_empty() {
        return;
    }
    if tags
        .iter()
        .any(|existing| existing.eq_ignore_ascii_case(normalized))
    {
        return;
    }
    if tags.len() >= MAX_TAGS {
        return;
    }
    tags.push(normalized.to_string());
}

fn collect_tags(value: Option<&Value>) -> Vec<String> {
    let mut out = Vec::<String>::new();
    let Some(raw) = value else {
        return out;
    };

    match raw {
        Value::String(single) => push_unique_tag(&mut out, single),
        Value::Array(values) => {
            for value in values {
                if let Some(tag) = value.as_str() {
                    push_unique_tag(&mut out, tag);
                }
            }
        }
        _ => {}
    }

    out
}

fn normalize_url_enrichment_payload(payload: Value) -> Result<Value> {
    let map = match payload {
        Value::Object(map) => map,
        _ => return Err(anyhow!("url enrichment json must be object")),
    };

    let title = read_optional_trimmed_string(&map, "title").unwrap_or_default();
    let summary = read_optional_trimmed_string(&map, "summary").unwrap_or_default();
    let tags = {
        let from_tags = collect_tags(map.get("tags"));
        if from_tags.is_empty() {
            collect_tags(map.get("tag"))
        } else {
            from_tags
        }
    };

    Ok(serde_json::json!({
        "title": title,
        "summary": summary,
        "tags": tags,
    }))
}

pub fn enrich_url_content_json(
    provider: &dyn AnswerProvider,
    original_url: &str,
    final_url: &str,
    site: &str,
    title: Option<&str>,
    readable_text_excerpt: &str,
    readable_text_full: &str,
) -> Result<String> {
    let prompt = build_url_enrichment_prompt(
        original_url,
        final_url,
        site,
        title,
        readable_text_excerpt,
        readable_text_full,
    );

    let mut raw_output = String::new();
    provider.stream_answer(&prompt, &mut |ev: ChatDelta| {
        raw_output.push_str(&ev.text_delta);
        Ok(())
    })?;

    let json = extract_first_json_object(&raw_output)?;
    let normalized = normalize_url_enrichment_payload(json)?;
    serde_json::to_string(&normalized).map_err(Into::into)
}

#[cfg(test)]
mod tests {
    use super::*;

    struct FakeProvider {
        response: String,
    }

    impl AnswerProvider for FakeProvider {
        fn stream_answer(
            &self,
            _prompt: &str,
            on_event: &mut dyn FnMut(ChatDelta) -> Result<()>,
        ) -> Result<()> {
            on_event(ChatDelta {
                role: Some("assistant".to_string()),
                text_delta: self.response.clone(),
                done: true,
            })?;
            Ok(())
        }
    }

    #[test]
    fn prompt_uses_excerpt_and_clips_length() {
        let long_text = "A".repeat(MAX_PROMPT_SOURCE_CHARS + 100);
        let prompt = build_url_enrichment_prompt(
            "https://a",
            "https://b",
            "example.com",
            Some("Title"),
            &long_text,
            "",
        );
        assert!(prompt.contains("original_url: https://a"));
        assert!(prompt.contains("current_title: Title"));
        assert!(!prompt.contains(&"A".repeat(MAX_PROMPT_SOURCE_CHARS + 50)));
    }

    #[test]
    fn normalize_payload_dedup_tags_and_fallback_tag_key() {
        let normalized = normalize_url_enrichment_payload(serde_json::json!({
            "title": "  Example  ",
            "summary": "  Summary  ",
            "tag": ["ai", "AI", "speech"],
        }))
        .expect("normalize payload");

        assert_eq!(normalized["title"], "Example");
        assert_eq!(normalized["summary"], "Summary");
        let tags = normalized["tags"].as_array().expect("tags array");
        assert_eq!(tags.len(), 2);
        assert_eq!(tags[0], "ai");
        assert_eq!(tags[1], "speech");
    }

    #[test]
    fn enrich_extracts_first_json_object_from_fenced_output() {
        let provider = FakeProvider {
            response: "```json\n{\"title\":\"A\",\"summary\":\"B\",\"tags\":[\"c\"]}\n```"
                .to_string(),
        };
        let out = enrich_url_content_json(
            &provider,
            "https://o",
            "https://f",
            "example.com",
            None,
            "excerpt",
            "full",
        )
        .expect("enrich");

        let parsed: Value = serde_json::from_str(&out).expect("json");
        assert_eq!(parsed["title"], "A");
        assert_eq!(parsed["summary"], "B");
        assert_eq!(parsed["tags"], serde_json::json!(["c"]));
    }
}
