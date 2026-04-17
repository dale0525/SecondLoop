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
struct V2ServerState {
    generation_id: String,
    latest_global_seq: i64,
    ops: Vec<serde_json::Value>,
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
                        let state = state_clone.lock().expect("lock");
                        let ops: Vec<serde_json::Value> = state
                            .ops
                            .iter()
                            .filter(|item| item["global_seq"].as_i64().unwrap_or(0) > after)
                            .cloned()
                            .collect();
                        write_json_response(
                            &mut stream,
                            200,
                            serde_json::json!({
                                "generation_id": state.generation_id,
                                "remote_latest_global_seq": state.latest_global_seq,
                                "has_more": false,
                                "ops": ops,
                            }),
                        );
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
    assert!(requests.contains("/v2/vaults/v1/sync/head"));

    stop_tx.send(()).expect("stop");
    handle.join().expect("join");
}

#[test]
fn managed_vault_v2_generation_mismatch_does_not_reupload_stale_local_data() {
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
        sync::managed_vault::push(&conn, &key, &sync_key, &base_url, &vault_id, &id_token)
            .expect("first push");
    assert!(first_push > 0);

    {
        let mut server = state.lock().expect("lock");
        server.generation_id = "generation-reset".to_string();
        server.latest_global_seq = 0;
        server.ops.clear();
    }

    let second_push =
        sync::managed_vault::push(&conn, &key, &sync_key, &base_url, &vault_id, &id_token)
            .expect("second push");
    assert_eq!(second_push, 0);

    let recovery_pull =
        sync::managed_vault::pull(&conn, &key, &sync_key, &base_url, &vault_id, &id_token)
            .expect("recovery pull");
    assert_eq!(recovery_pull, 0);

    let convs = db::list_conversations(&conn, &key).expect("list convs");
    assert_eq!(convs.len(), 0);

    let state = state.lock().expect("lock");
    assert_eq!(state.latest_global_seq, 0);
    assert_eq!(state.ops.len(), 0);

    stop_tx.send(()).expect("stop");
    handle.join().expect("join");
}
