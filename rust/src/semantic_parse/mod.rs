use anyhow::{anyhow, Result};
use serde_json::Value;

use crate::llm::ChatDelta;
use crate::rag::AnswerProvider;

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct TodoCandidate {
    pub id: String,
    pub title: String,
    pub status: String,
    pub due_local_iso: Option<String>,
}

fn extract_first_json_value(raw: &str) -> Result<Value> {
    let start = raw
        .find('{')
        .ok_or_else(|| anyhow!("no json object found"))?;

    let mut depth: i32 = 0;
    let mut in_string = false;
    let mut escaped = false;

    for (i, ch) in raw[start..].char_indices() {
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

        let end = start + i + 1;
        let snippet = raw
            .get(start..end)
            .ok_or_else(|| anyhow!("failed to slice json object"))?;
        let value: Value = serde_json::from_str(snippet)?;
        return Ok(value);
    }

    Err(anyhow!("unterminated json object"))
}

fn build_message_action_prompt(
    text: &str,
    now_local_iso: &str,
    locale: &str,
    day_end_minutes: i32,
    candidates: &[TodoCandidate],
    available_tags: &[String],
) -> String {
    let mut out = String::new();
    out.push_str("You are a strict JSON generator.\n");
    out.push_str("Output ONLY JSON. No markdown. No code fences. No extra text.\n\n");

    out.push_str("Task: classify the user message as one of:\n");
    out.push_str("- followup: updating an existing todo from the candidate list\n");
    out.push_str("- create: creating a new todo\n");
    out.push_str("- none: neither\n\n");

    out.push_str("Return this exact JSON schema:\n");
    out.push_str("{\n");
    out.push_str("  \"kind\": \"none\" | \"followup\" | \"create\",\n");
    out.push_str("  \"confidence\": number, // 0..1\n");
    out.push_str("  \"todo_id\": string, // only when kind=followup\n");
    out.push_str("  \"new_status\": \"in_progress\" | \"done\" | \"dismissed\" | null, // only when kind=followup\n");
    out.push_str(
        "  \"due_local_iso\": string | null, // optional for kind=followup or kind=create\n",
    );
    out.push_str("  \"title\": string, // only when kind=create\n");
    out.push_str("  \"status\": \"open\" | \"inbox\", // only when kind=create\n");
    out.push_str("  \"task_type\": \"execution\" | \"research\" | \"comparison\" | \"live_info_lookup\" | \"reference_collection\" | \"coordination\" | \"planning\" | \"unknown\", // use a fixed enum; for non-create use unknown\n");
    out.push_str("  \"recurrence\": { // only when kind=create\n");
    out.push_str("    \"freq\": \"daily\" | \"weekly\" | \"monthly\" | \"yearly\",\n");
    out.push_str("    \"interval\": number // >=1\n");
    out.push_str("  } | null,\n");
    out.push_str("  \"suggested_tags\": string[], // 0..3 normalized tags for this message\n");
    out.push_str("  \"tag_confidence\": number // 0..1 confidence for suggested_tags\n");
    out.push_str("}\n\n");

    append_message_action_common_constraints(&mut out, available_tags);

    out.push_str(&format!("now_local_iso: {now_local_iso}\n"));
    out.push_str(&format!("locale: {locale}\n"));
    out.push_str(&format!("day_end_minutes: {day_end_minutes}\n\n"));

    out.push_str("todo_candidates:\n");
    if candidates.is_empty() {
        out.push_str("- (none)\n");
    } else {
        for c in candidates {
            out.push_str(&format!(
                "- id={id} title={title} status={status}",
                id = c.id,
                title = c.title,
                status = c.status
            ));
            if let Some(due) = &c.due_local_iso {
                if !due.trim().is_empty() {
                    out.push_str(&format!(" due_local_iso={due}"));
                }
            }
            out.push('\n');
        }
    }

    out.push_str("\nuser_message:\n");
    out.push_str(text.trim());
    out.push('\n');

    out
}

fn build_message_action_enhancement_prompt(
    text: &str,
    now_local_iso: &str,
    locale: &str,
    day_end_minutes: i32,
    local_result_json: &str,
    unresolved_fields: &[String],
    candidates: &[TodoCandidate],
    available_tags: &[String],
) -> String {
    let mut out = String::new();
    out.push_str("You are a strict JSON generator.\n");
    out.push_str("Output ONLY JSON. No markdown. No code fences. No extra text.\n\n");

    out.push_str("Task: enhance a local-first semantic parse result.\n");
    out.push_str(
        "Do not ignore the local_result. Keep it unless the user message clearly requires a correction.\n",
    );
    out.push_str(
        "Use unresolved_fields to decide what still needs disambiguation or completion.\n\n",
    );

    out.push_str("Return this exact JSON schema:\n");
    out.push_str("{\n");
    out.push_str("  \"kind\": \"none\" | \"followup\" | \"create\",\n");
    out.push_str("  \"confidence\": number, // 0..1\n");
    out.push_str("  \"todo_id\": string, // only when kind=followup\n");
    out.push_str("  \"new_status\": \"in_progress\" | \"done\" | \"dismissed\" | null, // only when kind=followup\n");
    out.push_str(
        "  \"due_local_iso\": string | null, // optional for kind=followup or kind=create\n",
    );
    out.push_str("  \"title\": string, // only when kind=create\n");
    out.push_str("  \"status\": \"open\" | \"inbox\", // only when kind=create\n");
    out.push_str("  \"task_type\": \"execution\" | \"research\" | \"comparison\" | \"live_info_lookup\" | \"reference_collection\" | \"coordination\" | \"planning\" | \"unknown\", // use a fixed enum; for non-create use unknown\n");
    out.push_str("  \"recurrence\": {\n");
    out.push_str("    \"freq\": \"daily\" | \"weekly\" | \"monthly\" | \"yearly\",\n");
    out.push_str("    \"interval\": number // >=1\n");
    out.push_str("  } | null,\n");
    out.push_str("  \"suggested_tags\": string[], // 0..3 normalized tags for this message\n");
    out.push_str("  \"tag_confidence\": number // 0..1 confidence for suggested_tags\n");
    out.push_str("}\n\n");

    out.push_str("Constraints:\n");
    out.push_str("- If kind=create, preserve the local result unless the message clearly indicates otherwise.\n");
    out.push_str("- If still unsure after considering local_result, use kind=none.\n");
    append_message_action_common_constraints(&mut out, available_tags);

    out.push_str(&format!("now_local_iso: {now_local_iso}\n"));
    out.push_str(&format!("locale: {locale}\n"));
    out.push_str(&format!("day_end_minutes: {day_end_minutes}\n\n"));
    out.push_str("local_result:\n");
    out.push_str(local_result_json.trim());
    out.push('\n');
    out.push_str("unresolved_fields:\n");
    out.push_str(&serde_json::to_string(unresolved_fields).expect("serialize unresolved_fields"));
    out.push_str("\n\n");

    out.push_str("todo_candidates:\n");
    if candidates.is_empty() {
        out.push_str("- (none)\n");
    } else {
        for c in candidates {
            out.push_str(&format!(
                "- id={id} title={title} status={status}",
                id = c.id,
                title = c.title,
                status = c.status
            ));
            if let Some(due) = &c.due_local_iso {
                if !due.trim().is_empty() {
                    out.push_str(&format!(" due_local_iso={due}"));
                }
            }
            out.push('\n');
        }
    }

    out.push_str("\nuser_message:\n");
    out.push_str(text.trim());
    out.push('\n');

    out
}

fn append_message_action_common_constraints(out: &mut String, available_tags: &[String]) {
    out.push_str("- If kind=followup, todo_id MUST be one of the candidate IDs.\n");
    out.push_str(
        "- Use kind=followup ONLY when the user clearly refers to a specific candidate.\n",
    );
    out.push_str(
        "- If kind=followup, at least one of new_status or due_local_iso MUST be non-null.\n",
    );
    out.push_str(
        "- If the message describes a new task, use kind=create even if no candidates match.\n",
    );
    out.push_str("- If unsure, use kind=none.\n");
    out.push_str(
        "- due_local_iso must be local ISO 8601 without timezone, like 2026-02-04T15:00:00.\n",
    );
    out.push_str("- If the user provides a date but no time, use day_end_minutes.\n");
    out.push_str("- The user message may be in any language; infer intent from that language.\n");
    out.push_str("- recurrence is optional. If absent, set recurrence to null.\n");
    out.push_str(
        "- recurrence.freq MUST use the canonical enum values: daily|weekly|monthly|yearly.\n",
    );
    out.push_str("- recurrence.interval defaults to 1 when omitted by user intent.\n");
    out.push_str(
        "- status/new_status MUST use canonical enum values even if user text is non-English.\n",
    );
    out.push_str("- task_type MUST use the fixed enum values above; never invent new values.\n");
    out.push_str("- suggested_tags MUST contain at most 3 concise tags.\n");
    if available_tags.is_empty() {
        out.push_str(
            "- Prefer these canonical tags when relevant: work|personal|family|health|finance|study|travel|social|home|hobby.\n",
        );
    } else {
        out.push_str("- Prefer tags from available_tags when relevant.\n");
        out.push_str(
            "- Only suggest tags from available_tags; if none fit, return suggested_tags as [].\n",
        );
        out.push_str(&format!(
            "available_tags: {}\n",
            serde_json::to_string(available_tags).expect("serialize available_tags")
        ));
    }
    out.push_str(
        "- If no useful tag is inferred, return suggested_tags as [] and tag_confidence as 0.\n\n",
    );
}

pub fn semantic_parse_message_action_json(
    provider: &dyn AnswerProvider,
    text: &str,
    now_local_iso: &str,
    locale: &str,
    day_end_minutes: i32,
    candidates: &[TodoCandidate],
    available_tags: &[String],
) -> Result<String> {
    let prompt = build_message_action_prompt(
        text,
        now_local_iso,
        locale,
        day_end_minutes,
        candidates,
        available_tags,
    );
    let mut out = String::new();
    provider.stream_answer(&prompt, &mut |ev: ChatDelta| {
        out.push_str(&ev.text_delta);
        Ok(())
    })?;
    let value = extract_first_json_value(&out)?;
    Ok(serde_json::to_string(&value)?)
}

pub fn semantic_parse_message_action_enhancement_json(
    provider: &dyn AnswerProvider,
    text: &str,
    now_local_iso: &str,
    locale: &str,
    day_end_minutes: i32,
    local_result_json: &str,
    unresolved_fields: &[String],
    candidates: &[TodoCandidate],
    available_tags: &[String],
) -> Result<String> {
    let prompt = build_message_action_enhancement_prompt(
        text,
        now_local_iso,
        locale,
        day_end_minutes,
        local_result_json,
        unresolved_fields,
        candidates,
        available_tags,
    );
    let mut out = String::new();
    provider.stream_answer(&prompt, &mut |ev: ChatDelta| {
        out.push_str(&ev.text_delta);
        Ok(())
    })?;
    let value = extract_first_json_value(&out)?;
    Ok(serde_json::to_string(&value)?)
}

fn build_ask_ai_time_window_prompt(
    question: &str,
    now_local_iso: &str,
    locale: &str,
    first_day_of_week_index: i32,
) -> String {
    let mut out = String::new();
    out.push_str("You are a strict JSON generator.\n");
    out.push_str("Output ONLY JSON. No markdown. No code fences. No extra text.\n\n");

    out.push_str("Task: infer whether the user's question implies a time window.\n");
    out.push_str("If yes, return a local time window [start,end) (end is exclusive).\n\n");

    out.push_str("Return this exact JSON schema:\n");
    out.push_str("{\n");
    out.push_str("  \"kind\": \"none\" | \"past\" | \"future\" | \"both\",\n");
    out.push_str("  \"confidence\": number, // 0..1\n");
    out.push_str("  \"start_local_iso\": string | null,\n");
    out.push_str("  \"end_local_iso\": string | null\n");
    out.push_str("}\n\n");

    out.push_str("Constraints:\n");
    out.push_str("- start_local_iso and end_local_iso MUST be local ISO 8601 without timezone, like 2026-02-04T00:00:00.\n");
    out.push_str("- Use midnight boundaries for date-based ranges.\n");
    out.push_str("- end_local_iso MUST be strictly after start_local_iso.\n");
    out.push_str(
        "- If no time window is implied, kind=none and both *_local_iso must be null.\n\n",
    );

    out.push_str(&format!("now_local_iso: {now_local_iso}\n"));
    out.push_str(&format!("locale: {locale}\n"));
    out.push_str(&format!(
        "first_day_of_week_index: {first_day_of_week_index}\n\n"
    ));

    out.push_str("user_question:\n");
    out.push_str(question.trim());
    out.push('\n');

    out
}

pub fn semantic_parse_ask_ai_time_window_json(
    provider: &dyn AnswerProvider,
    question: &str,
    now_local_iso: &str,
    locale: &str,
    first_day_of_week_index: i32,
) -> Result<String> {
    let prompt =
        build_ask_ai_time_window_prompt(question, now_local_iso, locale, first_day_of_week_index);
    let mut out = String::new();
    provider.stream_answer(&prompt, &mut |ev: ChatDelta| {
        out.push_str(&ev.text_delta);
        Ok(())
    })?;
    let value = extract_first_json_value(&out)?;
    Ok(serde_json::to_string(&value)?)
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
            on_event(ChatDelta {
                role: None,
                text_delta: String::new(),
                done: true,
            })?;
            Ok(())
        }
    }

    #[test]
    fn extract_json_handles_markdown_code_fence() {
        let raw = r#"Sure!
```json
{"kind":"followup"}
```"#;
        let value = extract_first_json_value(raw).expect("extract should succeed");
        assert_eq!(value["kind"], "followup");
    }

    #[test]
    fn prompt_includes_candidates_and_constraints() {
        let prompt = build_message_action_prompt(
            "done with taxes",
            "2026-02-03T12:00:00",
            "en",
            21 * 60,
            &[TodoCandidate {
                id: "todo:1".to_string(),
                title: "taxes".to_string(),
                status: "open".to_string(),
                due_local_iso: None,
            }],
            &[],
        );
        assert!(prompt.contains("Output ONLY JSON"));
        assert!(prompt.contains("todo:1"));
        assert!(prompt.contains("taxes"));
        assert!(prompt.contains("day_end_minutes"));
        assert!(prompt.contains("\"recurrence\""));
        assert!(prompt.contains("\"suggested_tags\""));
        assert!(prompt.contains("message may be in any language"));
    }

    #[test]
    fn prompt_allows_create_when_no_candidate_matches() {
        let prompt = build_message_action_prompt(
            "fix the tv",
            "2026-02-03T12:00:00",
            "en",
            21 * 60,
            &[],
            &[],
        );
        assert!(prompt.contains("even if no candidates match"));
    }

    #[test]
    fn prompt_declares_due_local_iso_only_once() {
        let prompt = build_message_action_prompt(
            "reschedule taxes",
            "2026-02-03T12:00:00",
            "en",
            21 * 60,
            &[],
            &[],
        );
        assert_eq!(prompt.matches("\"due_local_iso\"").count(), 1);
    }

    #[test]
    fn enhancement_prompt_includes_local_result_and_unresolved_fields() {
        let prompt = build_message_action_enhancement_prompt(
            "把这个改到节后第一个工作日",
            "2026-02-04T10:00:00",
            "zh-CN",
            21 * 60,
            r#"{"kind":"none","confidence":0.45,"resolver":"local","diagnostics":{"local_intent":"ambiguous_followup"}}"#,
            &["todo_id".to_string(), "due_local_iso".to_string()],
            &[TodoCandidate {
                id: "todo:1".to_string(),
                title: "报销".to_string(),
                status: "open".to_string(),
                due_local_iso: None,
            }],
            &[],
        );
        assert!(prompt.contains("local_result"));
        assert!(prompt.contains("unresolved_fields"));
        assert!(prompt.contains("ambiguous_followup"));
        assert!(prompt.contains("Do not ignore the local_result"));
    }

    #[test]
    fn enhancement_prompt_keeps_create_without_candidate_guidance() {
        let prompt = build_message_action_enhancement_prompt(
            "book dentist for next Tuesday",
            "2026-02-04T10:00:00",
            "en",
            21 * 60,
            r#"{"kind":"none","confidence":0.55,"resolver":"local","diagnostics":{"local_intent":"needs_enhancement"}}"#,
            &[
                "kind".to_string(),
                "title".to_string(),
                "status".to_string(),
            ],
            &[],
            &[],
        );

        assert!(prompt.contains("even if no candidates match"));
    }

    #[test]
    fn enhancement_prompt_keeps_multilingual_guidance() {
        let prompt = build_message_action_enhancement_prompt(
            "把这个改到节后第一个工作日",
            "2026-02-04T10:00:00",
            "zh-CN",
            21 * 60,
            r#"{"kind":"none","confidence":0.45,"resolver":"local","diagnostics":{"local_intent":"ambiguous_followup"}}"#,
            &["todo_id".to_string(), "due_local_iso".to_string()],
            &[],
            &[],
        );

        assert!(prompt.contains("message may be in any language"));
    }

    #[test]
    fn prompt_includes_available_tags_guidance() {
        let prompt = build_message_action_prompt(
            "plan trip",
            "2026-02-03T12:00:00",
            "en",
            21 * 60,
            &[],
            &["travel".to_string(), "projectx".to_string()],
        );
        assert!(prompt.contains("available_tags"));
        assert!(prompt.contains("Prefer tags from available_tags"));
    }

    #[test]
    fn parse_message_action_returns_json_object() {
        let provider = FakeProvider {
            response: r#"```json
{"kind":"followup","confidence":0.9,"todo_id":"todo:1","new_status":"done"}
```"#
                .to_string(),
        };
        let result = semantic_parse_message_action_json(
            &provider,
            "I finished taxes",
            "2026-02-03T12:00:00",
            "en",
            21 * 60,
            &[],
            &[],
        )
        .expect("should parse");

        let decoded: Value = serde_json::from_str(&result).expect("valid json");
        assert_eq!(decoded["kind"], "followup");
        assert_eq!(decoded["todo_id"], "todo:1");
    }

    #[test]
    fn parse_message_action_enhancement_returns_json_object() {
        let provider = FakeProvider {
            response: r#"{"kind":"followup","confidence":0.91,"todo_id":"todo:1","new_status":null,"due_local_iso":"2026-02-24T21:00:00"}"#
                .to_string(),
        };
        let result = semantic_parse_message_action_enhancement_json(
            &provider,
            "把这个改到节后第一个工作日",
            "2026-02-04T10:00:00",
            "zh-CN",
            21 * 60,
            r#"{"kind":"none","confidence":0.45,"resolver":"local","diagnostics":{"local_intent":"ambiguous_followup"}}"#,
            &["todo_id".to_string(), "due_local_iso".to_string()],
            &[TodoCandidate {
                id: "todo:1".to_string(),
                title: "报销".to_string(),
                status: "open".to_string(),
                due_local_iso: None,
            }],
            &[],
        )
        .expect("should parse");

        let decoded: Value = serde_json::from_str(&result).expect("valid json");
        assert_eq!(decoded["kind"], "followup");
        assert_eq!(decoded["todo_id"], "todo:1");
    }

    #[test]
    fn prompt_time_window_includes_constraints() {
        let prompt = build_ask_ai_time_window_prompt(
            "what did i do last week",
            "2026-02-03T12:00:00",
            "en",
            1,
        );
        assert!(prompt.contains("Output ONLY JSON"));
        assert!(prompt.contains("first_day_of_week_index"));
        assert!(prompt.contains("start_local_iso"));
        assert!(prompt.contains("end_local_iso"));
    }

    #[test]
    fn parse_time_window_returns_json_object() {
        let provider = FakeProvider {
            response: r#"```json
{"kind":"past","confidence":0.9,"start_local_iso":"2026-01-26T00:00:00","end_local_iso":"2026-02-02T00:00:00"}
```"#
                .to_string(),
        };
        let result = semantic_parse_ask_ai_time_window_json(
            &provider,
            "what did I do last week",
            "2026-02-03T12:00:00",
            "en",
            1,
        )
        .expect("should parse");

        let decoded: Value = serde_json::from_str(&result).expect("valid json");
        assert_eq!(decoded["kind"], "past");
        assert_eq!(decoded["start_local_iso"], "2026-01-26T00:00:00");
    }
}
