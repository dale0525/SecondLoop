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
    last_push_body: Option<serde_json::Value>,
}

struct SeqGapServerState {
    push_calls: usize,
    remote_max_seq: i64,
}

struct OpIdConflictServerState {
    push_calls: usize,
    first_ops_len: usize,
    conflict_op_id: Option<String>,
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
        401 => "Unauthorized",
        403 => "Forbidden",
        404 => "Not Found",
        409 => "Conflict",
        _ => "OK",
    };
    let resp = format!(
        "HTTP/1.1 {status} {status_text}\r\nContent-Type: application/json\r\nContent-Length: {}\r\nConnection: close\r\n\r\n{body_str}",
        body_str.len()
    );
    stream.write_all(resp.as_bytes()).expect("write response");
}

fn start_seq_gap_mock_server(
    initial_remote_max_seq: i64,
) -> (
    String,
    mpsc::Sender<()>,
    Arc<Mutex<SeqGapServerState>>,
    thread::JoinHandle<()>,
) {
    let listener = TcpListener::bind("127.0.0.1:0").expect("bind");
    listener.set_nonblocking(true).expect("nonblocking");
    let addr = listener.local_addr().expect("local addr");

    let (stop_tx, stop_rx) = mpsc::channel::<()>();
    let state = Arc::new(Mutex::new(SeqGapServerState {
        push_calls: 0,
        remote_max_seq: initial_remote_max_seq,
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
                        405,
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

                    let mut seqs: Vec<i64> = ops
                        .iter()
                        .filter_map(|op| op.get("seq").and_then(|v| v.as_i64()))
                        .collect();
                    seqs.sort();

                    let mut st = state_clone.lock().expect("lock");
                    st.push_calls += 1;
                    let mut temp_max = st.remote_max_seq;
                    for seq in seqs {
                        if seq <= temp_max {
                            continue;
                        }
                        if seq == temp_max + 1 {
                            temp_max = seq;
                            continue;
                        }
                        write_json_response(
                            &mut stream,
                            409,
                            serde_json::json!({
                                "error": "seq_gap",
                                "expected_next_seq": temp_max + 1
                            }),
                        );
                        continue;
                    }

                    st.remote_max_seq = temp_max;
                    write_json_response(
                        &mut stream,
                        200,
                        serde_json::json!({ "accepted": ops.len(), "max_seq": temp_max }),
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

fn start_mock_server() -> (
    String,
    mpsc::Sender<()>,
    Arc<Mutex<ServerState>>,
    thread::JoinHandle<()>,
) {
    start_mock_server_with_expected_next_seq(6)
}

fn start_op_id_conflict_mock_server(
    expected_next_seq: i64,
) -> (
    String,
    mpsc::Sender<()>,
    Arc<Mutex<OpIdConflictServerState>>,
    thread::JoinHandle<()>,
) {
    let listener = TcpListener::bind("127.0.0.1:0").expect("bind");
    listener.set_nonblocking(true).expect("nonblocking");
    let addr = listener.local_addr().expect("local addr");

    let (stop_tx, stop_rx) = mpsc::channel::<()>();
    let state = Arc::new(Mutex::new(OpIdConflictServerState {
        push_calls: 0,
        first_ops_len: 0,
        conflict_op_id: None,
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
                        405,
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
                    assert!(!ops.is_empty(), "expected ops");

                    let first_seq = ops[0].get("seq").and_then(|v| v.as_i64()).unwrap_or(0);
                    let first_op_id = ops[0]
                        .get("op_id")
                        .and_then(|v| v.as_str())
                        .unwrap_or("")
                        .to_string();

                    let mut max_seq = 0i64;
                    for op in ops {
                        let seq = op.get("seq").and_then(|v| v.as_i64()).unwrap_or(0);
                        max_seq = max_seq.max(seq);
                    }

                    let mut st = state_clone.lock().expect("lock");
                    st.push_calls += 1;
                    let call = st.push_calls;

                    if call == 1 {
                        st.first_ops_len = ops.len();
                        st.conflict_op_id = Some(first_op_id.clone());
                        write_json_response(
                            &mut stream,
                            409,
                            serde_json::json!({
                                "error": "conflict",
                                "conflict_kind": "op_id",
                                "op_id": first_op_id,
                                "existing_device_id": "some_other_device",
                                "existing_seq": expected_next_seq.saturating_sub(1).max(0),
                                "expected_next_seq": expected_next_seq
                            }),
                        );
                        continue;
                    }

                    if call == 2 {
                        assert_eq!(first_seq, expected_next_seq, "expected same next seq");
                        assert_ne!(
                            st.conflict_op_id.as_deref().unwrap_or(""),
                            first_op_id,
                            "expected conflicting op_id to be removed"
                        );
                        assert_eq!(
                            ops.len() + 1,
                            st.first_ops_len,
                            "expected exactly one op removed after repair"
                        );

                        write_json_response(
                            &mut stream,
                            200,
                            serde_json::json!({ "accepted": ops.len(), "max_seq": max_seq }),
                        );
                        continue;
                    }

                    write_json_response(
                        &mut stream,
                        500,
                        serde_json::json!({ "error": "too_many_push_calls" }),
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

fn start_mock_server_with_expected_next_seq(
    expected_next_seq: i64,
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
                let (method, path, body) = read_request(&mut stream);

                if method != "POST" {
                    write_json_response(
                        &mut stream,
                        405,
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

                    let mut st = state_clone.lock().expect("lock");
                    st.push_calls += 1;
                    let call = st.push_calls;

                    if call == 1 {
                        write_json_response(
                            &mut stream,
                            409,
                            serde_json::json!({
                                "error": "conflict",
                                "conflict_kind": "seq",
                                "conflict_seq": 1,
                                "expected_next_seq": expected_next_seq
                            }),
                        );
                        continue;
                    }

                    if call == 2 {
                        let (ops_len, first_seq, max_seq) = {
                            let ops = decoded
                                .get("ops")
                                .and_then(|v| v.as_array())
                                .expect("ops array");
                            assert!(!ops.is_empty(), "expected ops");

                            let first_seq = ops[0].get("seq").and_then(|v| v.as_i64()).unwrap_or(0);
                            let mut max_seq = 0i64;
                            for op in ops {
                                let seq = op.get("seq").and_then(|v| v.as_i64()).unwrap_or(0);
                                max_seq = max_seq.max(seq);
                            }

                            (ops.len(), first_seq, max_seq)
                        };
                        assert_eq!(first_seq, expected_next_seq, "expected rebased seq");
                        st.last_push_body = Some(decoded.clone());
                        write_json_response(
                            &mut stream,
                            200,
                            serde_json::json!({ "accepted": ops_len, "max_seq": max_seq }),
                        );
                        continue;
                    }

                    write_json_response(
                        &mut stream,
                        500,
                        serde_json::json!({ "error": "too_many_push_calls" }),
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
fn managed_vault_push_recovers_from_conflict_by_rebasing() {
    let (base_url, stop_tx, state, handle) = start_mock_server();
    let vault_id = "v1".to_string();
    let id_token = "test_uid".to_string();

    let temp = tempfile::tempdir().expect("tempdir");
    let app_dir = temp.path().join("secondloop_a");
    let key = auth::init_master_password(&app_dir, "pw-a", KdfParams::for_test()).expect("init A");
    let conn = db::open(&app_dir).expect("open A db");
    let conv = db::create_conversation(&conn, &key, "Inbox").expect("create convo A");
    db::insert_message(&conn, &key, &conv.id, "user", "hello").expect("insert msg A");

    let sync_key = derive_root_key(
        "sync-passphrase",
        b"secondloop-sync1",
        &KdfParams::for_test(),
    )
    .expect("derive sync key");

    let pushed =
        sync::managed_vault::push_ops_only(&conn, &key, &sync_key, &base_url, &vault_id, &id_token)
            .expect("push");
    assert!(pushed > 0);

    let st = state.lock().expect("lock");
    assert_eq!(st.push_calls, 2);
    assert!(st.last_push_body.is_some());

    let _ = stop_tx.send(());
    handle.join().expect("join");
}

#[test]
fn managed_vault_push_rebase_delta_one_does_not_violate_unique_constraint() {
    let (base_url, stop_tx, state, handle) = start_mock_server_with_expected_next_seq(2);
    let vault_id = "v1".to_string();
    let id_token = "test_uid".to_string();

    let temp = tempfile::tempdir().expect("tempdir");
    let app_dir = temp.path().join("secondloop_a");
    let key = auth::init_master_password(&app_dir, "pw-a", KdfParams::for_test()).expect("init A");
    let conn = db::open(&app_dir).expect("open A db");
    let conv = db::create_conversation(&conn, &key, "Inbox").expect("create convo A");
    db::insert_message(&conn, &key, &conv.id, "user", "hello").expect("insert msg A");

    let sync_key = derive_root_key(
        "sync-passphrase",
        b"secondloop-sync1",
        &KdfParams::for_test(),
    )
    .expect("derive sync key");

    let pushed =
        sync::managed_vault::push_ops_only(&conn, &key, &sync_key, &base_url, &vault_id, &id_token)
            .expect("push");
    assert!(pushed > 0);

    let st = state.lock().expect("lock");
    assert_eq!(st.push_calls, 2);
    assert!(st.last_push_body.is_some());

    let _ = stop_tx.send(());
    handle.join().expect("join");
}

#[test]
fn managed_vault_push_recovers_from_seq_gap_by_compacting_local_seqs() {
    let (base_url, stop_tx, state, handle) = start_seq_gap_mock_server(30);
    let vault_id = "v1".to_string();
    let id_token = "test_uid".to_string();

    let temp = tempfile::tempdir().expect("tempdir");
    let app_dir = temp.path().join("secondloop_a");
    let key = auth::init_master_password(&app_dir, "pw-a", KdfParams::for_test()).expect("init A");
    let conn = db::open(&app_dir).expect("open A db");
    let conv = db::create_conversation(&conn, &key, "Inbox").expect("create convo A");
    for i in 0..31 {
        db::insert_message(&conn, &key, &conv.id, "user", &format!("m{i}")).expect("insert msg A");
    }

    let local_device_id = db::get_or_create_device_id(&conn).expect("device_id");
    conn.execute(
        r#"DELETE FROM oplog WHERE device_id = ?1 AND seq = ?2"#,
        rusqlite::params![local_device_id.as_str(), 31i64],
    )
    .expect("delete oplog seq");

    let sync_key = derive_root_key(
        "sync-passphrase",
        b"secondloop-sync1",
        &KdfParams::for_test(),
    )
    .expect("derive sync key");

    let pushed =
        sync::managed_vault::push_ops_only(&conn, &key, &sync_key, &base_url, &vault_id, &id_token)
            .expect("push");
    assert!(pushed > 0);

    let st = state.lock().expect("lock");
    assert!(st.push_calls >= 2);
    assert!(st.remote_max_seq >= 31);

    let _ = stop_tx.send(());
    handle.join().expect("join");
}

#[test]
fn managed_vault_push_recovers_from_op_id_conflict_by_dropping_duplicate_and_compacting() {
    let (base_url, stop_tx, state, handle) = start_op_id_conflict_mock_server(1);
    let vault_id = "v1".to_string();
    let id_token = "test_uid".to_string();

    let temp = tempfile::tempdir().expect("tempdir");
    let app_dir = temp.path().join("secondloop_a");
    let key = auth::init_master_password(&app_dir, "pw-a", KdfParams::for_test()).expect("init A");
    let conn = db::open(&app_dir).expect("open A db");
    let conv = db::create_conversation(&conn, &key, "Inbox").expect("create convo A");
    db::insert_message(&conn, &key, &conv.id, "user", "m1").expect("insert msg A1");
    db::insert_message(&conn, &key, &conv.id, "user", "m2").expect("insert msg A2");

    let sync_key = derive_root_key(
        "sync-passphrase",
        b"secondloop-sync1",
        &KdfParams::for_test(),
    )
    .expect("derive sync key");

    let pushed =
        sync::managed_vault::push_ops_only(&conn, &key, &sync_key, &base_url, &vault_id, &id_token)
            .expect("push");
    assert!(pushed > 0);

    let st = state.lock().expect("lock");
    assert_eq!(st.push_calls, 2);

    let _ = stop_tx.send(());
    handle.join().expect("join");
}
