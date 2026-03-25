pub const TODO_FOLLOWUP_SUGGESTION_STATE_PENDING: &str = "pending";
pub const TODO_FOLLOWUP_SUGGESTION_STATE_APPLIED: &str = "applied";
pub const TODO_FOLLOWUP_SUGGESTION_STATE_DISMISSED: &str = "dismissed";

type TodoFollowupSuggestionRow = (
    String,
    Vec<u8>,
    String,
    String,
    String,
    Option<String>,
    Option<String>,
    i64,
    i64,
    Option<i64>,
    Option<String>,
);

fn todo_followup_suggestion_content_aad(id: &str) -> Vec<u8> {
    format!("todo_followup_suggestion.content:{id}").into_bytes()
}

fn normalize_todo_followup_suggestion_citations_json(citations_json: Option<&str>) -> Option<String> {
    citations_json
        .map(|value| value.trim().to_string())
        .filter(|value| !value.is_empty())
}

fn find_todo_followup_suggestion_by_id(
    conn: &Connection,
    key: &[u8; 32],
    id: &str,
) -> Result<Option<TodoFollowupSuggestion>> {
    let row: Option<TodoFollowupSuggestionRow> = conn
        .query_row(
            r#"
SELECT todo_id, content, state, source, generation_mode, generation_key, citations_json, created_at_ms, updated_at_ms, dismissed_at_ms, applied_activity_id
FROM todo_followup_suggestions
WHERE id = ?1
"#,
            params![id],
            |row| {
                Ok((
                    row.get(0)?,
                    row.get(1)?,
                    row.get(2)?,
                    row.get(3)?,
                    row.get(4)?,
                    row.get(5)?,
                    row.get(6)?,
                    row.get(7)?,
                    row.get(8)?,
                    row.get(9)?,
                    row.get(10)?,
                ))
            },
        )
        .optional()?;

    let Some((
        todo_id,
        content_blob,
        state,
        source,
        generation_mode,
        generation_key,
        citations_json,
        created_at_ms,
        updated_at_ms,
        dismissed_at_ms,
        applied_activity_id,
    )) = row
    else {
        return Ok(None);
    };

    let content_bytes = decrypt_bytes(key, &content_blob, &todo_followup_suggestion_content_aad(id))?;
    let content = String::from_utf8(content_bytes)
        .map_err(|_| anyhow!("todo followup suggestion content is not valid utf-8"))?;

    Ok(Some(TodoFollowupSuggestion {
        id: id.to_string(),
        todo_id,
        content,
        state,
        source,
        generation_mode,
        generation_key,
        citations_json,
        created_at_ms,
        updated_at_ms,
        dismissed_at_ms,
        applied_activity_id,
    }))
}

fn get_todo_followup_suggestion_by_id(
    conn: &Connection,
    key: &[u8; 32],
    id: &str,
) -> Result<TodoFollowupSuggestion> {
    find_todo_followup_suggestion_by_id(conn, key, id)?
        .ok_or_else(|| anyhow!("get todo followup suggestion failed: Query returned no rows"))
}

pub fn list_todo_followup_suggestions(
    conn: &Connection,
    key: &[u8; 32],
    todo_id: &str,
) -> Result<Vec<TodoFollowupSuggestion>> {
    let mut stmt = conn.prepare(
        r#"
SELECT id, content, state, source, generation_mode, generation_key, citations_json, created_at_ms, updated_at_ms, dismissed_at_ms, applied_activity_id
FROM todo_followup_suggestions
WHERE todo_id = ?1
ORDER BY created_at_ms ASC, id ASC
"#,
    )?;

    let mut rows = stmt.query(params![todo_id])?;
    let mut result = Vec::new();
    while let Some(row) = rows.next()? {
        let id: String = row.get(0)?;
        let content_blob: Vec<u8> = row.get(1)?;
        let state: String = row.get(2)?;
        let source: String = row.get(3)?;
        let generation_mode: String = row.get(4)?;
        let generation_key: Option<String> = row.get(5)?;
        let citations_json: Option<String> = row.get(6)?;
        let created_at_ms: i64 = row.get(7)?;
        let updated_at_ms: i64 = row.get(8)?;
        let dismissed_at_ms: Option<i64> = row.get(9)?;
        let applied_activity_id: Option<String> = row.get(10)?;
        let content_bytes = decrypt_bytes(
            key,
            &content_blob,
            &todo_followup_suggestion_content_aad(&id),
        )?;
        let content = String::from_utf8(content_bytes)
            .map_err(|_| anyhow!("todo followup suggestion content is not valid utf-8"))?;

        result.push(TodoFollowupSuggestion {
            id,
            todo_id: todo_id.to_string(),
            content,
            state,
            source,
            generation_mode,
            generation_key,
            citations_json,
            created_at_ms,
            updated_at_ms,
            dismissed_at_ms,
            applied_activity_id,
        });
    }

    Ok(result)
}

fn create_todo_followup_information_activity_with_device_id(
    conn: &Connection,
    key: &[u8; 32],
    todo_id: &str,
    content: &str,
    device_id: &str,
) -> Result<TodoActivity> {
    let id = uuid::Uuid::new_v4().to_string();
    let now = now_ms();
    let aad = format!("todo_activity.content:{id}");
    let content_blob = encrypt_bytes(key, content.as_bytes(), aad.as_bytes())?;

    conn.execute(
        r#"
INSERT INTO todo_activities(
  id, todo_id, type, from_status, to_status, content, source_message_id, created_at_ms, needs_embedding
)
VALUES (?1, ?2, 'followup_information', NULL, NULL, ?3, NULL, ?4, 1)
"#,
        params![id, todo_id, content_blob, now],
    )?;
    conn.execute(
        r#"
UPDATE todos
SET updated_at_ms = MAX(?2, updated_at_ms + 1)
WHERE id = ?1
"#,
        params![todo_id, now],
    )?;

    let activity = get_todo_activity_by_id(conn, key, &id)?;

    let seq = next_device_seq(conn, device_id)?;
    let op = serde_json::json!({
        "op_id": uuid::Uuid::new_v4().to_string(),
        "device_id": device_id,
        "seq": seq,
        "ts_ms": now,
        "type": "todo.activity.append.v1",
        "payload": {
            "activity_id": activity.id.as_str(),
            "todo_id": activity.todo_id.as_str(),
            "activity_type": activity.activity_type.as_str(),
            "from_status": activity.from_status.as_deref(),
            "to_status": activity.to_status.as_deref(),
            "content": activity.content.as_deref(),
            "source_message_id": activity.source_message_id.as_deref(),
            "created_at_ms": activity.created_at_ms,
        }
    });
    insert_oplog(conn, key, &op)?;

    Ok(activity)
}

pub fn upsert_generated_todo_followup_suggestions(
    conn: &Connection,
    key: &[u8; 32],
    todo_id: &str,
    suggestions: &[TodoFollowupSuggestionDraftInput],
    source: &str,
    generation_key: Option<&str>,
) -> Result<Vec<TodoFollowupSuggestion>> {
    run_immediate_transaction(conn, || {
        let existing = list_todo_followup_suggestions(conn, key, todo_id)?;
        let now = now_ms();
        let device_id = get_or_create_device_id(conn)?;
        let mut pending_candidates_by_normalized = existing
            .iter()
            .filter(|item| item.state == TODO_FOLLOWUP_SUGGESTION_STATE_PENDING)
            .fold(
                std::collections::HashMap::<String, Vec<TodoFollowupSuggestion>>::new(),
                |mut acc, item| {
                    let normalized = normalize_checklist_suggestion_content(&item.content);
                    if !normalized.is_empty() {
                        acc.entry(normalized).or_default().push(item.clone());
                    }
                    acc
                },
            );
        let mut pending_by_normalized = std::collections::HashMap::new();

        for (normalized, mut items) in pending_candidates_by_normalized.drain() {
            let canonical = items.remove(0);
            let duplicate_ids = items
                .into_iter()
                .map(|item| item.id)
                .collect::<Vec<_>>();
            if !duplicate_ids.is_empty() {
                dismiss_todo_followup_suggestions_inner(
                    conn,
                    key,
                    todo_id,
                    &duplicate_ids,
                    now,
                    &device_id,
                )?;
            }
            pending_by_normalized.insert(normalized, canonical);
        }

        let mut created = Vec::new();

        for draft in suggestions {
            let trimmed = draft.content.trim();
            if trimmed.is_empty() {
                continue;
            }
            let normalized = normalize_checklist_suggestion_content(trimmed);
            if normalized.is_empty() {
                continue;
            }

            if let Some(existing_pending) = pending_by_normalized.get(&normalized).cloned() {
                let content_blob = encrypt_bytes(
                    key,
                    trimmed.as_bytes(),
                    &todo_followup_suggestion_content_aad(&existing_pending.id),
                )?;
                let normalized_citations_json =
                    normalize_todo_followup_suggestion_citations_json(draft.citations_json.as_deref());
                conn.execute(
                    r#"
UPDATE todo_followup_suggestions
SET content = ?2,
    source = ?3,
    generation_mode = ?4,
    generation_key = ?5,
    citations_json = ?6,
    updated_at_ms = ?7
WHERE id = ?1
"#,
                    params![
                        existing_pending.id,
                        content_blob,
                        source,
                        draft.generation_mode.trim(),
                        generation_key,
                        normalized_citations_json,
                        now,
                    ],
                )?;

                let suggestion =
                    get_todo_followup_suggestion_by_id(conn, key, &existing_pending.id)?;
                let seq = next_device_seq(conn, &device_id)?;
                let op = serde_json::json!({
                    "op_id": uuid::Uuid::new_v4().to_string(),
                    "device_id": device_id,
                    "seq": seq,
                    "ts_ms": now,
                    "type": "todo.followup_suggestion.upsert.v1",
                    "payload": {
                        "suggestion_id": suggestion.id.as_str(),
                        "todo_id": suggestion.todo_id.as_str(),
                        "content": suggestion.content.as_str(),
                        "state": suggestion.state.as_str(),
                        "source": suggestion.source.as_str(),
                        "generation_mode": suggestion.generation_mode.as_str(),
                        "generation_key": suggestion.generation_key.as_deref(),
                        "citations_json": suggestion.citations_json.as_deref(),
                        "created_at_ms": suggestion.created_at_ms,
                        "updated_at_ms": suggestion.updated_at_ms,
                        "dismissed_at_ms": suggestion.dismissed_at_ms,
                        "applied_activity_id": suggestion.applied_activity_id.as_deref(),
                    }
                });
                insert_oplog(conn, key, &op)?;
                pending_by_normalized.insert(normalized, suggestion.clone());
                created.push(suggestion);
                continue;
            }

            let id = uuid::Uuid::new_v4().to_string();
            let content_blob =
                encrypt_bytes(key, trimmed.as_bytes(), &todo_followup_suggestion_content_aad(&id))?;
            let normalized_citations_json =
                normalize_todo_followup_suggestion_citations_json(draft.citations_json.as_deref());
            conn.execute(
                r#"
INSERT INTO todo_followup_suggestions(
  id, todo_id, content, state, source, generation_mode, generation_key, citations_json, created_at_ms, updated_at_ms, dismissed_at_ms, applied_activity_id
) VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, NULL, NULL)
"#,
                params![
                    id,
                    todo_id,
                    content_blob,
                    TODO_FOLLOWUP_SUGGESTION_STATE_PENDING,
                    source,
                    draft.generation_mode,
                    generation_key,
                    normalized_citations_json,
                    now,
                    now,
                ],
            )?;
            let suggestion = get_todo_followup_suggestion_by_id(conn, key, &id)?;

            let seq = next_device_seq(conn, &device_id)?;
            let op = serde_json::json!({
                "op_id": uuid::Uuid::new_v4().to_string(),
                "device_id": device_id,
                "seq": seq,
                "ts_ms": now,
                "type": "todo.followup_suggestion.upsert.v1",
                "payload": {
                    "suggestion_id": suggestion.id.as_str(),
                    "todo_id": suggestion.todo_id.as_str(),
                    "content": suggestion.content.as_str(),
                    "state": suggestion.state.as_str(),
                    "source": suggestion.source.as_str(),
                    "generation_mode": suggestion.generation_mode.as_str(),
                    "generation_key": suggestion.generation_key.as_deref(),
                    "citations_json": suggestion.citations_json.as_deref(),
                    "created_at_ms": suggestion.created_at_ms,
                    "updated_at_ms": suggestion.updated_at_ms,
                    "dismissed_at_ms": suggestion.dismissed_at_ms,
                    "applied_activity_id": suggestion.applied_activity_id.as_deref(),
                }
            });
            insert_oplog(conn, key, &op)?;
            pending_by_normalized.insert(normalized, suggestion.clone());
            created.push(suggestion);
        }

        Ok(created)
    })
}

pub fn upsert_generated_todo_followup_suggestions_if_current_claim(
    conn: &Connection,
    key: &[u8; 32],
    todo_id: &str,
    job_started_at_ms: i64,
    suggestions: &[TodoFollowupSuggestionDraftInput],
    source: &str,
    generation_key: Option<&str>,
) -> Result<bool> {
    run_immediate_transaction(conn, || {
        let Some(job) = crate::db::find_todo_followup_generation_job(conn, todo_id)? else {
            return Ok(false);
        };
        if job.status != crate::db::TODO_FOLLOWUP_GENERATION_JOB_STATUS_RUNNING
            || job.updated_at_ms != job_started_at_ms
        {
            return Ok(false);
        }

        upsert_generated_todo_followup_suggestions(
            conn,
            key,
            todo_id,
            suggestions,
            source,
            generation_key,
        )?;
        Ok(true)
    })
}

pub fn apply_todo_followup_suggestions(
    conn: &Connection,
    key: &[u8; 32],
    todo_id: &str,
    suggestion_ids: &[String],
) -> Result<Vec<TodoActivity>> {
    run_immediate_transaction(conn, || {
        let device_id = get_or_create_device_id(conn)?;
        let mut created = Vec::new();
        let now = now_ms();

        for suggestion_id in suggestion_ids {
            let Some(suggestion) = find_todo_followup_suggestion_by_id(conn, key, suggestion_id)?
            else {
                continue;
            };
            if suggestion.todo_id != todo_id || suggestion.state != TODO_FOLLOWUP_SUGGESTION_STATE_PENDING {
                continue;
            }

            let activity = create_todo_followup_information_activity_with_device_id(
                conn,
                key,
                todo_id,
                &suggestion.content,
                &device_id,
            )?;

            conn.execute(
                r#"UPDATE todo_followup_suggestions SET state = ?2, updated_at_ms = ?3, applied_activity_id = ?4 WHERE id = ?1"#,
                params![
                    suggestion_id,
                    TODO_FOLLOWUP_SUGGESTION_STATE_APPLIED,
                    now,
                    activity.id,
                ],
            )?;

            let seq = next_device_seq(conn, &device_id)?;
            let op = serde_json::json!({
                "op_id": uuid::Uuid::new_v4().to_string(),
                "device_id": device_id,
                "seq": seq,
                "ts_ms": now,
                "type": "todo.followup_suggestion.apply.v1",
                "payload": {
                    "suggestion_id": suggestion_id,
                    "todo_id": todo_id,
                    "applied_activity_id": activity.id.as_str(),
                    "updated_at_ms": now,
                }
            });
            insert_oplog(conn, key, &op)?;
            created.push(activity);
        }

        Ok(created)
    })
}

pub fn dismiss_todo_followup_suggestions(
    conn: &Connection,
    key: &[u8; 32],
    todo_id: &str,
    suggestion_ids: &[String],
) -> Result<()> {
    run_immediate_transaction(conn, || {
        let now = now_ms();
        let device_id = get_or_create_device_id(conn)?;
        dismiss_todo_followup_suggestions_inner(
            conn,
            key,
            todo_id,
            suggestion_ids,
            now,
            &device_id,
        )
    })
}

pub fn dismiss_all_todo_followup_suggestions(
    conn: &Connection,
    key: &[u8; 32],
    todo_id: &str,
) -> Result<()> {
    run_immediate_transaction(conn, || {
        let mut stmt = conn.prepare(
            r#"SELECT id FROM todo_followup_suggestions WHERE todo_id = ?1 AND state = ?2"#,
        )?;
        let pending_ids = stmt
            .query_map(
                params![todo_id, TODO_FOLLOWUP_SUGGESTION_STATE_PENDING],
                |row| row.get::<_, String>(0),
            )?
            .collect::<rusqlite::Result<Vec<_>>>()?;
        let now = now_ms();
        let device_id = get_or_create_device_id(conn)?;
        dismiss_todo_followup_suggestions_inner(
            conn,
            key,
            todo_id,
            &pending_ids,
            now,
            &device_id,
        )
    })
}

fn dismiss_todo_followup_suggestions_inner(
    conn: &Connection,
    key: &[u8; 32],
    todo_id: &str,
    suggestion_ids: &[String],
    now: i64,
    device_id: &str,
) -> Result<()> {
    for suggestion_id in suggestion_ids {
        let rows_changed = conn.execute(
            r#"
UPDATE todo_followup_suggestions
SET state = ?2, updated_at_ms = ?3, dismissed_at_ms = ?4
WHERE id = ?1 AND todo_id = ?5 AND state = ?6
"#,
            params![
                suggestion_id,
                TODO_FOLLOWUP_SUGGESTION_STATE_DISMISSED,
                now,
                now,
                todo_id,
                TODO_FOLLOWUP_SUGGESTION_STATE_PENDING,
            ],
        )?;
        if rows_changed == 0 {
            continue;
        }

        let seq = next_device_seq(conn, device_id)?;
        let op = serde_json::json!({
            "op_id": uuid::Uuid::new_v4().to_string(),
            "device_id": device_id,
            "seq": seq,
            "ts_ms": now,
            "type": "todo.followup_suggestion.dismiss.v1",
            "payload": {
                "suggestion_id": suggestion_id,
                "todo_id": todo_id,
                "dismissed_at_ms": now,
            }
        });
        insert_oplog(conn, key, &op)?;
    }

    Ok(())
}
