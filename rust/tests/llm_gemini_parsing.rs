use std::io::Cursor;

use secondloop_rust::llm::{gemini, ChatDelta};

#[test]
fn gemini_sse_parses_deltas_and_done() {
    let sse = r#"
data: {"candidates":[{"content":{"role":"model","parts":[{"text":"Hello"}]}}]}

data: {"candidates":[{"content":{"role":"model","parts":[{"text":" world"}]}}]}

data: {"candidates":[{"content":{"role":"model","parts":[{"text":""}]},"finishReason":"STOP"}]}
"#;

    let events = gemini::parse_generate_content_sse(sse.as_bytes()).expect("parse sse");
    assert_eq!(
        events,
        vec![
            ChatDelta {
                role: Some("assistant".to_string()),
                text_delta: "".to_string(),
                done: false,
            },
            ChatDelta {
                role: None,
                text_delta: "Hello".to_string(),
                done: false,
            },
            ChatDelta {
                role: None,
                text_delta: " world".to_string(),
                done: false,
            },
            ChatDelta {
                role: None,
                text_delta: "".to_string(),
                done: true,
            },
        ]
    );
}

#[test]
fn gemini_non_stream_json_parses_message_content() {
    let body = r#"
{
  "candidates": [
    {
      "index": 0,
      "content": {
        "role": "model",
        "parts": [{"text": "Hello from JSON"}]
      },
      "finishReason": "STOP"
    }
  ]
}
"#;

    let events = gemini::parse_generate_content_json(Cursor::new(body)).expect("parse json");
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
            },
        ]
    );
}

