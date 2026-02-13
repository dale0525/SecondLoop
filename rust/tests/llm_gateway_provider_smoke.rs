use std::io::{Read, Write};
use std::net::TcpListener;
use std::sync::mpsc;
use std::thread;
use std::time::Duration;

use secondloop_rust::llm::ChatDelta;
use secondloop_rust::rag::AnswerProvider;

fn start_one_shot_server(
    body: String,
    content_type: &'static str,
) -> (String, mpsc::Receiver<String>, thread::JoinHandle<()>) {
    let listener = TcpListener::bind("127.0.0.1:0").expect("bind");
    let addr = listener.local_addr().expect("local addr");
    let (tx, rx) = mpsc::channel::<String>();

    let handle = thread::spawn(move || {
        let (mut stream, _) = listener.accept().expect("accept");
        let mut buf = [0u8; 4096];
        let n = stream.read(&mut buf).unwrap_or(0);
        let _ = tx.send(String::from_utf8_lossy(&buf[..n]).to_string());

        let resp = format!(
            "HTTP/1.1 200 OK\r\nContent-Type: {content_type}\r\nContent-Length: {}\r\nConnection: close\r\n\r\n{body}",
            body.len()
        );
        stream.write_all(resp.as_bytes()).expect("write response");
    });

    (format!("http://{}", addr), rx, handle)
}

#[test]
fn cloud_gateway_provider_sends_bearer_and_streams() {
    let sse = r#"
data: {"choices":[{"delta":{"role":"assistant"}}]}

data: {"choices":[{"delta":{"content":"Hello"}}]}

data: {"choices":[{"delta":{"content":" world"}}]}

data: [DONE]
"#;

    let (base_url, req_rx, handle) = start_one_shot_server(sse.to_string(), "text/event-stream");

    let provider = secondloop_rust::llm::gateway::CloudGatewayProvider::new(
        base_url,
        "test-id-token".to_string(),
        "gpt-test".to_string(),
        None,
    );

    let mut events: Vec<ChatDelta> = Vec::new();
    provider
        .stream_answer("hi", &mut |ev| {
            events.push(ev);
            Ok(())
        })
        .expect("stream answer");

    handle.join().expect("join server thread");

    let req = req_rx
        .recv_timeout(Duration::from_secs(1))
        .expect("receive request");
    let req_lower = req.to_ascii_lowercase();
    assert!(req_lower.contains("post /v1/chat/completions"));
    assert!(req_lower.contains("authorization: bearer test-id-token"));
    assert!(req_lower.contains("x-secondloop-detach-policy: continue_on_disconnect"));
    assert!(req_lower.contains("x-secondloop-request-id: req_"));

    assert!(
        events.len() >= 5,
        "expected meta + stream events, got {}",
        events.len()
    );
    let meta_event = &events[0];
    assert!(meta_event
        .role
        .as_deref()
        .is_some_and(|role| role.starts_with("secondloop_request_id:req_")));
    assert_eq!(meta_event.text_delta, "");
    assert!(!meta_event.done);

    assert_eq!(
        &events[1..],
        &[
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
fn cloud_gateway_provider_handles_plain_json_with_sse_content_type() {
    let body = r#"{
  "id": "chatcmpl-plain-json",
  "object": "chat.completion.chunk",
  "choices": [
    {
      "index": 0,
      "finish_reason": "stop",
      "message": {
        "role": "assistant",
        "content": "fallback-json-content"
      }
    }
  ]
}"#;

    let (base_url, req_rx, handle) = start_one_shot_server(body.to_string(), "text/event-stream");

    let provider = secondloop_rust::llm::gateway::CloudGatewayProvider::new(
        base_url,
        "test-id-token".to_string(),
        "gpt-test".to_string(),
        None,
    );

    let mut events: Vec<ChatDelta> = Vec::new();
    provider
        .stream_answer("hi", &mut |ev| {
            events.push(ev);
            Ok(())
        })
        .expect("stream answer");

    handle.join().expect("join server thread");

    let req = req_rx
        .recv_timeout(Duration::from_secs(1))
        .expect("receive request");
    let req_lower = req.to_ascii_lowercase();
    assert!(req_lower.contains("post /v1/chat/completions"));
    assert!(req_lower.contains("authorization: bearer test-id-token"));
    assert!(req_lower.contains("x-secondloop-detach-policy: continue_on_disconnect"));
    assert!(req_lower.contains("x-secondloop-request-id: req_"));

    assert!(
        events.len() >= 3,
        "expected meta + response events, got {}",
        events.len()
    );
    let meta_event = &events[0];
    assert!(meta_event
        .role
        .as_deref()
        .is_some_and(|role| role.starts_with("secondloop_request_id:req_")));
    assert_eq!(meta_event.text_delta, "");
    assert!(!meta_event.done);

    assert_eq!(
        &events[1..],
        &[
            ChatDelta {
                role: Some("assistant".to_string()),
                text_delta: "fallback-json-content".to_string(),
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
