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
       undone_at_ms,
       created_at_ms,
       updated_at_ms
FROM semantic_parse_jobs
WHERE status IN ('pending', 'failed', 'running')
  AND (next_retry_at_ms IS NULL OR next_retry_at_ms <= ?1)
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
            suggested_tags: None,
            suggested_tag_confidence: None,
            tag_suggestion_state: None,
            applied_tag_ids: None,
            undone_at_ms: row.get(9)?,
            created_at_ms: row.get(10)?,
            updated_at_ms: row.get(11)?,
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
            row.get(10)?,
            semantic_parse_job_suggested_tags_aad(&message_id),
        )?;
        let applied_tag_ids = decode_semantic_parse_job_string_list_blob(
            key,
            &message_id,
            row.get(13)?,
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
            suggested_tags,
            suggested_tag_confidence: row.get(11)?,
            tag_suggestion_state: row.get(12)?,
            applied_tag_ids,
            undone_at_ms: row.get(14)?,
            created_at_ms: row.get(15)?,
            updated_at_ms: row.get(16)?,
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
    updated_at_ms = ?2
WHERE message_id = ?1
  AND status IN ('pending', 'failed', 'running')
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
        if todo.created_at_ms == todo.updated_at_ms {
            let normalized_task_type_hint = task_type_hint
                .map(str::trim)
                .filter(|value| !value.is_empty());
            enqueue_todo_followup_generation_job(
                conn,
                todo_id,
                "auto_create",
                false,
                normalized_task_type_hint,
                now_ms,
            )?;
        }

        if let Some(rule_json) = recurrence_rule_json
            .map(str::trim)
            .filter(|value| !value.is_empty())
        {
            let _ = upsert_todo_recurrence_with_sync_in_txn(
                conn,
                key,
                todo_id,
                &format!("series:{message_id}"),
                rule_json,
                None,
            )?;
        }

        Ok(Some(todo.id))
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

        let existing = get_todo(conn, key, todo_id)?;
        let previous_status = existing.status.clone();
        let _ = set_todo_status_in_txn(conn, key, todo_id, new_status, Some(message_id))?;
        Ok(Some(previous_status))
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

pub fn link_attachment_to_message(
    conn: &Connection,
    key: &[u8; 32],
    message_id: &str,
    attachment_sha256: &str,
) -> Result<()> {
    backfill_attachments_oplog_if_needed(conn, key)?;

    let now = now_ms();
    let inserted = conn.execute(
        r#"INSERT OR IGNORE INTO message_attachments(message_id, attachment_sha256, created_at)
           VALUES (?1, ?2, ?3)"#,
        params![message_id, attachment_sha256, now],
    )?;
    if inserted == 0 {
        return Ok(());
    }

    let device_id = get_or_create_device_id(conn)?;
    let seq = next_device_seq(conn, &device_id)?;
    let op = serde_json::json!({
        "op_id": uuid::Uuid::new_v4().to_string(),
        "device_id": device_id,
        "seq": seq,
        "ts_ms": now,
        "type": "message.attachment.link.v1",
        "payload": {
            "message_id": message_id,
            "attachment_sha256": attachment_sha256,
            "created_at_ms": now,
        }
    });
    insert_oplog(conn, key, &op)?;

    // Best-effort: auto-enqueue content enrichment for URL manifests and document-like files.
    if let Ok(mime_type) = read_attachment_mime_type(conn, attachment_sha256) {
        let _ = maybe_auto_enqueue_content_enrichment_for_attachment(
            conn,
            attachment_sha256,
            &mime_type,
            now,
        );
    }
    Ok(())
}

fn sanitize_variant_id(raw: &str) -> String {
    let raw = raw.trim();
    if raw.is_empty() {
        return "variant".to_string();
    }
    let mut out = String::with_capacity(raw.len().min(64));
    for ch in raw.chars() {
        if out.len() >= 64 {
            break;
        }
        if ch.is_ascii_alphanumeric() || ch == '_' || ch == '-' {
            out.push(ch);
        } else {
            out.push('_');
        }
    }
    if out.is_empty() {
        "variant".to_string()
    } else {
        out
    }
}

pub fn upsert_attachment_variant(
    conn: &Connection,
    key: &[u8; 32],
    app_dir: &Path,
    attachment_sha256: &str,
    variant: &str,
    bytes: &[u8],
    mime_type: &str,
) -> Result<AttachmentVariant> {
    let variant = variant.trim();
    if variant.is_empty() {
        return Err(anyhow!("variant is required"));
    }

    let safe_variant = sanitize_variant_id(variant);
    let rel_dir = format!("attachments/variants/{attachment_sha256}");
    let rel_path = format!("{rel_dir}/{safe_variant}.bin");

    let full_dir = app_dir.join(&rel_dir);
    fs::create_dir_all(&full_dir)?;

    let full_path = full_dir.join(format!("{safe_variant}.bin"));
    let aad = format!("attachment.variant.bytes:{attachment_sha256}:{variant}");
    let blob = encrypt_bytes(key, bytes, aad.as_bytes())?;
    fs::write(&full_path, blob)?;

    let now = now_ms();
    conn.execute(
        r#"INSERT OR IGNORE INTO attachment_variants(
             attachment_sha256,
             variant,
             mime_type,
             path,
             byte_len,
             created_at
           ) VALUES (?1, ?2, ?3, ?4, ?5, ?6)"#,
        params![
            attachment_sha256,
            variant,
            mime_type,
            rel_path.as_str(),
            bytes.len() as i64,
            now
        ],
    )?;

    let (stored_mime_type, stored_path, stored_byte_len, stored_created_at_ms): (
        String,
        String,
        i64,
        i64,
    ) = conn.query_row(
        r#"SELECT mime_type, path, byte_len, created_at
           FROM attachment_variants
           WHERE attachment_sha256 = ?1 AND variant = ?2"#,
        params![attachment_sha256, variant],
        |row| Ok((row.get(0)?, row.get(1)?, row.get(2)?, row.get(3)?)),
    )?;

    Ok(AttachmentVariant {
        attachment_sha256: attachment_sha256.to_string(),
        variant: variant.to_string(),
        mime_type: stored_mime_type,
        path: stored_path,
        byte_len: stored_byte_len,
        created_at_ms: stored_created_at_ms,
    })
}

pub fn read_attachment_variant_bytes(
    conn: &Connection,
    key: &[u8; 32],
    app_dir: &Path,
    attachment_sha256: &str,
    variant: &str,
) -> Result<Vec<u8>> {
    let variant = variant.trim();
    if variant.is_empty() {
        return Err(anyhow!("variant is required"));
    }

    let stored_path: Option<String> = conn
        .query_row(
            r#"SELECT path
               FROM attachment_variants
               WHERE attachment_sha256 = ?1 AND variant = ?2"#,
            params![attachment_sha256, variant],
            |row| row.get(0),
        )
        .optional()?;
    let stored_path = stored_path.ok_or_else(|| anyhow!("attachment variant not found"))?;

    let blob = fs::read(app_dir.join(stored_path))?;
    let aad = format!("attachment.variant.bytes:{attachment_sha256}:{variant}");
    decrypt_bytes(key, &blob, aad.as_bytes())
}

pub fn enqueue_cloud_media_backup(
    conn: &Connection,
    attachment_sha256: &str,
    desired_variant: &str,
    now_ms: i64,
) -> Result<()> {
    let desired_variant = desired_variant.trim();
    if desired_variant.is_empty() {
        return Err(anyhow!("desired_variant is required"));
    }

    upsert_cloud_media_backup_row(conn, attachment_sha256, desired_variant, now_ms)?;
    Ok(())
}

fn upsert_cloud_media_backup_row(
    conn: &Connection,
    attachment_sha256: &str,
    desired_variant: &str,
    now_ms: i64,
) -> Result<u64> {
    let affected = conn.execute(
        r#"
INSERT INTO cloud_media_backup(
  attachment_sha256,
  desired_variant,
  status,
  attempts,
  next_retry_at,
  last_error,
  updated_at
)
VALUES (?1, ?2, 'pending', 0, NULL, NULL, ?3)
ON CONFLICT(attachment_sha256) DO UPDATE SET
  desired_variant = excluded.desired_variant,
  status = CASE
    WHEN cloud_media_backup.status = 'uploaded' THEN 'uploaded'
    ELSE 'pending'
  END,
  next_retry_at = NULL,
  last_error = NULL,
  updated_at = excluded.updated_at
"#,
        params![attachment_sha256, desired_variant, now_ms],
    )?;
    Ok(affected as u64)
}

fn prune_cloud_media_backup_rows_missing_local_bytes(conn: &Connection) -> Result<u64> {
    let Ok(app_dir) = app_dir_from_conn(conn) else {
        return Ok(0);
    };

    let mut stmt = conn.prepare(
        r#"
SELECT cmb.attachment_sha256, a.path
FROM cloud_media_backup cmb
LEFT JOIN attachments a ON a.sha256 = cmb.attachment_sha256
"#,
    )?;

    let mut rows = stmt.query([])?;
    let mut stale_attachment_sha256s = Vec::new();
    while let Some(row) = rows.next()? {
        let attachment_sha256: String = row.get(0)?;
        let path: Option<String> = row.get(1)?;
        let Some(path) = path else {
            stale_attachment_sha256s.push(attachment_sha256);
            continue;
        };

        if !app_dir.join(path).is_file() {
            stale_attachment_sha256s.push(attachment_sha256);
        }
    }

    let mut pruned = 0u64;
    for attachment_sha256 in stale_attachment_sha256s {
        pruned += conn.execute(
            r#"DELETE FROM cloud_media_backup WHERE attachment_sha256 = ?1"#,
            params![attachment_sha256],
        )? as u64;
    }
    Ok(pruned)
}

pub fn backfill_cloud_media_backup_images(
    conn: &Connection,
    desired_variant: &str,
    now_ms: i64,
) -> Result<u64> {
    let desired_variant = desired_variant.trim();
    if desired_variant.is_empty() {
        return Err(anyhow!("desired_variant is required"));
    }

    let _ = prune_cloud_media_backup_rows_missing_local_bytes(conn)?;

    let Ok(app_dir) = app_dir_from_conn(conn) else {
        return Ok(0);
    };

    let mut stmt = conn.prepare(
        r#"
SELECT sha256, path
FROM attachments
ORDER BY created_at ASC, sha256 ASC
"#,
    )?;

    let mut rows = stmt.query([])?;
    let mut affected = 0u64;
    while let Some(row) = rows.next()? {
        let attachment_sha256: String = row.get(0)?;
        let path: String = row.get(1)?;
        if !app_dir.join(path).is_file() {
            continue;
        }

        affected +=
            upsert_cloud_media_backup_row(conn, &attachment_sha256, desired_variant, now_ms)?;
    }

    Ok(affected)
}

pub fn list_due_cloud_media_backups(
    conn: &Connection,
    now_ms: i64,
    limit: i64,
) -> Result<Vec<CloudMediaBackup>> {
    let _ = prune_cloud_media_backup_rows_missing_local_bytes(conn)?;

    let limit = limit.clamp(1, 500);
    let mut stmt = conn.prepare(
        r#"
SELECT cmb.attachment_sha256,
       cmb.desired_variant,
       COALESCE(a.byte_len, 0) AS byte_len,
       cmb.status,
       cmb.attempts,
       cmb.next_retry_at,
       cmb.last_error,
       cmb.updated_at
FROM cloud_media_backup cmb
LEFT JOIN attachments a ON a.sha256 = cmb.attachment_sha256
WHERE status != 'uploaded'
  AND (next_retry_at IS NULL OR next_retry_at <= ?1)
ORDER BY cmb.updated_at ASC, cmb.attachment_sha256 ASC
LIMIT ?2
"#,
    )?;

    let mut rows = stmt.query(params![now_ms, limit])?;
    let mut result = Vec::new();
    while let Some(row) = rows.next()? {
        result.push(CloudMediaBackup {
            attachment_sha256: row.get(0)?,
            desired_variant: row.get(1)?,
            byte_len: row.get(2)?,
            status: row.get(3)?,
            attempts: row.get(4)?,
            next_retry_at_ms: row.get(5)?,
            last_error: row.get(6)?,
            updated_at_ms: row.get(7)?,
        });
    }
    Ok(result)
}

pub fn mark_cloud_media_backup_failed(
    conn: &Connection,
    attachment_sha256: &str,
    attempts: i64,
    next_retry_at_ms: i64,
    last_error: &str,
    now_ms: i64,
) -> Result<()> {
    conn.execute(
        r#"
UPDATE cloud_media_backup
SET status = 'failed',
    attempts = ?2,
    next_retry_at = ?3,
    last_error = ?4,
    updated_at = ?5
WHERE attachment_sha256 = ?1
"#,
        params![
            attachment_sha256,
            attempts,
            next_retry_at_ms,
            last_error,
            now_ms
        ],
    )?;
    Ok(())
}

pub fn mark_cloud_media_backup_uploaded(
    conn: &Connection,
    attachment_sha256: &str,
    now_ms: i64,
) -> Result<()> {
    conn.execute(
        r#"
UPDATE cloud_media_backup
SET status = 'uploaded',
    next_retry_at = NULL,
    last_error = NULL,
    updated_at = ?2
WHERE attachment_sha256 = ?1
"#,
        params![attachment_sha256, now_ms],
    )?;
    Ok(())
}

pub fn cloud_media_backup_summary(conn: &Connection) -> Result<CloudMediaBackupSummary> {
    let _ = prune_cloud_media_backup_rows_missing_local_bytes(conn)?;

    let mut pending = 0i64;
    let mut failed = 0i64;
    let mut uploaded = 0i64;

    let mut stmt =
        conn.prepare(r#"SELECT status, COUNT(*) FROM cloud_media_backup GROUP BY status"#)?;
    let mut rows = stmt.query([])?;
    while let Some(row) = rows.next()? {
        let status: String = row.get(0)?;
        let count: i64 = row.get(1)?;
        match status.as_str() {
            "pending" => pending = count,
            "failed" => failed = count,
            "uploaded" => uploaded = count,
            _ => {}
        }
    }

    let last_uploaded_at_ms: Option<i64> = conn
        .query_row(
            r#"SELECT MAX(updated_at) FROM cloud_media_backup WHERE status = 'uploaded'"#,
            [],
            |row| row.get(0),
        )
        .optional()?
        .flatten();

    let (last_error, last_error_at_ms): (Option<String>, Option<i64>) = conn
        .query_row(
            r#"
SELECT last_error, updated_at
FROM cloud_media_backup
WHERE last_error IS NOT NULL
ORDER BY updated_at DESC
LIMIT 1
"#,
            [],
            |row| Ok((row.get(0)?, row.get(1)?)),
        )
        .optional()?
        .unwrap_or((None, None));

    Ok(CloudMediaBackupSummary {
        pending,
        failed,
        uploaded,
        last_uploaded_at_ms,
        last_error,
        last_error_at_ms,
    })
}

pub fn list_message_attachments(
    conn: &Connection,
    _key: &[u8; 32],
    message_id: &str,
) -> Result<Vec<Attachment>> {
    let mut stmt = conn.prepare(
        r#"
SELECT a.sha256, a.mime_type, a.path, a.byte_len, a.created_at
FROM attachments a
JOIN message_attachments ma ON ma.attachment_sha256 = a.sha256
WHERE ma.message_id = ?1
ORDER BY a.created_at ASC, a.sha256 ASC
"#,
    )?;

    let mut rows = stmt.query(params![message_id])?;
    let mut result = Vec::new();
    while let Some(row) = rows.next()? {
        result.push(Attachment {
            sha256: row.get(0)?,
            mime_type: row.get(1)?,
            path: row.get(2)?,
            byte_len: row.get(3)?,
            created_at_ms: row.get(4)?,
        });
    }
    Ok(result)
}

pub fn list_recent_attachments(
    conn: &Connection,
    _key: &[u8; 32],
    limit: i64,
) -> Result<Vec<Attachment>> {
    let limit = limit.clamp(1, 500);
    let mut stmt = conn.prepare(
        r#"
SELECT sha256, mime_type, path, byte_len, created_at
FROM attachments
ORDER BY created_at DESC, sha256 DESC
LIMIT ?1
"#,
    )?;

    let mut rows = stmt.query(params![limit])?;
    let mut result = Vec::new();
    while let Some(row) = rows.next()? {
        result.push(Attachment {
            sha256: row.get(0)?,
            mime_type: row.get(1)?,
            path: row.get(2)?,
            byte_len: row.get(3)?,
            created_at_ms: row.get(4)?,
        });
    }
    Ok(result)
}
