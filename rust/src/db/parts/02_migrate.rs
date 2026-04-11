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
  attempt_id INTEGER NOT NULL DEFAULT 0,
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

    if user_version < 21 {
        // v21: attachment metadata (encrypted at rest, syncable).
        conn.execute_batch(
            r#"
CREATE TABLE IF NOT EXISTS attachment_metadata (
  attachment_sha256 TEXT PRIMARY KEY,
  title BLOB,
  filenames BLOB,
  source_urls BLOB,
  title_updated_at_ms INTEGER NOT NULL DEFAULT 0,
  created_at_ms INTEGER NOT NULL,
  updated_at_ms INTEGER NOT NULL,
  FOREIGN KEY(attachment_sha256) REFERENCES attachments(sha256) ON DELETE CASCADE
);
CREATE INDEX IF NOT EXISTS idx_attachment_metadata_updated_at_ms
  ON attachment_metadata(updated_at_ms);
PRAGMA user_version = 21;
"#,
        )?;
    }

    if user_version < 22 {
        // v22: recurring todo series + todo occurrence links.
        conn.execute_batch(
            r#"
CREATE TABLE IF NOT EXISTS todo_series (
  id TEXT PRIMARY KEY,
  rule_json TEXT NOT NULL,
  created_at_ms INTEGER NOT NULL,
  updated_at_ms INTEGER NOT NULL
);

CREATE TABLE IF NOT EXISTS todo_recurrences (
  todo_id TEXT PRIMARY KEY,
  series_id TEXT NOT NULL,
  occurrence_index INTEGER NOT NULL DEFAULT 0,
  created_at_ms INTEGER NOT NULL,
  updated_at_ms INTEGER NOT NULL,
  FOREIGN KEY(todo_id) REFERENCES todos(id) ON DELETE CASCADE,
  FOREIGN KEY(series_id) REFERENCES todo_series(id) ON DELETE CASCADE
);
CREATE INDEX IF NOT EXISTS idx_todo_recurrences_series_occurrence
  ON todo_recurrences(series_id, occurrence_index);
PRAGMA user_version = 22;
"#,
        )?;
        user_version = 22;
    }

    if user_version < 23 {
        // v23: tags + message tag relations.
        conn.execute_batch(
            r#"
CREATE TABLE IF NOT EXISTS tags (
  id TEXT PRIMARY KEY,
  name BLOB NOT NULL,
  system_key TEXT,
  is_system INTEGER NOT NULL DEFAULT 0,
  color TEXT,
  created_at_ms INTEGER NOT NULL,
  updated_at_ms INTEGER NOT NULL,
  CHECK (is_system IN (0, 1))
);
CREATE UNIQUE INDEX IF NOT EXISTS idx_tags_system_key_unique
  ON tags(system_key)
  WHERE system_key IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_tags_updated_at_ms
  ON tags(updated_at_ms);

CREATE TABLE IF NOT EXISTS message_tags (
  message_id TEXT NOT NULL,
  tag_id TEXT NOT NULL,
  created_at_ms INTEGER NOT NULL,
  PRIMARY KEY (message_id, tag_id),
  FOREIGN KEY(message_id) REFERENCES messages(id) ON DELETE CASCADE,
  FOREIGN KEY(tag_id) REFERENCES tags(id) ON DELETE CASCADE
);
CREATE INDEX IF NOT EXISTS idx_message_tags_tag_id
  ON message_tags(tag_id);
CREATE INDEX IF NOT EXISTS idx_message_tags_message_id
  ON message_tags(message_id);
PRAGMA user_version = 23;
"#,
        )?;
        user_version = 23;
    }

    if user_version < 24 {
        // v24: tag merge suggestion feedback learning.
        conn.execute_batch(
            r#"
CREATE TABLE IF NOT EXISTS tag_merge_feedback (
  source_tag_id TEXT NOT NULL,
  target_tag_id TEXT NOT NULL,
  reason TEXT NOT NULL,
  accept_count INTEGER NOT NULL DEFAULT 0,
  dismiss_count INTEGER NOT NULL DEFAULT 0,
  later_count INTEGER NOT NULL DEFAULT 0,
  updated_at_ms INTEGER NOT NULL,
  PRIMARY KEY (source_tag_id, target_tag_id, reason)
);
CREATE INDEX IF NOT EXISTS idx_tag_merge_feedback_reason
  ON tag_merge_feedback(reason, updated_at_ms DESC);
PRAGMA user_version = 24;
"#,
        )?;
        user_version = 24;
    }

    if user_version < 25 {
        // v25: message tag autofill shadow-mode jobs + event logs.
        conn.execute_batch(
            r#"
CREATE TABLE IF NOT EXISTS message_tag_autofill_jobs (
  message_id TEXT PRIMARY KEY,
  reason TEXT NOT NULL,
  status TEXT NOT NULL,
  attempts INTEGER NOT NULL DEFAULT 0,
  next_retry_at_ms INTEGER,
  last_error TEXT,
  created_at_ms INTEGER NOT NULL,
  updated_at_ms INTEGER NOT NULL,
  FOREIGN KEY(message_id) REFERENCES messages(id) ON DELETE CASCADE
);
CREATE INDEX IF NOT EXISTS idx_message_tag_autofill_jobs_status_due
  ON message_tag_autofill_jobs(status, next_retry_at_ms, updated_at_ms);

CREATE TABLE IF NOT EXISTS message_tag_autofill_events (
  id TEXT PRIMARY KEY,
  message_id TEXT NOT NULL,
  candidate_tag TEXT,
  score REAL NOT NULL,
  margin REAL NOT NULL,
  source_count INTEGER NOT NULL,
  decision TEXT NOT NULL,
  applied INTEGER NOT NULL DEFAULT 0,
  evidence_json TEXT NOT NULL,
  created_at_ms INTEGER NOT NULL,
  FOREIGN KEY(message_id) REFERENCES messages(id) ON DELETE CASCADE,
  CHECK (applied IN (0, 1))
);
CREATE INDEX IF NOT EXISTS idx_message_tag_autofill_events_message
  ON message_tag_autofill_events(message_id, created_at_ms DESC);
PRAGMA user_version = 25;
"#,
        )?;
        user_version = 25;
    }

    if user_version < 26 {
        // v26: attachment text chunk offsets + per-space vec0 embeddings.
        conn.execute_batch(
            r#"
CREATE TABLE IF NOT EXISTS attachment_text_chunks (
  attachment_sha256 TEXT NOT NULL,
  kind TEXT NOT NULL,
  chunk_index INTEGER NOT NULL,
  start_offset INTEGER NOT NULL,
  end_offset INTEGER NOT NULL,
  text_len INTEGER NOT NULL,
  created_at_ms INTEGER NOT NULL,
  updated_at_ms INTEGER NOT NULL,
  PRIMARY KEY (attachment_sha256, kind, chunk_index),
  FOREIGN KEY(attachment_sha256) REFERENCES attachments(sha256) ON DELETE CASCADE
);
CREATE INDEX IF NOT EXISTS idx_attachment_text_chunks_sha
  ON attachment_text_chunks(attachment_sha256);
CREATE INDEX IF NOT EXISTS idx_attachment_text_chunks_updated_at_ms
  ON attachment_text_chunks(updated_at_ms);

CREATE TABLE IF NOT EXISTS attachment_chunk_embedding_jobs (
  attachment_sha256 TEXT NOT NULL,
  kind TEXT NOT NULL,
  chunk_index INTEGER NOT NULL,
  status TEXT NOT NULL,
  attempts INTEGER NOT NULL DEFAULT 0,
  next_retry_at_ms INTEGER,
  last_error TEXT,
  created_at_ms INTEGER NOT NULL,
  updated_at_ms INTEGER NOT NULL,
  PRIMARY KEY (attachment_sha256, kind, chunk_index),
  FOREIGN KEY(attachment_sha256, kind, chunk_index)
    REFERENCES attachment_text_chunks(attachment_sha256, kind, chunk_index)
    ON DELETE CASCADE
);
CREATE INDEX IF NOT EXISTS idx_attachment_chunk_embedding_jobs_status_due
  ON attachment_chunk_embedding_jobs(status, next_retry_at_ms, updated_at_ms);

PRAGMA user_version = 26;
"#,
        )?;
    }

    if user_version < 27 {
        // v27: semantic parse tag suggestion metadata for manual-assist flow.
        conn.execute_batch(
            r#"
ALTER TABLE semantic_parse_jobs
  ADD COLUMN suggested_tags_json BLOB;
ALTER TABLE semantic_parse_jobs
  ADD COLUMN suggested_tag_confidence REAL;
ALTER TABLE semantic_parse_jobs
  ADD COLUMN tag_suggestion_state TEXT NOT NULL DEFAULT 'none';
ALTER TABLE semantic_parse_jobs
  ADD COLUMN applied_tag_ids_json BLOB;

PRAGMA user_version = 27;
"#,
        )?;
    }

    if user_version < 28 {
        // v28: detached ask completion claims for transaction-level idempotency.
        conn.execute_batch(
            r#"
CREATE TABLE IF NOT EXISTS detached_ask_completion_claims (
  request_id TEXT PRIMARY KEY,
  conversation_id TEXT NOT NULL,
  created_at_ms INTEGER NOT NULL,
  updated_at_ms INTEGER NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_detached_ask_completion_claims_conversation
  ON detached_ask_completion_claims(conversation_id, created_at_ms DESC);

PRAGMA user_version = 28;
"#,
        )?;
        user_version = 28;
    }

    if user_version < 29 {
        // v29: unified knowledge index foundation tables.
        conn.execute_batch(
            r#"
CREATE TABLE IF NOT EXISTS knowledge_documents (
  document_id TEXT PRIMARY KEY,
  origin_type TEXT NOT NULL,
  source_kind TEXT NOT NULL,
  role TEXT NOT NULL,
  language TEXT,
  quality_score REAL NOT NULL DEFAULT 1.0,
  title TEXT,
  summary TEXT,
  anchor_json TEXT NOT NULL DEFAULT '{}',
  raw_text BLOB NOT NULL,
  normalized_text BLOB NOT NULL,
  created_at_ms INTEGER NOT NULL,
  updated_at_ms INTEGER NOT NULL,
  schema_version INTEGER NOT NULL,
  normalization_version INTEGER NOT NULL,
  segmentation_version INTEGER NOT NULL,
  embedding_policy_version INTEGER NOT NULL,
  retrieval_policy_version INTEGER NOT NULL,
  last_indexed_at_ms INTEGER
);
CREATE INDEX IF NOT EXISTS idx_knowledge_documents_origin_updated
  ON knowledge_documents(origin_type, updated_at_ms DESC, document_id);

CREATE TABLE IF NOT EXISTS knowledge_units (
  unit_id TEXT PRIMARY KEY,
  document_id TEXT NOT NULL,
  parent_unit_id TEXT,
  unit_kind TEXT NOT NULL,
  source_kind TEXT NOT NULL,
  role TEXT NOT NULL,
  ordinal INTEGER NOT NULL,
  token_count INTEGER NOT NULL DEFAULT 0,
  anchor_json TEXT NOT NULL DEFAULT '{}',
  raw_text BLOB NOT NULL,
  normalized_text BLOB NOT NULL,
  prev_unit_id TEXT,
  next_unit_id TEXT,
  created_at_ms INTEGER NOT NULL,
  updated_at_ms INTEGER NOT NULL,
  FOREIGN KEY(document_id) REFERENCES knowledge_documents(document_id) ON DELETE CASCADE,
  FOREIGN KEY(parent_unit_id) REFERENCES knowledge_units(unit_id) ON DELETE CASCADE,
  FOREIGN KEY(prev_unit_id) REFERENCES knowledge_units(unit_id) ON DELETE SET NULL,
  FOREIGN KEY(next_unit_id) REFERENCES knowledge_units(unit_id) ON DELETE SET NULL
);
CREATE INDEX IF NOT EXISTS idx_knowledge_units_document_parent_kind
  ON knowledge_units(document_id, parent_unit_id, unit_kind, ordinal);
CREATE INDEX IF NOT EXISTS idx_knowledge_units_anchor_lookup
  ON knowledge_units(document_id, unit_kind, ordinal);

CREATE TABLE IF NOT EXISTS knowledge_embeddings (
  target_kind TEXT NOT NULL,
  target_id TEXT NOT NULL,
  unit_kind TEXT,
  model_name TEXT NOT NULL,
  dim INTEGER NOT NULL,
  embedding_json TEXT NOT NULL,
  created_at_ms INTEGER NOT NULL,
  updated_at_ms INTEGER NOT NULL,
  PRIMARY KEY(target_kind, target_id, model_name)
);
CREATE INDEX IF NOT EXISTS idx_knowledge_embeddings_target
  ON knowledge_embeddings(target_kind, target_id, unit_kind);

CREATE TABLE IF NOT EXISTS knowledge_index_jobs (
  document_id TEXT NOT NULL,
  stage TEXT NOT NULL,
  status TEXT NOT NULL,
  attempts INTEGER NOT NULL DEFAULT 0,
  next_retry_at_ms INTEGER,
  last_error TEXT,
  created_at_ms INTEGER NOT NULL,
  updated_at_ms INTEGER NOT NULL,
  PRIMARY KEY(document_id, stage),
  FOREIGN KEY(document_id) REFERENCES knowledge_documents(document_id) ON DELETE CASCADE
);
CREATE INDEX IF NOT EXISTS idx_knowledge_index_jobs_status_due
  ON knowledge_index_jobs(status, next_retry_at_ms, updated_at_ms);

CREATE TABLE IF NOT EXISTS knowledge_rebuild_state (
  state_key INTEGER PRIMARY KEY CHECK(state_key = 1),
  knowledge_schema_version INTEGER NOT NULL,
  normalization_version INTEGER NOT NULL,
  segmentation_version INTEGER NOT NULL,
  embedding_policy_version INTEGER NOT NULL,
  retrieval_policy_version INTEGER NOT NULL,
  last_indexed_model_name TEXT,
  last_indexed_dim INTEGER,
  status TEXT NOT NULL DEFAULT 'empty',
  rebuild_required INTEGER NOT NULL DEFAULT 0,
  stale_reason TEXT,
  last_error TEXT,
  last_rebuild_started_at_ms INTEGER,
  last_rebuild_completed_at_ms INTEGER,
  current_document_id TEXT,
  current_stage TEXT,
  documents_indexed INTEGER NOT NULL DEFAULT 0,
  units_indexed INTEGER NOT NULL DEFAULT 0,
  embeddings_indexed INTEGER NOT NULL DEFAULT 0,
  total_documents INTEGER NOT NULL DEFAULT 0,
  cancel_requested INTEGER NOT NULL DEFAULT 0
);
INSERT OR IGNORE INTO knowledge_rebuild_state(
  state_key,
  knowledge_schema_version,
  normalization_version,
  segmentation_version,
  embedding_policy_version,
  retrieval_policy_version,
  last_indexed_model_name,
  last_indexed_dim,
  status,
  rebuild_required,
  stale_reason,
  last_error,
  last_rebuild_started_at_ms,
  last_rebuild_completed_at_ms,
  current_document_id,
  current_stage,
  documents_indexed,
  units_indexed,
  embeddings_indexed,
  total_documents,
  cancel_requested
) VALUES (1, 1, 1, 1, 1, 1, NULL, NULL, 'empty', 0, NULL, NULL, NULL, NULL, NULL, NULL, 0, 0, 0, 0, 0);

PRAGMA user_version = 29;
"#,
        )?;
        user_version = 29;
    }

    if user_version < 30 {
        migrate_from_v29_to_v30(conn)?;
        user_version = 30;
    }

    if user_version < 31 {
        migrate_from_v30_to_v31(conn)?;
        user_version = 31;
    }

    if user_version < 32 {
        migrate_from_v31_to_v32(conn)?;
        user_version = 32;
    }

    if user_version < 33 {
        migrate_from_v32_to_v33(conn)?;
        user_version = 33;
    }

    if user_version < 34 {
        migrate_from_v33_to_v34(conn)?;
        user_version = 34;
    }

    if user_version < 35 {
        migrate_from_v34_to_v35(conn)?;
        user_version = 35;
    }

    if user_version < 36 {
        migrate_from_v35_to_v36(conn)?;
        user_version = 36;
    }

    if user_version < 37 {
        migrate_from_v36_to_v37(conn)?;
        user_version = 37;
    }

    if user_version < 38 {
        migrate_from_v37_to_v38(conn)?;
        user_version = 38;
    }

    if user_version < 39 {
        migrate_from_v38_to_v39(conn)?;
        user_version = 39;
    }

    if user_version < 40 {
        migrate_from_v39_to_v40(conn)?;
        user_version = 40;
    }

    if user_version < 41 {
        migrate_from_v40_to_v41(conn)?;
        user_version = 41;
    }

    if user_version < 42 {
        migrate_from_v41_to_v42(conn)?;
        user_version = 42;
    }

    debug_assert!(user_version >= 42);

    Ok(())
}

pub fn open(app_dir: &Path) -> Result<Connection> {
    fs::create_dir_all(app_dir)?;
    vector::register_sqlite_vec()?;
    let conn = Connection::open(db_path(app_dir))?;
    conn.busy_timeout(Duration::from_millis(5_000))?;
    conn.pragma_update(None, "journal_mode", "WAL")?;
    migrate(&conn)?;
    ensure_todo_manual_nudge_columns(&conn)?;
    ensure_content_enrichment_kv_defaults(&conn)?;
    ensure_knowledge_rebuild_state_defaults(&conn)?;
    Ok(conn)
}
