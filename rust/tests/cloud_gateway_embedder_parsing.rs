use secondloop_rust::embedding::cloud_gateway::parse_openai_embeddings_response;
use secondloop_rust::embedding::Embedder;

use std::io::{Read, Write};
use std::net::TcpListener;
use std::sync::mpsc;
use std::thread;
use std::time::Duration;

fn start_one_shot_server(
    body: String,
    extra_headers: Vec<(String, String)>,
) -> (String, mpsc::Receiver<String>, thread::JoinHandle<()>) {
    let listener = TcpListener::bind("127.0.0.1:0").expect("bind");
    let addr = listener.local_addr().expect("local addr");
    let (tx, rx) = mpsc::channel::<String>();

    let handle = thread::spawn(move || {
        let (mut stream, _) = listener.accept().expect("accept");
        let mut buf = [0u8; 8192];
        let n = stream.read(&mut buf).unwrap_or(0);
        let _ = tx.send(String::from_utf8_lossy(&buf[..n]).to_string());

        let mut headers = String::new();
        for (k, v) in extra_headers {
            headers.push_str(&format!("{k}: {v}\r\n"));
        }
        let resp = format!(
            "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\n{headers}Content-Length: {}\r\nConnection: close\r\n\r\n{body}",
            body.len()
        );
        stream.write_all(resp.as_bytes()).expect("write response");
    });

    (format!("http://{}", addr), rx, handle)
}

#[test]
fn parse_openai_embeddings_response_returns_embeddings_in_index_order() {
    let e0: Vec<f32> = (0..384).map(|i| i as f32).collect();
    let e1: Vec<f32> = (0..384).map(|i| 1000.0 + i as f32).collect();

    let body = serde_json::json!({
        "object": "list",
        "data": [
            { "object": "embedding", "index": 1, "embedding": e1 },
            { "object": "embedding", "index": 0, "embedding": e0 }
        ],
        "model": "multilingual-e5-small",
        "usage": { "prompt_tokens": 12, "total_tokens": 12 }
    })
    .to_string();

    let parsed = parse_openai_embeddings_response(&body, 2).expect("parse");
    assert_eq!(parsed.dim, 384);
    let embeddings = parsed.embeddings;
    assert_eq!(embeddings.len(), 2);
    assert_eq!(embeddings[0].len(), 384);
    assert_eq!(embeddings[1].len(), 384);
    assert_eq!(embeddings[0][0], 0.0);
    assert_eq!(embeddings[0][383], 383.0);
    assert_eq!(embeddings[1][0], 1000.0);
    assert_eq!(embeddings[1][383], 1383.0);
}

#[test]
fn parse_openai_embeddings_response_errors_on_count_mismatch() {
    let e0: Vec<f32> = vec![0.0; 384];

    let body = serde_json::json!({
        "object": "list",
        "data": [
            { "object": "embedding", "index": 0, "embedding": e0 }
        ],
        "model": "multilingual-e5-small"
    })
    .to_string();

    let err = parse_openai_embeddings_response(&body, 2).unwrap_err();
    assert!(err.to_string().contains("expected 2 embeddings"));
}

#[test]
fn parse_openai_embeddings_response_errors_on_dim_mismatch_between_items() {
    let e0: Vec<f32> = vec![0.0; 2];
    let e1: Vec<f32> = vec![0.0; 3];

    let body = serde_json::json!({
        "object": "list",
        "data": [
            { "object": "embedding", "index": 0, "embedding": e0 },
            { "object": "embedding", "index": 1, "embedding": e1 }
        ],
        "model": "multilingual-e5-small"
    })
    .to_string();

    let err = parse_openai_embeddings_response(&body, 2).unwrap_err();
    assert!(err.to_string().contains("embedding dim mismatch"));
}

#[test]
fn cloud_gateway_embedder_posts_bearer_and_returns_embeddings() {
    let e0: Vec<f32> = (0..384).map(|i| i as f32).collect();
    let e1: Vec<f32> = (0..384).map(|i| 1000.0 + i as f32).collect();

    let body = serde_json::json!({
        "object": "list",
        "data": [
            { "object": "embedding", "index": 0, "embedding": e0 },
            { "object": "embedding", "index": 1, "embedding": e1 }
        ],
        "model": "multilingual-e5-small",
        "usage": { "prompt_tokens": 12, "total_tokens": 12 }
    })
    .to_string();

    let (base_url, req_rx, handle) = start_one_shot_server(
        body,
        vec![(
            "x-secondloop-embedding-model-id".to_string(),
            "multilingual-e5-small@v2".to_string(),
        )],
    );

    let embedder = secondloop_rust::embedding::cloud_gateway::CloudGatewayEmbedder::new(
        base_url,
        "test-id-token".to_string(),
        "multilingual-e5-small".to_string(),
    );

    let out = embedder
        .embed(&["hello".to_string(), "world".to_string()])
        .expect("embed");
    assert_eq!(out.len(), 2);
    assert_eq!(out[0].len(), 384);
    assert_eq!(out[1].len(), 384);
    assert_eq!(out[0][0], 0.0);
    assert_eq!(out[1][0], 1000.0);
    assert_eq!(embedder.model_name(), "multilingual-e5-small@v2");

    handle.join().expect("join server thread");

    let req = req_rx
        .recv_timeout(Duration::from_secs(1))
        .expect("receive request");
    let req_lower = req.to_ascii_lowercase();
    assert!(req_lower.contains("post /v1/embeddings"));
    assert!(req_lower.contains("authorization: bearer test-id-token"));
    assert!(req_lower.contains("x-secondloop-purpose: embeddings"));
    assert!(req_lower.contains("content-type: application/json"));
    assert!(req.contains(r#""model":"multilingual-e5-small""#));
    assert!(req.contains(r#""encoding_format":"float""#));
    assert!(req.contains(r#""input":["hello","world"]"#));
}
