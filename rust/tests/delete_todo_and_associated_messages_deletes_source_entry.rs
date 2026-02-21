use secondloop_rust::auth;
use secondloop_rust::crypto::KdfParams;
use secondloop_rust::db;

#[test]
fn delete_todo_and_associated_messages_deletes_source_entry_and_activity_messages() {
    let temp = tempfile::tempdir().expect("tempdir");
    let app_dir = temp.path().join("secondloop");
    let key = auth::init_master_password(&app_dir, "pw", KdfParams::for_test()).expect("init");
    let conn = db::open(&app_dir).expect("open db");

    let convo = db::get_or_create_loop_home_conversation(&conn, &key).expect("loop home");
    let source_msg =
        db::insert_message(&conn, &key, &convo.id, "user", "source").expect("source msg");
    let note_msg = db::insert_message(&conn, &key, &convo.id, "user", "note").expect("note msg");

    db::upsert_todo(
        &conn,
        &key,
        "todo:1",
        "Task",
        None,
        "open",
        Some(&source_msg.id),
        None,
        None,
        None,
    )
    .expect("todo");
    db::append_todo_note(&conn, &key, "todo:1", "linked note", Some(&note_msg.id))
        .expect("activity");

    let deleted =
        db::delete_todo_and_associated_messages(&conn, &key, &app_dir, "todo:1").expect("delete");
    assert_eq!(deleted, 2);

    let todos = db::list_todos(&conn, &key).expect("list todos");
    assert_eq!(todos.len(), 0);

    let messages = db::list_messages(&conn, &key, &convo.id).expect("list messages");
    assert_eq!(messages.len(), 0);
}
