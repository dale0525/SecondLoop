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
fn openai_sse_keeps_role_and_content_in_same_chunk_together_without_reasoning() {
    let sse = r#"
data: {"choices":[{"delta":{"role":"assistant","content":"Hello in same chunk"}}]}

data: [DONE]
"#;

    let events = openai::parse_chat_completions_sse(sse.as_bytes()).expect("parse sse");
    assert_eq!(
        events,
        vec![
            ChatDelta {
                role: Some("assistant".to_string()),
                text_delta: "Hello in same chunk".to_string(),
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
fn openai_sse_parses_reasoning_content_as_control_role() {
    let sse = r#"
data: {"choices":[{"delta":{"reasoning_content":"I should inspect the local context."}}]}

data: {"choices":[{"delta":{"content":"Here is the answer."}}]}

data: [DONE]
"#;

    let events = openai::parse_chat_completions_sse(sse.as_bytes()).expect("parse sse");
    assert_eq!(
        events,
        vec![
            ChatDelta {
                role: Some(
                    "secondloop_reasoning_delta:I should inspect the local context.".to_string(),
                ),
                text_delta: "".to_string(),
                done: false,
            },
            ChatDelta {
                role: None,
                text_delta: "Here is the answer.".to_string(),
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
fn openai_json_parses_message_reasoning_before_answer() {
    let body = r#"{
  "choices": [
    {
      "message": {
        "role": "assistant",
        "reasoning_content": "I checked the relevant memory.",
        "content": "The next step is to book the appointment."
      }
    }
  ]
}"#;

    let events = openai::parse_chat_completions_json(body.as_bytes()).expect("parse json");
    assert_eq!(
        events,
        vec![
            ChatDelta {
                role: Some("secondloop_reasoning_delta:I checked the relevant memory.".to_string()),
                text_delta: "".to_string(),
                done: false,
            },
            ChatDelta {
                role: Some("assistant".to_string()),
                text_delta: "The next step is to book the appointment.".to_string(),
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
fn openai_json_parses_message_reasoning_field_before_answer() {
    let body = r#"{
  "choices": [
    {
      "message": {
        "role": "assistant",
        "reasoning": "I used the shorter message reasoning field.",
        "content": "Answer after reasoning."
      }
    }
  ]
}"#;

    let events = openai::parse_chat_completions_json(body.as_bytes()).expect("parse json");
    assert_eq!(
        events,
        vec![
            ChatDelta {
                role: Some(
                    "secondloop_reasoning_delta:I used the shorter message reasoning field."
                        .to_string(),
                ),
                text_delta: "".to_string(),
                done: false,
            },
            ChatDelta {
                role: Some("assistant".to_string()),
                text_delta: "Answer after reasoning.".to_string(),
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
fn openai_json_parses_top_level_reasoning_before_answer_text() {
    let body = r#"{
  "reasoning": "I used a top-level reasoning field.",
  "text": "Answer from top-level text."
}"#;

    let events = openai::parse_chat_completions_json(body.as_bytes()).expect("parse json");
    assert_eq!(
        events,
        vec![
            ChatDelta {
                role: Some(
                    "secondloop_reasoning_delta:I used a top-level reasoning field.".to_string(),
                ),
                text_delta: "".to_string(),
                done: false,
            },
            ChatDelta {
                role: None,
                text_delta: "Answer from top-level text.".to_string(),
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
fn openai_sse_parses_delta_reasoning_field_as_control_role() {
    let sse = r#"
data: {"choices":[{"delta":{"reasoning":"A shorter reasoning field."}}]}

data: [DONE]
"#;

    let events = openai::parse_chat_completions_sse(sse.as_bytes()).expect("parse sse");
    assert_eq!(
        events,
        vec![
            ChatDelta {
                role: Some("secondloop_reasoning_delta:A shorter reasoning field.".to_string()),
                text_delta: "".to_string(),
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
fn openai_sse_preserves_reasoning_delta_whitespace() {
    let sse = r#"
data: {"choices":[{"delta":{"reasoning_content":"I"}}]}

data: {"choices":[{"delta":{"reasoning_content":" should keep spacing."}}]}

data: [DONE]
"#;

    let events = openai::parse_chat_completions_sse(sse.as_bytes()).expect("parse sse");
    assert_eq!(
        events,
        vec![
            ChatDelta {
                role: Some("secondloop_reasoning_delta:I".to_string()),
                text_delta: "".to_string(),
                done: false,
            },
            ChatDelta {
                role: Some("secondloop_reasoning_delta: should keep spacing.".to_string()),
                text_delta: "".to_string(),
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
fn openai_sse_preserves_role_when_reasoning_appears_in_same_chunk() {
    let sse = r#"
data: {"choices":[{"delta":{"role":"assistant","reasoning_content":"Thinking."}}]}

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
                role: Some("secondloop_reasoning_delta:Thinking.".to_string()),
                text_delta: "".to_string(),
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
fn openai_sse_parses_responses_api_reasoning_delta_as_control_role() {
    let sse = r#"
event: response.reasoning_text.delta
data: {"type":"response.reasoning_text.delta","delta":"I should inspect context."}

event: response.output_text.delta
data: {"type":"response.output_text.delta","delta":"Here is the answer."}

event: response.completed
data: {"type":"response.completed"}
"#;

    let events = openai::parse_chat_completions_sse(sse.as_bytes()).expect("parse sse");
    assert_eq!(
        events,
        vec![
            ChatDelta {
                role: Some("secondloop_reasoning_delta:I should inspect context.".to_string()),
                text_delta: "".to_string(),
                done: false,
            },
            ChatDelta {
                role: None,
                text_delta: "Here is the answer.".to_string(),
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
