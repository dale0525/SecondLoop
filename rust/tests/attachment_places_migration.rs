use std::fs;

use rusqlite::Connection;

#[test]
fn attachment_places_migration() {
    let temp_dir = tempfile::tempdir().expect("tempdir");
    let app_dir = temp_dir.path().join("secondloop");
    fs::create_dir_all(&app_dir).expect("create app dir");

    // Create a v1 DB manually (no attachment tables, user_version default 0).
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
    assert_eq!(user_version, 22);

    let mut stmt = conn
        .prepare("PRAGMA table_info(attachment_places)")
        .expect("table_info(attachment_places)");
    let cols: Vec<String> = stmt
        .query_map([], |row| row.get(1))
        .expect("query_map")
        .map(|r| r.expect("row"))
        .collect();
    assert!(cols.iter().any(|c| c == "attachment_sha256"));
    assert!(cols.iter().any(|c| c == "status"));
    assert!(cols.iter().any(|c| c == "lang"));
    assert!(cols.iter().any(|c| c == "payload"));
    assert!(cols.iter().any(|c| c == "attempts"));
    assert!(cols.iter().any(|c| c == "next_retry_at"));
    assert!(cols.iter().any(|c| c == "last_error"));
    assert!(cols.iter().any(|c| c == "created_at"));
    assert!(cols.iter().any(|c| c == "updated_at"));

    let mut stmt = conn
        .prepare("PRAGMA index_list(attachment_places)")
        .expect("index_list(attachment_places)");
    let indexes: Vec<String> = stmt
        .query_map([], |row| row.get(1))
        .expect("query_map")
        .map(|r| r.expect("row"))
        .collect();
    assert!(indexes
        .iter()
        .any(|name| name == "idx_attachment_places_status_retry"));
}
