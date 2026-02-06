use secondloop_rust::llm::{openai, ChatDelta};

#[test]
fn openai_sse_parses_deltas_and_done() {
    let sse = r#"
data: {"id":"chatcmpl-123","choices":[{"index":0,"delta":{"role":"assistant"},"finish_reason":null}]}

data: {"id":"chatcmpl-123","choices":[{"index":0,"delta":{"content":"Hello"},"finish_reason":null}]}

data: {"id":"chatcmpl-123","choices":[{"index":0,"delta":{"content":" world"},"finish_reason":null}]}

data: {"usage":{"prompt_tokens":10,"completion_tokens":20,"total_tokens":30}}

data: [DONE]
"#;

    let events = openai::parse_chat_completions_sse(sse.as_bytes()).expect("parse sse");
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
fn openai_sse_parses_content_parts_deltas() {
    let sse = r#"
data: {"id":"chatcmpl-123","choices":[{"index":0,"delta":{"role":"assistant"},"finish_reason":null}]}

data: {"id":"chatcmpl-123","choices":[{"index":0,"delta":{"content":[{"type":"output_text","text":"Hello"},{"type":"output_text","text":" world"}]},"finish_reason":null}]}

data: [DONE]
"#;

    let events = openai::parse_chat_completions_sse(sse.as_bytes()).expect("parse sse");
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
                text_delta: "Hello world".to_string(),
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
fn openai_json_parses_content_parts_message() {
    let body = r#"{
  "choices": [
    {
      "message": {
        "role": "assistant",
        "content": [
          { "type": "output_text", "text": "你好" },
          { "type": "output_text", "text": "，世界" }
        ]
      }
    }
  ]
}"#;

    let events = openai::parse_chat_completions_json(body.as_bytes()).expect("parse json");
    assert_eq!(
        events,
        vec![
            ChatDelta {
                role: Some("assistant".to_string()),
                text_delta: "你好，世界".to_string(),
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
fn openai_sse_parses_multiline_data_event() {
    let sse = r#"
data: {"choices":[{"delta":
data: {"content":"line-one"}}]}

data: [DONE]
"#;

    let events = openai::parse_chat_completions_sse(sse.as_bytes()).expect("parse sse");
    assert_eq!(
        events,
        vec![
            ChatDelta {
                role: None,
                text_delta: "line-one".to_string(),
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
fn openai_sse_parses_responses_api_delta_event() {
    let sse = r#"
event: response.output_text.delta
data: {"type":"response.output_text.delta","delta":"hello"}

event: response.output_text.delta
data: {"type":"response.output_text.delta","delta":" world"}

event: response.completed
data: {"type":"response.completed"}
"#;

    let events = openai::parse_chat_completions_sse(sse.as_bytes()).expect("parse sse");
    assert_eq!(
        events,
        vec![
            ChatDelta {
                role: None,
                text_delta: "hello".to_string(),
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
fn openai_json_parses_responses_api_output() {
    let body = r#"{
  "id": "resp_123",
  "output": [
    {
      "type": "message",
      "role": "assistant",
      "content": [
        { "type": "output_text", "text": "hello" },
        { "type": "output_text", "text": " world" }
      ]
    }
  ]
}"#;

    let events = openai::parse_chat_completions_json(body.as_bytes()).expect("parse json");
    assert_eq!(
        events,
        vec![
            ChatDelta {
                role: Some("assistant".to_string()),
                text_delta: "hello world".to_string(),
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
fn openai_sse_falls_back_when_body_is_plain_json_object() {
    let body = r#"{
  "id": "chatcmpl-20260206183902599194512ZPnYjCkj",
  "object": "chat.completion.chunk",
  "created": 1770374346,
  "choices": [
    {
      "index": 0,
      "finish_reason": "stop",
      "message": {
        "role": "assistant",
        "content": "{\n  \"kind\": \"none\",\n  \"confidence\": 1.0,\n  \"start_local_iso\": null,\n  \"end_local_iso\": null\n}"
      }
    }
  ],
  "model": "gemini-3-flash-preview"
}"#;

    let events = openai::parse_chat_completions_sse(body.as_bytes()).expect("parse sse");
    assert_eq!(
        events,
        vec![
            ChatDelta {
                role: Some("assistant".to_string()),
                text_delta: "{\n  \"kind\": \"none\",\n  \"confidence\": 1.0,\n  \"start_local_iso\": null,\n  \"end_local_iso\": null\n}".to_string(),
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
