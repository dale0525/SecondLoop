use std::fs;
use std::path::{Path, PathBuf};

use anyhow::{anyhow, Result};
use rusqlite::{params, Connection, OptionalExtension};
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
}

#[derive(Clone, Debug)]
pub struct SimilarMessage {
    pub message: Message,
    pub distance: f64,
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

fn get_or_create_device_id(conn: &Connection) -> Result<String> {
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
UPDATE messages
SET needs_embedding = CASE
  WHEN COALESCE(is_deleted, 0) = 0 AND COALESCE(is_memory, 1) = 1 THEN 1
  ELSE 0
END;
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

    Ok(())
}

pub fn open(app_dir: &Path) -> Result<Connection> {
    fs::create_dir_all(app_dir)?;
    vector::register_sqlite_vec()?;
    let conn = Connection::open(db_path(app_dir))?;
    migrate(&conn)?;
    Ok(conn)
}

pub fn reset_vault_data_preserving_llm_profiles(conn: &Connection) -> Result<()> {
    conn.execute_batch("BEGIN IMMEDIATE;")?;

    let result: Result<()> = (|| {
        conn.execute_batch(
            r#"
DELETE FROM message_embeddings;
DELETE FROM messages;
DELETE FROM conversations;
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
) -> Result<Option<LlmProfileConfig>> {
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

    Ok(Some(LlmProfileConfig {
        provider_type,
        base_url,
        api_key,
        model_name,
    }))
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
        r#"SELECT id, role, content, created_at
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

        let content_bytes = decrypt_bytes(key, &content_blob, b"message.content")?;
        let content = String::from_utf8(content_bytes)
            .map_err(|_| anyhow!("message content is not valid utf-8"))?;

        result.push(Message {
            id,
            conversation_id: conversation_id.to_string(),
            role,
            content,
            created_at_ms,
        });
    }

    Ok(result)
}

fn get_message_by_id(conn: &Connection, key: &[u8; 32], id: &str) -> Result<Message> {
    let (conversation_id, role, content_blob, created_at_ms): (String, String, Vec<u8>, i64) = conn
        .query_row(
            r#"SELECT conversation_id, role, content, created_at FROM messages WHERE id = ?1"#,
            params![id],
            |row| Ok((row.get(0)?, row.get(1)?, row.get(2)?, row.get(3)?)),
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
    let sha256 = sha256_hex(bytes);
    let rel_path = format!("attachments/{sha256}.bin");
    let full_path = app_dir.join(&rel_path);

    fs::create_dir_all(app_dir.join("attachments"))?;
    let aad = format!("attachment.bytes:{sha256}");
    let blob = encrypt_bytes(key, bytes, aad.as_bytes())?;
    fs::write(&full_path, blob)?;

    let now = now_ms();
    conn.execute(
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
