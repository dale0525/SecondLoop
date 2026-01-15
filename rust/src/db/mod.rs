use std::fs;
use std::path::{Path, PathBuf};

use anyhow::{anyhow, Result};
use rusqlite::{params, Connection, OptionalExtension};
use zerocopy::IntoBytes;

use crate::crypto::{decrypt_bytes, encrypt_bytes};
use crate::embedding::Embedder;
use crate::vector;

const MESSAGE_EMBEDDING_DIM: usize = 384;

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
        conn.execute_batch("UPDATE messages SET needs_embedding = 1 WHERE needs_embedding IS NULL;")?;

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
    let id = uuid::Uuid::new_v4().to_string();
    let now = now_ms();

    let content_blob = encrypt_bytes(key, content.as_bytes(), b"message.content")?;
    conn.execute(
        r#"INSERT INTO messages (id, conversation_id, role, content, created_at, needs_embedding)
           VALUES (?1, ?2, ?3, ?4, ?5, 1)"#,
        params![id, conversation_id, role, content_blob, now],
    )?;

    conn.execute(
        r#"UPDATE conversations SET updated_at = ?2 WHERE id = ?1"#,
        params![conversation_id, now],
    )?;

    let device_id = get_or_create_device_id(conn)?;
    let seq = next_device_seq(conn, &device_id)?;
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
    let mut content =
        String::from_utf8(content_bytes).map_err(|_| anyhow!("message content is not valid utf-8"))?;
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

    let api_key_blob: Option<Vec<u8>> = api_key.map(|v| {
        encrypt_bytes(
            key,
            v.as_bytes(),
            format!("llm.api_key:{id}").as_bytes(),
        )
    })
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
            let api_key_bytes =
                decrypt_bytes(key, &blob, format!("llm.api_key:{id}").as_bytes())?;

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

pub fn process_pending_message_embeddings(
    conn: &Connection,
    key: &[u8; 32],
    embedder: &impl Embedder,
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
        plaintexts.push(content);
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
        plaintexts.push(content);
    }

    if plaintexts.is_empty() {
        return Ok(0);
    }

    let embeddings: Vec<Vec<f32>> = plaintexts.iter().map(|t| default_embed_text(t)).collect();

    for i in 0..message_ids.len() {
        let updated = conn.execute(
            r#"UPDATE message_embeddings
               SET embedding = ?2, message_id = ?3, model_name = ?4
               WHERE rowid = ?1"#,
            params![
                message_rowids[i],
                embeddings[i].as_bytes(),
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
                    embeddings[i].as_bytes(),
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

pub fn rebuild_message_embeddings_default(
    conn: &Connection,
    key: &[u8; 32],
    batch_limit: usize,
) -> Result<usize> {
    conn.execute_batch(
        r#"
BEGIN;
DELETE FROM message_embeddings;
UPDATE messages SET needs_embedding = 1;
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
           WHERE conversation_id = ?1
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
    let (conversation_id, role, content_blob, created_at_ms): (String, String, Vec<u8>, i64) =
        conn.query_row(
        r#"SELECT conversation_id, role, content, created_at FROM messages WHERE id = ?1"#,
        params![id],
        |row| {
            Ok((row.get(0)?, row.get(1)?, row.get(2)?, row.get(3)?))
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
    })
}

pub fn search_similar_messages(
    conn: &Connection,
    key: &[u8; 32],
    embedder: &impl Embedder,
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

    let mut vectors = embedder.embed(&[query.to_string()])?;
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
        i64::try_from(top_k).unwrap_or(i64::MAX),
        embedder.model_name()
    ])?;

    let mut result = Vec::new();
    while let Some(row) = rows.next()? {
        let message_id: String = row.get(0)?;
        let distance: f64 = row.get(1)?;
        let message = get_message_by_id(conn, key, &message_id)?;
        result.push(SimilarMessage { message, distance });
    }

    Ok(result)
}

pub fn search_similar_messages_default(
    conn: &Connection,
    key: &[u8; 32],
    query: &str,
    top_k: usize,
) -> Result<Vec<SimilarMessage>> {
    let query_vector = default_embed_text(query);

    let mut stmt = conn.prepare(
        r#"SELECT message_id, distance
           FROM message_embeddings
           WHERE embedding match ?1 AND k = ?2 AND model_name = ?3
           ORDER BY distance ASC"#,
    )?;

    let mut rows = stmt.query(params![
        query_vector.as_bytes(),
        i64::try_from(top_k).unwrap_or(i64::MAX),
        crate::embedding::DEFAULT_MODEL_NAME
    ])?;

    let mut result = Vec::new();
    while let Some(row) = rows.next()? {
        let message_id: String = row.get(0)?;
        let distance: f64 = row.get(1)?;
        let message = get_message_by_id(conn, key, &message_id)?;
        result.push(SimilarMessage { message, distance });
    }

    Ok(result)
}

pub fn search_similar_messages_in_conversation_default(
    conn: &Connection,
    key: &[u8; 32],
    conversation_id: &str,
    query: &str,
    top_k: usize,
) -> Result<Vec<SimilarMessage>> {
    // `sqlite-vec` KNN queries currently restrict additional WHERE constraints in ways that make
    // joins/IN filters brittle. For Focus scoping, we over-fetch candidates globally and then
    // filter in Rust.
    let top_k = top_k.max(1);
    let candidate_k = (top_k.saturating_mul(50)).min(1000);

    let candidates = search_similar_messages_default(conn, key, query, candidate_k)?;
    Ok(candidates
        .into_iter()
        .filter(|sm| sm.message.conversation_id == conversation_id)
        .take(top_k)
        .collect())
}
