use std::collections::BTreeMap;
use std::io::{Read, Write};
use std::net::{TcpListener, TcpStream};
use std::sync::mpsc;
use std::sync::{Arc, Mutex};
use std::thread;
use std::time::Duration;

use base64::engine::general_purpose::STANDARD as B64_STD;
use base64::Engine as _;

use secondloop_rust::auth;
use secondloop_rust::crypto::{derive_root_key, KdfParams};
use secondloop_rust::db;
use secondloop_rust::sync;

const PULL_BIN_MAGIC_V1: &[u8; 5] = b"SLVB1";

#[derive(Debug, Clone)]
struct StoredOp {
    device_id: String,
    seq: i64,
    op_id: String,
    ciphertext_b64: String,
}

#[derive(Default)]
struct ServerState {
    vault_devices: BTreeMap<String, Vec<String>>,
    ops: BTreeMap<(String, String), Vec<StoredOp>>,
    attachments: BTreeMap<(String, String), Vec<u8>>,
    attachment_request_methods: Vec<String>,
    omit_pull_max: bool,
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
        405 => "Method Not Allowed",
        _ => "OK",
    };
    let resp = format!(
        "HTTP/1.1 {status} {status_text}\r\nContent-Type: application/json\r\nContent-Length: {}\r\nConnection: close\r\n\r\n{body_str}",
        body_str.len()
    );
    stream.write_all(resp.as_bytes()).expect("write response");
}

fn write_bytes_response(stream: &mut TcpStream, status: u16, body: &[u8]) {
    let status_text = match status {
        200 => "OK",
        404 => "Not Found",
        _ => "OK",
    };
    let headers = format!(
        "HTTP/1.1 {status} {status_text}\r\nContent-Type: application/octet-stream\r\nContent-Length: {}\r\nConnection: close\r\n\r\n",
        body.len()
    );
    stream.write_all(headers.as_bytes()).expect("write headers");
    stream.write_all(body).expect("write body");
}

fn write_empty_response(stream: &mut TcpStream, status: u16) {
    let status_text = match status {
        200 => "OK",
        404 => "Not Found",
        _ => "OK",
    };
    let headers = format!(
        "HTTP/1.1 {status} {status_text}\r\nContent-Length: 0\r\nConnection: close\r\n\r\n"
    );
    stream.write_all(headers.as_bytes()).expect("write headers");
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

        let ciphertext = B64_STD
            .decode(op.ciphertext_b64.as_bytes())
            .expect("b64 decode");
        out.extend_from_slice(&(ciphertext.len() as u32).to_le_bytes());
        out.extend_from_slice(&ciphertext);
    }
    out
}

fn start_mock_server() -> (String, mpsc::Sender<()>, thread::JoinHandle<()>) {
    let (base_url, stop_tx, handle, _) = start_mock_server_with_state();
    (base_url, stop_tx, handle)
}

fn start_mock_server_with_state() -> (
    String,
    mpsc::Sender<()>,
    thread::JoinHandle<()>,
    Arc<Mutex<ServerState>>,
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
                let (_headers, method, path, body) = read_request(&mut stream);

                let segments: Vec<&str> = path.split('/').filter(|s| !s.is_empty()).collect();
                if segments.len() < 3 || segments[0] != "v1" || segments[1] != "vaults" {
                    write_json_response(
                        &mut stream,
                        404,
                        serde_json::json!({ "error": "not_found" }),
                    );
                    continue;
                }
                let vault_id = segments[2].to_string();
                let tail = segments[3..].join("/");

                if method == "POST" && tail == "devices" {
                    let decoded: serde_json::Value =
                        serde_json::from_slice(&body).expect("devices json");
                    let device_id = decoded
                        .get("device_id")
                        .and_then(|v| v.as_str())
                        .unwrap_or("dev")
                        .to_string();
                    {
                        let mut st = state_clone.lock().expect("lock");
                        st.vault_devices
                            .entry(vault_id.clone())
                            .or_default()
                            .push(device_id.clone());
                    }
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

                if method == "POST" && tail == "ops:push" {
                    let decoded: serde_json::Value =
                        serde_json::from_slice(&body).expect("push json");
                    let device_id = decoded
                        .get("device_id")
                        .and_then(|v| v.as_str())
                        .expect("device id")
                        .to_string();
                    let ops = decoded
                        .get("ops")
                        .and_then(|v| v.as_array())
                        .cloned()
                        .unwrap_or_default();
                    let mut max_seq = 0i64;
                    let mut st = state_clone.lock().expect("lock");
                    let entry = st
                        .ops
                        .entry((vault_id.clone(), device_id.clone()))
                        .or_default();
                    for op in ops {
                        let seq = op.get("seq").and_then(|v| v.as_i64()).expect("seq");
                        let op_id = op
                            .get("op_id")
                            .and_then(|v| v.as_str())
                            .expect("op_id")
                            .to_string();
                        let ciphertext_b64 = op
                            .get("ciphertext_b64")
                            .and_then(|v| v.as_str())
                            .expect("ciphertext")
                            .to_string();
                        entry.push(StoredOp {
                            device_id: device_id.clone(),
                            seq,
                            op_id,
                            ciphertext_b64,
                        });
                        max_seq = max_seq.max(seq);
                    }
                    write_json_response(
                        &mut stream,
                        200,
                        serde_json::json!({ "max_seq": max_seq }),
                    );
                    continue;
                }

                if method == "POST" && (tail == "ops:pull" || tail == "ops:pull_bin") {
                    let decoded: serde_json::Value =
                        serde_json::from_slice(&body).expect("pull json");
                    let request_device_id = decoded
                        .get("device_id")
                        .and_then(|v| v.as_str())
                        .unwrap_or("");
                    let since = decoded
                        .get("since")
                        .and_then(|v| v.as_object())
                        .cloned()
                        .unwrap_or_default();
                    let limit =
                        decoded.get("limit").and_then(|v| v.as_i64()).unwrap_or(100) as usize;

                    let mut out_json = Vec::<serde_json::Value>::new();
                    let mut out_bin = Vec::<StoredOp>::new();
                    let mut next = serde_json::Map::new();
                    let st = state_clone.lock().expect("lock");
                    for ((stored_vault_id, device_id), ops) in &st.ops {
                        if stored_vault_id != &vault_id || device_id == request_device_id {
                            continue;
                        }
                        let since_seq = since.get(device_id).and_then(|v| v.as_i64()).unwrap_or(0);
                        let mut max_seq = since_seq;
                        for op in ops {
                            if op.seq <= since_seq {
                                max_seq = max_seq.max(op.seq);
                                continue;
                            }
                            if out_json.len() >= limit {
                                continue;
                            }
                            out_json.push(serde_json::json!({
                                "device_id": op.device_id,
                                "seq": op.seq,
                                "op_id": op.op_id,
                                "ciphertext_b64": op.ciphertext_b64,
                            }));
                            out_bin.push(op.clone());
                            max_seq = max_seq.max(op.seq);
                        }
                        next.insert(device_id.clone(), serde_json::json!(max_seq));
                    }
                    if tail == "ops:pull_bin" {
                        write_bytes_response(&mut stream, 200, &encode_pull_bin(&out_bin));
                    } else {
                        let include_max = !st.omit_pull_max;
                        let max = if include_max {
                            let mut out_max = serde_json::Map::new();
                            for ((stored_vault_id, device_id), ops) in &st.ops {
                                if stored_vault_id != &vault_id || device_id == request_device_id {
                                    continue;
                                }
                                let max_seq = ops.iter().map(|op| op.seq).max().unwrap_or(0);
                                out_max.insert(device_id.clone(), serde_json::json!(max_seq));
                            }
                            Some(out_max)
                        } else {
                            None
                        };
                        let mut response = serde_json::Map::new();
                        response.insert("ops".to_string(), serde_json::Value::Array(out_json));
                        response.insert("next".to_string(), serde_json::Value::Object(next));
                        if let Some(max) = max {
                            response.insert("max".to_string(), serde_json::Value::Object(max));
                        }
                        write_json_response(&mut stream, 200, serde_json::Value::Object(response));
                    }
                    continue;
                }

                if tail.starts_with("attachments/") {
                    let attachment_id = tail.trim_start_matches("attachments/").to_string();
                    {
                        let mut st = state_clone.lock().expect("lock");
                        st.attachment_request_methods.push(method.clone());
                    }
                    if method == "PUT" {
                        let mut st = state_clone.lock().expect("lock");
                        st.attachments
                            .insert((vault_id.clone(), attachment_id), body);
                        write_json_response(&mut stream, 200, serde_json::json!({ "ok": true }));
                        continue;
                    }
                    if method == "HEAD" {
                        let st = state_clone.lock().expect("lock");
                        if st
                            .attachments
                            .contains_key(&(vault_id.clone(), attachment_id))
                        {
                            write_empty_response(&mut stream, 200);
                        } else {
                            write_empty_response(&mut stream, 404);
                        }
                        continue;
                    }
                    if method == "GET" {
                        let st = state_clone.lock().expect("lock");
                        if let Some(bytes) = st.attachments.get(&(vault_id.clone(), attachment_id))
                        {
                            write_bytes_response(&mut stream, 200, bytes);
                        } else {
                            write_json_response(
                                &mut stream,
                                404,
                                serde_json::json!({ "error": "not_found" }),
                            );
                        }
                        continue;
                    }
                }

                write_json_response(
                    &mut stream,
                    405,
                    serde_json::json!({ "error": "method_not_allowed" }),
                );
            }
            Err(err) if err.kind() == std::io::ErrorKind::WouldBlock => {
                thread::sleep(Duration::from_millis(10));
            }
            Err(err) => panic!("accept error: {err}"),
        }
    });

    (format!("http://{}", addr), stop_tx, handle, state)
}

fn message_updated_at(conn: &rusqlite::Connection, message_id: &str) -> i64 {
    conn.query_row(
        r#"SELECT updated_at FROM messages WHERE id = ?1"#,
        rusqlite::params![message_id],
        |row| row.get(0),
    )
    .expect("message updated_at")
}

#[test]
fn managed_vault_roundtrip_syncs_embedding_artifact_blobs() {
    let (base_url, stop_tx, handle) = start_mock_server();
    let vault_id = "vault-test".to_string();
    let id_token = "token-test".to_string();

    let temp_a = tempfile::tempdir().expect("tempdir A");
    let app_dir_a = temp_a.path().join("secondloop_a");
    let key_a =
        auth::init_master_password(&app_dir_a, "pw-a", KdfParams::for_test()).expect("init A");
    let conn_a = db::open(&app_dir_a).expect("open A db");
    let conversation =
        db::get_or_create_loop_home_conversation(&conn_a, &key_a).expect("conversation A");
    let message = db::insert_message(
        &conn_a,
        &key_a,
        &conversation.id,
        "user",
        "managed vault artifact note",
    )
    .expect("message A");
    let processed =
        db::process_pending_message_embeddings_default(&conn_a, &key_a, 10).expect("process A");
    assert_eq!(processed, 1);

    let revision = message_updated_at(&conn_a, &message.id);
    let profile_id = db::embedding_artifact_profile_id(
        secondloop_rust::embedding::DEFAULT_MODEL_NAME,
        secondloop_rust::embedding::DEFAULT_EMBED_DIM,
    );
    let manifests = db::list_active_embedding_artifacts_for_source_revision(
        &conn_a,
        "message",
        &message.id,
        revision,
        &profile_id,
    )
    .expect("manifests a");
    assert_eq!(manifests.len(), 1);
    let manifest = manifests[0].clone();
    assert!(db::has_embedding_artifact_blob(
        &app_dir_a,
        &manifest.blob_ref
    ));

    let sync_key = derive_root_key(
        "sync-passphrase",
        b"secondloop-sync1",
        &KdfParams::for_test(),
    )
    .expect("derive sync key");

    let pushed =
        sync::managed_vault::push(&conn_a, &key_a, &sync_key, &base_url, &vault_id, &id_token)
            .expect("push");
    assert!(pushed > 0);

    let temp_b = tempfile::tempdir().expect("tempdir B");
    let app_dir_b = temp_b.path().join("secondloop_b");
    let key_b =
        auth::init_master_password(&app_dir_b, "pw-b", KdfParams::for_test()).expect("init B");
    let conn_b = db::open(&app_dir_b).expect("open B db");

    let pulled =
        sync::managed_vault::pull(&conn_b, &key_b, &sync_key, &base_url, &vault_id, &id_token)
            .expect("pull");
    assert!(pulled > 0);

    let manifests_b = db::list_active_embedding_artifacts_for_source_revision(
        &conn_b,
        "message",
        &message.id,
        revision,
        &profile_id,
    )
    .expect("manifests b");
    assert_eq!(manifests_b.len(), 1);
    let manifest_b = manifests_b[0].clone();
    assert!(db::has_embedding_artifact_blob(
        &app_dir_b,
        &manifest_b.blob_ref
    ));

    conn_b
        .execute(r#"DELETE FROM message_embeddings"#, [])
        .expect("clear embeddings");
    conn_b
        .execute(
            r#"UPDATE messages SET needs_embedding = 1 WHERE id = ?1"#,
            rusqlite::params![message.id.as_str()],
        )
        .expect("mark pending");
    let processed_b =
        db::process_pending_message_embeddings_default(&conn_b, &key_b, 10).expect("process B");
    assert_eq!(processed_b, 1);

    let _ = stop_tx.send(());
    let _ = handle.join();
}

#[test]
fn managed_vault_pull_with_progress_includes_embedding_artifact_downloads() {
    let (base_url, stop_tx, handle) = start_mock_server();
    let vault_id = "vault-test".to_string();
    let id_token = "token-test".to_string();

    let temp_a = tempfile::tempdir().expect("tempdir A");
    let app_dir_a = temp_a.path().join("secondloop_a");
    let key_a =
        auth::init_master_password(&app_dir_a, "pw-a", KdfParams::for_test()).expect("init A");
    let conn_a = db::open(&app_dir_a).expect("open A db");
    let conversation =
        db::get_or_create_loop_home_conversation(&conn_a, &key_a).expect("conversation A");
    let _message = db::insert_message(
        &conn_a,
        &key_a,
        &conversation.id,
        "user",
        "managed vault artifact progress note",
    )
    .expect("message A");
    let processed =
        db::process_pending_message_embeddings_default(&conn_a, &key_a, 10).expect("process A");
    assert_eq!(processed, 1);

    let sync_key = derive_root_key(
        "sync-passphrase",
        b"secondloop-sync1",
        &KdfParams::for_test(),
    )
    .expect("derive sync key");

    let pushed =
        sync::managed_vault::push(&conn_a, &key_a, &sync_key, &base_url, &vault_id, &id_token)
            .expect("push");
    assert!(pushed > 0);

    let temp_b = tempfile::tempdir().expect("tempdir B");
    let app_dir_b = temp_b.path().join("secondloop_b");
    let key_b =
        auth::init_master_password(&app_dir_b, "pw-b", KdfParams::for_test()).expect("init B");
    let conn_b = db::open(&app_dir_b).expect("open B db");

    let mut seen: Vec<(u64, u64)> = Vec::new();
    let mut on_progress = |done: u64, total: u64| {
        seen.push((done, total));
    };

    let pulled = sync::managed_vault::pull_with_progress(
        &conn_b,
        &key_b,
        &sync_key,
        &base_url,
        &vault_id,
        &id_token,
        &mut on_progress,
    )
    .expect("pull with progress");
    assert!(pulled > 0);

    assert!(!seen.is_empty());
    let initial_total = seen.first().expect("first progress").1;
    assert!(
        initial_total > 0,
        "expected op progress total before artifact accounting: {seen:?}"
    );
    assert!(
        seen.iter()
            .any(|&(done, total)| done == initial_total && total == initial_total + 1),
        "expected artifact total to appear in progress after op accounting: {seen:?}"
    );
    assert_eq!(
        *seen.last().expect("last progress"),
        (initial_total + 1, initial_total + 1)
    );

    let _ = stop_tx.send(());
    let _ = handle.join();
}

#[test]
fn managed_vault_pull_with_progress_counts_ops_when_server_omits_max() {
    let (base_url, stop_tx, handle, state) = start_mock_server_with_state();
    let vault_id = "vault-test".to_string();
    let id_token = "token-test".to_string();

    let temp_a = tempfile::tempdir().expect("tempdir A");
    let app_dir_a = temp_a.path().join("secondloop_a");
    let key_a =
        auth::init_master_password(&app_dir_a, "pw-a", KdfParams::for_test()).expect("init A");
    let conn_a = db::open(&app_dir_a).expect("open A db");
    let conversation =
        db::get_or_create_loop_home_conversation(&conn_a, &key_a).expect("conversation A");
    let _message = db::insert_message(
        &conn_a,
        &key_a,
        &conversation.id,
        "user",
        "managed vault missing max progress note",
    )
    .expect("message A");
    let processed =
        db::process_pending_message_embeddings_default(&conn_a, &key_a, 10).expect("process A");
    assert_eq!(processed, 1);

    let sync_key = derive_root_key(
        "sync-passphrase",
        b"secondloop-sync1",
        &KdfParams::for_test(),
    )
    .expect("derive sync key");

    let pushed =
        sync::managed_vault::push(&conn_a, &key_a, &sync_key, &base_url, &vault_id, &id_token)
            .expect("push");
    assert!(pushed > 0);

    {
        let mut st = state.lock().expect("lock state");
        st.omit_pull_max = true;
    }

    let temp_b = tempfile::tempdir().expect("tempdir B");
    let app_dir_b = temp_b.path().join("secondloop_b");
    let key_b =
        auth::init_master_password(&app_dir_b, "pw-b", KdfParams::for_test()).expect("init B");
    let conn_b = db::open(&app_dir_b).expect("open B db");

    let mut seen: Vec<(u64, u64)> = Vec::new();
    let mut on_progress = |done: u64, total: u64| {
        seen.push((done, total));
    };

    let pulled = sync::managed_vault::pull_with_progress(
        &conn_b,
        &key_b,
        &sync_key,
        &base_url,
        &vault_id,
        &id_token,
        &mut on_progress,
    )
    .expect("pull with progress");
    assert!(pulled > 0);

    let first = *seen.first().expect("first progress");
    assert!(
        first.0 > 0,
        "expected op progress before artifact accounting: {seen:?}"
    );
    assert_eq!(
        first.0, first.1,
        "expected unknown-total op progress to start as done==total: {seen:?}"
    );
    assert!(
        seen.iter()
            .any(|&(done, total)| done == first.0 && total == first.1 + 1),
        "expected late-growing total after counting artifact downloads: {seen:?}"
    );
    assert_eq!(
        *seen.last().expect("last progress"),
        (first.0 + 1, first.1 + 1)
    );

    let _ = stop_tx.send(());
    let _ = handle.join();
}

#[test]
fn managed_vault_pull_with_progress_finishes_when_artifact_blob_is_missing() {
    let (base_url, stop_tx, handle, state) = start_mock_server_with_state();
    let vault_id = "vault-test".to_string();
    let id_token = "token-test".to_string();

    let temp_a = tempfile::tempdir().expect("tempdir A");
    let app_dir_a = temp_a.path().join("secondloop_a");
    let key_a =
        auth::init_master_password(&app_dir_a, "pw-a", KdfParams::for_test()).expect("init A");
    let conn_a = db::open(&app_dir_a).expect("open A db");
    let conversation =
        db::get_or_create_loop_home_conversation(&conn_a, &key_a).expect("conversation A");
    let _message = db::insert_message(
        &conn_a,
        &key_a,
        &conversation.id,
        "user",
        "managed vault missing artifact progress note",
    )
    .expect("message A");
    let processed =
        db::process_pending_message_embeddings_default(&conn_a, &key_a, 10).expect("process A");
    assert_eq!(processed, 1);

    let sync_key = derive_root_key(
        "sync-passphrase",
        b"secondloop-sync1",
        &KdfParams::for_test(),
    )
    .expect("derive sync key");

    let pushed =
        sync::managed_vault::push(&conn_a, &key_a, &sync_key, &base_url, &vault_id, &id_token)
            .expect("push");
    assert!(pushed > 0);

    {
        let mut st = state.lock().expect("lock state");
        st.attachments.clear();
    }

    let temp_b = tempfile::tempdir().expect("tempdir B");
    let app_dir_b = temp_b.path().join("secondloop_b");
    let key_b =
        auth::init_master_password(&app_dir_b, "pw-b", KdfParams::for_test()).expect("init B");
    let conn_b = db::open(&app_dir_b).expect("open B db");

    let mut seen: Vec<(u64, u64)> = Vec::new();
    let mut on_progress = |done: u64, total: u64| {
        seen.push((done, total));
    };

    let pulled = sync::managed_vault::pull_with_progress(
        &conn_b,
        &key_b,
        &sync_key,
        &base_url,
        &vault_id,
        &id_token,
        &mut on_progress,
    )
    .expect("pull with progress");
    assert!(pulled > 0);

    assert!(!seen.is_empty());
    let last = *seen.last().expect("last progress");
    assert_eq!(
        last.0, last.1,
        "progress should still complete when managed-vault artifact blob is missing: {seen:?}"
    );

    let _ = stop_tx.send(());
    let _ = handle.join();
}

#[test]
fn managed_vault_push_reuploads_bytes_after_fresh_device_remote_reset() {
    let (base_url, stop_tx, handle, state) = start_mock_server_with_state();
    let vault_id = "vault-test".to_string();
    let id_token = "token-test".to_string();

    let temp_a = tempfile::tempdir().expect("tempdir A");
    let app_dir_a = temp_a.path().join("secondloop_a");
    let key_a =
        auth::init_master_password(&app_dir_a, "pw-a", KdfParams::for_test()).expect("init A");
    let conn_a = db::open(&app_dir_a).expect("open A db");
    let conversation =
        db::get_or_create_loop_home_conversation(&conn_a, &key_a).expect("conversation A");
    let _message = db::insert_message(
        &conn_a,
        &key_a,
        &conversation.id,
        "user",
        "managed vault remote reset note",
    )
    .expect("message A");
    let processed =
        db::process_pending_message_embeddings_default(&conn_a, &key_a, 10).expect("process A");
    assert_eq!(processed, 1);

    let sync_key = derive_root_key(
        "sync-passphrase",
        b"secondloop-sync1",
        &KdfParams::for_test(),
    )
    .expect("derive sync key");

    let pushed_a =
        sync::managed_vault::push(&conn_a, &key_a, &sync_key, &base_url, &vault_id, &id_token)
            .expect("push A");
    assert!(pushed_a > 0);

    let initial_attachment_count = {
        let st = state.lock().expect("lock state");
        st.attachments.len()
    };
    assert!(initial_attachment_count > 0);

    let temp_b = tempfile::tempdir().expect("tempdir B");
    let app_dir_b = temp_b.path().join("secondloop_b");
    let key_b =
        auth::init_master_password(&app_dir_b, "pw-b", KdfParams::for_test()).expect("init B");
    let conn_b = db::open(&app_dir_b).expect("open B db");

    let pulled_b =
        sync::managed_vault::pull(&conn_b, &key_b, &sync_key, &base_url, &vault_id, &id_token)
            .expect("pull B");
    assert!(pulled_b > 0);

    {
        let mut st = state.lock().expect("lock state");
        st.attachments.clear();
    }

    let pushed_b =
        sync::managed_vault::push(&conn_b, &key_b, &sync_key, &base_url, &vault_id, &id_token)
            .expect("push B");
    assert_eq!(pushed_b, 0);

    let repaired_attachment_count = {
        let st = state.lock().expect("lock state");
        st.attachments.len()
    };
    assert!(
        repaired_attachment_count > 0,
        "fresh device should re-upload bytes after managed-vault remote reset"
    );

    let _ = stop_tx.send(());
    let _ = handle.join();
}

#[test]
fn managed_vault_push_does_not_skip_when_remote_metadata_has_gaps() {
    let (base_url, stop_tx, handle, state) = start_mock_server_with_state();
    let vault_id = "vault-test".to_string();
    let id_token = "token-test".to_string();

    let temp_a = tempfile::tempdir().expect("tempdir A");
    let app_dir_a = temp_a.path().join("secondloop_a");
    let key_a =
        auth::init_master_password(&app_dir_a, "pw-a", KdfParams::for_test()).expect("init A");
    let conn_a = db::open(&app_dir_a).expect("open A db");
    let _conversation =
        db::create_conversation(&conn_a, &key_a, "Gap repair").expect("conversation A");
    let _attachment = db::insert_attachment(
        &conn_a,
        &key_a,
        &app_dir_a,
        b"managed vault metadata gap",
        "image/png",
    )
    .expect("attachment A");

    let sync_key = derive_root_key(
        "sync-passphrase",
        b"secondloop-sync1",
        &KdfParams::for_test(),
    )
    .expect("derive sync key");

    let pushed_a =
        sync::managed_vault::push(&conn_a, &key_a, &sync_key, &base_url, &vault_id, &id_token)
            .expect("push A");
    assert!(pushed_a > 0);

    let device_id_a: String = conn_a
        .query_row(
            r#"SELECT value FROM kv WHERE key = 'device_id'"#,
            [],
            |row| row.get(0),
        )
        .expect("device id A");

    let temp_b = tempfile::tempdir().expect("tempdir B");
    let app_dir_b = temp_b.path().join("secondloop_b");
    let key_b =
        auth::init_master_password(&app_dir_b, "pw-b", KdfParams::for_test()).expect("init B");
    let conn_b = db::open(&app_dir_b).expect("open B db");

    let pulled_b =
        sync::managed_vault::pull(&conn_b, &key_b, &sync_key, &base_url, &vault_id, &id_token)
            .expect("pull B");
    assert!(pulled_b > 0);

    {
        let mut st = state.lock().expect("lock state");
        let ops = st
            .ops
            .get_mut(&(vault_id.clone(), device_id_a.clone()))
            .expect("device A ops");
        assert!(
            ops.len() > 1,
            "expected multiple ops to create a metadata gap"
        );
        ops.remove(0);
    }

    let pushed_b =
        sync::managed_vault::push(&conn_b, &key_b, &sync_key, &base_url, &vault_id, &id_token)
            .expect("push B");
    assert!(
        pushed_b > 0,
        "fresh device should not noop when remote metadata has gaps"
    );

    let _ = stop_tx.send(());
    let _ = handle.join();
}

#[test]
fn managed_vault_push_repairs_partially_missing_remote_bytes_for_fresh_device() {
    let (base_url, stop_tx, handle, state) = start_mock_server_with_state();
    let vault_id = "vault-test".to_string();
    let id_token = "token-test".to_string();

    let temp_a = tempfile::tempdir().expect("tempdir A");
    let app_dir_a = temp_a.path().join("secondloop_a");
    let key_a =
        auth::init_master_password(&app_dir_a, "pw-a", KdfParams::for_test()).expect("init A");
    let conn_a = db::open(&app_dir_a).expect("open A db");
    let conversation = db::get_or_create_loop_home_conversation(&conn_a, &key_a).expect("conv A");
    let _message_a = db::insert_message(
        &conn_a,
        &key_a,
        &conversation.id,
        "user",
        "managed vault artifact repair A",
    )
    .expect("message A");
    let _message_b = db::insert_message(
        &conn_a,
        &key_a,
        &conversation.id,
        "user",
        "managed vault artifact repair B",
    )
    .expect("message B");
    let processed = db::process_pending_message_embeddings_default(&conn_a, &key_a, 10)
        .expect("process embeddings A");
    assert_eq!(processed, 2);

    let sync_key = derive_root_key(
        "sync-passphrase",
        b"secondloop-sync1",
        &KdfParams::for_test(),
    )
    .expect("derive sync key");

    let pushed_a =
        sync::managed_vault::push(&conn_a, &key_a, &sync_key, &base_url, &vault_id, &id_token)
            .expect("push A");
    assert!(pushed_a > 0);

    let temp_b = tempfile::tempdir().expect("tempdir B");
    let app_dir_b = temp_b.path().join("secondloop_b");
    let key_b =
        auth::init_master_password(&app_dir_b, "pw-b", KdfParams::for_test()).expect("init B");
    let conn_b = db::open(&app_dir_b).expect("open B db");

    let pulled_b =
        sync::managed_vault::pull(&conn_b, &key_b, &sync_key, &base_url, &vault_id, &id_token)
            .expect("pull B");
    assert!(pulled_b > 0);

    let blob_refs = db::list_distinct_embedding_artifact_blob_refs(&conn_b).expect("blob refs B");
    assert_eq!(blob_refs.len(), 2);
    assert!(db::has_embedding_artifact_blob(&app_dir_b, &blob_refs[0]));
    assert!(db::has_embedding_artifact_blob(&app_dir_b, &blob_refs[1]));
    let missing_artifact_id = db::embedding_artifact_blob_storage_id(&blob_refs[1]);

    {
        let mut st = state.lock().expect("lock state");
        st.attachments
            .remove(&(vault_id.clone(), missing_artifact_id.clone()));
        st.attachment_request_methods.clear();
    }

    let _pushed_b =
        sync::managed_vault::push(&conn_b, &key_b, &sync_key, &base_url, &vault_id, &id_token)
            .expect("push B");
    let st = state.lock().expect("lock state");
    assert!(
        st.attachments
            .contains_key(&(vault_id.clone(), missing_artifact_id.clone())),
        "fresh device should repair partially missing remote bytes"
    );
    assert!(
        st.attachment_request_methods
            .iter()
            .any(|method| method == "HEAD"),
        "probe should use HEAD requests: {:?}",
        st.attachment_request_methods
    );
    assert!(
        !st.attachment_request_methods
            .iter()
            .any(|method| method == "GET"),
        "probe should avoid downloading bytes during existence checks: {:?}",
        st.attachment_request_methods
    );

    let _ = stop_tx.send(());
    let _ = handle.join();
}

#[test]
fn managed_vault_push_ops_only_with_progress_does_not_skip_when_remote_metadata_has_gaps() {
    let (base_url, stop_tx, handle, state) = start_mock_server_with_state();
    let vault_id = "vault-test".to_string();
    let id_token = "token-test".to_string();

    let temp_a = tempfile::tempdir().expect("tempdir A");
    let app_dir_a = temp_a.path().join("secondloop_a");
    let key_a =
        auth::init_master_password(&app_dir_a, "pw-a", KdfParams::for_test()).expect("init A");
    let conn_a = db::open(&app_dir_a).expect("open A db");
    let _conversation =
        db::create_conversation(&conn_a, &key_a, "Gap repair progress").expect("conversation A");
    let _attachment = db::insert_attachment(
        &conn_a,
        &key_a,
        &app_dir_a,
        b"managed vault metadata gap progress",
        "image/png",
    )
    .expect("attachment A");

    let sync_key = derive_root_key(
        "sync-passphrase",
        b"secondloop-sync1",
        &KdfParams::for_test(),
    )
    .expect("derive sync key");

    let pushed_a =
        sync::managed_vault::push(&conn_a, &key_a, &sync_key, &base_url, &vault_id, &id_token)
            .expect("push A");
    assert!(pushed_a > 0);

    let device_id_a: String = conn_a
        .query_row(
            r#"SELECT value FROM kv WHERE key = 'device_id'"#,
            [],
            |row| row.get(0),
        )
        .expect("device id A");

    let temp_b = tempfile::tempdir().expect("tempdir B");
    let app_dir_b = temp_b.path().join("secondloop_b");
    let key_b =
        auth::init_master_password(&app_dir_b, "pw-b", KdfParams::for_test()).expect("init B");
    let conn_b = db::open(&app_dir_b).expect("open B db");

    let pulled_b =
        sync::managed_vault::pull(&conn_b, &key_b, &sync_key, &base_url, &vault_id, &id_token)
            .expect("pull B");
    assert!(pulled_b > 0);

    {
        let mut st = state.lock().expect("lock state");
        let ops = st
            .ops
            .get_mut(&(vault_id.clone(), device_id_a.clone()))
            .expect("device A ops");
        assert!(
            ops.len() > 1,
            "expected multiple ops to create a metadata gap"
        );
        ops.remove(0);
    }

    let mut seen: Vec<(u64, u64)> = Vec::new();
    let mut on_progress = |done: u64, total: u64| {
        seen.push((done, total));
    };

    let pushed_b = sync::managed_vault::push_ops_only_with_progress(
        &conn_b,
        &key_b,
        &sync_key,
        &base_url,
        &vault_id,
        &id_token,
        &mut on_progress,
    )
    .expect("push B");

    assert!(
        pushed_b > 0,
        "progress push should not noop when remote metadata has gaps"
    );
    assert_ne!(seen, vec![(0, 0)]);

    let _ = stop_tx.send(());
    let _ = handle.join();
}

#[test]
fn managed_vault_pull_paginates_without_skipping_ops_at_limit_boundary() {
    let (base_url, stop_tx, handle) = start_mock_server();
    let vault_id = "vault-pagination".to_string();
    let id_token = "token-pagination".to_string();

    let temp_a = tempfile::tempdir().expect("tempdir A");
    let app_dir_a = temp_a.path().join("secondloop_a");
    let key_a =
        auth::init_master_password(&app_dir_a, "pw-a", KdfParams::for_test()).expect("init A");
    let conn_a = db::open(&app_dir_a).expect("open A db");
    let conversation =
        db::create_conversation(&conn_a, &key_a, "Pagination").expect("conversation A");

    for idx in 0..520 {
        db::insert_message(
            &conn_a,
            &key_a,
            &conversation.id,
            "user",
            &format!("pagination message {idx}"),
        )
        .expect("insert message");
    }

    let sync_key = derive_root_key(
        "sync-passphrase",
        b"secondloop-sync1",
        &KdfParams::for_test(),
    )
    .expect("derive sync key");

    let pushed =
        sync::managed_vault::push(&conn_a, &key_a, &sync_key, &base_url, &vault_id, &id_token)
            .expect("push");
    assert!(pushed >= 521);

    let temp_b = tempfile::tempdir().expect("tempdir B");
    let app_dir_b = temp_b.path().join("secondloop_b");
    let key_b =
        auth::init_master_password(&app_dir_b, "pw-b", KdfParams::for_test()).expect("init B");
    let conn_b = db::open(&app_dir_b).expect("open B db");

    let pulled =
        sync::managed_vault::pull(&conn_b, &key_b, &sync_key, &base_url, &vault_id, &id_token)
            .expect("pull");
    assert!(pulled >= 521);

    let message_count: i64 = conn_b
        .query_row("SELECT COUNT(*) FROM messages", [], |row| row.get(0))
        .expect("message count");
    assert_eq!(message_count, 520);

    let _ = stop_tx.send(());
    let _ = handle.join();
}
