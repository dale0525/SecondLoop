use std::time::{SystemTime, UNIX_EPOCH};

use rusqlite::{params, Connection};
use secondloop_rust::auth;
use secondloop_rust::crypto::{derive_root_key, encrypt_bytes, KdfParams};
use secondloop_rust::db;
use secondloop_rust::sync;
use secondloop_rust::sync::RemoteStore;

fn now_ms() -> i64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .expect("now")
        .as_millis()
        .try_into()
        .expect("ms i64")
}

fn insert_raw_op(conn: &Connection, db_key: &[u8; 32], op: serde_json::Value) {
    let op_id = op["op_id"].as_str().expect("op_id").to_string();
    let device_id = op["device_id"].as_str().expect("device_id").to_string();
    let seq = op["seq"].as_i64().expect("seq");
    let created_at = op["ts_ms"].as_i64().expect("ts_ms");

    let plaintext = serde_json::to_vec(&op).expect("op json");
    let aad = format!("oplog.op_json:{op_id}");
    let blob = encrypt_bytes(db_key, &plaintext, aad.as_bytes()).expect("encrypt op");

    conn.execute(
        r#"INSERT INTO oplog(op_id, device_id, seq, op_json, created_at)
           VALUES (?1, ?2, ?3, ?4, ?5)"#,
        params![op_id, device_id, seq, blob, created_at],
    )
    .expect("insert oplog");
}

fn next_seq(conn: &Connection, device_id: &str) -> i64 {
    conn.query_row(
        r#"SELECT COALESCE(MAX(seq), 0) FROM oplog WHERE device_id = ?1"#,
        params![device_id],
        |row| row.get(0),
    )
    .expect("max seq")
}

#[test]
fn sync_attachment_delete_purges_remote_and_messages() {
    let remote = sync::InMemoryRemoteStore::new();
    let remote_root = "SecondLoopTest";

    // Device A creates 2 messages referencing the same attachment.
    let temp_a = tempfile::tempdir().expect("tempdir A");
    let app_dir_a = temp_a.path().join("secondloop_a");
    let key_a =
        auth::init_master_password(&app_dir_a, "pw-a", KdfParams::for_test()).expect("init A");
    let conn_a = db::open(&app_dir_a).expect("open A db");

    let conversation =
        db::get_or_create_loop_home_conversation(&conn_a, &key_a).expect("conversation A");
    let message1 =
        db::insert_message(&conn_a, &key_a, &conversation.id, "user", "m1").expect("message1");
    let message2 =
        db::insert_message(&conn_a, &key_a, &conversation.id, "user", "m2").expect("message2");

    let bytes = b"pretend image bytes";
    let attachment = db::insert_attachment(&conn_a, &key_a, &app_dir_a, bytes, "image/webp")
        .expect("insert attachment");
    db::link_attachment_to_message(&conn_a, &key_a, &message1.id, &attachment.sha256)
        .expect("link1");
    db::link_attachment_to_message(&conn_a, &key_a, &message2.id, &attachment.sha256)
        .expect("link2");

    let sync_key = derive_root_key(
        "sync-passphrase",
        b"secondloop-sync1",
        &KdfParams::for_test(),
    )
    .expect("sync key");

    // First push uploads attachment bytes.
    let pushed1 = sync::push(&conn_a, &key_a, &sync_key, &remote, remote_root).expect("push1");
    assert!(pushed1 > 0);

    let remote_path = format!("/{remote_root}/attachments/{}.bin", attachment.sha256);
    remote.get(&remote_path).expect("remote attachment exists");

    // Simulate user "purge": delete all referencing messages + emit attachment delete op.
    db::set_message_deleted(&conn_a, &key_a, &message1.id, true).expect("delete message1");
    db::set_message_deleted(&conn_a, &key_a, &message2.id, true).expect("delete message2");

    let device_id = db::get_or_create_device_id(&conn_a).expect("device id");
    let seq = next_seq(&conn_a, &device_id) + 1;
    let now = now_ms();
    insert_raw_op(
        &conn_a,
        &key_a,
        serde_json::json!({
            "op_id": uuid::Uuid::new_v4().to_string(),
            "device_id": device_id,
            "seq": seq,
            "ts_ms": now,
            "type": "attachment.delete.v1",
            "payload": { "sha256": attachment.sha256, "deleted_at_ms": now }
        }),
    );

    // Second push should remove remote attachment bytes.
    let pushed2 = sync::push(&conn_a, &key_a, &sync_key, &remote, remote_root).expect("push2");
    assert!(pushed2 > 0);

    assert!(
        remote.get(&remote_path).is_err(),
        "expected remote attachment to be deleted"
    );

    // Device B pulls and should converge: messages deleted + attachment metadata removed.
    let temp_b = tempfile::tempdir().expect("tempdir B");
    let app_dir_b = temp_b.path().join("secondloop_b");
    let key_b =
        auth::init_master_password(&app_dir_b, "pw-b", KdfParams::for_test()).expect("init B");
    let conn_b = db::open(&app_dir_b).expect("open B db");

    let applied =
        sync::pull(&conn_b, &key_b, &sync_key, &remote, remote_root).expect("pull should succeed");
    assert!(applied > 0);

    let messages = db::list_messages(&conn_b, &key_b, &conversation.id).expect("list messages");
    assert_eq!(messages.len(), 0, "expected all messages deleted");

    let recent = db::list_recent_attachments(&conn_b, &key_b, 10).expect("list attachments");
    assert!(
        recent.iter().all(|a| a.sha256 != attachment.sha256),
        "expected attachment metadata removed"
    );
}
