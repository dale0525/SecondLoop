use std::io::{Read, Write};
use std::net::{TcpListener, TcpStream};
use std::sync::mpsc;
use std::sync::{Arc, Mutex};
use std::thread;
use std::time::Duration;

use base64::engine::general_purpose::STANDARD as B64_STD;
use base64::Engine as _;
use chacha20poly1305::aead::{Aead, Payload};
use chacha20poly1305::{KeyInit, XChaCha20Poly1305, XNonce};
use secondloop_rust::auth;
use secondloop_rust::crypto::{decrypt_bytes, derive_root_key, KdfParams};
use secondloop_rust::db;
use secondloop_rust::sync;
use secondloop_rust::sync::RemoteStore;

const SYNC_OP_COMPRESSED_MAGIC_V1: &[u8; 5] = b"SLOP1";

#[derive(Default)]
struct PushCaptureState {
    pushed_ops: Vec<(String, i64, String)>,
}

fn derive_sync_key() -> [u8; 32] {
    derive_root_key(
        "sync-passphrase",
        b"secondloop-sync1",
        &KdfParams::for_test(),
    )
    .expect("derive sync key")
}

fn read_device_id(conn: &rusqlite::Connection) -> String {
    conn.query_row(
        r#"SELECT value FROM kv WHERE key = 'device_id'"#,
        [],
        |row| row.get(0),
    )
    .expect("device id")
}

fn read_last_local_op_plaintext(
    conn: &rusqlite::Connection,
    db_key: &[u8; 32],
) -> (String, i64, Vec<u8>) {
    let (op_id, seq, blob): (String, i64, Vec<u8>) = conn
        .query_row(
            r#"SELECT op_id, seq, op_json FROM oplog ORDER BY seq DESC LIMIT 1"#,
            [],
            |row| Ok((row.get(0)?, row.get(1)?, row.get(2)?)),
        )
        .expect("latest oplog row");

    let plaintext = decrypt_bytes(db_key, &blob, format!("oplog.op_json:{op_id}").as_bytes())
        .expect("decrypt local op");
    (op_id, seq, plaintext)
}

fn decrypt_sync_op_ciphertext_raw(sync_key: &[u8; 32], ciphertext: &[u8], aad: &str) -> Vec<u8> {
    assert!(ciphertext.len() >= 24, "ciphertext too short");
    let (nonce_bytes, encrypted) = ciphertext.split_at(24);
    let cipher = XChaCha20Poly1305::new_from_slice(sync_key).expect("cipher");
    let nonce = XNonce::from_slice(nonce_bytes);
    cipher
        .decrypt(
            nonce,
            Payload {
                msg: encrypted,
                aad: aad.as_bytes(),
            },
        )
        .expect("decrypt raw sync ciphertext")
}

fn encrypt_sync_op_plaintext_raw(sync_key: &[u8; 32], plaintext: &[u8], aad: &str) -> Vec<u8> {
    let cipher = XChaCha20Poly1305::new_from_slice(sync_key).expect("cipher");
    let mut nonce_bytes = [0u8; 24];
    for (idx, b) in nonce_bytes.iter_mut().enumerate() {
        *b = (idx as u8).wrapping_mul(7).wrapping_add(3);
    }
    let nonce = XNonce::from_slice(&nonce_bytes);
    let encrypted = cipher
        .encrypt(
            nonce,
            Payload {
                msg: plaintext,
                aad: aad.as_bytes(),
            },
        )
        .expect("encrypt raw sync plaintext");

    let mut out = Vec::with_capacity(24 + encrypted.len());
    out.extend_from_slice(&nonce_bytes);
    out.extend_from_slice(&encrypted);
    out
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
        404 => "Not Found",
        _ => "OK",
    };
    let resp = format!(
        "HTTP/1.1 {status} {status_text}\r\nContent-Type: application/json\r\nContent-Length: {}\r\nConnection: close\r\n\r\n{body_str}",
        body_str.len()
    );
    stream.write_all(resp.as_bytes()).expect("write response");
}

fn start_push_capture_server() -> (
    String,
    mpsc::Sender<()>,
    Arc<Mutex<PushCaptureState>>,
    thread::JoinHandle<()>,
) {
    let listener = TcpListener::bind("127.0.0.1:0").expect("bind");
    listener.set_nonblocking(true).expect("nonblocking");
    let addr = listener.local_addr().expect("local addr");

    let (stop_tx, stop_rx) = mpsc::channel::<()>();
    let state = Arc::new(Mutex::new(PushCaptureState::default()));
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
                        serde_json::json!({ "error": "not_found" }),
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

                if segments[2] != "v1" {
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
                    let device_id = decoded
                        .get("device_id")
                        .and_then(|v| v.as_str())
                        .expect("device_id")
                        .to_string();
                    let ops = decoded
                        .get("ops")
                        .and_then(|v| v.as_array())
                        .expect("ops array");

                    let mut max_seq = 0i64;
                    {
                        let mut st = state_clone.lock().expect("state lock");
                        for op in ops {
                            let seq = op.get("seq").and_then(|v| v.as_i64()).expect("seq");
                            let ciphertext_b64 = op
                                .get("ciphertext_b64")
                                .and_then(|v| v.as_str())
                                .expect("ciphertext_b64")
                                .to_string();
                            st.pushed_ops.push((device_id.clone(), seq, ciphertext_b64));
                            max_seq = max_seq.max(seq);
                        }
                    }

                    write_json_response(
                        &mut stream,
                        200,
                        serde_json::json!({ "accepted": ops.len(), "max_seq": max_seq }),
                    );
                    continue;
                }

                if tail == "ops:pull" || tail == "ops:pull_bin" {
                    write_json_response(
                        &mut stream,
                        200,
                        serde_json::json!({ "ops": [], "next": {}, "max": {} }),
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
fn sync_push_compresses_large_message_ops() {
    let temp = tempfile::tempdir().expect("tempdir");
    let app_dir = temp.path().join("device_a");
    let db_key =
        auth::init_master_password(&app_dir, "pw-a", KdfParams::for_test()).expect("init key");
    let conn = db::open(&app_dir).expect("open db");

    let conv = db::get_or_create_loop_home_conversation(&conn, &db_key).expect("loop home");
    let large_text = "Long sync payload ".repeat(600);
    assert!(large_text.len() > 4 * 1024);
    db::insert_message(&conn, &db_key, &conv.id, "user", &large_text).expect("insert message");

    let (_op_id, seq, local_plaintext) = read_last_local_op_plaintext(&conn, &db_key);
    assert!(
        local_plaintext.len() > 4 * 1024,
        "op json should exceed threshold"
    );

    let sync_key = derive_sync_key();
    let remote = sync::InMemoryRemoteStore::new();
    let remote_root = "SecondLoopTest";
    let pushed = sync::push(&conn, &db_key, &sync_key, &remote, remote_root).expect("push");
    assert!(pushed > 0);

    let device_id = read_device_id(&conn);
    let remote_path = format!("/{remote_root}/{device_id}/ops/op_{seq}.json");
    let remote_blob = remote.get(&remote_path).expect("remote op blob");

    let raw_plaintext = decrypt_sync_op_ciphertext_raw(
        &sync_key,
        &remote_blob,
        &format!("sync.ops:{device_id}:{seq}"),
    );
    assert!(
        raw_plaintext.starts_with(SYNC_OP_COMPRESSED_MAGIC_V1),
        "expected compressed envelope for large sync op payload"
    );
    assert!(
        raw_plaintext.len() < local_plaintext.len(),
        "compressed payload should be smaller than local plaintext"
    );
}

#[test]
fn sync_push_keeps_small_message_ops_uncompressed() {
    let temp = tempfile::tempdir().expect("tempdir");
    let app_dir = temp.path().join("device_a");
    let db_key =
        auth::init_master_password(&app_dir, "pw-a", KdfParams::for_test()).expect("init key");
    let conn = db::open(&app_dir).expect("open db");

    let conv = db::get_or_create_loop_home_conversation(&conn, &db_key).expect("loop home");
    db::insert_message(&conn, &db_key, &conv.id, "user", "hello").expect("insert message");

    let (_op_id, seq, _local_plaintext) = read_last_local_op_plaintext(&conn, &db_key);

    let sync_key = derive_sync_key();
    let remote = sync::InMemoryRemoteStore::new();
    let remote_root = "SecondLoopTest";
    sync::push(&conn, &db_key, &sync_key, &remote, remote_root).expect("push");

    let device_id = read_device_id(&conn);
    let remote_path = format!("/{remote_root}/{device_id}/ops/op_{seq}.json");
    let remote_blob = remote.get(&remote_path).expect("remote op blob");

    let raw_plaintext = decrypt_sync_op_ciphertext_raw(
        &sync_key,
        &remote_blob,
        &format!("sync.ops:{device_id}:{seq}"),
    );
    assert!(
        !raw_plaintext.starts_with(SYNC_OP_COMPRESSED_MAGIC_V1),
        "small sync ops should not be wrapped in compressed envelope"
    );
}

#[test]
fn sync_pull_accepts_legacy_uncompressed_sync_op_payloads() {
    let remote = sync::InMemoryRemoteStore::new();
    let remote_root = "SecondLoopTest";

    let temp_a = tempfile::tempdir().expect("tempdir A");
    let app_dir_a = temp_a.path().join("secondloop_a");
    let db_key_a =
        auth::init_master_password(&app_dir_a, "pw-a", KdfParams::for_test()).expect("init A");
    let conn_a = db::open(&app_dir_a).expect("open A db");
    let conv_a = db::get_or_create_loop_home_conversation(&conn_a, &db_key_a).expect("loop home A");

    let large_text = "Legacy payload compatibility ".repeat(500);
    db::insert_message(&conn_a, &db_key_a, &conv_a.id, "user", &large_text).expect("insert A msg");

    let (_op_id, seq, local_plaintext) = read_last_local_op_plaintext(&conn_a, &db_key_a);
    assert!(
        local_plaintext.len() > 4 * 1024,
        "op json should exceed threshold"
    );

    let sync_key = derive_sync_key();
    sync::push(&conn_a, &db_key_a, &sync_key, &remote, remote_root).expect("push A");

    let device_id_a = read_device_id(&conn_a);
    let packs_dir = format!("/{remote_root}/{device_id_a}/packs/");
    for path in remote.list(&packs_dir).expect("list packs") {
        remote.delete(&path).expect("delete pack file");
    }

    let aad = format!("sync.ops:{device_id_a}:{seq}");
    let legacy_blob = encrypt_sync_op_plaintext_raw(&sync_key, &local_plaintext, &aad);
    let op_path = format!("/{remote_root}/{device_id_a}/ops/op_{seq}.json");
    remote
        .put(&op_path, legacy_blob)
        .expect("overwrite with legacy blob");

    let temp_b = tempfile::tempdir().expect("tempdir B");
    let app_dir_b = temp_b.path().join("secondloop_b");
    let db_key_b =
        auth::init_master_password(&app_dir_b, "pw-b", KdfParams::for_test()).expect("init B");
    let conn_b = db::open(&app_dir_b).expect("open B db");

    let applied = sync::pull(&conn_b, &db_key_b, &sync_key, &remote, remote_root).expect("pull B");
    assert!(applied > 0);

    let msgs_b = db::list_messages(&conn_b, &db_key_b, &conv_a.id).expect("list msgs B");
    assert_eq!(msgs_b.len(), 1);
    assert_eq!(msgs_b[0].content, large_text);
}

#[test]
fn managed_vault_push_compresses_large_message_ops() {
    let (base_url, stop_tx, state, handle) = start_push_capture_server();
    let vault_id = "v1".to_string();
    let id_token = "test_uid".to_string();

    let temp = tempfile::tempdir().expect("tempdir");
    let app_dir = temp.path().join("device_a");
    let db_key =
        auth::init_master_password(&app_dir, "pw-a", KdfParams::for_test()).expect("init key");
    let conn = db::open(&app_dir).expect("open db");

    let conv = db::get_or_create_loop_home_conversation(&conn, &db_key).expect("loop home");
    let large_text = "Managed vault long payload ".repeat(520);
    db::insert_message(&conn, &db_key, &conv.id, "user", &large_text).expect("insert message");

    let (_op_id, seq, _local_plaintext) = read_last_local_op_plaintext(&conn, &db_key);

    let sync_key = derive_sync_key();
    let pushed = sync::managed_vault::push_ops_only(
        &conn, &db_key, &sync_key, &base_url, &vault_id, &id_token,
    )
    .expect("managed vault push");
    assert!(pushed > 0);

    let device_id = read_device_id(&conn);
    let captured = {
        let st = state.lock().expect("state lock");
        st.pushed_ops
            .iter()
            .find(|(dev, pushed_seq, _)| dev == &device_id && *pushed_seq == seq)
            .cloned()
            .expect("captured pushed op")
    };

    let ciphertext = B64_STD
        .decode(captured.2.as_bytes())
        .expect("decode pushed ciphertext");
    let raw_plaintext = decrypt_sync_op_ciphertext_raw(
        &sync_key,
        &ciphertext,
        &format!("sync.ops:{device_id}:{seq}"),
    );

    assert!(
        raw_plaintext.starts_with(SYNC_OP_COMPRESSED_MAGIC_V1),
        "managed vault push should also use compressed envelope for large payload"
    );

    let _ = stop_tx.send(());
    handle.join().expect("join server");
}
