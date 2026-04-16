use std::io::{Read, Write};
use std::net::{TcpListener, TcpStream};
use std::sync::mpsc;
use std::sync::{Arc, Mutex};
use std::thread;
use std::time::{Duration, SystemTime, UNIX_EPOCH};

use base64::engine::general_purpose::URL_SAFE_NO_PAD;
use base64::Engine as _;
use rusqlite::params;
use secondloop_rust::auth;
use secondloop_rust::crypto::{derive_root_key, encrypt_bytes, KdfParams};
use secondloop_rust::db;
use secondloop_rust::sync;

const PULL_BIN_MAGIC_V1: &[u8; 5] = b"SLVB1";

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
enum RecoveryScenario {
    JsonRemoteAheadRecovery,
    PullBinProbeRemoteAheadRecovery,
    PullBinProbeFailureFallsBackToJson,
    PullBinProbeReturnsJsonOps,
}

#[derive(Default)]
struct ServerState {
    pull_requests: u64,
    pull_bin_requests: u64,
    json_since_values: Vec<i64>,
    pull_bin_since_values: Vec<i64>,
}

#[derive(Debug, Clone)]
struct StoredOp {
    device_id: String,
    seq: i64,
    op_id: String,
    ciphertext_b64: String,
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

    (headers_str, method, path, body)
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

fn write_bytes_response(stream: &mut TcpStream, body: Vec<u8>) {
    let resp = format!(
        "HTTP/1.1 200 OK\r\nContent-Type: application/octet-stream\r\nContent-Length: {}\r\nConnection: close\r\n\r\n",
        body.len()
    );
    stream.write_all(resp.as_bytes()).expect("write headers");
    stream.write_all(&body).expect("write body");
}

fn encode_pull_bin(ops: &[StoredOp]) -> Vec<u8> {
    let mut out: Vec<u8> = Vec::new();
    out.extend_from_slice(PULL_BIN_MAGIC_V1);
    out.extend_from_slice(&(ops.len() as u32).to_le_bytes());
    for op in ops {
        let device_id = op.device_id.as_bytes();
        out.extend_from_slice(&(device_id.len() as u16).to_le_bytes());
        out.extend_from_slice(device_id);
        out.extend_from_slice(&op.seq.to_le_bytes());

        let op_id = op.op_id.as_bytes();
        out.extend_from_slice(&(op_id.len() as u16).to_le_bytes());
        out.extend_from_slice(op_id);

        let ciphertext = base64::engine::general_purpose::STANDARD
            .decode(op.ciphertext_b64.as_bytes())
            .expect("decode ciphertext");
        out.extend_from_slice(&(ciphertext.len() as u32).to_le_bytes());
        out.extend_from_slice(&ciphertext);
    }
    out
}

fn start_short_page_probe_failure_server(
    first_op: StoredOp,
    second_op: StoredOp,
) -> (
    String,
    mpsc::Sender<()>,
    Arc<Mutex<ServerState>>,
    thread::JoinHandle<()>,
) {
    let listener = TcpListener::bind("127.0.0.1:0").expect("bind");
    listener.set_nonblocking(true).expect("nonblocking");
    let addr = listener.local_addr().expect("local addr");

    let (stop_tx, stop_rx) = mpsc::channel::<()>();
    let state = Arc::new(Mutex::new(ServerState::default()));
    let state_clone = Arc::clone(&state);

    let handle = thread::spawn(move || loop {
        if stop_rx.try_recv().is_ok() {
            break;
        }
        match listener.accept() {
            Ok((mut stream, _)) => {
                stream.set_nonblocking(false).expect("blocking stream");
                let (_raw_headers, method, path, body) = read_request(&mut stream);
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
                            "device_id": "local-short-page-device",
                            "ws_url": "wss://example.test/events",
                            "sse_url": "https://example.test/events"
                        }),
                    );
                    continue;
                }

                if tail == "ops:pull_bin" {
                    let decoded: serde_json::Value =
                        serde_json::from_slice(&body).expect("pull_bin json");
                    let since_seq = decoded["since"][first_op.device_id.as_str()]
                        .as_i64()
                        .unwrap_or(0);
                    let mut snapshot = state_clone.lock().expect("lock");
                    snapshot.pull_bin_requests += 1;
                    snapshot.pull_bin_since_values.push(since_seq);
                    drop(snapshot);

                    if since_seq == 0 {
                        write_bytes_response(&mut stream, encode_pull_bin(&[first_op.clone()]));
                    } else {
                        write_bytes_response(&mut stream, encode_pull_bin(&[]));
                    }
                    continue;
                }

                if tail == "ops:pull" {
                    let decoded: serde_json::Value =
                        serde_json::from_slice(&body).expect("pull json");
                    let since_seq = decoded["since"][first_op.device_id.as_str()]
                        .as_i64()
                        .unwrap_or(0);
                    let mut snapshot = state_clone.lock().expect("lock");
                    snapshot.pull_requests += 1;
                    snapshot.json_since_values.push(since_seq);
                    let pull_requests = snapshot.pull_requests;
                    drop(snapshot);

                    if pull_requests == 1 {
                        write_json_response(
                            &mut stream,
                            503,
                            serde_json::json!({ "error": "temporarily_unavailable" }),
                        );
                    } else if since_seq == 1 {
                        write_json_response(
                            &mut stream,
                            200,
                            serde_json::json!({
                                "ops": [{
                                    "device_id": second_op.device_id,
                                    "seq": second_op.seq,
                                    "op_id": second_op.op_id,
                                    "ciphertext_b64": second_op.ciphertext_b64,
                                }],
                                "next": { second_op.device_id.clone(): second_op.seq },
                                "max": { second_op.device_id.clone(): second_op.seq }
                            }),
                        );
                    } else {
                        write_json_response(
                            &mut stream,
                            200,
                            serde_json::json!({
                                "ops": [],
                                "next": { second_op.device_id.clone(): second_op.seq },
                                "max": { second_op.device_id.clone(): second_op.seq }
                            }),
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
            Err(e) if e.kind() == std::io::ErrorKind::WouldBlock => {
                thread::sleep(Duration::from_millis(5));
            }
            Err(e) => panic!("accept failed: {e}"),
        }
    });

    (format!("http://{}", addr), stop_tx, state, handle)
}

fn start_recovery_server(
    scenario: RecoveryScenario,
    remote_device_id: String,
    op: StoredOp,
) -> (
    String,
    mpsc::Sender<()>,
    Arc<Mutex<ServerState>>,
    thread::JoinHandle<()>,
) {
    let listener = TcpListener::bind("127.0.0.1:0").expect("bind");
    listener.set_nonblocking(true).expect("nonblocking");
    let addr = listener.local_addr().expect("local addr");

    let (stop_tx, stop_rx) = mpsc::channel::<()>();
    let state = Arc::new(Mutex::new(ServerState::default()));
    let state_clone = Arc::clone(&state);

    let handle = thread::spawn(move || loop {
        if stop_rx.try_recv().is_ok() {
            break;
        }
        match listener.accept() {
            Ok((mut stream, _)) => {
                stream.set_nonblocking(false).expect("blocking stream");
                let (_raw_headers, method, path, body) = read_request(&mut stream);
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
                    let decoded: serde_json::Value =
                        serde_json::from_slice(&body).expect("devices json");
                    let device_id = decoded
                        .get("device_id")
                        .and_then(|v| v.as_str())
                        .unwrap_or("local-device")
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

                if tail == "ops:pull_bin" {
                    let decoded: serde_json::Value =
                        serde_json::from_slice(&body).expect("pull_bin json");
                    let since_seq = decoded["since"][remote_device_id.as_str()]
                        .as_i64()
                        .unwrap_or(0);
                    let mut snapshot = state_clone.lock().expect("lock");
                    snapshot.pull_bin_requests += 1;
                    snapshot.pull_bin_since_values.push(since_seq);
                    drop(snapshot);

                    match scenario {
                        RecoveryScenario::JsonRemoteAheadRecovery => {
                            write_json_response(
                                &mut stream,
                                404,
                                serde_json::json!({ "error": "not_found" }),
                            );
                        }
                        RecoveryScenario::PullBinProbeRemoteAheadRecovery => {
                            if since_seq == 0 {
                                write_bytes_response(&mut stream, encode_pull_bin(&[op.clone()]));
                            } else {
                                write_bytes_response(&mut stream, encode_pull_bin(&[]));
                            }
                        }
                        RecoveryScenario::PullBinProbeFailureFallsBackToJson => {
                            write_bytes_response(&mut stream, encode_pull_bin(&[]));
                        }
                        RecoveryScenario::PullBinProbeReturnsJsonOps => {
                            write_bytes_response(&mut stream, encode_pull_bin(&[]));
                        }
                    }
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
                    snapshot.json_since_values.push(since_seq);
                    let pull_requests = snapshot.pull_requests;
                    drop(snapshot);

                    match scenario {
                        RecoveryScenario::JsonRemoteAheadRecovery
                        | RecoveryScenario::PullBinProbeRemoteAheadRecovery => {
                            if since_seq == 174 {
                                write_json_response(
                                    &mut stream,
                                    200,
                                    serde_json::json!({
                                        "ops": [],
                                        "next": {},
                                        "max": { remote_device_id.clone(): 262 }
                                    }),
                                );
                            } else if since_seq == 0 {
                                write_json_response(
                                    &mut stream,
                                    200,
                                    serde_json::json!({
                                        "ops": [{
                                            "device_id": op.device_id,
                                            "seq": op.seq,
                                            "op_id": op.op_id,
                                            "ciphertext_b64": op.ciphertext_b64,
                                        }],
                                        "next": { remote_device_id.clone(): 262 },
                                        "max": { remote_device_id.clone(): 262 }
                                    }),
                                );
                            } else {
                                write_json_response(
                                    &mut stream,
                                    200,
                                    serde_json::json!({
                                        "ops": [],
                                        "next": { remote_device_id.clone(): 262 },
                                        "max": { remote_device_id.clone(): 262 }
                                    }),
                                );
                            }
                        }
                        RecoveryScenario::PullBinProbeFailureFallsBackToJson => {
                            if pull_requests == 1 {
                                write_json_response(
                                    &mut stream,
                                    503,
                                    serde_json::json!({ "error": "temporarily_unavailable" }),
                                );
                            } else if since_seq == 0 {
                                write_json_response(
                                    &mut stream,
                                    200,
                                    serde_json::json!({
                                        "ops": [{
                                            "device_id": op.device_id,
                                            "seq": op.seq,
                                            "op_id": op.op_id,
                                            "ciphertext_b64": op.ciphertext_b64,
                                        }],
                                        "next": { remote_device_id.clone(): 262 },
                                        "max": { remote_device_id.clone(): 262 }
                                    }),
                                );
                            } else {
                                write_json_response(
                                    &mut stream,
                                    200,
                                    serde_json::json!({
                                        "ops": [],
                                        "next": { remote_device_id.clone(): 262 },
                                        "max": { remote_device_id.clone(): 262 }
                                    }),
                                );
                            }
                        }
                        RecoveryScenario::PullBinProbeReturnsJsonOps => {
                            if since_seq == 174 {
                                write_json_response(
                                    &mut stream,
                                    200,
                                    serde_json::json!({
                                        "ops": [{
                                            "device_id": op.device_id,
                                            "seq": op.seq,
                                            "op_id": op.op_id,
                                            "ciphertext_b64": op.ciphertext_b64,
                                        }],
                                        "next": { remote_device_id.clone(): 262 },
                                        "max": { remote_device_id.clone(): 262 }
                                    }),
                                );
                            } else {
                                write_json_response(
                                    &mut stream,
                                    200,
                                    serde_json::json!({
                                        "ops": [],
                                        "next": { remote_device_id.clone(): 262 },
                                        "max": { remote_device_id.clone(): 262 }
                                    }),
                                );
                            }
                        }
                    }
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

fn synthetic_remote_op(sync_key: &[u8; 32], remote_device_id: &str) -> StoredOp {
    synthetic_remote_op_with_seq(sync_key, remote_device_id, 262, "Recovered title")
}

fn synthetic_remote_op_with_seq(
    sync_key: &[u8; 32],
    remote_device_id: &str,
    seq: i64,
    title: &str,
) -> StoredOp {
    let op_id = format!("remote-op-{remote_device_id}-{seq}");
    let op_json = serde_json::json!({
        "op_id": op_id,
        "device_id": remote_device_id,
        "seq": seq,
        "ts_ms": now_ms(),
        "type": "conversation.upsert.v1",
        "payload": {
            "conversation_id": format!("conversation-{remote_device_id}-{seq}"),
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
    }
}

fn setup_local_client(
    app_name: &str,
) -> (
    tempfile::TempDir,
    std::path::PathBuf,
    [u8; 32],
    rusqlite::Connection,
) {
    let temp = tempfile::tempdir().expect("tempdir");
    let app_dir = temp.path().join(app_name);
    let key =
        auth::init_master_password(&app_dir, "pw", KdfParams::for_test()).expect("init master pw");
    let conn = db::open(&app_dir).expect("open db");
    (temp, app_dir, key, conn)
}

fn assert_recovered_conversation_exists(
    conn: &rusqlite::Connection,
    db_key: &[u8; 32],
    expected_title: &str,
) {
    let conversations = db::list_conversations(conn, db_key).expect("list conversations");
    assert!(
        conversations
            .iter()
            .any(|conversation| conversation.title == expected_title),
        "expected recovered conversation, got {conversations:?}"
    );
}

#[test]
fn managed_vault_pull_recovers_remote_ahead_cursor_on_json_path_even_with_local_remote_history() {
    let vault_id = "vault-json";
    let id_token = "test_uid";
    let sync_key = derive_root_key(
        "sync-passphrase",
        b"secondloop-sync1",
        &KdfParams::for_test(),
    )
    .expect("sync key");
    let remote_device_id = "remote-json-device";
    let remote_op = synthetic_remote_op(&sync_key, remote_device_id);
    let (base_url, stop_tx, state, handle) = start_recovery_server(
        RecoveryScenario::JsonRemoteAheadRecovery,
        remote_device_id.to_string(),
        remote_op,
    );

    let (_temp, _app_dir, db_key, conn) = setup_local_client("json_client");

    conn.execute(
        r#"INSERT INTO kv(key, value) VALUES ('device_id', 'local-json-device')"#,
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

    let scope = scope_id(&base_url, vault_id);
    conn.execute(
        r#"INSERT INTO kv(key, value) VALUES (?1, ?2)
           ON CONFLICT(key) DO UPDATE SET value = excluded.value"#,
        params![
            format!("managed_vault.last_pulled_seq:{scope}:{remote_device_id}"),
            "174"
        ],
    )
    .expect("set stale cursor");

    let applied =
        sync::managed_vault::pull(&conn, &db_key, &sync_key, &base_url, vault_id, id_token)
            .expect("pull succeeds");
    assert_eq!(applied, 1);

    let conversations = db::list_conversations(&conn, &db_key).expect("list conversations");
    assert!(
        conversations
            .iter()
            .any(|conversation| conversation.title == "Recovered title"),
        "expected recovered conversation, got {conversations:?}"
    );

    let repaired_cursor: String = conn
        .query_row(
            r#"SELECT value FROM kv WHERE key = ?1"#,
            params![format!(
                "managed_vault.last_pulled_seq:{scope}:{remote_device_id}"
            )],
            |row| row.get(0),
        )
        .expect("read repaired cursor");
    assert_eq!(repaired_cursor, "262");

    let snapshot = state.lock().expect("lock");
    assert_eq!(snapshot.pull_bin_requests, 1);
    assert_eq!(snapshot.pull_requests, 2);
    assert_eq!(snapshot.json_since_values, vec![174, 0]);
    drop(snapshot);

    let _ = stop_tx.send(());
    handle.join().expect("join");
}

#[test]
fn managed_vault_pull_bin_empty_response_falls_back_to_json_when_probe_fails() {
    let vault_id = "vault-noop";
    let id_token = "test_uid";
    let sync_key = derive_root_key(
        "sync-passphrase",
        b"secondloop-sync1",
        &KdfParams::for_test(),
    )
    .expect("sync key");
    let remote_device_id = "remote-noop-device";
    let remote_op = synthetic_remote_op(&sync_key, remote_device_id);
    let (base_url, stop_tx, state, handle) = start_recovery_server(
        RecoveryScenario::PullBinProbeFailureFallsBackToJson,
        remote_device_id.to_string(),
        remote_op,
    );

    let (_temp, _app_dir, db_key, conn) = setup_local_client("noop_client");
    conn.execute(
        r#"INSERT INTO kv(key, value) VALUES ('device_id', 'local-noop-device')"#,
        [],
    )
    .expect("set local device id");

    let applied =
        sync::managed_vault::pull(&conn, &db_key, &sync_key, &base_url, vault_id, id_token)
            .expect("pull succeeds after json fallback");
    assert_eq!(applied, 1);
    assert_recovered_conversation_exists(&conn, &db_key, "Recovered title");

    let snapshot = state.lock().expect("lock");
    assert_eq!(snapshot.pull_bin_requests, 1);
    assert_eq!(snapshot.pull_requests, 2);
    assert_eq!(snapshot.pull_bin_since_values, vec![0]);
    assert_eq!(snapshot.json_since_values, vec![0, 0]);
    drop(snapshot);

    let _ = stop_tx.send(());
    handle.join().expect("join");
}

#[test]
fn managed_vault_pull_bin_recovers_remote_ahead_cursor_without_resetting_to_json_mode() {
    let vault_id = "vault-pull-bin";
    let id_token = "test_uid";
    let sync_key = derive_root_key(
        "sync-passphrase",
        b"secondloop-sync1",
        &KdfParams::for_test(),
    )
    .expect("sync key");
    let remote_device_id = "remote-pull-bin-device";
    let remote_op = synthetic_remote_op(&sync_key, remote_device_id);
    let (base_url, stop_tx, state, handle) = start_recovery_server(
        RecoveryScenario::PullBinProbeRemoteAheadRecovery,
        remote_device_id.to_string(),
        remote_op,
    );

    let (_temp, _app_dir, db_key, conn) = setup_local_client("pull_bin_client");
    conn.execute(
        r#"INSERT INTO kv(key, value) VALUES ('device_id', 'local-pull-bin-device')"#,
        [],
    )
    .expect("set local device id");

    insert_raw_op(
        &conn,
        &db_key,
        serde_json::json!({
            "op_id": "existing-pull-bin-remote-op",
            "device_id": remote_device_id,
            "seq": 100,
            "ts_ms": now_ms(),
            "type": "noop.v1",
            "payload": {}
        }),
    );

    let scope = scope_id(&base_url, vault_id);
    conn.execute(
        r#"INSERT INTO kv(key, value) VALUES (?1, ?2)
           ON CONFLICT(key) DO UPDATE SET value = excluded.value"#,
        params![
            format!("managed_vault.last_pulled_seq:{scope}:{remote_device_id}"),
            "174"
        ],
    )
    .expect("set stale cursor");

    let applied =
        sync::managed_vault::pull(&conn, &db_key, &sync_key, &base_url, vault_id, id_token)
            .expect("pull succeeds");
    assert_eq!(applied, 1);

    let conversations = db::list_conversations(&conn, &db_key).expect("list conversations");
    assert!(
        conversations
            .iter()
            .any(|conversation| conversation.title == "Recovered title"),
        "expected recovered conversation, got {conversations:?}"
    );

    let snapshot = state.lock().expect("lock");
    assert_eq!(snapshot.pull_bin_requests, 2);
    assert_eq!(snapshot.pull_requests, 2);
    assert_eq!(snapshot.pull_bin_since_values, vec![174, 0]);
    assert_eq!(snapshot.json_since_values, vec![174, 262]);
    drop(snapshot);

    let _ = stop_tx.send(());
    handle.join().expect("join");
}

#[test]
fn managed_vault_pull_consumes_json_probe_ops_after_pull_bin_short_page() {
    let vault_id = "vault-probe-ops";
    let id_token = "test_uid";
    let sync_key = derive_root_key(
        "sync-passphrase",
        b"secondloop-sync1",
        &KdfParams::for_test(),
    )
    .expect("sync key");
    let remote_device_id = "remote-probe-ops-device";
    let remote_op = synthetic_remote_op(&sync_key, remote_device_id);
    let (base_url, stop_tx, state, handle) = start_recovery_server(
        RecoveryScenario::PullBinProbeReturnsJsonOps,
        remote_device_id.to_string(),
        remote_op,
    );

    let (_temp, _app_dir, db_key, conn) = setup_local_client("probe_ops_client");
    conn.execute(
        r#"INSERT INTO kv(key, value) VALUES ('device_id', 'local-probe-ops-device')"#,
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

    let scope = scope_id(&base_url, vault_id);
    conn.execute(
        r#"INSERT INTO kv(key, value) VALUES (?1, ?2)
           ON CONFLICT(key) DO UPDATE SET value = excluded.value"#,
        params![
            format!("managed_vault.last_pulled_seq:{scope}:{remote_device_id}"),
            "174"
        ],
    )
    .expect("set stale cursor");

    let applied =
        sync::managed_vault::pull(&conn, &db_key, &sync_key, &base_url, vault_id, id_token)
            .expect("pull succeeds");
    assert_eq!(applied, 1);
    assert_recovered_conversation_exists(&conn, &db_key, "Recovered title");

    let repaired_cursor: String = conn
        .query_row(
            r#"SELECT value FROM kv WHERE key = ?1"#,
            params![format!(
                "managed_vault.last_pulled_seq:{scope}:{remote_device_id}"
            )],
            |row| row.get(0),
        )
        .expect("read repaired cursor");
    assert_eq!(repaired_cursor, "262");

    let snapshot = state.lock().expect("lock");
    assert_eq!(snapshot.pull_bin_requests, 1);
    assert_eq!(snapshot.pull_requests, 1);
    assert_eq!(snapshot.pull_bin_since_values, vec![174]);
    assert_eq!(snapshot.json_since_values, vec![174]);
    drop(snapshot);

    let _ = stop_tx.send(());
    handle.join().expect("join");
}

#[test]
fn managed_vault_pull_short_page_probe_failure_falls_back_to_json_instead_of_exiting_early() {
    let vault_id = "vault-short-page-probe-failure";
    let id_token = "test_uid";
    let sync_key = derive_root_key(
        "sync-passphrase",
        b"secondloop-sync1",
        &KdfParams::for_test(),
    )
    .expect("sync key");
    let remote_device_id = "remote-short-page-probe-failure-device";
    let first_op = synthetic_remote_op_with_seq(&sync_key, remote_device_id, 1, "First title");
    let second_op = synthetic_remote_op_with_seq(&sync_key, remote_device_id, 2, "Second title");
    let (base_url, stop_tx, state, handle) =
        start_short_page_probe_failure_server(first_op, second_op);

    let (_temp, _app_dir, db_key, conn) = setup_local_client("short_page_probe_failure_client");
    conn.execute(
        r#"INSERT INTO kv(key, value) VALUES ('device_id', 'local-short-page-device')"#,
        [],
    )
    .expect("set local device id");

    let applied =
        sync::managed_vault::pull(&conn, &db_key, &sync_key, &base_url, vault_id, id_token)
            .expect("pull succeeds");
    assert_eq!(applied, 2);
    assert_recovered_conversation_exists(&conn, &db_key, "Second title");

    let snapshot = state.lock().expect("lock");
    assert_eq!(snapshot.pull_bin_requests, 1);
    assert_eq!(snapshot.pull_requests, 2);
    assert_eq!(snapshot.pull_bin_since_values, vec![0]);
    assert_eq!(snapshot.json_since_values, vec![1, 1]);
    drop(snapshot);

    let _ = stop_tx.send(());
    handle.join().expect("join");
}
