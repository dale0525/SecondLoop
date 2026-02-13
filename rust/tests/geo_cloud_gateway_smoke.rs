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
    let mut parts = request_line.split_whitespace();
    let method = parts.next().unwrap_or_default().to_string();
    let path = parts.next().unwrap_or_default().to_string();

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

    let mut body_bytes = rest[4..].to_vec(); // skip \r\n\r\n
    while body_bytes.len() < content_length {
        let n = stream.read(&mut tmp).expect("read body");
        if n == 0 {
            break;
        }
        body_bytes.extend_from_slice(&tmp[..n]);
    }
    body_bytes.truncate(content_length);

    let body = String::from_utf8_lossy(&body_bytes).to_string();
    CapturedRequest {
        method,
        path,
        headers,
        body,
    }
}

fn start_mock_server() -> (String, mpsc::Receiver<CapturedRequest>) {
    let listener = TcpListener::bind("127.0.0.1:0").expect("bind");
    let addr = listener.local_addr().expect("addr");
    let (tx, rx) = mpsc::channel::<CapturedRequest>();

    std::thread::spawn(move || {
        for stream in listener.incoming().take(3) {
            let mut stream = stream.expect("accept");
            let req = read_http_request(&mut stream);

            let path = req.path.clone();
            tx.send(req).expect("send req");

            let (status_code, status_text, body) = if path.starts_with("/v1/geo/reverse") {
                (
                    200,
                    "OK",
                    r#"{"country_code":"US","display_name":"Seattle"}"#,
                )
            } else if path.starts_with("/v1/chat/jobs/") {
                (404, "Not Found", r#"{"error":"job_not_found"}"#)
            } else if path == "/v1/chat/completions" {
                (
                    200,
                    "OK",
                    r#"{"choices":[{"message":{"role":"assistant","content":"{\"summary\":\"a cat\",\"tag\":[\"cat\"],\"full_text\":\"\"}"}}]}"#,
                )
            } else {
                (404, "Not Found", r#"{"error":"not found"}"#)
            };

            let resp = format!(
                "HTTP/1.1 {status_code} {status_text}\r\nContent-Type: application/json\r\nContent-Length: {}\r\n\r\n{body}",
                body.len()
            );
            let _ = stream.write_all(resp.as_bytes());
        }
    });

    (format!("http://{addr}"), rx)
}

#[test]
fn geo_cloud_gateway_smoke() {
    let (base_url, rx) = start_mock_server();
    let id_token = "testtoken".to_string();

    let geo = secondloop_rust::geo::CloudGatewayGeoClient::new(base_url.clone(), id_token.clone());
    let geo_payload = geo.reverse_geocode(1.0, 2.0, "en").expect("geo reverse");
    assert_eq!(
        geo_payload
            .get("display_name")
            .and_then(|v| v.as_str())
            .unwrap_or_default(),
        "Seattle"
    );

    let ann = secondloop_rust::media_annotation::CloudGatewayMediaAnnotationClient::new(
        base_url.clone(),
        id_token.clone(),
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
    let tags = ann_payload
        .get("tag")
        .and_then(|v| v.as_array())
        .expect("tag array");
    assert_eq!(tags.len(), 1);
    assert_eq!(tags[0].as_str().unwrap_or_default(), "cat");

    let req1 = rx.recv().expect("req1");
    let req2 = rx.recv().expect("req2");
    let req3 = rx.recv().expect("req3");
    let requests = [req1, req2, req3];

    let geo_req = requests
        .iter()
        .find(|r| r.path.starts_with("/v1/geo/reverse"))
        .expect("geo request");
    assert_eq!(geo_req.method, "GET");
    assert_eq!(
        geo_req.headers.get("authorization").map(String::as_str),
        Some("Bearer testtoken")
    );
    assert_eq!(
        geo_req
            .headers
            .get("x-secondloop-purpose")
            .map(String::as_str),
        Some("geo_reverse")
    );
    assert!(geo_req.path.contains("lat=1"));
    assert!(geo_req.path.contains("lon=2"));
    assert!(geo_req.path.contains("lang=en"));

    let preflight_req = requests
        .iter()
        .find(|r| r.path.starts_with("/v1/chat/jobs/"))
        .expect("detached preflight request");
    assert_eq!(preflight_req.method, "GET");
    assert_eq!(
        preflight_req
            .headers
            .get("authorization")
            .map(String::as_str),
        Some("Bearer testtoken")
    );

    let ann_req = requests
        .iter()
        .find(|r| r.path == "/v1/chat/completions")
        .expect("annotation request");
    assert_eq!(ann_req.method, "POST");
    assert_eq!(
        ann_req.headers.get("authorization").map(String::as_str),
        Some("Bearer testtoken")
    );
    assert_eq!(
        ann_req
            .headers
            .get("x-secondloop-purpose")
            .map(String::as_str),
        Some("media_annotation")
    );
    let request_id = ann_req
        .headers
        .get("x-secondloop-request-id")
        .expect("request id");
    assert!(request_id.starts_with("req_ma_"));
    assert!(preflight_req.path.ends_with(request_id));
    assert!(ann_req.body.contains("\"model\":\"test-model\""));
    assert!(ann_req.body.contains("data:image/jpeg;base64,"));
}
