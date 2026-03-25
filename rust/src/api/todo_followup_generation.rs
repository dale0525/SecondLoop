use std::path::{Path, PathBuf};

use anyhow::{anyhow, Context, Result};

use crate::{api::core::is_todo_access_error, auth, db};

fn key_from_bytes(bytes: Vec<u8>) -> Result<[u8; 32]> {
    bytes
        .try_into()
        .map_err(|_| anyhow!("expected 32-byte key"))
}

fn list_visible_due_auto_todo_followup_generation_jobs(
    conn: &rusqlite::Connection,
    key: &[u8; 32],
    now_ms: i64,
    limit: u32,
) -> Result<Vec<db::TodoFollowupGenerationJob>> {
    let requested_limit = i64::from(limit.max(1));
    let max_requested_limit = requested_limit.saturating_mul(128);

    let mut current_limit = requested_limit;
    let mut jobs = db::list_due_auto_todo_followup_generation_jobs(conn, now_ms, current_limit)?;

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
                    return Err(err).context(format!(
                        "failed to read todo for auto followup job: {}",
                        job.todo_id
                    ));
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
        let next_jobs = db::list_due_auto_todo_followup_generation_jobs(conn, now_ms, next_limit)?;
        if next_jobs.len() <= jobs.len() {
            return Ok(visible_jobs);
        }

        jobs = next_jobs;
        current_limit = next_limit;
    }
}

#[flutter_rust_bridge::frb]
pub fn db_list_due_auto_todo_followup_generation_jobs(
    app_dir: String,
    key: Vec<u8>,
    now_ms: i64,
    limit: u32,
) -> Result<Vec<db::TodoFollowupGenerationJob>> {
    let app_dir = PathBuf::from(app_dir);
    let key = key_from_bytes(key)?;
    auth::validate_key(Path::new(&app_dir), &key)?;
    let conn = db::open(&app_dir)?;
    list_visible_due_auto_todo_followup_generation_jobs(&conn, &key, now_ms, limit)
}
