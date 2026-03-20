use secondloop_rust::api::core;
use secondloop_rust::auth;
use secondloop_rust::crypto;
use secondloop_rust::crypto::KdfParams;
use secondloop_rust::db;

fn setup() -> (tempfile::TempDir, [u8; 32], rusqlite::Connection) {
    let temp_dir = tempfile::tempdir().expect("tempdir");
    let app_dir = temp_dir.path().join("secondloop");
    let key = auth::init_master_password(&app_dir, "pw", KdfParams::for_test())
        .expect("init master password");
    let conn = db::open(&app_dir).expect("open db");
    (temp_dir, key, conn)
}

#[test]
fn information_followup_suggestions_can_be_generated_applied_and_dismissed() {
    let (_temp_dir, key, conn) = setup();

    db::upsert_todo(
        &conn,
        &key,
        "todo_1",
        "Research LLM models",
        None,
        "open",
        None,
        None,
        None,
        None,
    )
    .expect("upsert todo");

    let generated = db::upsert_generated_todo_followup_suggestions(
        &conn,
        &key,
        "todo_1",
        &[db::TodoFollowupSuggestionDraftInput {
            content: "## Summary\nClaude / GPT / Gemini are still the main hosted options."
                .to_string(),
            generation_mode: "model_knowledge".to_string(),
            citations_json: None,
        }],
        "cloud",
        Some("gen_1"),
    )
    .expect("generate followup suggestions");

    assert_eq!(generated.len(), 1);
    assert_eq!(generated[0].state, "pending");
    assert_eq!(generated[0].generation_mode, "model_knowledge");

    let applied =
        db::apply_todo_followup_suggestions(&conn, &key, "todo_1", &[generated[0].id.clone()])
            .expect("apply followup suggestion");

    assert_eq!(applied.len(), 1);
    assert_eq!(applied[0].activity_type, "followup_information");
    assert!(applied[0]
        .content
        .as_deref()
        .unwrap_or_default()
        .contains("Claude / GPT / Gemini"));

    let suggestions = db::list_todo_followup_suggestions(&conn, &key, "todo_1")
        .expect("list followup suggestions");
    assert_eq!(suggestions.len(), 1);
    assert_eq!(suggestions[0].state, "applied");
    assert!(suggestions[0].applied_activity_id.is_some());

    let regenerated = db::upsert_generated_todo_followup_suggestions(
        &conn,
        &key,
        "todo_1",
        &[db::TodoFollowupSuggestionDraftInput {
            content: "## Summary\n机场官网显示 MU5101 到达 T1。".to_string(),
            generation_mode: "web_search".to_string(),
            citations_json: Some(
                r#"[{\"title\":\"Airport\",\"url\":\"https://airport.example\",\"domain\":\"airport.example\"}]"#
                    .to_string(),
            ),
        }],
        "cloud",
        Some("gen_2"),
    )
    .expect("regenerate followup suggestions");
    assert_eq!(regenerated.len(), 1);

    db::dismiss_todo_followup_suggestions(&conn, &key, "todo_1", &[regenerated[0].id.clone()])
        .expect("dismiss followup suggestion");

    let all = db::list_todo_followup_suggestions(&conn, &key, "todo_1")
        .expect("list all followup suggestions");
    assert_eq!(all.len(), 2);
    assert!(all.iter().any(|item| item.state == "applied"));
    assert!(all.iter().any(|item| item.state == "dismissed"));
}

#[test]
fn todo_upsert_keeps_updated_at_ms_monotonic() {
    let (_temp_dir, key, conn) = setup();

    db::upsert_todo(
        &conn,
        &key,
        "todo_1",
        "Research LLM models",
        None,
        "open",
        None,
        None,
        None,
        None,
    )
    .expect("upsert todo");

    conn.execute(
        "UPDATE todos SET updated_at_ms = 32_503_680_000_000 WHERE id = ?1",
        ["todo_1"],
    )
    .expect("force newer updated_at_ms");

    let todo = db::upsert_todo(
        &conn,
        &key,
        "todo_1",
        "Research LLM models (updated)",
        None,
        "open",
        None,
        None,
        None,
        None,
    )
    .expect("upsert todo again");

    assert!(todo.updated_at_ms >= 32_503_680_000_000);
}

#[test]
fn todo_is_updated_when_applying_followup_information() {
    let (_temp_dir, key, conn) = setup();

    let initial_todo = db::upsert_todo(
        &conn,
        &key,
        "todo_1",
        "Research LLM models",
        None,
        "open",
        None,
        None,
        None,
        None,
    )
    .expect("upsert todo");

    let generated = db::upsert_generated_todo_followup_suggestions(
        &conn,
        &key,
        "todo_1",
        &[db::TodoFollowupSuggestionDraftInput {
            content: "## Summary\nClaude / GPT / Gemini are still the main hosted options."
                .to_string(),
            generation_mode: "model_knowledge".to_string(),
            citations_json: None,
        }],
        "cloud",
        Some("gen_1"),
    )
    .expect("generate followup suggestions");

    db::apply_todo_followup_suggestions(&conn, &key, "todo_1", &[generated[0].id.clone()])
        .expect("apply followup suggestion");

    let updated_todo = db::get_todo(&conn, &key, "todo_1").expect("get updated todo");
    assert!(updated_todo.updated_at_ms > initial_todo.updated_at_ms);
}

#[test]
fn todo_followup_generation_jobs_support_enqueue_claim_retry_and_succeed() {
    let (_temp_dir, key, conn) = setup();

    db::upsert_todo(
        &conn,
        &key,
        "todo_1",
        "去浦东机场接 MU5101",
        None,
        "open",
        None,
        None,
        None,
        None,
    )
    .expect("upsert todo");

    db::enqueue_todo_followup_generation_job(&conn, "todo_1", "auto_create", None, 100)
        .expect("enqueue job");

    let due = db::list_due_todo_followup_generation_jobs(&conn, 100, 10).expect("list due jobs");
    assert_eq!(due.len(), 1);
    assert_eq!(due[0].todo_id, "todo_1");
    assert_eq!(due[0].status, "pending");

    db::mark_todo_followup_generation_job_running(&conn, "todo_1", 120).expect("mark running");
    db::mark_todo_followup_generation_job_failed(&conn, "todo_1", 1, 240, "temporary error", 130)
        .expect("mark failed");

    let retried = db::list_due_todo_followup_generation_jobs(&conn, 239, 10)
        .expect("list before retry window");
    assert!(retried.is_empty());

    let retried =
        db::list_due_todo_followup_generation_jobs(&conn, 240, 10).expect("list retried jobs");
    assert_eq!(retried.len(), 1);

    db::mark_todo_followup_generation_job_running(&conn, "todo_1", 250)
        .expect("mark running again");
    db::mark_todo_followup_generation_job_succeeded(&conn, "todo_1", 260).expect("mark succeeded");

    let final_jobs =
        db::list_due_todo_followup_generation_jobs(&conn, 1000, 10).expect("list final jobs");
    assert!(final_jobs.is_empty());
}

#[test]
fn running_jobs_are_not_released_until_their_lease_expires() {
    let (_temp_dir, key, conn) = setup();

    db::upsert_todo(
        &conn,
        &key,
        "todo_1",
        "去浦东机场接 MU5101",
        None,
        "open",
        None,
        None,
        None,
        None,
    )
    .expect("upsert todo");

    db::enqueue_todo_followup_generation_job(&conn, "todo_1", "auto_create", None, 100)
        .expect("enqueue job");
    db::mark_todo_followup_generation_job_running(&conn, "todo_1", 120).expect("mark running");

    let before_expiry = db::list_due_todo_followup_generation_jobs(
        &conn,
        120 + db::TODO_FOLLOWUP_GENERATION_RUNNING_LEASE_MS - 1,
        10,
    )
    .expect("list jobs before lease expiry");
    assert!(before_expiry.is_empty());

    let after_expiry = db::list_due_todo_followup_generation_jobs(
        &conn,
        120 + db::TODO_FOLLOWUP_GENERATION_RUNNING_LEASE_MS,
        10,
    )
    .expect("list jobs after lease expiry");
    assert_eq!(after_expiry.len(), 1);
    assert_eq!(after_expiry[0].todo_id, "todo_1");
    assert_eq!(after_expiry[0].status, "running");
}

#[test]
fn manual_regenerate_jobs_are_prioritized_ahead_of_auto_jobs() {
    let (_temp_dir, key, conn) = setup();

    for (todo_id, title) in [
        ("todo_auto", "调研一下当前主流的 llm 模型"),
        ("todo_manual", "比较 Cursor、Windsurf 和 Copilot 的能力"),
    ] {
        db::upsert_todo(
            &conn, &key, todo_id, title, None, "open", None, None, None, None,
        )
        .expect("upsert todo");
    }

    db::enqueue_todo_followup_generation_job(&conn, "todo_auto", "auto_create", None, 100)
        .expect("enqueue auto job");
    db::enqueue_todo_followup_generation_job(&conn, "todo_manual", "manual_regenerate", None, 200)
        .expect("enqueue manual job");

    let due = db::list_due_todo_followup_generation_jobs(&conn, 200, 1).expect("list due jobs");
    assert_eq!(due.len(), 1);
    assert_eq!(due[0].todo_id, "todo_manual");
    assert_eq!(due[0].trigger_kind, "manual_regenerate");
}

#[test]
fn manual_regenerate_jobs_keep_fifo_order_within_manual_queue() {
    let (_temp_dir, key, conn) = setup();

    for (todo_id, title) in [
        ("todo_manual_old", "比较 Cursor、Windsurf 和 Copilot 的能力"),
        ("todo_manual_new", "调研一下当前主流的 llm 模型"),
    ] {
        db::upsert_todo(
            &conn, &key, todo_id, title, None, "open", None, None, None, None,
        )
        .expect("upsert todo");
    }

    db::enqueue_todo_followup_generation_job(
        &conn,
        "todo_manual_old",
        "manual_regenerate",
        None,
        100,
    )
    .expect("enqueue older manual job");
    db::enqueue_todo_followup_generation_job(
        &conn,
        "todo_manual_new",
        "manual_regenerate",
        None,
        200,
    )
    .expect("enqueue newer manual job");

    let due = db::list_due_todo_followup_generation_jobs(&conn, 200, 1).expect("list due jobs");
    assert_eq!(due.len(), 1);
    assert_eq!(due[0].todo_id, "todo_manual_old");
}

#[test]
fn enqueue_followup_job_rejects_invalid_trigger_kind() {
    let (_temp_dir, key, conn) = setup();

    db::upsert_todo(
        &conn,
        &key,
        "todo_1",
        "Research LLM models",
        None,
        "open",
        None,
        None,
        None,
        None,
    )
    .expect("upsert todo");

    let err = db::enqueue_todo_followup_generation_job(&conn, "todo_1", "bogus", None, 100)
        .expect_err("invalid trigger kind should fail");
    assert!(err.to_string().contains("invalid trigger_kind"));
}

#[test]
fn reenqueue_without_new_hint_clears_previous_task_type_hint() {
    let (_temp_dir, key, conn) = setup();

    db::upsert_todo(
        &conn,
        &key,
        "todo_1",
        "调研一下当前主流的 llm 模型",
        None,
        "open",
        None,
        None,
        None,
        None,
    )
    .expect("upsert todo");

    db::enqueue_todo_followup_generation_job(
        &conn,
        "todo_1",
        "auto_create",
        Some("execution"),
        100,
    )
    .expect("enqueue first job");
    db::enqueue_todo_followup_generation_job(&conn, "todo_1", "manual_regenerate", None, 200)
        .expect("enqueue second job");

    let due = db::list_due_todo_followup_generation_jobs(&conn, 200, 10).expect("list due jobs");
    assert_eq!(due.len(), 1);
    assert_eq!(due[0].todo_id, "todo_1");
    assert_eq!(due[0].trigger_kind, "manual_regenerate");
    assert!(due[0].include_manual_followups);
    assert!(due[0].task_type_hint.is_none());
}

#[test]
fn later_auto_create_does_not_overwrite_existing_manual_regenerate_job() {
    let (_temp_dir, key, conn) = setup();

    db::upsert_todo(
        &conn,
        &key,
        "todo_1",
        "调研一下当前主流的 llm 模型",
        None,
        "open",
        None,
        None,
        None,
        None,
    )
    .expect("upsert todo");

    db::enqueue_todo_followup_generation_job(&conn, "todo_1", "manual_regenerate", None, 100)
        .expect("enqueue manual job");
    db::enqueue_todo_followup_generation_job(&conn, "todo_1", "auto_create", None, 200)
        .expect("enqueue later auto job");

    let due = db::list_due_todo_followup_generation_jobs(&conn, 200, 10).expect("list due jobs");
    assert_eq!(due.len(), 1);
    assert_eq!(due[0].todo_id, "todo_1");
    assert_eq!(due[0].trigger_kind, "manual_regenerate");
    assert!(due[0].include_manual_followups);
}

#[test]
fn auto_create_reenqueue_without_hint_preserves_existing_task_type_hint() {
    let (_temp_dir, key, conn) = setup();

    db::upsert_todo(
        &conn,
        &key,
        "todo_1",
        "调研一下当前主流的 llm 模型",
        None,
        "open",
        None,
        None,
        None,
        None,
    )
    .expect("upsert todo");

    db::enqueue_todo_followup_generation_job(&conn, "todo_1", "auto_create", Some("research"), 100)
        .expect("enqueue hinted job");
    db::enqueue_todo_followup_generation_job(&conn, "todo_1", "auto_create", None, 200)
        .expect("enqueue fallback job");

    let due = db::list_due_todo_followup_generation_jobs(&conn, 200, 10).expect("list due jobs");
    assert_eq!(due.len(), 1);
    assert_eq!(due[0].todo_id, "todo_1");
    assert_eq!(due[0].trigger_kind, "auto_create");
    assert_eq!(due[0].task_type_hint.as_deref(), Some("research"));
}

#[test]
fn historical_followup_suggestions_do_not_block_same_content_regeneration() {
    let (_temp_dir, key, conn) = setup();

    db::upsert_todo(
        &conn,
        &key,
        "todo_1",
        "Research LLM models",
        None,
        "open",
        None,
        None,
        None,
        None,
    )
    .expect("upsert todo");

    let first = db::upsert_generated_todo_followup_suggestions(
        &conn,
        &key,
        "todo_1",
        &[db::TodoFollowupSuggestionDraftInput {
            content: "Same content".to_string(),
            generation_mode: "model_knowledge".to_string(),
            citations_json: None,
        }],
        "cloud",
        Some("gen_1"),
    )
    .expect("generate first suggestion");
    assert_eq!(first.len(), 1);

    db::dismiss_todo_followup_suggestions(&conn, &key, "todo_1", &[first[0].id.clone()])
        .expect("dismiss first suggestion");

    let second = db::upsert_generated_todo_followup_suggestions(
        &conn,
        &key,
        "todo_1",
        &[db::TodoFollowupSuggestionDraftInput {
            content: "Same content".to_string(),
            generation_mode: "model_knowledge".to_string(),
            citations_json: None,
        }],
        "cloud",
        Some("gen_2"),
    )
    .expect("regenerate after dismiss");
    assert_eq!(second.len(), 1);

    let applied =
        db::apply_todo_followup_suggestions(&conn, &key, "todo_1", &[second[0].id.clone()])
            .expect("apply second suggestion");
    assert_eq!(applied.len(), 1);

    let third = db::upsert_generated_todo_followup_suggestions(
        &conn,
        &key,
        "todo_1",
        &[db::TodoFollowupSuggestionDraftInput {
            content: "Same content".to_string(),
            generation_mode: "model_knowledge".to_string(),
            citations_json: None,
        }],
        "cloud",
        Some("gen_3"),
    )
    .expect("regenerate after apply");
    assert_eq!(third.len(), 1);
}

#[test]
fn dismiss_all_followup_suggestions_dismisses_every_pending_item() {
    let (_temp_dir, key, conn) = setup();

    db::upsert_todo(
        &conn,
        &key,
        "todo_1",
        "Research LLM models",
        None,
        "open",
        None,
        None,
        None,
        None,
    )
    .expect("upsert todo");

    let generated = db::upsert_generated_todo_followup_suggestions(
        &conn,
        &key,
        "todo_1",
        &[
            db::TodoFollowupSuggestionDraftInput {
                content: "Suggestion A".to_string(),
                generation_mode: "model_knowledge".to_string(),
                citations_json: None,
            },
            db::TodoFollowupSuggestionDraftInput {
                content: "Suggestion B".to_string(),
                generation_mode: "model_knowledge".to_string(),
                citations_json: None,
            },
        ],
        "cloud",
        Some("gen_all"),
    )
    .expect("generate followup suggestions");

    assert_eq!(generated.len(), 2);

    db::dismiss_all_todo_followup_suggestions(&conn, &key, "todo_1")
        .expect("dismiss all followup suggestions");

    let all = db::list_todo_followup_suggestions(&conn, &key, "todo_1")
        .expect("list followup suggestions");
    assert_eq!(all.len(), 2);
    assert!(all.iter().all(|item| item.state == "dismissed"));
}

#[test]
fn regenerate_same_content_refreshes_pending_metadata() {
    let (_temp_dir, key, conn) = setup();

    db::upsert_todo(
        &conn,
        &key,
        "todo_1",
        "Research LLM models",
        None,
        "open",
        None,
        None,
        None,
        None,
    )
    .expect("upsert todo");

    let first = db::upsert_generated_todo_followup_suggestions(
        &conn,
        &key,
        "todo_1",
        &[db::TodoFollowupSuggestionDraftInput {
            content: "Same content".to_string(),
            generation_mode: "model_knowledge".to_string(),
            citations_json: None,
        }],
        "cloud",
        Some("gen_1"),
    )
    .expect("insert initial suggestion");
    assert_eq!(first.len(), 1);

    let refreshed = db::upsert_generated_todo_followup_suggestions(
        &conn,
        &key,
        "todo_1",
        &[db::TodoFollowupSuggestionDraftInput {
            content: "Same content".to_string(),
            generation_mode: "web_search".to_string(),
            citations_json: Some(
                r#"[{\"title\":\"Airport\",\"url\":\"https://airport.example\",\"domain\":\"airport.example\"}]"#
                    .to_string(),
            ),
        }],
        "cloud",
        Some("gen_2"),
    )
    .expect("refresh pending suggestion metadata");
    assert_eq!(refreshed.len(), 1);

    let all = db::list_todo_followup_suggestions(&conn, &key, "todo_1")
        .expect("list refreshed suggestions");
    assert_eq!(all.len(), 1);
    assert_eq!(all[0].id, first[0].id);
    assert_eq!(all[0].generation_mode, "web_search");
    assert_eq!(all[0].generation_key.as_deref(), Some("gen_2"));
    assert_eq!(
        all[0].citations_json.as_deref(),
        Some(
            r#"[{\"title\":\"Airport\",\"url\":\"https://airport.example\",\"domain\":\"airport.example\"}]"#
        ),
    );
}

#[test]
fn duplicate_pending_followup_is_collapsed_during_regeneration() {
    let (_temp_dir, key, conn) = setup();

    db::upsert_todo(
        &conn,
        &key,
        "todo_1",
        "Research LLM models",
        None,
        "open",
        None,
        None,
        None,
        None,
    )
    .expect("upsert todo");

    let first = db::upsert_generated_todo_followup_suggestions(
        &conn,
        &key,
        "todo_1",
        &[db::TodoFollowupSuggestionDraftInput {
            content: "Same content".to_string(),
            generation_mode: "model_knowledge".to_string(),
            citations_json: None,
        }],
        "cloud",
        Some("gen_1"),
    )
    .expect("insert initial suggestion");

    let duplicate_id = "dup_pending";
    let duplicate_created_at_ms = first[0].created_at_ms + 1;
    let duplicate_updated_at_ms = first[0].updated_at_ms + 1;
    let duplicate_blob = crypto::encrypt_bytes(
        &key,
        b"Same content",
        format!("todo_followup_suggestion.content:{duplicate_id}").as_bytes(),
    )
    .expect("encrypt duplicate pending suggestion");

    conn.execute(
        r#"
INSERT INTO todo_followup_suggestions(
  id, todo_id, content, state, source, generation_mode, generation_key, citations_json, created_at_ms, updated_at_ms, dismissed_at_ms, applied_activity_id
)
VALUES (?1, ?2, ?3, 'pending', 'cloud', 'model_knowledge', 'gen_dup', NULL, ?4, ?5, NULL, NULL)
"#,
        rusqlite::params![
            duplicate_id,
            "todo_1",
            duplicate_blob,
            duplicate_created_at_ms,
            duplicate_updated_at_ms,
        ],
    )
    .expect("seed duplicate pending suggestion");

    let duplicated = db::list_todo_followup_suggestions(&conn, &key, "todo_1")
        .expect("list duplicated suggestions");
    assert_eq!(duplicated.len(), 2);
    assert!(duplicated.iter().all(|item| item.state == "pending"));

    let refreshed = db::upsert_generated_todo_followup_suggestions(
        &conn,
        &key,
        "todo_1",
        &[db::TodoFollowupSuggestionDraftInput {
            content: "Same content".to_string(),
            generation_mode: "web_search".to_string(),
            citations_json: Some(
                r#"[{\"title\":\"Airport\",\"url\":\"https://airport.example\",\"domain\":\"airport.example\"}]"#
                    .to_string(),
            ),
        }],
        "cloud",
        Some("gen_2"),
    )
    .expect("refresh pending suggestion metadata");
    assert_eq!(refreshed.len(), 1);

    let all = db::list_todo_followup_suggestions(&conn, &key, "todo_1")
        .expect("list refreshed suggestions");
    assert_eq!(all.len(), 2);

    let pending = all
        .iter()
        .filter(|item| item.state == "pending")
        .collect::<Vec<_>>();
    assert_eq!(pending.len(), 1);
    assert_eq!(pending[0].id, first[0].id);

    let dismissed = all
        .iter()
        .filter(|item| item.state == "dismissed")
        .collect::<Vec<_>>();
    assert_eq!(dismissed.len(), 1);
    assert_eq!(dismissed[0].id, duplicate_id);
}

#[test]
fn followup_job_api_requires_a_matching_todo_key() {
    let (temp_dir, key, conn) = setup();
    let app_dir = temp_dir
        .path()
        .join("secondloop")
        .to_string_lossy()
        .into_owned();

    db::upsert_todo(
        &conn,
        &key,
        "todo_1",
        "Research LLM models",
        None,
        "open",
        None,
        None,
        None,
        None,
    )
    .expect("upsert todo");
    db::enqueue_todo_followup_generation_job(&conn, "todo_1", "auto_create", None, 100)
        .expect("enqueue job");

    let wrong_key = vec![9u8; 32];

    assert!(core::db_get_todo_followup_generation_job(
        app_dir.clone(),
        wrong_key.clone(),
        "todo_1".to_string(),
    )
    .is_err());

    assert!(core::db_list_due_todo_followup_generation_jobs(
        app_dir.clone(),
        wrong_key.clone(),
        100,
        10,
    )
    .is_err());

    assert!(core::db_mark_todo_followup_generation_job_running(
        app_dir.clone(),
        wrong_key.clone(),
        "todo_1".to_string(),
        120,
    )
    .is_err());

    assert!(core::db_enqueue_todo_followup_generation_job(
        app_dir,
        wrong_key,
        "todo_1".to_string(),
        "manual_regenerate".to_string(),
        None,
        130,
    )
    .is_err());
}

#[test]
fn followup_job_api_filters_out_jobs_for_inaccessible_todos() {
    let (temp_dir, key, conn) = setup();
    let app_dir = temp_dir
        .path()
        .join("secondloop")
        .to_string_lossy()
        .into_owned();

    db::upsert_todo(
        &conn,
        &key,
        "todo_visible",
        "Research LLM models",
        None,
        "open",
        None,
        None,
        None,
        None,
    )
    .expect("upsert visible todo");

    db::enqueue_todo_followup_generation_job(&conn, "todo_visible", "auto_create", None, 100)
        .expect("enqueue visible job");

    let inaccessible_key = [9u8; 32];
    db::upsert_todo(
        &conn,
        &inaccessible_key,
        "todo_hidden",
        "Secret todo",
        None,
        "open",
        None,
        None,
        None,
        None,
    )
    .expect("upsert inaccessible todo");
    db::enqueue_todo_followup_generation_job(&conn, "todo_hidden", "auto_create", None, 90)
        .expect("enqueue inaccessible job");

    let due = core::db_list_due_todo_followup_generation_jobs(app_dir, key.to_vec(), 100, 10)
        .expect("list visible due jobs");

    assert_eq!(due.len(), 1);
    assert_eq!(due[0].todo_id, "todo_visible");
}

#[test]
fn followup_job_api_rejects_missing_todo_instead_of_returning_none() {
    let (temp_dir, key, conn) = setup();
    let app_dir = temp_dir
        .path()
        .join("secondloop")
        .to_string_lossy()
        .into_owned();

    db::upsert_todo(
        &conn,
        &key,
        "todo_1",
        "Research LLM models",
        None,
        "open",
        None,
        None,
        None,
        None,
    )
    .expect("upsert todo");

    let result = core::db_get_todo_followup_generation_job(
        app_dir,
        key.to_vec(),
        "missing_todo".to_string(),
    );

    assert!(result.is_err());
}

#[test]
fn followup_job_api_returns_none_when_todo_exists_but_job_is_missing() {
    let (temp_dir, key, conn) = setup();
    let app_dir = temp_dir
        .path()
        .join("secondloop")
        .to_string_lossy()
        .into_owned();

    db::upsert_todo(
        &conn,
        &key,
        "todo_1",
        "Research LLM models",
        None,
        "open",
        None,
        None,
        None,
        None,
    )
    .expect("upsert todo");

    let result =
        core::db_get_todo_followup_generation_job(app_dir, key.to_vec(), "todo_1".to_string())
            .expect("query followup job");

    assert!(result.is_none());
}
