use std::io::Cursor;

use secondloop_rust::llm::{self, ChatDelta};

#[test]
fn openai_non_stream_json_parses_message_content() {
    let body = r#"
{
  "id": "chatcmpl-123",
  "object": "chat.completion",
  "created": 123456,
  "model": "gpt-4o-mini",
  "choices": [
    {
      "index": 0,
      "message": {"role": "assistant", "content": "Hello from JSON"},
      "finish_reason": "stop"
    }
  ]
}
"#;

    let events = llm::openai::parse_chat_completions_json(Cursor::new(body)).expect("parse");
    assert_eq!(
        events,
        vec![
            ChatDelta {
                role: Some("assistant".to_string()),
                text_delta: "Hello from JSON".to_string(),
                done: false,
            },
            ChatDelta {
                role: None,
                text_delta: String::new(),
                done: true,
            }
        ]
    );
}
