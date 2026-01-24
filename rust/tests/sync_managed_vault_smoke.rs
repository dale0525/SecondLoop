use std::collections::BTreeMap;
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
    ops: BTreeMap<(String, String), Vec<StoredOp>>, // (vault_id, device_id) -> ops
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
        header_end = buf
            .windows(4)
            .position(|w| w == b"\r\n\r\n")
            .map(|p| p + 4);
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

fn start_mock_managed_vault_server(
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
                let (raw_headers, method, path, body) = read_request(&mut stream);
                let req_dump = format!("{raw_headers}{}", String::from_utf8_lossy(&body));
                {
                    let mut st = state_clone.lock().expect("lock");
                    st.requests.push(req_dump);
                }

                if method != "POST" {
                    write_json_response(&mut stream, 405, serde_json::json!({ "error": "method_not_allowed" }));
                    continue;
                }

                let segments: Vec<&str> = path.split('/').filter(|s| !s.is_empty()).collect();
                if segments.len() < 3 || segments[0] != "v1" || segments[1] != "vaults" {
                    write_json_response(&mut stream, 404, serde_json::json!({ "error": "not_found" }));
                    continue;
                }
                let vault_id = segments[2].to_string();
                let tail = segments[3..].join("/");

                if tail == "devices" {
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

                if tail == "ops:push" {
                    let decoded: serde_json::Value =
                        serde_json::from_slice(&body).expect("push json");
                    let device_id = decoded
                        .get("device_id")
                        .and_then(|v| v.as_str())
                        .expect("device_id")
                        .to_string();
                    let ops = decoded
                        .get("ops")
                        .and_then(|v| v.as_array())
                        .expect("ops array");

                    let mut max_seq: i64 = 0;
                    let mut accepted: i64 = 0;
                    let mut stored: Vec<StoredOp> = Vec::new();
                    for op in ops {
                        let seq = op.get("seq").and_then(|v| v.as_i64()).expect("seq");
                        let op_id = op.get("op_id").and_then(|v| v.as_str()).expect("op_id");
                        let ciphertext_b64 = op
                            .get("ciphertext_b64")
                            .and_then(|v| v.as_str())
                            .expect("ciphertext_b64");
                        max_seq = max_seq.max(seq);
                        accepted += 1;
                        stored.push(StoredOp {
                            device_id: device_id.clone(),
                            seq,
                            op_id: op_id.to_string(),
                            ciphertext_b64: ciphertext_b64.to_string(),
                        });
                    }

                    {
                        let mut st = state_clone.lock().expect("lock");
                        st.ops
                            .entry((vault_id.clone(), device_id.clone()))
                            .or_default()
                            .extend(stored);
                    }

                    write_json_response(
                        &mut stream,
                        200,
                        serde_json::json!({ "accepted": accepted, "max_seq": max_seq }),
                    );
                    continue;
                }

                if tail == "ops:pull" {
                    let decoded: serde_json::Value =
                        serde_json::from_slice(&body).expect("pull json");
                    let requester_device_id = decoded
                        .get("device_id")
                        .and_then(|v| v.as_str())
                        .expect("device_id");
                    let since = decoded.get("since").cloned().unwrap_or(serde_json::json!({}));
                    let limit = decoded
                        .get("limit")
                        .and_then(|v| v.as_u64())
                        .unwrap_or(500) as usize;

                    let devices: Vec<String> = {
                        let st = state_clone.lock().expect("lock");
                        st.vault_devices
                            .get(&vault_id)
                            .cloned()
                            .unwrap_or_default()
                    };

                    let mut out_ops: Vec<serde_json::Value> = Vec::new();
                    let mut next = serde_json::Map::<String, serde_json::Value>::new();

                    for dev in devices {
                        if out_ops.len() >= limit {
                            break;
                        }
                        if dev == requester_device_id {
                            continue;
                        }

                        let since_seq = since
                            .get(&dev)
                            .and_then(|v| v.as_i64())
                            .unwrap_or(0);

                        let ops_for_dev: Vec<StoredOp> = {
                            let st = state_clone.lock().expect("lock");
                            st.ops
                                .get(&(vault_id.clone(), dev.clone()))
                                .cloned()
                                .unwrap_or_default()
                        };

                        let mut last = None;
                        for op in ops_for_dev {
                            if out_ops.len() >= limit {
                                break;
                            }
                            if op.seq <= since_seq {
                                continue;
                            }
                            last = Some(op.seq);
                            out_ops.push(serde_json::json!({
                                "device_id": op.device_id,
                                "seq": op.seq,
                                "op_id": op.op_id,
                                "ciphertext_b64": op.ciphertext_b64,
                            }));
                        }
                        if let Some(last_seq) = last {
                            next.insert(dev, serde_json::Value::from(last_seq));
                        }
                    }

                    write_json_response(
                        &mut stream,
                        200,
                        serde_json::json!({ "ops": out_ops, "next": serde_json::Value::Object(next) }),
                    );
                    continue;
                }

                write_json_response(&mut stream, 404, serde_json::json!({ "error": "not_found" }));
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
fn managed_vault_push_then_pull_copies_messages() {
    let (base_url, stop_tx, state, handle) = start_mock_managed_vault_server();
    let vault_id = "v1".to_string();
    let id_token = "test_uid".to_string();

    // Device A creates data locally.
    let temp_a = tempfile::tempdir().expect("tempdir A");
    let app_dir_a = temp_a.path().join("secondloop_a");
    let key_a =
        auth::init_master_password(&app_dir_a, "pw-a", KdfParams::for_test()).expect("init A");
    let conn_a = db::open(&app_dir_a).expect("open A db");
    let conv_a = db::create_conversation(&conn_a, &key_a, "Inbox").expect("create convo A");
    db::insert_message(&conn_a, &key_a, &conv_a.id, "user", "hello").expect("insert msg A");

    // Device B is a fresh install (different local root key).
    let temp_b = tempfile::tempdir().expect("tempdir B");
    let app_dir_b = temp_b.path().join("secondloop_b");
    let key_b =
        auth::init_master_password(&app_dir_b, "pw-b", KdfParams::for_test()).expect("init B");
    let conn_b = db::open(&app_dir_b).expect("open B db");

    // Shared sync key derived from a shared passphrase (same on both devices).
    let sync_key = derive_root_key(
        "sync-passphrase",
        b"secondloop-sync1",
        &KdfParams::for_test(),
    )
    .expect("derive sync key");

    let pushed = sync::managed_vault::push(&conn_a, &key_a, &sync_key, &base_url, &vault_id, &id_token)
        .expect("push");
    assert!(pushed > 0);

    let applied = sync::managed_vault::pull(&conn_b, &key_b, &sync_key, &base_url, &vault_id, &id_token)
        .expect("pull");
    assert!(applied > 0);

    let convs_b = db::list_conversations(&conn_b, &key_b).expect("list convs B");
    assert_eq!(convs_b.len(), 1);
    assert_eq!(convs_b[0].title, "Inbox");
    assert_eq!(convs_b[0].id, conv_a.id);

    let msgs_b = db::list_messages(&conn_b, &key_b, &convs_b[0].id).expect("list msgs B");
    assert_eq!(msgs_b.len(), 1);
    assert_eq!(msgs_b[0].content, "hello");

    // Push should have sent bearer token.
    let requests = state.lock().expect("lock").requests.join("\n\n");
    let req_lower = requests.to_ascii_lowercase();
    assert!(req_lower.contains("authorization: bearer test_uid"));

    let _ = stop_tx.send(());
    handle.join().expect("join");
}
