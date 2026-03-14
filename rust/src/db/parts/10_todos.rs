#[allow(clippy::type_complexity)]
fn get_todo_by_id(conn: &Connection, key: &[u8; 32], id: &str) -> Result<Todo> {
    let (
        title_blob,
        due_at_ms,
        status,
        source_entry_id,
        created_at_ms,
        updated_at_ms,
        review_stage,
        next_review_at_ms,
        last_review_at_ms,
    ): (Vec<u8>, Option<i64>, String, Option<String>, i64, i64, Option<i64>, Option<i64>, Option<i64>) = conn
        .query_row(
            r#"
SELECT title, due_at_ms, status, source_entry_id, created_at_ms, updated_at_ms, review_stage, next_review_at_ms, last_review_at_ms
FROM todos
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
                ))
            },
        )
        .map_err(|e| anyhow!("get todo failed: {e}"))?;

    let title_bytes = decrypt_bytes(key, &title_blob, b"todo.title")?;
    let title =
        String::from_utf8(title_bytes).map_err(|_| anyhow!("todo title is not valid utf-8"))?;

    Ok(Todo {
        id: id.to_string(),
        title,
        due_at_ms,
        status,
        source_entry_id,
        created_at_ms,
        updated_at_ms,
        review_stage,
        next_review_at_ms,
        last_review_at_ms,
    })
}

pub fn get_todo(conn: &Connection, key: &[u8; 32], id: &str) -> Result<Todo> {
    get_todo_by_id(conn, key, id)
}

#[allow(clippy::too_many_arguments)]
pub fn upsert_todo(
    conn: &Connection,
    key: &[u8; 32],
    id: &str,
    title: &str,
    due_at_ms: Option<i64>,
    status: &str,
    source_entry_id: Option<&str>,
    review_stage: Option<i64>,
    next_review_at_ms: Option<i64>,
    last_review_at_ms: Option<i64>,
) -> Result<Todo> {
    let now = now_ms();

    let (existing_title, existing_status, existing_due_at_ms, existing_needs_embedding): (
        Option<String>,
        Option<String>,
        Option<i64>,
        i64,
    ) = {
        type ExistingTodoRow = (Vec<u8>, String, Option<i64>, Option<i64>);

        let row: Option<ExistingTodoRow> = conn
            .query_row(
                r#"SELECT title, status, due_at_ms, needs_embedding FROM todos WHERE id = ?1"#,
                params![id],
                |row| Ok((row.get(0)?, row.get(1)?, row.get(2)?, row.get(3)?)),
            )
            .optional()?;
        if let Some((title_blob, status, due_at_ms, needs_embedding)) = row {
            let title_bytes = decrypt_bytes(key, &title_blob, b"todo.title")?;
            let title = String::from_utf8(title_bytes)
                .map_err(|_| anyhow!("todo title is not valid utf-8"))?;
            (
                Some(title),
                Some(status),
                due_at_ms,
                needs_embedding.unwrap_or(0),
            )
        } else {
            (None, None, None, 0)
        }
    };

    let needs_embedding = if existing_title.as_deref() != Some(title)
        || existing_status.as_deref() != Some(status)
        || existing_due_at_ms != due_at_ms
    {
        1i64
    } else {
        existing_needs_embedding
    };

    let title_blob = encrypt_bytes(key, title.as_bytes(), b"todo.title")?;
    conn.execute(
        r#"
INSERT INTO todos (
  id, title, due_at_ms, status, source_entry_id, created_at_ms, updated_at_ms, review_stage, next_review_at_ms, last_review_at_ms, needs_embedding
)
VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?11)
ON CONFLICT(id) DO UPDATE SET
  title = excluded.title,
  due_at_ms = excluded.due_at_ms,
  status = excluded.status,
  source_entry_id = excluded.source_entry_id,
  updated_at_ms = excluded.updated_at_ms,
  review_stage = excluded.review_stage,
  next_review_at_ms = excluded.next_review_at_ms,
  last_review_at_ms = excluded.last_review_at_ms,
  needs_embedding = excluded.needs_embedding
"#,
        params![
            id,
            title_blob,
            due_at_ms,
            status,
            source_entry_id,
            now,
            now,
            review_stage,
            next_review_at_ms,
            last_review_at_ms,
            needs_embedding,
        ],
    )?;

    let todo = get_todo_by_id(conn, key, id)?;

    let device_id = get_or_create_device_id(conn)?;
    let seq = next_device_seq(conn, &device_id)?;
    let op = serde_json::json!({
        "op_id": uuid::Uuid::new_v4().to_string(),
        "device_id": device_id,
        "seq": seq,
        "ts_ms": now,
        "type": "todo.upsert.v1",
        "payload": {
            "todo_id": todo.id.as_str(),
            "title": todo.title.as_str(),
            "due_at_ms": todo.due_at_ms,
            "status": todo.status.as_str(),
            "source_entry_id": todo.source_entry_id.as_deref(),
            "created_at_ms": todo.created_at_ms,
            "updated_at_ms": todo.updated_at_ms,
            "review_stage": todo.review_stage,
            "next_review_at_ms": todo.next_review_at_ms,
            "last_review_at_ms": todo.last_review_at_ms,
        }
    });
    insert_oplog(conn, key, &op)?;

    Ok(todo)
}

pub fn list_todos(conn: &Connection, key: &[u8; 32]) -> Result<Vec<Todo>> {
    let mut stmt = conn.prepare(
        r#"
SELECT id, title, due_at_ms, status, source_entry_id, created_at_ms, updated_at_ms, review_stage, next_review_at_ms, last_review_at_ms
FROM todos
ORDER BY COALESCE(due_at_ms, 9223372036854775807) ASC, created_at_ms ASC
"#,
    )?;

    let mut rows = stmt.query([])?;
    let mut result = Vec::new();
    while let Some(row) = rows.next()? {
        let id: String = row.get(0)?;
        let title_blob: Vec<u8> = row.get(1)?;
        let due_at_ms: Option<i64> = row.get(2)?;
        let status: String = row.get(3)?;
        let source_entry_id: Option<String> = row.get(4)?;
        let created_at_ms: i64 = row.get(5)?;
        let updated_at_ms: i64 = row.get(6)?;
        let review_stage: Option<i64> = row.get(7)?;
        let next_review_at_ms: Option<i64> = row.get(8)?;
        let last_review_at_ms: Option<i64> = row.get(9)?;

        let title_bytes = decrypt_bytes(key, &title_blob, b"todo.title")?;
        let title =
            String::from_utf8(title_bytes).map_err(|_| anyhow!("todo title is not valid utf-8"))?;

        result.push(Todo {
            id,
            title,
            due_at_ms,
            status,
            source_entry_id,
            created_at_ms,
            updated_at_ms,
            review_stage,
            next_review_at_ms,
            last_review_at_ms,
        });
    }
    Ok(result)
}

fn todo_checklist_item_content_aad(id: &str) -> Vec<u8> {
    format!("todo_checklist_item.content:{id}").into_bytes()
}

fn get_todo_checklist_item_by_id(
    conn: &Connection,
    key: &[u8; 32],
    id: &str,
) -> Result<TodoChecklistItem> {
    let (todo_id, content_blob, is_done, sort_order, created_at_ms, updated_at_ms): (
        String,
        Vec<u8>,
        i64,
        i64,
        i64,
        i64,
    ) = conn
        .query_row(
            r#"
SELECT todo_id, content, is_done, sort_order, created_at_ms, updated_at_ms
FROM todo_checklist_items
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
                ))
            },
        )
        .map_err(|e| anyhow!("get todo checklist item failed: {e}"))?;

    let content_bytes = decrypt_bytes(key, &content_blob, &todo_checklist_item_content_aad(id))?;
    let content = String::from_utf8(content_bytes)
        .map_err(|_| anyhow!("todo checklist item content is not valid utf-8"))?;

    Ok(TodoChecklistItem {
        id: id.to_string(),
        todo_id,
        content,
        is_done: is_done != 0,
        sort_order,
        created_at_ms,
        updated_at_ms,
    })
}

pub fn list_todo_checklist_items(
    conn: &Connection,
    key: &[u8; 32],
    todo_id: &str,
) -> Result<Vec<TodoChecklistItem>> {
    let mut stmt = conn.prepare(
        r#"
SELECT id, content, is_done, sort_order, created_at_ms, updated_at_ms
FROM todo_checklist_items
WHERE todo_id = ?1
ORDER BY sort_order ASC, created_at_ms ASC, id ASC
"#,
    )?;

    let mut rows = stmt.query(params![todo_id])?;
    let mut result = Vec::new();
    while let Some(row) = rows.next()? {
        let id: String = row.get(0)?;
        let content_blob: Vec<u8> = row.get(1)?;
        let is_done: i64 = row.get(2)?;
        let sort_order: i64 = row.get(3)?;
        let created_at_ms: i64 = row.get(4)?;
        let updated_at_ms: i64 = row.get(5)?;
        let content_bytes = decrypt_bytes(key, &content_blob, &todo_checklist_item_content_aad(&id))?;
        let content = String::from_utf8(content_bytes)
            .map_err(|_| anyhow!("todo checklist item content is not valid utf-8"))?;

        result.push(TodoChecklistItem {
            id,
            todo_id: todo_id.to_string(),
            content,
            is_done: is_done != 0,
            sort_order,
            created_at_ms,
            updated_at_ms,
        });
    }

    Ok(result)
}

fn run_immediate_transaction<T, F>(conn: &Connection, run_body: F) -> Result<T>
where
    F: FnOnce() -> Result<T>,
{
    if !conn.is_autocommit() {
        return run_body();
    }

    conn.execute_batch("BEGIN IMMEDIATE;")?;
    let result = run_body();
    match result {
        Ok(value) => {
            conn.execute_batch("COMMIT;")?;
            Ok(value)
        }
        Err(err) => {
            let _ = conn.execute_batch("ROLLBACK;");
            Err(err)
        }
    }
}

pub fn create_todo_checklist_item(
    conn: &Connection,
    key: &[u8; 32],
    todo_id: &str,
    content: &str,
) -> Result<TodoChecklistItem> {
    run_immediate_transaction(conn, || {
        let id = uuid::Uuid::new_v4().to_string();
        let now = now_ms();
        let sort_order: i64 = conn.query_row(
            r#"SELECT COALESCE(MAX(sort_order), -1) + 1 FROM todo_checklist_items WHERE todo_id = ?1"#,
            params![todo_id],
            |row| row.get(0),
        )?;
        let content_blob = encrypt_bytes(key, content.as_bytes(), &todo_checklist_item_content_aad(&id))?;

        conn.execute(
            r#"
INSERT INTO todo_checklist_items(id, todo_id, content, is_done, sort_order, created_at_ms, updated_at_ms)
VALUES (?1, ?2, ?3, 0, ?4, ?5, ?6)
"#,
            params![id, todo_id, content_blob, sort_order, now, now],
        )?;

        let item = get_todo_checklist_item_by_id(conn, key, &id)?;

        let device_id = get_or_create_device_id(conn)?;
        let seq = next_device_seq(conn, &device_id)?;
        let op = serde_json::json!({
            "op_id": uuid::Uuid::new_v4().to_string(),
            "device_id": device_id,
            "seq": seq,
            "ts_ms": now,
            "type": "todo.checklist_item.upsert.v1",
            "payload": {
                "item_id": item.id.as_str(),
                "todo_id": item.todo_id.as_str(),
                "content": item.content.as_str(),
                "is_done": item.is_done,
                "sort_order": item.sort_order,
                "created_at_ms": item.created_at_ms,
                "updated_at_ms": item.updated_at_ms,
            }
        });
        insert_oplog(conn, key, &op)?;

        Ok(item)
    })
}

pub fn update_todo_checklist_item_content(
    conn: &Connection,
    key: &[u8; 32],
    item_id: &str,
    content: &str,
) -> Result<TodoChecklistItem> {
    run_immediate_transaction(conn, || {
        let existing = get_todo_checklist_item_by_id(conn, key, item_id)?;
        if existing.content == content {
            return Ok(existing);
        }

        let now = now_ms();
        let content_blob = encrypt_bytes(key, content.as_bytes(), &todo_checklist_item_content_aad(item_id))?;
        conn.execute(
            r#"UPDATE todo_checklist_items SET content = ?2, updated_at_ms = ?3 WHERE id = ?1"#,
            params![item_id, content_blob, now],
        )?;
        let updated = get_todo_checklist_item_by_id(conn, key, item_id)?;

        let device_id = get_or_create_device_id(conn)?;
        let seq = next_device_seq(conn, &device_id)?;
        let op = serde_json::json!({
            "op_id": uuid::Uuid::new_v4().to_string(),
            "device_id": device_id,
            "seq": seq,
            "ts_ms": now,
            "type": "todo.checklist_item.upsert.v1",
            "payload": {
                "item_id": updated.id.as_str(),
                "todo_id": updated.todo_id.as_str(),
                "content": updated.content.as_str(),
                "is_done": updated.is_done,
                "sort_order": updated.sort_order,
                "created_at_ms": updated.created_at_ms,
                "updated_at_ms": updated.updated_at_ms,
            }
        });
        insert_oplog(conn, key, &op)?;

        Ok(updated)
    })
}

pub fn set_todo_checklist_item_done(
    conn: &Connection,
    key: &[u8; 32],
    item_id: &str,
    is_done: bool,
) -> Result<TodoChecklistItem> {
    run_immediate_transaction(conn, || {
        let existing = get_todo_checklist_item_by_id(conn, key, item_id)?;
        if existing.is_done == is_done {
            return Ok(existing);
        }

        let now = now_ms();
        conn.execute(
            r#"UPDATE todo_checklist_items SET is_done = ?2, updated_at_ms = ?3 WHERE id = ?1"#,
            params![item_id, if is_done { 1 } else { 0 }, now],
        )?;
        let updated = get_todo_checklist_item_by_id(conn, key, item_id)?;

        let device_id = get_or_create_device_id(conn)?;
        let seq = next_device_seq(conn, &device_id)?;
        let op = serde_json::json!({
            "op_id": uuid::Uuid::new_v4().to_string(),
            "device_id": device_id,
            "seq": seq,
            "ts_ms": now,
            "type": "todo.checklist_item.upsert.v1",
            "payload": {
                "item_id": updated.id.as_str(),
                "todo_id": updated.todo_id.as_str(),
                "content": updated.content.as_str(),
                "is_done": updated.is_done,
                "sort_order": updated.sort_order,
                "created_at_ms": updated.created_at_ms,
                "updated_at_ms": updated.updated_at_ms,
            }
        });
        insert_oplog(conn, key, &op)?;

        Ok(updated)
    })
}

pub fn delete_todo_checklist_item(
    conn: &Connection,
    key: &[u8; 32],
    item_id: &str,
) -> Result<()> {
    run_immediate_transaction(conn, || {
        let existing = get_todo_checklist_item_by_id(conn, key, item_id)?;
        let now = now_ms();
        conn.execute(r#"DELETE FROM todo_checklist_items WHERE id = ?1"#, params![item_id])?;

        let device_id = get_or_create_device_id(conn)?;
        let seq = next_device_seq(conn, &device_id)?;
        let op = serde_json::json!({
            "op_id": uuid::Uuid::new_v4().to_string(),
            "device_id": device_id,
            "seq": seq,
            "ts_ms": now,
            "type": "todo.checklist_item.delete.v1",
            "payload": {
                "item_id": existing.id.as_str(),
                "todo_id": existing.todo_id.as_str(),
                "deleted_at_ms": now,
            }
        });
        insert_oplog(conn, key, &op)?;

        Ok(())
    })
}

pub fn reorder_todo_checklist_items(
    conn: &Connection,
    key: &[u8; 32],
    todo_id: &str,
    ordered_item_ids: &[String],
) -> Result<()> {
    if ordered_item_ids.is_empty() {
        return Ok(());
    }
    run_immediate_transaction(conn, || {
        let now = now_ms();
        for (index, item_id) in ordered_item_ids.iter().enumerate() {
            let rows_changed = conn.execute(
                r#"UPDATE todo_checklist_items SET sort_order = ?2, updated_at_ms = ?3 WHERE id = ?1 AND todo_id = ?4"#,
                params![item_id, index as i64, now, todo_id],
            )?;
            if rows_changed == 0 {
                return Err(anyhow!(
                    "reorder todo checklist item failed: {item_id} does not belong to {todo_id}"
                ));
            }
        }

        let device_id = get_or_create_device_id(conn)?;
        let seq = next_device_seq(conn, &device_id)?;
        let op = serde_json::json!({
            "op_id": uuid::Uuid::new_v4().to_string(),
            "device_id": device_id,
            "seq": seq,
            "ts_ms": now,
            "type": "todo.checklist_item.reorder.v1",
            "payload": {
                "todo_id": todo_id,
                "ordered_item_ids": ordered_item_ids,
                "updated_at_ms": now,
            }
        });
        insert_oplog(conn, key, &op)?;

        Ok(())
    })
}

pub fn list_todo_checklist_progress(
    conn: &Connection,
    _key: &[u8; 32],
) -> Result<Vec<TodoChecklistProgress>> {
    let mut stmt = conn.prepare(
        r#"
SELECT tci.todo_id, SUM(CASE WHEN tci.is_done != 0 THEN 1 ELSE 0 END) AS done_count, COUNT(*) AS total_count
FROM todo_checklist_items tci
JOIN todos t ON t.id = tci.todo_id
WHERE t.status NOT IN ('done', 'dismissed')
GROUP BY tci.todo_id
ORDER BY tci.todo_id ASC
"#,
    )?;

    let mut rows = stmt.query([])?;
    let mut result = Vec::new();
    while let Some(row) = rows.next()? {
        result.push(TodoChecklistProgress {
            todo_id: row.get(0)?,
            done_count: row.get(1)?,
            total_count: row.get(2)?,
        });
    }

    Ok(result)
}

fn todo_checklist_suggestion_content_aad(id: &str) -> Vec<u8> {
    format!("todo_checklist_suggestion.content:{id}").into_bytes()
}

fn normalize_checklist_suggestion_content(content: &str) -> String {
    content.split_whitespace().collect::<Vec<_>>().join(" ").trim().to_lowercase()
}

fn find_todo_checklist_suggestion_by_id(
    conn: &Connection,
    key: &[u8; 32],
    id: &str,
) -> Result<Option<TodoChecklistSuggestion>> {
    type TodoChecklistSuggestionRow = (
        String,
        Vec<u8>,
        i64,
        String,
        String,
        Option<String>,
        i64,
        i64,
        Option<i64>,
        Option<String>,
    );

    let row: Option<TodoChecklistSuggestionRow> = conn
        .query_row(
            r#"
SELECT todo_id, content, sort_order, state, source, generation_key, created_at_ms, updated_at_ms, dismissed_at_ms, applied_checklist_item_id
FROM todo_checklist_suggestions
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
                ))
            },
        )
        .optional()
        .map_err(|e| anyhow!("get todo checklist suggestion failed: {e}"))?;

    let Some((
        todo_id,
        content_blob,
        sort_order,
        state,
        source,
        generation_key,
        created_at_ms,
        updated_at_ms,
        dismissed_at_ms,
        applied_checklist_item_id,
    )) = row
    else {
        return Ok(None);
    };

    let content_bytes = decrypt_bytes(key, &content_blob, &todo_checklist_suggestion_content_aad(id))?;
    let content = String::from_utf8(content_bytes)
        .map_err(|_| anyhow!("todo checklist suggestion content is not valid utf-8"))?;

    Ok(Some(TodoChecklistSuggestion {
        id: id.to_string(),
        todo_id,
        content,
        sort_order,
        state,
        source,
        generation_key,
        created_at_ms,
        updated_at_ms,
        dismissed_at_ms,
        applied_checklist_item_id,
    }))
}

fn get_todo_checklist_suggestion_by_id(
    conn: &Connection,
    key: &[u8; 32],
    id: &str,
) -> Result<TodoChecklistSuggestion> {
    find_todo_checklist_suggestion_by_id(conn, key, id)?
        .ok_or_else(|| anyhow!("get todo checklist suggestion failed: Query returned no rows"))
}

pub fn list_todo_checklist_suggestions(
    conn: &Connection,
    key: &[u8; 32],
    todo_id: &str,
) -> Result<Vec<TodoChecklistSuggestion>> {
    let mut stmt = conn.prepare(
        r#"
SELECT id, content, sort_order, state, source, generation_key, created_at_ms, updated_at_ms, dismissed_at_ms, applied_checklist_item_id
FROM todo_checklist_suggestions
WHERE todo_id = ?1
ORDER BY sort_order ASC, created_at_ms ASC, id ASC
"#,
    )?;

    let mut rows = stmt.query(params![todo_id])?;
    let mut result = Vec::new();
    while let Some(row) = rows.next()? {
        let id: String = row.get(0)?;
        let content_blob: Vec<u8> = row.get(1)?;
        let sort_order: i64 = row.get(2)?;
        let state: String = row.get(3)?;
        let source: String = row.get(4)?;
        let generation_key: Option<String> = row.get(5)?;
        let created_at_ms: i64 = row.get(6)?;
        let updated_at_ms: i64 = row.get(7)?;
        let dismissed_at_ms: Option<i64> = row.get(8)?;
        let applied_checklist_item_id: Option<String> = row.get(9)?;
        let content_bytes = decrypt_bytes(key, &content_blob, &todo_checklist_suggestion_content_aad(&id))?;
        let content = String::from_utf8(content_bytes)
            .map_err(|_| anyhow!("todo checklist suggestion content is not valid utf-8"))?;

        result.push(TodoChecklistSuggestion {
            id,
            todo_id: todo_id.to_string(),
            content,
            sort_order,
            state,
            source,
            generation_key,
            created_at_ms,
            updated_at_ms,
            dismissed_at_ms,
            applied_checklist_item_id,
        });
    }

    Ok(result)
}

pub fn upsert_generated_todo_checklist_suggestions(
    conn: &Connection,
    key: &[u8; 32],
    todo_id: &str,
    suggestions: &[String],
    source: &str,
    generation_key: Option<&str>,
) -> Result<Vec<TodoChecklistSuggestion>> {
    run_immediate_transaction(conn, || {
        let existing = list_todo_checklist_suggestions(conn, key, todo_id)?;
        let mut blocked_norms = existing
            .iter()
            .filter(|item| {
                item.state == TODO_CHECKLIST_SUGGESTION_STATE_APPLIED
                    || item.state == TODO_CHECKLIST_SUGGESTION_STATE_DISMISSED
                    || item.state == TODO_CHECKLIST_SUGGESTION_STATE_PENDING
            })
            .map(|item| normalize_checklist_suggestion_content(&item.content))
            .collect::<std::collections::HashSet<_>>();

        let mut created = Vec::new();
        let base_sort_order: i64 = conn.query_row(
            r#"SELECT COALESCE(MAX(sort_order), -1) + 1 FROM todo_checklist_suggestions WHERE todo_id = ?1"#,
            params![todo_id],
            |row| row.get(0),
        )?;
        let now = now_ms();
        let mut insert_index: i64 = 0;

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
            let content_blob = encrypt_bytes(key, trimmed.as_bytes(), &todo_checklist_suggestion_content_aad(&id))?;
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

            let device_id = get_or_create_device_id(conn)?;
            let seq = next_device_seq(conn, &device_id)?;
            let op = serde_json::json!({
                "op_id": uuid::Uuid::new_v4().to_string(),
                "device_id": device_id,
                "seq": seq,
                "ts_ms": now,
                "type": "todo.checklist_suggestion.upsert.v1",
                "payload": {
                    "suggestion_id": suggestion.id.as_str(),
                    "todo_id": suggestion.todo_id.as_str(),
                    "content": suggestion.content.as_str(),
                    "sort_order": suggestion.sort_order,
                    "state": suggestion.state.as_str(),
                    "source": suggestion.source.as_str(),
                    "generation_key": suggestion.generation_key.as_deref(),
                    "created_at_ms": suggestion.created_at_ms,
                    "updated_at_ms": suggestion.updated_at_ms,
                    "dismissed_at_ms": suggestion.dismissed_at_ms,
                    "applied_checklist_item_id": suggestion.applied_checklist_item_id.as_deref(),
                }
            });
            insert_oplog(conn, key, &op)?;
            created.push(suggestion);
            insert_index += 1;
        }

        Ok(created)
    })
}

pub fn apply_todo_checklist_suggestions(
    conn: &Connection,
    key: &[u8; 32],
    todo_id: &str,
    suggestion_ids: &[String],
) -> Result<Vec<TodoChecklistItem>> {
    run_immediate_transaction(conn, || {
        let mut applied = Vec::new();
        for suggestion_id in suggestion_ids {
            let Some(suggestion) = find_todo_checklist_suggestion_by_id(conn, key, suggestion_id)?
            else {
                continue;
            };
            if suggestion.todo_id != todo_id || suggestion.state != TODO_CHECKLIST_SUGGESTION_STATE_PENDING {
                continue;
            }
            let item = create_todo_checklist_item(conn, key, todo_id, &suggestion.content)?;
            applied.push((suggestion_id.clone(), item));
        }

        let now = now_ms();
        let mut created_items = Vec::new();
        for (suggestion_id, item) in applied {
            conn.execute(
                r#"UPDATE todo_checklist_suggestions SET state = ?2, updated_at_ms = ?3, applied_checklist_item_id = ?4 WHERE id = ?1"#,
                params![suggestion_id, TODO_CHECKLIST_SUGGESTION_STATE_APPLIED, now, item.id],
            )?;

            let device_id = get_or_create_device_id(conn)?;
            let seq = next_device_seq(conn, &device_id)?;
            let op = serde_json::json!({
                "op_id": uuid::Uuid::new_v4().to_string(),
                "device_id": device_id,
                "seq": seq,
                "ts_ms": now,
                "type": "todo.checklist_suggestion.apply.v1",
                "payload": {
                    "suggestion_id": suggestion_id,
                    "todo_id": todo_id,
                    "applied_checklist_item_id": item.id.as_str(),
                    "updated_at_ms": now,
                }
            });
            insert_oplog(conn, key, &op)?;
            created_items.push(item);
        }
        Ok(created_items)
    })
}

pub fn dismiss_todo_checklist_suggestions(
    conn: &Connection,
    key: &[u8; 32],
    todo_id: &str,
    suggestion_ids: &[String],
) -> Result<()> {
    run_immediate_transaction(conn, || {
        let now = now_ms();
        for suggestion_id in suggestion_ids {
            let rows_changed = conn.execute(
                r#"
UPDATE todo_checklist_suggestions
SET state = ?2, updated_at_ms = ?3, dismissed_at_ms = ?4
WHERE id = ?1 AND todo_id = ?5 AND state = ?6
"#,
                params![
                    suggestion_id,
                    TODO_CHECKLIST_SUGGESTION_STATE_DISMISSED,
                    now,
                    now,
                    todo_id,
                    TODO_CHECKLIST_SUGGESTION_STATE_PENDING,
                ],
            )?;
            if rows_changed == 0 {
                continue;
            }

            let device_id = get_or_create_device_id(conn)?;
            let seq = next_device_seq(conn, &device_id)?;
            let op = serde_json::json!({
                "op_id": uuid::Uuid::new_v4().to_string(),
                "device_id": device_id,
                "seq": seq,
                "ts_ms": now,
                "type": "todo.checklist_suggestion.dismiss.v1",
                "payload": {
                    "suggestion_id": suggestion_id,
                    "todo_id": todo_id,
                    "dismissed_at_ms": now,
                }
            });
            insert_oplog(conn, key, &op)?;
        }
        Ok(())
    })
}

pub fn dismiss_all_todo_checklist_suggestions(
    conn: &Connection,
    key: &[u8; 32],
    todo_id: &str,
) -> Result<()> {
    run_immediate_transaction(conn, || {
        let pending_ids = list_todo_checklist_suggestions(conn, key, todo_id)?
            .into_iter()
            .filter(|item| item.state == TODO_CHECKLIST_SUGGESTION_STATE_PENDING)
            .map(|item| item.id)
            .collect::<Vec<_>>();
        dismiss_todo_checklist_suggestions(conn, key, todo_id, &pending_ids)
    })
}

#[allow(clippy::type_complexity)]
fn get_todo_activity_by_id(conn: &Connection, key: &[u8; 32], id: &str) -> Result<TodoActivity> {
    let (
        todo_id,
        activity_type,
        from_status,
        to_status,
        content_blob,
        source_message_id,
        created_at_ms,
    ): (
        String,
        String,
        Option<String>,
        Option<String>,
        Option<Vec<u8>>,
        Option<String>,
        i64,
    ) = conn
        .query_row(
            r#"
SELECT todo_id, type, from_status, to_status, content, source_message_id, created_at_ms
FROM todo_activities
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
                ))
            },
        )
        .map_err(|e| anyhow!("get todo activity failed: {e}"))?;

    let content = if let Some(blob) = content_blob {
        let aad = format!("todo_activity.content:{id}");
        let bytes = decrypt_bytes(key, &blob, aad.as_bytes())?;
        Some(
            String::from_utf8(bytes)
                .map_err(|_| anyhow!("todo activity content is not valid utf-8"))?,
        )
    } else {
        None
    };

    Ok(TodoActivity {
        id: id.to_string(),
        todo_id,
        activity_type,
        from_status,
        to_status,
        content,
        source_message_id,
        created_at_ms,
    })
}

pub fn list_todo_activities(
    conn: &Connection,
    key: &[u8; 32],
    todo_id: &str,
) -> Result<Vec<TodoActivity>> {
    let mut stmt = conn.prepare(
        r#"
	SELECT a.id, a.todo_id, a.type, a.from_status, a.to_status, a.content, a.source_message_id, a.created_at_ms
	FROM todo_activities a
	LEFT JOIN messages m ON m.id = a.source_message_id
	WHERE a.todo_id = ?1
	  AND NOT (
	    a.type IN ('note', 'summary')
	    AND COALESCE(m.is_deleted, 0) != 0
	  )
	ORDER BY a.created_at_ms ASC, a.id ASC
	"#,
    )?;

    let mut rows = stmt.query(params![todo_id])?;
    let mut result = Vec::new();
    while let Some(row) = rows.next()? {
        let id: String = row.get(0)?;
        let todo_id: String = row.get(1)?;
        let activity_type: String = row.get(2)?;
        let from_status: Option<String> = row.get(3)?;
        let to_status: Option<String> = row.get(4)?;
        let content_blob: Option<Vec<u8>> = row.get(5)?;
        let source_message_id: Option<String> = row.get(6)?;
        let created_at_ms: i64 = row.get(7)?;

        let content = if let Some(blob) = content_blob {
            let aad = format!("todo_activity.content:{id}");
            let bytes = decrypt_bytes(key, &blob, aad.as_bytes())?;
            Some(
                String::from_utf8(bytes)
                    .map_err(|_| anyhow!("todo activity content is not valid utf-8"))?,
            )
        } else {
            None
        };

        result.push(TodoActivity {
            id,
            todo_id,
            activity_type,
            from_status,
            to_status,
            content,
            source_message_id,
            created_at_ms,
        });
    }
    Ok(result)
}

pub fn list_todo_activities_in_range(
    conn: &Connection,
    key: &[u8; 32],
    start_at_ms_inclusive: i64,
    end_at_ms_exclusive: i64,
) -> Result<Vec<TodoActivity>> {
    let mut stmt = conn.prepare(
        r#"
	SELECT a.id, a.todo_id, a.type, a.from_status, a.to_status, a.content, a.source_message_id, a.created_at_ms
	FROM todo_activities a
	LEFT JOIN messages m ON m.id = a.source_message_id
	WHERE a.created_at_ms >= ?1 AND a.created_at_ms < ?2
	  AND NOT (
	    a.type IN ('note', 'summary')
	    AND COALESCE(m.is_deleted, 0) != 0
	  )
	ORDER BY a.created_at_ms ASC, a.id ASC
	"#,
    )?;

    let mut rows = stmt.query(params![start_at_ms_inclusive, end_at_ms_exclusive])?;
    let mut result = Vec::new();
    while let Some(row) = rows.next()? {
        let id: String = row.get(0)?;
        let todo_id: String = row.get(1)?;
        let activity_type: String = row.get(2)?;
        let from_status: Option<String> = row.get(3)?;
        let to_status: Option<String> = row.get(4)?;
        let content_blob: Option<Vec<u8>> = row.get(5)?;
        let source_message_id: Option<String> = row.get(6)?;
        let created_at_ms: i64 = row.get(7)?;

        let content = if let Some(blob) = content_blob {
            let aad = format!("todo_activity.content:{id}");
            let bytes = decrypt_bytes(key, &blob, aad.as_bytes())?;
            Some(
                String::from_utf8(bytes)
                    .map_err(|_| anyhow!("todo activity content is not valid utf-8"))?,
            )
        } else {
            None
        };

        result.push(TodoActivity {
            id,
            todo_id,
            activity_type,
            from_status,
            to_status,
            content,
            source_message_id,
            created_at_ms,
        });
    }
    Ok(result)
}

pub fn append_todo_note(
    conn: &Connection,
    key: &[u8; 32],
    todo_id: &str,
    content: &str,
    source_message_id: Option<&str>,
) -> Result<TodoActivity> {
    let mut source_message_id = source_message_id
        .map(str::trim)
        .filter(|s| !s.is_empty())
        .map(|s| s.to_string());

    if source_message_id.is_none() {
        // If this note is created outside of chat (e.g. Todo detail follow-up),
        // create a chat message so it shows up in the conversation list and can
        // carry attachments.
        let todo_source_entry_id: Option<Option<String>> = conn
            .query_row(
                r#"SELECT source_entry_id FROM todos WHERE id = ?1"#,
                params![todo_id],
                |row| row.get(0),
            )
            .optional()?;

        let mut conversation_id: Option<String> = None;
        if let Some(Some(source_entry_id)) = todo_source_entry_id {
            let trimmed = source_entry_id.trim();
            if !trimmed.is_empty() {
                conversation_id = conn
                    .query_row(
                        r#"SELECT conversation_id FROM messages WHERE id = ?1"#,
                        params![trimmed],
                        |row| row.get(0),
                    )
                    .optional()?;
            }
        }

        let conversation_id =
            conversation_id.unwrap_or_else(|| LOOP_HOME_CONVERSATION_ID.to_string());
        if conversation_id == LOOP_HOME_CONVERSATION_ID {
            // Ensure the loop home exists before inserting.
            get_or_create_loop_home_conversation(conn, key)?;
        }

        let msg = insert_message(conn, key, &conversation_id, "user", content)?;
        source_message_id = Some(msg.id);
    }

    let id = uuid::Uuid::new_v4().to_string();
    let now = now_ms();
    let created_at_ms = match source_message_id.as_deref() {
        Some(message_id) => conn
            .query_row(
                r#"SELECT created_at FROM messages WHERE id = ?1"#,
                params![message_id],
                |row| row.get(0),
            )
            .optional()?
            .unwrap_or(now),
        None => now,
    };
    let aad = format!("todo_activity.content:{id}");
    let content_blob = encrypt_bytes(key, content.as_bytes(), aad.as_bytes())?;

    conn.execute(
        r#"
INSERT INTO todo_activities(
  id, todo_id, type, from_status, to_status, content, source_message_id, created_at_ms, needs_embedding
)
VALUES (?1, ?2, 'note', NULL, NULL, ?3, ?4, ?5, 1)
"#,
        params![
            id,
            todo_id,
            content_blob,
            source_message_id.as_deref(),
            created_at_ms
        ],
    )?;

    let activity = get_todo_activity_by_id(conn, key, &id)?;

    let device_id = get_or_create_device_id(conn)?;
    let seq = next_device_seq(conn, &device_id)?;
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

pub fn move_todo_activity(
    conn: &Connection,
    key: &[u8; 32],
    activity_id: &str,
    to_todo_id: &str,
) -> Result<TodoActivity> {
    conn.execute_batch("BEGIN IMMEDIATE;")?;

    let result: Result<TodoActivity> = (|| {
        let activity = get_todo_activity_by_id(conn, key, activity_id)?;
        if activity.todo_id == to_todo_id {
            return Ok(activity);
        }

        let todo_exists: Option<i64> = conn
            .query_row(
                r#"SELECT 1 FROM todos WHERE id = ?1"#,
                params![to_todo_id],
                |row| row.get(0),
            )
            .optional()?;
        if todo_exists.is_none() {
            // Keep behavior aligned with sync apply path:
            // allow moving to a temporary/orphan todo id so source-message
            // links can be detached without deleting the original message.
            conn.execute_batch("PRAGMA foreign_keys = OFF;")?;
        }

        let now = now_ms();
        let update_result = conn.execute(
            r#"UPDATE todo_activities
               SET todo_id = ?2,
                   needs_embedding = 1
               WHERE id = ?1"#,
            params![activity_id, to_todo_id],
        );
        if todo_exists.is_none() {
            let _ = conn.execute_batch("PRAGMA foreign_keys = ON;");
        }
        update_result?;

        // Persist move metadata to prevent older remote ops overriding local moves.
        let moved_at_key = format!("todo_activity.todo_id_updated_at:{activity_id}");
        kv_set_string(conn, &moved_at_key, &now.to_string())?;
        let todo_id_override_key = format!("todo_activity.todo_id_override:{activity_id}");
        kv_set_string(conn, &todo_id_override_key, to_todo_id)?;

        let device_id = get_or_create_device_id(conn)?;
        let seq = next_device_seq(conn, &device_id)?;
        let op = serde_json::json!({
            "op_id": uuid::Uuid::new_v4().to_string(),
            "device_id": device_id,
            "seq": seq,
            "ts_ms": now,
            "type": "todo.activity.move.v1",
            "payload": {
                "activity_id": activity_id,
                "to_todo_id": to_todo_id,
                "moved_at_ms": now,
            }
        });
        insert_oplog(conn, key, &op)?;

        get_todo_activity_by_id(conn, key, activity_id)
    })();

    match result {
        Ok(activity) => {
            conn.execute_batch("COMMIT;")?;
            Ok(activity)
        }
        Err(e) => {
            let _ = conn.execute_batch("ROLLBACK;");
            Err(e)
        }
    }
}

pub fn link_attachment_to_todo_activity(
    conn: &Connection,
    key: &[u8; 32],
    activity_id: &str,
    attachment_sha256: &str,
) -> Result<()> {
    let now = now_ms();
    let inserted = conn.execute(
        r#"INSERT OR IGNORE INTO todo_activity_attachments(activity_id, attachment_sha256, created_at_ms)
           VALUES (?1, ?2, ?3)"#,
        params![activity_id, attachment_sha256, now],
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
        "type": "todo.activity_attachment.link.v1",
        "payload": {
            "activity_id": activity_id,
            "attachment_sha256": attachment_sha256,
            "created_at_ms": now,
        }
    });
    insert_oplog(conn, key, &op)?;

    Ok(())
}

pub fn list_todo_activity_attachments(
    conn: &Connection,
    _key: &[u8; 32],
    activity_id: &str,
) -> Result<Vec<Attachment>> {
    let mut stmt = conn.prepare(
        r#"
SELECT a.sha256, a.mime_type, a.path, a.byte_len, a.created_at
FROM attachments a
JOIN todo_activity_attachments taa ON taa.attachment_sha256 = a.sha256
WHERE taa.activity_id = ?1
ORDER BY taa.created_at_ms ASC, a.sha256 ASC
"#,
    )?;

    let mut rows = stmt.query(params![activity_id])?;
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

pub fn list_todos_created_in_range(
    conn: &Connection,
    key: &[u8; 32],
    start_at_ms_inclusive: i64,
    end_at_ms_exclusive: i64,
) -> Result<Vec<Todo>> {
    let mut stmt = conn.prepare(
        r#"
SELECT id, title, due_at_ms, status, source_entry_id, created_at_ms, updated_at_ms, review_stage, next_review_at_ms, last_review_at_ms
FROM todos
WHERE created_at_ms >= ?1 AND created_at_ms < ?2
ORDER BY created_at_ms ASC, id ASC
"#,
    )?;

    let mut rows = stmt.query(params![start_at_ms_inclusive, end_at_ms_exclusive])?;
    let mut result = Vec::new();
    while let Some(row) = rows.next()? {
        let id: String = row.get(0)?;
        let title_blob: Vec<u8> = row.get(1)?;
        let due_at_ms: Option<i64> = row.get(2)?;
        let status: String = row.get(3)?;
        let source_entry_id: Option<String> = row.get(4)?;
        let created_at_ms: i64 = row.get(5)?;
        let updated_at_ms: i64 = row.get(6)?;
        let review_stage: Option<i64> = row.get(7)?;
        let next_review_at_ms: Option<i64> = row.get(8)?;
        let last_review_at_ms: Option<i64> = row.get(9)?;

        let title_bytes = decrypt_bytes(key, &title_blob, b"todo.title")?;
        let title =
            String::from_utf8(title_bytes).map_err(|_| anyhow!("todo title is not valid utf-8"))?;

        result.push(Todo {
            id,
            title,
            due_at_ms,
            status,
            source_entry_id,
            created_at_ms,
            updated_at_ms,
            review_stage,
            next_review_at_ms,
            last_review_at_ms,
        });
    }
    Ok(result)
}

fn set_todo_status_in_txn(
    conn: &Connection,
    key: &[u8; 32],
    todo_id: &str,
    new_status: &str,
    source_message_id: Option<&str>,
) -> Result<Todo> {
    let existing = get_todo_by_id(conn, key, todo_id)?;
    if existing.status == new_status {
        return Ok(existing);
    }

    let activity_id = uuid::Uuid::new_v4().to_string();
    let now = now_ms();
    conn.execute(
        r#"
INSERT INTO todo_activities(
  id, todo_id, type, from_status, to_status, content, source_message_id, created_at_ms, needs_embedding
)
VALUES (?1, ?2, 'status_change', ?3, ?4, NULL, ?5, ?6, 1)
"#,
        params![
            activity_id,
            todo_id,
            existing.status,
            new_status,
            source_message_id,
            now
        ],
    )?;

    let device_id = get_or_create_device_id(conn)?;
    let seq = next_device_seq(conn, &device_id)?;
    let op = serde_json::json!({
        "op_id": uuid::Uuid::new_v4().to_string(),
        "device_id": device_id,
        "seq": seq,
        "ts_ms": now,
        "type": "todo.activity.append.v1",
        "payload": {
            "activity_id": activity_id.as_str(),
            "todo_id": todo_id,
            "activity_type": "status_change",
            "from_status": existing.status.as_str(),
            "to_status": new_status,
            "content": null,
            "source_message_id": source_message_id,
            "created_at_ms": now,
        }
    });
    insert_oplog(conn, key, &op)?;

    let (review_stage, next_review_at_ms) = if existing.status == "inbox" && new_status != "inbox" {
        (None, None)
    } else {
        (existing.review_stage, existing.next_review_at_ms)
    };
    let due_at_ms = if existing.due_at_ms.is_none()
        && existing.status == "open"
        && (new_status == "in_progress" || new_status == "done")
    {
        Some(now)
    } else {
        existing.due_at_ms
    };

    let updated = upsert_todo(
        conn,
        key,
        todo_id,
        &existing.title,
        due_at_ms,
        new_status,
        existing.source_entry_id.as_deref(),
        review_stage,
        next_review_at_ms,
        Some(now),
    )?;

    maybe_spawn_next_recurring_todo(conn, key, &updated, new_status)?;

    Ok(updated)
}

pub fn set_todo_status(
    conn: &Connection,
    key: &[u8; 32],
    todo_id: &str,
    new_status: &str,
    source_message_id: Option<&str>,
) -> Result<Todo> {
    conn.execute_batch("BEGIN IMMEDIATE;")?;

    let result = set_todo_status_in_txn(conn, key, todo_id, new_status, source_message_id);

    match result {
        Ok(todo) => {
            conn.execute_batch("COMMIT;")?;
            Ok(todo)
        }
        Err(e) => {
            let _ = conn.execute_batch("ROLLBACK;");
            Err(e)
        }
    }
}

pub fn delete_todo_and_associated_messages(
    conn: &Connection,
    key: &[u8; 32],
    app_dir: &Path,
    todo_id: &str,
) -> Result<u64> {
    conn.execute_batch("BEGIN IMMEDIATE;")?;

    let result: Result<u64> = (|| {
        let todo_source_entry_id: Option<Option<String>> = conn
            .query_row(
                r#"SELECT source_entry_id FROM todos WHERE id = ?1"#,
                params![todo_id],
                |row| row.get(0),
            )
            .optional()?;
        let Some(source_entry_id) = todo_source_entry_id else {
            return Ok(0);
        };

        let mut direct_message_ids: BTreeSet<String> = BTreeSet::new();
        if let Some(source_entry_id) = source_entry_id {
            let trimmed = source_entry_id.trim();
            if !trimmed.is_empty() {
                direct_message_ids.insert(trimmed.to_string());
            }
        }

        // Messages linked via todo activities.
        let mut stmt_activity_messages = conn.prepare(
            r#"SELECT DISTINCT source_message_id
               FROM todo_activities
               WHERE todo_id = ?1
                 AND source_message_id IS NOT NULL
                 AND source_message_id != ''
               ORDER BY source_message_id ASC"#,
        )?;
        let mut rows = stmt_activity_messages.query(params![todo_id])?;
        while let Some(row) = rows.next()? {
            let id: String = row.get(0)?;
            let trimmed = id.trim();
            if trimmed.is_empty() {
                continue;
            }
            direct_message_ids.insert(trimmed.to_string());
        }

        // Collect attachments from:
        // - direct messages (message_attachments)
        // - todo activities (todo_activity_attachments)
        let mut attachment_sha256s: BTreeSet<String> = BTreeSet::new();

        if !direct_message_ids.is_empty() {
            let mut stmt_message_attachments = conn.prepare(
                r#"SELECT attachment_sha256
                   FROM message_attachments
                   WHERE message_id = ?1
                   ORDER BY created_at ASC"#,
            )?;
            for message_id in &direct_message_ids {
                let mut rows = stmt_message_attachments.query(params![message_id])?;
                while let Some(row) = rows.next()? {
                    let sha: String = row.get(0)?;
                    let trimmed = sha.trim();
                    if trimmed.is_empty() {
                        continue;
                    }
                    attachment_sha256s.insert(trimmed.to_string());
                }
            }
        }

        let mut stmt_todo_activity_attachments = conn.prepare(
            r#"SELECT DISTINCT attachment_sha256
               FROM todo_activity_attachments
               WHERE activity_id IN (SELECT id FROM todo_activities WHERE todo_id = ?1)
               ORDER BY attachment_sha256 ASC"#,
        )?;
        let mut rows = stmt_todo_activity_attachments.query(params![todo_id])?;
        while let Some(row) = rows.next()? {
            let sha: String = row.get(0)?;
            let trimmed = sha.trim();
            if trimmed.is_empty() {
                continue;
            }
            attachment_sha256s.insert(trimmed.to_string());
        }

        // Delete all messages referencing the attachments (including the direct messages).
        let mut message_ids_to_delete: BTreeSet<String> = BTreeSet::new();
        message_ids_to_delete.extend(direct_message_ids.iter().cloned());

        if !attachment_sha256s.is_empty() {
            let mut stmt_attachment_messages = conn.prepare(
                r#"SELECT message_id
                   FROM message_attachments
                   WHERE attachment_sha256 = ?1"#,
            )?;
            for sha in &attachment_sha256s {
                let mut rows = stmt_attachment_messages.query(params![sha])?;
                while let Some(row) = rows.next()? {
                    let id: String = row.get(0)?;
                    let trimmed = id.trim();
                    if trimmed.is_empty() {
                        continue;
                    }
                    message_ids_to_delete.insert(trimmed.to_string());
                }
            }
        }

        // Best-effort: delete linked messages with their own oplog operations.
        for message_id in &message_ids_to_delete {
            let _ = set_message_deleted(conn, key, message_id, true);
        }

        // Purge attachment bytes and emit attachment.delete.v1 ops.
        for sha in &attachment_sha256s {
            purge_attachment(conn, key, app_dir, sha)?;
        }

        let now = now_ms();
        let device_id = get_or_create_device_id(conn)?;
        let seq = next_device_seq(conn, &device_id)?;
        let op = serde_json::json!({
            "op_id": uuid::Uuid::new_v4().to_string(),
            "device_id": device_id,
            "seq": seq,
            "ts_ms": now,
            "type": "todo.delete.v1",
            "payload": {
                "todo_id": todo_id,
                "deleted_at_ms": now,
            }
        });
        insert_oplog(conn, key, &op)?;

        conn.execute(
            r#"
INSERT INTO todo_deletions(todo_id, deleted_at_ms)
VALUES (?1, ?2)
ON CONFLICT(todo_id) DO UPDATE SET
  deleted_at_ms = max(todo_deletions.deleted_at_ms, excluded.deleted_at_ms)
"#,
            params![todo_id, now],
        )?;

        let _ = conn.execute(
            r#"DELETE FROM todo_activity_attachments
               WHERE activity_id IN (SELECT id FROM todo_activities WHERE todo_id = ?1)"#,
            params![todo_id],
        )?;
        let _ = conn.execute(
            r#"DELETE FROM todo_activities WHERE todo_id = ?1"#,
            params![todo_id],
        )?;
        let _ = conn.execute(
            r#"DELETE FROM todo_activity_embeddings WHERE todo_id = ?1"#,
            params![todo_id],
        )?;
        let _ = conn.execute(
            r#"DELETE FROM todo_embeddings WHERE todo_id = ?1"#,
            params![todo_id],
        )?;

        conn.execute(r#"DELETE FROM todos WHERE id = ?1"#, params![todo_id])?;

        Ok(direct_message_ids.len() as u64)
    })();

    match result {
        Ok(deleted_messages) => {
            conn.execute_batch("COMMIT;")?;
            Ok(deleted_messages)
        }
        Err(e) => {
            let _ = conn.execute_batch("ROLLBACK;");
            Err(e)
        }
    }
}
