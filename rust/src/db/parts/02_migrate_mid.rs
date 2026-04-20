fn migrate_legacy_schema_part2(conn: &Connection, mut user_version: i64) -> Result<i64> {
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
  applied_prev_todo_due_at_ms INTEGER,
  applied_due_changed INTEGER NOT NULL DEFAULT 0,
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

    Ok(user_version)
}
