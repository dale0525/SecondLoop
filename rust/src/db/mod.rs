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

const MESSAGE_EMBEDDING_DIM: usize = 384;
const MAIN_STREAM_CONVERSATION_ID: &str = "main_stream";
const KV_ACTIVE_EMBEDDING_MODEL_NAME: &str = "embedding.active_model_name";

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
pub struct CloudMediaBackup {
    pub attachment_sha256: String,
    pub desired_variant: String,
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

pub fn set_active_embedding_model_name(conn: &Connection, model_name: &str) -> Result<bool> {
    let existing = get_active_embedding_model_name(conn)?;
    if existing.as_deref() == Some(model_name) {
        return Ok(false);
    }

    conn.execute_batch("BEGIN;")?;

    let result = (|| -> Result<bool> {
        conn.execute(
            r#"INSERT INTO kv(key, value)
               VALUES (?1, ?2)
               ON CONFLICT(key) DO UPDATE SET value = excluded.value"#,
            params![KV_ACTIVE_EMBEDDING_MODEL_NAME, model_name],
        )?;

        conn.execute_batch(
            r#"
DELETE FROM message_embeddings;
DELETE FROM todo_embeddings;
DELETE FROM todo_activity_embeddings;
UPDATE messages
SET needs_embedding = CASE
  WHEN COALESCE(is_deleted, 0) = 0 AND COALESCE(is_memory, 1) = 1 THEN 1
  ELSE 0
END;
UPDATE todos
SET needs_embedding = CASE WHEN status != 'dismissed' THEN 1 ELSE 0 END;
UPDATE todo_activities
SET needs_embedding = 1;
"#,
        )?;

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

pub fn backfill_attachments_oplog_if_needed(conn: &Connection, key: &[u8; 32]) -> Result<u64> {
    let attachments_backfilled = kv_get_string(conn, KV_ATTACHMENTS_OPLOG_BACKFILLED)?.is_some();
    let exif_backfilled = kv_get_string(conn, KV_ATTACHMENT_EXIF_OPLOG_BACKFILLED)?.is_some();
    if attachments_backfilled && exif_backfilled {
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

    Ok(ops_inserted)
}

fn migrate(conn: &Connection) -> Result<()> {
    conn.execute_batch("PRAGMA foreign_keys = ON;")?;

    let mut user_version: i64 = conn.query_row("PRAGMA user_version", [], |row| row.get(0))?;
    if user_version < 1 {
        conn.execute_batch(
            r#"
CREATE TABLE IF NOT EXISTS conversations (
  id TEXT PRIMARY KEY,
  title BLOB NOT NULL,
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL
);

CREATE TABLE IF NOT EXISTS messages (
  id TEXT PRIMARY KEY,
  conversation_id TEXT NOT NULL,
  role TEXT NOT NULL,
  content BLOB NOT NULL,
  created_at INTEGER NOT NULL,
  FOREIGN KEY(conversation_id) REFERENCES conversations(id) ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS idx_messages_conversation_created_at
  ON messages(conversation_id, created_at);
"#,
        )?;
        conn.execute_batch("PRAGMA user_version = 1;")?;
        user_version = 1;
    }

    if user_version < 2 {
        // v2: vector schema (sqlite-vec vec0 table) + pending embedding flag.
        //
        // NOTE: `sqlite-vec` must be registered via `sqlite3_auto_extension` BEFORE opening
        // this connection. `db::open()` guarantees that.
        let has_needs_embedding: bool = {
            let mut stmt = conn.prepare("PRAGMA table_info(messages)")?;
            let mut rows = stmt.query([])?;
            let mut found = false;
            while let Some(row) = rows.next()? {
                let name: String = row.get(1)?;
                if name == "needs_embedding" {
                    found = true;
                    break;
                }
            }
            found
        };
        if !has_needs_embedding {
            conn.execute_batch("ALTER TABLE messages ADD COLUMN needs_embedding INTEGER;")?;
        }
        conn.execute_batch(
            "UPDATE messages SET needs_embedding = 1 WHERE needs_embedding IS NULL;",
        )?;

        conn.execute_batch(
            r#"
CREATE VIRTUAL TABLE IF NOT EXISTS message_embeddings USING vec0(
  embedding float[384],
  +message_id TEXT
);
"#,
        )?;

        conn.execute_batch("PRAGMA user_version = 2;")?;
        user_version = 2;
    }

    if user_version < 3 {
        // v3: embedding model versioning.
        //
        // Different embedding models are NOT backward compatible. To prevent mixing vectors from
        // different models, the vector index must record `model_name`. Since `vec0` virtual tables
        // cannot be altered in-place reliably, we rebuild the table and trigger a full re-index.
        conn.execute_batch(
            r#"
DROP TABLE IF EXISTS message_embeddings;
CREATE VIRTUAL TABLE IF NOT EXISTS message_embeddings USING vec0(
  embedding float[384],
  +message_id TEXT,
  model_name TEXT
);
UPDATE messages SET needs_embedding = 1;
PRAGMA user_version = 3;
"#,
        )?;
        user_version = 3;
    }

    if user_version < 4 {
        // v4: LLM provider profiles (encrypted at rest).
        conn.execute_batch(
            r#"
CREATE TABLE IF NOT EXISTS llm_profiles (
  id TEXT PRIMARY KEY,
  name TEXT NOT NULL,
  provider_type TEXT NOT NULL,
  base_url TEXT,
  api_key BLOB,
  model_name TEXT NOT NULL,
  is_active INTEGER NOT NULL DEFAULT 0,
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_llm_profiles_active ON llm_profiles(is_active);
PRAGMA user_version = 4;
"#,
        )?;
        user_version = 4;
    }

    if user_version < 5 {
        // v5: key-value config + operation log for sync.
        conn.execute_batch(
            r#"
CREATE TABLE IF NOT EXISTS kv (
  key TEXT PRIMARY KEY,
  value TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS oplog (
  op_id TEXT PRIMARY KEY,
  device_id TEXT NOT NULL,
  seq INTEGER NOT NULL,
  op_json BLOB NOT NULL,
  created_at INTEGER NOT NULL
);

CREATE UNIQUE INDEX IF NOT EXISTS idx_oplog_device_seq ON oplog(device_id, seq);

PRAGMA user_version = 5;
"#,
        )?;
        user_version = 5;
    }

    if user_version < 6 {
        // v6: message LWW metadata + soft delete for cross-device edit/delete.
        let (
            mut has_updated_at,
            mut has_updated_by_device_id,
            mut has_updated_by_seq,
            mut has_is_deleted,
        ) = (false, false, false, false);
        let mut stmt = conn.prepare("PRAGMA table_info(messages)")?;
        let mut rows = stmt.query([])?;
        while let Some(row) = rows.next()? {
            let name: String = row.get(1)?;
            match name.as_str() {
                "updated_at" => has_updated_at = true,
                "updated_by_device_id" => has_updated_by_device_id = true,
                "updated_by_seq" => has_updated_by_seq = true,
                "is_deleted" => has_is_deleted = true,
                _ => {}
            }
        }

        if !has_updated_at {
            conn.execute_batch("ALTER TABLE messages ADD COLUMN updated_at INTEGER;")?;
        }
        if !has_updated_by_device_id {
            conn.execute_batch("ALTER TABLE messages ADD COLUMN updated_by_device_id TEXT;")?;
        }
        if !has_updated_by_seq {
            conn.execute_batch("ALTER TABLE messages ADD COLUMN updated_by_seq INTEGER;")?;
        }
        if !has_is_deleted {
            conn.execute_batch("ALTER TABLE messages ADD COLUMN is_deleted INTEGER;")?;
        }

        conn.execute_batch(
            r#"
UPDATE messages SET updated_at = created_at WHERE updated_at IS NULL;
UPDATE messages SET updated_by_device_id = '' WHERE updated_by_device_id IS NULL;
UPDATE messages SET updated_by_seq = 0 WHERE updated_by_seq IS NULL;
UPDATE messages SET is_deleted = 0 WHERE is_deleted IS NULL;
PRAGMA user_version = 6;
"#,
        )?;
    }

    if user_version < 7 {
        // v7: classify which messages should be indexed for semantic search.
        let has_is_memory: bool = {
            let mut stmt = conn.prepare("PRAGMA table_info(messages)")?;
            let mut rows = stmt.query([])?;
            let mut found = false;
            while let Some(row) = rows.next()? {
                let name: String = row.get(1)?;
                if name == "is_memory" {
                    found = true;
                    break;
                }
            }
            found
        };
        if !has_is_memory {
            conn.execute_batch("ALTER TABLE messages ADD COLUMN is_memory INTEGER;")?;
        }

        conn.execute_batch(
            r#"
UPDATE messages
SET is_memory = CASE WHEN role = 'assistant' THEN 0 ELSE 1 END
WHERE is_memory IS NULL;

-- Heuristic: for legacy Ask AI flows, mark the user question message (seq-1) as non-memory when
-- it is immediately followed by an assistant message (same device_id/seq ordering).
UPDATE messages
SET is_memory = 0
WHERE role = 'user'
  AND is_memory != 0
  AND EXISTS (
    SELECT 1
    FROM messages a
    WHERE a.conversation_id = messages.conversation_id
      AND a.role = 'assistant'
      AND a.updated_by_device_id = messages.updated_by_device_id
      AND a.updated_by_seq = messages.updated_by_seq + 1
  );

BEGIN;
DELETE FROM message_embeddings;
UPDATE messages
SET needs_embedding = CASE
  WHEN COALESCE(is_deleted, 0) = 0 AND COALESCE(is_memory, 1) = 1 THEN 1
  ELSE 0
END;
COMMIT;

PRAGMA user_version = 7;
"#,
        )?;
    }

    if user_version < 8 {
        // v8: encrypted attachments (for Android Share Intent).
        conn.execute_batch(
            r#"
CREATE TABLE IF NOT EXISTS attachments (
  sha256 TEXT PRIMARY KEY,
  mime_type TEXT NOT NULL,
  path TEXT NOT NULL,
  byte_len INTEGER NOT NULL,
  created_at INTEGER NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_attachments_created_at ON attachments(created_at);
PRAGMA user_version = 8;
"#,
        )?;
    }

    if user_version < 9 {
        // v9: message <-> attachment associations.
        conn.execute_batch(
            r#"
CREATE TABLE IF NOT EXISTS message_attachments (
  message_id TEXT NOT NULL,
  attachment_sha256 TEXT NOT NULL,
  created_at INTEGER NOT NULL,
  PRIMARY KEY (message_id, attachment_sha256),
  FOREIGN KEY(message_id) REFERENCES messages(id) ON DELETE CASCADE,
  FOREIGN KEY(attachment_sha256) REFERENCES attachments(sha256) ON DELETE CASCADE
);
CREATE INDEX IF NOT EXISTS idx_message_attachments_message_created_at
  ON message_attachments(message_id, created_at);
PRAGMA user_version = 9;
"#,
        )?;
    }

    if user_version < 10 {
        // v10: actions (todos/events) + review scheduling metadata.
        conn.execute_batch(
            r#"
CREATE TABLE IF NOT EXISTS todos (
  id TEXT PRIMARY KEY,
  title BLOB NOT NULL,
  due_at_ms INTEGER,
  status TEXT NOT NULL,
  source_entry_id TEXT,
  created_at_ms INTEGER NOT NULL,
  updated_at_ms INTEGER NOT NULL,
  review_stage INTEGER,
  next_review_at_ms INTEGER,
  last_review_at_ms INTEGER
);
CREATE INDEX IF NOT EXISTS idx_todos_due_at_ms ON todos(due_at_ms);
CREATE INDEX IF NOT EXISTS idx_todos_next_review_at_ms ON todos(next_review_at_ms);
CREATE INDEX IF NOT EXISTS idx_todos_status ON todos(status);

CREATE TABLE IF NOT EXISTS events (
  id TEXT PRIMARY KEY,
  title BLOB NOT NULL,
  start_at_ms INTEGER NOT NULL,
  end_at_ms INTEGER NOT NULL,
  tz TEXT NOT NULL,
  source_entry_id TEXT,
  created_at_ms INTEGER NOT NULL,
  updated_at_ms INTEGER NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_events_start_at_ms ON events(start_at_ms);
CREATE INDEX IF NOT EXISTS idx_events_end_at_ms ON events(end_at_ms);
PRAGMA user_version = 10;
"#,
        )?;
    }

    if user_version < 11 {
        // v11: todo activity timeline (status changes + follow-ups).
        conn.execute_batch(
            r#"
CREATE TABLE IF NOT EXISTS todo_activities (
  id TEXT PRIMARY KEY,
  todo_id TEXT NOT NULL,
  type TEXT NOT NULL,
  from_status TEXT,
  to_status TEXT,
  content BLOB,
  source_message_id TEXT,
  created_at_ms INTEGER NOT NULL,
  FOREIGN KEY(todo_id) REFERENCES todos(id) ON DELETE CASCADE
);
CREATE INDEX IF NOT EXISTS idx_todo_activities_todo_created_at_ms
  ON todo_activities(todo_id, created_at_ms);
CREATE INDEX IF NOT EXISTS idx_todo_activities_created_at_ms
  ON todo_activities(created_at_ms);

CREATE TABLE IF NOT EXISTS todo_activity_attachments (
  activity_id TEXT NOT NULL,
  attachment_sha256 TEXT NOT NULL,
  created_at_ms INTEGER NOT NULL,
  PRIMARY KEY (activity_id, attachment_sha256),
  FOREIGN KEY(activity_id) REFERENCES todo_activities(id) ON DELETE CASCADE,
  FOREIGN KEY(attachment_sha256) REFERENCES attachments(sha256) ON DELETE CASCADE
);
CREATE INDEX IF NOT EXISTS idx_todo_activity_attachments_created_at_ms
  ON todo_activity_attachments(created_at_ms);
PRAGMA user_version = 11;
"#,
        )?;
    }

    if user_version < 12 {
        // v12: embeddings for todos and todo activities.
        let has_todo_needs_embedding: bool = {
            let mut stmt = conn.prepare(r#"PRAGMA table_info(todos);"#)?;
            let mut rows = stmt.query([])?;
            let mut found = false;
            while let Some(row) = rows.next()? {
                let name: String = row.get(1)?;
                if name == "needs_embedding" {
                    found = true;
                    break;
                }
            }
            found
        };
        if !has_todo_needs_embedding {
            conn.execute_batch("ALTER TABLE todos ADD COLUMN needs_embedding INTEGER;")?;
            conn.execute_batch(
                "UPDATE todos SET needs_embedding = 1 WHERE needs_embedding IS NULL;",
            )?;
        }

        let has_activity_needs_embedding: bool = {
            let mut stmt = conn.prepare(r#"PRAGMA table_info(todo_activities);"#)?;
            let mut rows = stmt.query([])?;
            let mut found = false;
            while let Some(row) = rows.next()? {
                let name: String = row.get(1)?;
                if name == "needs_embedding" {
                    found = true;
                    break;
                }
            }
            found
        };
        if !has_activity_needs_embedding {
            conn.execute_batch("ALTER TABLE todo_activities ADD COLUMN needs_embedding INTEGER;")?;
            conn.execute_batch(
                "UPDATE todo_activities SET needs_embedding = 1 WHERE needs_embedding IS NULL;",
            )?;
        }

        conn.execute_batch(
            r#"
CREATE VIRTUAL TABLE IF NOT EXISTS todo_embeddings USING vec0(
  embedding float[384],
  todo_id TEXT,
  model_name TEXT
);
CREATE VIRTUAL TABLE IF NOT EXISTS todo_activity_embeddings USING vec0(
  embedding float[384],
  activity_id TEXT,
  todo_id TEXT,
  model_name TEXT
);
PRAGMA user_version = 12;
"#,
        )?;
        user_version = 12;
    }

    if user_version < 13 {
        // v13: local LLM usage metering for BYOK.
        conn.execute_batch(
            r#"
CREATE TABLE IF NOT EXISTS llm_usage_daily (
  day TEXT NOT NULL,
  profile_id TEXT NOT NULL,
  purpose TEXT NOT NULL,
  requests INTEGER NOT NULL DEFAULT 0,
  requests_with_usage INTEGER NOT NULL DEFAULT 0,
  input_tokens INTEGER NOT NULL DEFAULT 0,
  output_tokens INTEGER NOT NULL DEFAULT 0,
  total_tokens INTEGER NOT NULL DEFAULT 0,
  created_at_ms INTEGER NOT NULL,
  updated_at_ms INTEGER NOT NULL,
  PRIMARY KEY (day, profile_id, purpose),
  FOREIGN KEY(profile_id) REFERENCES llm_profiles(id) ON DELETE CASCADE
);
CREATE INDEX IF NOT EXISTS idx_llm_usage_daily_profile_day
  ON llm_usage_daily(profile_id, day);
PRAGMA user_version = 13;
"#,
        )?;
        user_version = 13;
    }

    if user_version < 14 {
        // v14: attachment variants + cloud media backup bookkeeping.
        conn.execute_batch(
            r#"
CREATE TABLE IF NOT EXISTS attachment_variants (
  attachment_sha256 TEXT NOT NULL,
  variant TEXT NOT NULL,
  mime_type TEXT NOT NULL,
  path TEXT NOT NULL,
  byte_len INTEGER NOT NULL,
  created_at INTEGER NOT NULL,
  PRIMARY KEY (attachment_sha256, variant),
  FOREIGN KEY(attachment_sha256) REFERENCES attachments(sha256) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS cloud_media_backup (
  attachment_sha256 TEXT PRIMARY KEY,
  desired_variant TEXT NOT NULL,
  status TEXT NOT NULL,
  attempts INTEGER NOT NULL DEFAULT 0,
  next_retry_at INTEGER,
  last_error TEXT,
  updated_at INTEGER NOT NULL,
  FOREIGN KEY(attachment_sha256) REFERENCES attachments(sha256) ON DELETE CASCADE
);
CREATE INDEX IF NOT EXISTS idx_cloud_media_backup_status_retry
  ON cloud_media_backup(status, next_retry_at);
PRAGMA user_version = 14;
"#,
        )?;
    }

    if user_version < 15 {
        // v15: attachment EXIF metadata (captured time/location) persisted separately from bytes.
        conn.execute_batch(
            r#"
CREATE TABLE IF NOT EXISTS attachment_exif (
  attachment_sha256 TEXT PRIMARY KEY,
  metadata BLOB NOT NULL,
  created_at_ms INTEGER NOT NULL,
  updated_at_ms INTEGER NOT NULL,
  FOREIGN KEY(attachment_sha256) REFERENCES attachments(sha256) ON DELETE CASCADE
);
CREATE INDEX IF NOT EXISTS idx_attachment_exif_updated_at_ms
  ON attachment_exif(updated_at_ms);
PRAGMA user_version = 15;
"#,
        )?;
    }

    if user_version < 16 {
        // v16: attachment deletion tombstones for cross-device purge.
        conn.execute_batch(
            r#"
CREATE TABLE IF NOT EXISTS attachment_deletions (
  sha256 TEXT PRIMARY KEY,
  deleted_at_ms INTEGER NOT NULL,
  deleted_by_device_id TEXT NOT NULL,
  deleted_by_seq INTEGER NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_attachment_deletions_deleted_at_ms
  ON attachment_deletions(deleted_at_ms);
PRAGMA user_version = 16;
"#,
        )?;
    }

    if user_version < 17 {
        // v17: todo deletion tombstones for cross-device hard delete.
        conn.execute_batch(
            r#"
CREATE TABLE IF NOT EXISTS todo_deletions (
  todo_id TEXT PRIMARY KEY,
  deleted_at_ms INTEGER NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_todo_deletions_deleted_at_ms
  ON todo_deletions(deleted_at_ms);
PRAGMA user_version = 17;
"#,
        )?;
    }

    Ok(())
}

pub fn open(app_dir: &Path) -> Result<Connection> {
    fs::create_dir_all(app_dir)?;
    vector::register_sqlite_vec()?;
    let conn = Connection::open(db_path(app_dir))?;
    conn.busy_timeout(Duration::from_millis(5_000))?;
    conn.pragma_update(None, "journal_mode", "WAL")?;
    migrate(&conn)?;
    Ok(conn)
}

pub fn reset_vault_data_preserving_llm_profiles(conn: &Connection) -> Result<()> {
    conn.execute_batch("BEGIN IMMEDIATE;")?;

    let result: Result<()> = (|| {
        conn.execute_batch(
            r#"
DELETE FROM message_embeddings;
DELETE FROM todo_embeddings;
DELETE FROM todo_activity_embeddings;
DELETE FROM messages;
DELETE FROM conversations;
DELETE FROM todos;
DELETE FROM todo_activity_attachments;
DELETE FROM todo_activities;
DELETE FROM events;
DELETE FROM oplog;
DELETE FROM kv WHERE key != 'embedding.active_model_name';
"#,
        )?;
        Ok(())
    })();

    match result {
        Ok(()) => {
            conn.execute_batch("COMMIT;")?;
            Ok(())
        }
        Err(e) => {
            let _ = conn.execute_batch("ROLLBACK;");
            Err(e)
        }
    }
}

pub fn create_conversation(conn: &Connection, key: &[u8; 32], title: &str) -> Result<Conversation> {
    let id = uuid::Uuid::new_v4().to_string();
    let now = now_ms();

    let title_blob = encrypt_bytes(key, title.as_bytes(), b"conversation.title")?;
    conn.execute(
        r#"INSERT INTO conversations (id, title, created_at, updated_at) VALUES (?1, ?2, ?3, ?4)"#,
        params![id, title_blob, now, now],
    )?;

    let device_id = get_or_create_device_id(conn)?;
    let seq = next_device_seq(conn, &device_id)?;
    let op = serde_json::json!({
        "op_id": uuid::Uuid::new_v4().to_string(),
        "device_id": device_id,
        "seq": seq,
        "ts_ms": now,
        "type": "conversation.upsert.v1",
        "payload": {
            "conversation_id": id.clone(),
            "title": title,
            "created_at_ms": now,
            "updated_at_ms": now,
        }
    });
    insert_oplog(conn, key, &op)?;

    Ok(Conversation {
        id,
        title: title.to_string(),
        created_at_ms: now,
        updated_at_ms: now,
    })
}

pub fn get_or_create_main_stream_conversation(
    conn: &Connection,
    key: &[u8; 32],
) -> Result<Conversation> {
    let existing: Option<(Vec<u8>, i64, i64)> = conn
        .query_row(
            r#"SELECT title, created_at, updated_at FROM conversations WHERE id = ?1"#,
            params![MAIN_STREAM_CONVERSATION_ID],
            |row| Ok((row.get(0)?, row.get(1)?, row.get(2)?)),
        )
        .optional()?;

    if let Some((title_blob, created_at_ms, updated_at_ms)) = existing {
        let title_bytes = decrypt_bytes(key, &title_blob, b"conversation.title")?;
        let title = String::from_utf8(title_bytes)
            .map_err(|_| anyhow!("conversation title is not valid utf-8"))?;
        return Ok(Conversation {
            id: MAIN_STREAM_CONVERSATION_ID.to_string(),
            title,
            created_at_ms,
            updated_at_ms,
        });
    }

    let now = now_ms();
    let title = "Main Stream";

    let title_blob = encrypt_bytes(key, title.as_bytes(), b"conversation.title")?;
    conn.execute(
        r#"INSERT INTO conversations (id, title, created_at, updated_at) VALUES (?1, ?2, ?3, ?4)"#,
        params![MAIN_STREAM_CONVERSATION_ID, title_blob, now, now],
    )?;

    let device_id = get_or_create_device_id(conn)?;
    let seq = next_device_seq(conn, &device_id)?;
    let op = serde_json::json!({
        "op_id": uuid::Uuid::new_v4().to_string(),
        "device_id": device_id,
        "seq": seq,
        "ts_ms": now,
        "type": "conversation.upsert.v1",
        "payload": {
            "conversation_id": MAIN_STREAM_CONVERSATION_ID,
            "title": title,
            "created_at_ms": now,
            "updated_at_ms": now,
        }
    });
    insert_oplog(conn, key, &op)?;

    Ok(Conversation {
        id: MAIN_STREAM_CONVERSATION_ID.to_string(),
        title: title.to_string(),
        created_at_ms: now,
        updated_at_ms: now,
    })
}

pub fn list_conversations(conn: &Connection, key: &[u8; 32]) -> Result<Vec<Conversation>> {
    let mut stmt = conn.prepare(
        r#"SELECT id, title, created_at, updated_at FROM conversations ORDER BY updated_at DESC"#,
    )?;

    let mut rows = stmt.query([])?;
    let mut result = Vec::new();
    while let Some(row) = rows.next()? {
        let id: String = row.get(0)?;
        let title_blob: Vec<u8> = row.get(1)?;
        let created_at_ms: i64 = row.get(2)?;
        let updated_at_ms: i64 = row.get(3)?;

        let title_bytes = decrypt_bytes(key, &title_blob, b"conversation.title")?;
        let title = String::from_utf8(title_bytes)
            .map_err(|_| anyhow!("conversation title is not valid utf-8"))?;

        result.push(Conversation {
            id,
            title,
            created_at_ms,
            updated_at_ms,
        });
    }

    Ok(result)
}

pub fn insert_message(
    conn: &Connection,
    key: &[u8; 32],
    conversation_id: &str,
    role: &str,
    content: &str,
) -> Result<Message> {
    insert_message_with_is_memory(
        conn,
        key,
        conversation_id,
        role,
        content,
        role != "assistant",
    )
}

pub fn insert_message_non_memory(
    conn: &Connection,
    key: &[u8; 32],
    conversation_id: &str,
    role: &str,
    content: &str,
) -> Result<Message> {
    insert_message_with_is_memory(conn, key, conversation_id, role, content, false)
}

fn insert_message_with_is_memory(
    conn: &Connection,
    key: &[u8; 32],
    conversation_id: &str,
    role: &str,
    content: &str,
    is_memory: bool,
) -> Result<Message> {
    let id = uuid::Uuid::new_v4().to_string();
    let now = now_ms();

    let device_id = get_or_create_device_id(conn)?;
    let seq = next_device_seq(conn, &device_id)?;

    let content_blob = encrypt_bytes(key, content.as_bytes(), b"message.content")?;
    conn.execute(
        r#"INSERT INTO messages
           (id, conversation_id, role, content, created_at, updated_at, updated_by_device_id, updated_by_seq, is_deleted, needs_embedding, is_memory)
           VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, 0, ?9, ?10)"#,
        params![
            id,
            conversation_id,
            role,
            content_blob,
            now,
            now,
            device_id,
            seq,
            if is_memory { 1 } else { 0 },
            if is_memory { 1 } else { 0 }
        ],
    )?;

    conn.execute(
        r#"UPDATE conversations SET updated_at = ?2 WHERE id = ?1"#,
        params![conversation_id, now],
    )?;

    let op = serde_json::json!({
        "op_id": uuid::Uuid::new_v4().to_string(),
        "device_id": device_id,
        "seq": seq,
        "ts_ms": now,
        "type": "message.insert.v1",
        "payload": {
            "message_id": id.clone(),
            "conversation_id": conversation_id,
            "role": role,
            "content": content,
            "created_at_ms": now,
            "is_memory": is_memory,
        }
    });
    insert_oplog(conn, key, &op)?;

    Ok(Message {
        id,
        conversation_id: conversation_id.to_string(),
        role: role.to_string(),
        content: content.to_string(),
        created_at_ms: now,
        is_memory,
    })
}

pub fn edit_message(
    conn: &Connection,
    key: &[u8; 32],
    message_id: &str,
    content: &str,
) -> Result<()> {
    let (existing, is_memory) = get_message_by_id_with_is_memory(conn, key, message_id)?;
    let conversation_id = existing.conversation_id.clone();
    let role = existing.role.clone();
    let created_at_ms = existing.created_at_ms;
    let now = now_ms();

    let device_id = get_or_create_device_id(conn)?;
    let seq = next_device_seq(conn, &device_id)?;

    let op = serde_json::json!({
        "op_id": uuid::Uuid::new_v4().to_string(),
        "device_id": device_id,
        "seq": seq,
        "ts_ms": now,
        "type": "message.set.v2",
        "payload": {
            "message_id": message_id,
            "conversation_id": conversation_id.as_str(),
            "role": role.as_str(),
            "content": content,
            "created_at_ms": created_at_ms,
            "updated_at_ms": now,
            "is_deleted": false,
            "is_memory": is_memory,
        }
    });
    insert_oplog(conn, key, &op)?;

    let content_blob = encrypt_bytes(key, content.as_bytes(), b"message.content")?;
    let updated = conn.execute(
        r#"UPDATE messages
           SET content = ?2,
               updated_at = ?3,
               updated_by_device_id = ?4,
               updated_by_seq = ?5,
               is_deleted = 0,
               needs_embedding = CASE WHEN COALESCE(is_memory, 1) = 1 THEN 1 ELSE 0 END
           WHERE id = ?1"#,
        params![message_id, content_blob, now, device_id, seq],
    )?;
    if updated == 0 {
        return Err(anyhow!("message not found: {message_id}"));
    }

    conn.execute(
        r#"UPDATE conversations
           SET updated_at = CASE WHEN updated_at < ?2 THEN ?2 ELSE updated_at END
           WHERE id = ?1"#,
        params![conversation_id, now],
    )?;

    Ok(())
}

pub fn set_message_deleted(
    conn: &Connection,
    key: &[u8; 32],
    message_id: &str,
    is_deleted: bool,
) -> Result<()> {
    let (existing, is_memory) = get_message_by_id_with_is_memory(conn, key, message_id)?;
    let conversation_id = existing.conversation_id.clone();
    let role = existing.role.clone();
    let content = existing.content.clone();
    let created_at_ms = existing.created_at_ms;
    let now = now_ms();

    let device_id = get_or_create_device_id(conn)?;
    let seq = next_device_seq(conn, &device_id)?;

    let op = serde_json::json!({
        "op_id": uuid::Uuid::new_v4().to_string(),
        "device_id": device_id,
        "seq": seq,
        "ts_ms": now,
        "type": "message.set.v2",
        "payload": {
            "message_id": message_id,
            "conversation_id": conversation_id.as_str(),
            "role": role.as_str(),
            "content": content.as_str(),
            "created_at_ms": created_at_ms,
            "updated_at_ms": now,
            "is_deleted": is_deleted,
            "is_memory": is_memory,
        }
    });
    insert_oplog(conn, key, &op)?;

    let updated = conn.execute(
        r#"UPDATE messages
           SET updated_at = ?2,
               updated_by_device_id = ?3,
               updated_by_seq = ?4,
               is_deleted = ?5,
               needs_embedding = CASE WHEN ?5 = 0 AND COALESCE(is_memory, 1) = 1 THEN 1 ELSE 0 END
           WHERE id = ?1"#,
        params![
            message_id,
            now,
            device_id,
            seq,
            if is_deleted { 1 } else { 0 }
        ],
    )?;
    if updated == 0 {
        return Err(anyhow!("message not found: {message_id}"));
    }

    conn.execute(
        r#"UPDATE conversations
           SET updated_at = CASE WHEN updated_at < ?2 THEN ?2 ELSE updated_at END
           WHERE id = ?1"#,
        params![conversation_id, now],
    )?;

    Ok(())
}

pub fn append_message_content(
    conn: &Connection,
    key: &[u8; 32],
    message_id: &str,
    text_delta: &str,
) -> Result<()> {
    if text_delta.is_empty() {
        return Ok(());
    }

    let content_blob: Vec<u8> = conn.query_row(
        r#"SELECT content FROM messages WHERE id = ?1"#,
        params![message_id],
        |row| row.get(0),
    )?;
    let content_bytes = decrypt_bytes(key, &content_blob, b"message.content")?;
    let mut content = String::from_utf8(content_bytes)
        .map_err(|_| anyhow!("message content is not valid utf-8"))?;
    content.push_str(text_delta);

    let new_blob = encrypt_bytes(key, content.as_bytes(), b"message.content")?;
    conn.execute(
        r#"UPDATE messages SET content = ?2 WHERE id = ?1"#,
        params![message_id, new_blob],
    )?;

    Ok(())
}

pub fn create_llm_profile(
    conn: &Connection,
    key: &[u8; 32],
    name: &str,
    provider_type: &str,
    base_url: Option<&str>,
    api_key: Option<&str>,
    model_name: &str,
    set_active: bool,
) -> Result<LlmProfile> {
    let id = uuid::Uuid::new_v4().to_string();
    let now = now_ms();

    let api_key_blob: Option<Vec<u8>> = api_key
        .map(|v| encrypt_bytes(key, v.as_bytes(), format!("llm.api_key:{id}").as_bytes()))
        .transpose()?;

    if set_active {
        conn.execute_batch("UPDATE llm_profiles SET is_active = 0;")?;
    }

    conn.execute(
        r#"INSERT INTO llm_profiles
           (id, name, provider_type, base_url, api_key, model_name, is_active, created_at, updated_at)
           VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9)"#,
        params![
            id,
            name,
            provider_type,
            base_url,
            api_key_blob,
            model_name,
            if set_active { 1 } else { 0 },
            now,
            now
        ],
    )?;

    Ok(LlmProfile {
        id,
        name: name.to_string(),
        provider_type: provider_type.to_string(),
        base_url: base_url.map(|v| v.to_string()),
        model_name: model_name.to_string(),
        is_active: set_active,
        created_at_ms: now,
        updated_at_ms: now,
    })
}

pub fn list_llm_profiles(conn: &Connection) -> Result<Vec<LlmProfile>> {
    let mut stmt = conn.prepare(
        r#"SELECT id, name, provider_type, base_url, model_name, is_active, created_at, updated_at
           FROM llm_profiles
           ORDER BY updated_at DESC"#,
    )?;

    let mut rows = stmt.query([])?;
    let mut out: Vec<LlmProfile> = Vec::new();

    while let Some(row) = rows.next()? {
        out.push(LlmProfile {
            id: row.get(0)?,
            name: row.get(1)?,
            provider_type: row.get(2)?,
            base_url: row.get(3)?,
            model_name: row.get(4)?,
            is_active: row.get::<_, i64>(5)? != 0,
            created_at_ms: row.get(6)?,
            updated_at_ms: row.get(7)?,
        });
    }

    Ok(out)
}

pub fn set_active_llm_profile(conn: &Connection, profile_id: &str) -> Result<()> {
    let now = now_ms();

    conn.execute_batch("BEGIN IMMEDIATE;")?;

    let result: Result<()> = (|| {
        let updated = conn.execute(
            r#"UPDATE llm_profiles
               SET is_active = 1, updated_at = ?2
               WHERE id = ?1"#,
            params![profile_id, now],
        )?;

        if updated == 0 {
            return Err(anyhow!("llm profile not found: {profile_id}"));
        }

        conn.execute(
            r#"UPDATE llm_profiles SET is_active = 0 WHERE id != ?1"#,
            params![profile_id],
        )?;

        Ok(())
    })();

    match result {
        Ok(()) => {
            conn.execute_batch("COMMIT;")?;
            Ok(())
        }
        Err(e) => {
            let _ = conn.execute_batch("ROLLBACK;");
            Err(e)
        }
    }
}

pub fn delete_llm_profile(conn: &Connection, profile_id: &str) -> Result<()> {
    let deleted = conn.execute(
        r#"DELETE FROM llm_profiles WHERE id = ?1"#,
        params![profile_id],
    )?;

    if deleted == 0 {
        return Err(anyhow!("llm profile not found: {profile_id}"));
    }

    Ok(())
}

pub fn load_active_llm_profile_config(
    conn: &Connection,
    key: &[u8; 32],
) -> Result<Option<(String, LlmProfileConfig)>> {
    let row = conn
        .query_row(
            r#"SELECT id, provider_type, base_url, api_key, model_name
               FROM llm_profiles
               WHERE is_active = 1
               ORDER BY updated_at DESC
               LIMIT 1"#,
            [],
            |row| {
                Ok((
                    row.get::<_, String>(0)?,
                    row.get::<_, String>(1)?,
                    row.get::<_, Option<String>>(2)?,
                    row.get::<_, Option<Vec<u8>>>(3)?,
                    row.get::<_, String>(4)?,
                ))
            },
        )
        .optional()?;

    let Some((id, provider_type, base_url, api_key_blob, model_name)) = row else {
        return Ok(None);
    };

    let api_key = match api_key_blob {
        Some(blob) => {
            let api_key_bytes = decrypt_bytes(key, &blob, format!("llm.api_key:{id}").as_bytes())?;

            Some(
                String::from_utf8(api_key_bytes)
                    .map_err(|_| anyhow!("llm api_key is not valid utf-8"))?,
            )
        }
        None => None,
    };

    Ok(Some((
        id,
        LlmProfileConfig {
            provider_type,
            base_url,
            api_key,
            model_name,
        },
    )))
}

pub fn record_llm_usage_daily(
    conn: &Connection,
    day: &str,
    profile_id: &str,
    purpose: &str,
    input_tokens: Option<i64>,
    output_tokens: Option<i64>,
    total_tokens: Option<i64>,
) -> Result<()> {
    let now = now_ms();

    let has_usage = input_tokens.is_some() && output_tokens.is_some() && total_tokens.is_some();
    let requests_with_usage = if has_usage { 1 } else { 0 };

    conn.execute(
        r#"INSERT INTO llm_usage_daily
           (day, profile_id, purpose, requests, requests_with_usage, input_tokens, output_tokens, total_tokens, created_at_ms, updated_at_ms)
           VALUES (?1, ?2, ?3, 1, ?4, ?5, ?6, ?7, ?8, ?8)
           ON CONFLICT(day, profile_id, purpose) DO UPDATE SET
             requests = llm_usage_daily.requests + excluded.requests,
             requests_with_usage = llm_usage_daily.requests_with_usage + excluded.requests_with_usage,
             input_tokens = llm_usage_daily.input_tokens + excluded.input_tokens,
             output_tokens = llm_usage_daily.output_tokens + excluded.output_tokens,
             total_tokens = llm_usage_daily.total_tokens + excluded.total_tokens,
             updated_at_ms = excluded.updated_at_ms"#,
        params![
            day,
            profile_id,
            purpose,
            requests_with_usage,
            input_tokens.unwrap_or(0),
            output_tokens.unwrap_or(0),
            total_tokens.unwrap_or(0),
            now
        ],
    )?;

    Ok(())
}

pub fn sum_llm_usage_daily_by_purpose(
    conn: &Connection,
    profile_id: &str,
    start_day: &str,
    end_day: &str,
) -> Result<Vec<LlmUsageAggregate>> {
    let mut stmt = conn.prepare(
        r#"SELECT purpose,
                  COALESCE(SUM(requests), 0),
                  COALESCE(SUM(requests_with_usage), 0),
                  COALESCE(SUM(input_tokens), 0),
                  COALESCE(SUM(output_tokens), 0),
                  COALESCE(SUM(total_tokens), 0)
           FROM llm_usage_daily
           WHERE profile_id = ?1
             AND day >= ?2
             AND day <= ?3
           GROUP BY purpose
           ORDER BY purpose ASC"#,
    )?;

    let mut rows = stmt.query(params![profile_id, start_day, end_day])?;
    let mut out = Vec::new();
    while let Some(row) = rows.next()? {
        out.push(LlmUsageAggregate {
            purpose: row.get(0)?,
            requests: row.get(1)?,
            requests_with_usage: row.get(2)?,
            input_tokens: row.get(3)?,
            output_tokens: row.get(4)?,
            total_tokens: row.get(5)?,
        });
    }

    Ok(out)
}

fn default_embedding_model_name_for_platform() -> &'static str {
    if cfg!(any(
        target_os = "windows",
        target_os = "macos",
        target_os = "linux"
    )) {
        crate::embedding::PRODUCTION_MODEL_NAME
    } else {
        crate::embedding::DEFAULT_MODEL_NAME
    }
}

fn normalize_embedding_model_name(name: &str) -> &'static str {
    match name {
        crate::embedding::DEFAULT_MODEL_NAME => crate::embedding::DEFAULT_MODEL_NAME,
        crate::embedding::PRODUCTION_MODEL_NAME => crate::embedding::PRODUCTION_MODEL_NAME,
        _ => default_embedding_model_name_for_platform(),
    }
}

fn desired_embedding_model_name(conn: &Connection) -> Result<&'static str> {
    let stored = get_active_embedding_model_name(conn)?;
    Ok(stored
        .as_deref()
        .map(normalize_embedding_model_name)
        .unwrap_or_else(default_embedding_model_name_for_platform))
}

fn default_embed_text(text: &str) -> Vec<f32> {
    let mut v = vec![0.0f32; MESSAGE_EMBEDDING_DIM];
    let t = text.to_lowercase();

    if t.contains("apple") {
        v[0] += 1.0;
    }
    if t.contains("pie") {
        v[0] += 1.0;
    }
    if t.contains("banana") {
        v[1] += 1.0;
    }

    v
}

pub fn process_pending_message_embeddings_active(
    conn: &Connection,
    key: &[u8; 32],
    app_dir: &Path,
    limit: usize,
) -> Result<usize> {
    let desired = desired_embedding_model_name(conn)?;

    if desired == crate::embedding::DEFAULT_MODEL_NAME {
        set_active_embedding_model_name(conn, crate::embedding::DEFAULT_MODEL_NAME)?;
        return process_pending_message_embeddings_default(conn, key, limit);
    }

    if desired == crate::embedding::PRODUCTION_MODEL_NAME {
        #[cfg(all(
            any(target_os = "windows", target_os = "macos", target_os = "linux"),
            not(frb_expand)
        ))]
        {
            match crate::embedding::FastEmbedder::get_or_try_init(app_dir) {
                Ok(embedder) => {
                    set_active_embedding_model_name(conn, crate::embedding::PRODUCTION_MODEL_NAME)?;
                    return process_pending_message_embeddings(conn, key, &embedder, limit);
                }
                Err(e) => return Err(anyhow!("production embeddings unavailable: {e}")),
            }
        }

        #[cfg(not(all(
            any(target_os = "windows", target_os = "macos", target_os = "linux"),
            not(frb_expand)
        )))]
        {
            set_active_embedding_model_name(conn, crate::embedding::DEFAULT_MODEL_NAME)?;
            return process_pending_message_embeddings_default(conn, key, limit);
        }
    }

    set_active_embedding_model_name(conn, crate::embedding::DEFAULT_MODEL_NAME)?;
    process_pending_message_embeddings_default(conn, key, limit)
}

pub fn process_pending_todo_embeddings_active(
    conn: &Connection,
    key: &[u8; 32],
    app_dir: &Path,
    limit: usize,
) -> Result<usize> {
    let desired = desired_embedding_model_name(conn)?;

    if desired == crate::embedding::DEFAULT_MODEL_NAME {
        set_active_embedding_model_name(conn, crate::embedding::DEFAULT_MODEL_NAME)?;
        return process_pending_todo_embeddings_default(conn, key, limit);
    }

    if desired == crate::embedding::PRODUCTION_MODEL_NAME {
        #[cfg(all(
            any(target_os = "windows", target_os = "macos", target_os = "linux"),
            not(frb_expand)
        ))]
        {
            match crate::embedding::FastEmbedder::get_or_try_init(app_dir) {
                Ok(embedder) => {
                    set_active_embedding_model_name(conn, crate::embedding::PRODUCTION_MODEL_NAME)?;
                    return process_pending_todo_embeddings(conn, key, &embedder, limit);
                }
                Err(e) => return Err(anyhow!("production embeddings unavailable: {e}")),
            }
        }

        #[cfg(not(all(
            any(target_os = "windows", target_os = "macos", target_os = "linux"),
            not(frb_expand)
        )))]
        {
            set_active_embedding_model_name(conn, crate::embedding::DEFAULT_MODEL_NAME)?;
            return process_pending_todo_embeddings_default(conn, key, limit);
        }
    }

    set_active_embedding_model_name(conn, crate::embedding::DEFAULT_MODEL_NAME)?;
    process_pending_todo_embeddings_default(conn, key, limit)
}

pub fn process_pending_todo_activity_embeddings_active(
    conn: &Connection,
    key: &[u8; 32],
    app_dir: &Path,
    limit: usize,
) -> Result<usize> {
    let desired = desired_embedding_model_name(conn)?;

    if desired == crate::embedding::DEFAULT_MODEL_NAME {
        set_active_embedding_model_name(conn, crate::embedding::DEFAULT_MODEL_NAME)?;
        return process_pending_todo_activity_embeddings_default(conn, key, limit);
    }

    if desired == crate::embedding::PRODUCTION_MODEL_NAME {
        #[cfg(all(
            any(target_os = "windows", target_os = "macos", target_os = "linux"),
            not(frb_expand)
        ))]
        {
            match crate::embedding::FastEmbedder::get_or_try_init(app_dir) {
                Ok(embedder) => {
                    set_active_embedding_model_name(conn, crate::embedding::PRODUCTION_MODEL_NAME)?;
                    return process_pending_todo_activity_embeddings(conn, key, &embedder, limit);
                }
                Err(e) => return Err(anyhow!("production embeddings unavailable: {e}")),
            }
        }

        #[cfg(not(all(
            any(target_os = "windows", target_os = "macos", target_os = "linux"),
            not(frb_expand)
        )))]
        {
            set_active_embedding_model_name(conn, crate::embedding::DEFAULT_MODEL_NAME)?;
            return process_pending_todo_activity_embeddings_default(conn, key, limit);
        }
    }

    set_active_embedding_model_name(conn, crate::embedding::DEFAULT_MODEL_NAME)?;
    process_pending_todo_activity_embeddings_default(conn, key, limit)
}

pub fn rebuild_message_embeddings_active(
    conn: &Connection,
    key: &[u8; 32],
    app_dir: &Path,
    batch_limit: usize,
) -> Result<usize> {
    let desired = desired_embedding_model_name(conn)?;

    if desired == crate::embedding::DEFAULT_MODEL_NAME {
        set_active_embedding_model_name(conn, crate::embedding::DEFAULT_MODEL_NAME)?;
        return rebuild_message_embeddings_default(conn, key, batch_limit);
    }

    if desired == crate::embedding::PRODUCTION_MODEL_NAME {
        #[cfg(all(
            any(target_os = "windows", target_os = "macos", target_os = "linux"),
            not(frb_expand)
        ))]
        {
            match crate::embedding::FastEmbedder::get_or_try_init(app_dir) {
                Ok(embedder) => {
                    set_active_embedding_model_name(conn, crate::embedding::PRODUCTION_MODEL_NAME)?;
                    return rebuild_message_embeddings(conn, key, &embedder, batch_limit);
                }
                Err(e) => return Err(anyhow!("production embeddings unavailable: {e}")),
            }
        }

        #[cfg(not(all(
            any(target_os = "windows", target_os = "macos", target_os = "linux"),
            not(frb_expand)
        )))]
        {
            set_active_embedding_model_name(conn, crate::embedding::DEFAULT_MODEL_NAME)?;
            return rebuild_message_embeddings_default(conn, key, batch_limit);
        }
    }

    set_active_embedding_model_name(conn, crate::embedding::DEFAULT_MODEL_NAME)?;
    rebuild_message_embeddings_default(conn, key, batch_limit)
}

pub fn search_similar_messages_active(
    conn: &Connection,
    key: &[u8; 32],
    app_dir: &Path,
    query: &str,
    top_k: usize,
) -> Result<Vec<SimilarMessage>> {
    let desired = desired_embedding_model_name(conn)?;

    if desired == crate::embedding::DEFAULT_MODEL_NAME {
        set_active_embedding_model_name(conn, crate::embedding::DEFAULT_MODEL_NAME)?;
        return search_similar_messages_default(conn, key, query, top_k);
    }

    if desired == crate::embedding::PRODUCTION_MODEL_NAME {
        #[cfg(all(
            any(target_os = "windows", target_os = "macos", target_os = "linux"),
            not(frb_expand)
        ))]
        {
            match crate::embedding::FastEmbedder::get_or_try_init(app_dir) {
                Ok(embedder) => {
                    set_active_embedding_model_name(conn, crate::embedding::PRODUCTION_MODEL_NAME)?;
                    return search_similar_messages(conn, key, &embedder, query, top_k);
                }
                Err(e) => return Err(anyhow!("production embeddings unavailable: {e}")),
            }
        }

        #[cfg(not(all(
            any(target_os = "windows", target_os = "macos", target_os = "linux"),
            not(frb_expand)
        )))]
        {
            set_active_embedding_model_name(conn, crate::embedding::DEFAULT_MODEL_NAME)?;
            return search_similar_messages_default(conn, key, query, top_k);
        }
    }

    set_active_embedding_model_name(conn, crate::embedding::DEFAULT_MODEL_NAME)?;
    search_similar_messages_default(conn, key, query, top_k)
}

pub fn search_similar_messages_in_conversation_active(
    conn: &Connection,
    key: &[u8; 32],
    app_dir: &Path,
    conversation_id: &str,
    query: &str,
    top_k: usize,
) -> Result<Vec<SimilarMessage>> {
    let desired = desired_embedding_model_name(conn)?;

    if desired == crate::embedding::DEFAULT_MODEL_NAME {
        set_active_embedding_model_name(conn, crate::embedding::DEFAULT_MODEL_NAME)?;
        return search_similar_messages_in_conversation_default(
            conn,
            key,
            conversation_id,
            query,
            top_k,
        );
    }

    if desired == crate::embedding::PRODUCTION_MODEL_NAME {
        #[cfg(all(
            any(target_os = "windows", target_os = "macos", target_os = "linux"),
            not(frb_expand)
        ))]
        {
            match crate::embedding::FastEmbedder::get_or_try_init(app_dir) {
                Ok(embedder) => {
                    set_active_embedding_model_name(conn, crate::embedding::PRODUCTION_MODEL_NAME)?;
                    return search_similar_messages_in_conversation(
                        conn,
                        key,
                        &embedder,
                        conversation_id,
                        query,
                        top_k,
                    );
                }
                Err(e) => return Err(anyhow!("production embeddings unavailable: {e}")),
            }
        }

        #[cfg(not(all(
            any(target_os = "windows", target_os = "macos", target_os = "linux"),
            not(frb_expand)
        )))]
        {
            set_active_embedding_model_name(conn, crate::embedding::DEFAULT_MODEL_NAME)?;
            return search_similar_messages_in_conversation_default(
                conn,
                key,
                conversation_id,
                query,
                top_k,
            );
        }
    }

    set_active_embedding_model_name(conn, crate::embedding::DEFAULT_MODEL_NAME)?;
    search_similar_messages_in_conversation_default(conn, key, conversation_id, query, top_k)
}

pub fn search_similar_todo_threads_active(
    conn: &Connection,
    key: &[u8; 32],
    app_dir: &Path,
    query: &str,
    top_k: usize,
) -> Result<Vec<SimilarTodoThread>> {
    let desired = desired_embedding_model_name(conn)?;

    if desired == crate::embedding::DEFAULT_MODEL_NAME {
        set_active_embedding_model_name(conn, crate::embedding::DEFAULT_MODEL_NAME)?;
        return search_similar_todo_threads_default(conn, key, query, top_k);
    }

    if desired == crate::embedding::PRODUCTION_MODEL_NAME {
        #[cfg(all(
            any(target_os = "windows", target_os = "macos", target_os = "linux"),
            not(frb_expand)
        ))]
        {
            match crate::embedding::FastEmbedder::get_or_try_init(app_dir) {
                Ok(embedder) => {
                    set_active_embedding_model_name(conn, crate::embedding::PRODUCTION_MODEL_NAME)?;
                    return search_similar_todo_threads(conn, key, &embedder, query, top_k);
                }
                Err(e) => return Err(anyhow!("production embeddings unavailable: {e}")),
            }
        }

        #[cfg(not(all(
            any(target_os = "windows", target_os = "macos", target_os = "linux"),
            not(frb_expand)
        )))]
        {
            set_active_embedding_model_name(conn, crate::embedding::DEFAULT_MODEL_NAME)?;
            return search_similar_todo_threads_default(conn, key, query, top_k);
        }
    }

    set_active_embedding_model_name(conn, crate::embedding::DEFAULT_MODEL_NAME)?;
    search_similar_todo_threads_default(conn, key, query, top_k)
}

pub fn process_pending_message_embeddings<E: Embedder + ?Sized>(
    conn: &Connection,
    key: &[u8; 32],
    embedder: &E,
    limit: usize,
) -> Result<usize> {
    if embedder.dim() != MESSAGE_EMBEDDING_DIM {
        return Err(anyhow!(
            "embedder dim mismatch: expected {}, got {}",
            MESSAGE_EMBEDDING_DIM,
            embedder.dim()
        ));
    }

    let mut stmt = conn.prepare(
        r#"SELECT rowid, id, content
           FROM messages
           WHERE COALESCE(needs_embedding, 1) = 1
             AND COALESCE(is_deleted, 0) = 0
             AND COALESCE(is_memory, 1) = 1
           ORDER BY created_at ASC
           LIMIT ?1"#,
    )?;

    let mut rows = stmt.query(params![i64::try_from(limit).unwrap_or(i64::MAX)])?;
    let mut message_rowids: Vec<i64> = Vec::new();
    let mut message_ids: Vec<String> = Vec::new();
    let mut plaintexts: Vec<String> = Vec::new();

    while let Some(row) = rows.next()? {
        let rowid: i64 = row.get(0)?;
        let id: String = row.get(1)?;
        let content_blob: Vec<u8> = row.get(2)?;

        let content_bytes = decrypt_bytes(key, &content_blob, b"message.content")?;
        let content = String::from_utf8(content_bytes)
            .map_err(|_| anyhow!("message content is not valid utf-8"))?;

        message_rowids.push(rowid);
        message_ids.push(id);
        plaintexts.push(format!("passage: {content}"));
    }

    if plaintexts.is_empty() {
        return Ok(0);
    }

    let embeddings = embedder.embed(&plaintexts)?;
    if embeddings.len() != plaintexts.len() {
        return Err(anyhow!(
            "embedder output length mismatch: expected {}, got {}",
            plaintexts.len(),
            embeddings.len()
        ));
    }

    for i in 0..message_ids.len() {
        let updated = conn.execute(
            r#"UPDATE message_embeddings
               SET embedding = ?2, message_id = ?3, model_name = ?4
               WHERE rowid = ?1"#,
            params![
                message_rowids[i],
                embeddings[i].as_bytes(),
                message_ids[i],
                embedder.model_name()
            ],
        )?;
        if updated == 0 {
            conn.execute(
                r#"INSERT INTO message_embeddings(rowid, embedding, message_id, model_name)
                   VALUES (?1, ?2, ?3, ?4)"#,
                params![
                    message_rowids[i],
                    embeddings[i].as_bytes(),
                    message_ids[i],
                    embedder.model_name()
                ],
            )?;
        }
        conn.execute(
            r#"UPDATE messages SET needs_embedding = 0 WHERE rowid = ?1"#,
            params![message_rowids[i]],
        )?;
    }

    Ok(message_ids.len())
}

pub fn process_pending_todo_embeddings<E: Embedder + ?Sized>(
    conn: &Connection,
    key: &[u8; 32],
    embedder: &E,
    limit: usize,
) -> Result<usize> {
    if embedder.dim() != MESSAGE_EMBEDDING_DIM {
        return Err(anyhow!(
            "embedder dim mismatch: expected {}, got {}",
            MESSAGE_EMBEDDING_DIM,
            embedder.dim()
        ));
    }

    let mut stmt = conn.prepare(
        r#"SELECT rowid, id, title, status, due_at_ms
           FROM todos
           WHERE COALESCE(needs_embedding, 1) = 1
             AND status != 'dismissed'
           ORDER BY updated_at_ms ASC
           LIMIT ?1"#,
    )?;

    let mut rows = stmt.query(params![i64::try_from(limit).unwrap_or(i64::MAX)])?;
    let mut todo_rowids: Vec<i64> = Vec::new();
    let mut todo_ids: Vec<String> = Vec::new();
    let mut plaintexts: Vec<String> = Vec::new();

    while let Some(row) = rows.next()? {
        let rowid: i64 = row.get(0)?;
        let id: String = row.get(1)?;
        let title_blob: Vec<u8> = row.get(2)?;
        let status: String = row.get(3)?;
        let due_at_ms: Option<i64> = row.get(4)?;

        let title_bytes = decrypt_bytes(key, &title_blob, b"todo.title")?;
        let title =
            String::from_utf8(title_bytes).map_err(|_| anyhow!("todo title is not valid utf-8"))?;

        let mut text = format!("TODO [{status}] {title}");
        if let Some(ms) = due_at_ms {
            text.push_str(&format!(" (due_at_ms={ms})"));
        }

        todo_rowids.push(rowid);
        todo_ids.push(id);
        plaintexts.push(format!("passage: {text}"));
    }

    if plaintexts.is_empty() {
        return Ok(0);
    }

    let embeddings = embedder.embed(&plaintexts)?;
    if embeddings.len() != plaintexts.len() {
        return Err(anyhow!(
            "embedder output length mismatch: expected {}, got {}",
            plaintexts.len(),
            embeddings.len()
        ));
    }

    for i in 0..todo_ids.len() {
        let updated = conn.execute(
            r#"UPDATE todo_embeddings
               SET embedding = ?2, todo_id = ?3, model_name = ?4
               WHERE rowid = ?1"#,
            params![
                todo_rowids[i],
                embeddings[i].as_bytes(),
                todo_ids[i],
                embedder.model_name()
            ],
        )?;
        if updated == 0 {
            conn.execute(
                r#"INSERT INTO todo_embeddings(rowid, embedding, todo_id, model_name)
                   VALUES (?1, ?2, ?3, ?4)"#,
                params![
                    todo_rowids[i],
                    embeddings[i].as_bytes(),
                    todo_ids[i],
                    embedder.model_name()
                ],
            )?;
        }

        conn.execute(
            r#"UPDATE todos SET needs_embedding = 0 WHERE rowid = ?1"#,
            params![todo_rowids[i]],
        )?;
    }

    Ok(todo_ids.len())
}

fn status_embedding_hint(status: &str) -> String {
    match status {
        "inbox" => "inbox needs confirmation not started 待确认 未开始".to_string(),
        "in_progress" => "in_progress doing ongoing 进行中".to_string(),
        "done" => "done completed finished 完成 已完成".to_string(),
        "dismissed" => "dismissed deleted removed 已删除".to_string(),
        _ => status.to_string(),
    }
}

pub fn process_pending_todo_activity_embeddings<E: Embedder + ?Sized>(
    conn: &Connection,
    key: &[u8; 32],
    embedder: &E,
    limit: usize,
) -> Result<usize> {
    if embedder.dim() != MESSAGE_EMBEDDING_DIM {
        return Err(anyhow!(
            "embedder dim mismatch: expected {}, got {}",
            MESSAGE_EMBEDDING_DIM,
            embedder.dim()
        ));
    }

    let mut stmt = conn.prepare(
        r#"SELECT a.rowid, a.id, a.todo_id, a.type, a.from_status, a.to_status, a.content
           FROM todo_activities a
           LEFT JOIN todos t ON t.id = a.todo_id
           WHERE COALESCE(a.needs_embedding, 1) = 1
             AND (t.status IS NULL OR t.status != 'dismissed')
           ORDER BY a.created_at_ms ASC
           LIMIT ?1"#,
    )?;

    let mut rows = stmt.query(params![i64::try_from(limit).unwrap_or(i64::MAX)])?;
    let mut activity_rowids: Vec<i64> = Vec::new();
    let mut activity_ids: Vec<String> = Vec::new();
    let mut todo_ids: Vec<String> = Vec::new();
    let mut plaintexts: Vec<String> = Vec::new();

    while let Some(row) = rows.next()? {
        let rowid: i64 = row.get(0)?;
        let id: String = row.get(1)?;
        let todo_id: String = row.get(2)?;
        let activity_type: String = row.get(3)?;
        let from_status: Option<String> = row.get(4)?;
        let to_status: Option<String> = row.get(5)?;
        let content_blob: Option<Vec<u8>> = row.get(6)?;

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

        let text =
            if let Some(content) = content.as_deref().map(str::trim).filter(|s| !s.is_empty()) {
                format!("TODO activity note: {content}")
            } else if activity_type == "status_change" {
                let from = from_status.as_deref().unwrap_or("unknown");
                let to = to_status.as_deref().unwrap_or("unknown");
                format!(
                    "TODO status changed from {} to {}",
                    status_embedding_hint(from),
                    status_embedding_hint(to)
                )
            } else {
                format!("TODO activity {activity_type}")
            };

        activity_rowids.push(rowid);
        activity_ids.push(id);
        todo_ids.push(todo_id);
        plaintexts.push(format!("passage: {text}"));
    }

    if plaintexts.is_empty() {
        return Ok(0);
    }

    let embeddings = embedder.embed(&plaintexts)?;
    if embeddings.len() != plaintexts.len() {
        return Err(anyhow!(
            "embedder output length mismatch: expected {}, got {}",
            plaintexts.len(),
            embeddings.len()
        ));
    }

    for i in 0..activity_ids.len() {
        let updated = conn.execute(
            r#"UPDATE todo_activity_embeddings
               SET embedding = ?2, activity_id = ?3, todo_id = ?4, model_name = ?5
               WHERE rowid = ?1"#,
            params![
                activity_rowids[i],
                embeddings[i].as_bytes(),
                activity_ids[i],
                todo_ids[i],
                embedder.model_name()
            ],
        )?;
        if updated == 0 {
            conn.execute(
                r#"INSERT INTO todo_activity_embeddings(rowid, embedding, activity_id, todo_id, model_name)
                   VALUES (?1, ?2, ?3, ?4, ?5)"#,
                params![
                    activity_rowids[i],
                    embeddings[i].as_bytes(),
                    activity_ids[i],
                    todo_ids[i],
                    embedder.model_name()
                ],
            )?;
        }
        conn.execute(
            r#"UPDATE todo_activities SET needs_embedding = 0 WHERE rowid = ?1"#,
            params![activity_rowids[i]],
        )?;
    }

    Ok(activity_ids.len())
}

pub fn process_pending_message_embeddings_default(
    conn: &Connection,
    key: &[u8; 32],
    limit: usize,
) -> Result<usize> {
    let mut stmt = conn.prepare(
        r#"SELECT rowid, id, content
           FROM messages
           WHERE COALESCE(needs_embedding, 1) = 1
             AND COALESCE(is_deleted, 0) = 0
             AND COALESCE(is_memory, 1) = 1
           ORDER BY created_at ASC
           LIMIT ?1"#,
    )?;

    let mut rows = stmt.query(params![i64::try_from(limit).unwrap_or(i64::MAX)])?;
    let mut message_rowids: Vec<i64> = Vec::new();
    let mut message_ids: Vec<String> = Vec::new();
    let mut plaintexts: Vec<String> = Vec::new();

    while let Some(row) = rows.next()? {
        let rowid: i64 = row.get(0)?;
        let id: String = row.get(1)?;
        let content_blob: Vec<u8> = row.get(2)?;

        let content_bytes = decrypt_bytes(key, &content_blob, b"message.content")?;
        let content = String::from_utf8(content_bytes)
            .map_err(|_| anyhow!("message content is not valid utf-8"))?;

        message_rowids.push(rowid);
        message_ids.push(id);
        plaintexts.push(format!("passage: {content}"));
    }

    if plaintexts.is_empty() {
        return Ok(0);
    }

    for i in 0..message_ids.len() {
        let embedding = default_embed_text(&plaintexts[i]);
        if embedding.len() != MESSAGE_EMBEDDING_DIM {
            return Err(anyhow!(
                "default embed dim mismatch: expected {}, got {}",
                MESSAGE_EMBEDDING_DIM,
                embedding.len()
            ));
        }

        let updated = conn.execute(
            r#"UPDATE message_embeddings
               SET embedding = ?2, message_id = ?3, model_name = ?4
               WHERE rowid = ?1"#,
            params![
                message_rowids[i],
                embedding.as_bytes(),
                message_ids[i],
                crate::embedding::DEFAULT_MODEL_NAME
            ],
        )?;
        if updated == 0 {
            conn.execute(
                r#"INSERT INTO message_embeddings(rowid, embedding, message_id, model_name)
                   VALUES (?1, ?2, ?3, ?4)"#,
                params![
                    message_rowids[i],
                    embedding.as_bytes(),
                    message_ids[i],
                    crate::embedding::DEFAULT_MODEL_NAME
                ],
            )?;
        }
        conn.execute(
            r#"UPDATE messages SET needs_embedding = 0 WHERE rowid = ?1"#,
            params![message_rowids[i]],
        )?;
    }

    Ok(message_ids.len())
}

pub fn process_pending_todo_embeddings_default(
    conn: &Connection,
    key: &[u8; 32],
    limit: usize,
) -> Result<usize> {
    let mut stmt = conn.prepare(
        r#"SELECT rowid, id, title, status, due_at_ms
           FROM todos
           WHERE COALESCE(needs_embedding, 1) = 1
             AND status != 'dismissed'
           ORDER BY updated_at_ms ASC
           LIMIT ?1"#,
    )?;

    let mut rows = stmt.query(params![i64::try_from(limit).unwrap_or(i64::MAX)])?;
    let mut todo_rowids: Vec<i64> = Vec::new();
    let mut todo_ids: Vec<String> = Vec::new();
    let mut plaintexts: Vec<String> = Vec::new();

    while let Some(row) = rows.next()? {
        let rowid: i64 = row.get(0)?;
        let id: String = row.get(1)?;
        let title_blob: Vec<u8> = row.get(2)?;
        let status: String = row.get(3)?;
        let due_at_ms: Option<i64> = row.get(4)?;

        let title_bytes = decrypt_bytes(key, &title_blob, b"todo.title")?;
        let title =
            String::from_utf8(title_bytes).map_err(|_| anyhow!("todo title is not valid utf-8"))?;

        let mut text = format!("TODO [{status}] {title}");
        if let Some(ms) = due_at_ms {
            text.push_str(&format!(" (due_at_ms={ms})"));
        }

        todo_rowids.push(rowid);
        todo_ids.push(id);
        plaintexts.push(format!("passage: {text}"));
    }

    if plaintexts.is_empty() {
        return Ok(0);
    }

    for i in 0..todo_ids.len() {
        let embedding = default_embed_text(&plaintexts[i]);
        if embedding.len() != MESSAGE_EMBEDDING_DIM {
            return Err(anyhow!(
                "default embed dim mismatch: expected {}, got {}",
                MESSAGE_EMBEDDING_DIM,
                embedding.len()
            ));
        }

        let updated = conn.execute(
            r#"UPDATE todo_embeddings
               SET embedding = ?2, todo_id = ?3, model_name = ?4
               WHERE rowid = ?1"#,
            params![
                todo_rowids[i],
                embedding.as_bytes(),
                todo_ids[i],
                crate::embedding::DEFAULT_MODEL_NAME
            ],
        )?;
        if updated == 0 {
            conn.execute(
                r#"INSERT INTO todo_embeddings(rowid, embedding, todo_id, model_name)
                   VALUES (?1, ?2, ?3, ?4)"#,
                params![
                    todo_rowids[i],
                    embedding.as_bytes(),
                    todo_ids[i],
                    crate::embedding::DEFAULT_MODEL_NAME
                ],
            )?;
        }

        conn.execute(
            r#"UPDATE todos SET needs_embedding = 0 WHERE rowid = ?1"#,
            params![todo_rowids[i]],
        )?;
    }

    Ok(todo_ids.len())
}

pub fn process_pending_todo_activity_embeddings_default(
    conn: &Connection,
    key: &[u8; 32],
    limit: usize,
) -> Result<usize> {
    let mut stmt = conn.prepare(
        r#"SELECT a.rowid, a.id, a.todo_id, a.type, a.from_status, a.to_status, a.content
           FROM todo_activities a
           LEFT JOIN todos t ON t.id = a.todo_id
           WHERE COALESCE(a.needs_embedding, 1) = 1
             AND (t.status IS NULL OR t.status != 'dismissed')
           ORDER BY a.created_at_ms ASC
           LIMIT ?1"#,
    )?;

    let mut rows = stmt.query(params![i64::try_from(limit).unwrap_or(i64::MAX)])?;
    let mut activity_rowids: Vec<i64> = Vec::new();
    let mut activity_ids: Vec<String> = Vec::new();
    let mut todo_ids: Vec<String> = Vec::new();
    let mut plaintexts: Vec<String> = Vec::new();

    while let Some(row) = rows.next()? {
        let rowid: i64 = row.get(0)?;
        let id: String = row.get(1)?;
        let todo_id: String = row.get(2)?;
        let activity_type: String = row.get(3)?;
        let from_status: Option<String> = row.get(4)?;
        let to_status: Option<String> = row.get(5)?;
        let content_blob: Option<Vec<u8>> = row.get(6)?;

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

        let text =
            if let Some(content) = content.as_deref().map(str::trim).filter(|s| !s.is_empty()) {
                format!("TODO activity note: {content}")
            } else if activity_type == "status_change" {
                let from = from_status.as_deref().unwrap_or("unknown");
                let to = to_status.as_deref().unwrap_or("unknown");
                format!(
                    "TODO status changed from {} to {}",
                    status_embedding_hint(from),
                    status_embedding_hint(to)
                )
            } else {
                format!("TODO activity {activity_type}")
            };

        activity_rowids.push(rowid);
        activity_ids.push(id);
        todo_ids.push(todo_id);
        plaintexts.push(format!("passage: {text}"));
    }

    if plaintexts.is_empty() {
        return Ok(0);
    }

    for i in 0..activity_ids.len() {
        let embedding = default_embed_text(&plaintexts[i]);
        if embedding.len() != MESSAGE_EMBEDDING_DIM {
            return Err(anyhow!(
                "default embed dim mismatch: expected {}, got {}",
                MESSAGE_EMBEDDING_DIM,
                embedding.len()
            ));
        }

        let updated = conn.execute(
            r#"UPDATE todo_activity_embeddings
               SET embedding = ?2, activity_id = ?3, todo_id = ?4, model_name = ?5
               WHERE rowid = ?1"#,
            params![
                activity_rowids[i],
                embedding.as_bytes(),
                activity_ids[i],
                todo_ids[i],
                crate::embedding::DEFAULT_MODEL_NAME
            ],
        )?;
        if updated == 0 {
            conn.execute(
                r#"INSERT INTO todo_activity_embeddings(rowid, embedding, activity_id, todo_id, model_name)
                   VALUES (?1, ?2, ?3, ?4, ?5)"#,
                params![
                    activity_rowids[i],
                    embedding.as_bytes(),
                    activity_ids[i],
                    todo_ids[i],
                    crate::embedding::DEFAULT_MODEL_NAME
                ],
            )?;
        }

        conn.execute(
            r#"UPDATE todo_activities SET needs_embedding = 0 WHERE rowid = ?1"#,
            params![activity_rowids[i]],
        )?;
    }

    Ok(activity_ids.len())
}

pub fn rebuild_message_embeddings<E: Embedder + ?Sized>(
    conn: &Connection,
    key: &[u8; 32],
    embedder: &E,
    batch_limit: usize,
) -> Result<usize> {
    conn.execute_batch(
        r#"
BEGIN;
DELETE FROM message_embeddings;
UPDATE messages
SET needs_embedding = CASE
  WHEN COALESCE(is_deleted, 0) = 0 AND COALESCE(is_memory, 1) = 1 THEN 1
  ELSE 0
END;
COMMIT;
"#,
    )?;

    let batch_limit = batch_limit.max(1);
    let mut total = 0usize;
    loop {
        let processed = process_pending_message_embeddings(conn, key, embedder, batch_limit)?;
        total += processed;
        if processed == 0 {
            break;
        }
    }

    Ok(total)
}

pub fn rebuild_message_embeddings_default(
    conn: &Connection,
    key: &[u8; 32],
    batch_limit: usize,
) -> Result<usize> {
    conn.execute_batch(
        r#"
BEGIN;
DELETE FROM message_embeddings;
UPDATE messages
SET needs_embedding = CASE
  WHEN COALESCE(is_deleted, 0) = 0 AND COALESCE(is_memory, 1) = 1 THEN 1
  ELSE 0
END;
COMMIT;
"#,
    )?;

    let batch_limit = batch_limit.max(1);
    let mut total = 0usize;
    loop {
        let processed = process_pending_message_embeddings_default(conn, key, batch_limit)?;
        total += processed;
        if processed == 0 {
            break;
        }
    }

    Ok(total)
}

pub fn list_messages(
    conn: &Connection,
    key: &[u8; 32],
    conversation_id: &str,
) -> Result<Vec<Message>> {
    let mut stmt = conn.prepare(
        r#"SELECT id, role, content, created_at, COALESCE(is_memory, 1)
           FROM messages
           WHERE conversation_id = ?1 AND COALESCE(is_deleted, 0) = 0
           ORDER BY created_at ASC"#,
    )?;

    let mut rows = stmt.query(params![conversation_id])?;
    let mut result = Vec::new();
    while let Some(row) = rows.next()? {
        let id: String = row.get(0)?;
        let role: String = row.get(1)?;
        let content_blob: Vec<u8> = row.get(2)?;
        let created_at_ms: i64 = row.get(3)?;
        let is_memory_i64: i64 = row.get(4)?;

        let content_bytes = decrypt_bytes(key, &content_blob, b"message.content")?;
        let content = String::from_utf8(content_bytes)
            .map_err(|_| anyhow!("message content is not valid utf-8"))?;

        result.push(Message {
            id,
            conversation_id: conversation_id.to_string(),
            role,
            content,
            created_at_ms,
            is_memory: is_memory_i64 != 0,
        });
    }

    Ok(result)
}

pub fn list_messages_page(
    conn: &Connection,
    key: &[u8; 32],
    conversation_id: &str,
    before_created_at_ms: Option<i64>,
    before_id: Option<&str>,
    limit: i64,
) -> Result<Vec<Message>> {
    let limit = limit.clamp(1, 500);

    let mut stmt = match (before_created_at_ms, before_id) {
        (None, None) => conn.prepare(
            r#"SELECT id, role, content, created_at, COALESCE(is_memory, 1)
               FROM messages
               WHERE conversation_id = ?1 AND COALESCE(is_deleted, 0) = 0
               ORDER BY created_at DESC, id DESC
               LIMIT ?2"#,
        )?,
        (Some(_), Some(_)) => conn.prepare(
            r#"SELECT id, role, content, created_at, COALESCE(is_memory, 1)
               FROM messages
               WHERE conversation_id = ?1 AND COALESCE(is_deleted, 0) = 0
                 AND (created_at < ?2 OR (created_at = ?2 AND id < ?3))
               ORDER BY created_at DESC, id DESC
               LIMIT ?4"#,
        )?,
        (Some(_), None) | (None, Some(_)) => {
            return Err(anyhow!(
                "invalid cursor: both before_created_at_ms and before_id required"
            ))
        }
    };

    let mut rows = match (before_created_at_ms, before_id) {
        (None, None) => stmt.query(params![conversation_id, limit])?,
        (Some(ts), Some(id)) => stmt.query(params![conversation_id, ts, id, limit])?,
        _ => unreachable!(),
    };

    let mut result = Vec::new();
    while let Some(row) = rows.next()? {
        let id: String = row.get(0)?;
        let role: String = row.get(1)?;
        let content_blob: Vec<u8> = row.get(2)?;
        let created_at_ms: i64 = row.get(3)?;
        let is_memory_i64: i64 = row.get(4)?;

        let content_bytes = decrypt_bytes(key, &content_blob, b"message.content")?;
        let content = String::from_utf8(content_bytes)
            .map_err(|_| anyhow!("message content is not valid utf-8"))?;

        result.push(Message {
            id,
            conversation_id: conversation_id.to_string(),
            role,
            content,
            created_at_ms,
            is_memory: is_memory_i64 != 0,
        });
    }

    Ok(result)
}

pub fn get_message_by_id_optional(
    conn: &Connection,
    key: &[u8; 32],
    id: &str,
) -> Result<Option<Message>> {
    let row: Option<(String, String, Vec<u8>, i64, i64)> = conn
        .query_row(
            r#"SELECT conversation_id, role, content, created_at, COALESCE(is_memory, 1)
               FROM messages
               WHERE id = ?1 AND COALESCE(is_deleted, 0) = 0"#,
            params![id],
            |row| {
                Ok((
                    row.get(0)?,
                    row.get(1)?,
                    row.get(2)?,
                    row.get(3)?,
                    row.get(4)?,
                ))
            },
        )
        .optional()?;

    let Some((conversation_id, role, content_blob, created_at_ms, is_memory_i64)) = row else {
        return Ok(None);
    };

    let content_bytes = decrypt_bytes(key, &content_blob, b"message.content")?;
    let content = String::from_utf8(content_bytes)
        .map_err(|_| anyhow!("message content is not valid utf-8"))?;

    Ok(Some(Message {
        id: id.to_string(),
        conversation_id,
        role,
        content,
        created_at_ms,
        is_memory: is_memory_i64 != 0,
    }))
}

fn get_message_by_id(conn: &Connection, key: &[u8; 32], id: &str) -> Result<Message> {
    let (conversation_id, role, content_blob, created_at_ms, is_memory_i64): (
        String,
        String,
        Vec<u8>,
        i64,
        i64,
    ) = conn
        .query_row(
            r#"SELECT conversation_id, role, content, created_at, COALESCE(is_memory, 1)
               FROM messages
               WHERE id = ?1"#,
            params![id],
            |row| {
                Ok((
                    row.get(0)?,
                    row.get(1)?,
                    row.get(2)?,
                    row.get(3)?,
                    row.get(4)?,
                ))
            },
        )
        .map_err(|e| anyhow!("get message failed: {e}"))?;

    let content_bytes = decrypt_bytes(key, &content_blob, b"message.content")?;
    let content = String::from_utf8(content_bytes)
        .map_err(|_| anyhow!("message content is not valid utf-8"))?;

    Ok(Message {
        id: id.to_string(),
        conversation_id,
        role,
        content,
        created_at_ms,
        is_memory: is_memory_i64 != 0,
    })
}

fn get_message_by_id_with_is_memory(
    conn: &Connection,
    key: &[u8; 32],
    id: &str,
) -> Result<(Message, bool)> {
    let (conversation_id, role, content_blob, created_at_ms, is_memory_i64): (
        String,
        String,
        Vec<u8>,
        i64,
        i64,
    ) = conn
        .query_row(
            r#"SELECT conversation_id, role, content, created_at, COALESCE(is_memory, 1)
               FROM messages
               WHERE id = ?1"#,
            params![id],
            |row| {
                Ok((
                    row.get(0)?,
                    row.get(1)?,
                    row.get(2)?,
                    row.get(3)?,
                    row.get(4)?,
                ))
            },
        )
        .map_err(|e| anyhow!("get message failed: {e}"))?;

    let content_bytes = decrypt_bytes(key, &content_blob, b"message.content")?;
    let content = String::from_utf8(content_bytes)
        .map_err(|_| anyhow!("message content is not valid utf-8"))?;

    Ok((
        Message {
            id: id.to_string(),
            conversation_id,
            role,
            content,
            created_at_ms,
            is_memory: is_memory_i64 != 0,
        },
        is_memory_i64 != 0,
    ))
}

pub fn search_similar_messages<E: Embedder + ?Sized>(
    conn: &Connection,
    key: &[u8; 32],
    embedder: &E,
    query: &str,
    top_k: usize,
) -> Result<Vec<SimilarMessage>> {
    if embedder.dim() != MESSAGE_EMBEDDING_DIM {
        return Err(anyhow!(
            "embedder dim mismatch: expected {}, got {}",
            MESSAGE_EMBEDDING_DIM,
            embedder.dim()
        ));
    }

    let top_k = top_k.max(1);
    let candidate_k = (top_k.saturating_mul(10)).min(1000);

    let query = format!("query: {query}");
    let mut vectors = embedder.embed(&[query])?;
    if vectors.len() != 1 {
        return Err(anyhow!(
            "embedder output length mismatch: expected 1, got {}",
            vectors.len()
        ));
    }
    let query_vector = vectors.remove(0);

    let mut stmt = conn.prepare(
        r#"SELECT message_id, distance
           FROM message_embeddings
           WHERE embedding match ?1 AND k = ?2 AND model_name = ?3
           ORDER BY distance ASC"#,
    )?;

    let mut rows = stmt.query(params![
        query_vector.as_bytes(),
        i64::try_from(candidate_k).unwrap_or(i64::MAX),
        embedder.model_name()
    ])?;

    let mut result = Vec::new();
    let mut seen_contents = std::collections::HashSet::new();
    while let Some(row) = rows.next()? {
        let message_id: String = row.get(0)?;
        let distance: f64 = row.get(1)?;
        let message = get_message_by_id(conn, key, &message_id)?;
        if !seen_contents.insert(message.content.clone()) {
            continue;
        }
        result.push(SimilarMessage { message, distance });
        if result.len() >= top_k {
            break;
        }
    }

    Ok(result)
}

pub fn search_similar_messages_default(
    conn: &Connection,
    key: &[u8; 32],
    query: &str,
    top_k: usize,
) -> Result<Vec<SimilarMessage>> {
    search_similar_messages_lite(conn, key, None, query, top_k)
}

pub fn search_similar_messages_in_conversation_default(
    conn: &Connection,
    key: &[u8; 32],
    conversation_id: &str,
    query: &str,
    top_k: usize,
) -> Result<Vec<SimilarMessage>> {
    search_similar_messages_lite(conn, key, Some(conversation_id), query, top_k)
}

pub fn search_similar_todo_threads<E: Embedder + ?Sized>(
    conn: &Connection,
    _key: &[u8; 32],
    embedder: &E,
    query: &str,
    top_k: usize,
) -> Result<Vec<SimilarTodoThread>> {
    if embedder.dim() != MESSAGE_EMBEDDING_DIM {
        return Err(anyhow!(
            "embedder dim mismatch: expected {}, got {}",
            MESSAGE_EMBEDDING_DIM,
            embedder.dim()
        ));
    }

    let top_k = top_k.max(1);
    let candidate_k = (top_k.saturating_mul(10)).min(1000);

    let query = format!("query: {query}");
    let mut vectors = embedder.embed(&[query])?;
    if vectors.len() != 1 {
        return Err(anyhow!(
            "embedder output length mismatch: expected 1, got {}",
            vectors.len()
        ));
    }
    let query_vector = vectors.remove(0);

    let mut best: std::collections::HashMap<String, f64> = std::collections::HashMap::new();

    {
        let mut stmt = conn.prepare(
            r#"SELECT te.todo_id, te.distance
               FROM todo_embeddings te
               JOIN todos t ON t.id = te.todo_id
               WHERE te.embedding match ?1 AND te.k = ?2 AND te.model_name = ?3
                 AND t.status != 'dismissed'
               ORDER BY te.distance ASC"#,
        )?;

        let mut rows = stmt.query(params![
            query_vector.as_bytes(),
            i64::try_from(candidate_k).unwrap_or(i64::MAX),
            embedder.model_name()
        ])?;

        while let Some(row) = rows.next()? {
            let todo_id: String = row.get(0)?;
            let distance: f64 = row.get(1)?;
            best.entry(todo_id)
                .and_modify(|d| *d = (*d).min(distance))
                .or_insert(distance);
        }
    }

    {
        let mut stmt = conn.prepare(
            r#"SELECT tae.todo_id, tae.distance
               FROM todo_activity_embeddings tae
               JOIN todos t ON t.id = tae.todo_id
               WHERE tae.embedding match ?1 AND tae.k = ?2 AND tae.model_name = ?3
                 AND t.status != 'dismissed'
               ORDER BY tae.distance ASC"#,
        )?;

        let mut rows = stmt.query(params![
            query_vector.as_bytes(),
            i64::try_from(candidate_k).unwrap_or(i64::MAX),
            embedder.model_name()
        ])?;

        while let Some(row) = rows.next()? {
            let todo_id: String = row.get(0)?;
            let distance: f64 = row.get(1)?;
            best.entry(todo_id)
                .and_modify(|d| *d = (*d).min(distance))
                .or_insert(distance);
        }
    }

    let mut result: Vec<SimilarTodoThread> = best
        .into_iter()
        .map(|(todo_id, distance)| SimilarTodoThread { todo_id, distance })
        .collect();
    result.sort_by(|a, b| {
        a.distance
            .partial_cmp(&b.distance)
            .unwrap_or(std::cmp::Ordering::Equal)
            .then_with(|| a.todo_id.cmp(&b.todo_id))
    });
    result.truncate(top_k);
    Ok(result)
}

pub fn search_similar_todo_threads_default(
    conn: &Connection,
    key: &[u8; 32],
    query: &str,
    top_k: usize,
) -> Result<Vec<SimilarTodoThread>> {
    let top_k = top_k.max(1);

    let query_norm = lite_normalize_text(query);
    let query_compact = lite_compact_text(&query_norm);
    if query_compact.is_empty() {
        return Ok(Vec::new());
    }

    let query_chars: Vec<char> = query_compact.chars().collect();
    let query_bigrams = lite_collect_bigrams(&query_chars);
    let query_trigrams = lite_collect_trigrams(&query_chars);

    let mut result: Vec<SimilarTodoThread> = Vec::new();

    for todo in list_todos(conn, key)? {
        if todo.status == "dismissed" {
            continue;
        }

        let activities = list_todo_activities(conn, key, &todo.id)?;
        let mut text = String::new();
        text.push_str("TODO ");
        text.push_str(&todo.title);
        for a in activities {
            text.push('\n');
            text.push_str("ACTIVITY ");
            text.push_str(&a.activity_type);
            if let Some(from) = a.from_status.as_deref() {
                text.push_str(" from=");
                text.push_str(from);
            }
            if let Some(to) = a.to_status.as_deref() {
                text.push_str(" to=");
                text.push_str(to);
            }
            if let Some(content) = a.content.as_deref() {
                text.push_str(" content=");
                text.push_str(content);
            }
        }

        let score = lite_score(
            &query_norm,
            &query_compact,
            &query_bigrams,
            &query_trigrams,
            &text,
        );
        if score == 0 {
            continue;
        }

        let distance = 1.0 / (score as f64 + 1.0);
        result.push(SimilarTodoThread {
            todo_id: todo.id,
            distance,
        });
    }

    result.sort_by(|a, b| {
        a.distance
            .partial_cmp(&b.distance)
            .unwrap_or(std::cmp::Ordering::Equal)
            .then_with(|| a.todo_id.cmp(&b.todo_id))
    });
    result.truncate(top_k);
    Ok(result)
}

fn search_similar_messages_lite(
    conn: &Connection,
    key: &[u8; 32],
    conversation_id: Option<&str>,
    query: &str,
    top_k: usize,
) -> Result<Vec<SimilarMessage>> {
    let top_k = top_k.max(1);

    let query_norm = lite_normalize_text(query);
    let query_compact = lite_compact_text(&query_norm);
    if query_compact.is_empty() {
        return Ok(Vec::new());
    }

    let query_chars: Vec<char> = query_compact.chars().collect();
    let query_bigrams = lite_collect_bigrams(&query_chars);
    let query_trigrams = lite_collect_trigrams(&query_chars);

    let mut result: Vec<SimilarMessage> = Vec::new();
    let mut seen_contents = std::collections::HashSet::new();

    let mut stmt = if conversation_id.is_some() {
        conn.prepare(
            r#"SELECT id, conversation_id, role, content, created_at
               FROM messages
               WHERE conversation_id = ?1
                 AND COALESCE(is_deleted, 0) = 0
                 AND COALESCE(is_memory, 1) = 1
               ORDER BY created_at DESC"#,
        )?
    } else {
        conn.prepare(
            r#"SELECT id, conversation_id, role, content, created_at
               FROM messages
               WHERE COALESCE(is_deleted, 0) = 0
                 AND COALESCE(is_memory, 1) = 1
               ORDER BY created_at DESC"#,
        )?
    };

    let mut rows = if let Some(conversation_id) = conversation_id {
        stmt.query(params![conversation_id])?
    } else {
        stmt.query([])?
    };

    while let Some(row) = rows.next()? {
        let id: String = row.get(0)?;
        let conversation_id: String = row.get(1)?;
        let role: String = row.get(2)?;
        let content_blob: Vec<u8> = row.get(3)?;
        let created_at_ms: i64 = row.get(4)?;

        let content_bytes = decrypt_bytes(key, &content_blob, b"message.content")?;
        let content = String::from_utf8(content_bytes)
            .map_err(|_| anyhow!("message content is not valid utf-8"))?;

        if !seen_contents.insert(content.clone()) {
            continue;
        }

        let score = lite_score(
            &query_norm,
            &query_compact,
            &query_bigrams,
            &query_trigrams,
            &content,
        );
        if score == 0 {
            continue;
        }

        let distance = 1.0 / (score as f64 + 1.0);
        result.push(SimilarMessage {
            message: Message {
                id,
                conversation_id,
                role,
                content,
                created_at_ms,
                is_memory: true,
            },
            distance,
        });
    }

    result.sort_by(|a, b| {
        a.distance
            .partial_cmp(&b.distance)
            .unwrap_or(std::cmp::Ordering::Equal)
            .then_with(|| b.message.created_at_ms.cmp(&a.message.created_at_ms))
    });

    result.truncate(top_k);
    Ok(result)
}

fn lite_normalize_text(text: &str) -> String {
    let mut out = String::with_capacity(text.len());
    for ch in text.chars() {
        if ch.is_alphanumeric() {
            out.extend(ch.to_lowercase());
        } else {
            out.push(' ');
        }
    }
    out.split_whitespace().collect::<Vec<_>>().join(" ")
}

fn lite_compact_text(text: &str) -> String {
    text.chars().filter(|c| !c.is_whitespace()).collect()
}

fn lite_collect_bigrams(chars: &[char]) -> std::collections::HashSet<u64> {
    let mut set = std::collections::HashSet::new();
    if chars.len() < 2 {
        return set;
    }
    for i in 0..(chars.len() - 1) {
        let a = chars[i] as u64;
        let b = chars[i + 1] as u64;
        set.insert((a << 32) | b);
    }
    set
}

fn lite_collect_trigrams(chars: &[char]) -> std::collections::HashSet<u128> {
    let mut set = std::collections::HashSet::new();
    if chars.len() < 3 {
        return set;
    }
    for i in 0..(chars.len() - 2) {
        let a = chars[i] as u128;
        let b = chars[i + 1] as u128;
        let c = chars[i + 2] as u128;
        set.insert((a << 64) | (b << 32) | c);
    }
    set
}

fn lite_score(
    query_norm: &str,
    query_compact: &str,
    query_bigrams: &std::collections::HashSet<u64>,
    query_trigrams: &std::collections::HashSet<u128>,
    candidate: &str,
) -> u64 {
    let cand_norm = lite_normalize_text(candidate);
    if cand_norm.is_empty() {
        return 0;
    }

    let cand_compact = lite_compact_text(&cand_norm);
    if cand_compact.is_empty() {
        return 0;
    }

    let mut score = 0u64;

    if cand_norm == query_norm {
        score = score.saturating_add(10_000);
    }

    if !query_norm.is_empty() && cand_norm.contains(query_norm) {
        score = score.saturating_add(500);
        score = score.saturating_add((query_compact.chars().count() as u64).saturating_mul(50));
    }

    for token in query_norm.split_whitespace() {
        if token.len() < 2 {
            continue;
        }
        if cand_norm.contains(token) {
            score = score.saturating_add((token.chars().count() as u64).saturating_mul(200));
        }
    }

    let cand_chars: Vec<char> = cand_compact.chars().collect();
    if !query_bigrams.is_empty() {
        let cand_bigrams = lite_collect_bigrams(&cand_chars);
        let overlap = query_bigrams.intersection(&cand_bigrams).count() as u64;
        score = score.saturating_add(overlap.saturating_mul(50));
    }

    if !query_trigrams.is_empty() {
        let cand_trigrams = lite_collect_trigrams(&cand_chars);
        let overlap = query_trigrams.intersection(&cand_trigrams).count() as u64;
        score = score.saturating_add(overlap.saturating_mul(80));
    }

    score
}

pub fn search_similar_messages_in_conversation<E: Embedder + ?Sized>(
    conn: &Connection,
    key: &[u8; 32],
    embedder: &E,
    conversation_id: &str,
    query: &str,
    top_k: usize,
) -> Result<Vec<SimilarMessage>> {
    // `sqlite-vec` KNN queries currently restrict additional WHERE constraints in ways that make
    // joins/IN filters brittle. For Focus scoping, we over-fetch candidates globally and then
    // filter in Rust.
    let top_k = top_k.max(1);
    let candidate_k = (top_k.saturating_mul(50)).min(1000);

    let candidates = search_similar_messages(conn, key, embedder, query, candidate_k)?;
    Ok(candidates
        .into_iter()
        .filter(|sm| sm.message.conversation_id == conversation_id)
        .take(top_k)
        .collect())
}

fn sha256_hex(bytes: &[u8]) -> String {
    let digest = Sha256::digest(bytes);
    let mut out = String::with_capacity(64);
    for b in digest {
        use std::fmt::Write;
        let _ = write!(&mut out, "{:02x}", b);
    }
    out
}

pub fn insert_attachment(
    conn: &Connection,
    key: &[u8; 32],
    app_dir: &Path,
    bytes: &[u8],
    mime_type: &str,
) -> Result<Attachment> {
    backfill_attachments_oplog_if_needed(conn, key)?;

    let sha256 = sha256_hex(bytes);
    let rel_path = format!("attachments/{sha256}.bin");
    let full_path = app_dir.join(&rel_path);

    fs::create_dir_all(app_dir.join("attachments"))?;
    let aad = format!("attachment.bytes:{sha256}");
    let blob = encrypt_bytes(key, bytes, aad.as_bytes())?;
    fs::write(&full_path, blob)?;

    let now = now_ms();
    let inserted = conn.execute(
        r#"INSERT OR IGNORE INTO attachments(sha256, mime_type, path, byte_len, created_at)
           VALUES (?1, ?2, ?3, ?4, ?5)"#,
        params![sha256, mime_type, rel_path, bytes.len() as i64, now],
    )?;

    let (stored_mime_type, stored_path, stored_byte_len, stored_created_at_ms): (
        String,
        String,
        i64,
        i64,
    ) = conn.query_row(
        r#"SELECT mime_type, path, byte_len, created_at
           FROM attachments
           WHERE sha256 = ?1"#,
        params![sha256],
        |row| Ok((row.get(0)?, row.get(1)?, row.get(2)?, row.get(3)?)),
    )?;

    if inserted > 0 {
        let device_id = get_or_create_device_id(conn)?;
        let seq = next_device_seq(conn, &device_id)?;
        let op = serde_json::json!({
            "op_id": uuid::Uuid::new_v4().to_string(),
            "device_id": device_id,
            "seq": seq,
            "ts_ms": stored_created_at_ms,
            "type": "attachment.upsert.v1",
            "payload": {
                "sha256": sha256.as_str(),
                "mime_type": stored_mime_type.as_str(),
                "byte_len": stored_byte_len,
                "created_at_ms": stored_created_at_ms,
            }
        });
        insert_oplog(conn, key, &op)?;
    }

    Ok(Attachment {
        sha256,
        mime_type: stored_mime_type,
        path: stored_path,
        byte_len: stored_byte_len,
        created_at_ms: stored_created_at_ms,
    })
}

pub fn read_attachment_bytes(
    conn: &Connection,
    key: &[u8; 32],
    app_dir: &Path,
    sha256: &str,
) -> Result<Vec<u8>> {
    let stored_path: Option<String> = conn
        .query_row(
            r#"SELECT path FROM attachments WHERE sha256 = ?1"#,
            params![sha256],
            |row| row.get(0),
        )
        .optional()?;
    let stored_path = stored_path.ok_or_else(|| anyhow!("attachment not found"))?;

    let blob = fs::read(app_dir.join(stored_path))?;
    let aad = format!("attachment.bytes:{sha256}");
    decrypt_bytes(key, &blob, aad.as_bytes())
}

fn version_newer(
    incoming_updated_at: i64,
    incoming_device_id: &str,
    incoming_seq: i64,
    existing_updated_at: i64,
    existing_device_id: &str,
    existing_seq: i64,
) -> bool {
    if incoming_updated_at != existing_updated_at {
        return incoming_updated_at > existing_updated_at;
    }
    if incoming_device_id != existing_device_id {
        return incoming_device_id > existing_device_id;
    }
    incoming_seq > existing_seq
}

fn best_effort_remove_file(path: &Path) -> Result<()> {
    match fs::remove_file(path) {
        Ok(()) => Ok(()),
        Err(e) if e.kind() == std::io::ErrorKind::NotFound => Ok(()),
        Err(e) => Err(e.into()),
    }
}

fn best_effort_remove_dir_all(path: &Path) -> Result<()> {
    match fs::remove_dir_all(path) {
        Ok(()) => Ok(()),
        Err(e) if e.kind() == std::io::ErrorKind::NotFound => Ok(()),
        Err(e) => Err(e.into()),
    }
}

fn purge_attachment(conn: &Connection, key: &[u8; 32], app_dir: &Path, sha256: &str) -> Result<()> {
    let now = now_ms();
    let device_id = get_or_create_device_id(conn)?;
    let seq = next_device_seq(conn, &device_id)?;

    let op = serde_json::json!({
        "op_id": uuid::Uuid::new_v4().to_string(),
        "device_id": device_id,
        "seq": seq,
        "ts_ms": now,
        "type": "attachment.delete.v1",
        "payload": {
            "sha256": sha256,
            "deleted_at_ms": now,
        }
    });
    insert_oplog(conn, key, &op)?;

    let existing_delete: Option<(i64, String, i64)> = conn
        .query_row(
            r#"SELECT deleted_at_ms, deleted_by_device_id, deleted_by_seq
               FROM attachment_deletions
               WHERE sha256 = ?1"#,
            params![sha256],
            |row| Ok((row.get(0)?, row.get(1)?, row.get(2)?)),
        )
        .optional()?;

    let should_update_tombstone = match existing_delete {
        None => true,
        Some((existing_at, existing_device, existing_seq)) => version_newer(
            now,
            &device_id,
            seq,
            existing_at,
            &existing_device,
            existing_seq,
        ),
    };
    if should_update_tombstone {
        conn.execute(
            r#"
INSERT INTO attachment_deletions(sha256, deleted_at_ms, deleted_by_device_id, deleted_by_seq)
VALUES (?1, ?2, ?3, ?4)
ON CONFLICT(sha256) DO UPDATE SET
  deleted_at_ms = excluded.deleted_at_ms,
  deleted_by_device_id = excluded.deleted_by_device_id,
  deleted_by_seq = excluded.deleted_by_seq
"#,
            params![sha256, now, device_id, seq],
        )?;
    }

    best_effort_remove_file(&app_dir.join(format!("attachments/{sha256}.bin")))?;
    best_effort_remove_dir_all(&app_dir.join(format!("attachments/variants/{sha256}")))?;

    conn.execute(
        r#"DELETE FROM attachments WHERE sha256 = ?1"#,
        params![sha256],
    )?;

    Ok(())
}

pub fn purge_message_attachments(
    conn: &Connection,
    key: &[u8; 32],
    app_dir: &Path,
    message_id: &str,
) -> Result<u64> {
    let mut stmt = conn.prepare(
        r#"SELECT attachment_sha256
           FROM message_attachments
           WHERE message_id = ?1
           ORDER BY created_at ASC"#,
    )?;

    let mut rows = stmt.query(params![message_id])?;
    let mut attachment_sha256s: BTreeSet<String> = BTreeSet::new();
    while let Some(row) = rows.next()? {
        let sha: String = row.get(0)?;
        attachment_sha256s.insert(sha);
    }

    if attachment_sha256s.is_empty() {
        set_message_deleted(conn, key, message_id, true)?;
        return Ok(0);
    }

    let mut message_ids_to_delete: BTreeSet<String> = BTreeSet::new();
    for sha in &attachment_sha256s {
        let mut stmt = conn.prepare(
            r#"SELECT message_id
               FROM message_attachments
               WHERE attachment_sha256 = ?1"#,
        )?;
        let mut rows = stmt.query(params![sha])?;
        while let Some(row) = rows.next()? {
            let id: String = row.get(0)?;
            message_ids_to_delete.insert(id);
        }
    }

    // Delete all referencing messages (including the original message).
    for id in message_ids_to_delete {
        let _ = set_message_deleted(conn, key, &id, true);
    }

    for sha in &attachment_sha256s {
        purge_attachment(conn, key, app_dir, sha)?;
    }

    Ok(attachment_sha256s.len() as u64)
}

pub fn clear_local_attachment_cache(conn: &Connection, app_dir: &Path) -> Result<()> {
    best_effort_remove_dir_all(&app_dir.join("attachments"))?;
    let _ = conn.execute(r#"DELETE FROM attachment_variants"#, []);
    Ok(())
}

pub fn upsert_attachment_exif_metadata(
    conn: &Connection,
    key: &[u8; 32],
    attachment_sha256: &str,
    captured_at_ms: Option<i64>,
    latitude: Option<f64>,
    longitude: Option<f64>,
) -> Result<()> {
    backfill_attachments_oplog_if_needed(conn, key)?;
    if captured_at_ms.is_none() && latitude.is_none() && longitude.is_none() {
        return Ok(());
    }

    let now = now_ms();
    let metadata = AttachmentExifMetadata {
        captured_at_ms,
        latitude,
        longitude,
    };
    let json = serde_json::to_vec(&metadata)?;
    let aad = format!("attachment.exif:{attachment_sha256}");
    let blob = encrypt_bytes(key, &json, aad.as_bytes())?;

    conn.execute(
        r#"INSERT INTO attachment_exif(attachment_sha256, metadata, created_at_ms, updated_at_ms)
           VALUES (?1, ?2, ?3, ?4)
           ON CONFLICT(attachment_sha256) DO UPDATE SET
             metadata = excluded.metadata,
             updated_at_ms = excluded.updated_at_ms"#,
        params![attachment_sha256, blob, now, now],
    )?;

    let (stored_created_at_ms, stored_updated_at_ms): (i64, i64) = conn.query_row(
        r#"SELECT created_at_ms, updated_at_ms
           FROM attachment_exif
           WHERE attachment_sha256 = ?1"#,
        params![attachment_sha256],
        |row| Ok((row.get(0)?, row.get(1)?)),
    )?;

    let device_id = get_or_create_device_id(conn)?;
    let seq = next_device_seq(conn, &device_id)?;
    let op = serde_json::json!({
        "op_id": uuid::Uuid::new_v4().to_string(),
        "device_id": device_id,
        "seq": seq,
        "ts_ms": stored_updated_at_ms,
        "type": "attachment.exif.upsert.v1",
        "payload": {
            "attachment_sha256": attachment_sha256,
            "captured_at_ms": captured_at_ms,
            "latitude": latitude,
            "longitude": longitude,
            "created_at_ms": stored_created_at_ms,
            "updated_at_ms": stored_updated_at_ms,
        }
    });
    insert_oplog(conn, key, &op)?;

    Ok(())
}

pub fn read_attachment_exif_metadata(
    conn: &Connection,
    key: &[u8; 32],
    attachment_sha256: &str,
) -> Result<Option<AttachmentExifMetadata>> {
    let blob: Option<Vec<u8>> = conn
        .query_row(
            r#"SELECT metadata FROM attachment_exif WHERE attachment_sha256 = ?1"#,
            params![attachment_sha256],
            |row| row.get(0),
        )
        .optional()?;

    let blob = match blob {
        Some(blob) => blob,
        None => return Ok(None),
    };

    let aad = format!("attachment.exif:{attachment_sha256}");
    let json = decrypt_bytes(key, &blob, aad.as_bytes())?;
    let metadata: AttachmentExifMetadata = serde_json::from_slice(&json)?;
    Ok(Some(metadata))
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

    conn.execute(
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
    Ok(())
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
SELECT sha256, ?1, 'pending', 0, NULL, NULL, ?2
FROM attachments
WHERE mime_type LIKE 'image/%'
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
        params![desired_variant, now_ms],
    )?;

    Ok(affected as u64)
}

pub fn list_due_cloud_media_backups(
    conn: &Connection,
    now_ms: i64,
    limit: i64,
) -> Result<Vec<CloudMediaBackup>> {
    let limit = limit.clamp(1, 500);
    let mut stmt = conn.prepare(
        r#"
SELECT attachment_sha256, desired_variant, status, attempts, next_retry_at, last_error, updated_at
FROM cloud_media_backup
WHERE status != 'uploaded'
  AND (next_retry_at IS NULL OR next_retry_at <= ?1)
ORDER BY updated_at ASC, attachment_sha256 ASC
LIMIT ?2
"#,
    )?;

    let mut rows = stmt.query(params![now_ms, limit])?;
    let mut result = Vec::new();
    while let Some(row) = rows.next()? {
        result.push(CloudMediaBackup {
            attachment_sha256: row.get(0)?,
            desired_variant: row.get(1)?,
            status: row.get(2)?,
            attempts: row.get(3)?,
            next_retry_at_ms: row.get(4)?,
            last_error: row.get(5)?,
            updated_at_ms: row.get(6)?,
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
SELECT id, todo_id, type, from_status, to_status, content, source_message_id, created_at_ms
FROM todo_activities
WHERE todo_id = ?1
ORDER BY created_at_ms ASC, id ASC
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
SELECT id, todo_id, type, from_status, to_status, content, source_message_id, created_at_ms
FROM todo_activities
WHERE created_at_ms >= ?1 AND created_at_ms < ?2
ORDER BY created_at_ms ASC, id ASC
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
            conversation_id.unwrap_or_else(|| MAIN_STREAM_CONVERSATION_ID.to_string());
        if conversation_id == MAIN_STREAM_CONVERSATION_ID {
            // Ensure the main stream exists before inserting.
            get_or_create_main_stream_conversation(conn, key)?;
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

pub fn set_todo_status(
    conn: &Connection,
    key: &[u8; 32],
    todo_id: &str,
    new_status: &str,
    source_message_id: Option<&str>,
) -> Result<Todo> {
    conn.execute_batch("BEGIN IMMEDIATE;")?;

    let result: Result<Todo> = (|| {
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

        let (review_stage, next_review_at_ms) =
            if existing.status == "inbox" && new_status != "inbox" {
                (None, None)
            } else {
                (existing.review_stage, existing.next_review_at_ms)
            };

        let updated = upsert_todo(
            conn,
            key,
            todo_id,
            &existing.title,
            existing.due_at_ms,
            new_status,
            existing.source_entry_id.as_deref(),
            review_stage,
            next_review_at_ms,
            Some(now),
        )?;

        Ok(updated)
    })();

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

fn get_event_by_id(conn: &Connection, key: &[u8; 32], id: &str) -> Result<Event> {
    let (title_blob, start_at_ms, end_at_ms, tz, source_entry_id, created_at_ms, updated_at_ms): (
        Vec<u8>,
        i64,
        i64,
        String,
        Option<String>,
        i64,
        i64,
    ) = conn
        .query_row(
            r#"
SELECT title, start_at_ms, end_at_ms, tz, source_entry_id, created_at_ms, updated_at_ms
FROM events
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
        .map_err(|e| anyhow!("get event failed: {e}"))?;

    let title_bytes = decrypt_bytes(key, &title_blob, b"event.title")?;
    let title =
        String::from_utf8(title_bytes).map_err(|_| anyhow!("event title is not valid utf-8"))?;

    Ok(Event {
        id: id.to_string(),
        title,
        start_at_ms,
        end_at_ms,
        tz,
        source_entry_id,
        created_at_ms,
        updated_at_ms,
    })
}

pub fn upsert_event(
    conn: &Connection,
    key: &[u8; 32],
    id: &str,
    title: &str,
    start_at_ms: i64,
    end_at_ms: i64,
    tz: &str,
    source_entry_id: Option<&str>,
) -> Result<Event> {
    let now = now_ms();
    let title_blob = encrypt_bytes(key, title.as_bytes(), b"event.title")?;
    conn.execute(
        r#"
INSERT INTO events (
  id, title, start_at_ms, end_at_ms, tz, source_entry_id, created_at_ms, updated_at_ms
)
VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8)
ON CONFLICT(id) DO UPDATE SET
  title = excluded.title,
  start_at_ms = excluded.start_at_ms,
  end_at_ms = excluded.end_at_ms,
  tz = excluded.tz,
  source_entry_id = excluded.source_entry_id,
  updated_at_ms = excluded.updated_at_ms
"#,
        params![
            id,
            title_blob,
            start_at_ms,
            end_at_ms,
            tz,
            source_entry_id,
            now,
            now
        ],
    )?;

    let event = get_event_by_id(conn, key, id)?;

    let device_id = get_or_create_device_id(conn)?;
    let seq = next_device_seq(conn, &device_id)?;
    let op = serde_json::json!({
        "op_id": uuid::Uuid::new_v4().to_string(),
        "device_id": device_id,
        "seq": seq,
        "ts_ms": now,
        "type": "event.upsert.v1",
        "payload": {
            "event_id": event.id.as_str(),
            "title": event.title.as_str(),
            "start_at_ms": event.start_at_ms,
            "end_at_ms": event.end_at_ms,
            "tz": event.tz.as_str(),
            "source_entry_id": event.source_entry_id.as_deref(),
            "created_at_ms": event.created_at_ms,
            "updated_at_ms": event.updated_at_ms,
        }
    });
    insert_oplog(conn, key, &op)?;

    Ok(event)
}

pub fn list_events(conn: &Connection, key: &[u8; 32]) -> Result<Vec<Event>> {
    let mut stmt = conn.prepare(
        r#"
SELECT id, title, start_at_ms, end_at_ms, tz, source_entry_id, created_at_ms, updated_at_ms
FROM events
ORDER BY start_at_ms ASC, end_at_ms ASC
"#,
    )?;

    let mut rows = stmt.query([])?;
    let mut result = Vec::new();
    while let Some(row) = rows.next()? {
        let id: String = row.get(0)?;
        let title_blob: Vec<u8> = row.get(1)?;
        let start_at_ms: i64 = row.get(2)?;
        let end_at_ms: i64 = row.get(3)?;
        let tz: String = row.get(4)?;
        let source_entry_id: Option<String> = row.get(5)?;
        let created_at_ms: i64 = row.get(6)?;
        let updated_at_ms: i64 = row.get(7)?;

        let title_bytes = decrypt_bytes(key, &title_blob, b"event.title")?;
        let title = String::from_utf8(title_bytes)
            .map_err(|_| anyhow!("event title is not valid utf-8"))?;

        result.push(Event {
            id,
            title,
            start_at_ms,
            end_at_ms,
            tz,
            source_entry_id,
            created_at_ms,
            updated_at_ms,
        });
    }
    Ok(result)
}
