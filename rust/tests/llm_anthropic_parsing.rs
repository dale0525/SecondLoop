use std::io::Cursor;

use secondloop_rust::llm::{anthropic, ChatDelta};

#[test]
fn anthropic_sse_parses_deltas_and_done() {
    let sse = r#"
event: message_start
data: {"type":"message_start","message":{"id":"msg_123","type":"message","role":"assistant","content":[],"model":"claude-3-5-sonnet-20240620","stop_reason":null,"stop_sequence":null,"usage":{"input_tokens":10,"output_tokens":0}}}

event: content_block_start
data: {"type":"content_block_start","index":0,"content_block":{"type":"text","text":""}}

event: content_block_delta
data: {"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"Hello"}}

event: content_block_delta
data: {"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":" world"}}

event: message_stop
data: {"type":"message_stop"}
"#;

    let events = anthropic::parse_messages_sse(sse.as_bytes()).expect("parse sse");
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
fn anthropic_non_stream_json_parses_message_content() {
    let body = r#"
{
  "id": "msg_123",
  "type": "message",
  "role": "assistant",
  "model": "claude-3-5-sonnet-20240620",
  "content": [
    {"type": "text", "text": "Hello from JSON"}
  ],
  "stop_reason": "end_turn",
  "stop_sequence": null,
  "usage": {"input_tokens": 10, "output_tokens": 2}
}
"#;

    let events = anthropic::parse_messages_json(Cursor::new(body)).expect("parse json");
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

