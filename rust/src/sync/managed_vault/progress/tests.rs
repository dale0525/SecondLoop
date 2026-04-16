use super::*;

use std::io::{Read, Write};
use std::net::{TcpListener, TcpStream};
use std::sync::{Arc, Mutex};
use std::thread;

use base64::engine::general_purpose::STANDARD as B64_STD;
use tempfile::tempdir;

use crate::sync::{kv_get_i64, kv_set_i64};

#[derive(Default)]
struct ServerState {
    seen_since_values: Vec<i64>,
    seen_secondary_since_values: Vec<i64>,
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
        for _ in 0..6 {
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

            if request_line.starts_with("POST /v1/vaults/test-vault/ops:pull_v2 ") {
                respond_json(&mut stream, "404 Not Found", r#"{"error":"not_found"}"#);
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

fn spawn_progress_partial_then_recovery_server(
    first_device_id: String,
    first_ops: Vec<(i64, String, String)>,
    stalled_device_id: String,
    stalled_encrypted_op_b64: String,
    stalled_op_id: String,
) -> (String, Arc<Mutex<ServerState>>) {
    let listener = TcpListener::bind("127.0.0.1:0").expect("bind listener");
    let addr = format!("http://{}", listener.local_addr().expect("local addr"));
    let state = Arc::new(Mutex::new(ServerState::default()));
    let state_for_thread = Arc::clone(&state);

    thread::spawn(move || {
        for _ in 0..8 {
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

            if request_line.starts_with("POST /v1/vaults/test-vault/ops:pull_v2 ") {
                respond_json(&mut stream, "404 Not Found", r#"{"error":"not_found"}"#);
                continue;
            }

            if request_line.starts_with("POST /v1/vaults/test-vault/ops:pull ") {
                let payload: serde_json::Value =
                    serde_json::from_slice(&body).expect("parse pull body");
                let first_since = payload["since"][first_device_id.as_str()]
                    .as_i64()
                    .unwrap_or(0);
                let stalled_since = payload["since"][stalled_device_id.as_str()]
                    .as_i64()
                    .unwrap_or(174);

                let mut snapshot = state_for_thread.lock().expect("lock state");
                snapshot.seen_since_values.push(stalled_since);
                snapshot.seen_secondary_since_values.push(first_since);
                drop(snapshot);

                if first_since == 0 && stalled_since == 174 {
                    let first_ops_json = first_ops
                        .iter()
                        .map(|(seq, op_id, ciphertext_b64)| {
                            serde_json::json!({
                                "device_id": first_device_id,
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
                            r#"{{"ops":{first_ops_json},"next":{{"{first_device_id}":500}},"max":{{"{first_device_id}":500,"{stalled_device_id}":262}}}}"#,
                            first_device_id = first_device_id,
                            first_ops_json = serde_json::Value::Array(first_ops_json),
                            stalled_device_id = stalled_device_id,
                        ),
                    );
                    continue;
                }

                if first_since == 500 && stalled_since == 174 {
                    respond_json(
                        &mut stream,
                        "200 OK",
                        &format!(
                            r#"{{"ops":[],"next":{{}},"max":{{"{first_device_id}":500,"{stalled_device_id}":262}}}}"#,
                            first_device_id = first_device_id,
                            stalled_device_id = stalled_device_id,
                        ),
                    );
                    continue;
                }

                if first_since == 500 && stalled_since == 0 {
                    respond_json(
                        &mut stream,
                        "200 OK",
                        &format!(
                            r#"{{"ops":[{{"device_id":"{stalled_device_id}","seq":262,"op_id":"{stalled_op_id}","ciphertext_b64":"{stalled_ciphertext}"}}],"next":{{"{stalled_device_id}":262}},"max":{{"{first_device_id}":500,"{stalled_device_id}":262}}}}"#,
                            first_device_id = first_device_id,
                            stalled_device_id = stalled_device_id,
                            stalled_op_id = stalled_op_id,
                            stalled_ciphertext = stalled_encrypted_op_b64,
                        ),
                    );
                    continue;
                }

                respond_json(
                    &mut stream,
                    "200 OK",
                    &format!(
                        r#"{{"ops":[],"next":{{"{first_device_id}":500,"{stalled_device_id}":262}},"max":{{"{first_device_id}":500,"{stalled_device_id}":262}}}}"#,
                        first_device_id = first_device_id,
                        stalled_device_id = stalled_device_id,
                    ),
                );
                continue;
            }

            respond_json(&mut stream, "404 Not Found", r#"{"error":"not_found"}"#);
        }
    });

    (addr, state)
}

#[test]
fn pull_with_progress_recovers_when_remote_cursor_is_ahead_but_first_response_is_empty() {
    let db_key = [41u8; 32];
    let sync_key = [42u8; 32];
    let remote_device_id = "remote-device-progress";

    let dir = tempdir().expect("tempdir");
    let conn = crate::db::open(dir.path()).expect("open");
    conn.execute(
        r#"INSERT INTO kv(key, value) VALUES ('device_id', 'local-device-progress')"#,
        [],
    )
    .expect("set local device id");

    let op_id = "op-progress-recovery";
    let op_json = serde_json::json!({
        "op_id": op_id,
        "device_id": remote_device_id,
        "seq": 262,
        "ts_ms": 1_775_811_648_824i64,
        "type": "conversation.upsert.v1",
        "payload": {
            "conversation_id": "conversation-progress-recovery",
            "title": "Recovered title",
            "created_at_ms": 1_775_811_648_824i64,
            "updated_at_ms": 1_775_811_648_824i64,
        }
    });
    let plaintext = serde_json::to_vec(&op_json).expect("serialize op");
    let ciphertext = encrypt_bytes(
        &sync_key,
        &plaintext,
        format!("sync.ops:{remote_device_id}:262").as_bytes(),
    )
    .expect("encrypt op");
    let encrypted_op_b64 = B64_STD.encode(ciphertext);

    let (base_url, server_state) = spawn_progress_recovery_server(
        remote_device_id.to_string(),
        encrypted_op_b64,
        op_id.to_string(),
    );
    let scope_id = crate::sync::managed_vault::runtime::scope_id(&base_url, "test-vault");
    kv_set_i64(
        &conn,
        &format!("managed_vault.last_pulled_seq:{scope_id}:{remote_device_id}"),
        174,
    )
    .expect("set stale cursor");

    let mut seen_progress = Vec::new();
    let applied = pull_with_progress(
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
    assert_eq!(seen_progress.first().copied(), Some((0, 88)));
    assert_eq!(seen_progress.last().copied(), Some((88, 88)));

    let conversations = crate::db::list_conversations(&conn, &db_key).expect("list conversations");
    assert!(
        conversations
            .iter()
            .any(|conversation| conversation.id == "conversation-progress-recovery"),
        "expected recovered conversation to exist, got {conversations:?}"
    );

    let repaired_cursor = kv_get_i64(
        &conn,
        &format!("managed_vault.last_pulled_seq:{scope_id}:{remote_device_id}"),
    )
    .expect("get repaired cursor");
    assert_eq!(repaired_cursor, Some(262));

    let seen_since_values = server_state
        .lock()
        .expect("lock state")
        .seen_since_values
        .clone();
    assert_eq!(seen_since_values, vec![174, 0]);
}

#[test]
fn pull_with_progress_does_not_reset_completed_work_when_remote_cursor_is_repaired() {
    let db_key = [51u8; 32];
    let sync_key = [52u8; 32];
    let first_device_id = "remote-device-fast";
    let stalled_device_id = "remote-device-stalled";

    let dir = tempdir().expect("tempdir");
    let conn = crate::db::open(dir.path()).expect("open");
    conn.execute(
        r#"INSERT INTO kv(key, value) VALUES ('device_id', 'local-device-progress')"#,
        [],
    )
    .expect("set local device id");

    let first_ops = (1..=500)
        .map(|seq| {
            let op_id = format!("op-progress-first-{seq}");
            let op_json = serde_json::json!({
                "op_id": op_id,
                "device_id": first_device_id,
                "seq": seq,
                "ts_ms": 1_775_811_648_824i64 + seq,
                "type": "conversation.upsert.v1",
                "payload": {
                    "conversation_id": format!("conversation-progress-first-{seq}"),
                    "title": format!("First title {seq}"),
                    "created_at_ms": 1_775_811_648_824i64 + seq,
                    "updated_at_ms": 1_775_811_648_824i64 + seq,
                }
            });
            let plaintext = serde_json::to_vec(&op_json).expect("serialize first op");
            let ciphertext = encrypt_bytes(
                &sync_key,
                &plaintext,
                format!("sync.ops:{first_device_id}:{seq}").as_bytes(),
            )
            .expect("encrypt first op");
            (seq, op_id, B64_STD.encode(ciphertext))
        })
        .collect::<Vec<_>>();

    let stalled_op_id = "op-progress-stalled";
    let stalled_op_json = serde_json::json!({
        "op_id": stalled_op_id,
        "device_id": stalled_device_id,
        "seq": 262,
        "ts_ms": 1_775_811_648_825i64,
        "type": "conversation.upsert.v1",
        "payload": {
            "conversation_id": "conversation-progress-stalled",
            "title": "Stalled title",
            "created_at_ms": 1_775_811_648_825i64,
            "updated_at_ms": 1_775_811_648_825i64,
        }
    });
    let stalled_plaintext = serde_json::to_vec(&stalled_op_json).expect("serialize stalled op");
    let stalled_ciphertext = encrypt_bytes(
        &sync_key,
        &stalled_plaintext,
        format!("sync.ops:{stalled_device_id}:262").as_bytes(),
    )
    .expect("encrypt stalled op");

    let (base_url, server_state) = spawn_progress_partial_then_recovery_server(
        first_device_id.to_string(),
        first_ops,
        stalled_device_id.to_string(),
        B64_STD.encode(stalled_ciphertext),
        stalled_op_id.to_string(),
    );
    let scope_id = crate::sync::managed_vault::runtime::scope_id(&base_url, "test-vault");
    kv_set_i64(
        &conn,
        &format!("managed_vault.last_pulled_seq:{scope_id}:{stalled_device_id}"),
        174,
    )
    .expect("set stalled cursor");

    let mut seen_progress = Vec::new();
    let applied = pull_with_progress(
        &conn,
        &db_key,
        &sync_key,
        &base_url,
        "test-vault",
        "test-token",
        &mut |done, total| seen_progress.push((done, total)),
    )
    .expect("pull with recovery");

    assert!(applied >= 500);
    assert!(
        seen_progress
            .windows(2)
            .all(|window| window[1].0 >= window[0].0),
        "progress should not go backwards: {seen_progress:?}"
    );
    assert_eq!(seen_progress.last().copied(), Some((588, 588)));

    let conversations = crate::db::list_conversations(&conn, &db_key).expect("list conversations");
    assert!(
        conversations
            .iter()
            .any(|conversation| conversation.id == "conversation-progress-first-1"),
        "expected first conversation to exist, got {conversations:?}"
    );
    assert!(
        conversations
            .iter()
            .any(|conversation| conversation.id == "conversation-progress-stalled"),
        "expected stalled conversation to exist, got {conversations:?}"
    );

    let snapshot = server_state.lock().expect("lock state");
    assert_eq!(snapshot.seen_secondary_since_values, vec![0, 500, 500]);
    assert_eq!(snapshot.seen_since_values, vec![174, 174, 0]);
}
