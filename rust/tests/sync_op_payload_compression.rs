use base64::engine::general_purpose::STANDARD as B64_STD;
use base64::Engine as _;
use chacha20poly1305::aead::{Aead, Payload};
use chacha20poly1305::{KeyInit, XChaCha20Poly1305, XNonce};
use secondloop_rust::auth;
use secondloop_rust::crypto::{decrypt_bytes, derive_root_key, KdfParams};
use secondloop_rust::db;
use secondloop_rust::sync;
use secondloop_rust::sync::RemoteStore;

#[path = "support/managed_vault_v2_test_server.rs"]
mod managed_vault_v2_test_server;

use managed_vault_v2_test_server::start_mock_v2_server;

const SYNC_OP_COMPRESSED_MAGIC_V1: &[u8; 5] = b"SLOP1";

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

fn request_body_json(request: &str) -> serde_json::Value {
    let (_, body) = request
        .split_once("\r\n\r\n")
        .expect("http request should contain headers");
    serde_json::from_str(body).expect("request body json")
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
    let (base_url, stop_tx, state, handle) = start_mock_v2_server();
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
    let requests = state.lock().expect("state lock").requests.clone();
    let captured = requests
        .iter()
        .filter(|request| request.starts_with("POST /v2/vaults/v1/sync/push "))
        .flat_map(|request| {
            request_body_json(request)["ops"]
                .as_array()
                .cloned()
                .unwrap_or_default()
        })
        .find(|op| {
            op["device_id"].as_str() == Some(device_id.as_str()) && op["seq"].as_i64() == Some(seq)
        })
        .expect("captured pushed op");

    let ciphertext = B64_STD
        .decode(
            captured["ciphertext_b64"]
                .as_str()
                .expect("ciphertext_b64")
                .as_bytes(),
        )
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

    stop_tx.send(()).expect("stop");
    handle.join().expect("join server");
}
