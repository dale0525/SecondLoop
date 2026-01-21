use std::io::{Read, Write};
use std::net::TcpListener;
use std::thread;

use secondloop_rust::llm::anthropic::AnthropicCompatibleProvider;
use secondloop_rust::llm::ChatDelta;
use secondloop_rust::rag::AnswerProvider;

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
            body.len()
        );
        stream.write_all(resp.as_bytes()).expect("write response");
    });

    (format!("http://{}", addr), handle)
}

#[test]
fn anthropic_provider_streams_sse_deltas() {
    let sse = r#"
event: message_start
data: {"type":"message_start","message":{"id":"msg_123","type":"message","role":"assistant","content":[],"model":"claude-3-5-sonnet-20240620","stop_reason":null,"stop_sequence":null,"usage":{"input_tokens":10,"output_tokens":0}}}

event: content_block_delta
data: {"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"Hello"}}

event: content_block_delta
data: {"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":" world"}}

event: message_stop
data: {"type":"message_stop"}
"#;

    let (base_url, handle) = start_one_shot_server(sse.to_string(), "text/event-stream");

    let provider = AnthropicCompatibleProvider::new(
        base_url,
        "test-key".to_string(),
        "claude-3-5-sonnet-20240620".to_string(),
        1024,
    );

    let mut events: Vec<ChatDelta> = Vec::new();
    provider
        .stream_answer("hi", &mut |ev| {
            events.push(ev);
            Ok(())
        })
        .expect("stream answer");

    handle.join().expect("join server thread");

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
