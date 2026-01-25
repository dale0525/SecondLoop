use secondloop_rust::auth;
use secondloop_rust::crypto::KdfParams;
use secondloop_rust::db;

#[test]
fn todo_activity_can_link_and_list_attachments() {
    let temp_dir = tempfile::tempdir().expect("tempdir");
    let app_dir = temp_dir.path().join("secondloop");

    let key = auth::init_master_password(&app_dir, "pw", KdfParams::for_test())
        .expect("init master password");
    let conn = db::open(&app_dir).expect("open db");

    db::upsert_todo(
        &conn,
        &key,
        "todo_1",
        "周末给狗狗做口粮",
        None,
        "open",
        None,
        None,
        None,
        None,
    )
    .expect("upsert todo");

    let activity =
        db::append_todo_note(&conn, &key, "todo_1", "狗粮做完了", None).expect("append note");

    let attachment = db::insert_attachment(&conn, &key, &app_dir, b"hello world", "text/plain")
        .expect("insert attachment");

    db::link_attachment_to_todo_activity(&conn, &key, &activity.id, &attachment.sha256)
        .expect("link attachment");
    db::link_attachment_to_todo_activity(&conn, &key, &activity.id, &attachment.sha256)
        .expect("link attachment idempotent");

    let listed =
        db::list_todo_activity_attachments(&conn, &key, &activity.id).expect("list attachments");
    assert_eq!(listed.len(), 1);
    assert_eq!(listed[0].sha256, attachment.sha256);
    assert_eq!(listed[0].mime_type, "text/plain");
}
