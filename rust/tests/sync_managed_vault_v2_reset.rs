use std::io::{Read, Write};
use std::net::{TcpListener, TcpStream};
use std::sync::mpsc;
use std::sync::{Arc, Mutex};
use std::thread;
use std::time::Duration;

use secondloop_rust::sync;

#[derive(Default)]
struct ResetState {
    requests: Vec<String>,
}

fn read_request(stream: &mut TcpStream) -> (String, String, String, Vec<u8>) {
    let mut buf = Vec::<u8>::new();
    let mut header_end = None;
    let mut tmp = [0u8; 4096];

    while header_end.is_none() {
        let n = stream.read(&mut tmp).expect("read");
        assert!(n > 0, "unexpected EOF");
        buf.extend_from_slice(&tmp[..n]);
        header_end = buf.windows(4).position(|w| w == b"\r\n\r\n").map(|p| p + 4);
    }

    let header_end = header_end.expect("header end");
    let (headers, rest) = buf.split_at(header_end);
    let headers_str = String::from_utf8_lossy(headers).to_string();
    let mut lines = headers_str.lines();
    let request_line = lines.next().expect("request line");
    let mut parts = request_line.split_whitespace();
    let method = parts.next().unwrap_or("").to_string();
    let path = parts.next().unwrap_or("").to_string();

    let mut content_length = 0usize;
    for line in lines {
        if let Some((name, value)) = line.split_once(':') {
            if name.eq_ignore_ascii_case("content-length") {
                content_length = value.trim().parse::<usize>().unwrap_or(0);
            }
        }
    }

    let mut body = rest.to_vec();
    while body.len() < content_length {
        let n = stream.read(&mut tmp).expect("read body");
        assert!(n > 0, "unexpected EOF body");
        body.extend_from_slice(&tmp[..n]);
    }
    body.truncate(content_length);

    (headers_str, method, path, body)
}

fn write_json_response(stream: &mut TcpStream, status: u16, body: serde_json::Value) {
    let body_str = body.to_string();
    let status_text = match status {
        200 => "OK",
        404 => "Not Found",
        _ => "OK",
    };
    let response = format!(
        "HTTP/1.1 {status} {status_text}\r\nContent-Type: application/json\r\nContent-Length: {}\r\nConnection: close\r\n\r\n{body_str}",
        body_str.len()
    );
    stream
        .write_all(response.as_bytes())
        .expect("write response");
}

fn start_reset_server() -> (
    String,
    mpsc::Sender<()>,
    Arc<Mutex<ResetState>>,
    thread::JoinHandle<()>,
) {
    let listener = TcpListener::bind("127.0.0.1:0").expect("bind");
    listener.set_nonblocking(true).expect("nonblocking");
    let addr = listener.local_addr().expect("local addr");

    let (stop_tx, stop_rx) = mpsc::channel::<()>();
    let state = Arc::new(Mutex::new(ResetState::default()));
    let state_clone = Arc::clone(&state);

    let handle = thread::spawn(move || loop {
        if stop_rx.try_recv().is_ok() {
            break;
        }
        match listener.accept() {
            Ok((mut stream, _)) => {
                stream.set_nonblocking(false).expect("blocking stream");
                let (raw_headers, method, path, body) = read_request(&mut stream);
                state_clone
                    .lock()
                    .expect("lock")
                    .requests
                    .push(format!("{raw_headers}{}", String::from_utf8_lossy(&body)));

                match (method.as_str(), path.as_str()) {
                    ("POST", "/v2/vaults/v1/sync/reset") => write_json_response(
                        &mut stream,
                        200,
                        serde_json::json!({
                            "generation_id": "generation-reset",
                            "remote_latest_global_seq": 0,
                            "deleted_meta": 3,
                            "deleted_blobs": 2,
                        }),
                    ),
                    _ => write_json_response(
                        &mut stream,
                        404,
                        serde_json::json!({ "error": "not_found" }),
                    ),
                }
            }
            Err(error) if error.kind() == std::io::ErrorKind::WouldBlock => {
                thread::sleep(Duration::from_millis(5));
            }
            Err(error) => panic!("accept failed: {error}"),
        }
    });

    (format!("http://{addr}"), stop_tx, state, handle)
}

#[test]
fn managed_vault_clear_vault_prefers_v2_reset_endpoint() {
    let (base_url, stop_tx, state, handle) = start_reset_server();
    sync::managed_vault::clear_vault(&base_url, "v1", "test_uid").expect("clear vault");

    let requests = state.lock().expect("lock").requests.join("\n\n");
    assert!(requests.contains("/v2/vaults/v1/sync/reset"));
    assert!(!requests.contains("/v1/vaults/v1/ops:clear"));

    stop_tx.send(()).expect("stop");
    handle.join().expect("join");
}

#[test]
fn managed_vault_clear_vault_fails_when_v2_reset_is_unavailable() {
    let listener = TcpListener::bind("127.0.0.1:0").expect("bind");
    listener.set_nonblocking(true).expect("nonblocking");
    let addr = listener.local_addr().expect("local addr");

    let (stop_tx, stop_rx) = mpsc::channel::<()>();
    let requests = Arc::new(Mutex::new(Vec::<String>::new()));
    let requests_clone = Arc::clone(&requests);

    let handle = thread::spawn(move || loop {
        if stop_rx.try_recv().is_ok() {
            break;
        }
        match listener.accept() {
            Ok((mut stream, _)) => {
                stream.set_nonblocking(false).expect("blocking stream");
                let (raw_headers, method, path, body) = read_request(&mut stream);
                requests_clone
                    .lock()
                    .expect("lock")
                    .push(format!("{raw_headers}{}", String::from_utf8_lossy(&body)));

                match (method.as_str(), path.as_str()) {
                    ("POST", "/v2/vaults/v1/sync/reset") => write_json_response(
                        &mut stream,
                        404,
                        serde_json::json!({ "error": "not_found" }),
                    ),
                    _ => write_json_response(
                        &mut stream,
                        404,
                        serde_json::json!({ "error": "not_found" }),
                    ),
                }
            }
            Err(error) if error.kind() == std::io::ErrorKind::WouldBlock => {
                thread::sleep(Duration::from_millis(5));
            }
            Err(error) => panic!("accept failed: {error}"),
        }
    });

    let base_url = format!("http://{addr}");
    let err = sync::managed_vault::clear_vault(&base_url, "v1", "test_uid")
        .expect_err("v2 reset should be required");

    let joined = requests.lock().expect("lock").join("\n\n");
    assert!(joined.contains("/v2/vaults/v1/sync/reset"));
    assert!(!joined.contains("/v1/vaults/v1/ops:clear"));
    assert!(err.to_string().contains("HTTP 404"));

    stop_tx.send(()).expect("stop");
    handle.join().expect("join");
}
