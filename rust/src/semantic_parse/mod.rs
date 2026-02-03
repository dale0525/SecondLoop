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
    out.push_str(
        "  \"new_status\": \"in_progress\" | \"done\" | \"dismissed\", // only when kind=followup\n",
    );
    out.push_str("  \"title\": string, // only when kind=create\n");
    out.push_str("  \"status\": \"open\" | \"inbox\", // only when kind=create\n");
    out.push_str("  \"due_local_iso\": string | null // only when kind=create\n");
    out.push_str("}\n\n");

    out.push_str("Constraints:\n");
    out.push_str("- If kind=followup, todo_id MUST be one of the candidate IDs.\n");
    out.push_str(
        "- Use kind=followup ONLY when the user clearly refers to a specific candidate.\n",
    );
    out.push_str(
        "- If the message describes a new task, use kind=create even if no candidates match.\n",
    );
    out.push_str("- If unsure, use kind=none.\n");
    out.push_str(
        "- due_local_iso must be local ISO 8601 without timezone, like 2026-02-04T15:00:00.\n",
    );
    out.push_str("- If the user provides a date but no time, use day_end_minutes.\n\n");

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

pub fn semantic_parse_message_action_json(
    provider: &dyn AnswerProvider,
    text: &str,
    now_local_iso: &str,
    locale: &str,
    day_end_minutes: i32,
    candidates: &[TodoCandidate],
) -> Result<String> {
    let prompt =
        build_message_action_prompt(text, now_local_iso, locale, day_end_minutes, candidates);
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
        );
        assert!(prompt.contains("Output ONLY JSON"));
        assert!(prompt.contains("todo:1"));
        assert!(prompt.contains("taxes"));
        assert!(prompt.contains("day_end_minutes"));
    }

    #[test]
    fn prompt_allows_create_when_no_candidate_matches() {
        let prompt =
            build_message_action_prompt("fix the tv", "2026-02-03T12:00:00", "en", 21 * 60, &[]);
        assert!(prompt.contains("even if no candidates match"));
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
