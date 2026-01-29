use secondloop_rust::auth;
use secondloop_rust::crypto::{derive_root_key, encrypt_bytes, KdfParams};
use secondloop_rust::db;
use secondloop_rust::sync;
use secondloop_rust::sync::RemoteStore;

#[test]
fn sync_pull_todo_delete_removes_todo_and_deletes_linked_messages() {
    let remote = sync::InMemoryRemoteStore::new();
    let remote_root = "SecondLoopTest";

    // Device B has local state: a todo + an activity linking a source message.
    let temp_b = tempfile::tempdir().expect("tempdir B");
    let app_dir_b = temp_b.path().join("secondloop_b");
    let key_b =
        auth::init_master_password(&app_dir_b, "pw-b", KdfParams::for_test()).expect("init B");
    let conn_b = db::open(&app_dir_b).expect("open B db");

    let convo = db::get_or_create_main_stream_conversation(&conn_b, &key_b).expect("main stream");
    let source_msg =
        db::insert_message(&conn_b, &key_b, &convo.id, "user", "source").expect("source message");
    let note_msg =
        db::insert_message(&conn_b, &key_b, &convo.id, "user", "note").expect("note message");

    db::upsert_todo(
        &conn_b,
        &key_b,
        "todo:1",
        "Buy milk",
        None,
        "open",
        Some(&source_msg.id),
        None,
        None,
        None,
    )
    .expect("todo B");
    db::append_todo_note(&conn_b, &key_b, "todo:1", "linked note", Some(&note_msg.id))
        .expect("activity B");

    // Shared sync key (same on both devices).
    let sync_key = derive_root_key(
        "sync-passphrase",
        b"secondloop-sync1",
        &KdfParams::for_test(),
    )
    .expect("derive sync key");

    // Remote device publishes a todo.delete.v1 op (no packs; pull will fall back to ops files).
    let remote_device_id = "remote_device";
    let ops_dir = format!("/{remote_root}/{remote_device_id}/ops/");
    remote.mkdir_all(&ops_dir).expect("mkdir ops dir");

    let deleted_at_ms = note_msg.created_at_ms + 1;
    let op_json = serde_json::json!({
        "op_id": "op_1",
        "device_id": remote_device_id,
        "seq": 1,
        "ts_ms": deleted_at_ms,
        "type": "todo.delete.v1",
        "payload": {
            "todo_id": "todo:1",
            "deleted_at_ms": deleted_at_ms,
        }
    });
    let plaintext = serde_json::to_vec(&op_json).expect("op json bytes");
    let ciphertext = encrypt_bytes(
        &sync_key,
        &plaintext,
        format!("sync.ops:{remote_device_id}:1").as_bytes(),
    )
    .expect("encrypt op");
    let op_path = format!("{ops_dir}op_1.json");
    remote.put(&op_path, ciphertext).expect("put op");

    let applied = sync::pull(&conn_b, &key_b, &sync_key, &remote, remote_root).expect("pull");
    assert_eq!(applied, 1);

    let todos = db::list_todos(&conn_b, &key_b).expect("list todos");
    assert_eq!(todos.len(), 0);

    let messages = db::list_messages(&conn_b, &key_b, &convo.id).expect("list messages");
    assert_eq!(messages.len(), 0);
}
