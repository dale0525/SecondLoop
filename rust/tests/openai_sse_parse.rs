use secondloop_rust::llm::{openai, ChatDelta};

#[test]
fn openai_sse_parses_deltas_and_done() {
    let sse = r#"
data: {"id":"chatcmpl-123","choices":[{"index":0,"delta":{"role":"assistant"},"finish_reason":null}]}

data: {"id":"chatcmpl-123","choices":[{"index":0,"delta":{"content":"Hello"},"finish_reason":null}]}

data: {"id":"chatcmpl-123","choices":[{"index":0,"delta":{"content":" world"},"finish_reason":null}]}

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
