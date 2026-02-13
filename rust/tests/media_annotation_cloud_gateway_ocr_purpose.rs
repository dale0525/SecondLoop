use std::collections::HashMap;
use std::io::{Read, Write};
use std::net::{TcpListener, TcpStream};
use std::sync::mpsc;

#[derive(Debug)]
struct CapturedRequest {
    method: String,
    path: String,
    headers: HashMap<String, String>,
    body: String,
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
    body_bytes.truncate(content_length);

    CapturedRequest {
        method,
        path,
        headers,
        body: String::from_utf8_lossy(&body_bytes).to_string(),
    }
}

fn start_mock_server() -> (String, mpsc::Receiver<CapturedRequest>) {
    let listener = TcpListener::bind("127.0.0.1:0").expect("bind");
    let addr = listener.local_addr().expect("addr");
    let (tx, rx) = mpsc::channel::<CapturedRequest>();

    std::thread::spawn(move || {
        let (mut stream1, _) = listener.accept().expect("accept first");
        let status_req = read_http_request(&mut stream1);
        assert_eq!(status_req.method, "GET");
        assert!(status_req.path.starts_with("/v1/chat/jobs/"));

        let not_found_body = r##"{"error":"job_not_found"}"##;
        let not_found_resp = format!(
            "HTTP/1.1 404 Not Found\r\nContent-Type: application/json\r\nContent-Length: {}\r\nConnection: close\r\n\r\n{not_found_body}",
            not_found_body.len()
        );
        let _ = stream1.write_all(not_found_resp.as_bytes());

        let (mut stream2, _) = listener.accept().expect("accept second");
        let req = read_http_request(&mut stream2);
        tx.send(req).expect("send req");

        let body = r##"{"choices":[{"message":{"role":"assistant","content":"{\"caption_long\":\"\",\"tags\":[],\"ocr_text\":\"# Report\\n\\nTotal: 42\"}"}}]}"##;
        let resp = format!(
            "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: {}\r\n\r\n{body}",
            body.len()
        );
        let _ = stream2.write_all(resp.as_bytes());
    });

    (format!("http://{addr}"), rx)
}

#[test]
fn cloud_gateway_multimodal_ocr_uses_ask_ai_purpose() {
    let (base_url, rx) = start_mock_server();
    let client = secondloop_rust::media_annotation::CloudGatewayMediaAnnotationClient::new(
        base_url,
        "testtoken".to_string(),
        "test-model".to_string(),
    );

    let payload = client
        .annotate_image("ocr_markdown:en", "application/pdf", b"%PDF-1.4")
        .expect("annotate");
    assert_eq!(
        payload
            .get("ocr_text")
            .and_then(|v| v.as_str())
            .unwrap_or_default(),
        "# Report\n\nTotal: 42"
    );
    assert_eq!(
        payload
            .get("summary")
            .and_then(|v| v.as_str())
            .unwrap_or_default(),
        ""
    );
    assert_eq!(
        payload
            .get("full_text")
            .and_then(|v| v.as_str())
            .unwrap_or_default(),
        "# Report\n\nTotal: 42"
    );
    assert_eq!(
        payload
            .get("tag")
            .and_then(|v| v.as_array())
            .map(|v| v.len())
            .unwrap_or(usize::MAX),
        0
    );

    let req = rx.recv().expect("request");
    assert_eq!(req.method, "POST");
    assert_eq!(req.path, "/v1/chat/completions");
    assert_eq!(
        req.headers.get("x-secondloop-purpose").map(String::as_str),
        Some("ask_ai")
    );
    let request_id = req
        .headers
        .get("x-secondloop-request-id")
        .expect("request id header");
    assert!(request_id.starts_with("req_"));
    assert_eq!(
        payload
            .get("secondloop_cloud_request_id")
            .and_then(|v| v.as_str())
            .unwrap_or_default(),
        request_id
    );
    assert_eq!(
        req.headers
            .get("x-secondloop-detach-policy")
            .map(String::as_str),
        Some("continue_on_disconnect")
    );
    assert!(req.body.contains("data:application/pdf;base64,"));
    assert!(req.body.contains("full_text"));
    assert!(req.body.contains("summary"));
    assert!(req.body.contains("tag"));
    assert!(req.body.contains("\"stream\":true"));
}
