use std::io::{Read, Write};
use std::net::{TcpListener, TcpStream};
use std::sync::{Arc, Mutex};
use std::thread;

use base64::engine::general_purpose::STANDARD as B64_STD;
use base64::engine::general_purpose::URL_SAFE_NO_PAD;
use base64::Engine as _;
use secondloop_rust::crypto::encrypt_bytes;
use secondloop_rust::db;
use secondloop_rust::sync;
use tempfile::tempdir;

#[derive(Default)]
struct ServerState {
    seen_since_values: Vec<i64>,
}

fn scope_id(base_url: &str, vault_id: &str) -> String {
    let raw = format!("managed_vault|{}|{}", base_url.trim(), vault_id.trim());
    URL_SAFE_NO_PAD.encode(raw.as_bytes())
}

fn read_http_request(stream: &mut TcpStream) -> (String, Vec<u8>) {
    let mut raw = Vec::new();
    let mut buf = [0u8; 1024];
    let mut header_end = None;
    loop {
        let n = stream.read(&mut buf).expect("read request");
        if n == 0 {
            break;
        }
        raw.extend_from_slice(&buf[..n]);
        if let Some(pos) = raw.windows(4).position(|w| w == b"\r\n\r\n") {
            header_end = Some(pos + 4);
            break;
        }
    }

    let header_end = header_end.expect("header end");
    let headers = String::from_utf8_lossy(&raw[..header_end]).to_string();
    let content_length = headers
        .lines()
        .find_map(|line| {
            let lower = line.to_ascii_lowercase();
            lower
                .strip_prefix("content-length:")
                .and_then(|v| v.trim().parse::<usize>().ok())
        })
        .unwrap_or(0);
    let mut body = raw[header_end..].to_vec();
    while body.len() < content_length {
        let n = stream.read(&mut buf).expect("read body");
        if n == 0 {
            break;
        }
        body.extend_from_slice(&buf[..n]);
    }
    (headers, body)
}

fn respond_json(stream: &mut TcpStream, status: &str, body: &str) {
    let response = format!(
        "HTTP/1.1 {status}\r\nContent-Type: application/json\r\nContent-Length: {}\r\nConnection: close\r\n\r\n{}",
        body.len(),
        body
    );
    stream
        .write_all(response.as_bytes())
        .expect("write response");
}

fn spawn_progress_recovery_server(
    remote_device_id: String,
    encrypted_op_b64: String,
    expected_op_id: String,
) -> (String, Arc<Mutex<ServerState>>) {
    let listener = TcpListener::bind("127.0.0.1:0").expect("bind listener");
    let addr = format!("http://{}", listener.local_addr().expect("local addr"));
    let state = Arc::new(Mutex::new(ServerState::default()));
    let state_for_thread = Arc::clone(&state);

    thread::spawn(move || {
        for _ in 0..3 {
            let (mut stream, _) = listener.accept().expect("accept");
            let (headers, body) = read_http_request(&mut stream);
            let request_line = headers.lines().next().unwrap_or_default().to_string();

            if request_line.starts_with("POST /v1/vaults/test-vault/devices ") {
                respond_json(
                    &mut stream,
                    "200 OK",
                    r#"{"device_id":"local-device-progress"}"#,
                );
                continue;
            }

            if request_line.starts_with("POST /v1/vaults/test-vault/ops:pull ") {
                let payload: serde_json::Value =
                    serde_json::from_slice(&body).expect("parse pull body");
                let since_value = payload["since"][remote_device_id.as_str()]
                    .as_i64()
                    .unwrap_or(0);
                state_for_thread
                    .lock()
                    .expect("lock state")
                    .seen_since_values
                    .push(since_value);

                if since_value == 174 {
                    respond_json(
                        &mut stream,
                        "200 OK",
                        &format!(
                            r#"{{"ops":[],"next":{{}},"max":{{"{device_id}":262}}}}"#,
                            device_id = remote_device_id
                        ),
                    );
                    continue;
                }

                if since_value == 0 {
                    respond_json(
                        &mut stream,
                        "200 OK",
                        &format!(
                            r#"{{"ops":[{{"device_id":"{device_id}","seq":262,"op_id":"{op_id}","ciphertext_b64":"{ciphertext}"}}],"next":{{"{device_id}":262}},"max":{{"{device_id}":262}}}}"#,
                            device_id = remote_device_id,
                            op_id = expected_op_id,
                            ciphertext = encrypted_op_b64,
                        ),
                    );
                    continue;
                }

                respond_json(
                    &mut stream,
                    "200 OK",
                    &format!(
                        r#"{{"ops":[],"next":{{"{device_id}":262}},"max":{{"{device_id}":262}}}}"#,
                        device_id = remote_device_id
                    ),
                );
                continue;
            }

            respond_json(&mut stream, "404 Not Found", r#"{"error":"not_found"}"#);
        }
    });

    (addr, state)
}

fn spawn_missing_max_after_large_first_page_server(
    remote_device_id: String,
    first_page_ops: Vec<(i64, String, String)>,
    second_ciphertext_b64: String,
) -> String {
    let listener = TcpListener::bind("127.0.0.1:0").expect("bind listener");
    let addr = format!("http://{}", listener.local_addr().expect("local addr"));

    thread::spawn(move || {
        for _ in 0..3 {
            let (mut stream, _) = listener.accept().expect("accept");
            let (headers, body) = read_http_request(&mut stream);
            let request_line = headers.lines().next().unwrap_or_default().to_string();

            if request_line.starts_with("POST /v1/vaults/test-vault/devices ") {
                respond_json(
                    &mut stream,
                    "200 OK",
                    r#"{"device_id":"local-device-progress"}"#,
                );
                continue;
            }

            if request_line.starts_with("POST /v1/vaults/test-vault/ops:pull ") {
                let payload: serde_json::Value =
                    serde_json::from_slice(&body).expect("parse pull body");
                let since_value = payload["since"][remote_device_id.as_str()]
                    .as_i64()
                    .unwrap_or(0);

                if since_value == 0 {
                    let ops_json = first_page_ops
                        .iter()
                        .map(|(seq, op_id, ciphertext_b64)| {
                            serde_json::json!({
                                "device_id": remote_device_id,
                                "seq": seq,
                                "op_id": op_id,
                                "ciphertext_b64": ciphertext_b64,
                            })
                        })
                        .collect::<Vec<_>>();
                    respond_json(
                        &mut stream,
                        "200 OK",
                        &format!(
                            r#"{{"ops":{ops_json},"next":{{"{device_id}":500}},"max":{{"{device_id}":501}}}}"#,
                            device_id = remote_device_id,
                            ops_json = serde_json::Value::Array(ops_json),
                        ),
                    );
                    continue;
                }

                if since_value == 500 {
                    respond_json(
                        &mut stream,
                        "200 OK",
                        &format!(
                            r#"{{"ops":[{{"device_id":"{device_id}","seq":501,"op_id":"op-conversation-missing-max-501","ciphertext_b64":"{ciphertext}"}}],"next":{{"{device_id}":501}}}}"#,
                            device_id = remote_device_id,
                            ciphertext = second_ciphertext_b64,
                        ),
                    );
                    continue;
                }

                respond_json(
                    &mut stream,
                    "200 OK",
                    &format!(
                        r#"{{"ops":[],"next":{{"{device_id}":2}}}}"#,
                        device_id = remote_device_id
                    ),
                );
                continue;
            }

            respond_json(&mut stream, "404 Not Found", r#"{"error":"not_found"}"#);
        }
    });

    addr
}

fn encrypted_conversation_op(
    sync_key: &[u8; 32],
    remote_device_id: &str,
    seq: i64,
    conversation_id: &str,
    title: &str,
    ts_ms: i64,
) -> String {
    let op_id = format!("op-{conversation_id}");
    let op_json = serde_json::json!({
        "op_id": op_id,
        "device_id": remote_device_id,
        "seq": seq,
        "ts_ms": ts_ms,
        "type": "conversation.upsert.v1",
        "payload": {
            "conversation_id": conversation_id,
            "title": title,
            "created_at_ms": ts_ms,
            "updated_at_ms": ts_ms,
        }
    });
    let plaintext = serde_json::to_vec(&op_json).expect("serialize op");
    let ciphertext = encrypt_bytes(
        sync_key,
        &plaintext,
        format!("sync.ops:{remote_device_id}:{seq}").as_bytes(),
    )
    .expect("encrypt op");
    B64_STD.encode(ciphertext)
}

#[test]
fn managed_vault_pull_with_progress_keeps_total_stable_during_cursor_repair() {
    let db_key = [61u8; 32];
    let sync_key = [62u8; 32];
    let remote_device_id = "remote-device-progress";

    let dir = tempdir().expect("tempdir");
    let conn = db::open(dir.path()).expect("open");
    conn.execute(
        r#"INSERT INTO kv(key, value) VALUES ('device_id', 'local-device-progress')"#,
        [],
    )
    .expect("set local device id");

    let encrypted_op_b64 = encrypted_conversation_op(
        &sync_key,
        remote_device_id,
        262,
        "conversation-progress-recovery",
        "Recovered title",
        1_775_811_648_824,
    );
    let (base_url, state) = spawn_progress_recovery_server(
        remote_device_id.to_string(),
        encrypted_op_b64,
        "op-conversation-progress-recovery".to_string(),
    );
    let scope_id = scope_id(&base_url, "test-vault");
    conn.execute(
        r#"INSERT INTO kv(key, value) VALUES (?1, ?2)
           ON CONFLICT(key) DO UPDATE SET value = excluded.value"#,
        [
            format!("managed_vault.last_pulled_seq:{scope_id}:{remote_device_id}"),
            "174".to_string(),
        ],
    )
    .expect("set stale cursor");

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
    .expect("pull with recovery");

    assert_eq!(applied, 1);
    assert!(
        seen_progress.iter().all(|(_, total)| *total == 88),
        "repair should not inflate total progress: {seen_progress:?}"
    );

    let snapshot = state.lock().expect("lock state");
    assert_eq!(snapshot.seen_since_values, vec![174, 0]);
}

#[test]
fn managed_vault_pull_with_progress_preserves_known_total_when_later_pages_omit_max() {
    let db_key = [71u8; 32];
    let sync_key = [72u8; 32];
    let remote_device_id = "remote-missing-max";

    let dir = tempdir().expect("tempdir");
    let conn = db::open(dir.path()).expect("open");
    conn.execute(
        r#"INSERT INTO kv(key, value) VALUES ('device_id', 'local-device-progress')"#,
        [],
    )
    .expect("set local device id");

    let first_page_ops = (1..=500)
        .map(|seq| {
            let conversation_id = format!("conversation-missing-max-{seq}");
            let title = format!("Title {seq}");
            (
                seq,
                format!("op-{conversation_id}"),
                encrypted_conversation_op(
                    &sync_key,
                    remote_device_id,
                    seq,
                    &conversation_id,
                    &title,
                    1_775_811_648_900 + seq,
                ),
            )
        })
        .collect::<Vec<_>>();
    let second_ciphertext_b64 = encrypted_conversation_op(
        &sync_key,
        remote_device_id,
        501,
        "conversation-missing-max-501",
        "Last title",
        1_775_811_649_500,
    );
    let base_url = spawn_missing_max_after_large_first_page_server(
        remote_device_id.to_string(),
        first_page_ops,
        second_ciphertext_b64,
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
    .expect("pull with missing max");

    assert_eq!(applied, 501);
    assert!(
        seen_progress.iter().all(|(_, total)| *total == 501),
        "known total should remain stable when later pages omit max: {seen_progress:?}"
    );

    let conversations = db::list_conversations(&conn, &db_key).expect("list conversations");
    assert!(conversations
        .iter()
        .any(|conversation| conversation.id == "conversation-missing-max-1"));
    assert!(conversations
        .iter()
        .any(|conversation| conversation.id == "conversation-missing-max-501"));
}
