use agent_runtime::session::ConversationEventRecord;

pub(crate) fn user_visible_events(
    events: Vec<ConversationEventRecord>,
) -> Vec<ConversationEventRecord> {
    events.into_iter().filter(user_visible_event).collect()
}

fn user_visible_event(event: &ConversationEventRecord) -> bool {
    match event.kind.as_str() {
        "structured_content_published" => {
            event
                .payload
                .pointer("/content/audience")
                .and_then(serde_json::Value::as_str)
                == Some("user")
        }
        "structured_content_deleted" => {
            event
                .payload
                .get("audience")
                .and_then(serde_json::Value::as_str)
                == Some("user")
        }
        "structured_content_action_accepted" => false,
        _ => true,
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use chrono::Utc;
    use serde_json::json;

    #[test]
    fn user_projection_hides_private_structured_events_and_receipts() {
        let events = vec![
            event(
                "structured_content_published",
                json!({
                    "type":"structured_content_published",
                    "content":{"audience":"owner"}
                }),
            ),
            event(
                "structured_content_published",
                json!({
                    "type":"structured_content_published",
                    "content":{"audience":"user"}
                }),
            ),
            event(
                "structured_content_deleted",
                json!({
                    "type":"structured_content_deleted",
                    "audience":"developer"
                }),
            ),
            event(
                "structured_content_action_accepted",
                json!({
                    "type":"structured_content_action_accepted",
                    "receipt":{"binding_id":"private"}
                }),
            ),
            event(
                "assistant_text_delta",
                json!({
                    "type":"assistant_text_delta",
                    "text":"visible"
                }),
            ),
        ];

        let projected = user_visible_events(events);

        assert_eq!(projected.len(), 2);
        assert_eq!(projected[0].kind, "structured_content_published");
        assert_eq!(projected[1].kind, "assistant_text_delta");
    }

    fn event(kind: &str, payload: serde_json::Value) -> ConversationEventRecord {
        ConversationEventRecord {
            id: format!("{kind}-id"),
            session_id: "session".into(),
            turn_id: None,
            event_index: 0,
            kind: kind.into(),
            payload,
            created_at: Utc::now(),
        }
    }
}
