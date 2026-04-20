use tempfile::tempdir;

use super::*;

#[test]
fn semantic_parse_followup_same_status_finalizes_as_no_action() {
    let dir = tempdir().expect("tempdir");
    let conn = open(dir.path()).expect("open");
    let key = [4u8; 32];

    let conversation = get_or_create_loop_home_conversation(&conn, &key).expect("conversation");
    let message = insert_message(&conn, &key, &conversation.id, "user", "把这个标记为进行中")
        .expect("message");
    enqueue_semantic_parse_job(&conn, &message.id, 20_000).expect("enqueue");
    let attempt_id = mark_semantic_parse_job_running(&conn, &message.id, 20_001).expect("running");

    let seeded = upsert_todo(
        &conn,
        &key,
        "todo:followup-same-status",
        "报销",
        Some(20_200),
        "open",
        Some(&message.id),
        None,
        None,
        None,
        None,
        None,
    )
    .expect("seed todo");

    let applied = complete_semantic_parse_followup_if_current_attempt(
        &conn,
        &key,
        &message.id,
        attempt_id,
        &seeded.id,
        Some("报销"),
        Some("open"),
        None,
        None,
        None,
        None,
        20_010,
    )
    .expect("followup applied");
    assert!(applied);

    let todo = get_todo(&conn, &key, &seeded.id).expect("todo after followup");
    assert_eq!(todo.status, "open");

    let jobs =
        list_semantic_parse_jobs_by_message_ids(&conn, &key, &[message.id.clone()]).expect("jobs");
    assert_eq!(jobs.len(), 1);
    assert_eq!(jobs[0].status, "succeeded");
    assert_eq!(jobs[0].applied_action_kind.as_deref(), Some("none"));
    assert_eq!(jobs[0].applied_todo_id, None);
    assert_eq!(jobs[0].applied_prev_todo_status, None);
    assert!(!jobs[0].applied_due_changed);
    assert_eq!(jobs[0].applied_prev_todo_due_at_ms, None);
}

#[test]
fn semantic_parse_followup_same_due_finalizes_as_no_action() {
    let dir = tempdir().expect("tempdir");
    let conn = open(dir.path()).expect("open");
    let key = [5u8; 32];

    let conversation = get_or_create_loop_home_conversation(&conn, &key).expect("conversation");
    let message = insert_message(&conn, &key, &conversation.id, "user", "把这个改到明天晚上")
        .expect("message");
    enqueue_semantic_parse_job(&conn, &message.id, 21_000).expect("enqueue");
    let attempt_id = mark_semantic_parse_job_running(&conn, &message.id, 21_001).expect("running");

    let seeded = upsert_todo(
        &conn,
        &key,
        "todo:followup-same-due",
        "报销",
        Some(21_500),
        "open",
        Some(&message.id),
        None,
        None,
        None,
        None,
        None,
    )
    .expect("seed todo");

    let applied = complete_semantic_parse_followup_if_current_attempt(
        &conn,
        &key,
        &message.id,
        attempt_id,
        &seeded.id,
        Some("报销"),
        None,
        Some(21_500),
        None,
        None,
        None,
        21_010,
    )
    .expect("followup applied");
    assert!(applied);

    let todo = get_todo(&conn, &key, &seeded.id).expect("todo after followup");
    assert_eq!(todo.due_at_ms, Some(21_500));

    let jobs =
        list_semantic_parse_jobs_by_message_ids(&conn, &key, &[message.id.clone()]).expect("jobs");
    assert_eq!(jobs.len(), 1);
    assert_eq!(jobs[0].status, "succeeded");
    assert_eq!(jobs[0].applied_action_kind.as_deref(), Some("none"));
    assert_eq!(jobs[0].applied_todo_id, None);
    assert_eq!(jobs[0].applied_prev_todo_due_at_ms, None);
    assert!(!jobs[0].applied_due_changed);
    assert_eq!(jobs[0].applied_prev_todo_status, None);
}
