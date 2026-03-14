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
