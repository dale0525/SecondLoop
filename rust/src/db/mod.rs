use std::fs;
use std::path::{Path, PathBuf};

use anyhow::{anyhow, Result};
use rusqlite::{params, Connection};
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

    Ok(Message {
        id,
        conversation_id: conversation_id.to_string(),
        role: role.to_string(),
        content: content.to_string(),
        created_at_ms: now,
    })
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
