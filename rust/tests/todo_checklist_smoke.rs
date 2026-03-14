use secondloop_rust::auth;
use secondloop_rust::crypto::KdfParams;
use secondloop_rust::db;

fn setup() -> (tempfile::TempDir, [u8; 32], rusqlite::Connection) {
    let temp_dir = tempfile::tempdir().expect("tempdir");
    let app_dir = temp_dir.path().join("secondloop");
    let key = auth::init_master_password(&app_dir, "pw", KdfParams::for_test())
        .expect("init master password");
    let conn = db::open(&app_dir).expect("open db");
    (temp_dir, key, conn)
}

#[test]
fn checklist_item_crud_and_progress_roundtrip() {
    let (_temp_dir, key, conn) = setup();

    db::upsert_todo(
        &conn,
        &key,
        "todo_1",
        "Plan launch",
        None,
        "open",
        None,
        None,
        None,
        None,
    )
    .expect("upsert todo");

    let item = db::create_todo_checklist_item(&conn, &key, "todo_1", "Draft announcement")
        .expect("create checklist item");
    assert_eq!(item.todo_id, "todo_1");
    assert_eq!(item.content, "Draft announcement");
    assert!(!item.is_done);

    let listed = db::list_todo_checklist_items(&conn, &key, "todo_1").expect("list items");
    assert_eq!(listed.len(), 1);
    assert_eq!(listed[0].id, item.id);

    let updated =
        db::update_todo_checklist_item_content(&conn, &key, &item.id, "Draft launch post")
            .expect("update content");
    assert_eq!(updated.content, "Draft launch post");

    let completed =
        db::set_todo_checklist_item_done(&conn, &key, &item.id, true).expect("set done");
    assert!(completed.is_done);

    let progress = db::list_todo_checklist_progress(&conn, &key).expect("list progress");
    assert_eq!(progress.len(), 1);
    assert_eq!(progress[0].todo_id, "todo_1");
    assert_eq!(progress[0].done_count, 1);
    assert_eq!(progress[0].total_count, 1);

    db::delete_todo_checklist_item(&conn, &key, &item.id).expect("delete item");
    let listed_after_delete =
        db::list_todo_checklist_items(&conn, &key, "todo_1").expect("list items after delete");
    assert!(listed_after_delete.is_empty());
}

#[test]
fn checklist_items_can_be_reordered() {
    let (_temp_dir, key, conn) = setup();

    db::upsert_todo(
        &conn,
        &key,
        "todo_1",
        "Plan launch",
        None,
        "open",
        None,
        None,
        None,
        None,
    )
    .expect("upsert todo");

    let first =
        db::create_todo_checklist_item(&conn, &key, "todo_1", "First").expect("create first");
    let second =
        db::create_todo_checklist_item(&conn, &key, "todo_1", "Second").expect("create second");

    db::reorder_todo_checklist_items(
        &conn,
        &key,
        "todo_1",
        &[second.id.clone(), first.id.clone()],
    )
    .expect("reorder items");

    let listed = db::list_todo_checklist_items(&conn, &key, "todo_1").expect("list items");
    assert_eq!(listed.len(), 2);
    assert_eq!(listed[0].id, second.id);
    assert_eq!(listed[1].id, first.id);
    assert!(listed[0].sort_order < listed[1].sort_order);
}

#[test]
fn checklist_no_op_content_update_keeps_timestamp_and_oplog_stable() {
    let (_temp_dir, key, conn) = setup();

    db::upsert_todo(
        &conn,
        &key,
        "todo_1",
        "Plan launch",
        None,
        "open",
        None,
        None,
        None,
        None,
    )
    .expect("upsert todo");

    let item = db::create_todo_checklist_item(&conn, &key, "todo_1", "Draft launch post")
        .expect("create checklist item");
    let oplog_before: i64 = conn
        .query_row("SELECT COUNT(*) FROM oplog", [], |row| row.get(0))
        .expect("count oplog before");

    let updated =
        db::update_todo_checklist_item_content(&conn, &key, &item.id, "Draft launch post")
            .expect("noop update content");
    let oplog_after: i64 = conn
        .query_row("SELECT COUNT(*) FROM oplog", [], |row| row.get(0))
        .expect("count oplog after");

    assert_eq!(updated.content, item.content);
    assert_eq!(updated.updated_at_ms, item.updated_at_ms);
    assert_eq!(oplog_after, oplog_before);
}

#[test]
fn checklist_reorder_uses_consistent_updated_at_in_rows_and_oplog() {
    let (_temp_dir, key, conn) = setup();

    db::upsert_todo(
        &conn,
        &key,
        "todo_1",
        "Plan launch",
        None,
        "open",
        None,
        None,
        None,
        None,
    )
    .expect("upsert todo");

    let first =
        db::create_todo_checklist_item(&conn, &key, "todo_1", "First").expect("create first");
    let second =
        db::create_todo_checklist_item(&conn, &key, "todo_1", "Second").expect("create second");

    db::reorder_todo_checklist_items(
        &conn,
        &key,
        "todo_1",
        &[second.id.clone(), first.id.clone()],
    )
    .expect("reorder items");

    let listed = db::list_todo_checklist_items(&conn, &key, "todo_1").expect("list items");
    assert_eq!(listed.len(), 2);
    assert_eq!(listed[0].updated_at_ms, listed[1].updated_at_ms);

    let (op_id, blob): (String, Vec<u8>) = conn
        .query_row(
            "SELECT op_id, op_json FROM oplog ORDER BY created_at DESC, seq DESC LIMIT 1",
            [],
            |row| Ok((row.get(0)?, row.get(1)?)),
        )
        .expect("read latest oplog");
    let plaintext = secondloop_rust::crypto::decrypt_bytes(
        &key,
        &blob,
        format!("oplog.op_json:{op_id}").as_bytes(),
    )
    .expect("decrypt oplog");
    let op: serde_json::Value = serde_json::from_slice(&plaintext).expect("parse oplog json");
    let payload_updated_at = op["payload"]["updated_at_ms"]
        .as_i64()
        .expect("payload updated_at_ms");

    assert_eq!(payload_updated_at, listed[0].updated_at_ms);
}
