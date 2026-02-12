use secondloop_rust::auth;
use secondloop_rust::crypto::KdfParams;
use secondloop_rust::db;

#[test]
fn marking_recurring_todo_done_spawns_next_occurrence() {
    let temp = tempfile::tempdir().expect("tempdir");
    let app_dir = temp.path().join("secondloop");
    let key = auth::init_master_password(&app_dir, "pw", KdfParams::for_test()).expect("init");
    let conn = db::open(&app_dir).expect("open db");

    let due_at_ms = 1_730_808_000_000i64; // 2024-11-01T10:00:00Z

    db::upsert_todo(
        &conn,
        &key,
        "todo:daily:1",
        "Daily standup",
        Some(due_at_ms),
        "open",
        None,
        None,
        None,
        None,
    )
    .expect("upsert todo");

    db::upsert_todo_recurrence(
        &conn,
        "todo:daily:1",
        "series:daily:1",
        r#"{"freq":"daily","interval":1}"#,
    )
    .expect("upsert recurrence");

    db::set_todo_status(&conn, &key, "todo:daily:1", "done", None).expect("set done");

    let todos = db::list_todos(&conn, &key).expect("list todos");
    assert_eq!(todos.len(), 2);

    let done = todos
        .iter()
        .find(|todo| todo.id == "todo:daily:1")
        .expect("done todo exists");
    assert_eq!(done.status, "done");

    let spawned = todos
        .iter()
        .find(|todo| todo.id != "todo:daily:1")
        .expect("spawned todo exists");
    assert_eq!(spawned.status, "open");
    assert_eq!(spawned.due_at_ms, Some(due_at_ms + 24 * 60 * 60 * 1000));

    let spawned_rule = db::get_todo_recurrence_rule_json(&conn, &spawned.id)
        .expect("load spawned recurrence")
        .expect("spawned recurrence exists");
    assert!(spawned_rule.contains("\"daily\""));
}

#[test]
fn setting_done_twice_does_not_spawn_duplicates() {
    let temp = tempfile::tempdir().expect("tempdir");
    let app_dir = temp.path().join("secondloop");
    let key = auth::init_master_password(&app_dir, "pw", KdfParams::for_test()).expect("init");
    let conn = db::open(&app_dir).expect("open db");

    db::upsert_todo(
        &conn,
        &key,
        "todo:daily:1",
        "Daily standup",
        Some(1_730_808_000_000i64),
        "open",
        None,
        None,
        None,
        None,
    )
    .expect("upsert todo");

    db::upsert_todo_recurrence(
        &conn,
        "todo:daily:1",
        "series:daily:1",
        r#"{"freq":"daily","interval":1}"#,
    )
    .expect("upsert recurrence");

    db::set_todo_status(&conn, &key, "todo:daily:1", "done", None).expect("set done once");
    db::set_todo_status(&conn, &key, "todo:daily:1", "done", None).expect("set done twice");

    let todos = db::list_todos(&conn, &key).expect("list todos");
    assert_eq!(todos.len(), 2);
}
