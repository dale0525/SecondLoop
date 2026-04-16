use std::io::{Read, Write};
use std::net::{TcpListener, TcpStream};
use std::sync::mpsc;
use std::sync::{Arc, Mutex};
use std::thread;
use std::time::{Duration, SystemTime, UNIX_EPOCH};

use base64::engine::general_purpose::URL_SAFE_NO_PAD;
use base64::Engine as _;
use rusqlite::params;
use secondloop_rust::crypto::encrypt_bytes;
use secondloop_rust::db;
use secondloop_rust::sync;

#[derive(Debug, Clone)]
struct StoredOp {
    device_id: String,
    seq: i64,
    op_id: String,
    ciphertext_b64: String,
}

#[derive(Default)]
struct RepairLoopState {
    seen_since_values: Vec<i64>,
    pull_requests: usize,
}

fn now_ms() -> i64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .expect("now")
        .as_millis()
        .try_into()
        .expect("ms i64")
}

fn scope_id(base_url: &str, vault_id: &str) -> String {
    let raw = format!("managed_vault|{}|{}", base_url.trim(), vault_id.trim());
    URL_SAFE_NO_PAD.encode(raw.as_bytes())
}

fn set_kv_i64(conn: &rusqlite::Connection, key: &str, value: i64) {
    conn.execute(
        r#"INSERT INTO kv(key, value) VALUES (?1, ?2)
           ON CONFLICT(key) DO UPDATE SET value = excluded.value"#,
        params![key, value.to_string()],
    )
    .expect("set kv");
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

    let request_line = headers_str.lines().next().expect("request line");
    let mut parts = request_line.split_whitespace();
    let method = parts.next().unwrap_or("").to_string();
    let path = parts.next().unwrap_or("").to_string();

    let content_length = headers_str
        .lines()
        .find_map(|line| {
            let (key, value) = line.split_once(':')?;
            key.eq_ignore_ascii_case("content-length")
                .then(|| value.trim().parse::<usize>().ok())
                .flatten()
        })
        .unwrap_or(0);

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
        404 => "Not Found",
        503 => "Service Unavailable",
        _ => "OK",
    };
    let resp = format!(
        "HTTP/1.1 {status} {status_text}\r\nContent-Type: application/json\r\nContent-Length: {}\r\nConnection: close\r\n\r\n{body_str}",
        body_str.len()
    );
    stream.write_all(resp.as_bytes()).expect("write response");
}

fn synthetic_remote_op(sync_key: &[u8; 32], remote_device_id: &str, seq: i64) -> StoredOp {
    let op_id = format!("remote-op-{remote_device_id}-{seq}");
    let op_json = serde_json::json!({
        "op_id": op_id,
        "device_id": remote_device_id,
        "seq": seq,
        "ts_ms": now_ms(),
        "type": "conversation.upsert.v1",
        "payload": {
            "conversation_id": format!("conversation-{remote_device_id}-{seq}"),
            "title": format!("Recovered title {seq}"),
            "created_at_ms": now_ms(),
            "updated_at_ms": now_ms(),
        }
    });
    let plaintext = serde_json::to_vec(&op_json).expect("serialize op");
    let ciphertext = encrypt_bytes(
        sync_key,
        &plaintext,
        format!("sync.ops:{remote_device_id}:{seq}").as_bytes(),
    )
    .expect("encrypt op");
    StoredOp {
        device_id: remote_device_id.to_string(),
        seq,
        op_id,
        ciphertext_b64: base64::engine::general_purpose::STANDARD.encode(ciphertext),
    }
}

fn start_repair_loop_server(
    local_device_id: String,
    remote_device_id: String,
    repeated_op: StoredOp,
    repeated_max: i64,
) -> (
    String,
    mpsc::Sender<()>,
    Arc<Mutex<RepairLoopState>>,
    thread::JoinHandle<()>,
) {
    let listener = TcpListener::bind("127.0.0.1:0").expect("bind");
    listener.set_nonblocking(true).expect("nonblocking");
    let addr = listener.local_addr().expect("local addr");

    let (stop_tx, stop_rx) = mpsc::channel::<()>();
    let state = Arc::new(Mutex::new(RepairLoopState::default()));
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
                        serde_json::json!({ "error": "method_not_allowed" }),
                    );
                    continue;
                }

                let segments: Vec<&str> = path
                    .split('/')
                    .filter(|segment| !segment.is_empty())
                    .collect();
                if segments.len() < 4 || segments[0] != "v1" || segments[1] != "vaults" {
                    write_json_response(
                        &mut stream,
                        404,
                        serde_json::json!({ "error": "not_found" }),
                    );
                    continue;
                }
                let tail = segments[3..].join("/");

                if tail == "devices" {
                    write_json_response(
                        &mut stream,
                        200,
                        serde_json::json!({
                            "device_id": local_device_id,
                            "ws_url": "wss://example.test/events",
                            "sse_url": "https://example.test/events"
                        }),
                    );
                    continue;
                }

                if tail == "ops:pull_bin" {
                    write_json_response(
                        &mut stream,
                        404,
                        serde_json::json!({ "error": "not_found" }),
                    );
                    continue;
                }

                if tail == "ops:pull" {
                    let decoded: serde_json::Value =
                        serde_json::from_slice(&body).expect("pull json");
                    let since_seq = decoded["since"][remote_device_id.as_str()]
                        .as_i64()
                        .unwrap_or(0);

                    let mut snapshot = state_clone.lock().expect("lock");
                    snapshot.pull_requests += 1;
                    snapshot.seen_since_values.push(since_seq);
                    let pull_requests = snapshot.pull_requests;
                    drop(snapshot);

                    if pull_requests <= 2 && (since_seq == 174 || since_seq == 0) {
                        write_json_response(
                            &mut stream,
                            200,
                            serde_json::json!({
                                "ops": [{
                                    "device_id": repeated_op.device_id,
                                    "seq": repeated_op.seq,
                                    "op_id": repeated_op.op_id,
                                    "ciphertext_b64": repeated_op.ciphertext_b64,
                                }],
                                "next": { remote_device_id.clone(): repeated_op.seq },
                                "max": { remote_device_id.clone(): repeated_max }
                            }),
                        );
                    } else {
                        write_json_response(
                            &mut stream,
                            503,
                            serde_json::json!({ "error": "loop_detected" }),
                        );
                    }
                    continue;
                }

                write_json_response(
                    &mut stream,
                    404,
                    serde_json::json!({ "error": "not_found" }),
                );
            }
            Err(error) if error.kind() == std::io::ErrorKind::WouldBlock => {
                thread::sleep(Duration::from_millis(5));
            }
            Err(error) => panic!("accept failed: {error}"),
        }
    });

    (format!("http://{}", addr), stop_tx, state, handle)
}

#[test]
fn managed_vault_pull_stops_after_repairing_the_same_short_page_once() {
    let db_key = [101u8; 32];
    let sync_key = [102u8; 32];
    let local_device_id = "local-loop-guard-device";
    let remote_device_id = "remote-loop-guard-device";
    let repeated_op = synthetic_remote_op(&sync_key, remote_device_id, 262);
    let (base_url, stop_tx, state, handle) = start_repair_loop_server(
        local_device_id.to_string(),
        remote_device_id.to_string(),
        repeated_op,
        762,
    );

    let dir = tempfile::tempdir().expect("tempdir");
    let conn = db::open(dir.path()).expect("open");
    conn.execute(
        r#"INSERT INTO kv(key, value) VALUES ('device_id', ?1)"#,
        params![local_device_id],
    )
    .expect("set local device id");

    let scope_id = scope_id(&base_url, "test-vault");
    set_kv_i64(
        &conn,
        &format!("managed_vault.last_pulled_seq:{scope_id}:{remote_device_id}"),
        174,
    );

    let error = sync::managed_vault::pull(
        &conn,
        &db_key,
        &sync_key,
        &base_url,
        "test-vault",
        "test-token",
    )
    .expect_err("repeated repair should stop with an error");
    assert!(
        error.to_string().contains("repeated remote-ahead repair"),
        "expected repeated-repair error, got {error:#}"
    );

    let snapshot = state.lock().expect("lock");
    assert_eq!(snapshot.seen_since_values, vec![174, 0]);
    drop(snapshot);

    let _ = stop_tx.send(());
    handle.join().expect("join");
}

#[test]
fn managed_vault_pull_with_progress_stops_after_repairing_the_same_short_page_once() {
    let db_key = [111u8; 32];
    let sync_key = [112u8; 32];
    let local_device_id = "local-progress-loop-guard-device";
    let remote_device_id = "remote-progress-loop-guard-device";
    let repeated_op = synthetic_remote_op(&sync_key, remote_device_id, 262);
    let (base_url, stop_tx, state, handle) = start_repair_loop_server(
        local_device_id.to_string(),
        remote_device_id.to_string(),
        repeated_op,
        762,
    );

    let dir = tempfile::tempdir().expect("tempdir");
    let conn = db::open(dir.path()).expect("open");
    conn.execute(
        r#"INSERT INTO kv(key, value) VALUES ('device_id', ?1)"#,
        params![local_device_id],
    )
    .expect("set local device id");

    let scope_id = scope_id(&base_url, "test-vault");
    set_kv_i64(
        &conn,
        &format!("managed_vault.last_pulled_seq:{scope_id}:{remote_device_id}"),
        174,
    );

    let mut seen_progress = Vec::new();
    let error = sync::managed_vault::pull_with_progress(
        &conn,
        &db_key,
        &sync_key,
        &base_url,
        "test-vault",
        "test-token",
        &mut |done, total| seen_progress.push((done, total)),
    )
    .expect_err("repeated repair should stop with an error");
    assert!(
        error.to_string().contains("repeated remote-ahead repair"),
        "expected repeated-repair error, got {error:#}"
    );

    let snapshot = state.lock().expect("lock");
    assert_eq!(snapshot.seen_since_values, vec![174, 0]);
    drop(snapshot);

    let _ = stop_tx.send(());
    handle.join().expect("join");
}
