use secondloop_rust::auth;
use secondloop_rust::crypto::KdfParams;
use secondloop_rust::db;

#[test]
fn actions_schema_smoke_roundtrip_persists_across_restart() {
    let temp_dir = tempfile::tempdir().expect("tempdir");
    let app_dir = temp_dir.path().join("secondloop");

    let key = auth::init_master_password(&app_dir, "pw", KdfParams::for_test())
        .expect("init master password");

    let conn = db::open(&app_dir).expect("open db");
    let conversation = db::create_conversation(&conn, &key, "Inbox").expect("create conversation");
    let message =
        db::insert_message(&conn, &key, &conversation.id, "user", "周末做某事").expect("message");

    db::upsert_todo(
        &conn,
        &key,
        "todo_1",
        "周末做某事",
        None,
        "inbox",
        Some(&message.id),
        Some(0),
        Some(1_700_000_000_000),
        None,
    )
    .expect("upsert todo");

    db::upsert_event(
        &conn,
        &key,
        "event_1",
        "Coffee chat",
        1_700_000_000_000,
        1_700_000_360_000,
        "America/Los_Angeles",
        Some(&message.id),
    )
    .expect("upsert event");

    let todos = db::list_todos(&conn, &key).expect("list todos");
    assert_eq!(todos.len(), 1);
    assert_eq!(todos[0].id, "todo_1");
    assert_eq!(todos[0].title, "周末做某事");
    assert_eq!(todos[0].status, "inbox");
    assert_eq!(
        todos[0].source_entry_id.as_deref(),
        Some(message.id.as_str())
    );
    assert_eq!(todos[0].review_stage, Some(0));
    assert_eq!(todos[0].next_review_at_ms, Some(1_700_000_000_000));

    let events = db::list_events(&conn, &key).expect("list events");
    assert_eq!(events.len(), 1);
    assert_eq!(events[0].id, "event_1");
    assert_eq!(events[0].title, "Coffee chat");
    assert_eq!(events[0].start_at_ms, 1_700_000_000_000);
    assert_eq!(events[0].end_at_ms, 1_700_000_360_000);
    assert_eq!(events[0].tz, "America/Los_Angeles");
    assert_eq!(
        events[0].source_entry_id.as_deref(),
        Some(message.id.as_str())
    );
    drop(conn);

    let conn2 = db::open(&app_dir).expect("open db again");
    let todos2 = db::list_todos(&conn2, &key).expect("list todos again");
    assert_eq!(todos2.len(), 1);
    assert_eq!(todos2[0].id, "todo_1");
    assert_eq!(todos2[0].title, "周末做某事");

    let events2 = db::list_events(&conn2, &key).expect("list events again");
    assert_eq!(events2.len(), 1);
    assert_eq!(events2[0].id, "event_1");
    assert_eq!(events2[0].title, "Coffee chat");
}

#[test]
fn actions_schema_smoke_wrong_key_cannot_decrypt() {
    let temp_dir = tempfile::tempdir().expect("tempdir");
    let app_dir = temp_dir.path().join("secondloop");

    let key =
        auth::init_master_password(&app_dir, "pw", KdfParams::for_test()).expect("init master");
    let wrong_key = [0u8; 32];

    let conn = db::open(&app_dir).expect("open db");
    db::upsert_todo(
        &conn, &key, "todo_1", "hello", None, "inbox", None, None, None, None,
    )
    .expect("upsert todo");

    let result = db::list_todos(&conn, &wrong_key);
    assert!(result.is_err());
}
