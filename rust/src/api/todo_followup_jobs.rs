use anyhow::{Context, Result};
use rusqlite::Connection;

use crate::db;

const DUE_JOB_REFETCH_LIMIT_MULTIPLIER: i64 = 128;

fn is_todo_access_error(err: &anyhow::Error) -> bool {
    err.chain()
        .any(|cause| cause.to_string().contains("decrypt failed"))
}

pub fn list_visible_due_todo_followup_generation_jobs(
    conn: &Connection,
    key: &[u8; 32],
    now_ms: i64,
    limit: u32,
) -> Result<Vec<db::TodoFollowupGenerationJob>> {
    let requested_limit = i64::from(limit.max(1));
    let max_requested_limit = requested_limit.saturating_mul(DUE_JOB_REFETCH_LIMIT_MULTIPLIER);

    let mut current_limit = requested_limit;
    let mut jobs = db::list_due_todo_followup_generation_jobs(conn, now_ms, current_limit)?;

    loop {
        let mut visible_jobs = Vec::with_capacity(jobs.len());
        for job in &jobs {
            match db::find_todo(conn, key, &job.todo_id) {
                Ok(Some(_)) => visible_jobs.push(job.clone()),
                Ok(None) => {}
                Err(err) => {
                    if is_todo_access_error(&err) {
                        continue;
                    }
                    return Err(err).with_context(|| {
                        format!("failed to read todo for followup job: {}", job.todo_id)
                    });
                }
            }
        }

        if visible_jobs.len() >= requested_limit as usize {
            visible_jobs.truncate(requested_limit as usize);
            return Ok(visible_jobs);
        }

        if jobs.len() < current_limit as usize || current_limit >= max_requested_limit {
            return Ok(visible_jobs);
        }

        let next_limit = (current_limit.saturating_mul(2)).min(max_requested_limit);
        let next_jobs = db::list_due_todo_followup_generation_jobs(conn, now_ms, next_limit)?;
        if next_jobs.len() <= jobs.len() {
            return Ok(visible_jobs);
        }

        jobs = next_jobs;
        current_limit = next_limit;
    }
}

#[cfg(test)]
mod tests {
    use anyhow::anyhow;

    use super::is_todo_access_error;

    #[test]
    fn todo_access_error_matches_wrapped_decrypt_failures_with_extra_context() {
        let err = anyhow!("decrypt failed while reading todo.title");

        assert!(is_todo_access_error(&err));
    }
}
