use std::io::{Read, Write};
use std::net::{TcpListener, TcpStream};

fn read_http_request_head(stream: &mut TcpStream) {
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
}

fn start_mock_server_with_truncated_sse_after_done() -> String {
    let listener = TcpListener::bind("127.0.0.1:0").expect("bind");
    let addr = listener.local_addr().expect("addr");

    std::thread::spawn(move || {
        let (mut stream, _) = listener.accept().expect("accept");
        read_http_request_head(&mut stream);

        let body = concat!(
            "data: {\"choices\":[{\"delta\":{\"content\":\"{\\\"caption_long\\\":\\\"a cat\\\",\\\"tags\\\":[],\\\"ocr_text\\\":null}\"}}]}\n\n",
            "data: [DONE]\n\n",
        );

        let declared_len = body.len() + 64;
        let headers = format!(
            "HTTP/1.1 200 OK\r\nContent-Type: text/event-stream\r\nContent-Length: {declared_len}\r\nConnection: close\r\n\r\n"
        );

        let _ = stream.write_all(headers.as_bytes());
        let _ = stream.write_all(body.as_bytes());
    });

    format!("http://{addr}")
}

#[test]
fn cloud_gateway_media_annotation_succeeds_when_sse_stream_ends_after_done() {
    let base_url = start_mock_server_with_truncated_sse_after_done();

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
            .get("caption_long")
            .and_then(|v| v.as_str())
            .unwrap_or_default(),
        "a cat"
    );
}
