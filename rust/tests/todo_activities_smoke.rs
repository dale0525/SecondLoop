use secondloop_rust::auth;
use secondloop_rust::crypto::KdfParams;
use secondloop_rust::db;

#[test]
fn todo_status_change_appends_activity_and_clears_review_fields() {
    let temp_dir = tempfile::tempdir().expect("tempdir");
    let app_dir = temp_dir.path().join("secondloop");

    let key = auth::init_master_password(&app_dir, "pw", KdfParams::for_test())
        .expect("init master password");

    let conn = db::open(&app_dir).expect("open db");
    let conversation = db::create_conversation(&conn, &key, "Inbox").expect("create conversation");
    let message = db::insert_message(&conn, &key, &conversation.id, "user", "接到了客户")
        .expect("insert message");

    db::upsert_todo(
        &conn,
        &key,
        "todo_1",
        "下午 2 点有客户来拜访，需要接待",
        None,
        "inbox",
        Some(&message.id),
        Some(0),
        Some(1_700_000_000_000),
        None,
    )
    .expect("upsert todo");

    let updated = db::set_todo_status(&conn, &key, "todo_1", "in_progress", Some(&message.id))
        .expect("set todo status");
    assert_eq!(updated.status, "in_progress");
    assert_eq!(updated.review_stage, None);
    assert_eq!(updated.next_review_at_ms, None);

    let activities = db::list_todo_activities(&conn, &key, "todo_1").expect("list activities");
    assert_eq!(activities.len(), 1);
    let activity = &activities[0];
    assert_eq!(activity.todo_id, "todo_1");
    assert_eq!(activity.activity_type, "status_change");
    assert_eq!(activity.from_status.as_deref(), Some("inbox"));
    assert_eq!(activity.to_status.as_deref(), Some("in_progress"));
    assert_eq!(
        activity.source_message_id.as_deref(),
        Some(message.id.as_str())
    );

    drop(conn);
    let conn2 = db::open(&app_dir).expect("open db again");
    let activities2 = db::list_todo_activities(&conn2, &key, "todo_1").expect("list activities");
    assert_eq!(activities2.len(), 1);
    assert_eq!(activities2[0].activity_type, "status_change");
}

#[test]
fn todo_note_activity_roundtrips_and_is_encrypted() {
    let temp_dir = tempfile::tempdir().expect("tempdir");
    let app_dir = temp_dir.path().join("secondloop");

    let key = auth::init_master_password(&app_dir, "pw", KdfParams::for_test())
        .expect("init master password");
    let wrong_key = [0u8; 32];

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

    let note =
        db::append_todo_note(&conn, &key, "todo_1", "狗粮做完了", None).expect("append note");
    assert_eq!(note.todo_id, "todo_1");
    assert_eq!(note.activity_type, "note");
    assert_eq!(note.content.as_deref(), Some("狗粮做完了"));

    let activities = db::list_todo_activities(&conn, &key, "todo_1").expect("list activities");
    assert!(activities
        .iter()
        .any(|a| a.content.as_deref() == Some("狗粮做完了")));

    let result = db::list_todo_activities(&conn, &wrong_key, "todo_1");
    assert!(result.is_err());
}
