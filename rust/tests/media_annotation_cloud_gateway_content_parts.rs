use std::io::{Read, Write};
use std::net::{TcpListener, TcpStream};
use std::sync::mpsc;

#[derive(Debug)]
struct CapturedRequest {
    method: String,
    path: String,
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
    let (head, _) = buf.split_at(header_end);
    let head = String::from_utf8_lossy(head);

    let mut lines = head.split("\r\n");
    let request_line = lines.next().expect("request line");
    let mut parts = request_line.split_whitespace();
    let method = parts.next().unwrap_or_default().to_string();
    let path = parts.next().unwrap_or_default().to_string();

    CapturedRequest { method, path }
}

fn start_mock_server() -> (String, mpsc::Receiver<CapturedRequest>) {
    let listener = TcpListener::bind("127.0.0.1:0").expect("bind");
    let addr = listener.local_addr().expect("addr");
    let (tx, rx) = mpsc::channel::<CapturedRequest>();

    std::thread::spawn(move || {
        for stream in listener.incoming().take(1) {
            let mut stream = stream.expect("accept");
            let req = read_http_request(&mut stream);
            tx.send(req).expect("send req");

            let body = r#"{"choices":[{"message":{"role":"assistant","content":[{"type":"text","text":"{\"caption_long\":\"a cat\",\"tags\":[\"cat\"],\"ocr_text\":null}"}]}}]}"#;
            let resp = format!(
                "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: {}\r\n\r\n{body}",
                body.len()
            );
            let _ = stream.write_all(resp.as_bytes());
        }
    });

    (format!("http://{addr}"), rx)
}

#[test]
fn cloud_gateway_media_annotation_parses_content_parts() {
    let (base_url, rx) = start_mock_server();

    let ann = secondloop_rust::media_annotation::CloudGatewayMediaAnnotationClient::new(
        base_url.clone(),
        "testtoken".to_string(),
        "test-model".to_string(),
    );
    let ann_payload = ann
        .annotate_image("en", "image/jpeg", b"img")
        .expect("annotate image");
    assert_eq!(
        ann_payload
            .get("caption_long")
            .and_then(|v| v.as_str())
            .unwrap_or_default(),
        "a cat"
    );

    let req = rx.recv().expect("request");
    assert_eq!(req.method, "POST");
    assert_eq!(req.path, "/v1/chat/completions");
}
