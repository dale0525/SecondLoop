use secondloop_rust::auth;
use secondloop_rust::crypto::KdfParams;
use secondloop_rust::db;

#[test]
fn todo_history_range_lists_created_todos_and_activities() {
    let temp_dir = tempfile::tempdir().expect("tempdir");
    let app_dir = temp_dir.path().join("secondloop");

    let key = auth::init_master_password(&app_dir, "pw", KdfParams::for_test())
        .expect("init master password");
    let conn = db::open(&app_dir).expect("open db");

    let todo_1 = db::upsert_todo(
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
    .expect("todo 1");

    std::thread::sleep(std::time::Duration::from_millis(3));
    let status =
        db::set_todo_status(&conn, &key, "todo_1", "in_progress", None).expect("status change");
    assert_eq!(status.status, "in_progress");

    std::thread::sleep(std::time::Duration::from_millis(3));
    let note =
        db::append_todo_note(&conn, &key, "todo_1", "狗粮做完了", None).expect("append note");

    std::thread::sleep(std::time::Duration::from_millis(3));
    let todo_2 = db::upsert_todo(
        &conn,
        &key,
        "todo_2",
        "下午 2 点接待客户",
        None,
        "open",
        None,
        None,
        None,
        None,
    )
    .expect("todo 2");

    let start = todo_1.created_at_ms.saturating_sub(1);
    let end_exclusive = todo_2.created_at_ms.saturating_add(1);

    let created =
        db::list_todos_created_in_range(&conn, &key, start, end_exclusive).expect("created");
    assert_eq!(created.len(), 2);
    assert!(created.iter().any(|t| t.id == "todo_1"));
    assert!(created.iter().any(|t| t.id == "todo_2"));

    let created_first_only =
        db::list_todos_created_in_range(&conn, &key, start, todo_2.created_at_ms)
            .expect("created first only");
    assert_eq!(created_first_only.len(), 1);
    assert_eq!(created_first_only[0].id, "todo_1");

    let activities =
        db::list_todo_activities_in_range(&conn, &key, start, end_exclusive).expect("activities");
    assert_eq!(activities.len(), 2);
    assert!(activities.iter().any(
        |a| a.activity_type == "status_change" && a.to_status.as_deref() == Some("in_progress")
    ));
    assert!(activities
        .iter()
        .any(|a| a.activity_type == "note" && a.id == note.id));
}
