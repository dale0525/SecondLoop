use rusqlite::params;

use secondloop_rust::auth;
use secondloop_rust::crypto::KdfParams;
use secondloop_rust::db;

#[test]
fn append_todo_note_uses_source_message_timestamp_for_created_at_ms() {
    let temp = tempfile::tempdir().expect("tempdir");
    let app_dir = temp.path().join("secondloop");
    let key = auth::init_master_password(&app_dir, "pw", KdfParams::for_test()).expect("init");
    let conn = db::open(&app_dir).expect("open db");

    let convo = db::get_or_create_loop_home_conversation(&conn, &key).expect("loop home");
    let msg = db::insert_message(&conn, &key, &convo.id, "user", "hello").expect("msg");
    let msg_id = msg.id.clone();

    let desired_ts: i64 = 123_456;
    conn.execute(
        "UPDATE messages SET created_at = ?1 WHERE id = ?2",
        params![desired_ts, msg_id],
    )
    .expect("update message timestamp");

    db::upsert_todo(
        &conn,
        &key,
        "todo:1",
        "Task",
        None,
        "open",
        Some(msg.id.as_str()),
        None,
        None,
        None,
    )
    .expect("todo");

    let activity =
        db::append_todo_note(&conn, &key, "todo:1", "hello", Some(&msg.id)).expect("activity");

    assert_eq!(activity.created_at_ms, desired_ts);
}

#[test]
fn append_todo_note_without_source_message_creates_chat_message_in_todo_thread() {
    let temp = tempfile::tempdir().expect("tempdir");
    let app_dir = temp.path().join("secondloop");
    let key = auth::init_master_password(&app_dir, "pw", KdfParams::for_test()).expect("init");
    let conn = db::open(&app_dir).expect("open db");

    let convo = db::create_conversation(&conn, &key, "Other").expect("conversation");
    let source_msg =
        db::insert_message(&conn, &key, &convo.id, "user", "source").expect("source msg");

    db::upsert_todo(
        &conn,
        &key,
        "todo:1",
        "Task",
        None,
        "open",
        Some(source_msg.id.as_str()),
        None,
        None,
        None,
    )
    .expect("todo");

    let activity =
        db::append_todo_note(&conn, &key, "todo:1", "follow up", None).expect("activity");
    let follow_up_msg_id = activity
        .source_message_id
        .clone()
        .expect("todo note should create a source message");

    let messages = db::list_messages(&conn, &key, &convo.id).expect("list messages");
    assert_eq!(messages.len(), 2);

    let follow_up = messages
        .iter()
        .find(|m| m.id == follow_up_msg_id)
        .expect("follow-up message not found");
    assert_eq!(follow_up.role, "user");
    assert_eq!(follow_up.content, "follow up");
}
