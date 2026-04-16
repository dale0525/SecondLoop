use std::io::{Read, Write};
use std::net::{TcpListener, TcpStream};
use std::sync::{Arc, Mutex};
use std::thread;

use secondloop_rust::{db, sync};
use tempfile::tempdir;

#[derive(Default)]
struct PullRecoveryState {
    initial_registered_device_id: Option<String>,
    first_pull_device_id: Option<String>,
    rotated_registered_device_id: Option<String>,
    second_pull_device_id: Option<String>,
}

fn read_http_request(stream: &mut TcpStream) -> (String, String, Vec<u8>) {
    let mut buf = Vec::new();
    let mut tmp = [0u8; 1024];
    let header_end = loop {
        let n = stream.read(&mut tmp).expect("read request");
        assert!(n > 0, "unexpected eof while reading request");
        buf.extend_from_slice(&tmp[..n]);
        if let Some(pos) = buf.windows(4).position(|w| w == b"\r\n\r\n") {
            break pos + 4;
        }
    };

    let headers = String::from_utf8_lossy(&buf[..header_end]).to_string();
    let content_length = headers
        .lines()
        .find_map(|line| {
            let (name, value) = line.split_once(':')?;
            if name.eq_ignore_ascii_case("content-length") {
                value.trim().parse::<usize>().ok()
            } else {
                None
            }
        })
        .unwrap_or(0);

    let mut body = buf[header_end..].to_vec();
    while body.len() < content_length {
        let n = stream.read(&mut tmp).expect("read request body");
        assert!(n > 0, "unexpected eof while reading request body");
        body.extend_from_slice(&tmp[..n]);
    }

    let first_line = headers.lines().next().unwrap_or("");
    let mut parts = first_line.split_whitespace();
    let method = parts.next().unwrap_or("").to_string();
    let path = parts.next().unwrap_or("").to_string();
    (method, path, body)
}

fn respond_json(stream: &mut TcpStream, status_line: &str, body: &str) {
    let response = format!(
        "{status_line}\r\nContent-Type: application/json\r\nContent-Length: {}\r\nConnection: close\r\n\r\n{}",
        body.len(),
        body
    );
    stream
        .write_all(response.as_bytes())
        .expect("write json response");
}

#[test]
fn managed_vault_pull_recovers_from_forbidden_v2_requester_device_by_rotating_local_device_id() {
    let dir = tempdir().expect("tempdir");
    let conn = db::open(dir.path()).expect("open");
    conn.execute(
        r#"INSERT INTO kv(key, value) VALUES ('device_id', 'stale-device')"#,
        [],
    )
    .expect("seed device id");

    let state = Arc::new(Mutex::new(PullRecoveryState::default()));
    let state_clone = Arc::clone(&state);
    let listener = TcpListener::bind("127.0.0.1:0").expect("bind");
    let addr = listener.local_addr().expect("local addr");

    let handle = thread::spawn(move || {
        for step in 0..5 {
            let (mut stream, _) = listener.accept().expect("accept");
            let (method, path, body) = read_http_request(&mut stream);
            let parsed: serde_json::Value =
                serde_json::from_slice(&body).expect("parse request body");
            match (step, method.as_str(), path.as_str()) {
                (0, "POST", "/v1/vaults/v1/devices") => {
                    state_clone
                        .lock()
                        .expect("lock")
                        .initial_registered_device_id =
                        parsed["device_id"].as_str().map(str::to_string);
                    respond_json(
                        &mut stream,
                        "HTTP/1.1 200 OK",
                        &format!(
                            r#"{{"device_id":"{}"}}"#,
                            parsed["device_id"].as_str().unwrap_or("")
                        ),
                    );
                }
                (1, "POST", "/v1/vaults/v1/ops:pull_bin_v2") => {
                    respond_json(
                        &mut stream,
                        "HTTP/1.1 404 Not Found",
                        r#"{"error":"not_found"}"#,
                    );
                }
                (2, "POST", "/v1/vaults/v1/ops:pull_v2") => {
                    state_clone.lock().expect("lock").first_pull_device_id =
                        parsed["device_id"].as_str().map(str::to_string);
                    respond_json(
                        &mut stream,
                        "HTTP/1.1 403 Forbidden",
                        r#"{"error":"forbidden"}"#,
                    );
                }
                (3, "POST", "/v1/vaults/v1/devices") => {
                    state_clone
                        .lock()
                        .expect("lock")
                        .rotated_registered_device_id =
                        parsed["device_id"].as_str().map(str::to_string);
                    respond_json(
                        &mut stream,
                        "HTTP/1.1 200 OK",
                        &format!(
                            r#"{{"device_id":"{}"}}"#,
                            parsed["device_id"].as_str().unwrap_or("")
                        ),
                    );
                }
                (4, "POST", "/v1/vaults/v1/ops:pull_v2") => {
                    state_clone.lock().expect("lock").second_pull_device_id =
                        parsed["device_id"].as_str().map(str::to_string);
                    respond_json(
                        &mut stream,
                        "HTTP/1.1 200 OK",
                        r#"{"protocol_version":2,"generation_id":"generation-v2","checkpoint_token":"checkpoint-v2","has_more":false,"reseed_required":false,"history_lower_bound":{},"ops":[]}"#,
                    );
                    return;
                }
                _ => panic!("unexpected request: step={step} method={method} path={path}"),
            }
        }
        panic!("expected exactly 5 requests");
    });

    let pulled = sync::managed_vault::pull(
        &conn,
        &[3u8; 32],
        &[4u8; 32],
        &format!("http://{addr}"),
        "v1",
        "token",
    )
    .expect("pull succeeds");
    assert_eq!(pulled, 0);

    let final_device_id = conn
        .query_row("SELECT value FROM kv WHERE key = 'device_id'", [], |row| {
            row.get::<_, String>(0)
        })
        .expect("read device id");
    let state = state.lock().expect("lock");
    assert_eq!(
        state.initial_registered_device_id.as_deref(),
        Some("stale-device")
    );
    assert_eq!(state.first_pull_device_id.as_deref(), Some("stale-device"));
    let registered_device_id = state
        .rotated_registered_device_id
        .clone()
        .expect("registered device id");
    assert_ne!(registered_device_id, "stale-device");
    assert_eq!(
        state.second_pull_device_id.as_deref(),
        Some(registered_device_id.as_str())
    );
    assert_eq!(final_device_id, registered_device_id);
    drop(state);
    handle.join().expect("join");
}
