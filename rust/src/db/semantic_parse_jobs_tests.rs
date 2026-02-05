use tempfile::tempdir;

use super::*;

#[test]
fn semantic_parse_jobs_lifecycle_and_due_query() {
    let dir = tempdir().expect("tempdir");
    let conn = open(dir.path()).expect("open");

    let now_ms = 1_000i64;
    enqueue_semantic_parse_job(&conn, "msg:1", now_ms).expect("enqueue");

    let due = list_due_semantic_parse_jobs(&conn, now_ms, 10).expect("list due");
    assert_eq!(due.len(), 1);
    assert_eq!(due[0].message_id, "msg:1");
    assert_eq!(due[0].status, "pending");
    assert_eq!(due[0].attempts, 0);
    assert_eq!(due[0].next_retry_at_ms, None);

    mark_semantic_parse_job_running(&conn, "msg:1", now_ms + 1).expect("running");
    let due_after_running = list_due_semantic_parse_jobs(&conn, now_ms + 1, 10).expect("list due");
    assert_eq!(due_after_running.len(), 1);
    assert_eq!(due_after_running[0].message_id, "msg:1");
    assert_eq!(due_after_running[0].status, "running");

    mark_semantic_parse_job_failed(&conn, "msg:1", 1, now_ms + 120, "timeout", now_ms + 2)
        .expect("failed");

    let due_before_retry = list_due_semantic_parse_jobs(&conn, now_ms + 100, 10).expect("list due");
    assert!(due_before_retry.is_empty());

    let due_ready = list_due_semantic_parse_jobs(&conn, now_ms + 120, 10).expect("list due");
    assert_eq!(due_ready.len(), 1);
    assert_eq!(due_ready[0].status, "failed");
    assert_eq!(due_ready[0].attempts, 1);
    assert_eq!(due_ready[0].next_retry_at_ms, Some(now_ms + 120));

    mark_semantic_parse_job_retry(&conn, "msg:1", now_ms + 121).expect("retry");

    let due_again = list_due_semantic_parse_jobs(&conn, now_ms + 121, 10).expect("list due");
    assert_eq!(due_again.len(), 1);
    assert_eq!(due_again[0].status, "pending");
    assert_eq!(due_again[0].attempts, 1);
    assert_eq!(due_again[0].next_retry_at_ms, None);

    let key = [7u8; 32];
    mark_semantic_parse_job_succeeded(
        &conn,
        &key,
        "msg:1",
        "create",
        Some("todo:msg:1"),
        Some("Fix TV"),
        None,
        now_ms + 122,
    )
    .expect("succeeded");

    let due_after_success =
        list_due_semantic_parse_jobs(&conn, now_ms + 123, 10).expect("list due");
    assert!(due_after_success.is_empty());

    let jobs = list_semantic_parse_jobs_by_message_ids(&conn, &key, &["msg:1".to_string()])
        .expect("list by message ids");
    assert_eq!(jobs.len(), 1);
    assert_eq!(jobs[0].message_id, "msg:1");
    assert_eq!(jobs[0].status, "succeeded");
    assert_eq!(jobs[0].applied_action_kind.as_deref(), Some("create"));
    assert_eq!(jobs[0].applied_todo_id.as_deref(), Some("todo:msg:1"));
    assert_eq!(jobs[0].applied_todo_title.as_deref(), Some("Fix TV"));
    assert_eq!(jobs[0].applied_prev_todo_status, None);
    assert_eq!(jobs[0].undone_at_ms, None);

    mark_semantic_parse_job_undone(&conn, "msg:1", now_ms + 200).expect("undone");
    let jobs = list_semantic_parse_jobs_by_message_ids(&conn, &key, &["msg:1".to_string()])
        .expect("list by message ids");
    assert_eq!(jobs[0].undone_at_ms, Some(now_ms + 200));

    mark_semantic_parse_job_canceled(&conn, "msg:2", now_ms + 201).expect("cancel missing ok");
}
