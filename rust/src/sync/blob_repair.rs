use anyhow::Result;
use rusqlite::{params, Connection, OptionalExtension};
use serde::{Deserialize, Serialize};
use std::time::{SystemTime, UNIX_EPOCH};

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub enum BlobRepairKind {
    DownloadAttachment { sha256: String },
    DownloadArtifact { blob_ref: String },
    UploadAttachment { sha256: String },
    UploadArtifact { blob_ref: String },
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct BlobRepairItem {
    pub scope_id: String,
    pub kind: BlobRepairKind,
    pub queued_at_ms: i64,
}

#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub struct BlobRepairDiagnostics {
    pub queued_count: u64,
    pub last_attempted_at_ms: Option<i64>,
    pub last_error: Option<String>,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum RepairAttemptOutcome {
    Done,
    RetryLater,
    StopProcessing,
}

#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub struct BlobRepairProcessStats {
    pub attempted: u64,
    pub repaired: u64,
    pub remaining: u64,
}

fn now_ms() -> i64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or_default()
        .as_millis() as i64
}

fn queue_prefix(scope_id: &str) -> String {
    format!("sync.blob_repair.queue:{scope_id}:")
}

fn queue_key(scope_id: &str, kind: &BlobRepairKind) -> String {
    match kind {
        BlobRepairKind::DownloadAttachment { sha256 } => {
            format!("{}download_attachment:{sha256}", queue_prefix(scope_id))
        }
        BlobRepairKind::DownloadArtifact { blob_ref } => {
            format!("{}download_artifact:{blob_ref}", queue_prefix(scope_id))
        }
        BlobRepairKind::UploadAttachment { sha256 } => {
            format!("{}upload_attachment:{sha256}", queue_prefix(scope_id))
        }
        BlobRepairKind::UploadArtifact { blob_ref } => {
            format!("{}upload_artifact:{blob_ref}", queue_prefix(scope_id))
        }
    }
}

fn last_attempt_key(scope_id: &str) -> String {
    format!("sync.blob_repair.last_attempted_at:{scope_id}")
}

fn last_error_key(scope_id: &str) -> String {
    format!("sync.blob_repair.last_error:{scope_id}")
}

fn kv_get_string(conn: &Connection, key: &str) -> Result<Option<String>> {
    conn.query_row(
        r#"SELECT value FROM kv WHERE key = ?1"#,
        params![key],
        |row| row.get(0),
    )
    .optional()
    .map_err(Into::into)
}

fn kv_set_string(conn: &Connection, key: &str, value: &str) -> Result<()> {
    conn.execute(
        r#"INSERT INTO kv(key, value) VALUES (?1, ?2)
           ON CONFLICT(key) DO UPDATE SET value = excluded.value"#,
        params![key, value],
    )?;
    Ok(())
}

fn kv_set_i64(conn: &Connection, key: &str, value: i64) -> Result<()> {
    kv_set_string(conn, key, &value.to_string())
}

fn kv_delete(conn: &Connection, key: &str) -> Result<()> {
    let _ = conn.execute(r#"DELETE FROM kv WHERE key = ?1"#, params![key])?;
    Ok(())
}

pub fn enqueue_blob_repair(conn: &Connection, scope_id: &str, kind: BlobRepairKind) -> Result<()> {
    let item = BlobRepairItem {
        scope_id: scope_id.to_string(),
        kind: kind.clone(),
        queued_at_ms: now_ms(),
    };
    kv_set_string(
        conn,
        &queue_key(scope_id, &kind),
        &serde_json::to_string(&item)?,
    )?;
    Ok(())
}

pub fn load_blob_repair_diagnostics(
    conn: &Connection,
    scope_id: &str,
) -> Result<BlobRepairDiagnostics> {
    let pattern = format!("{}%", queue_prefix(scope_id));
    let queued_count: i64 = conn.query_row(
        r#"SELECT count(*) FROM kv WHERE key LIKE ?1"#,
        params![pattern],
        |row| row.get(0),
    )?;
    let last_attempted_at_ms = kv_get_string(conn, &last_attempt_key(scope_id))?
        .and_then(|value| value.parse::<i64>().ok());
    let last_error = kv_get_string(conn, &last_error_key(scope_id))?;
    Ok(BlobRepairDiagnostics {
        queued_count: queued_count.max(0) as u64,
        last_attempted_at_ms,
        last_error,
    })
}

pub fn clear_blob_repairs_for_scope(conn: &Connection, scope_id: &str) -> Result<()> {
    let pattern = format!("{}%", queue_prefix(scope_id));
    let _ = conn.execute(r#"DELETE FROM kv WHERE key LIKE ?1"#, params![pattern])?;
    kv_delete(conn, &last_attempt_key(scope_id))?;
    kv_delete(conn, &last_error_key(scope_id))?;
    Ok(())
}

fn load_queue_items(conn: &Connection, scope_id: &str) -> Result<Vec<(String, BlobRepairItem)>> {
    let pattern = format!("{}%", queue_prefix(scope_id));
    let mut stmt =
        conn.prepare(r#"SELECT key, value FROM kv WHERE key LIKE ?1 ORDER BY key ASC"#)?;
    let mut rows = stmt.query(params![pattern])?;
    let mut items = Vec::new();
    while let Some(row) = rows.next()? {
        let key: String = row.get(0)?;
        let value: String = row.get(1)?;
        let item: BlobRepairItem = serde_json::from_str(&value)?;
        items.push((key, item));
    }
    Ok(items)
}

pub fn process_blob_repairs(
    conn: &Connection,
    scope_id: &str,
    limit: usize,
    mut handler: impl FnMut(&BlobRepairItem) -> Result<RepairAttemptOutcome>,
) -> Result<BlobRepairProcessStats> {
    if limit == 0 {
        let diagnostics = load_blob_repair_diagnostics(conn, scope_id)?;
        return Ok(BlobRepairProcessStats {
            attempted: 0,
            repaired: 0,
            remaining: diagnostics.queued_count,
        });
    }

    let items = load_queue_items(conn, scope_id)?;
    if items.is_empty() {
        return Ok(BlobRepairProcessStats::default());
    }

    kv_set_i64(conn, &last_attempt_key(scope_id), now_ms())?;
    let mut attempted = 0u64;
    let mut repaired = 0u64;

    for (key, item) in items.iter().take(limit) {
        attempted += 1;
        match handler(item)? {
            RepairAttemptOutcome::Done => {
                kv_delete(conn, key)?;
                repaired += 1;
            }
            RepairAttemptOutcome::RetryLater => {}
            RepairAttemptOutcome::StopProcessing => {
                break;
            }
        }
    }

    let remaining = load_blob_repair_diagnostics(conn, scope_id)?.queued_count;
    Ok(BlobRepairProcessStats {
        attempted,
        repaired,
        remaining,
    })
}

pub fn record_blob_repair_error(conn: &Connection, scope_id: &str, error: &str) -> Result<()> {
    kv_set_string(conn, &last_error_key(scope_id), error)
}

pub fn clear_blob_repair_error(conn: &Connection, scope_id: &str) -> Result<()> {
    kv_delete(conn, &last_error_key(scope_id))
}
