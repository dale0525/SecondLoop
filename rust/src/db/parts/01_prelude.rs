use std::collections::BTreeSet;
use std::fs;
use std::path::{Path, PathBuf};
use std::time::Duration;

use anyhow::{anyhow, Result};
use rusqlite::{params, Connection, OptionalExtension};
use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};
use zerocopy::IntoBytes;

use crate::crypto::{decrypt_bytes, encrypt_bytes};
use crate::embedding::Embedder;
use crate::vector;

const DEFAULT_EMBEDDING_DIM: usize = crate::embedding::DEFAULT_EMBED_DIM;
const MAIN_STREAM_CONVERSATION_ID: &str = "main_stream";
const KV_ACTIVE_EMBEDDING_MODEL_NAME: &str = "embedding.active_model_name";
const KV_ACTIVE_EMBEDDING_DIM: &str = "embedding.active_dim";

#[derive(Clone, Debug)]
pub struct Conversation {
    pub id: String,
    pub title: String,
    pub created_at_ms: i64,
    pub updated_at_ms: i64,
}

#[derive(Clone, Debug)]
pub struct Message {
    pub id: String,
    pub conversation_id: String,
    pub role: String,
    pub content: String,
    pub created_at_ms: i64,
    pub is_memory: bool,
}

#[derive(Clone, Debug)]
pub struct SimilarMessage {
    pub message: Message,
    pub distance: f64,
}

#[derive(Clone, Debug)]
pub struct SimilarTodoThread {
    pub todo_id: String,
    pub distance: f64,
}

#[derive(Clone, Debug)]
pub struct LlmUsageAggregate {
    pub purpose: String,
    pub requests: i64,
    pub requests_with_usage: i64,
    pub input_tokens: i64,
    pub output_tokens: i64,
    pub total_tokens: i64,
}

#[derive(Clone, Debug)]
pub struct LlmProfile {
    pub id: String,
    pub name: String,
    pub provider_type: String,
    pub base_url: Option<String>,
    pub model_name: String,
    pub is_active: bool,
    pub created_at_ms: i64,
    pub updated_at_ms: i64,
}

#[derive(Clone, Debug)]
pub struct LlmProfileConfig {
    pub provider_type: String,
    pub base_url: Option<String>,
    pub api_key: Option<String>,
    pub model_name: String,
}

#[derive(Clone, Debug)]
pub struct EmbeddingProfile {
    pub id: String,
    pub name: String,
    pub provider_type: String,
    pub base_url: Option<String>,
    pub model_name: String,
    pub is_active: bool,
    pub created_at_ms: i64,
    pub updated_at_ms: i64,
}

#[derive(Clone, Debug)]
pub struct EmbeddingProfileConfig {
    pub provider_type: String,
    pub base_url: Option<String>,
    pub api_key: Option<String>,
    pub model_name: String,
}

#[derive(Clone, Debug)]
pub struct Attachment {
    pub sha256: String,
    pub mime_type: String,
    pub path: String,
    pub byte_len: i64,
    pub created_at_ms: i64,
}

#[derive(Clone, Debug)]
pub struct AttachmentVariant {
    pub attachment_sha256: String,
    pub variant: String,
    pub mime_type: String,
    pub path: String,
    pub byte_len: i64,
    pub created_at_ms: i64,
}

#[derive(Clone, Debug, Deserialize, Serialize)]
pub struct AttachmentExifMetadata {
    pub captured_at_ms: Option<i64>,
    pub latitude: Option<f64>,
    pub longitude: Option<f64>,
}

#[derive(Clone, Debug)]
pub struct AttachmentPlaceJob {
    pub attachment_sha256: String,
    pub status: String,
    pub lang: String,
    pub attempts: i64,
    pub next_retry_at_ms: Option<i64>,
    pub last_error: Option<String>,
    pub created_at_ms: i64,
    pub updated_at_ms: i64,
}

#[derive(Clone, Debug)]
pub struct AttachmentAnnotationJob {
    pub attachment_sha256: String,
    pub status: String,
    pub lang: String,
    pub model_name: Option<String>,
    pub attempts: i64,
    pub next_retry_at_ms: Option<i64>,
    pub last_error: Option<String>,
    pub created_at_ms: i64,
    pub updated_at_ms: i64,
}

#[derive(Clone, Debug)]
pub struct SemanticParseJob {
    pub message_id: String,
    pub status: String,
    pub attempts: i64,
    pub next_retry_at_ms: Option<i64>,
    pub last_error: Option<String>,
    pub applied_action_kind: Option<String>,
    pub applied_todo_id: Option<String>,
    pub applied_todo_title: Option<String>,
    pub applied_prev_todo_status: Option<String>,
    pub undone_at_ms: Option<i64>,
    pub created_at_ms: i64,
    pub updated_at_ms: i64,
}

#[derive(Clone, Debug)]
pub struct CloudMediaBackup {
    pub attachment_sha256: String,
    pub desired_variant: String,
    pub byte_len: i64,
    pub status: String,
    pub attempts: i64,
    pub next_retry_at_ms: Option<i64>,
    pub last_error: Option<String>,
    pub updated_at_ms: i64,
}

#[derive(Clone, Debug)]
pub struct CloudMediaBackupSummary {
    pub pending: i64,
    pub failed: i64,
    pub uploaded: i64,
    pub last_uploaded_at_ms: Option<i64>,
    pub last_error: Option<String>,
    pub last_error_at_ms: Option<i64>,
}

#[derive(Clone, Debug)]
pub struct Todo {
    pub id: String,
    pub title: String,
    pub due_at_ms: Option<i64>,
    pub status: String,
    pub source_entry_id: Option<String>,
    pub created_at_ms: i64,
    pub updated_at_ms: i64,
    pub review_stage: Option<i64>,
    pub next_review_at_ms: Option<i64>,
    pub last_review_at_ms: Option<i64>,
}

#[derive(Clone, Debug)]
pub struct TodoActivity {
    pub id: String,
    pub todo_id: String,
    pub activity_type: String,
    pub from_status: Option<String>,
    pub to_status: Option<String>,
    pub content: Option<String>,
    pub source_message_id: Option<String>,
    pub created_at_ms: i64,
}

#[derive(Clone, Debug)]
pub struct Event {
    pub id: String,
    pub title: String,
    pub start_at_ms: i64,
    pub end_at_ms: i64,
    pub tz: String,
    pub source_entry_id: Option<String>,
    pub created_at_ms: i64,
    pub updated_at_ms: i64,
}

fn db_path(app_dir: &Path) -> PathBuf {
    app_dir.join("secondloop.sqlite3")
}

fn now_ms() -> i64 {
    use std::time::{SystemTime, UNIX_EPOCH};

    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or_default()
        .as_millis()
        .try_into()
        .unwrap_or(i64::MAX)
}

fn semantic_parse_job_title_aad(message_id: &str) -> Vec<u8> {
    format!("semantic_parse_job.title:{message_id}").into_bytes()
}

pub fn get_or_create_device_id(conn: &Connection) -> Result<String> {
    let existing: Option<String> = conn
        .query_row(
            r#"SELECT value FROM kv WHERE key = 'device_id'"#,
            [],
            |row| row.get(0),
        )
        .optional()?;

    if let Some(device_id) = existing {
        return Ok(device_id);
    }

    let device_id = uuid::Uuid::new_v4().to_string();
    conn.execute(
        r#"INSERT INTO kv(key, value) VALUES ('device_id', ?1)"#,
        params![device_id],
    )?;
    Ok(device_id)
}

pub fn get_active_embedding_model_name(conn: &Connection) -> Result<Option<String>> {
    let existing: Option<String> = conn
        .query_row(
            "SELECT value FROM kv WHERE key = ?1",
            params![KV_ACTIVE_EMBEDDING_MODEL_NAME],
            |row| row.get(0),
        )
        .optional()?;
    Ok(existing)
}

fn parse_vec_dim_from_column_type(column_type: &str) -> Option<usize> {
    let type_lc = column_type.trim().to_ascii_lowercase();
    let rest = type_lc.strip_prefix("float[")?;
    let digits = rest.strip_suffix(']')?;
    digits.parse::<usize>().ok()
}

fn vec0_dim_from_table(conn: &Connection, table: &str) -> Result<Option<usize>> {
    let stmt = match table {
        "message_embeddings" => "PRAGMA table_info(message_embeddings)",
        "todo_embeddings" => "PRAGMA table_info(todo_embeddings)",
        "todo_activity_embeddings" => "PRAGMA table_info(todo_activity_embeddings)",
        _ => return Err(anyhow!("unknown vec0 table: {table}")),
    };

    let mut stmt = conn.prepare(stmt)?;
    let mut rows = stmt.query([])?;

    while let Some(row) = rows.next()? {
        let name: String = row.get(1)?;
        if name != "embedding" {
            continue;
        }
        let column_type: String = row.get(2)?;
        return Ok(parse_vec_dim_from_column_type(&column_type));
    }

    Ok(None)
}

pub fn get_active_embedding_dim(conn: &Connection) -> Result<Option<usize>> {
    let existing: Option<String> = conn
        .query_row(
            "SELECT value FROM kv WHERE key = ?1",
            params![KV_ACTIVE_EMBEDDING_DIM],
            |row| row.get(0),
        )
        .optional()?;

    let Some(raw) = existing else {
        return Ok(None);
    };
    let trimmed = raw.trim();
    if trimmed.is_empty() {
        return Ok(None);
    }
    let dim = trimmed
        .parse::<usize>()
        .map_err(|_| anyhow!("invalid {KV_ACTIVE_EMBEDDING_DIM}: {raw}"))?;
    Ok(Some(dim))
}

fn current_embedding_dim(conn: &Connection) -> Result<usize> {
    if let Some(dim) = get_active_embedding_dim(conn)? {
        return Ok(dim);
    }
    if let Some(dim) = vec0_dim_from_table(conn, "message_embeddings")? {
        return Ok(dim);
    }
    Ok(DEFAULT_EMBEDDING_DIM)
}

fn embedding_space_id(model_name: &str, dim: usize) -> Result<String> {
    let model_name = model_name.trim();
    if model_name.is_empty() {
        return Err(anyhow!("missing embedding model_name"));
    }
    if dim == 0 || dim > 8192 {
        return Err(anyhow!("invalid embedding dim: {dim}"));
    }

    let mut s = String::new();
    for ch in model_name.chars() {
        if ch.is_ascii_alphanumeric() {
            s.push(ch.to_ascii_lowercase());
        } else {
            s.push('_');
        }
    }
    while s.contains("__") {
        s = s.replace("__", "_");
    }
    let s = s.trim_matches('_');
    let s = if s.is_empty() { "unknown" } else { s };
    Ok(format!("s_{s}_{dim}"))
}

fn is_safe_sqlite_ident(name: &str) -> bool {
    name.chars()
        .all(|ch| ch.is_ascii_alphanumeric() || ch == '_')
}

fn sqlite_table_exists(conn: &Connection, name: &str) -> Result<bool> {
    let count: i64 = conn.query_row(
        "SELECT COUNT(*) FROM sqlite_master WHERE type = 'table' AND name = ?1",
        params![name],
        |row| row.get(0),
    )?;
    Ok(count > 0)
}

fn vec0_dim_from_sqlite_master(conn: &Connection, table: &str) -> Result<Option<usize>> {
    let sql: Option<String> = conn
        .query_row(
            "SELECT sql FROM sqlite_master WHERE type = 'table' AND name = ?1",
            params![table],
            |row| row.get(0),
        )
        .optional()?;
    let Some(sql) = sql else {
        return Ok(None);
    };
    let sql_lc = sql.to_ascii_lowercase();
    let Some(start) = sql_lc.find("float[") else {
        return Ok(None);
    };
    let after = &sql_lc[start + "float[".len()..];
    let Some(end) = after.find(']') else {
        return Ok(None);
    };
    let digits = &after[..end];
    Ok(digits.parse::<usize>().ok())
}

fn message_embeddings_table(space_id: &str) -> Result<String> {
    if !is_safe_sqlite_ident(space_id) {
        return Err(anyhow!("unsafe embedding space_id: {space_id}"));
    }
    Ok(format!("message_embeddings__{space_id}"))
}

fn todo_embeddings_table(space_id: &str) -> Result<String> {
    if !is_safe_sqlite_ident(space_id) {
        return Err(anyhow!("unsafe embedding space_id: {space_id}"));
    }
    Ok(format!("todo_embeddings__{space_id}"))
}

fn todo_activity_embeddings_table(space_id: &str) -> Result<String> {
    if !is_safe_sqlite_ident(space_id) {
        return Err(anyhow!("unsafe embedding space_id: {space_id}"));
    }
    Ok(format!("todo_activity_embeddings__{space_id}"))
}

fn ensure_vec_tables_for_space(conn: &Connection, space_id: &str, dim: usize) -> Result<()> {
    if dim == 0 || dim > 8192 {
        return Err(anyhow!("invalid embedding dim: {dim}"));
    }

    let message_table = message_embeddings_table(space_id)?;
    let todo_table = todo_embeddings_table(space_id)?;
    let activity_table = todo_activity_embeddings_table(space_id)?;

    if !sqlite_table_exists(conn, &message_table)? {
        conn.execute_batch(&format!(
            r#"
CREATE VIRTUAL TABLE "{message_table}" USING vec0(
  embedding float[{dim}],
  +message_id TEXT,
  model_name TEXT
);
"#
        ))?;
    }
    if !sqlite_table_exists(conn, &todo_table)? {
        conn.execute_batch(&format!(
            r#"
CREATE VIRTUAL TABLE "{todo_table}" USING vec0(
  embedding float[{dim}],
  todo_id TEXT,
  model_name TEXT
);
"#
        ))?;
    }
    if !sqlite_table_exists(conn, &activity_table)? {
        conn.execute_batch(&format!(
            r#"
CREATE VIRTUAL TABLE "{activity_table}" USING vec0(
  embedding float[{dim}],
  activity_id TEXT,
  todo_id TEXT,
  model_name TEXT
);
"#
        ))?;
    }

    let msg_dim = vec0_dim_from_sqlite_master(conn, &message_table)?.unwrap_or(0);
    if msg_dim != dim {
        return Err(anyhow!(
            "message vec0 dim mismatch: expected {dim}, got {msg_dim} (table={message_table})"
        ));
    }
    let todo_dim = vec0_dim_from_sqlite_master(conn, &todo_table)?.unwrap_or(0);
    if todo_dim != dim {
        return Err(anyhow!(
            "todo vec0 dim mismatch: expected {dim}, got {todo_dim} (table={todo_table})"
        ));
    }
    let act_dim = vec0_dim_from_sqlite_master(conn, &activity_table)?.unwrap_or(0);
    if act_dim != dim {
        return Err(anyhow!(
            "todo-activity vec0 dim mismatch: expected {dim}, got {act_dim} (table={activity_table})"
        ));
    }

    Ok(())
}

fn recompute_needs_embedding_for_space(conn: &Connection, space_id: &str) -> Result<()> {
    let message_table = message_embeddings_table(space_id)?;
    let todo_table = todo_embeddings_table(space_id)?;
    let activity_table = todo_activity_embeddings_table(space_id)?;

    conn.execute_batch(&format!(
        r#"
UPDATE messages
SET needs_embedding = CASE
  WHEN COALESCE(is_deleted, 0) = 0
   AND COALESCE(is_memory, 1) = 1
   AND NOT EXISTS (SELECT 1 FROM "{message_table}" me WHERE me.rowid = messages.rowid)
  THEN 1
  ELSE 0
END;

UPDATE todos
SET needs_embedding = CASE
  WHEN status != 'dismissed'
   AND NOT EXISTS (SELECT 1 FROM "{todo_table}" te WHERE te.rowid = todos.rowid)
  THEN 1
  ELSE 0
END;

UPDATE todo_activities
SET needs_embedding = CASE
  WHEN NOT EXISTS (
    SELECT 1 FROM "{activity_table}" tae WHERE tae.rowid = todo_activities.rowid
  )
  THEN 1
  ELSE 0
END;
"#
    ))?;
    Ok(())
}

pub fn set_active_embedding_model(conn: &Connection, model_name: &str, dim: usize) -> Result<bool> {
    let existing_model = get_active_embedding_model_name(conn)?;
    let existing_dim = get_active_embedding_dim(conn)?;
    if existing_model.as_deref() == Some(model_name) && existing_dim == Some(dim) {
        return Ok(false);
    }

    conn.execute_batch("BEGIN IMMEDIATE;")?;

    let result = (|| -> Result<bool> {
        let next_space_id = embedding_space_id(model_name, dim)?;

        conn.execute(
            r#"INSERT INTO kv(key, value)
               VALUES (?1, ?2)
               ON CONFLICT(key) DO UPDATE SET value = excluded.value"#,
            params![KV_ACTIVE_EMBEDDING_MODEL_NAME, model_name],
        )?;
        conn.execute(
            r#"INSERT INTO kv(key, value)
               VALUES (?1, ?2)
               ON CONFLICT(key) DO UPDATE SET value = excluded.value"#,
            params![KV_ACTIVE_EMBEDDING_DIM, dim.to_string()],
        )?;

        conn.execute_batch(
            r#"
CREATE TABLE IF NOT EXISTS embedding_spaces (
  space_id TEXT PRIMARY KEY,
  model_name TEXT NOT NULL,
  dim INTEGER NOT NULL,
  created_at_ms INTEGER NOT NULL,
  updated_at_ms INTEGER NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_embedding_spaces_updated_at_ms
  ON embedding_spaces(updated_at_ms);
"#,
        )?;

        let now = now_ms();
        conn.execute(
            r#"INSERT INTO embedding_spaces(space_id, model_name, dim, created_at_ms, updated_at_ms)
               VALUES (?1, ?2, ?3, ?4, ?4)
               ON CONFLICT(space_id) DO UPDATE SET
                 model_name = excluded.model_name,
                 dim = excluded.dim,
                 updated_at_ms = excluded.updated_at_ms"#,
            params![next_space_id, model_name, dim as i64, now],
        )?;

        ensure_vec_tables_for_space(conn, &next_space_id, dim)?;
        recompute_needs_embedding_for_space(conn, &next_space_id)?;

        Ok(true)
    })();

    match result {
        Ok(changed) => {
            conn.execute_batch("COMMIT;")?;
            Ok(changed)
        }
        Err(e) => {
            let _ = conn.execute_batch("ROLLBACK;");
            Err(e)
        }
    }
}

pub fn set_active_embedding_model_name(conn: &Connection, model_name: &str) -> Result<bool> {
    let dim = match model_name {
        crate::embedding::DEFAULT_MODEL_NAME | crate::embedding::PRODUCTION_MODEL_NAME => {
            DEFAULT_EMBEDDING_DIM
        }
        _ => current_embedding_dim(conn)?,
    };
    set_active_embedding_model(conn, model_name, dim)
}

fn next_device_seq(conn: &Connection, device_id: &str) -> Result<i64> {
    let max_seq: Option<i64> = conn.query_row(
        r#"SELECT MAX(seq) FROM oplog WHERE device_id = ?1"#,
        params![device_id],
        |row| row.get(0),
    )?;
    Ok(max_seq.unwrap_or(0) + 1)
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

fn insert_oplog(conn: &Connection, key: &[u8; 32], op_json: &serde_json::Value) -> Result<()> {
    let op_id = op_json["op_id"]
        .as_str()
        .ok_or_else(|| anyhow!("oplog missing op_id"))?;
    let device_id = op_json["device_id"]
        .as_str()
        .ok_or_else(|| anyhow!("oplog missing device_id"))?;
    let seq = op_json["seq"]
        .as_i64()
        .ok_or_else(|| anyhow!("oplog missing seq"))?;
    let created_at = op_json["ts_ms"]
        .as_i64()
        .ok_or_else(|| anyhow!("oplog missing ts_ms"))?;

    let plaintext = serde_json::to_vec(op_json)?;
    let blob = encrypt_bytes(key, &plaintext, format!("oplog.op_json:{op_id}").as_bytes())?;
    conn.execute(
        r#"INSERT INTO oplog(op_id, device_id, seq, op_json, created_at)
           VALUES (?1, ?2, ?3, ?4, ?5)"#,
        params![op_id, device_id, seq, blob, created_at],
    )?;
    Ok(())
}

const KV_ATTACHMENTS_OPLOG_BACKFILLED: &str = "oplog.backfill.attachments.v1";
const KV_ATTACHMENT_EXIF_OPLOG_BACKFILLED: &str = "oplog.backfill.attachment_exif.v1";
const KV_ATTACHMENT_PLACES_OPLOG_BACKFILLED: &str = "oplog.backfill.attachment_places.v1";

pub fn backfill_attachments_oplog_if_needed(conn: &Connection, key: &[u8; 32]) -> Result<u64> {
    let attachments_backfilled = kv_get_string(conn, KV_ATTACHMENTS_OPLOG_BACKFILLED)?.is_some();
    let exif_backfilled = kv_get_string(conn, KV_ATTACHMENT_EXIF_OPLOG_BACKFILLED)?.is_some();
    let places_backfilled = kv_get_string(conn, KV_ATTACHMENT_PLACES_OPLOG_BACKFILLED)?.is_some();
    if attachments_backfilled && exif_backfilled && places_backfilled {
        return Ok(0);
    }

    let device_id = get_or_create_device_id(conn)?;

    let mut ops_inserted = 0u64;

    if !attachments_backfilled {
        let mut stmt = conn.prepare(
            r#"
SELECT sha256, mime_type, byte_len, created_at
FROM attachments
ORDER BY created_at ASC, sha256 ASC
"#,
        )?;
        let mut rows = stmt.query([])?;
        while let Some(row) = rows.next()? {
            let sha256: String = row.get(0)?;
            let mime_type: String = row.get(1)?;
            let byte_len: i64 = row.get(2)?;
            let created_at_ms: i64 = row.get(3)?;

            let seq = next_device_seq(conn, &device_id)?;
            let op = serde_json::json!({
                "op_id": uuid::Uuid::new_v4().to_string(),
                "device_id": device_id.as_str(),
                "seq": seq,
                "ts_ms": created_at_ms,
                "type": "attachment.upsert.v1",
                "payload": {
                    "sha256": sha256,
                    "mime_type": mime_type,
                    "byte_len": byte_len,
                    "created_at_ms": created_at_ms,
                }
            });
            insert_oplog(conn, key, &op)?;
            ops_inserted += 1;
        }
    }

    if !attachments_backfilled {
        let mut stmt = conn.prepare(
            r#"
SELECT message_id, attachment_sha256, created_at
FROM message_attachments
ORDER BY created_at ASC, message_id ASC, attachment_sha256 ASC
"#,
        )?;
        let mut rows = stmt.query([])?;
        while let Some(row) = rows.next()? {
            let message_id: String = row.get(0)?;
            let attachment_sha256: String = row.get(1)?;
            let created_at_ms: i64 = row.get(2)?;

            let seq = next_device_seq(conn, &device_id)?;
            let op = serde_json::json!({
                "op_id": uuid::Uuid::new_v4().to_string(),
                "device_id": device_id.as_str(),
                "seq": seq,
                "ts_ms": created_at_ms,
                "type": "message.attachment.link.v1",
                "payload": {
                    "message_id": message_id,
                    "attachment_sha256": attachment_sha256,
                    "created_at_ms": created_at_ms,
                }
            });
            insert_oplog(conn, key, &op)?;
            ops_inserted += 1;
        }
    }

    if !attachments_backfilled {
        kv_set_string(conn, KV_ATTACHMENTS_OPLOG_BACKFILLED, "1")?;
    }

    if !exif_backfilled {
        let mut stmt = conn.prepare(
            r#"
SELECT attachment_sha256, metadata, created_at_ms, updated_at_ms
FROM attachment_exif
ORDER BY updated_at_ms ASC, attachment_sha256 ASC
"#,
        )?;
        let mut rows = stmt.query([])?;
        while let Some(row) = rows.next()? {
            let attachment_sha256: String = row.get(0)?;
            let blob: Vec<u8> = row.get(1)?;
            let created_at_ms: i64 = row.get(2)?;
            let updated_at_ms: i64 = row.get(3)?;

            let aad = format!("attachment.exif:{attachment_sha256}");
            let json = decrypt_bytes(key, &blob, aad.as_bytes())?;
            let metadata: AttachmentExifMetadata = serde_json::from_slice(&json)?;

            let seq = next_device_seq(conn, &device_id)?;
            let op = serde_json::json!({
                "op_id": uuid::Uuid::new_v4().to_string(),
                "device_id": device_id.as_str(),
                "seq": seq,
                "ts_ms": updated_at_ms,
                "type": "attachment.exif.upsert.v1",
                "payload": {
                    "attachment_sha256": attachment_sha256,
                    "captured_at_ms": metadata.captured_at_ms,
                    "latitude": metadata.latitude,
                    "longitude": metadata.longitude,
                    "created_at_ms": created_at_ms,
                    "updated_at_ms": updated_at_ms,
                }
            });
            insert_oplog(conn, key, &op)?;
            ops_inserted += 1;
        }

        kv_set_string(conn, KV_ATTACHMENT_EXIF_OPLOG_BACKFILLED, "1")?;
    }

    if !places_backfilled {
        let mut stmt = conn.prepare(
            r#"
SELECT attachment_sha256, status, lang, payload, created_at, updated_at
FROM attachment_places
WHERE status = 'ok' AND payload IS NOT NULL
ORDER BY updated_at ASC, attachment_sha256 ASC
"#,
        )?;
        let mut rows = stmt.query([])?;
        while let Some(row) = rows.next()? {
            let attachment_sha256: String = row.get(0)?;
            let status: String = row.get(1)?;
            let lang: String = row.get(2)?;
            let blob: Vec<u8> = row.get(3)?;
            let created_at_ms: i64 = row.get(4)?;
            let updated_at_ms: i64 = row.get(5)?;

            if status != "ok" {
                continue;
            }
            let aad = format!("attachment.place:{attachment_sha256}:{lang}");
            let json = decrypt_bytes(key, &blob, aad.as_bytes())?;
            let payload: serde_json::Value = serde_json::from_slice(&json)?;

            let seq = next_device_seq(conn, &device_id)?;
            let op = serde_json::json!({
                "op_id": uuid::Uuid::new_v4().to_string(),
                "device_id": device_id.as_str(),
                "seq": seq,
                "ts_ms": updated_at_ms,
                "type": "attachment.place.upsert.v1",
                "payload": {
                    "attachment_sha256": attachment_sha256,
                    "lang": lang,
                    "payload": payload,
                    "created_at_ms": created_at_ms,
                    "updated_at_ms": updated_at_ms,
                }
            });
            insert_oplog(conn, key, &op)?;
            ops_inserted += 1;
        }

        kv_set_string(conn, KV_ATTACHMENT_PLACES_OPLOG_BACKFILLED, "1")?;
    }

    Ok(ops_inserted)
}
