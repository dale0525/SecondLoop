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
        user_version = 17;
    }

    if user_version < 18 {
        // v18: BYOK embedding profiles (encrypted at rest).
        conn.execute_batch(
            r#"
CREATE TABLE IF NOT EXISTS embedding_profiles (
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
CREATE INDEX IF NOT EXISTS idx_embedding_profiles_active ON embedding_profiles(is_active);
PRAGMA user_version = 18;
"#,
        )?;
    }

    if user_version < 19 {
        // v19: attachment places + multimodal annotations (encrypted at rest).
        conn.execute_batch(
            r#"
CREATE TABLE IF NOT EXISTS attachment_places (
  attachment_sha256 TEXT PRIMARY KEY,
  status TEXT NOT NULL,
  lang TEXT NOT NULL,
  payload BLOB,
  attempts INTEGER NOT NULL DEFAULT 0,
  next_retry_at INTEGER,
  last_error TEXT,
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL,
  FOREIGN KEY(attachment_sha256) REFERENCES attachments(sha256) ON DELETE CASCADE
);
CREATE INDEX IF NOT EXISTS idx_attachment_places_status_retry
  ON attachment_places(status, next_retry_at);

CREATE TABLE IF NOT EXISTS attachment_annotations (
  attachment_sha256 TEXT PRIMARY KEY,
  status TEXT NOT NULL,
  lang TEXT NOT NULL,
  model_name TEXT,
  payload BLOB,
  attempts INTEGER NOT NULL DEFAULT 0,
  next_retry_at INTEGER,
  last_error TEXT,
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL,
  FOREIGN KEY(attachment_sha256) REFERENCES attachments(sha256) ON DELETE CASCADE
);
CREATE INDEX IF NOT EXISTS idx_attachment_annotations_status_retry
  ON attachment_annotations(status, next_retry_at);
PRAGMA user_version = 19;
"#,
        )?;
    }

    if user_version < 20 {
        // v20: semantic parse auto-action jobs (local-only, eventually consistent).
        conn.execute_batch(
            r#"
CREATE TABLE IF NOT EXISTS semantic_parse_jobs (
  message_id TEXT PRIMARY KEY,
  status TEXT NOT NULL,
  attempts INTEGER NOT NULL DEFAULT 0,
  next_retry_at_ms INTEGER,
  last_error TEXT,
  applied_action_kind TEXT,
  applied_todo_id TEXT,
  applied_todo_title BLOB,
  applied_prev_todo_status TEXT,
  undone_at_ms INTEGER,
  created_at_ms INTEGER NOT NULL,
  updated_at_ms INTEGER NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_semantic_parse_jobs_status_retry
  ON semantic_parse_jobs(status, next_retry_at_ms);
CREATE INDEX IF NOT EXISTS idx_semantic_parse_jobs_updated_at_ms
  ON semantic_parse_jobs(updated_at_ms);
PRAGMA user_version = 20;
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

fn app_dir_from_conn(conn: &Connection) -> Result<PathBuf> {
    let mut stmt = conn.prepare("PRAGMA database_list")?;
    let mut rows = stmt.query([])?;
    while let Some(row) = rows.next()? {
        let name: String = row.get(1)?;
        if name != "main" {
            continue;
        }
        let file: String = row.get(2)?;
        if file.trim().is_empty() {
            break;
        }

        let path = PathBuf::from(file);
        let Some(parent) = path.parent() else {
            break;
        };
        return Ok(parent.to_path_buf());
    }
    Err(anyhow!("unable to derive app_dir from sqlite connection"))
}

pub fn reset_vault_data_preserving_llm_profiles(conn: &Connection) -> Result<()> {
    let app_dir = app_dir_from_conn(conn).ok();
    conn.execute_batch("BEGIN IMMEDIATE;")?;

    let result: Result<()> = (|| {
        conn.execute_batch(
            r#"
DELETE FROM message_embeddings;
DELETE FROM todo_embeddings;
DELETE FROM todo_activity_embeddings;
DELETE FROM semantic_parse_jobs;
DELETE FROM message_attachments;
DELETE FROM cloud_media_backup;
DELETE FROM attachment_variants;
DELETE FROM attachment_exif;
DELETE FROM attachment_places;
DELETE FROM attachment_annotations;
DELETE FROM attachment_deletions;
DELETE FROM attachments;
DELETE FROM messages;
DELETE FROM conversations;
DELETE FROM todo_deletions;
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
            if let Some(app_dir) = app_dir {
                let _ = best_effort_remove_dir_all(&app_dir.join("attachments"));
            }
            Ok(())
        }
        Err(e) => {
            let _ = conn.execute_batch("ROLLBACK;");
            Err(e)
        }
    }
}
