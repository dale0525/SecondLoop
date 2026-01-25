use std::fs;

use rusqlite::{params, Connection};
use zerocopy::IntoBytes;

#[test]
fn vector_schema_migration() {
    let temp_dir = tempfile::tempdir().expect("tempdir");
    let app_dir = temp_dir.path().join("secondloop");
    fs::create_dir_all(&app_dir).expect("create app dir");

    // Create a v1 DB manually (no `needs_embedding`, no vec0 table, user_version default 0).
    let db_path = app_dir.join("secondloop.sqlite3");
    let conn = Connection::open(db_path).expect("open");
    conn.execute_batch(
        r#"
PRAGMA foreign_keys = ON;

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
    )
    .expect("create v1 schema");
    drop(conn);

    // Opening via our API should migrate to the latest schema.
    let conn = secondloop_rust::db::open(&app_dir).expect("open via db::open");

    let user_version: i64 = conn
        .query_row("PRAGMA user_version", [], |row| row.get(0))
        .expect("user_version");
    assert_eq!(user_version, 11);

    // Verify messages table has needs_embedding.
    let mut stmt = conn
        .prepare("PRAGMA table_info(messages)")
        .expect("table_info");
    let cols: Vec<String> = stmt
        .query_map([], |row| row.get(1))
        .expect("query_map")
        .map(|r| r.expect("row"))
        .collect();
    assert!(cols.iter().any(|c| c == "needs_embedding"));
    assert!(cols.iter().any(|c| c == "is_memory"));

    // Verify vec0 table exists and is usable.
    let embedding = vec![0.0f32; 384];
    conn.execute(
        "INSERT INTO message_embeddings(rowid, embedding, message_id, model_name) VALUES (?1, ?2, ?3, ?4)",
        params![1i64, embedding.as_bytes(), "m1", "test-model"],
    )
    .expect("insert vec0 row");

    let dim: i64 = conn
        .query_row(
            "SELECT vec_length(embedding) FROM message_embeddings WHERE rowid = 1",
            [],
            |row| row.get(0),
        )
        .expect("vec_length");
    assert_eq!(dim, 384);

    let model_name: String = conn
        .query_row(
            "SELECT model_name FROM message_embeddings WHERE rowid = 1",
            [],
            |row| row.get(0),
        )
        .expect("model_name");
    assert_eq!(model_name, "test-model");
}
