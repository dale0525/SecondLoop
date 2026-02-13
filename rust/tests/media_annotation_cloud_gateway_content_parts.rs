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
        let (mut stream1, _) = listener.accept().expect("accept first");
        let status_req = read_http_request(&mut stream1);
        assert_eq!(status_req.method, "GET");
        assert!(status_req.path.starts_with("/v1/chat/jobs/"));

        let not_found_body = r##"{"error":"job_not_found"}"##;
        let not_found_resp = format!(
            "HTTP/1.1 404 Not Found\r\nContent-Type: application/json\r\nContent-Length: {}\r\nConnection: close\r\n\r\n{not_found_body}",
            not_found_body.len(),
        );
        let _ = stream1.write_all(not_found_resp.as_bytes());

        let (mut stream2, _) = listener.accept().expect("accept second");
        let req = read_http_request(&mut stream2);
        tx.send(req).expect("send req");

        let body = r#"{"choices":[{"message":{"role":"assistant","content":[{"type":"text","text":"{\"caption_long\":\"a cat\",\"tags\":[\"cat\"],\"ocr_text\":null}"}]}}]}"#;
        let resp = format!(
            "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: {}\r\n\r\n{body}",
            body.len()
        );
        let _ = stream2.write_all(resp.as_bytes());
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
    assert_eq!(
        ann_payload
            .get("summary")
            .and_then(|v| v.as_str())
            .unwrap_or_default(),
        "a cat"
    );
    assert_eq!(
        ann_payload
            .get("full_text")
            .and_then(|v| v.as_str())
            .unwrap_or_default(),
        ""
    );
    let tag_values = ann_payload
        .get("tag")
        .and_then(|v| v.as_array())
        .expect("tag array");
    assert_eq!(tag_values.len(), 1);
    assert_eq!(tag_values[0].as_str().unwrap_or_default(), "cat");

    let req = rx.recv().expect("request");
    assert_eq!(req.method, "POST");
    assert_eq!(req.path, "/v1/chat/completions");
}
