#[allow(clippy::too_many_arguments)]
fn transition_todo_in_txn(
    conn: &Connection,
    key: &[u8; 32],
    todo_id: &str,
    new_status: Option<&str>,
    due_at_ms: Option<i64>,
    clear_due_at_ms: bool,
    review_stage: Option<i64>,
    clear_review_stage: bool,
    next_review_at_ms: Option<i64>,
    clear_next_review_at_ms: bool,
    last_review_at_ms: Option<i64>,
    clear_last_review_at_ms: bool,
    source_message_id: Option<&str>,
) -> Result<Todo> {
    let existing = get_todo(conn, key, todo_id)?;
    let staged = match new_status {
        Some(status) if status != existing.status => {
            set_todo_status_in_txn(conn, key, todo_id, status, source_message_id)?
        }
        _ => existing,
    };

    let target_due_at_ms = if clear_due_at_ms {
        None
    } else {
        due_at_ms.or(staged.due_at_ms)
    };
    let target_review_stage = if clear_review_stage {
        None
    } else {
        review_stage.or(staged.review_stage)
    };
    let target_next_review_at_ms = if clear_next_review_at_ms {
        None
    } else {
        next_review_at_ms.or(staged.next_review_at_ms)
    };
    let target_last_review_at_ms = if clear_last_review_at_ms {
        None
    } else {
        last_review_at_ms.or(staged.last_review_at_ms)
    };

    if target_due_at_ms == staged.due_at_ms
        && target_review_stage == staged.review_stage
        && target_next_review_at_ms == staged.next_review_at_ms
        && target_last_review_at_ms == staged.last_review_at_ms
    {
        return Ok(staged);
    }

    upsert_todo(
        conn,
        key,
        &staged.id,
        &staged.title,
        target_due_at_ms,
        &staged.status,
        staged.source_entry_id.as_deref(),
        target_review_stage,
        target_next_review_at_ms,
        target_last_review_at_ms,
    )
}

#[allow(clippy::too_many_arguments)]
pub fn transition_todo(
    conn: &Connection,
    key: &[u8; 32],
    todo_id: &str,
    new_status: Option<&str>,
    due_at_ms: Option<i64>,
    clear_due_at_ms: bool,
    review_stage: Option<i64>,
    clear_review_stage: bool,
    next_review_at_ms: Option<i64>,
    clear_next_review_at_ms: bool,
    last_review_at_ms: Option<i64>,
    clear_last_review_at_ms: bool,
    source_message_id: Option<&str>,
) -> Result<Todo> {
    conn.execute_batch("BEGIN IMMEDIATE;")?;

    let result = transition_todo_in_txn(
        conn,
        key,
        todo_id,
        new_status,
        due_at_ms,
        clear_due_at_ms,
        review_stage,
        clear_review_stage,
        next_review_at_ms,
        clear_next_review_at_ms,
        last_review_at_ms,
        clear_last_review_at_ms,
        source_message_id,
    );

    match result {
        Ok(todo) => {
            conn.execute_batch("COMMIT;")?;
            Ok(todo)
        }
        Err(error) => {
            let _ = conn.execute_batch("ROLLBACK;");
            Err(error)
        }
    }
}
