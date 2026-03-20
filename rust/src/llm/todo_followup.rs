use serde::Deserialize;

const TODO_FOLLOWUP_ENVELOPE_TAG: &str = "secondloop_todo_followup";

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum TodoFollowupGenerationMode {
    WebSearch,
    ModelKnowledge,
}

#[derive(Debug, Deserialize)]
struct TodoFollowupPromptEnvelope {
    #[serde(default)]
    generation_mode: String,
}

impl TodoFollowupGenerationMode {
    fn from_wire_value(raw: &str) -> Self {
        if raw.trim().eq_ignore_ascii_case("web_search") {
            return Self::WebSearch;
        }
        Self::ModelKnowledge
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

    let prompt_body = rest[close_index + close_tag.len()..].trim_start();
    (
        Some(TodoFollowupGenerationMode::from_wire_value(
            &metadata.generation_mode,
        )),
        prompt_body.to_string(),
    )
}
