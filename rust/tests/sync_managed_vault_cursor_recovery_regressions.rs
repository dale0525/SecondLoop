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
    conversation_id: String,
}

#[derive(Default)]
struct RepeatedRecoveryState {
    delivered_first_repair: bool,
    delivered_second_repair: bool,
    seen_since_values: Vec<i64>,
}

#[derive(Default)]
struct ProgressRegressionState {
    delivered_repair: bool,
    seen_since_values: Vec<i64>,
}

#[derive(Default)]
struct TwoDeviceRecoveryState {
    first_since_values: Vec<i64>,
    stalled_since_values: Vec<i64>,
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

fn get_kv_i64(conn: &rusqlite::Connection, key: &str) -> Option<i64> {
    conn.query_row(
        r#"SELECT value FROM kv WHERE key = ?1"#,
        params![key],
        |row| row.get::<_, String>(0),
    )
    .ok()
    .and_then(|value| value.parse::<i64>().ok())
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
        _ => "OK",
    };
    let resp = format!(
        "HTTP/1.1 {status} {status_text}\r\nContent-Type: application/json\r\nContent-Length: {}\r\nConnection: close\r\n\r\n{body_str}",
        body_str.len()
    );
    stream.write_all(resp.as_bytes()).expect("write response");
}

fn synthetic_remote_op(
    sync_key: &[u8; 32],
    remote_device_id: &str,
    seq: i64,
    title: &str,
) -> StoredOp {
    let op_id = format!("remote-op-{remote_device_id}-{seq}");
    let conversation_id = format!("conversation-{remote_device_id}-{seq}");
    let op_json = serde_json::json!({
        "op_id": op_id,
        "device_id": remote_device_id,
        "seq": seq,
        "ts_ms": now_ms(),
        "type": "conversation.upsert.v1",
        "payload": {
            "conversation_id": conversation_id,
            "title": title,
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
        conversation_id,
    }
}

fn insert_raw_op(conn: &rusqlite::Connection, db_key: &[u8; 32], op: serde_json::Value) {
    let op_id = op["op_id"].as_str().expect("op_id").to_string();
    let device_id = op["device_id"].as_str().expect("device_id").to_string();
    let seq = op["seq"].as_i64().expect("seq");
    let created_at = op["ts_ms"].as_i64().expect("ts_ms");

    let plaintext = serde_json::to_vec(&op).expect("op json");
    let aad = format!("oplog.op_json:{op_id}");
    let blob = encrypt_bytes(db_key, &plaintext, aad.as_bytes()).expect("encrypt op");
    conn.execute(
        r#"INSERT INTO oplog(op_id, device_id, seq, op_json, created_at)
           VALUES (?1, ?2, ?3, ?4, ?5)"#,
        params![op_id, device_id, seq, blob, created_at],
    )
    .expect("insert oplog");
}

fn start_repeated_recovery_server(
    remote_device_id: String,
    first_op: StoredOp,
    second_op: StoredOp,
) -> (
    String,
    mpsc::Sender<()>,
    Arc<Mutex<RepeatedRecoveryState>>,
    thread::JoinHandle<()>,
) {
    let listener = TcpListener::bind("127.0.0.1:0").expect("bind");
    listener.set_nonblocking(true).expect("nonblocking");
    let addr = listener.local_addr().expect("local addr");

    let (stop_tx, stop_rx) = mpsc::channel::<()>();
    let state = Arc::new(Mutex::new(RepeatedRecoveryState::default()));
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

                let segments: Vec<&str> = path.split('/').filter(|s| !s.is_empty()).collect();
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
                            "device_id": "local-repeat-device",
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
                    snapshot.seen_since_values.push(since_seq);

                    let response = if since_seq == 174 {
                        serde_json::json!({
                            "ops": [],
                            "next": {},
                            "max": { remote_device_id.clone(): first_op.seq }
                        })
                    } else if since_seq == 0 && !snapshot.delivered_first_repair {
                        snapshot.delivered_first_repair = true;
                        serde_json::json!({
                            "ops": [{
                                "device_id": first_op.device_id,
                                "seq": first_op.seq,
                                "op_id": first_op.op_id,
                                "ciphertext_b64": first_op.ciphertext_b64,
                            }],
                            "next": { remote_device_id.clone(): first_op.seq },
                            "max": { remote_device_id.clone(): first_op.seq }
                        })
                    } else if since_seq == 300 {
                        serde_json::json!({
                            "ops": [],
                            "next": {},
                            "max": { remote_device_id.clone(): second_op.seq }
                        })
                    } else if since_seq == 0 && !snapshot.delivered_second_repair {
                        snapshot.delivered_second_repair = true;
                        serde_json::json!({
                            "ops": [{
                                "device_id": second_op.device_id,
                                "seq": second_op.seq,
                                "op_id": second_op.op_id,
                                "ciphertext_b64": second_op.ciphertext_b64,
                            }],
                            "next": { remote_device_id.clone(): second_op.seq },
                            "max": { remote_device_id.clone(): second_op.seq }
                        })
                    } else {
                        serde_json::json!({
                            "ops": [],
                            "next": { remote_device_id.clone(): second_op.seq },
                            "max": { remote_device_id.clone(): second_op.seq }
                        })
                    };
                    drop(snapshot);

                    write_json_response(&mut stream, 200, response);
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

fn start_progress_repair_server(
    remote_device_id: String,
    partial_ops: Vec<StoredOp>,
    repaired_op: StoredOp,
) -> (
    String,
    mpsc::Sender<()>,
    Arc<Mutex<ProgressRegressionState>>,
    thread::JoinHandle<()>,
) {
    let listener = TcpListener::bind("127.0.0.1:0").expect("bind");
    listener.set_nonblocking(true).expect("nonblocking");
    let addr = listener.local_addr().expect("local addr");

    let (stop_tx, stop_rx) = mpsc::channel::<()>();
    let state = Arc::new(Mutex::new(ProgressRegressionState::default()));
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

                let segments: Vec<&str> = path.split('/').filter(|s| !s.is_empty()).collect();
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
                            "device_id": "local-progress-device",
                            "ws_url": "wss://example.test/events",
                            "sse_url": "https://example.test/events"
                        }),
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
                    snapshot.seen_since_values.push(since_seq);

                    let response = if since_seq == 174 {
                        let last_partial_seq = partial_ops.last().expect("partial op").seq;
                        let ops_json: Vec<_> = partial_ops
                            .iter()
                            .map(|op| {
                                serde_json::json!({
                                    "device_id": op.device_id,
                                    "seq": op.seq,
                                    "op_id": op.op_id,
                                    "ciphertext_b64": op.ciphertext_b64,
                                })
                            })
                            .collect();
                        serde_json::json!({
                            "ops": ops_json,
                            "next": { remote_device_id.clone(): last_partial_seq },
                            "max": { remote_device_id.clone(): repaired_op.seq }
                        })
                    } else if since_seq == partial_ops.last().expect("partial op").seq {
                        serde_json::json!({
                            "ops": [],
                            "next": {},
                            "max": { remote_device_id.clone(): repaired_op.seq }
                        })
                    } else if since_seq == 0 && !snapshot.delivered_repair {
                        snapshot.delivered_repair = true;
                        serde_json::json!({
                            "ops": [{
                                "device_id": repaired_op.device_id,
                                "seq": repaired_op.seq,
                                "op_id": repaired_op.op_id,
                                "ciphertext_b64": repaired_op.ciphertext_b64,
                            }],
                            "next": { remote_device_id.clone(): repaired_op.seq },
                            "max": { remote_device_id.clone(): repaired_op.seq }
                        })
                    } else {
                        serde_json::json!({
                            "ops": [],
                            "next": { remote_device_id.clone(): repaired_op.seq },
                            "max": { remote_device_id.clone(): repaired_op.seq }
                        })
                    };
                    drop(snapshot);

                    write_json_response(&mut stream, 200, response);
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

fn start_nonempty_page_recovery_server(
    first_device_id: String,
    first_op: StoredOp,
    stalled_device_id: String,
    stalled_op: StoredOp,
) -> (
    String,
    mpsc::Sender<()>,
    Arc<Mutex<TwoDeviceRecoveryState>>,
    thread::JoinHandle<()>,
) {
    let listener = TcpListener::bind("127.0.0.1:0").expect("bind");
    listener.set_nonblocking(true).expect("nonblocking");
    let addr = listener.local_addr().expect("local addr");

    let (stop_tx, stop_rx) = mpsc::channel::<()>();
    let state = Arc::new(Mutex::new(TwoDeviceRecoveryState::default()));
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

                let segments: Vec<&str> = path.split('/').filter(|s| !s.is_empty()).collect();
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
                            "device_id": "local-nonempty-page-device",
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
                    let first_since = decoded["since"][first_device_id.as_str()]
                        .as_i64()
                        .unwrap_or(0);
                    let stalled_since = decoded["since"][stalled_device_id.as_str()]
                        .as_i64()
                        .unwrap_or(174);

                    let mut snapshot = state_clone.lock().expect("lock");
                    snapshot.first_since_values.push(first_since);
                    snapshot.stalled_since_values.push(stalled_since);

                    let response = if first_since == 0 && stalled_since == 174 {
                        serde_json::json!({
                            "ops": [{
                                "device_id": first_op.device_id,
                                "seq": first_op.seq,
                                "op_id": first_op.op_id,
                                "ciphertext_b64": first_op.ciphertext_b64,
                            }],
                            "next": { first_device_id.clone(): first_op.seq },
                            "max": {
                                first_device_id.clone(): first_op.seq,
                                stalled_device_id.clone(): stalled_op.seq
                            }
                        })
                    } else if first_since == first_op.seq && stalled_since == 0 {
                        serde_json::json!({
                            "ops": [{
                                "device_id": stalled_op.device_id,
                                "seq": stalled_op.seq,
                                "op_id": stalled_op.op_id,
                                "ciphertext_b64": stalled_op.ciphertext_b64,
                            }],
                            "next": { stalled_device_id.clone(): stalled_op.seq },
                            "max": {
                                first_device_id.clone(): first_op.seq,
                                stalled_device_id.clone(): stalled_op.seq
                            }
                        })
                    } else {
                        serde_json::json!({
                            "ops": [],
                            "next": {
                                first_device_id.clone(): first_op.seq,
                                stalled_device_id.clone(): stalled_op.seq
                            },
                            "max": {
                                first_device_id.clone(): first_op.seq,
                                stalled_device_id.clone(): stalled_op.seq
                            }
                        })
                    };
                    drop(snapshot);

                    write_json_response(&mut stream, 200, response);
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

fn start_progress_empty_page_recovery_server(
    remote_device_id: String,
    repaired_op: StoredOp,
) -> (
    String,
    mpsc::Sender<()>,
    Arc<Mutex<ProgressRegressionState>>,
    thread::JoinHandle<()>,
) {
    let listener = TcpListener::bind("127.0.0.1:0").expect("bind");
    listener.set_nonblocking(true).expect("nonblocking");
    let addr = listener.local_addr().expect("local addr");

    let (stop_tx, stop_rx) = mpsc::channel::<()>();
    let state = Arc::new(Mutex::new(ProgressRegressionState::default()));
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

                let segments: Vec<&str> = path.split('/').filter(|s| !s.is_empty()).collect();
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
                            "device_id": "local-progress-empty-device",
                            "ws_url": "wss://example.test/events",
                            "sse_url": "https://example.test/events"
                        }),
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
                    snapshot.seen_since_values.push(since_seq);

                    let response = if since_seq == 174 {
                        serde_json::json!({
                            "ops": [],
                            "next": { remote_device_id.clone(): 262 },
                            "max": { remote_device_id.clone(): repaired_op.seq }
                        })
                    } else if since_seq == 0 && !snapshot.delivered_repair {
                        snapshot.delivered_repair = true;
                        serde_json::json!({
                            "ops": [{
                                "device_id": repaired_op.device_id,
                                "seq": repaired_op.seq,
                                "op_id": repaired_op.op_id,
                                "ciphertext_b64": repaired_op.ciphertext_b64,
                            }],
                            "next": { remote_device_id.clone(): repaired_op.seq },
                            "max": { remote_device_id.clone(): repaired_op.seq }
                        })
                    } else {
                        serde_json::json!({
                            "ops": [],
                            "next": { remote_device_id.clone(): repaired_op.seq },
                            "max": { remote_device_id.clone(): repaired_op.seq }
                        })
                    };
                    drop(snapshot);

                    write_json_response(&mut stream, 200, response);
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
fn managed_vault_pull_can_repair_same_remote_device_more_than_once() {
    let db_key = [61u8; 32];
    let sync_key = [62u8; 32];
    let remote_device_id = "remote-repeat-device";

    let first_op = synthetic_remote_op(&sync_key, remote_device_id, 262, "Recovered once");
    let second_op = synthetic_remote_op(&sync_key, remote_device_id, 350, "Recovered twice");
    let (base_url, stop_tx, state, handle) = start_repeated_recovery_server(
        remote_device_id.to_string(),
        first_op.clone(),
        second_op.clone(),
    );

    let dir = tempfile::tempdir().expect("tempdir");
    let conn = db::open(dir.path()).expect("open");
    conn.execute(
        r#"INSERT INTO kv(key, value) VALUES ('device_id', 'local-repeat-device')"#,
        [],
    )
    .expect("set local device id");

    insert_raw_op(
        &conn,
        &db_key,
        serde_json::json!({
            "op_id": "existing-remote-op",
            "device_id": remote_device_id,
            "seq": 100,
            "ts_ms": now_ms(),
            "type": "noop.v1",
            "payload": {}
        }),
    );

    let scope_id = scope_id(&base_url, "test-vault");
    set_kv_i64(
        &conn,
        &format!("managed_vault.last_pulled_seq:{scope_id}:{remote_device_id}"),
        174,
    );

    let first_applied = sync::managed_vault::pull(
        &conn,
        &db_key,
        &sync_key,
        &base_url,
        "test-vault",
        "test-token",
    )
    .expect("first repair succeeds");
    assert_eq!(first_applied, 1);

    set_kv_i64(
        &conn,
        &format!("managed_vault.last_pulled_seq:{scope_id}:{remote_device_id}"),
        300,
    );

    let second_applied = sync::managed_vault::pull(
        &conn,
        &db_key,
        &sync_key,
        &base_url,
        "test-vault",
        "test-token",
    )
    .expect("second repair succeeds");
    assert_eq!(second_applied, 1);

    let conversations = db::list_conversations(&conn, &db_key).expect("list conversations");
    assert!(
        conversations
            .iter()
            .any(|conversation| conversation.id == first_op.conversation_id),
        "expected first recovered conversation, got {conversations:?}"
    );
    assert!(
        conversations
            .iter()
            .any(|conversation| conversation.id == second_op.conversation_id),
        "expected second recovered conversation, got {conversations:?}"
    );

    let final_cursor = get_kv_i64(
        &conn,
        &format!("managed_vault.last_pulled_seq:{scope_id}:{remote_device_id}"),
    );
    assert_eq!(final_cursor, Some(350));

    let snapshot = state.lock().expect("lock");
    assert_eq!(snapshot.seen_since_values, vec![174, 0, 300, 0]);
    drop(snapshot);

    let _ = stop_tx.send(());
    handle.join().expect("join");
}

#[test]
fn managed_vault_pull_with_progress_keeps_done_monotonic_when_same_device_cursor_is_repaired() {
    let db_key = [71u8; 32];
    let sync_key = [72u8; 32];
    let remote_device_id = "remote-progress-device";

    let partial_ops = (175..=674)
        .map(|seq| {
            synthetic_remote_op(
                &sync_key,
                remote_device_id,
                seq,
                &format!("Partial progress {seq}"),
            )
        })
        .collect::<Vec<_>>();
    let repaired_op = synthetic_remote_op(&sync_key, remote_device_id, 762, "Recovered progress");
    let (base_url, stop_tx, state, handle) = start_progress_repair_server(
        remote_device_id.to_string(),
        partial_ops.clone(),
        repaired_op.clone(),
    );

    let dir = tempfile::tempdir().expect("tempdir");
    let conn = db::open(dir.path()).expect("open");
    conn.execute(
        r#"INSERT INTO kv(key, value) VALUES ('device_id', 'local-progress-device')"#,
        [],
    )
    .expect("set local device id");

    let scope_id = scope_id(&base_url, "test-vault");
    set_kv_i64(
        &conn,
        &format!("managed_vault.last_pulled_seq:{scope_id}:{remote_device_id}"),
        174,
    );

    let mut seen_progress = Vec::new();
    let applied = sync::managed_vault::pull_with_progress(
        &conn,
        &db_key,
        &sync_key,
        &base_url,
        "test-vault",
        "test-token",
        &mut |done, total| seen_progress.push((done, total)),
    )
    .expect("pull with progress succeeds");

    assert!(
        applied > 0,
        "expected repaired pull to apply at least one op"
    );
    assert!(
        seen_progress
            .windows(2)
            .all(|window| window[1].0 >= window[0].0),
        "progress should not go backwards: {seen_progress:?}"
    );
    assert_eq!(seen_progress.last().copied(), Some((588, 588)));

    let conversations = db::list_conversations(&conn, &db_key).expect("list conversations");
    assert!(
        conversations
            .iter()
            .any(|conversation| conversation.id == partial_ops[0].conversation_id),
        "expected partial conversation, got {conversations:?}"
    );
    assert!(
        conversations
            .iter()
            .any(|conversation| conversation.id == repaired_op.conversation_id),
        "expected repaired conversation, got {conversations:?}"
    );

    let snapshot = state.lock().expect("lock");
    assert_eq!(snapshot.seen_since_values, vec![174, 674, 0]);
    drop(snapshot);

    let _ = stop_tx.send(());
    handle.join().expect("join");
}

#[test]
fn managed_vault_pull_repairs_stalled_device_even_when_current_page_has_other_device_ops() {
    let db_key = [81u8; 32];
    let sync_key = [82u8; 32];
    let first_device_id = "remote-first-device";
    let stalled_device_id = "remote-stalled-device";
    let first_op = synthetic_remote_op(&sync_key, first_device_id, 10, "First page op");
    let stalled_op = synthetic_remote_op(&sync_key, stalled_device_id, 262, "Recovered stalled op");
    let (base_url, stop_tx, state, handle) = start_nonempty_page_recovery_server(
        first_device_id.to_string(),
        first_op.clone(),
        stalled_device_id.to_string(),
        stalled_op.clone(),
    );

    let dir = tempfile::tempdir().expect("tempdir");
    let conn = db::open(dir.path()).expect("open");
    conn.execute(
        r#"INSERT INTO kv(key, value) VALUES ('device_id', 'local-nonempty-page-device')"#,
        [],
    )
    .expect("set local device id");

    let scope_id = scope_id(&base_url, "test-vault");
    set_kv_i64(
        &conn,
        &format!("managed_vault.last_pulled_seq:{scope_id}:{stalled_device_id}"),
        174,
    );

    let applied = sync::managed_vault::pull(
        &conn,
        &db_key,
        &sync_key,
        &base_url,
        "test-vault",
        "test-token",
    )
    .expect("pull succeeds");

    assert_eq!(applied, 2);
    let conversations = db::list_conversations(&conn, &db_key).expect("list conversations");
    assert!(
        conversations
            .iter()
            .any(|conversation| conversation.id == first_op.conversation_id),
        "expected first-page conversation, got {conversations:?}"
    );
    assert!(
        conversations
            .iter()
            .any(|conversation| conversation.id == stalled_op.conversation_id),
        "expected stalled conversation, got {conversations:?}"
    );

    let snapshot = state.lock().expect("lock");
    assert_eq!(snapshot.first_since_values, vec![0, first_op.seq]);
    assert_eq!(snapshot.stalled_since_values, vec![174, 0]);
    drop(snapshot);

    let _ = stop_tx.send(());
    handle.join().expect("join");
}

#[test]
fn managed_vault_pull_with_progress_repairs_remote_ahead_when_empty_page_advances_next_cursor() {
    let db_key = [91u8; 32];
    let sync_key = [92u8; 32];
    let remote_device_id = "remote-progress-empty-device";
    let repaired_op = synthetic_remote_op(
        &sync_key,
        remote_device_id,
        350,
        "Recovered after empty page",
    );
    let (base_url, stop_tx, state, handle) = start_progress_empty_page_recovery_server(
        remote_device_id.to_string(),
        repaired_op.clone(),
    );

    let dir = tempfile::tempdir().expect("tempdir");
    let conn = db::open(dir.path()).expect("open");
    conn.execute(
        r#"INSERT INTO kv(key, value) VALUES ('device_id', 'local-progress-empty-device')"#,
        [],
    )
    .expect("set local device id");

    let scope_id = scope_id(&base_url, "test-vault");
    set_kv_i64(
        &conn,
        &format!("managed_vault.last_pulled_seq:{scope_id}:{remote_device_id}"),
        174,
    );

    let mut seen_progress = Vec::new();
    let applied = sync::managed_vault::pull_with_progress(
        &conn,
        &db_key,
        &sync_key,
        &base_url,
        "test-vault",
        "test-token",
        &mut |done, total| seen_progress.push((done, total)),
    )
    .expect("pull with progress succeeds");

    assert_eq!(applied, 1);
    assert!(
        seen_progress
            .windows(2)
            .all(|window| window[1].0 >= window[0].0),
        "progress should not go backwards: {seen_progress:?}"
    );
    assert_eq!(seen_progress.first().copied(), Some((0, 176)));
    assert_eq!(seen_progress.last().copied(), Some((176, 176)));

    let conversations = db::list_conversations(&conn, &db_key).expect("list conversations");
    assert!(
        conversations
            .iter()
            .any(|conversation| conversation.id == repaired_op.conversation_id),
        "expected repaired conversation, got {conversations:?}"
    );

    let snapshot = state.lock().expect("lock");
    assert_eq!(snapshot.seen_since_values, vec![174, 0]);
    drop(snapshot);

    let _ = stop_tx.send(());
    handle.join().expect("join");
}
