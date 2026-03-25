pub const TODO_FOLLOWUP_GENERATION_JOB_STATUS_PENDING: &str = "pending";
pub const TODO_FOLLOWUP_GENERATION_JOB_STATUS_RUNNING: &str = "running";
pub const TODO_FOLLOWUP_GENERATION_JOB_STATUS_FAILED: &str = "failed";
pub const TODO_FOLLOWUP_GENERATION_JOB_STATUS_SUCCEEDED: &str = "succeeded";
pub const TODO_FOLLOWUP_GENERATION_JOB_STATUS_SKIPPED: &str = "skipped";
pub const TODO_FOLLOWUP_GENERATION_JOB_STATUS_CANCELED: &str = "canceled";
pub const TODO_FOLLOWUP_GENERATION_RUNNING_LEASE_MS: i64 = 2 * 60 * 1000;
const TODO_FOLLOWUP_TRIGGER_KIND_AUTO_CREATE: &str = "auto_create";
const TODO_FOLLOWUP_TRIGGER_KIND_MANUAL_REGENERATE: &str = "manual_regenerate";

pub fn enqueue_todo_followup_generation_job(
    conn: &Connection,
    todo_id: &str,
    trigger_kind: &str,
    manual_override_followup: bool,
    task_type_hint: Option<&str>,
    now_ms: i64,
) -> Result<()> {
    let todo_id = todo_id.trim();
    if todo_id.is_empty() {
        return Err(anyhow!("todo_id is required"));
    }

    let trigger_kind = trigger_kind.trim();
    if trigger_kind.is_empty() {
        return Err(anyhow!("trigger_kind is required"));
    }
    if trigger_kind != TODO_FOLLOWUP_TRIGGER_KIND_AUTO_CREATE
        && trigger_kind != TODO_FOLLOWUP_TRIGGER_KIND_MANUAL_REGENERATE
    {
        return Err(anyhow!("invalid trigger_kind: {trigger_kind}"));
    }

    let include_manual_followups = if trigger_kind == TODO_FOLLOWUP_TRIGGER_KIND_MANUAL_REGENERATE {
        1i64
    } else {
        0i64
    };
    let manual_override_followup = if manual_override_followup { 1i64 } else { 0i64 };

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
  manual_override_followup,
  task_type_hint,
  created_at_ms,
  updated_at_ms
)
VALUES (?1, ?2, 'pending', 0, NULL, NULL, ?3, ?4, ?5, ?6, ?6)
ON CONFLICT(todo_id) DO UPDATE SET
  trigger_kind = CASE
    WHEN todo_followup_generation_jobs.trigger_kind = 'manual_regenerate'
      AND todo_followup_generation_jobs.status IN ('pending', 'running', 'failed')
      AND excluded.trigger_kind = 'auto_create'
      THEN todo_followup_generation_jobs.trigger_kind
    ELSE excluded.trigger_kind
  END,
  status = CASE
    WHEN todo_followup_generation_jobs.trigger_kind = 'manual_regenerate'
      AND todo_followup_generation_jobs.status IN ('pending', 'running', 'failed')
      AND excluded.trigger_kind = 'auto_create'
      THEN todo_followup_generation_jobs.status
    ELSE 'pending'
  END,
  attempts = CASE
    WHEN todo_followup_generation_jobs.trigger_kind = 'manual_regenerate'
      AND todo_followup_generation_jobs.status IN ('pending', 'running', 'failed')
      AND excluded.trigger_kind = 'auto_create'
      THEN todo_followup_generation_jobs.attempts
    ELSE 0
  END,
  next_retry_at_ms = CASE
    WHEN todo_followup_generation_jobs.trigger_kind = 'manual_regenerate'
      AND todo_followup_generation_jobs.status IN ('pending', 'running', 'failed')
      AND excluded.trigger_kind = 'auto_create'
      THEN todo_followup_generation_jobs.next_retry_at_ms
    ELSE NULL
  END,
  last_error = CASE
    WHEN todo_followup_generation_jobs.trigger_kind = 'manual_regenerate'
      AND todo_followup_generation_jobs.status IN ('pending', 'running', 'failed')
      AND excluded.trigger_kind = 'auto_create'
      THEN todo_followup_generation_jobs.last_error
    ELSE NULL
  END,
  include_manual_followups = CASE
    WHEN todo_followup_generation_jobs.trigger_kind = 'manual_regenerate'
      AND todo_followup_generation_jobs.status IN ('pending', 'running', 'failed')
      AND excluded.trigger_kind = 'auto_create'
      THEN todo_followup_generation_jobs.include_manual_followups
    ELSE excluded.include_manual_followups
  END,
  manual_override_followup = CASE
    WHEN todo_followup_generation_jobs.trigger_kind = 'manual_regenerate'
      AND todo_followup_generation_jobs.status IN ('pending', 'running', 'failed')
      AND excluded.trigger_kind = 'auto_create'
      THEN todo_followup_generation_jobs.manual_override_followup
    ELSE excluded.manual_override_followup
  END,
  task_type_hint = CASE
    WHEN todo_followup_generation_jobs.trigger_kind = 'manual_regenerate'
      AND todo_followup_generation_jobs.status IN ('pending', 'running', 'failed')
      AND excluded.trigger_kind = 'auto_create'
      THEN todo_followup_generation_jobs.task_type_hint
    WHEN excluded.task_type_hint IS NOT NULL THEN excluded.task_type_hint
    WHEN excluded.trigger_kind = 'manual_regenerate'
      THEN todo_followup_generation_jobs.task_type_hint
    WHEN excluded.trigger_kind = 'auto_create' THEN todo_followup_generation_jobs.task_type_hint
    ELSE NULL
  END,
  created_at_ms = CASE
    WHEN todo_followup_generation_jobs.trigger_kind = 'manual_regenerate'
      AND todo_followup_generation_jobs.status IN ('pending', 'running', 'failed')
      AND excluded.trigger_kind = 'auto_create'
      THEN todo_followup_generation_jobs.created_at_ms
    ELSE excluded.created_at_ms
  END,
  updated_at_ms = CASE
    WHEN todo_followup_generation_jobs.trigger_kind = 'manual_regenerate'
      AND todo_followup_generation_jobs.status IN ('pending', 'running', 'failed')
      AND excluded.trigger_kind = 'auto_create'
      THEN todo_followup_generation_jobs.updated_at_ms
    ELSE excluded.updated_at_ms
  END
"#,
        params![todo_id, trigger_kind, include_manual_followups, manual_override_followup, task_type_hint, now_ms],
    )?;
    Ok(())
}

pub fn find_todo_followup_generation_job(
    conn: &Connection,
    todo_id: &str,
) -> Result<Option<TodoFollowupGenerationJob>> {
    conn.query_row(
        r#"
SELECT todo_id, trigger_kind, status, attempts, next_retry_at_ms, last_error, include_manual_followups, manual_override_followup, task_type_hint, created_at_ms, updated_at_ms
FROM todo_followup_generation_jobs
WHERE todo_id = ?1
"#,
        params![todo_id],
        |row| {
            Ok(TodoFollowupGenerationJob {
                todo_id: row.get(0)?,
                trigger_kind: row.get(1)?,
                status: row.get(2)?,
                attempts: row.get(3)?,
                next_retry_at_ms: row.get(4)?,
                last_error: row.get(5)?,
                include_manual_followups: row.get::<_, i64>(6)? != 0,
                manual_override_followup: row.get::<_, i64>(7)? != 0,
                task_type_hint: row.get(8)?,
                created_at_ms: row.get(9)?,
                updated_at_ms: row.get(10)?,
            })
        },
    )
    .optional()
    .map_err(Into::into)
}

pub fn list_due_todo_followup_generation_jobs(
    conn: &Connection,
    now_ms: i64,
    limit: i64,
) -> Result<Vec<TodoFollowupGenerationJob>> {
    let limit = limit.max(1);
    let manual_jobs = query_due_todo_followup_generation_jobs(
        conn,
        now_ms,
        limit,
        TODO_FOLLOWUP_TRIGGER_KIND_MANUAL_REGENERATE,
    )?;
    let auto_jobs = query_due_todo_followup_generation_jobs_excluding(
        conn,
        now_ms,
        limit,
        TODO_FOLLOWUP_TRIGGER_KIND_MANUAL_REGENERATE,
    )?;

    if limit == 1 {
        return Ok(
            manual_jobs
                .into_iter()
                .take(1)
                .chain(auto_jobs.into_iter().take(1))
                .take(1)
                .collect(),
        );
    }

    if manual_jobs.is_empty() {
        return Ok(auto_jobs.into_iter().take(limit as usize).collect());
    }
    if auto_jobs.is_empty() {
        return Ok(manual_jobs.into_iter().take(limit as usize).collect());
    }

    let mut result = manual_jobs
        .iter()
        .take((limit - 1) as usize)
        .cloned()
        .collect::<Vec<_>>();
    result.push(auto_jobs[0].clone());

    let mut remaining = (limit as usize).saturating_sub(result.len());
    if remaining > 0 {
        result.extend(auto_jobs.iter().skip(1).take(remaining).cloned());
        remaining = (limit as usize).saturating_sub(result.len());
    }
    if remaining > 0 {
        result.extend(
            manual_jobs
                .iter()
                .skip((limit - 1) as usize)
                .take(remaining)
                .cloned(),
        );
    }

    Ok(result)
}


pub fn list_due_auto_todo_followup_generation_jobs(
    conn: &Connection,
    now_ms: i64,
    limit: i64,
) -> Result<Vec<TodoFollowupGenerationJob>> {
    let limit = limit.max(1);
    query_due_todo_followup_generation_jobs_excluding(
        conn,
        now_ms,
        limit,
        TODO_FOLLOWUP_TRIGGER_KIND_MANUAL_REGENERATE,
    )
}

fn query_due_todo_followup_generation_jobs(
    conn: &Connection,
    now_ms: i64,
    limit: i64,
    trigger_kind: &str,
) -> Result<Vec<TodoFollowupGenerationJob>> {
    query_due_todo_followup_generation_jobs_internal(conn, now_ms, limit, trigger_kind, true)
}

fn query_due_todo_followup_generation_jobs_excluding(
    conn: &Connection,
    now_ms: i64,
    limit: i64,
    trigger_kind: &str,
) -> Result<Vec<TodoFollowupGenerationJob>> {
    query_due_todo_followup_generation_jobs_internal(conn, now_ms, limit, trigger_kind, false)
}

fn query_due_todo_followup_generation_jobs_internal(
    conn: &Connection,
    now_ms: i64,
    limit: i64,
    trigger_kind: &str,
    include_trigger_kind: bool,
) -> Result<Vec<TodoFollowupGenerationJob>> {
    let running_lease_cutoff_ms = now_ms - TODO_FOLLOWUP_GENERATION_RUNNING_LEASE_MS;
    let filter_sql = if include_trigger_kind { "=" } else { "!=" };
    let sql = format!(
        r#"
SELECT todo_id, trigger_kind, status, attempts, next_retry_at_ms, last_error, include_manual_followups, manual_override_followup, task_type_hint, created_at_ms, updated_at_ms
FROM todo_followup_generation_jobs
WHERE (((
        status IN ('pending', 'failed')
        AND (next_retry_at_ms IS NULL OR next_retry_at_ms <= ?1)
      )
   OR (
        status = 'running'
        AND updated_at_ms <= ?2
      ))
  AND trigger_kind {filter_sql} ?3)
ORDER BY
  CASE WHEN trigger_kind = 'manual_regenerate' THEN created_at_ms ELSE updated_at_ms END ASC,
  todo_id ASC
LIMIT ?4
"#,
    );
    let mut stmt = conn.prepare(&sql)?;
    let mut rows = stmt.query(params![now_ms, running_lease_cutoff_ms, trigger_kind, limit])?;
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
            manual_override_followup: row.get::<_, i64>(7)? != 0,
            task_type_hint: row.get(8)?,
            created_at_ms: row.get(9)?,
            updated_at_ms: row.get(10)?,
        });
    }
    Ok(result)
}

pub fn mark_todo_followup_generation_job_running(
    conn: &Connection,
    todo_id: &str,
    now_ms: i64,
) -> Result<()> {
    let running_lease_cutoff_ms = now_ms - TODO_FOLLOWUP_GENERATION_RUNNING_LEASE_MS;
    let updated = conn.execute(
        r#"
UPDATE todo_followup_generation_jobs
SET status = 'running',
    next_retry_at_ms = NULL,
    last_error = NULL,
    updated_at_ms = ?2
WHERE todo_id = ?1
  AND (
    status IN ('pending', 'failed')
    OR (status = 'running' AND updated_at_ms <= ?3)
  )
"#,
        params![todo_id, now_ms, running_lease_cutoff_ms],
    )?;
    if updated == 0 {
        return Err(anyhow!("todo_followup_generation_job_not_claimed"));
    }
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
  AND status IN ('pending', 'failed', 'running')
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
  AND status = 'running'
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
  AND status IN ('pending', 'failed', 'running')
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
  AND status IN ('pending', 'failed', 'running')
"#,
        params![todo_id, now_ms],
    )?;
    Ok(())
}
