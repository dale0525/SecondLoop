pub fn mark_semantic_parse_job_failed_if_current_attempt(
    conn: &Connection,
    message_id: &str,
    expected_attempt_id: i64,
    attempts: i64,
    next_retry_at_ms: i64,
    last_error: &str,
    now_ms: i64,
) -> Result<bool> {
    let updated = conn.execute(
        r#"
UPDATE semantic_parse_jobs
SET status = 'failed',
    attempts = ?3,
    next_retry_at_ms = ?4,
    last_error = ?5,
    updated_at_ms = ?6
WHERE message_id = ?1
  AND status = 'running'
  AND attempt_id = ?2
"#,
        params![
            message_id,
            expected_attempt_id,
            attempts,
            next_retry_at_ms,
            last_error,
            now_ms
        ],
    )?;
    Ok(updated > 0)
}

pub fn mark_semantic_parse_job_retry(
    conn: &Connection,
    message_id: &str,
    now_ms: i64,
) -> Result<()> {
    conn.execute(
        r#"
UPDATE semantic_parse_jobs
SET status = 'pending',
    next_retry_at_ms = NULL,
    last_error = NULL,
    applied_action_kind = NULL,
    applied_todo_id = NULL,
    applied_todo_title = NULL,
    applied_prev_todo_status = NULL,
    suggested_tags_json = NULL,
    suggested_tag_confidence = NULL,
    tag_suggestion_state = 'none',
    applied_tag_ids_json = NULL,
    undone_at_ms = NULL,
    updated_at_ms = ?2
WHERE message_id = ?1
"#,
        params![message_id, now_ms],
    )?;
    Ok(())
}

pub fn requeue_running_semantic_parse_jobs(conn: &Connection, now_ms: i64) -> Result<i64> {
    let updated = conn.execute(
        r#"
UPDATE semantic_parse_jobs
SET status = 'pending',
    next_retry_at_ms = NULL,
    last_error = NULL,
    applied_action_kind = NULL,
    applied_todo_id = NULL,
    applied_todo_title = NULL,
    applied_prev_todo_status = NULL,
    suggested_tags_json = NULL,
    suggested_tag_confidence = NULL,
    tag_suggestion_state = 'none',
    applied_tag_ids_json = NULL,
    undone_at_ms = NULL,
    updated_at_ms = ?1
WHERE status = 'running'
"#,
        params![now_ms],
    )?;
    Ok(updated as i64)
}

pub fn mark_semantic_parse_job_succeeded(
    conn: &Connection,
    key: &[u8; 32],
    message_id: &str,
    applied_action_kind: &str,
    applied_todo_id: Option<&str>,
    applied_todo_title: Option<&str>,
    applied_prev_todo_status: Option<&str>,
    now_ms: i64,
) -> Result<()> {
    mark_semantic_parse_job_succeeded_with_tag_metadata(
        conn,
        key,
        message_id,
        applied_action_kind,
        applied_todo_id,
        applied_todo_title,
        applied_prev_todo_status,
        None,
        None,
        None,
        None,
        now_ms,
    )
}

#[allow(clippy::too_many_arguments)]
pub fn mark_semantic_parse_job_succeeded_if_current_attempt(
    conn: &Connection,
    key: &[u8; 32],
    message_id: &str,
    expected_attempt_id: i64,
    applied_action_kind: &str,
    applied_todo_id: Option<&str>,
    applied_todo_title: Option<&str>,
    applied_prev_todo_status: Option<&str>,
    now_ms: i64,
) -> Result<bool> {
    mark_semantic_parse_job_succeeded_with_tag_metadata_if_current_attempt(
        conn,
        key,
        message_id,
        expected_attempt_id,
        applied_action_kind,
        applied_todo_id,
        applied_todo_title,
        applied_prev_todo_status,
        None,
        None,
        None,
        None,
        now_ms,
    )
}

#[allow(clippy::too_many_arguments)]
pub fn mark_semantic_parse_job_succeeded_with_tag_metadata(
    conn: &Connection,
    key: &[u8; 32],
    message_id: &str,
    applied_action_kind: &str,
    applied_todo_id: Option<&str>,
    applied_todo_title: Option<&str>,
    applied_prev_todo_status: Option<&str>,
    suggested_tags: Option<&[String]>,
    suggested_tag_confidence: Option<f64>,
    tag_suggestion_state: Option<&str>,
    applied_tag_ids: Option<&[String]>,
    now_ms: i64,
) -> Result<()> {
    let message_id = message_id.trim();
    if message_id.is_empty() {
        return Err(anyhow!("message_id is required"));
    }
    let applied_action_kind = applied_action_kind.trim();
    if applied_action_kind.is_empty() {
        return Err(anyhow!("applied_action_kind is required"));
    }

    let title_blob = match applied_todo_title {
        Some(title) if !title.trim().is_empty() => {
            let aad = semantic_parse_job_title_aad(message_id);
            Some(encrypt_bytes(key, title.trim().as_bytes(), &aad)?)
        }
        _ => None,
    };

    let suggested_tags_blob = encode_semantic_parse_job_string_list_blob(
        key,
        message_id,
        suggested_tags,
        semantic_parse_job_suggested_tags_aad(message_id),
    )?;
    let applied_tag_ids_blob = encode_semantic_parse_job_string_list_blob(
        key,
        message_id,
        applied_tag_ids,
        semantic_parse_job_applied_tag_ids_aad(message_id),
    )?;
    let normalized_tag_suggestion_state = normalize_tag_suggestion_state(tag_suggestion_state)?;
    let normalized_tag_confidence = suggested_tag_confidence
        .filter(|value| value.is_finite())
        .map(|value| value.clamp(0.0, 1.0));

    conn.execute(
        r#"
UPDATE semantic_parse_jobs
SET status = 'succeeded',
    next_retry_at_ms = NULL,
    last_error = NULL,
    applied_action_kind = ?2,
    applied_todo_id = ?3,
    applied_todo_title = ?4,
    applied_prev_todo_status = ?5,
    suggested_tags_json = ?6,
    suggested_tag_confidence = ?7,
    tag_suggestion_state = ?8,
    applied_tag_ids_json = ?9,
    updated_at_ms = ?10
WHERE message_id = ?1
  AND status = 'running'
  AND updated_at_ms = ?10
"#,
        params![
            message_id,
            applied_action_kind,
            applied_todo_id,
            title_blob,
            applied_prev_todo_status,
            suggested_tags_blob,
            normalized_tag_confidence,
            normalized_tag_suggestion_state,
            applied_tag_ids_blob,
            now_ms
        ],
    )?;
    Ok(())
}

#[allow(clippy::too_many_arguments)]
pub fn mark_semantic_parse_job_succeeded_with_tag_metadata_if_current_attempt(
    conn: &Connection,
    key: &[u8; 32],
    message_id: &str,
    expected_attempt_id: i64,
    applied_action_kind: &str,
    applied_todo_id: Option<&str>,
    applied_todo_title: Option<&str>,
    applied_prev_todo_status: Option<&str>,
    suggested_tags: Option<&[String]>,
    suggested_tag_confidence: Option<f64>,
    tag_suggestion_state: Option<&str>,
    applied_tag_ids: Option<&[String]>,
    now_ms: i64,
) -> Result<bool> {
    let message_id = message_id.trim();
    if message_id.is_empty() {
        return Err(anyhow!("message_id is required"));
    }
    let applied_action_kind = applied_action_kind.trim();
    if applied_action_kind.is_empty() {
        return Err(anyhow!("applied_action_kind is required"));
    }

    let title_blob = match applied_todo_title {
        Some(title) if !title.trim().is_empty() => {
            let aad = semantic_parse_job_title_aad(message_id);
            Some(encrypt_bytes(key, title.trim().as_bytes(), &aad)?)
        }
        _ => None,
    };

    let suggested_tags_blob = encode_semantic_parse_job_string_list_blob(
        key,
        message_id,
        suggested_tags,
        semantic_parse_job_suggested_tags_aad(message_id),
    )?;
    let applied_tag_ids_blob = encode_semantic_parse_job_string_list_blob(
        key,
        message_id,
        applied_tag_ids,
        semantic_parse_job_applied_tag_ids_aad(message_id),
    )?;
    let normalized_tag_suggestion_state = normalize_tag_suggestion_state(tag_suggestion_state)?;
    let normalized_tag_confidence = suggested_tag_confidence
        .filter(|value| value.is_finite())
        .map(|value| value.clamp(0.0, 1.0));

    let updated = conn.execute(
        r#"
UPDATE semantic_parse_jobs
SET status = 'succeeded',
    next_retry_at_ms = NULL,
    last_error = NULL,
    applied_action_kind = ?3,
    applied_todo_id = ?4,
    applied_todo_title = ?5,
    applied_prev_todo_status = ?6,
    suggested_tags_json = ?7,
    suggested_tag_confidence = ?8,
    tag_suggestion_state = ?9,
    applied_tag_ids_json = ?10,
    updated_at_ms = ?11
WHERE message_id = ?1
  AND status = 'running'
  AND attempt_id = ?2
"#,
        params![
            message_id,
            expected_attempt_id,
            applied_action_kind,
            applied_todo_id,
            title_blob,
            applied_prev_todo_status,
            suggested_tags_blob,
            normalized_tag_confidence,
            normalized_tag_suggestion_state,
            applied_tag_ids_blob,
            now_ms
        ],
    )?;
    Ok(updated > 0)
}

pub fn mark_semantic_parse_job_canceled(
    conn: &Connection,
    message_id: &str,
    now_ms: i64,
) -> Result<()> {
    conn.execute(
        r#"
UPDATE semantic_parse_jobs
SET status = 'canceled',
    next_retry_at_ms = NULL,
    last_error = NULL,
    updated_at_ms = ?2
WHERE message_id = ?1
  AND status != 'succeeded'
"#,
        params![message_id, now_ms],
    )?;
    Ok(())
}

pub fn mark_semantic_parse_job_canceled_if_current_attempt(
    conn: &Connection,
    message_id: &str,
    expected_attempt_id: i64,
    now_ms: i64,
) -> Result<bool> {
    let updated = conn.execute(
        r#"
UPDATE semantic_parse_jobs
SET status = 'canceled',
    next_retry_at_ms = NULL,
    last_error = NULL,
    updated_at_ms = ?3
WHERE message_id = ?1
  AND status = 'running'
  AND attempt_id = ?2
"#,
        params![message_id, expected_attempt_id, now_ms],
    )?;
    Ok(updated > 0)
}

pub fn apply_semantic_parse_tags_if_current_attempt(
    conn: &Connection,
    key: &[u8; 32],
    message_id: &str,
    expected_attempt_id: i64,
    suggested_tags: &[String],
) -> Result<Vec<String>> {
    run_immediate_transaction(conn, || {
        if !semantic_parse_attempt_matches(conn, message_id, expected_attempt_id)? {
            return Ok(Vec::new());
        }
        apply_semantic_parse_tags_in_existing_txn(conn, key, message_id, suggested_tags)
    })
}

#[allow(clippy::too_many_arguments)]
pub fn upsert_semantic_parse_todo_create_if_current_attempt(
    conn: &Connection,
    key: &[u8; 32],
    message_id: &str,
    expected_attempt_id: i64,
    todo_id: &str,
    title: &str,
    due_at_ms: Option<i64>,
    status: &str,
    review_stage: Option<i64>,
    next_review_at_ms: Option<i64>,
    last_review_at_ms: Option<i64>,
    task_type_hint: Option<&str>,
    recurrence_rule_json: Option<&str>,
    now_ms: i64,
) -> Result<Option<String>> {
    run_immediate_transaction(conn, || {
        if !semantic_parse_attempt_matches(conn, message_id, expected_attempt_id)? {
            return Ok(None);
        }

        Ok(Some(upsert_semantic_parse_todo_create_in_existing_txn(
            conn,
            key,
            SemanticParseTodoCreateUpsert {
                message_id,
                todo_id,
                title,
                due_at_ms,
                status,
                review_stage,
                next_review_at_ms,
                last_review_at_ms,
                task_type_hint,
                recurrence_rule_json,
                now_ms,
            },
        )?))
    })
}

pub fn upsert_semantic_parse_checklist_suggestions_if_current_attempt(
    conn: &Connection,
    key: &[u8; 32],
    message_id: &str,
    expected_attempt_id: i64,
    todo_id: &str,
    suggestions: &[String],
    source: &str,
    generation_key: Option<&str>,
) -> Result<bool> {
    run_immediate_transaction(conn, || {
        if !semantic_parse_attempt_matches(conn, message_id, expected_attempt_id)? {
            return Ok(false);
        }
        upsert_semantic_parse_checklist_suggestions_in_existing_txn(
            conn,
            key,
            todo_id,
            suggestions,
            source,
            generation_key,
        )
    })
}

pub fn set_semantic_parse_todo_status_if_current_attempt(
    conn: &Connection,
    key: &[u8; 32],
    message_id: &str,
    expected_attempt_id: i64,
    todo_id: &str,
    new_status: &str,
) -> Result<Option<String>> {
    run_immediate_transaction(conn, || {
        if !semantic_parse_attempt_matches(conn, message_id, expected_attempt_id)? {
            return Ok(None);
        }

        Ok(Some(set_semantic_parse_todo_status_in_existing_txn(
            conn,
            key,
            todo_id,
            new_status,
            message_id,
        )?))
    })
}

fn set_semantic_parse_todo_due_in_existing_txn(
    conn: &Connection,
    key: &[u8; 32],
    todo_id: &str,
    due_at_ms: i64,
) -> Result<()> {
    let current = get_todo(conn, key, todo_id)?;
    let _ = upsert_todo(
        conn,
        key,
        &current.id,
        &current.title,
        Some(due_at_ms),
        &current.status,
        current.source_entry_id.as_deref(),
        current.review_stage,
        current.next_review_at_ms,
        current.last_review_at_ms,
        current.manual_importance_nudge_score,
        current.manual_urgency_nudge_score,
    )?;
    Ok(())
}

#[allow(clippy::too_many_arguments)]
pub fn complete_semantic_parse_no_action_if_current_attempt(
    conn: &Connection,
    key: &[u8; 32],
    message_id: &str,
    expected_attempt_id: i64,
    pending_suggested_tags: Option<&[String]>,
    auto_apply_suggested_tags: Option<&[String]>,
    suggested_tag_confidence: Option<f64>,
    now_ms: i64,
) -> Result<Option<Vec<String>>> {
    run_immediate_transaction(conn, || {
        if !semantic_parse_attempt_matches(conn, message_id, expected_attempt_id)? {
            return Ok(None);
        }

        let mut applied_tag_ids = Vec::<String>::new();
        let mut stored_suggested_tags = pending_suggested_tags;
        let mut stored_tag_confidence = pending_suggested_tags.and(suggested_tag_confidence);
        let mut stored_tag_state = if pending_suggested_tags.is_some() {
            Some("pending")
        } else {
            Some("none")
        };

        if let Some(auto_tags) = auto_apply_suggested_tags {
            let applied = apply_semantic_parse_tags_in_existing_txn(conn, key, message_id, auto_tags)?;
            if !applied.is_empty() {
                stored_suggested_tags = Some(auto_tags);
                stored_tag_confidence = suggested_tag_confidence;
                stored_tag_state = Some("applied");
                applied_tag_ids = applied;
            } else {
                stored_suggested_tags = None;
                stored_tag_confidence = None;
                stored_tag_state = Some("none");
            }
        }

        let finalized = mark_semantic_parse_job_succeeded_with_tag_metadata_if_current_attempt(
            conn,
            key,
            message_id,
            expected_attempt_id,
            "none",
            None,
            None,
            None,
            stored_suggested_tags,
            stored_tag_confidence,
            stored_tag_state,
            if applied_tag_ids.is_empty() {
                None
            } else {
                Some(applied_tag_ids.as_slice())
            },
            now_ms,
        )?;
        if !finalized {
            return Err(anyhow!("semantic parse no-op finalize failed inside transaction"));
        }
        Ok(Some(applied_tag_ids))
    })
}

#[allow(clippy::too_many_arguments)]
pub fn complete_semantic_parse_create_if_current_attempt(
    conn: &Connection,
    key: &[u8; 32],
    message_id: &str,
    expected_attempt_id: i64,
    todo_id: &str,
    title: &str,
    due_at_ms: Option<i64>,
    status: &str,
    review_stage: Option<i64>,
    next_review_at_ms: Option<i64>,
    last_review_at_ms: Option<i64>,
    task_type_hint: Option<&str>,
    recurrence_rule_json: Option<&str>,
    checklist_suggestions: &[String],
    checklist_source: &str,
    checklist_generation_key: Option<&str>,
    pending_suggested_tags: Option<&[String]>,
    auto_apply_suggested_tags: Option<&[String]>,
    suggested_tag_confidence: Option<f64>,
    now_ms: i64,
) -> Result<bool> {
    run_immediate_transaction(conn, || {
        if !semantic_parse_attempt_matches(conn, message_id, expected_attempt_id)? {
            return Ok(false);
        }

        let mut applied_tag_ids = Vec::<String>::new();
        let mut stored_suggested_tags = pending_suggested_tags;
        let mut stored_tag_confidence = pending_suggested_tags.and(suggested_tag_confidence);
        let mut stored_tag_state = if pending_suggested_tags.is_some() {
            Some("pending")
        } else {
            Some("none")
        };

        if let Some(auto_tags) = auto_apply_suggested_tags {
            let applied = apply_semantic_parse_tags_in_existing_txn(conn, key, message_id, auto_tags)?;
            if !applied.is_empty() {
                stored_suggested_tags = Some(auto_tags);
                stored_tag_confidence = suggested_tag_confidence;
                stored_tag_state = Some("applied");
                applied_tag_ids = applied;
            } else {
                stored_suggested_tags = None;
                stored_tag_confidence = None;
                stored_tag_state = Some("none");
            }
        }

        let applied_todo_id = upsert_semantic_parse_todo_create_in_existing_txn(
            conn,
            key,
            SemanticParseTodoCreateUpsert {
                message_id,
                todo_id,
                title,
                due_at_ms,
                status,
                review_stage,
                next_review_at_ms,
                last_review_at_ms,
                task_type_hint,
                recurrence_rule_json,
                now_ms,
            },
        )?;
        let _ = upsert_semantic_parse_checklist_suggestions_in_existing_txn(
            conn,
            key,
            applied_todo_id.as_str(),
            checklist_suggestions,
            checklist_source,
            checklist_generation_key,
        )?;

        let finalized = mark_semantic_parse_job_succeeded_with_tag_metadata_if_current_attempt(
            conn,
            key,
            message_id,
            expected_attempt_id,
            "create",
            Some(applied_todo_id.as_str()),
            Some(title),
            None,
            stored_suggested_tags,
            stored_tag_confidence,
            stored_tag_state,
            if applied_tag_ids.is_empty() {
                None
            } else {
                Some(applied_tag_ids.as_slice())
            },
            now_ms,
        )?;
        if !finalized {
            return Err(anyhow!("semantic parse create finalize failed inside transaction"));
        }
        Ok(true)
    })
}

#[allow(clippy::too_many_arguments)]
pub fn complete_semantic_parse_followup_if_current_attempt(
    conn: &Connection,
    key: &[u8; 32],
    message_id: &str,
    expected_attempt_id: i64,
    todo_id: &str,
    todo_title: Option<&str>,
    new_status: Option<&str>,
    due_at_ms: Option<i64>,
    pending_suggested_tags: Option<&[String]>,
    auto_apply_suggested_tags: Option<&[String]>,
    suggested_tag_confidence: Option<f64>,
    now_ms: i64,
) -> Result<bool> {
    run_immediate_transaction(conn, || {
        if !semantic_parse_attempt_matches(conn, message_id, expected_attempt_id)? {
            return Ok(false);
        }

        let mut applied_tag_ids = Vec::<String>::new();
        let mut stored_suggested_tags = pending_suggested_tags;
        let mut stored_tag_confidence = pending_suggested_tags.and(suggested_tag_confidence);
        let mut stored_tag_state = if pending_suggested_tags.is_some() {
            Some("pending")
        } else {
            Some("none")
        };

        if let Some(auto_tags) = auto_apply_suggested_tags {
            let applied = apply_semantic_parse_tags_in_existing_txn(conn, key, message_id, auto_tags)?;
            if !applied.is_empty() {
                stored_suggested_tags = Some(auto_tags);
                stored_tag_confidence = suggested_tag_confidence;
                stored_tag_state = Some("applied");
                applied_tag_ids = applied;
            } else {
                stored_suggested_tags = None;
                stored_tag_confidence = None;
                stored_tag_state = Some("none");
            }
        }

        let previous_status = match new_status {
            Some(status) if !status.trim().is_empty() => Some(
                set_semantic_parse_todo_status_in_existing_txn(
                    conn, key, todo_id, status, message_id,
                )?,
            ),
            _ => None,
        };
        if let Some(next_due_at_ms) = due_at_ms {
            set_semantic_parse_todo_due_in_existing_txn(conn, key, todo_id, next_due_at_ms)?;
        }

        let finalized = mark_semantic_parse_job_succeeded_with_tag_metadata_if_current_attempt(
            conn,
            key,
            message_id,
            expected_attempt_id,
            "followup",
            Some(todo_id),
            todo_title,
            previous_status.as_deref(),
            stored_suggested_tags,
            stored_tag_confidence,
            stored_tag_state,
            if applied_tag_ids.is_empty() {
                None
            } else {
                Some(applied_tag_ids.as_slice())
            },
            now_ms,
        )?;
        if !finalized {
            return Err(anyhow!("semantic parse followup finalize failed inside transaction"));
        }
        Ok(true)
    })
}

pub fn mark_semantic_parse_job_undone(
    conn: &Connection,
    message_id: &str,
    now_ms: i64,
) -> Result<()> {
    conn.execute(
        r#"
UPDATE semantic_parse_jobs
SET undone_at_ms = ?2,
    updated_at_ms = ?2
WHERE message_id = ?1
"#,
        params![message_id, now_ms],
    )?;
    Ok(())
}
