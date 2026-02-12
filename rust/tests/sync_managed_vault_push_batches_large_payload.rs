use std::io::{Read, Write};
use std::net::{TcpListener, TcpStream};
use std::sync::mpsc;
use std::sync::{Arc, Mutex};
use std::thread;
use std::time::Duration;

use secondloop_rust::auth;
use secondloop_rust::crypto::{derive_root_key, KdfParams};
use secondloop_rust::db;
use secondloop_rust::sync;

#[derive(Default)]
struct ServerState {
    push_calls: usize,
    max_ops_per_push: usize,
    next_expected_seq: i64,
}

fn read_request(stream: &mut TcpStream) -> (String, String, Vec<u8>) {
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

    let mut content_length: usize = 0;
    for line in lines {
        let line = line.trim();
        if line.is_empty() {
            break;
        }
        if let Some((k, v)) = line.split_once(':') {
            if k.eq_ignore_ascii_case("content-length") {
                content_length = v.trim().parse::<usize>().unwrap_or(0);
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

    (method, path, body)
}

fn write_json_response(stream: &mut TcpStream, status: u16, body: serde_json::Value) {
    let body_str = body.to_string();
    let status_text = match status {
        200 => "OK",
        400 => "Bad Request",
        404 => "Not Found",
        _ => "OK",
    };
    let resp = format!(
        "HTTP/1.1 {status} {status_text}\r\nContent-Type: application/json\r\nContent-Length: {}\r\nConnection: close\r\n\r\n{body_str}",
        body_str.len()
    );
    stream.write_all(resp.as_bytes()).expect("write response");
}

fn start_mock_server() -> (
    String,
    mpsc::Sender<()>,
    Arc<Mutex<ServerState>>,
    thread::JoinHandle<()>,
) {
    let listener = TcpListener::bind("127.0.0.1:0").expect("bind");
    listener.set_nonblocking(true).expect("nonblocking");
    let addr = listener.local_addr().expect("local addr");

    let (stop_tx, stop_rx) = mpsc::channel::<()>();
    let state = Arc::new(Mutex::new(ServerState {
        next_expected_seq: 1,
        ..ServerState::default()
    }));
    let state_clone = Arc::clone(&state);

    let handle = thread::spawn(move || loop {
        if stop_rx.try_recv().is_ok() {
            break;
        }
        match listener.accept() {
            Ok((mut stream, _)) => {
                stream.set_nonblocking(false).expect("blocking stream");
                let (method, path, body) = read_request(&mut stream);

                if method != "POST" {
                    write_json_response(
                        &mut stream,
                        404,
                        serde_json::json!({ "error": "not_found" }),
                    );
                    continue;
                }

                let segments: Vec<&str> = path.split('/').filter(|s| !s.is_empty()).collect();
                if segments.len() < 4 || segments[0] != "v1" || segments[1] != "vaults" {
                    write_json_response(
                        &mut stream,
                        404,
                        serde_json::json!({ "error": "not_found" }),
                    );
                    continue;
                }

                let vault_id = segments[2];
                let tail = segments[3..].join("/");

                if vault_id != "v1" {
                    write_json_response(
                        &mut stream,
                        404,
                        serde_json::json!({ "error": "not_found" }),
                    );
                    continue;
                }

                if tail == "devices" {
                    let decoded: serde_json::Value =
                        serde_json::from_slice(&body).expect("devices json");
                    let device_id = decoded
                        .get("device_id")
                        .and_then(|v| v.as_str())
                        .unwrap_or("dev")
                        .to_string();
                    write_json_response(
                        &mut stream,
                        200,
                        serde_json::json!({
                            "device_id": device_id,
                            "ws_url": "wss://example.test/events",
                            "sse_url": "https://example.test/events"
                        }),
                    );
                    continue;
                }

                if tail == "ops:push" {
                    let decoded: serde_json::Value =
                        serde_json::from_slice(&body).expect("push json");
                    let ops = decoded
                        .get("ops")
                        .and_then(|v| v.as_array())
                        .expect("ops array");
                    assert!(!ops.is_empty(), "expected non-empty ops");

                    let mut st = state_clone.lock().expect("lock");
                    st.push_calls += 1;
                    st.max_ops_per_push = st.max_ops_per_push.max(ops.len());

                    let first_seq = ops[0].get("seq").and_then(|v| v.as_i64()).unwrap_or(0);
                    assert_eq!(first_seq, st.next_expected_seq);

                    let mut max_seq = 0i64;
                    for op in ops {
                        let seq = op.get("seq").and_then(|v| v.as_i64()).unwrap_or(0);
                        max_seq = max_seq.max(seq);
                    }
                    st.next_expected_seq = max_seq + 1;

                    write_json_response(
                        &mut stream,
                        200,
                        serde_json::json!({ "accepted": ops.len(), "max_seq": max_seq }),
                    );
                    continue;
                }

                write_json_response(
                    &mut stream,
                    404,
                    serde_json::json!({ "error": "not_found" }),
                );
            }
            Err(e) if e.kind() == std::io::ErrorKind::WouldBlock => {
                thread::sleep(Duration::from_millis(5));
            }
            Err(e) => panic!("accept failed: {e}"),
        }
    });

    (format!("http://{}", addr), stop_tx, state, handle)
}

#[test]
fn managed_vault_push_ops_only_splits_large_payload_into_batches() {
    let (base_url, stop_tx, state, handle) = start_mock_server();
    let vault_id = "v1".to_string();
    let id_token = "test_uid".to_string();

    let temp = tempfile::tempdir().expect("tempdir");
    let app_dir = temp.path().join("secondloop_a");
    let key = auth::init_master_password(&app_dir, "pw-a", KdfParams::for_test()).expect("init A");
    let conn = db::open(&app_dir).expect("open A db");

    for i in 0..510 {
        let title = format!("Conversation {i}");
        let _ = db::create_conversation(&conn, &key, &title).expect("create conversation");
    }

    let sync_key = derive_root_key(
        "sync-passphrase",
        b"secondloop-sync1",
        &KdfParams::for_test(),
    )
    .expect("derive sync key");

    let pushed =
        sync::managed_vault::push_ops_only(&conn, &key, &sync_key, &base_url, &vault_id, &id_token)
            .expect("push");
    assert_eq!(pushed, 510);

    let st = state.lock().expect("lock");
    assert!(st.push_calls >= 3, "expected multiple push requests");
    assert!(
        st.max_ops_per_push <= 200,
        "expected each push request to be capped"
    );

    let _ = stop_tx.send(());
    handle.join().expect("join");
}
