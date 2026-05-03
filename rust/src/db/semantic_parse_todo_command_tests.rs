use tempfile::tempdir;

use super::*;

#[test]
fn semantic_parse_todo_command_reprioritize_updates_todo_and_finalizes_job() {
    let dir = tempdir().expect("tempdir");
    let conn = open(dir.path()).expect("open");
    let key = [6u8; 32];

    let conversation = get_or_create_loop_home_conversation(&conn, &key).expect("conversation");
    let message =
        insert_message(&conn, &key, &conversation.id, "user", "把报销优先级调高").expect("message");
    enqueue_semantic_parse_job(&conn, &message.id, 30_000).expect("enqueue");
    let attempt_id = mark_semantic_parse_job_running(&conn, &message.id, 30_001).expect("running");

    let seeded = upsert_todo(
        &conn,
        &key,
        "todo:priority",
        "报销",
        None,
        "open",
        Some(&message.id),
        None,
        None,
        None,
        Some(0),
        Some(0),
    )
    .expect("seed todo");

    let applied = complete_semantic_parse_todo_command_if_current_attempt(
        &conn,
        &key,
        &message.id,
        attempt_id,
        &seeded.id,
        Some("报销"),
        "todo_command:reprioritize",
        None,
        None,
        None,
        Some(1),
        Some(1),
        None,
        None,
        None,
        30_010,
    )
    .expect("todo command applied");
    assert!(applied);

    let todo = get_todo(&conn, &key, &seeded.id).expect("todo after command");
    assert_eq!(todo.manual_importance_nudge_score, Some(1));
    assert_eq!(todo.manual_urgency_nudge_score, Some(1));

    let jobs =
        list_semantic_parse_jobs_by_message_ids(&conn, &key, &[message.id.clone()]).expect("jobs");
    assert_eq!(jobs.len(), 1);
    assert_eq!(jobs[0].status, "succeeded");
    assert_eq!(
        jobs[0].applied_action_kind.as_deref(),
        Some("todo_command:reprioritize")
    );
    assert_eq!(jobs[0].applied_todo_id.as_deref(), Some("todo:priority"));
    assert_eq!(jobs[0].applied_prev_todo_status, None);
}

#[test]
fn semantic_parse_todo_command_stale_attempt_does_not_mutate_todo() {
    let dir = tempdir().expect("tempdir");
    let conn = open(dir.path()).expect("open");
    let key = [7u8; 32];

    let conversation = get_or_create_loop_home_conversation(&conn, &key).expect("conversation");
    let message =
        insert_message(&conn, &key, &conversation.id, "user", "把报销优先级调高").expect("message");
    enqueue_semantic_parse_job(&conn, &message.id, 31_000).expect("enqueue");
    let attempt_id = mark_semantic_parse_job_running(&conn, &message.id, 31_001).expect("running");

    let seeded = upsert_todo(
        &conn,
        &key,
        "todo:priority-stale",
        "报销",
        None,
        "open",
        Some(&message.id),
        None,
        None,
        None,
        Some(0),
        Some(0),
    )
    .expect("seed todo");

    let applied = complete_semantic_parse_todo_command_if_current_attempt(
        &conn,
        &key,
        &message.id,
        attempt_id + 1,
        &seeded.id,
        Some("报销"),
        "todo_command:reprioritize",
        None,
        None,
        None,
        Some(1),
        Some(1),
        None,
        None,
        None,
        31_010,
    )
    .expect("todo command rejected");
    assert!(!applied);

    let todo = get_todo(&conn, &key, &seeded.id).expect("todo after command");
    assert_eq!(todo.manual_importance_nudge_score, Some(0));
    assert_eq!(todo.manual_urgency_nudge_score, Some(0));
}
