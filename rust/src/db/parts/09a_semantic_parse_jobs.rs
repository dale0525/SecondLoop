fn encode_semantic_parse_job_string_list_blob(
    key: &[u8; 32],
    _message_id: &str,
    values: Option<&[String]>,
    aad: Vec<u8>,
) -> Result<Option<Vec<u8>>> {
    let Some(values) = values else {
        return Ok(None);
    };

    let normalized = values
        .iter()
        .map(|value| value.trim())
        .filter(|value| !value.is_empty())
        .map(std::string::ToString::to_string)
        .collect::<Vec<_>>();
    if normalized.is_empty() {
        return Ok(None);
    }

    let json = serde_json::to_vec(&normalized)
        .map_err(|e| anyhow!("failed to serialize semantic parse job tags json: {e}"))?;
    let encrypted = encrypt_bytes(key, &json, &aad)?;
    Ok(Some(encrypted))
}

fn decode_semantic_parse_job_string_list_blob(
    key: &[u8; 32],
    message_id: &str,
    blob: Option<Vec<u8>>,
    aad: Vec<u8>,
) -> Result<Option<Vec<String>>> {
    let Some(blob) = blob else {
        return Ok(None);
    };

    let bytes = decrypt_bytes(key, &blob, &aad)?;
    let parsed: Vec<String> = serde_json::from_slice(&bytes).map_err(|e| {
        anyhow!(
            "failed to decode semantic parse job tag list for message_id={message_id}: {e}"
        )
    })?;

    let normalized = parsed
        .into_iter()
        .map(|value| value.trim().to_string())
        .filter(|value| !value.is_empty())
        .collect::<Vec<_>>();
    if normalized.is_empty() {
        return Ok(None);
    }

    Ok(Some(normalized))
}

fn normalize_tag_suggestion_state(raw: Option<&str>) -> Result<String> {
    let value = raw.unwrap_or("none").trim().to_ascii_lowercase();
    match value.as_str() {
        "none" | "pending" | "applied" | "dismissed" => Ok(value),
        _ => Err(anyhow!("invalid tag_suggestion_state")),
    }
}


pub fn enqueue_semantic_parse_job(conn: &Connection, message_id: &str, now_ms: i64) -> Result<()> {
    let message_id = message_id.trim();
    if message_id.is_empty() {
        return Err(anyhow!("message_id is required"));
    }

    conn.execute(
        r#"
INSERT INTO semantic_parse_jobs(
  message_id,
  status,
  attempt_id,
  attempts,
  next_retry_at_ms,
  last_error,
  applied_action_kind,
  applied_todo_id,
  applied_todo_title,
  applied_prev_todo_status,
  applied_prev_todo_due_at_ms,
  applied_due_changed,
  suggested_tags_json,
  suggested_tag_confidence,
  tag_suggestion_state,
  applied_tag_ids_json,
  undone_at_ms,
  created_at_ms,
  updated_at_ms
)
VALUES (
  ?1,
  'pending',
  0,
  0,
  NULL,
  NULL,
  NULL,
  NULL,
  NULL,
  NULL,
  NULL,
  0,
  NULL,
  NULL,
  'none',
  NULL,
  NULL,
  ?2,
  ?2
)
ON CONFLICT(message_id) DO UPDATE SET
  status = 'pending',
  attempt_id = 0,
  attempts = 0,
  next_retry_at_ms = NULL,
  last_error = NULL,
  applied_action_kind = NULL,
  applied_todo_id = NULL,
  applied_todo_title = NULL,
  applied_prev_todo_status = NULL,
  applied_prev_todo_due_at_ms = NULL,
  applied_due_changed = 0,
  suggested_tags_json = NULL,
  suggested_tag_confidence = NULL,
  tag_suggestion_state = 'none',
  applied_tag_ids_json = NULL,
  undone_at_ms = NULL,
  updated_at_ms = excluded.updated_at_ms
"#,
        params![message_id, now_ms],
    )?;
    Ok(())
}

pub fn list_due_semantic_parse_jobs(
    conn: &Connection,
    now_ms: i64,
    limit: i64,
) -> Result<Vec<SemanticParseJob>> {
    let limit = limit.clamp(1, 500);
    let mut stmt = conn.prepare(
        r#"
SELECT message_id,
       status,
       attempt_id,
       attempts,
       next_retry_at_ms,
       last_error,
       applied_action_kind,
       applied_todo_id,
       applied_prev_todo_status,
       applied_prev_todo_due_at_ms,
       applied_due_changed,
       undone_at_ms,
       created_at_ms,
       updated_at_ms
FROM semantic_parse_jobs
WHERE (
      status = 'pending'
   OR (
        status = 'failed'
        AND (next_retry_at_ms IS NULL OR next_retry_at_ms <= ?1)
      )
)
ORDER BY updated_at_ms ASC, message_id ASC
LIMIT ?2
"#,
    )?;

    let mut rows = stmt.query(params![now_ms, limit])?;
    let mut result = Vec::new();
    while let Some(row) = rows.next()? {
        result.push(SemanticParseJob {
            message_id: row.get(0)?,
            status: row.get(1)?,
            attempt_id: row.get(2)?,
            attempts: row.get(3)?,
            next_retry_at_ms: row.get(4)?,
            last_error: row.get(5)?,
            applied_action_kind: row.get(6)?,
            applied_todo_id: row.get(7)?,
            applied_todo_title: None,
            applied_prev_todo_status: row.get(8)?,
            applied_prev_todo_due_at_ms: row.get(9)?,
            applied_due_changed: row.get::<_, i64>(10)? != 0,
            suggested_tags: None,
            suggested_tag_confidence: None,
            tag_suggestion_state: None,
            applied_tag_ids: None,
            undone_at_ms: row.get(11)?,
            created_at_ms: row.get(12)?,
            updated_at_ms: row.get(13)?,
        });
    }
    Ok(result)
}

pub fn list_semantic_parse_jobs_by_message_ids(
    conn: &Connection,
    key: &[u8; 32],
    message_ids: &[String],
) -> Result<Vec<SemanticParseJob>> {
    if message_ids.is_empty() {
        return Ok(Vec::new());
    }

    let mut placeholders = String::new();
    for i in 0..message_ids.len() {
        if i > 0 {
            placeholders.push(',');
        }
        placeholders.push('?');
        placeholders.push_str(&(i + 1).to_string());
    }

    let sql = format!(
        r#"
SELECT message_id,
       status,
       attempt_id,
       attempts,
       next_retry_at_ms,
       last_error,
       applied_action_kind,
       applied_todo_id,
       applied_todo_title,
       applied_prev_todo_status,
       applied_prev_todo_due_at_ms,
       applied_due_changed,
       suggested_tags_json,
       suggested_tag_confidence,
       tag_suggestion_state,
       applied_tag_ids_json,
       undone_at_ms,
       created_at_ms,
       updated_at_ms
FROM semantic_parse_jobs
WHERE message_id IN ({placeholders})
ORDER BY updated_at_ms ASC, message_id ASC
"#
    );

    let mut stmt = conn.prepare(&sql)?;
    let params = rusqlite::params_from_iter(message_ids.iter());
    let mut rows = stmt.query(params)?;

    let mut result = Vec::new();
    while let Some(row) = rows.next()? {
        let message_id: String = row.get(0)?;
        let title_blob: Option<Vec<u8>> = row.get(8)?;
        let applied_todo_title = match title_blob {
            Some(blob) => {
                let aad = semantic_parse_job_title_aad(&message_id);
                let bytes = decrypt_bytes(key, &blob, &aad)?;
                Some(
                    String::from_utf8(bytes)
                        .map_err(|_| anyhow!("job title is not valid utf-8"))?,
                )
            }
            None => None,
        };

        let suggested_tags = decode_semantic_parse_job_string_list_blob(
            key,
            &message_id,
            row.get(12)?,
            semantic_parse_job_suggested_tags_aad(&message_id),
        )?;
        let applied_tag_ids = decode_semantic_parse_job_string_list_blob(
            key,
            &message_id,
            row.get(15)?,
            semantic_parse_job_applied_tag_ids_aad(&message_id),
        )?;

        result.push(SemanticParseJob {
            message_id,
            status: row.get(1)?,
            attempt_id: row.get(2)?,
            attempts: row.get(3)?,
            next_retry_at_ms: row.get(4)?,
            last_error: row.get(5)?,
            applied_action_kind: row.get(6)?,
            applied_todo_id: row.get(7)?,
            applied_todo_title,
            applied_prev_todo_status: row.get(9)?,
            applied_prev_todo_due_at_ms: row.get(10)?,
            applied_due_changed: row.get::<_, i64>(11)? != 0,
            suggested_tags,
            suggested_tag_confidence: row.get(13)?,
            tag_suggestion_state: row.get(14)?,
            applied_tag_ids,
            undone_at_ms: row.get(16)?,
            created_at_ms: row.get(17)?,
            updated_at_ms: row.get(18)?,
        });
    }
    Ok(result)
}

fn get_semantic_parse_job_attempt_row(
    conn: &Connection,
    message_id: &str,
) -> Result<Option<(String, i64)>> {
    Ok(conn
        .query_row(
        r#"SELECT status, attempt_id FROM semantic_parse_jobs WHERE message_id = ?1"#,
        params![message_id],
        |row| Ok((row.get(0)?, row.get(1)?)),
    )
    .optional()?)
}

fn semantic_parse_attempt_matches(
    conn: &Connection,
    message_id: &str,
    expected_attempt_id: i64,
) -> Result<bool> {
    let Some((status, attempt_id)) = get_semantic_parse_job_attempt_row(conn, message_id)? else {
        return Ok(false);
    };
    Ok(status == "running" && attempt_id == expected_attempt_id)
}

fn set_message_tags_in_existing_txn(
    conn: &Connection,
    db_key: &[u8; 32],
    message_id: &str,
    tag_ids: &[String],
) -> Result<()> {
    ensure_system_tags(conn, db_key)?;

    let message_exists: Option<i64> = conn
        .query_row(
            r#"SELECT 1 FROM messages WHERE id = ?1"#,
            params![message_id],
            |row| row.get(0),
        )
        .optional()?;
    if message_exists.is_none() {
        return Err(anyhow!("message not found: {message_id}"));
    }

    let mut dedup = std::collections::BTreeSet::<String>::new();
    for raw in tag_ids {
        let trimmed = raw.trim();
        if trimmed.is_empty() {
            continue;
        }
        let tag_exists: Option<i64> = conn
            .query_row(
                r#"SELECT 1 FROM tags WHERE id = ?1"#,
                params![trimmed],
                |row| row.get(0),
            )
            .optional()?;
        if tag_exists.is_some() {
            dedup.insert(trimmed.to_string());
        }
    }

    let next_tag_ids: Vec<String> = dedup.into_iter().collect();
    let mut stmt = conn.prepare(
        r#"SELECT tag_id FROM message_tags WHERE message_id = ?1 ORDER BY tag_id ASC"#,
    )?;
    let mut rows = stmt.query(params![message_id])?;
    let mut existing_tag_ids = Vec::<String>::new();
    while let Some(row) = rows.next()? {
        existing_tag_ids.push(row.get(0)?);
    }

    if existing_tag_ids == next_tag_ids {
        return Ok(());
    }

    conn.execute(
        r#"DELETE FROM message_tags WHERE message_id = ?1"#,
        params![message_id],
    )?;

    let now = now_ms();
    for tag_id in &next_tag_ids {
        conn.execute(
            r#"INSERT INTO message_tags(message_id, tag_id, created_at_ms)
               VALUES (?1, ?2, ?3)"#,
            params![message_id, tag_id, now],
        )?;
    }

    let device_id = get_or_create_device_id(conn)?;
    let seq = next_device_seq(conn, &device_id)?;
    let op = serde_json::json!({
        "op_id": uuid::Uuid::new_v4().to_string(),
        "device_id": device_id,
        "seq": seq,
        "ts_ms": now,
        "type": "message.tag_set.v1",
        "payload": {
            "message_id": message_id,
            "tag_ids": next_tag_ids,
            "created_at_ms": now,
        }
    });
    insert_oplog(conn, db_key, &op)?;
    Ok(())
}

pub fn mark_semantic_parse_job_running(
    conn: &Connection,
    message_id: &str,
    now_ms: i64,
) -> Result<i64> {
    run_immediate_transaction(conn, || {
        let updated = conn.execute(
            r#"
UPDATE semantic_parse_jobs
SET status = 'running',
    attempt_id = attempt_id + 1,
    next_retry_at_ms = NULL,
    last_error = NULL,
    updated_at_ms = ?2
WHERE message_id = ?1
  AND status IN ('pending', 'failed')
"#,
            params![message_id, now_ms],
        )?;
        if updated == 0 {
            return Err(anyhow!("semantic parse job is not claimable: {message_id}"));
        }

        conn.query_row(
            r#"SELECT attempt_id FROM semantic_parse_jobs WHERE message_id = ?1"#,
            params![message_id],
            |row| row.get(0),
        )
        .map_err(Into::into)
    })
}

fn apply_semantic_parse_tags_in_existing_txn(
    conn: &Connection,
    key: &[u8; 32],
    message_id: &str,
    suggested_tags: &[String],
) -> Result<Vec<String>> {
    let manual_tag_names = list_manual_message_tag_names(conn, key, message_id)?;
    if manual_tag_names.len() >= MAX_SUGGESTED_TAGS_PER_MESSAGE {
        return Ok(Vec::new());
    }

    let manual_tag_name_set = manual_tag_names
        .into_iter()
        .map(|name| normalize_tag_name(&name))
        .collect::<std::collections::HashSet<_>>();
    let allowed_auto_fill_count = MAX_SUGGESTED_TAGS_PER_MESSAGE - manual_tag_name_set.len();
    if allowed_auto_fill_count == 0 {
        return Ok(Vec::new());
    }

    let existing_message_tags = list_message_tags(conn, key, message_id)?;
    let mut next_tag_ids = existing_message_tags
        .iter()
        .map(|tag| tag.id.clone())
        .collect::<std::collections::BTreeSet<_>>();

    let mut applied_tag_ids = Vec::<String>::new();
    for raw_tag_name in suggested_tags {
        let normalized = normalize_tag_name(raw_tag_name);
        if normalized.is_empty() || manual_tag_name_set.contains(&normalized) {
            continue;
        }

        let tag = upsert_tag(conn, key, raw_tag_name)?;
        if next_tag_ids.insert(tag.id.clone()) {
            applied_tag_ids.push(tag.id);
            if applied_tag_ids.len() >= allowed_auto_fill_count {
                break;
            }
        }
    }

    if applied_tag_ids.is_empty() {
        return Ok(Vec::new());
    }

    let next_tag_ids = next_tag_ids.into_iter().collect::<Vec<_>>();
    set_message_tags_in_existing_txn(conn, key, message_id, &next_tag_ids)?;
    Ok(applied_tag_ids)
}

struct SemanticParseTodoCreateUpsert<'a> {
    message_id: &'a str,
    todo_id: &'a str,
    title: &'a str,
    due_at_ms: Option<i64>,
    status: &'a str,
    review_stage: Option<i64>,
    next_review_at_ms: Option<i64>,
    last_review_at_ms: Option<i64>,
    task_type_hint: Option<&'a str>,
    recurrence_rule_json: Option<&'a str>,
    now_ms: i64,
}

fn upsert_semantic_parse_todo_create_in_existing_txn(
    conn: &Connection,
    key: &[u8; 32],
    params: SemanticParseTodoCreateUpsert<'_>,
) -> Result<String> {
    let SemanticParseTodoCreateUpsert {
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
    } = params;
    let todo = upsert_todo(
        conn,
        key,
        todo_id,
        title,
        due_at_ms,
        status,
        Some(message_id),
        review_stage,
        next_review_at_ms,
        last_review_at_ms,
        None,
        None,
    )?;
    let normalized_task_type_hint = normalize_todo_followup_task_type_hint(task_type_hint);
    if todo.created_at_ms == todo.updated_at_ms
        && todo_followup_task_type_allows_auto_followup(title, normalized_task_type_hint)
    {
        enqueue_todo_followup_generation_job(
            conn,
            todo_id,
            "auto_create",
            false,
            normalized_task_type_hint,
            now_ms,
        )?;
    }

    if let Some(rule_json) = recurrence_rule_json.map(str::trim).filter(|value| !value.is_empty()) {
        let _ = upsert_todo_recurrence_with_sync_in_txn(
            conn,
            key,
            todo_id,
            &format!("series:{message_id}"),
            rule_json,
            None,
        )?;
    }

    Ok(todo.id)
}

fn upsert_semantic_parse_checklist_suggestions_in_existing_txn(
    conn: &Connection,
    key: &[u8; 32],
    todo_id: &str,
    suggestions: &[String],
    source: &str,
    generation_key: Option<&str>,
) -> Result<bool> {
    if suggestions.is_empty() {
        return Ok(false);
    }

    let existing = list_todo_checklist_suggestions(conn, key, todo_id)?;
    let mut blocked_norms = existing
        .iter()
        .map(|item| normalize_checklist_suggestion_content(&item.content))
        .collect::<std::collections::HashSet<_>>();

    let base_sort_order: i64 = conn.query_row(
        r#"SELECT COALESCE(MAX(sort_order), -1) + 1 FROM todo_checklist_suggestions WHERE todo_id = ?1"#,
        params![todo_id],
        |row| row.get(0),
    )?;
    let now = now_ms();
    let device_id = get_or_create_device_id(conn)?;
    let mut insert_index: i64 = 0;
    let mut created_any = false;

    for raw_content in suggestions {
        let trimmed = raw_content.trim();
        if trimmed.is_empty() {
            continue;
        }
        let normalized = normalize_checklist_suggestion_content(trimmed);
        if normalized.is_empty() || !blocked_norms.insert(normalized) {
            continue;
        }

        let id = uuid::Uuid::new_v4().to_string();
        let content_blob = encrypt_bytes(
            key,
            trimmed.as_bytes(),
            &todo_checklist_suggestion_content_aad(&id),
        )?;
        conn.execute(
            r#"
INSERT INTO todo_checklist_suggestions(
  id, todo_id, content, sort_order, state, source, generation_key, created_at_ms, updated_at_ms, dismissed_at_ms, applied_checklist_item_id
) VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, NULL, NULL)
"#,
            params![
                id,
                todo_id,
                content_blob,
                base_sort_order + insert_index,
                TODO_CHECKLIST_SUGGESTION_STATE_PENDING,
                source,
                generation_key,
                now,
                now,
            ],
        )?;
        let suggestion = get_todo_checklist_suggestion_by_id(conn, key, &id)?;

        let seq = next_device_seq(conn, &device_id)?;
        let op = serde_json::json!({
            "op_id": uuid::Uuid::new_v4().to_string(),
            "device_id": device_id,
            "seq": seq,
            "ts_ms": now,
            "type": "todo.checklist_suggestion.upsert.v1",
            "payload": {
                "suggestion_id": suggestion.id,
                "todo_id": suggestion.todo_id,
                "content": suggestion.content,
                "sort_order": suggestion.sort_order,
                "state": suggestion.state,
                "source": suggestion.source,
                "generation_key": suggestion.generation_key,
                "created_at_ms": suggestion.created_at_ms,
                "updated_at_ms": suggestion.updated_at_ms,
                "dismissed_at_ms": suggestion.dismissed_at_ms,
                "applied_checklist_item_id": suggestion.applied_checklist_item_id,
            }
        });
        insert_oplog(conn, key, &op)?;

        insert_index += 1;
        created_any = true;
    }

    Ok(created_any)
}

fn set_semantic_parse_todo_status_in_existing_txn(
    conn: &Connection,
    key: &[u8; 32],
    todo_id: &str,
    new_status: &str,
    source_message_id: &str,
) -> Result<String> {
    let existing = get_todo(conn, key, todo_id)?;
    let previous_status = existing.status.clone();
    let _ = set_todo_status_in_txn(conn, key, todo_id, new_status, Some(source_message_id))?;
    Ok(previous_status)
}

pub fn mark_semantic_parse_job_failed(
    conn: &Connection,
    message_id: &str,
    attempts: i64,
    next_retry_at_ms: i64,
    last_error: &str,
    now_ms: i64,
) -> Result<()> {
    conn.execute(
        r#"
UPDATE semantic_parse_jobs
SET status = 'failed',
    attempts = ?2,
    next_retry_at_ms = ?3,
    last_error = ?4,
    updated_at_ms = ?5
WHERE message_id = ?1
  AND status = 'running'
  AND updated_at_ms = ?5
"#,
        params![message_id, attempts, next_retry_at_ms, last_error, now_ms],
    )?;
    Ok(())
}
