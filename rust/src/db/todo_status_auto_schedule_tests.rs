use super::*;

fn create_todo(
    conn: &Connection,
    key: &[u8; 32],
    id: &str,
    due_at_ms: Option<i64>,
    status: &str,
) -> Todo {
    upsert_todo(
        conn,
        key,
        id,
        "Task",
        due_at_ms,
        status,
        None,
        None,
        None,
        Some(now_ms()),
    )
    .expect("create todo")
}

#[test]
fn set_todo_status_auto_schedules_unscheduled_open_todo_to_in_progress() {
    let dir = tempfile::tempdir().expect("tempdir");
    let conn = open(dir.path()).expect("open");
    let key = [21u8; 32];

    let created = create_todo(&conn, &key, "todo:auto:in-progress", None, "open");
    assert_eq!(created.due_at_ms, None);

    let updated = set_todo_status(&conn, &key, &created.id, "in_progress", None).expect("update");
    assert_eq!(updated.status, "in_progress");
    assert!(updated.due_at_ms.is_some());
}

#[test]
fn set_todo_status_auto_schedules_unscheduled_open_todo_to_done() {
    let dir = tempfile::tempdir().expect("tempdir");
    let conn = open(dir.path()).expect("open");
    let key = [22u8; 32];

    let created = create_todo(&conn, &key, "todo:auto:done", None, "open");
    assert_eq!(created.due_at_ms, None);

    let updated = set_todo_status(&conn, &key, &created.id, "done", None).expect("update");
    assert_eq!(updated.status, "done");
    assert!(updated.due_at_ms.is_some());
}

#[test]
fn set_todo_status_keeps_existing_schedule_when_already_scheduled() {
    let dir = tempfile::tempdir().expect("tempdir");
    let conn = open(dir.path()).expect("open");
    let key = [23u8; 32];

    let due_at_ms = now_ms().saturating_add(24 * 60 * 60 * 1000);
    let created = create_todo(&conn, &key, "todo:auto:keep-due", Some(due_at_ms), "open");
    assert_eq!(created.due_at_ms, Some(due_at_ms));

    let updated = set_todo_status(&conn, &key, &created.id, "in_progress", None).expect("update");
    assert_eq!(updated.status, "in_progress");
    assert_eq!(updated.due_at_ms, Some(due_at_ms));
}

#[test]
fn set_todo_status_does_not_auto_schedule_inbox_to_done() {
    let dir = tempfile::tempdir().expect("tempdir");
    let conn = open(dir.path()).expect("open");
    let key = [24u8; 32];

    let created = create_todo(&conn, &key, "todo:auto:inbox", None, "inbox");
    assert_eq!(created.due_at_ms, None);

    let updated = set_todo_status(&conn, &key, &created.id, "done", None).expect("update");
    assert_eq!(updated.status, "done");
    assert_eq!(updated.due_at_ms, None);
}

#[test]
fn transition_todo_updates_status_due_and_review_fields_atomically() {
    let dir = tempfile::tempdir().expect("tempdir");
    let conn = open(dir.path()).expect("open");
    let key = [25u8; 32];

    let created = upsert_todo(
        &conn,
        &key,
        "todo:transition",
        "Task",
        None,
        "done",
        None,
        Some(2),
        Some(now_ms().saturating_add(60_000)),
        None,
    )
    .expect("create todo");

    let target_due_at_ms = now_ms().saturating_add(24 * 60 * 60 * 1000);
    let updated = transition_todo(
        &conn,
        &key,
        &created.id,
        Some("in_progress"),
        Some(target_due_at_ms),
        false,
        None,
        true,
        None,
        true,
        Some(now_ms()),
        false,
        None,
    )
    .expect("transition todo");

    assert_eq!(updated.id, created.id);
    assert_eq!(updated.title, created.title);
    assert_eq!(updated.status, "in_progress");
    assert_eq!(updated.due_at_ms, Some(target_due_at_ms));
    assert_eq!(updated.review_stage, None);
    assert_eq!(updated.next_review_at_ms, None);
    assert!(updated.last_review_at_ms.is_some());
}
