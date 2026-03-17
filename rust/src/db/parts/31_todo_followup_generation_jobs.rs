pub const TODO_FOLLOWUP_GENERATION_JOB_STATUS_PENDING: &str = "pending";
pub const TODO_FOLLOWUP_GENERATION_JOB_STATUS_RUNNING: &str = "running";
pub const TODO_FOLLOWUP_GENERATION_JOB_STATUS_FAILED: &str = "failed";
pub const TODO_FOLLOWUP_GENERATION_JOB_STATUS_SUCCEEDED: &str = "succeeded";
pub const TODO_FOLLOWUP_GENERATION_JOB_STATUS_SKIPPED: &str = "skipped";
pub const TODO_FOLLOWUP_GENERATION_JOB_STATUS_CANCELED: &str = "canceled";

pub fn enqueue_todo_followup_generation_job(
    conn: &Connection,
    todo_id: &str,
    trigger_kind: &str,
    task_type_hint: Option<&str>,
    now_ms: i64,
) -> Result<()> {
    let todo_id = todo_id.trim();
    if todo_id.is_empty() {
        return Err(anyhow!("todo_id is required"));
    }

    let include_manual_followups = if trigger_kind.trim() == "manual_regenerate" {
        1i64
    } else {
        0i64
    };

    conn.execute(
        r#"
INSERT INTO todo_followup_generation_jobs(
  todo_id,
  trigger_kind,
  status,
  attempts,
  next_retry_at_ms,
  last_error,
  include_manual_followups,
  task_type_hint,
  created_at_ms,
  updated_at_ms
)
VALUES (?1, ?2, 'pending', 0, NULL, NULL, ?3, ?4, ?5, ?5)
ON CONFLICT(todo_id) DO UPDATE SET
  trigger_kind = excluded.trigger_kind,
  status = 'pending',
  attempts = 0,
  next_retry_at_ms = NULL,
  last_error = NULL,
  include_manual_followups = excluded.include_manual_followups,
  task_type_hint = COALESCE(excluded.task_type_hint, todo_followup_generation_jobs.task_type_hint),
  updated_at_ms = excluded.updated_at_ms
"#,
        params![todo_id, trigger_kind, include_manual_followups, task_type_hint, now_ms],
    )?;
    Ok(())
}

pub fn list_due_todo_followup_generation_jobs(
    conn: &Connection,
    now_ms: i64,
    limit: i64,
) -> Result<Vec<TodoFollowupGenerationJob>> {
    let limit = limit.clamp(1, 500);
    let mut stmt = conn.prepare(
        r#"
SELECT todo_id, trigger_kind, status, attempts, next_retry_at_ms, last_error, include_manual_followups, task_type_hint, created_at_ms, updated_at_ms
FROM todo_followup_generation_jobs
WHERE status IN ('pending', 'failed', 'running')
  AND (next_retry_at_ms IS NULL OR next_retry_at_ms <= ?1)
ORDER BY updated_at_ms ASC, todo_id ASC
LIMIT ?2
"#,
    )?;

    let mut rows = stmt.query(params![now_ms, limit])?;
    let mut result = Vec::new();
    while let Some(row) = rows.next()? {
        result.push(TodoFollowupGenerationJob {
            todo_id: row.get(0)?,
            trigger_kind: row.get(1)?,
            status: row.get(2)?,
            attempts: row.get(3)?,
            next_retry_at_ms: row.get(4)?,
            last_error: row.get(5)?,
            include_manual_followups: row.get::<_, i64>(6)? != 0,
            task_type_hint: row.get(7)?,
            created_at_ms: row.get(8)?,
            updated_at_ms: row.get(9)?,
        });
    }
    Ok(result)
}

pub fn mark_todo_followup_generation_job_running(
    conn: &Connection,
    todo_id: &str,
    now_ms: i64,
) -> Result<()> {
    conn.execute(
        r#"
UPDATE todo_followup_generation_jobs
SET status = 'running', updated_at_ms = ?2
WHERE todo_id = ?1
"#,
        params![todo_id, now_ms],
    )?;
    Ok(())
}

pub fn mark_todo_followup_generation_job_failed(
    conn: &Connection,
    todo_id: &str,
    attempts: i64,
    next_retry_at_ms: i64,
    last_error: &str,
    now_ms: i64,
) -> Result<()> {
    conn.execute(
        r#"
UPDATE todo_followup_generation_jobs
SET status = 'failed',
    attempts = ?2,
    next_retry_at_ms = ?3,
    last_error = ?4,
    updated_at_ms = ?5
WHERE todo_id = ?1
"#,
        params![todo_id, attempts, next_retry_at_ms, last_error, now_ms],
    )?;
    Ok(())
}

pub fn mark_todo_followup_generation_job_succeeded(
    conn: &Connection,
    todo_id: &str,
    now_ms: i64,
) -> Result<()> {
    conn.execute(
        r#"
UPDATE todo_followup_generation_jobs
SET status = 'succeeded',
    next_retry_at_ms = NULL,
    last_error = NULL,
    updated_at_ms = ?2
WHERE todo_id = ?1
"#,
        params![todo_id, now_ms],
    )?;
    Ok(())
}

pub fn mark_todo_followup_generation_job_skipped(
    conn: &Connection,
    todo_id: &str,
    now_ms: i64,
) -> Result<()> {
    conn.execute(
        r#"
UPDATE todo_followup_generation_jobs
SET status = 'skipped',
    next_retry_at_ms = NULL,
    last_error = NULL,
    updated_at_ms = ?2
WHERE todo_id = ?1
"#,
        params![todo_id, now_ms],
    )?;
    Ok(())
}

pub fn mark_todo_followup_generation_job_canceled(
    conn: &Connection,
    todo_id: &str,
    now_ms: i64,
) -> Result<()> {
    conn.execute(
        r#"
UPDATE todo_followup_generation_jobs
SET status = 'canceled',
    next_retry_at_ms = NULL,
    updated_at_ms = ?2
WHERE todo_id = ?1
"#,
        params![todo_id, now_ms],
    )?;
    Ok(())
}
