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
    assert_eq!(due[0].attempt_id, 0);
    assert_eq!(due[0].attempts, 0);
    assert_eq!(due[0].next_retry_at_ms, None);

    let attempt_id = mark_semantic_parse_job_running(&conn, "msg:1", now_ms + 1).expect("running");
    assert_eq!(attempt_id, 1);
    let due_after_running = list_due_semantic_parse_jobs(&conn, now_ms + 1, 10).expect("list due");
    assert!(due_after_running.is_empty());

    let running_due_later = list_due_semantic_parse_jobs(&conn, now_ms + 60_000, 10)
        .expect("running jobs stay hidden from due query");
    assert!(running_due_later.is_empty());

    mark_semantic_parse_job_failed(&conn, "msg:1", 1, now_ms + 120, "timeout", now_ms + 1)
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

    let second_attempt_id =
        mark_semantic_parse_job_running(&conn, "msg:1", now_ms + 122).expect("running after retry");
    assert_eq!(second_attempt_id, 2);

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
    assert_eq!(jobs[0].attempt_id, 2);
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

#[test]
fn semantic_parse_jobs_running_recovery_requires_explicit_requeue_and_clears_retry_state() {
    let dir = tempdir().expect("tempdir");
    let conn = open(dir.path()).expect("open");

    let now_ms = 10_000i64;
    enqueue_semantic_parse_job(&conn, "msg:lease", now_ms).expect("enqueue");
    let first_attempt_id =
        mark_semantic_parse_job_running(&conn, "msg:lease", now_ms + 1).expect("running");
    assert_eq!(first_attempt_id, 1);
    mark_semantic_parse_job_failed(&conn, "msg:lease", 1, now_ms + 120, "timeout", now_ms + 1)
        .expect("failed");

    let second_attempt_id = mark_semantic_parse_job_running(&conn, "msg:lease", now_ms + 120)
        .expect("running after failure");
    assert_eq!(second_attempt_id, 2);

    let key = [3u8; 32];
    let jobs = list_semantic_parse_jobs_by_message_ids(&conn, &key, &["msg:lease".to_string()])
        .expect("list jobs");
    assert_eq!(jobs.len(), 1);
    assert_eq!(jobs[0].status, "running");
    assert_eq!(jobs[0].attempt_id, 2);
    assert_eq!(jobs[0].next_retry_at_ms, None);
    assert_eq!(jobs[0].last_error, None);

    let due_fresh = list_due_semantic_parse_jobs(&conn, now_ms + 121, 10).expect("fresh due");
    assert!(due_fresh.is_empty());
    assert!(mark_semantic_parse_job_running(&conn, "msg:lease", now_ms + 121).is_err());

    let stale_now = now_ms + 120 + 60_000;
    let due_stale = list_due_semantic_parse_jobs(&conn, stale_now, 10).expect("stale due");
    assert!(due_stale.is_empty());
    assert!(mark_semantic_parse_job_running(&conn, "msg:lease", stale_now).is_err());

    let recovered = requeue_running_semantic_parse_jobs(&conn, stale_now).expect("recover running");
    assert_eq!(recovered, 1);

    let due_after_recovery =
        list_due_semantic_parse_jobs(&conn, stale_now, 10).expect("due after recovery");
    assert_eq!(due_after_recovery.len(), 1);
    assert_eq!(due_after_recovery[0].message_id, "msg:lease");
    assert_eq!(due_after_recovery[0].status, "pending");
    assert_eq!(due_after_recovery[0].attempt_id, 2);

    let third_attempt_id = mark_semantic_parse_job_running(&conn, "msg:lease", stale_now + 1)
        .expect("reclaim recovered running");
    assert_eq!(third_attempt_id, 3);
}

#[test]
fn semantic_parse_jobs_retry_reopens_succeeded_job() {
    let dir = tempdir().expect("tempdir");
    let conn = open(dir.path()).expect("open");

    let now_ms = 2_000i64;
    enqueue_semantic_parse_job(&conn, "msg:2", now_ms).expect("enqueue");
    let _ = mark_semantic_parse_job_running(&conn, "msg:2", now_ms + 1).expect("running");

    let key = [9u8; 32];
    mark_semantic_parse_job_succeeded(
        &conn,
        &key,
        "msg:2",
        "followup",
        Some("todo:2"),
        Some("Follow up"),
        Some("open"),
        now_ms + 1,
    )
    .expect("succeeded");

    mark_semantic_parse_job_retry(&conn, "msg:2", now_ms + 2).expect("retry");

    let jobs = list_semantic_parse_jobs_by_message_ids(&conn, &key, &["msg:2".to_string()])
        .expect("list jobs");
    assert_eq!(jobs.len(), 1);
    assert_eq!(jobs[0].status, "pending");
    assert_eq!(jobs[0].applied_action_kind, None);
    assert_eq!(jobs[0].applied_todo_id, None);
    assert_eq!(jobs[0].applied_todo_title, None);
    assert_eq!(jobs[0].applied_prev_todo_status, None);
    assert_eq!(jobs[0].undone_at_ms, None);
}

#[test]
fn semantic_parse_jobs_enqueue_reopens_existing_job() {
    let dir = tempdir().expect("tempdir");
    let conn = open(dir.path()).expect("open");

    let now_ms = 3_000i64;
    enqueue_semantic_parse_job(&conn, "msg:3", now_ms).expect("enqueue");

    let key = [5u8; 32];
    let _ = mark_semantic_parse_job_running(&conn, "msg:3", now_ms + 1).expect("running");
    mark_semantic_parse_job_failed(&conn, "msg:3", 2, now_ms + 120, "timeout", now_ms + 1)
        .expect("failed");
    let _ = mark_semantic_parse_job_running(&conn, "msg:3", now_ms + 2).expect("running again");
    mark_semantic_parse_job_succeeded(
        &conn,
        &key,
        "msg:3",
        "create",
        Some("todo:3"),
        Some("Draft"),
        None,
        now_ms + 2,
    )
    .expect("succeeded");

    enqueue_semantic_parse_job(&conn, "msg:3", now_ms + 3).expect("enqueue again");

    let due = list_due_semantic_parse_jobs(&conn, now_ms + 3, 10).expect("list due");
    assert_eq!(due.len(), 1);
    assert_eq!(due[0].message_id, "msg:3");
    assert_eq!(due[0].status, "pending");
    assert_eq!(due[0].attempts, 0);
    assert_eq!(due[0].next_retry_at_ms, None);

    let jobs = list_semantic_parse_jobs_by_message_ids(&conn, &key, &["msg:3".to_string()])
        .expect("list jobs");
    assert_eq!(jobs.len(), 1);
    assert_eq!(jobs[0].status, "pending");
    assert_eq!(jobs[0].attempts, 0);
    assert_eq!(jobs[0].last_error, None);
    assert_eq!(jobs[0].applied_action_kind, None);
    assert_eq!(jobs[0].applied_todo_id, None);
    assert_eq!(jobs[0].applied_todo_title, None);
    assert_eq!(jobs[0].applied_prev_todo_status, None);
    assert_eq!(jobs[0].undone_at_ms, None);
}

#[test]
fn semantic_parse_jobs_canceled_job_ignores_late_success_and_failure() {
    let dir = tempdir().expect("tempdir");
    let conn = open(dir.path()).expect("open");

    let now_ms = 4_000i64;
    enqueue_semantic_parse_job(&conn, "msg:cancel", now_ms).expect("enqueue");
    let _ = mark_semantic_parse_job_running(&conn, "msg:cancel", now_ms + 1).expect("running");
    mark_semantic_parse_job_canceled(&conn, "msg:cancel", now_ms + 2).expect("canceled");

    let key = [6u8; 32];
    mark_semantic_parse_job_succeeded(
        &conn,
        &key,
        "msg:cancel",
        "create",
        Some("todo:cancel"),
        Some("Should not exist"),
        None,
        now_ms + 3,
    )
    .expect("late success ignored");
    mark_semantic_parse_job_failed(
        &conn,
        "msg:cancel",
        2,
        now_ms + 120,
        "late failure",
        now_ms + 4,
    )
    .expect("late failure ignored");

    let due = list_due_semantic_parse_jobs(&conn, now_ms + 200, 10).expect("list due");
    assert!(due.is_empty());

    let jobs = list_semantic_parse_jobs_by_message_ids(&conn, &key, &["msg:cancel".to_string()])
        .expect("list jobs");
    assert_eq!(jobs.len(), 1);
    assert_eq!(jobs[0].status, "canceled");
    assert_eq!(jobs[0].attempts, 0);
    assert_eq!(jobs[0].last_error, None);
    assert_eq!(jobs[0].applied_action_kind, None);
    assert_eq!(jobs[0].applied_todo_id, None);
    assert_eq!(jobs[0].applied_todo_title, None);
}

#[test]
fn semantic_parse_jobs_old_attempt_cannot_finalize_new_running_attempt() {
    let dir = tempdir().expect("tempdir");
    let conn = open(dir.path()).expect("open");

    let first_attempt_ms = 6_001i64;
    let second_attempt_ms = 6_010i64;
    enqueue_semantic_parse_job(&conn, "msg:retry", 6_000).expect("enqueue");
    let first_attempt_id =
        mark_semantic_parse_job_running(&conn, "msg:retry", first_attempt_ms).expect("running 1");
    mark_semantic_parse_job_retry(&conn, "msg:retry", 6_005).expect("retry");
    let second_attempt_id =
        mark_semantic_parse_job_running(&conn, "msg:retry", second_attempt_ms).expect("running 2");
    assert_eq!(first_attempt_id, 1);
    assert_eq!(second_attempt_id, 2);

    let key = [4u8; 32];
    mark_semantic_parse_job_succeeded(
        &conn,
        &key,
        "msg:retry",
        "create",
        Some("todo:old"),
        Some("Old attempt"),
        None,
        first_attempt_ms,
    )
    .expect("late old success ignored");
    mark_semantic_parse_job_failed(
        &conn,
        "msg:retry",
        1,
        6_120,
        "late old failure",
        first_attempt_ms,
    )
    .expect("late old failure ignored");

    let jobs = list_semantic_parse_jobs_by_message_ids(&conn, &key, &["msg:retry".to_string()])
        .expect("list jobs");
    assert_eq!(jobs.len(), 1);
    assert_eq!(jobs[0].status, "running");
    assert_eq!(jobs[0].attempt_id, 2);
    assert_eq!(jobs[0].applied_action_kind, None);
    assert_eq!(jobs[0].applied_todo_id, None);
    assert_eq!(jobs[0].last_error, None);

    mark_semantic_parse_job_succeeded(
        &conn,
        &key,
        "msg:retry",
        "create",
        Some("todo:new"),
        Some("Current attempt"),
        None,
        second_attempt_ms,
    )
    .expect("current success applied");

    let jobs = list_semantic_parse_jobs_by_message_ids(&conn, &key, &["msg:retry".to_string()])
        .expect("list jobs after success");
    assert_eq!(jobs.len(), 1);
    assert_eq!(jobs[0].status, "succeeded");
    assert_eq!(jobs[0].attempt_id, 2);
    assert_eq!(jobs[0].applied_todo_id.as_deref(), Some("todo:new"));
    assert_eq!(
        jobs[0].applied_todo_title.as_deref(),
        Some("Current attempt")
    );
}

#[test]
fn attachment_annotation_requeues_semantic_parse_for_linked_user_message() {
    let dir = tempdir().expect("tempdir");
    let app_dir = dir.path().to_path_buf();
    let conn = open(&app_dir).expect("open");

    let key = [3u8; 32];
    let conversation = get_or_create_loop_home_conversation(&conn, &key).expect("conversation");
    let long_content = "A".repeat(150);
    let message = insert_message(&conn, &key, &conversation.id, "user", &long_content)
        .expect("insert message");
    let attachment =
        insert_attachment(&conn, &key, &app_dir, b"img", "image/png").expect("insert attachment");
    link_attachment_to_message(&conn, &key, &message.id, &attachment.sha256).expect("link");

    let now_ms = 5_000i64;
    let due_before = list_due_semantic_parse_jobs(&conn, now_ms, 10).expect("list due before");
    assert!(due_before.is_empty());

    mark_attachment_annotation_ok(
        &conn,
        &key,
        &attachment.sha256,
        "und",
        "vision.v1",
        &serde_json::json!({
            "caption_long": "Client recap notes are visible in the attachment"
        }),
        now_ms,
    )
    .expect("mark ok");

    let due_after = list_due_semantic_parse_jobs(&conn, now_ms, 10).expect("list due after");
    assert_eq!(due_after.len(), 1);
    assert_eq!(due_after[0].message_id, message.id);
    assert_eq!(due_after[0].status, "pending");
    assert_eq!(due_after[0].attempt_id, 0);
    assert_eq!(due_after[0].attempts, 0);
}

#[test]
fn attachment_annotation_running_payload_does_not_requeue_semantic_parse() {
    let dir = tempdir().expect("tempdir");
    let app_dir = dir.path().to_path_buf();
    let conn = open(&app_dir).expect("open");

    let key = [4u8; 32];
    let conversation = get_or_create_loop_home_conversation(&conn, &key).expect("conversation");
    let message = insert_message(
        &conn,
        &key,
        &conversation.id,
        "user",
        "follow up from attachment",
    )
    .expect("insert message");
    let attachment =
        insert_attachment(&conn, &key, &app_dir, b"img", "image/png").expect("insert attachment");
    link_attachment_to_message(&conn, &key, &message.id, &attachment.sha256).expect("link");

    let now_ms = 6_000i64;
    mark_attachment_annotation_ok(
        &conn,
        &key,
        &attachment.sha256,
        "und",
        "vision.v1",
        &serde_json::json!({
            "ocr_auto_status": "running",
            "caption_long": "in-progress extraction output"
        }),
        now_ms,
    )
    .expect("mark ok");

    let due = list_due_semantic_parse_jobs(&conn, now_ms, 10).expect("list due");
    assert!(due.is_empty());
}

#[test]
fn semantic_parse_jobs_store_and_clear_tag_suggestion_metadata() {
    let dir = tempdir().expect("tempdir");
    let conn = open(dir.path()).expect("open");

    let now_ms = 7_000i64;
    enqueue_semantic_parse_job(&conn, "msg:meta", now_ms).expect("enqueue");
    let _ = mark_semantic_parse_job_running(&conn, "msg:meta", now_ms + 1).expect("running");

    let key = [8u8; 32];
    let suggested_tags = vec!["finance".to_string(), "work".to_string()];
    let applied_tag_ids = vec!["tag:finance".to_string()];
    mark_semantic_parse_job_succeeded_with_tag_metadata(
        &conn,
        &key,
        "msg:meta",
        "none",
        None,
        None,
        None,
        Some(&suggested_tags),
        Some(0.72),
        Some("pending"),
        Some(&applied_tag_ids),
        now_ms + 1,
    )
    .expect("succeeded");

    let jobs = list_semantic_parse_jobs_by_message_ids(&conn, &key, &["msg:meta".to_string()])
        .expect("list jobs");
    assert_eq!(jobs.len(), 1);
    assert_eq!(jobs[0].suggested_tags.as_ref(), Some(&suggested_tags));
    assert_eq!(jobs[0].suggested_tag_confidence, Some(0.72));
    assert_eq!(jobs[0].tag_suggestion_state.as_deref(), Some("pending"));
    assert_eq!(jobs[0].applied_tag_ids.as_ref(), Some(&applied_tag_ids));

    mark_semantic_parse_job_retry(&conn, "msg:meta", now_ms + 2).expect("retry");

    let jobs = list_semantic_parse_jobs_by_message_ids(&conn, &key, &["msg:meta".to_string()])
        .expect("list jobs after retry");
    assert_eq!(jobs.len(), 1);
    assert_eq!(jobs[0].suggested_tags, None);
    assert_eq!(jobs[0].suggested_tag_confidence, None);
    assert_eq!(jobs[0].tag_suggestion_state.as_deref(), Some("none"));
    assert_eq!(jobs[0].applied_tag_ids, None);
}

#[test]
fn semantic_parse_jobs_succeeded_job_allows_metadata_refresh() {
    let dir = tempdir().expect("tempdir");
    let conn = open(dir.path()).expect("open");

    let now_ms = 7_500i64;
    enqueue_semantic_parse_job(&conn, "msg:refresh-meta", now_ms).expect("enqueue");
    let _ =
        mark_semantic_parse_job_running(&conn, "msg:refresh-meta", now_ms + 1).expect("running");

    let key = [8u8; 32];
    mark_semantic_parse_job_succeeded_with_tag_metadata(
        &conn,
        &key,
        "msg:refresh-meta",
        "none",
        None,
        None,
        None,
        Some(&["work".to_string()]),
        Some(0.72),
        Some("pending"),
        None,
        now_ms + 1,
    )
    .expect("initial success");

    mark_semantic_parse_job_succeeded_with_tag_metadata(
        &conn,
        &key,
        "msg:refresh-meta",
        "none",
        None,
        None,
        None,
        Some(&["work".to_string()]),
        Some(0.72),
        Some("dismissed"),
        None,
        now_ms + 2,
    )
    .expect("refresh succeeded metadata");

    let jobs =
        list_semantic_parse_jobs_by_message_ids(&conn, &key, &["msg:refresh-meta".to_string()])
            .expect("list jobs");
    assert_eq!(jobs.len(), 1);
    assert_eq!(jobs[0].status, "succeeded");
    assert_eq!(jobs[0].tag_suggestion_state.as_deref(), Some("dismissed"));
    assert_eq!(jobs[0].suggested_tags, Some(vec!["work".to_string()]));
}

#[test]
fn semantic_parse_jobs_old_attempt_cannot_cancel_new_running_attempt() {
    let dir = tempdir().expect("tempdir");
    let conn = open(dir.path()).expect("open");

    enqueue_semantic_parse_job(&conn, "msg:cancel-race", 7_000).expect("enqueue");
    let first_attempt_id =
        mark_semantic_parse_job_running(&conn, "msg:cancel-race", 7_001).expect("running 1");
    mark_semantic_parse_job_retry(&conn, "msg:cancel-race", 7_005).expect("retry");
    let second_attempt_id =
        mark_semantic_parse_job_running(&conn, "msg:cancel-race", 7_010).expect("running 2");

    let stale_canceled = mark_semantic_parse_job_canceled_if_current_attempt(
        &conn,
        "msg:cancel-race",
        first_attempt_id,
        7_020,
    )
    .expect("stale cancel ignored");
    assert!(!stale_canceled);

    let key = [8u8; 32];
    let jobs =
        list_semantic_parse_jobs_by_message_ids(&conn, &key, &["msg:cancel-race".to_string()])
            .expect("list jobs");
    assert_eq!(jobs[0].status, "running");
    assert_eq!(jobs[0].attempt_id, second_attempt_id);

    let current_canceled = mark_semantic_parse_job_canceled_if_current_attempt(
        &conn,
        "msg:cancel-race",
        second_attempt_id,
        7_021,
    )
    .expect("current cancel applied");
    assert!(current_canceled);

    let jobs =
        list_semantic_parse_jobs_by_message_ids(&conn, &key, &["msg:cancel-race".to_string()])
            .expect("list jobs after cancel");
    assert_eq!(jobs[0].status, "canceled");
    assert_eq!(jobs[0].attempt_id, second_attempt_id);
}

#[test]
fn semantic_parse_jobs_guarded_mutations_require_current_attempt() {
    let dir = tempdir().expect("tempdir");
    let app_dir = dir.path().to_path_buf();
    let conn = open(&app_dir).expect("open");
    let key = [5u8; 32];

    let conversation = get_or_create_loop_home_conversation(&conn, &key).expect("conversation");
    let message =
        insert_message(&conn, &key, &conversation.id, "user", "Buy milk").expect("message");
    enqueue_semantic_parse_job(&conn, &message.id, 8_000).expect("enqueue");
    let first_attempt_id =
        mark_semantic_parse_job_running(&conn, &message.id, 8_001).expect("running 1");
    mark_semantic_parse_job_retry(&conn, &message.id, 8_005).expect("retry");
    let second_attempt_id =
        mark_semantic_parse_job_running(&conn, &message.id, 8_010).expect("running 2");

    let stale_tag_ids = apply_semantic_parse_tags_if_current_attempt(
        &conn,
        &key,
        &message.id,
        first_attempt_id,
        &["errand".to_string()],
    )
    .expect("stale tags ignored");
    assert!(stale_tag_ids.is_empty());
    assert!(list_message_tags(&conn, &key, &message.id)
        .expect("message tags")
        .is_empty());

    let stale_todo_id = upsert_semantic_parse_todo_create_if_current_attempt(
        &conn,
        &key,
        &message.id,
        first_attempt_id,
        "todo:stale",
        "Buy milk",
        None,
        "inbox",
        Some(0),
        Some(8_100),
        Some(8_050),
        Some("shopping"),
        None,
        8_020,
    )
    .expect("stale create ignored");
    assert_eq!(stale_todo_id, None);
    assert!(get_todo(&conn, &key, "todo:stale").is_err());

    let todo = upsert_todo(
        &conn,
        &key,
        "todo:followup",
        "Buy milk",
        None,
        "open",
        Some(&message.id),
        None,
        None,
        None,
        None,
        None,
    )
    .expect("seed todo");
    let stale_prev = set_semantic_parse_todo_status_if_current_attempt(
        &conn,
        &key,
        &message.id,
        first_attempt_id,
        &todo.id,
        "done",
    )
    .expect("stale followup ignored");
    assert_eq!(stale_prev, None);
    assert_eq!(
        get_todo(&conn, &key, &todo.id)
            .expect("todo after stale")
            .status,
        "open"
    );

    let current_tag_ids = apply_semantic_parse_tags_if_current_attempt(
        &conn,
        &key,
        &message.id,
        second_attempt_id,
        &["errand".to_string()],
    )
    .expect("current tags applied");
    assert_eq!(current_tag_ids.len(), 1);

    let current_todo_id = upsert_semantic_parse_todo_create_if_current_attempt(
        &conn,
        &key,
        &message.id,
        second_attempt_id,
        "todo:current",
        "Buy milk today",
        None,
        "inbox",
        Some(0),
        Some(8_100),
        Some(8_050),
        Some("shopping"),
        Some(r#"{"freq":"weekly","interval":1}"#),
        8_030,
    )
    .expect("current create applied");
    assert_eq!(current_todo_id.as_deref(), Some("todo:current"));
    assert!(get_todo(&conn, &key, "todo:current").is_ok());
    assert_eq!(
        get_todo_recurrence_rule_json(&conn, "todo:current").expect("recurrence"),
        Some(r#"{"freq":"weekly","interval":1}"#.to_string())
    );

    let checklist_created = upsert_semantic_parse_checklist_suggestions_if_current_attempt(
        &conn,
        &key,
        &message.id,
        second_attempt_id,
        "todo:current",
        &["Check pantry".to_string()],
        "byok",
        Some("semantic_parse_auto:test"),
    )
    .expect("checklist created");
    assert!(checklist_created);
    assert_eq!(
        list_todo_checklist_suggestions(&conn, &key, "todo:current")
            .expect("checklist suggestions")
            .len(),
        1
    );

    let prev_status = set_semantic_parse_todo_status_if_current_attempt(
        &conn,
        &key,
        &message.id,
        second_attempt_id,
        &todo.id,
        "done",
    )
    .expect("current followup applied");
    assert_eq!(prev_status.as_deref(), Some("open"));
    assert_eq!(
        get_todo(&conn, &key, &todo.id)
            .expect("todo after followup")
            .status,
        "done"
    );
}

#[test]
fn semantic_parse_jobs_guarded_finalize_returns_applied_flag() {
    let dir = tempdir().expect("tempdir");
    let conn = open(dir.path()).expect("open");
    let key = [4u8; 32];

    enqueue_semantic_parse_job(&conn, "msg:finalize-flag", 9_000).expect("enqueue");
    let first_attempt_id =
        mark_semantic_parse_job_running(&conn, "msg:finalize-flag", 9_001).expect("running 1");
    mark_semantic_parse_job_retry(&conn, "msg:finalize-flag", 9_005).expect("retry");
    let second_attempt_id =
        mark_semantic_parse_job_running(&conn, "msg:finalize-flag", 9_010).expect("running 2");

    let stale_succeeded = mark_semantic_parse_job_succeeded_if_current_attempt(
        &conn,
        &key,
        "msg:finalize-flag",
        first_attempt_id,
        "none",
        None,
        None,
        None,
        9_020,
    )
    .expect("stale finalize ignored");
    assert!(!stale_succeeded);

    let stale_failed = mark_semantic_parse_job_failed_if_current_attempt(
        &conn,
        "msg:finalize-flag",
        first_attempt_id,
        1,
        9_120,
        "timeout",
        9_021,
    )
    .expect("stale failure ignored");
    assert!(!stale_failed);

    let current_succeeded = mark_semantic_parse_job_succeeded_if_current_attempt(
        &conn,
        &key,
        "msg:finalize-flag",
        second_attempt_id,
        "none",
        None,
        None,
        None,
        9_022,
    )
    .expect("current finalize applied");
    assert!(current_succeeded);
}

#[test]
fn upsert_todo_with_auto_followup_job_skips_execution_task_auto_enqueue() {
    let dir = tempdir().expect("tempdir");
    let conn = open(dir.path()).expect("open");
    let key = [2u8; 32];

    let todo = upsert_todo_with_auto_followup_job(
        &conn,
        &key,
        "todo:execution",
        "修复登录页闪退",
        None,
        "open",
        None,
        None,
        None,
        None,
        None,
        10_000,
    )
    .expect("upsert todo");

    assert_eq!(todo.id, "todo:execution");
    assert!(find_todo_followup_generation_job(&conn, &todo.id)
        .expect("find followup job")
        .is_none());
}

#[test]
fn semantic_parse_create_skips_execution_task_auto_enqueue() {
    let dir = tempdir().expect("tempdir");
    let conn = open(dir.path()).expect("open");
    let key = [9u8; 32];

    let conversation = get_or_create_loop_home_conversation(&conn, &key).expect("conversation");
    let message = insert_message(&conn, &key, &conversation.id, "user", "修复登录页闪退")
        .expect("insert message");
    enqueue_semantic_parse_job(&conn, &message.id, 11_000).expect("enqueue");
    let attempt_id = mark_semantic_parse_job_running(&conn, &message.id, 11_001).expect("running");

    let created = complete_semantic_parse_create_if_current_attempt(
        &conn,
        &key,
        &message.id,
        attempt_id,
        "todo:execution-semantic",
        "修复登录页闪退",
        None,
        "inbox",
        Some(0),
        Some(11_100),
        Some(11_050),
        None,
        None,
        &[],
        "byok",
        None,
        None,
        None,
        None,
        11_002,
    )
    .expect("complete create");
    assert!(created);

    let todo = get_todo(&conn, &key, "todo:execution-semantic").expect("get todo");
    assert_eq!(todo.title, "修复登录页闪退");
    assert!(find_todo_followup_generation_job(&conn, &todo.id)
        .expect("find followup job")
        .is_none());
}

#[test]
fn semantic_parse_create_with_unknown_hint_falls_back_to_title_classification() {
    let dir = tempdir().expect("tempdir");
    let conn = open(dir.path()).expect("open");
    let key = [6u8; 32];

    let conversation = get_or_create_loop_home_conversation(&conn, &key).expect("conversation");
    let message = insert_message(
        &conn,
        &key,
        &conversation.id,
        "user",
        "调研一下当前主流的 llm 模型",
    )
    .expect("insert message");
    enqueue_semantic_parse_job(&conn, &message.id, 15_000).expect("enqueue");
    let attempt_id = mark_semantic_parse_job_running(&conn, &message.id, 15_001).expect("running");

    let created = complete_semantic_parse_create_if_current_attempt(
        &conn,
        &key,
        &message.id,
        attempt_id,
        "todo:semantic-unknown-hint",
        "调研一下当前主流的 llm 模型",
        None,
        "inbox",
        Some(0),
        Some(15_100),
        Some(15_050),
        Some("unknown"),
        None,
        &[],
        "byok",
        None,
        None,
        None,
        None,
        15_002,
    )
    .expect("complete create");
    assert!(created);

    let job = find_todo_followup_generation_job(&conn, "todo:semantic-unknown-hint")
        .expect("find followup job")
        .expect("job");
    assert_eq!(job.task_type_hint.as_deref(), Some("unknown"));
}

#[test]
fn semantic_parse_followup_can_apply_due_without_status_change_atomically() {
    let dir = tempdir().expect("tempdir");
    let conn = open(dir.path()).expect("open");
    let key = [7u8; 32];

    let conversation = get_or_create_loop_home_conversation(&conn, &key).expect("conversation");
    let message = insert_message(
        &conn,
        &key,
        &conversation.id,
        "user",
        "把这个改到节后第一个工作日",
    )
    .expect("insert message");
    enqueue_semantic_parse_job(&conn, &message.id, 16_000).expect("enqueue");
    let attempt_id = mark_semantic_parse_job_running(&conn, &message.id, 16_001).expect("running");

    let seeded = upsert_todo(
        &conn,
        &key,
        "todo:followup-due-only",
        "报销",
        Some(16_200),
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
        Some(16_500),
        None,
        None,
        None,
        16_010,
    )
    .expect("followup applied");
    assert!(applied);

    let updated = get_todo(&conn, &key, &seeded.id).expect("updated todo");
    assert_eq!(updated.status, "open");
    assert_eq!(updated.due_at_ms, Some(16_500));

    let jobs =
        list_semantic_parse_jobs_by_message_ids(&conn, &key, &[message.id.clone()]).expect("jobs");
    assert_eq!(jobs.len(), 1);
    assert_eq!(jobs[0].status, "succeeded");
    assert_eq!(jobs[0].applied_prev_todo_status.as_deref(), None);
    assert_eq!(
        jobs[0].applied_todo_id.as_deref(),
        Some("todo:followup-due-only")
    );
    let (stored_prev_due_at_ms, stored_due_changed): (Option<i64>, i64) = conn
        .query_row(
            r#"
SELECT applied_prev_todo_due_at_ms,
       applied_due_changed
FROM semantic_parse_jobs
WHERE message_id = ?1
"#,
            params![&message.id],
            |row| Ok((row.get(0)?, row.get(1)?)),
        )
        .expect("load stored due undo metadata");
    assert_eq!(stored_prev_due_at_ms, Some(16_200));
    assert_eq!(stored_due_changed, 1);
}

#[test]
fn upsert_todo_with_unknown_hint_falls_back_to_title_classification() {
    let dir = tempdir().expect("tempdir");
    let conn = open(dir.path()).expect("open");
    let key = [3u8; 32];

    let todo = upsert_todo_with_auto_followup_job(
        &conn,
        &key,
        "todo:unknown-hint",
        "调研一下当前主流的 llm 模型",
        None,
        "open",
        None,
        None,
        None,
        None,
        Some("unknown"),
        12_000,
    )
    .expect("upsert todo");

    let job = find_todo_followup_generation_job(&conn, &todo.id)
        .expect("find followup job")
        .expect("job");
    assert_eq!(job.task_type_hint.as_deref(), Some("unknown"));
}

#[test]
fn upsert_todo_with_explicit_execution_hint_suppresses_auto_enqueue() {
    let dir = tempdir().expect("tempdir");
    let conn = open(dir.path()).expect("open");
    let key = [4u8; 32];

    let todo = upsert_todo_with_auto_followup_job(
        &conn,
        &key,
        "todo:explicit-execution",
        "调研一下当前主流的 llm 模型",
        None,
        "open",
        None,
        None,
        None,
        None,
        Some("execution"),
        13_000,
    )
    .expect("upsert todo");

    assert!(find_todo_followup_generation_job(&conn, &todo.id)
        .expect("find followup job")
        .is_none());
}

#[test]
fn upsert_todo_with_explicit_research_hint_overrides_execution_title() {
    let dir = tempdir().expect("tempdir");
    let conn = open(dir.path()).expect("open");
    let key = [5u8; 32];

    let todo = upsert_todo_with_auto_followup_job(
        &conn,
        &key,
        "todo:explicit-research",
        "修复登录页闪退",
        None,
        "open",
        None,
        None,
        None,
        None,
        Some("research"),
        14_000,
    )
    .expect("upsert todo");

    let job = find_todo_followup_generation_job(&conn, &todo.id)
        .expect("find followup job")
        .expect("job");
    assert_eq!(job.task_type_hint.as_deref(), Some("research"));
}
