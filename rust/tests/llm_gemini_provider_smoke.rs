use std::io::{Read, Write};
use std::net::TcpListener;
use std::thread;

use secondloop_rust::llm::gemini::GeminiCompatibleProvider;
use secondloop_rust::llm::ChatDelta;
use secondloop_rust::rag::AnswerProvider;

fn start_one_shot_server(body: String, content_type: &'static str) -> (String, thread::JoinHandle<()>) {
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
fn gemini_provider_streams_sse_deltas() {
    let sse = r#"
data: {"candidates":[{"content":{"role":"model","parts":[{"text":"Hello"}]}}]}

data: {"candidates":[{"content":{"role":"model","parts":[{"text":" world"}]}}]}

data: {"candidates":[{"content":{"role":"model","parts":[{"text":""}]},"finishReason":"STOP"}]}
"#;

    let (base_url, handle) = start_one_shot_server(sse.to_string(), "text/event-stream");

    let provider = GeminiCompatibleProvider::new(
        base_url,
        "test-key".to_string(),
        "gemini-1.5-flash".to_string(),
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

