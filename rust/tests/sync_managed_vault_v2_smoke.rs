use std::io::{Read, Write};
use std::net::{TcpListener, TcpStream};
use std::sync::mpsc;
use std::sync::{Arc, Mutex};
use std::thread;
use std::time::Duration;

use base64::engine::general_purpose::URL_SAFE_NO_PAD as B64_URL;
use base64::Engine as _;
use rusqlite::OptionalExtension;
use secondloop_rust::auth;
use secondloop_rust::crypto::{derive_root_key, KdfParams};
use secondloop_rust::db;
use secondloop_rust::sync;

#[derive(Default)]
struct V2ServerState {
    generation_id: String,
    latest_global_seq: i64,
    ops: Vec<serde_json::Value>,
    attachments: std::collections::BTreeMap<String, Vec<u8>>,
    requests: Vec<String>,
    require_generation_for_push_without_id: bool,
    gap_pull_once_after_global_seq: Option<i64>,
    reset_required_once_after_global_seq: Option<i64>,
    pull_page_size: Option<usize>,
    switch_generation_once_after_global_seq: Option<i64>,
    switch_generation_id: Option<String>,
    switch_generation_latest_global_seq: Option<i64>,
    switch_generation_ops: Vec<serde_json::Value>,
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
        assert!(n > 0, "unexpected eof body");
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

fn start_mock_v2_server() -> (
    String,
    mpsc::Sender<()>,
    Arc<Mutex<V2ServerState>>,
    thread::JoinHandle<()>,
) {
    let listener = TcpListener::bind("127.0.0.1:0").expect("bind");
    listener.set_nonblocking(true).expect("nonblocking");
    let addr = listener.local_addr().expect("local addr");

    let (stop_tx, stop_rx) = mpsc::channel::<()>();
    let state = Arc::new(Mutex::new(V2ServerState {
        generation_id: "generation-a".to_string(),
        ..V2ServerState::default()
    }));
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
                    ("GET", "/v2/vaults/v1/sync/head") => {
                        let state = state_clone.lock().expect("lock");
                        write_json_response(
                            &mut stream,
                            200,
                            serde_json::json!({
                                "generation_id": state.generation_id,
                                "remote_latest_global_seq": state.latest_global_seq,
                            }),
                        );
                    }
                    ("POST", "/v2/vaults/v1/sync/push") => {
                        let decoded: serde_json::Value =
                            serde_json::from_slice(&body).expect("push json");
                        let incoming = decoded["ops"].as_array().cloned().expect("ops array");
                        let mut state = state_clone.lock().expect("lock");
                        let client_generation = decoded["generation_id"]
                            .as_str()
                            .unwrap_or("")
                            .trim()
                            .to_string();
                        if client_generation.is_empty()
                            && state.require_generation_for_push_without_id
                        {
                            write_json_response(
                                &mut stream,
                                409,
                                serde_json::json!({
                                    "error": "generation_required",
                                    "remote_generation_id": state.generation_id,
                                    "remote_latest_global_seq": state.latest_global_seq,
                                }),
                            );
                            continue;
                        }
                        if !client_generation.is_empty() && client_generation != state.generation_id
                        {
                            write_json_response(
                                &mut stream,
                                409,
                                serde_json::json!({
                                    "error": "generation_mismatch",
                                    "remote_generation_id": state.generation_id,
                                    "remote_latest_global_seq": state.latest_global_seq,
                                }),
                            );
                            continue;
                        }
                        let from_seq = state.latest_global_seq + 1;
                        for op in incoming {
                            state.latest_global_seq += 1;
                            let mut value = op;
                            value["global_seq"] = serde_json::Value::from(state.latest_global_seq);
                            state.ops.push(value);
                        }
                        write_json_response(
                            &mut stream,
                            200,
                            serde_json::json!({
                                "generation_id": state.generation_id,
                                "accepted": decoded["ops"].as_array().map(|ops| ops.len()).unwrap_or(0),
                                "committed_from_seq": from_seq,
                                "committed_to_seq": state.latest_global_seq,
                                "remote_latest_global_seq": state.latest_global_seq,
                            }),
                        );
                    }
                    ("POST", "/v2/vaults/v1/sync/reset") => {
                        let mut state = state_clone.lock().expect("lock");
                        state.generation_id = "generation-reset".to_string();
                        state.latest_global_seq = 0;
                        state.ops.clear();
                        write_json_response(
                            &mut stream,
                            200,
                            serde_json::json!({
                                "generation_id": state.generation_id,
                                "remote_latest_global_seq": 0,
                                "deleted_meta": 0,
                                "deleted_blobs": 0,
                            }),
                        );
                    }
                    ("POST", "/v2/vaults/v1/sync/pull") => {
                        let decoded: serde_json::Value =
                            serde_json::from_slice(&body).expect("pull json");
                        let after = decoded["after_global_seq"].as_i64().unwrap_or(0);
                        let limit = decoded["limit"].as_u64().unwrap_or(100) as usize;
                        let mut state = state_clone.lock().expect("lock");
                        if state.reset_required_once_after_global_seq == Some(after) {
                            state.reset_required_once_after_global_seq = None;
                            write_json_response(
                                &mut stream,
                                409,
                                serde_json::json!({
                                    "error": "reset_required",
                                    "reason": "global_log_gap",
                                    "remote_generation_id": state.generation_id,
                                    "remote_latest_global_seq": state.latest_global_seq,
                                }),
                            );
                            continue;
                        }
                        if state.gap_pull_once_after_global_seq == Some(after) {
                            state.gap_pull_once_after_global_seq = None;
                            let gap_ops = state
                                .ops
                                .iter()
                                .filter(|item| item["global_seq"].as_i64().unwrap_or(0) > after)
                                .map(|item| {
                                    let mut value = item.clone();
                                    let current = value["global_seq"].as_i64().unwrap_or(0);
                                    value["global_seq"] = serde_json::Value::from(current + 1);
                                    value
                                })
                                .collect::<Vec<_>>();
                            write_json_response(
                                &mut stream,
                                200,
                                serde_json::json!({
                                    "generation_id": state.generation_id,
                                    "remote_latest_global_seq": state.latest_global_seq + 1,
                                    "has_more": false,
                                    "ops": gap_ops,
                                }),
                            );
                            continue;
                        }
                        if state.switch_generation_once_after_global_seq == Some(after) {
                            state.switch_generation_once_after_global_seq = None;
                            state.generation_id =
                                state.switch_generation_id.take().unwrap_or_default();
                            state.latest_global_seq = state
                                .switch_generation_latest_global_seq
                                .take()
                                .unwrap_or(0);
                            state.ops = std::mem::take(&mut state.switch_generation_ops);
                        }
                        let page_size = state.pull_page_size.unwrap_or(limit).max(1);
                        let all_ops: Vec<serde_json::Value> = state
                            .ops
                            .iter()
                            .filter(|item| item["global_seq"].as_i64().unwrap_or(0) > after)
                            .cloned()
                            .collect();
                        let has_more = all_ops.len() > page_size;
                        let ops: Vec<serde_json::Value> =
                            all_ops.into_iter().take(page_size).collect();
                        write_json_response(
                            &mut stream,
                            200,
                            serde_json::json!({
                                "generation_id": state.generation_id,
                                "remote_latest_global_seq": state.latest_global_seq,
                                "has_more": has_more,
                                "ops": ops,
                            }),
                        );
                    }
                    ("GET", path) if path.starts_with("/v1/vaults/v1/attachments/") => {
                        let artifact_id = path
                            .strip_prefix("/v1/vaults/v1/attachments/")
                            .unwrap_or_default()
                            .to_string();
                        let state = state_clone.lock().expect("lock");
                        if let Some(bytes) = state.attachments.get(&artifact_id) {
                            let response = format!(
                                "HTTP/1.1 200 OK\r\nContent-Type: application/octet-stream\r\nContent-Length: {}\r\nConnection: close\r\n\r\n",
                                bytes.len()
                            );
                            stream
                                .write_all(response.as_bytes())
                                .expect("write headers");
                            stream.write_all(bytes).expect("write body");
                        } else {
                            write_json_response(
                                &mut stream,
                                404,
                                serde_json::json!({ "error": "not_found" }),
                            );
                        }
                    }
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

fn managed_vault_v2_scope_id(base_url: &str, vault_id: &str) -> String {
    B64_URL.encode(format!("managed_vault|{}|{}", base_url.trim(), vault_id.trim()).as_bytes())
}

#[test]
fn managed_vault_v2_push_and_pull_roundtrip() {
    let (base_url, stop_tx, state, handle) = start_mock_v2_server();
    let vault_id = "v1".to_string();
    let id_token = "test_uid".to_string();

    let temp_a = tempfile::tempdir().expect("tempdir A");
    let app_dir_a = temp_a.path().join("secondloop_a");
    let key_a =
        auth::init_master_password(&app_dir_a, "pw-a", KdfParams::for_test()).expect("init A");
    let conn_a = db::open(&app_dir_a).expect("open A db");
    let conv_a = db::create_conversation(&conn_a, &key_a, "Inbox").expect("create convo A");
    db::insert_message(&conn_a, &key_a, &conv_a.id, "user", "hello").expect("insert msg A");

    let temp_b = tempfile::tempdir().expect("tempdir B");
    let app_dir_b = temp_b.path().join("secondloop_b");
    let key_b =
        auth::init_master_password(&app_dir_b, "pw-b", KdfParams::for_test()).expect("init B");
    let conn_b = db::open(&app_dir_b).expect("open B db");

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

    let pulled =
        sync::managed_vault::pull(&conn_b, &key_b, &sync_key, &base_url, &vault_id, &id_token)
            .expect("pull");
    assert!(pulled > 0);

    let convs_b = db::list_conversations(&conn_b, &key_b).expect("list convs B");
    assert_eq!(convs_b.len(), 1);
    let msgs_b = db::list_messages(&conn_b, &key_b, &convs_b[0].id).expect("list msgs B");
    assert_eq!(msgs_b.len(), 1);
    assert_eq!(msgs_b[0].content, "hello");

    let requests = state.lock().expect("lock").requests.join("\n\n");
    assert!(requests.contains("/v2/vaults/v1/sync/push"));
    assert!(requests.contains("/v2/vaults/v1/sync/pull"));
    assert!(!requests.contains("/v2/vaults/v1/sync/head"));

    stop_tx.send(()).expect("stop");
    handle.join().expect("join");
}

#[test]
fn managed_vault_v2_generation_mismatch_preserves_local_data_until_pull_recovers() {
    let (base_url, stop_tx, state, handle) = start_mock_v2_server();
    let vault_id = "v1".to_string();
    let id_token = "test_uid".to_string();

    let temp = tempfile::tempdir().expect("tempdir");
    let app_dir = temp.path().join("secondloop");
    let key = auth::init_master_password(&app_dir, "pw", KdfParams::for_test()).expect("init");
    let conn = db::open(&app_dir).expect("open db");

    let sync_key = derive_root_key(
        "sync-passphrase",
        b"secondloop-sync1",
        &KdfParams::for_test(),
    )
    .expect("derive sync key");

    let conv = db::create_conversation(&conn, &key, "Inbox").expect("create convo");
    db::insert_message(&conn, &key, &conv.id, "user", "hello").expect("insert msg");

    let first_push =
        sync::managed_vault::push_ops_only(&conn, &key, &sync_key, &base_url, &vault_id, &id_token)
            .expect("first push");
    assert!(first_push > 0);

    {
        let mut server = state.lock().expect("lock");
        server.generation_id = "generation-reset".to_string();
        server.latest_global_seq = 0;
        server.ops.clear();
    }

    db::insert_message(&conn, &key, &conv.id, "user", "after reset")
        .expect("insert msg after reset");

    let second_push_error =
        sync::managed_vault::push_ops_only(&conn, &key, &sync_key, &base_url, &vault_id, &id_token)
            .expect_err("second push should fail");
    assert!(
        second_push_error
            .to_string()
            .contains("generation_mismatch"),
        "unexpected error: {second_push_error:#}"
    );

    let convs_before_pull = db::list_conversations(&conn, &key).expect("list convs before pull");
    assert_eq!(convs_before_pull.len(), 1);

    let recovery_pull =
        sync::managed_vault::pull(&conn, &key, &sync_key, &base_url, &vault_id, &id_token)
            .expect("recovery pull");
    assert_eq!(recovery_pull, 0);

    let convs_after_pull = db::list_conversations(&conn, &key).expect("list convs after pull");
    assert_eq!(convs_after_pull.len(), 0);

    let state = state.lock().expect("lock");
    assert_eq!(state.latest_global_seq, 0);
    assert_eq!(state.ops.len(), 0);

    stop_tx.send(()).expect("stop");
    handle.join().expect("join");
}

#[test]
fn managed_vault_v2_missing_local_generation_preserves_local_data_until_pull_recovers() {
    let (base_url, stop_tx, state, handle) = start_mock_v2_server();
    let vault_id = "v1".to_string();
    let id_token = "test_uid".to_string();

    {
        let mut server = state.lock().expect("lock");
        server.require_generation_for_push_without_id = true;
    }

    let temp = tempfile::tempdir().expect("tempdir");
    let app_dir = temp.path().join("secondloop");
    let key = auth::init_master_password(&app_dir, "pw", KdfParams::for_test()).expect("init");
    let conn = db::open(&app_dir).expect("open db");

    let sync_key = derive_root_key(
        "sync-passphrase",
        b"secondloop-sync1",
        &KdfParams::for_test(),
    )
    .expect("derive sync key");

    let conv = db::create_conversation(&conn, &key, "Inbox").expect("create convo");
    db::insert_message(&conn, &key, &conv.id, "user", "hello").expect("insert msg");

    let push_error =
        sync::managed_vault::push_ops_only(&conn, &key, &sync_key, &base_url, &vault_id, &id_token)
            .expect_err("push should fail");
    assert!(
        push_error.to_string().contains("generation_required"),
        "unexpected error: {push_error:#}"
    );

    let convs_before_pull = db::list_conversations(&conn, &key).expect("list convs before pull");
    assert_eq!(convs_before_pull.len(), 1);

    let requests = state.lock().expect("lock").requests.join("\n\n");
    assert!(
        requests.contains("\"error\":\"generation_required\"")
            || requests.contains("/v2/vaults/v1/sync/push")
    );
    drop(requests);

    let state = state.lock().expect("lock");
    assert_eq!(state.ops.len(), 0);

    stop_tx.send(()).expect("stop");
    handle.join().expect("join");
}

#[test]
fn managed_vault_v2_empty_remote_pull_does_not_persist_generation_state() {
    let (base_url, stop_tx, state, handle) = start_mock_v2_server();
    let vault_id = "v1".to_string();
    let id_token = "test_uid".to_string();

    {
        let mut server = state.lock().expect("lock");
        server.generation_id.clear();
        server.latest_global_seq = 0;
        server.ops.clear();
    }

    let temp = tempfile::tempdir().expect("tempdir");
    let app_dir = temp.path().join("secondloop");
    let key = auth::init_master_password(&app_dir, "pw", KdfParams::for_test()).expect("init");
    let conn = db::open(&app_dir).expect("open db");

    let sync_key = derive_root_key(
        "sync-passphrase",
        b"secondloop-sync1",
        &KdfParams::for_test(),
    )
    .expect("derive sync key");

    let pulled = sync::managed_vault::pull(&conn, &key, &sync_key, &base_url, &vault_id, &id_token)
        .expect("pull");
    assert_eq!(pulled, 0);

    let generation_key = format!(
        "managed_vault_v2.generation_id:{}",
        managed_vault_v2_scope_id(&base_url, &vault_id)
    );
    let generation: Option<String> = conn
        .query_row(
            "SELECT value FROM kv WHERE key = ?1",
            rusqlite::params![generation_key],
            |row| row.get(0),
        )
        .optional()
        .expect("load generation");
    assert_eq!(generation, None);

    stop_tx.send(()).expect("stop");
    handle.join().expect("join");
}

#[test]
fn managed_vault_v2_pull_rebuilds_after_non_contiguous_page() {
    let (base_url, stop_tx, state, handle) = start_mock_v2_server();
    let vault_id = "v1".to_string();
    let id_token = "test_uid".to_string();

    let temp_a = tempfile::tempdir().expect("tempdir A");
    let app_dir_a = temp_a.path().join("secondloop_a");
    let key_a =
        auth::init_master_password(&app_dir_a, "pw-a", KdfParams::for_test()).expect("init A");
    let conn_a = db::open(&app_dir_a).expect("open A db");
    let conv_a = db::create_conversation(&conn_a, &key_a, "Inbox").expect("create convo A");
    db::insert_message(&conn_a, &key_a, &conv_a.id, "user", "hello").expect("insert msg A");

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
    let expected_last_applied = state.lock().expect("lock").latest_global_seq;

    let temp_b = tempfile::tempdir().expect("tempdir B");
    let app_dir_b = temp_b.path().join("secondloop_b");
    let key_b =
        auth::init_master_password(&app_dir_b, "pw-b", KdfParams::for_test()).expect("init B");
    let conn_b = db::open(&app_dir_b).expect("open B db");

    let scope_id = managed_vault_v2_scope_id(&base_url, &vault_id);
    conn_b
        .execute(
            "INSERT INTO kv(key, value) VALUES (?1, ?2)
             ON CONFLICT(key) DO UPDATE SET value = excluded.value",
            rusqlite::params![
                format!("managed_vault_v2.generation_id:{scope_id}"),
                "generation-a"
            ],
        )
        .expect("seed generation");

    {
        let mut server = state.lock().expect("lock");
        server.gap_pull_once_after_global_seq = Some(0);
    }

    let pulled =
        sync::managed_vault::pull(&conn_b, &key_b, &sync_key, &base_url, &vault_id, &id_token)
            .expect("pull");
    assert!(pulled > 0);

    let convs_b = db::list_conversations(&conn_b, &key_b).expect("list convs B");
    assert_eq!(convs_b.len(), 1);
    let msgs_b = db::list_messages(&conn_b, &key_b, &convs_b[0].id).expect("list msgs B");
    assert_eq!(msgs_b.len(), 1);
    assert_eq!(msgs_b[0].content, "hello");
    let last_applied: Option<String> = conn_b
        .query_row(
            "SELECT value FROM kv WHERE key = ?1",
            rusqlite::params![format!(
                "managed_vault_v2.last_applied_global_seq:{}",
                managed_vault_v2_scope_id(&base_url, &vault_id)
            )],
            |row| row.get(0),
        )
        .optional()
        .expect("load last_applied");
    let expected_last_applied_text = expected_last_applied.to_string();
    assert_eq!(
        last_applied.as_deref(),
        Some(expected_last_applied_text.as_str()),
    );

    stop_tx.send(()).expect("stop");
    handle.join().expect("join");
}

#[test]
fn managed_vault_v2_pull_generation_switch_resets_applied_count() {
    let (base_url, stop_tx, state, handle) = start_mock_v2_server();
    let vault_id = "v1".to_string();
    let id_token = "test_uid".to_string();

    let sync_key = derive_root_key(
        "sync-passphrase",
        b"secondloop-sync1",
        &KdfParams::for_test(),
    )
    .expect("derive sync key");

    let temp_a = tempfile::tempdir().expect("tempdir A");
    let app_dir_a = temp_a.path().join("secondloop_a");
    let key_a =
        auth::init_master_password(&app_dir_a, "pw-a", KdfParams::for_test()).expect("init A");
    let conn_a = db::open(&app_dir_a).expect("open A db");
    let conv_a = db::create_conversation(&conn_a, &key_a, "Inbox").expect("create convo A");
    db::insert_message(&conn_a, &key_a, &conv_a.id, "user", "old generation")
        .expect("insert msg A");
    let pushed_old =
        sync::managed_vault::push(&conn_a, &key_a, &sync_key, &base_url, &vault_id, &id_token)
            .expect("push old generation");
    assert!(pushed_old > 0);

    let (old_generation_id, old_latest_global_seq, old_ops) = {
        let server = state.lock().expect("lock");
        (
            server.generation_id.clone(),
            server.latest_global_seq,
            server.ops.clone(),
        )
    };
    assert!(old_latest_global_seq > 0);

    {
        let mut server = state.lock().expect("lock");
        server.generation_id = "generation-b".to_string();
        server.latest_global_seq = 0;
        server.ops.clear();
    }

    let temp_c = tempfile::tempdir().expect("tempdir C");
    let app_dir_c = temp_c.path().join("secondloop_c");
    let key_c =
        auth::init_master_password(&app_dir_c, "pw-c", KdfParams::for_test()).expect("init C");
    let conn_c = db::open(&app_dir_c).expect("open C db");
    let conv_c = db::create_conversation(&conn_c, &key_c, "Inbox").expect("create convo C");
    db::insert_message(&conn_c, &key_c, &conv_c.id, "user", "new generation")
        .expect("insert msg C");
    let pushed_new =
        sync::managed_vault::push(&conn_c, &key_c, &sync_key, &base_url, &vault_id, &id_token)
            .expect("push new generation");
    assert!(pushed_new > 0);

    let (new_generation_id, new_latest_global_seq, new_ops) = {
        let server = state.lock().expect("lock");
        (
            server.generation_id.clone(),
            server.latest_global_seq,
            server.ops.clone(),
        )
    };
    assert_ne!(new_generation_id, old_generation_id);
    assert!(new_latest_global_seq > 0);

    {
        let mut server = state.lock().expect("lock");
        server.generation_id = old_generation_id;
        server.latest_global_seq = old_latest_global_seq;
        server.ops = old_ops;
        server.pull_page_size = Some(1);
        server.switch_generation_once_after_global_seq = Some(1);
        server.switch_generation_id = Some(new_generation_id);
        server.switch_generation_latest_global_seq = Some(new_latest_global_seq);
        server.switch_generation_ops = new_ops;
    }

    let temp_b = tempfile::tempdir().expect("tempdir B");
    let app_dir_b = temp_b.path().join("secondloop_b");
    let key_b =
        auth::init_master_password(&app_dir_b, "pw-b", KdfParams::for_test()).expect("init B");
    let conn_b = db::open(&app_dir_b).expect("open B db");

    let pulled =
        sync::managed_vault::pull(&conn_b, &key_b, &sync_key, &base_url, &vault_id, &id_token)
            .expect("pull after generation switch");
    assert_eq!(pulled, new_latest_global_seq as u64);

    let convs_b = db::list_conversations(&conn_b, &key_b).expect("list convs B");
    assert_eq!(convs_b.len(), 1);
    let msgs_b = db::list_messages(&conn_b, &key_b, &convs_b[0].id).expect("list msgs B");
    assert_eq!(msgs_b.len(), 1);
    assert_eq!(msgs_b[0].content, "new generation");

    stop_tx.send(()).expect("stop");
    handle.join().expect("join");
}

#[test]
fn managed_vault_v2_pull_rebuilds_after_reset_required_response() {
    let (base_url, stop_tx, state, handle) = start_mock_v2_server();
    let vault_id = "v1".to_string();
    let id_token = "test_uid".to_string();

    let temp_a = tempfile::tempdir().expect("tempdir A");
    let app_dir_a = temp_a.path().join("secondloop_a");
    let key_a =
        auth::init_master_password(&app_dir_a, "pw-a", KdfParams::for_test()).expect("init A");
    let conn_a = db::open(&app_dir_a).expect("open A db");
    let conv_a = db::create_conversation(&conn_a, &key_a, "Inbox").expect("create convo A");
    db::insert_message(&conn_a, &key_a, &conv_a.id, "user", "hello").expect("insert msg A");

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
    let expected_last_applied = state.lock().expect("lock").latest_global_seq;

    let temp_b = tempfile::tempdir().expect("tempdir B");
    let app_dir_b = temp_b.path().join("secondloop_b");
    let key_b =
        auth::init_master_password(&app_dir_b, "pw-b", KdfParams::for_test()).expect("init B");
    let conn_b = db::open(&app_dir_b).expect("open B db");

    let scope_id = managed_vault_v2_scope_id(&base_url, &vault_id);
    conn_b
        .execute(
            "INSERT INTO kv(key, value) VALUES (?1, ?2)
             ON CONFLICT(key) DO UPDATE SET value = excluded.value",
            rusqlite::params![
                format!("managed_vault_v2.generation_id:{scope_id}"),
                "generation-a"
            ],
        )
        .expect("seed generation");

    {
        let mut server = state.lock().expect("lock");
        server.reset_required_once_after_global_seq = Some(0);
    }

    let pulled =
        sync::managed_vault::pull(&conn_b, &key_b, &sync_key, &base_url, &vault_id, &id_token)
            .expect("pull");
    assert!(pulled > 0);

    let convs_b = db::list_conversations(&conn_b, &key_b).expect("list convs B");
    assert_eq!(convs_b.len(), 1);
    let msgs_b = db::list_messages(&conn_b, &key_b, &convs_b[0].id).expect("list msgs B");
    assert_eq!(msgs_b.len(), 1);
    assert_eq!(msgs_b[0].content, "hello");
    let last_applied: Option<String> = conn_b
        .query_row(
            "SELECT value FROM kv WHERE key = ?1",
            rusqlite::params![format!(
                "managed_vault_v2.last_applied_global_seq:{}",
                managed_vault_v2_scope_id(&base_url, &vault_id)
            )],
            |row| row.get(0),
        )
        .optional()
        .expect("load last_applied");
    let expected_last_applied_text = expected_last_applied.to_string();
    assert_eq!(
        last_applied.as_deref(),
        Some(expected_last_applied_text.as_str()),
    );

    stop_tx.send(()).expect("stop");
    handle.join().expect("join");
}

#[test]
fn managed_vault_v2_pull_with_progress_resets_baseline_after_reset_required_response() {
    let (base_url, stop_tx, state, handle) = start_mock_v2_server();
    let vault_id = "v1".to_string();
    let id_token = "test_uid".to_string();

    let temp_a = tempfile::tempdir().expect("tempdir A");
    let app_dir_a = temp_a.path().join("secondloop_a");
    let key_a =
        auth::init_master_password(&app_dir_a, "pw-a", KdfParams::for_test()).expect("init A");
    let conn_a = db::open(&app_dir_a).expect("open A db");
    let conv_a = db::create_conversation(&conn_a, &key_a, "Inbox").expect("create convo A");
    db::insert_message(&conn_a, &key_a, &conv_a.id, "user", "hello").expect("insert msg A");

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
    let expected_last_applied = state.lock().expect("lock").latest_global_seq;
    assert_eq!(expected_last_applied, 2);

    let temp_b = tempfile::tempdir().expect("tempdir B");
    let app_dir_b = temp_b.path().join("secondloop_b");
    let key_b =
        auth::init_master_password(&app_dir_b, "pw-b", KdfParams::for_test()).expect("init B");
    let conn_b = db::open(&app_dir_b).expect("open B db");

    let scope_id = managed_vault_v2_scope_id(&base_url, &vault_id);
    conn_b
        .execute(
            "INSERT INTO kv(key, value) VALUES (?1, ?2)
             ON CONFLICT(key) DO UPDATE SET value = excluded.value",
            rusqlite::params![
                format!("managed_vault_v2.generation_id:{scope_id}"),
                "generation-a"
            ],
        )
        .expect("seed generation");
    conn_b
        .execute(
            "INSERT INTO kv(key, value) VALUES (?1, ?2)
             ON CONFLICT(key) DO UPDATE SET value = excluded.value",
            rusqlite::params![
                format!("managed_vault_v2.last_applied_global_seq:{scope_id}"),
                "1"
            ],
        )
        .expect("seed stale last_applied");

    {
        let mut server = state.lock().expect("lock");
        server.reset_required_once_after_global_seq = Some(1);
    }

    let mut seen_progress = Vec::new();
    let pulled = sync::managed_vault::pull_with_progress(
        &conn_b,
        &key_b,
        &sync_key,
        &base_url,
        &vault_id,
        &id_token,
        &mut |done, total| seen_progress.push((done, total)),
    )
    .expect("pull with progress");
    assert!(pulled > 0);

    assert!(
        seen_progress.contains(&(0, expected_last_applied as u64)),
        "expected progress to reset after rebuild, got {seen_progress:?}"
    );
    assert_eq!(
        seen_progress.last().copied(),
        Some((expected_last_applied as u64, expected_last_applied as u64)),
        "expected rebuilt pull to report full recovered total, got {seen_progress:?}"
    );

    stop_tx.send(()).expect("stop");
    handle.join().expect("join");
}

#[test]
fn managed_vault_v2_pull_downloads_missing_embedding_artifact_blobs() {
    let (base_url, stop_tx, state, handle) = start_mock_v2_server();
    let vault_id = "v1".to_string();
    let id_token = "test_uid".to_string();

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
        "shared semantic note",
    )
    .expect("insert message");
    let processed =
        db::process_pending_message_embeddings_default(&conn_a, &key_a, 10).expect("process A");
    assert_eq!(processed, 1);

    let sync_key = derive_root_key(
        "sync-passphrase",
        b"secondloop-sync1",
        &KdfParams::for_test(),
    )
    .expect("derive sync key");

    let device_id = db::get_or_create_device_id(&conn_a).expect("device id");
    let mut stmt = conn_a
        .prepare(
            r#"SELECT op_id, seq, op_json
               FROM oplog
               WHERE device_id = ?1
               ORDER BY seq ASC"#,
        )
        .expect("prepare oplog");
    let mut rows = stmt
        .query(rusqlite::params![device_id.as_str()])
        .expect("query oplog");

    let mut remote_ops = Vec::<serde_json::Value>::new();
    while let Some(row) = rows.next().expect("next row") {
        let op_id: String = row.get(0).expect("op_id");
        let seq: i64 = row.get(1).expect("seq");
        let op_json_blob: Vec<u8> = row.get(2).expect("op_json");
        let plaintext = secondloop_rust::crypto::decrypt_bytes(
            &key_a,
            &op_json_blob,
            format!("oplog.op_json:{op_id}").as_bytes(),
        )
        .expect("decrypt op");
        let ciphertext = secondloop_rust::crypto::encrypt_bytes(
            &sync_key,
            &plaintext,
            format!("sync.ops:{device_id}:{seq}").as_bytes(),
        )
        .expect("encrypt op");
        remote_ops.push(serde_json::json!({
            "global_seq": (remote_ops.len() as i64) + 1,
            "device_id": device_id,
            "seq": seq,
            "op_id": op_id,
            "client_op_id": op_id,
            "ciphertext_b64": base64::engine::general_purpose::STANDARD.encode(ciphertext),
        }));
    }

    let profile_id = db::embedding_artifact_profile_id(
        secondloop_rust::embedding::DEFAULT_MODEL_NAME,
        secondloop_rust::embedding::DEFAULT_EMBED_DIM,
    );
    let revision = conn_a
        .query_row(
            r#"SELECT updated_at FROM messages WHERE id = ?1"#,
            rusqlite::params![message.id.as_str()],
            |row| row.get::<_, i64>(0),
        )
        .expect("message revision");
    let manifests = db::list_active_embedding_artifacts_for_source_revision(
        &conn_a,
        "message",
        &message.id,
        revision,
        &profile_id,
    )
    .expect("manifests");
    assert_eq!(manifests.len(), 1);
    let manifest = manifests[0].clone();
    let artifact_plaintext =
        db::read_embedding_artifact_blob(&app_dir_a, &key_a, &manifest.blob_ref)
            .expect("read artifact blob");
    let artifact_ciphertext = secondloop_rust::crypto::encrypt_bytes(
        &sync_key,
        &artifact_plaintext,
        format!("sync.embedding_artifact.blob:{}", manifest.blob_ref).as_bytes(),
    )
    .expect("encrypt artifact");

    {
        let mut server = state.lock().expect("lock");
        server.latest_global_seq = remote_ops.len() as i64;
        server.ops = remote_ops;
        server.attachments.insert(
            db::embedding_artifact_blob_storage_id(&manifest.blob_ref),
            artifact_ciphertext,
        );
    }

    let temp_b = tempfile::tempdir().expect("tempdir B");
    let app_dir_b = temp_b.path().join("secondloop_b");
    let key_b =
        auth::init_master_password(&app_dir_b, "pw-b", KdfParams::for_test()).expect("init B");
    let conn_b = db::open(&app_dir_b).expect("open B db");

    let applied =
        sync::managed_vault::pull(&conn_b, &key_b, &sync_key, &base_url, &vault_id, &id_token)
            .expect("pull");
    assert!(applied > 0);

    let manifests_b = db::list_active_embedding_artifacts_for_source_revision(
        &conn_b,
        "message",
        &message.id,
        revision,
        &profile_id,
    )
    .expect("manifests B");
    assert_eq!(manifests_b.len(), 1);
    assert!(db::has_embedding_artifact_blob(
        &app_dir_b,
        &manifests_b[0].blob_ref
    ));

    stop_tx.send(()).expect("stop");
    handle.join().expect("join");
}
