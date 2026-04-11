use std::io::{Read, Write};
use std::net::{TcpListener, TcpStream};
use std::sync::mpsc;
use std::thread;
use std::time::Duration;

use base64::engine::general_purpose::STANDARD as B64_STD;
use base64::Engine as _;
use secondloop_rust::auth;
use secondloop_rust::crypto::{derive_root_key, encrypt_bytes, KdfParams};
use secondloop_rust::db;
use secondloop_rust::sync;
use serde_json::json;

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

    let mut content_length: usize = 0;
    for line in headers_str.lines() {
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

    let request_line = headers_str.lines().next().expect("request line");
    let mut parts = request_line.split_whitespace();
    let method = parts.next().unwrap_or("").to_string();
    let path = parts.next().unwrap_or("").to_string();
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

fn encrypted_conversation_op(
    sync_key: &[u8; 32],
    remote_device_id: &str,
    seq: i64,
    conversation_id: &str,
    op_id: &str,
) -> String {
    let ts_ms = 1_775_811_648_824i64;
    let op_json = serde_json::json!({
        "op_id": op_id,
        "device_id": remote_device_id,
        "seq": seq,
        "ts_ms": ts_ms,
        "type": "conversation.upsert.v1",
        "payload": {
            "conversation_id": conversation_id,
            "title": "Recovered conversation",
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

fn start_v2_pull_server(
    encrypted_op_b64: String,
) -> (String, mpsc::Sender<()>, thread::JoinHandle<()>) {
    let listener = TcpListener::bind("127.0.0.1:0").expect("bind");
    listener.set_nonblocking(true).expect("nonblocking");
    let addr = listener.local_addr().expect("local addr");
    let (stop_tx, stop_rx) = mpsc::channel::<()>();

    let handle = thread::spawn(move || loop {
        if stop_rx.try_recv().is_ok() {
            break;
        }
        match listener.accept() {
            Ok((mut stream, _)) => {
                let (method, path, body) = read_request(&mut stream);
                if method != "POST" {
                    write_json_response(&mut stream, 404, json!({"error":"not_found"}));
                    continue;
                }

                if path.ends_with("/devices") {
                    write_json_response(&mut stream, 200, json!({ "device_id": "server-device" }));
                    continue;
                }

                if path.ends_with("/ops:push") {
                    write_json_response(&mut stream, 200, json!({ "accepted": 1, "max_seq": 1 }));
                    continue;
                }

                if path.ends_with("/ops:pull_v2") {
                    let request_json: serde_json::Value =
                        serde_json::from_slice(&body).expect("pull_v2 body");
                    let checkpoint = request_json
                        .get("checkpoint_token")
                        .and_then(|value| value.as_str())
                        .unwrap_or("");
                    let ops = if checkpoint.is_empty() {
                        vec![json!({
                            "device_id": "remote-a",
                            "seq": 1,
                            "op_id": "op-conversation-a",
                            "ciphertext_b64": encrypted_op_b64
                        })]
                    } else {
                        Vec::new()
                    };
                    write_json_response(
                        &mut stream,
                        200,
                        json!({
                            "protocol_version": 2,
                            "generation_id": "generation-a",
                            "checkpoint_token": "checkpoint-a",
                            "has_more": false,
                            "high_water": 1,
                            "history_lower_bound": { "remote-a": 1 },
                            "reseed_required": false,
                            "ops": ops
                        }),
                    );
                    continue;
                }

                write_json_response(&mut stream, 404, json!({"error":"not_found"}));
            }
            Err(error) if error.kind() == std::io::ErrorKind::WouldBlock => {
                thread::sleep(Duration::from_millis(10));
            }
            Err(error) => panic!("accept failed: {error}"),
        }
    });

    (format!("http://{}", addr), stop_tx, handle)
}

#[test]
fn managed_vault_pull_uses_v2_checkpoint_route_when_available() {
    let vault_id = "v1".to_string();
    let id_token = "test_uid".to_string();

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
    let encrypted_op_b64 = encrypted_conversation_op(
        &sync_key,
        "remote-a",
        1,
        "conversation-checkpoint-a",
        "op-conversation-a",
    );
    let (base_url, stop_tx, handle) = start_v2_pull_server(encrypted_op_b64);

    let applied =
        sync::managed_vault::pull(&conn_b, &key_b, &sync_key, &base_url, &vault_id, &id_token)
            .expect("pull");
    assert!(applied > 0);

    let diagnostics =
        secondloop_rust::api::sync_diagnostics::sync_managed_vault_cursor_diagnostics(
            app_dir_b.to_string_lossy().to_string(),
            base_url.clone(),
            vault_id.clone(),
            Some(id_token.clone()),
        )
        .expect("diagnostics");
    let diagnostics_json: serde_json::Value =
        serde_json::from_str(&diagnostics).expect("parse diagnostics");
    assert_eq!(
        diagnostics_json["managed_vault_protocol_version"].as_u64(),
        Some(2)
    );
    assert_eq!(
        diagnostics_json["managed_vault_generation_id"].as_str(),
        Some("generation-a")
    );
    assert_eq!(
        diagnostics_json["managed_vault_checkpoint_token_present"].as_bool(),
        Some(true)
    );

    let _ = stop_tx.send(());
    handle.join().expect("join");
}

#[test]
fn managed_vault_pull_with_progress_probes_v2_before_any_checkpoint_state_exists() {
    let vault_id = "v1".to_string();
    let id_token = "test_uid".to_string();

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
    let encrypted_op_b64 = encrypted_conversation_op(
        &sync_key,
        "remote-a",
        1,
        "conversation-progress-v2-a",
        "op-conversation-a",
    );
    let (base_url, stop_tx, handle) = start_v2_pull_server(encrypted_op_b64);

    let mut seen_progress = Vec::new();
    let applied = sync::managed_vault::pull_with_progress(
        &conn_b,
        &key_b,
        &sync_key,
        &base_url,
        &vault_id,
        &id_token,
        &mut |done, total| seen_progress.push((done, total)),
    )
    .expect("pull with progress");
    assert!(applied > 0);
    assert!(!seen_progress.is_empty());
    assert_eq!(seen_progress.last().copied(), Some((1, 1)));

    let diagnostics =
        secondloop_rust::api::sync_diagnostics::sync_managed_vault_cursor_diagnostics(
            app_dir_b.to_string_lossy().to_string(),
            base_url.clone(),
            vault_id.clone(),
            Some(id_token.clone()),
        )
        .expect("diagnostics");
    let diagnostics_json: serde_json::Value =
        serde_json::from_str(&diagnostics).expect("parse diagnostics");
    assert_eq!(
        diagnostics_json["managed_vault_protocol_version"].as_u64(),
        Some(2)
    );
    assert_eq!(
        diagnostics_json["managed_vault_generation_id"].as_str(),
        Some("generation-a")
    );
    assert_eq!(
        diagnostics_json["managed_vault_checkpoint_token_present"].as_bool(),
        Some(true)
    );

    let _ = stop_tx.send(());
    handle.join().expect("join");
}
