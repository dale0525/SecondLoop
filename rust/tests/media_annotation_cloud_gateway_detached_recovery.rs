use std::collections::HashMap;
use std::io::{Read, Write};
use std::net::{TcpListener, TcpStream};
use std::time::Duration;

use serde_json::json;

#[derive(Debug)]
struct CapturedRequest {
    method: String,
    path: String,
    headers: HashMap<String, String>,
}

fn read_http_request(stream: &mut TcpStream) -> CapturedRequest {
    let mut buf = Vec::<u8>::new();
    let mut tmp = [0u8; 4096];

    loop {
        let n = stream.read(&mut tmp).expect("read");
        if n == 0 {
            break;
        }
        buf.extend_from_slice(&tmp[..n]);
        if buf.windows(4).any(|w| w == b"\r\n\r\n") {
            break;
        }
        if buf.len() > 1024 * 1024 {
            panic!("request too large");
        }
    }

    let header_end = buf
        .windows(4)
        .position(|w| w == b"\r\n\r\n")
        .expect("header end");
    let (head, rest) = buf.split_at(header_end);
    let head = String::from_utf8_lossy(head);

    let mut lines = head.split("\r\n");
    let request_line = lines.next().expect("request line");
    let mut request_parts = request_line.split_whitespace();
    let method = request_parts.next().unwrap_or_default().to_string();
    let path = request_parts.next().unwrap_or_default().to_string();

    let mut headers = HashMap::<String, String>::new();
    for line in lines {
        if line.trim().is_empty() {
            continue;
        }
        if let Some((k, v)) = line.split_once(':') {
            headers.insert(k.trim().to_ascii_lowercase(), v.trim().to_string());
        }
    }

    let content_length = headers
        .get("content-length")
        .and_then(|v| v.parse::<usize>().ok())
        .unwrap_or(0);

    let mut body_bytes = rest[4..].to_vec();
    while body_bytes.len() < content_length {
        let n = stream.read(&mut tmp).expect("read body");
        if n == 0 {
            break;
        }
        body_bytes.extend_from_slice(&tmp[..n]);
    }

    CapturedRequest {
        method,
        path,
        headers,
    }
}

fn start_mock_server_for_detached_recovery() -> String {
    let listener = TcpListener::bind("127.0.0.1:0").expect("bind");
    let addr = listener.local_addr().expect("addr");

    std::thread::spawn(move || {
        let (mut stream1, _) = listener.accept().expect("accept first");
        let req1 = read_http_request(&mut stream1);
        assert_eq!(req1.method, "GET");
        let request_id = req1
            .path
            .strip_prefix("/v1/chat/jobs/")
            .expect("status path")
            .to_string();

        let body1 = json!({
            "error": "job_not_found",
        })
        .to_string();
        let resp1 = format!(
            "HTTP/1.1 404 Not Found\r\nContent-Type: application/json\r\nContent-Length: {}\r\nConnection: close\r\n\r\n{body1}",
            body1.len(),
        );
        stream1.write_all(resp1.as_bytes()).expect("write first");

        let (mut stream2, _) = listener.accept().expect("accept second");
        let req2 = read_http_request(&mut stream2);
        assert_eq!(req2.method, "POST");
        assert_eq!(req2.path, "/v1/chat/completions");
        assert_eq!(
            req2.headers
                .get("x-secondloop-request-id")
                .map(String::as_str),
            Some(request_id.as_str())
        );

        let body2 = "data: {\"choices\":[{\"delta\":{\"content\":\"not-json\"}}]}\n\n";
        let resp2 = format!(
            "HTTP/1.1 200 OK\r\nContent-Type: text/event-stream\r\nContent-Length: {}\r\nConnection: close\r\n\r\n{body2}",
            body2.len(),
        );
        stream2.write_all(resp2.as_bytes()).expect("write second");

        let (mut stream3, _) = listener.accept().expect("accept third");
        let req3 = read_http_request(&mut stream3);
        assert_eq!(req3.method, "GET");
        assert_eq!(req3.path, format!("/v1/chat/jobs/{request_id}"));

        let detached_result_text =
            "{\"caption_long\":\"detached cat\",\"tag\":[],\"summary\":\"detached cat\",\"full_text\":\"detached cat\"}";

        let body3 = json!({
            "ok": true,
            "request_id": request_id,
            "status": "completed",
            "result_text": detached_result_text,
            "result_truncated": false,
        })
        .to_string();

        let resp3 = format!(
            "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: {}\r\nConnection: close\r\n\r\n{body3}",
            body3.len(),
        );
        stream3.write_all(resp3.as_bytes()).expect("write third");
    });

    format!("http://{addr}")
}

#[test]
fn cloud_gateway_media_annotation_recovers_from_detached_job_when_stream_parse_fails() {
    let base_url = start_mock_server_for_detached_recovery();

    let client = secondloop_rust::media_annotation::CloudGatewayMediaAnnotationClient::new(
        base_url,
        "testtoken".to_string(),
        "test-model".to_string(),
    );

    let payload = client
        .annotate_image("en", "image/jpeg", b"img")
        .expect("annotate");

    assert_eq!(
        payload
            .get("summary")
            .and_then(|v| v.as_str())
            .unwrap_or_default(),
        "detached cat"
    );
    assert_eq!(
        payload
            .get("full_text")
            .and_then(|v| v.as_str())
            .unwrap_or_default(),
        "detached cat"
    );
    assert!(payload
        .get("secondloop_cloud_request_id")
        .and_then(|v| v.as_str())
        .unwrap_or_default()
        .starts_with("req_ma_"));
}

fn start_mock_server_for_detached_preflight_reuse() -> String {
    let listener = TcpListener::bind("127.0.0.1:0").expect("bind");
    let addr = listener.local_addr().expect("addr");

    std::thread::spawn(move || {
        let (mut stream1, _) = listener.accept().expect("accept first");
        let req1 = read_http_request(&mut stream1);
        assert_eq!(req1.method, "GET");
        let request_id = req1
            .path
            .strip_prefix("/v1/chat/jobs/")
            .expect("status path")
            .to_string();
        assert!(request_id.starts_with("req_ma_"));

        let body1 = json!({
            "error": "job_not_found",
        })
        .to_string();
        let resp1 = format!(
            "HTTP/1.1 404 Not Found\r\nContent-Type: application/json\r\nContent-Length: {}\r\nConnection: close\r\n\r\n{body1}",
            body1.len(),
        );
        stream1.write_all(resp1.as_bytes()).expect("write first");

        let (mut stream2, _) = listener.accept().expect("accept second");
        let req2 = read_http_request(&mut stream2);
        assert_eq!(req2.method, "POST");
        assert_eq!(req2.path, "/v1/chat/completions");
        assert_eq!(
            req2.headers
                .get("x-secondloop-request-id")
                .map(String::as_str),
            Some(request_id.as_str())
        );

        let first_payload_text =
            "{\"caption_long\":\"first run\",\"tag\":[],\"summary\":\"first run\",\"full_text\":\"first run\"}";
        let body2 = json!({
            "choices": [
                {
                    "message": {
                        "role": "assistant",
                        "content": first_payload_text,
                    }
                }
            ]
        })
        .to_string();
        let resp2 = format!(
            "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: {}\r\nConnection: close\r\n\r\n{body2}",
            body2.len(),
        );
        stream2.write_all(resp2.as_bytes()).expect("write second");

        let (mut stream3, _) = listener.accept().expect("accept third");
        let req3 = read_http_request(&mut stream3);
        assert_eq!(req3.method, "GET");
        assert_eq!(req3.path, format!("/v1/chat/jobs/{request_id}"));

        let detached_result_text =
            "{\"caption_long\":\"detached reuse\",\"tag\":[],\"summary\":\"detached reuse\",\"full_text\":\"detached reuse\"}";
        let body3 = json!({
            "ok": true,
            "request_id": request_id,
            "status": "completed",
            "result_text": detached_result_text,
            "result_truncated": false,
        })
        .to_string();
        let resp3 = format!(
            "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: {}\r\nConnection: close\r\n\r\n{body3}",
            body3.len(),
        );
        stream3.write_all(resp3.as_bytes()).expect("write third");

        listener
            .set_nonblocking(true)
            .expect("set listener nonblocking");
        for _ in 0..30 {
            match listener.accept() {
                Ok((_stream, _addr)) => {
                    panic!("unexpected extra request after detached preflight recovery")
                }
                Err(err) if err.kind() == std::io::ErrorKind::WouldBlock => {
                    std::thread::sleep(Duration::from_millis(10));
                }
                Err(err) => panic!("unexpected accept error: {err}"),
            }
        }
    });

    format!("http://{addr}")
}

#[test]
fn cloud_gateway_media_annotation_reuses_detached_result_before_resending_same_request() {
    let base_url = start_mock_server_for_detached_preflight_reuse();

    let client = secondloop_rust::media_annotation::CloudGatewayMediaAnnotationClient::new(
        base_url,
        "testtoken".to_string(),
        "test-model".to_string(),
    );

    let first = client
        .annotate_image("ocr_markdown:en", "application/pdf", b"%PDF-1.4")
        .expect("first annotate");
    assert_eq!(
        first
            .get("full_text")
            .and_then(|v| v.as_str())
            .unwrap_or_default(),
        "first run"
    );
    let first_request_id = first
        .get("secondloop_cloud_request_id")
        .and_then(|v| v.as_str())
        .unwrap_or_default()
        .to_string();
    assert!(first_request_id.starts_with("req_ma_"));

    let second = client
        .annotate_image("ocr_markdown:en", "application/pdf", b"%PDF-1.4")
        .expect("second annotate");
    assert_eq!(
        second
            .get("full_text")
            .and_then(|v| v.as_str())
            .unwrap_or_default(),
        "detached reuse"
    );
    assert_eq!(
        second
            .get("secondloop_cloud_request_id")
            .and_then(|v| v.as_str())
            .unwrap_or_default(),
        first_request_id
    );
}
