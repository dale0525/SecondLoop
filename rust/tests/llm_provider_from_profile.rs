use std::io::{Read, Write};
use std::net::TcpListener;
use std::thread;

use secondloop_rust::db::LlmProfileConfig;
use secondloop_rust::llm::ChatDelta;
use secondloop_rust::llm;

fn start_one_shot_server(
    body: String,
    content_type: &'static str,
) -> (String, thread::JoinHandle<()>) {
    let listener = TcpListener::bind("127.0.0.1:0").expect("bind");
    let addr = listener.local_addr().expect("local addr");

    let handle = thread::spawn(move || {
        let (mut stream, _) = listener.accept().expect("accept");
        let mut buf = [0u8; 4096];
        let _ = stream.read(&mut buf);

        let resp = format!(
            "HTTP/1.1 200 OK\r\nContent-Type: {content_type}\r\nContent-Length: {}\r\nConnection: close\r\n\r\n{body}",
            body.as_bytes().len()
        );
        stream.write_all(resp.as_bytes()).expect("write response");
    });

    (format!("http://{}", addr), handle)
}

#[test]
fn provider_from_profile_streams_gemini() {
    let sse = r#"
data: {"candidates":[{"content":{"role":"model","parts":[{"text":"Hello"}]}}]}

data: {"candidates":[{"content":{"role":"model","parts":[{"text":" world"}]}}]}

data: {"candidates":[{"content":{"role":"model","parts":[{"text":""}]},"finishReason":"STOP"}]}
"#;
    let (base_url, handle) = start_one_shot_server(sse.to_string(), "text/event-stream");

    let config = LlmProfileConfig {
        provider_type: "gemini-compatible".to_string(),
        base_url: Some(base_url),
        api_key: Some("test-key".to_string()),
        model_name: "gemini-1.5-flash".to_string(),
    };

    let provider = llm::answer_provider_from_profile(&config).expect("provider");

    let mut events: Vec<ChatDelta> = Vec::new();
    provider
        .stream_answer("hi", &mut |ev| {
            events.push(ev);
            Ok(())
        })
        .expect("stream answer");

    handle.join().expect("join server thread");

    assert_eq!(events.last().map(|v| v.done), Some(true));
}

#[test]
fn provider_from_profile_streams_anthropic() {
    let sse = r#"
event: message_start
data: {"type":"message_start","message":{"id":"msg_123","type":"message","role":"assistant","content":[],"model":"claude-3-5-sonnet-20240620","stop_reason":null,"stop_sequence":null,"usage":{"input_tokens":10,"output_tokens":0}}}

event: content_block_delta
data: {"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"Hello"}}

event: message_stop
data: {"type":"message_stop"}
"#;
    let (base_url, handle) = start_one_shot_server(sse.to_string(), "text/event-stream");

    let config = LlmProfileConfig {
        provider_type: "anthropic-compatible".to_string(),
        base_url: Some(base_url),
        api_key: Some("test-key".to_string()),
        model_name: "claude-3-5-sonnet-20240620".to_string(),
    };

    let provider = llm::answer_provider_from_profile(&config).expect("provider");

    let mut events: Vec<ChatDelta> = Vec::new();
    provider
        .stream_answer("hi", &mut |ev| {
            events.push(ev);
            Ok(())
        })
        .expect("stream answer");

    handle.join().expect("join server thread");

    assert_eq!(events.last().map(|v| v.done), Some(true));
}

#[test]
fn provider_from_profile_requires_api_key_for_byok_providers() {
    let config = LlmProfileConfig {
        provider_type: "gemini-compatible".to_string(),
        base_url: None,
        api_key: None,
        model_name: "gemini-1.5-flash".to_string(),
    };

    let err = match llm::answer_provider_from_profile(&config) {
        Ok(_) => panic!("should error"),
        Err(e) => e,
    };
    assert!(err.to_string().contains("missing api_key"));

    let config2 = LlmProfileConfig {
        provider_type: "anthropic-compatible".to_string(),
        base_url: None,
        api_key: None,
        model_name: "claude-3-5-sonnet-20240620".to_string(),
    };

    let err2 = match llm::answer_provider_from_profile(&config2) {
        Ok(_) => panic!("should error"),
        Err(e) => e,
    };
    assert!(err2.to_string().contains("missing api_key"));
}

#[test]
fn provider_from_profile_rejects_unknown_provider_type() {
    let config = LlmProfileConfig {
        provider_type: "unknown".to_string(),
        base_url: None,
        api_key: None,
        model_name: "x".to_string(),
    };

    let err = match llm::answer_provider_from_profile(&config) {
        Ok(_) => panic!("should error"),
        Err(e) => e,
    };
    assert!(err.to_string().contains("unsupported provider_type"));
}
