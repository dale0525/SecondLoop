use serde::Deserialize;

const TODO_FOLLOWUP_ENVELOPE_TAG: &str = "secondloop_todo_followup";

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum TodoFollowupGenerationMode {
    WebSearch,
    ModelKnowledge,
}

#[derive(Debug, Deserialize)]
struct TodoFollowupPromptEnvelope {
    generation_mode: Option<String>,
}

impl TodoFollowupGenerationMode {
    fn parse_wire_value(raw: &str) -> Option<Self> {
        if raw.trim().eq_ignore_ascii_case("web_search") {
            return Some(Self::WebSearch);
        }
        if raw.trim().eq_ignore_ascii_case("model_knowledge") {
            return Some(Self::ModelKnowledge);
        }
        None
    }
}

pub fn parse_todo_followup_prompt(prompt: &str) -> (Option<TodoFollowupGenerationMode>, String) {
    let trimmed = prompt.trim_start();
    let open_tag = format!("<{}>", TODO_FOLLOWUP_ENVELOPE_TAG);
    let close_tag = format!("</{}>", TODO_FOLLOWUP_ENVELOPE_TAG);
    if !trimmed.starts_with(&open_tag) {
        return (None, prompt.to_string());
    }

    let rest = &trimmed[open_tag.len()..];
    let Some(close_index) = rest.find(&close_tag) else {
        return (None, prompt.to_string());
    };

    let metadata_text = &rest[..close_index];
    let Ok(metadata) = serde_json::from_str::<TodoFollowupPromptEnvelope>(metadata_text) else {
        return (None, prompt.to_string());
    };

    let Some(generation_mode) = metadata
        .generation_mode
        .as_deref()
        .and_then(TodoFollowupGenerationMode::parse_wire_value)
    else {
        return (None, prompt.to_string());
    };

    let prompt_body = rest[close_index + close_tag.len()..].trim_start();
    (Some(generation_mode), prompt_body.to_string())
}

#[cfg(test)]
mod tests {
    use super::{parse_todo_followup_prompt, TodoFollowupGenerationMode};

    #[test]
    fn keeps_original_prompt_when_generation_mode_is_invalid() {
        let prompt = concat!(
            r#"<secondloop_todo_followup>{"generation_mode":"internet"}</secondloop_todo_followup>"#,
            "\nPrompt body"
        );

        let (mode, body) = parse_todo_followup_prompt(prompt);

        assert_eq!(mode, None);
        assert_eq!(body, prompt);
    }

    #[test]
    fn keeps_original_prompt_when_generation_mode_is_missing() {
        let prompt = concat!(
            r#"<secondloop_todo_followup>{"unexpected":true}</secondloop_todo_followup>"#,
            "\nPrompt body"
        );

        let (mode, body) = parse_todo_followup_prompt(prompt);

        assert_eq!(mode, None);
        assert_eq!(body, prompt);
    }

    #[test]
    fn strips_envelope_when_generation_mode_is_valid() {
        let prompt = concat!(
            r#"<secondloop_todo_followup>{"generation_mode":"web_search"}</secondloop_todo_followup>"#,
            "\nPrompt body"
        );

        let (mode, body) = parse_todo_followup_prompt(prompt);

        assert_eq!(mode, Some(TodoFollowupGenerationMode::WebSearch));
        assert_eq!(body, "Prompt body");
    }
}
