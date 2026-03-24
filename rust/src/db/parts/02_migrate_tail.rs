fn migrate_from_v29_to_v30(conn: &Connection) -> Result<()> {
    conn.execute_batch(
        r#"
CREATE TABLE IF NOT EXISTS embedding_artifact_manifests (
  artifact_id TEXT PRIMARY KEY,
  source_kind TEXT NOT NULL,
  source_id TEXT NOT NULL,
  source_revision INTEGER NOT NULL,
  chunk_hash TEXT NOT NULL,
  chunk_ordinal INTEGER NOT NULL DEFAULT 0,
  profile_id TEXT NOT NULL,
  producer_device_id TEXT,
  producer_class TEXT NOT NULL,
  quality_tier TEXT NOT NULL DEFAULT 'full',
  vector_format TEXT NOT NULL,
  dimension INTEGER NOT NULL,
  blob_ref TEXT NOT NULL,
  status TEXT NOT NULL DEFAULT 'ready',
  supersedes_artifact_id TEXT,
  created_at_ms INTEGER NOT NULL,
  updated_at_ms INTEGER NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_embedding_artifact_identity
  ON embedding_artifact_manifests(
    source_kind,
    source_id,
    source_revision,
    chunk_hash,
    profile_id,
    status
  );
CREATE INDEX IF NOT EXISTS idx_embedding_artifact_source_revision
  ON embedding_artifact_manifests(
    source_kind,
    source_id,
    source_revision,
    profile_id,
    status,
    chunk_ordinal,
    created_at_ms
  );
CREATE INDEX IF NOT EXISTS idx_embedding_artifact_chunk_profile
  ON embedding_artifact_manifests(chunk_hash, profile_id, status, created_at_ms);

PRAGMA user_version = 30;
"#,
    )?;
    Ok(())
}

fn migrate_from_v30_to_v31(conn: &Connection) -> Result<()> {
    conn.execute_batch(
        r#"
CREATE TABLE IF NOT EXISTS attachment_derivations (
  root_sha256 TEXT NOT NULL,
  child_sha256 TEXT NOT NULL,
  role TEXT NOT NULL,
  created_at_ms INTEGER NOT NULL,
  PRIMARY KEY(root_sha256, child_sha256, role)
);
CREATE INDEX IF NOT EXISTS idx_attachment_derivations_root_sha256
  ON attachment_derivations(root_sha256);
CREATE INDEX IF NOT EXISTS idx_attachment_derivations_child_sha256
  ON attachment_derivations(child_sha256);

PRAGMA user_version = 31;
"#,
    )?;
    Ok(())
}

fn migrate_from_v31_to_v32(conn: &Connection) -> Result<()> {
    conn.execute_batch(
        r#"
CREATE TABLE IF NOT EXISTS knowledge_document_usage (
  document_id TEXT PRIMARY KEY,
  retrieve_count INTEGER NOT NULL DEFAULT 0,
  last_retrieved_at_ms INTEGER,
  FOREIGN KEY(document_id) REFERENCES knowledge_documents(document_id) ON DELETE CASCADE
);
CREATE INDEX IF NOT EXISTS idx_knowledge_document_usage_recent
  ON knowledge_document_usage(last_retrieved_at_ms DESC, retrieve_count DESC);

PRAGMA user_version = 32;
"#,
    )?;
    Ok(())
}

fn migrate_from_v32_to_v33(conn: &Connection) -> Result<()> {
    conn.execute_batch(
        r#"
CREATE TABLE IF NOT EXISTS todo_checklist_items (
  id TEXT PRIMARY KEY,
  todo_id TEXT NOT NULL,
  content BLOB NOT NULL,
  is_done INTEGER NOT NULL DEFAULT 0,
  sort_order INTEGER NOT NULL DEFAULT 0,
  created_at_ms INTEGER NOT NULL,
  updated_at_ms INTEGER NOT NULL,
  FOREIGN KEY(todo_id) REFERENCES todos(id) ON DELETE CASCADE
);
CREATE INDEX IF NOT EXISTS idx_todo_checklist_items_todo_sort
  ON todo_checklist_items(todo_id, sort_order, created_at_ms);
CREATE INDEX IF NOT EXISTS idx_todo_checklist_items_todo_done
  ON todo_checklist_items(todo_id, is_done);

CREATE TABLE IF NOT EXISTS todo_checklist_suggestions (
  id TEXT PRIMARY KEY,
  todo_id TEXT NOT NULL,
  content BLOB NOT NULL,
  sort_order INTEGER NOT NULL DEFAULT 0,
  state TEXT NOT NULL,
  source TEXT NOT NULL,
  generation_key TEXT,
  created_at_ms INTEGER NOT NULL,
  updated_at_ms INTEGER NOT NULL,
  dismissed_at_ms INTEGER,
  applied_checklist_item_id TEXT,
  FOREIGN KEY(todo_id) REFERENCES todos(id) ON DELETE CASCADE,
  FOREIGN KEY(applied_checklist_item_id) REFERENCES todo_checklist_items(id) ON DELETE SET NULL
);
CREATE INDEX IF NOT EXISTS idx_todo_checklist_suggestions_todo_state
  ON todo_checklist_suggestions(todo_id, state, sort_order);
CREATE INDEX IF NOT EXISTS idx_todo_checklist_suggestions_generation_key
  ON todo_checklist_suggestions(generation_key);

PRAGMA user_version = 33;
"#,
    )?;
    Ok(())
}


fn migrate_from_v33_to_v34(conn: &Connection) -> Result<()> {
    conn.execute_batch(
        r#"
UPDATE todo_checklist_suggestions
SET state = 'pending',
    updated_at_ms = CAST((julianday('now') - 2440587.5) * 86400000 AS INTEGER)
WHERE state = 'applied' AND applied_checklist_item_id IS NULL;

CREATE TRIGGER IF NOT EXISTS trg_todo_checklist_suggestions_revert_deleted_item
BEFORE DELETE ON todo_checklist_items
FOR EACH ROW
BEGIN
  UPDATE todo_checklist_suggestions
  SET state = 'pending',
      updated_at_ms = CAST((julianday('now') - 2440587.5) * 86400000 AS INTEGER),
      applied_checklist_item_id = NULL
  WHERE applied_checklist_item_id = OLD.id
    AND state = 'applied';
END;

PRAGMA user_version = 34;
"#,
    )?;
    Ok(())
}

fn migrate_from_v34_to_v35(conn: &Connection) -> Result<()> {
    conn.execute_batch(
        r#"
CREATE TABLE IF NOT EXISTS todo_followup_suggestions (
  id TEXT PRIMARY KEY,
  todo_id TEXT NOT NULL,
  content BLOB NOT NULL,
  state TEXT NOT NULL,
  source TEXT NOT NULL,
  generation_mode TEXT NOT NULL,
  generation_key TEXT,
  citations_json TEXT,
  created_at_ms INTEGER NOT NULL,
  updated_at_ms INTEGER NOT NULL,
  dismissed_at_ms INTEGER,
  applied_activity_id TEXT,
  FOREIGN KEY(todo_id) REFERENCES todos(id) ON DELETE CASCADE,
  FOREIGN KEY(applied_activity_id) REFERENCES todo_activities(id) ON DELETE SET NULL
);
CREATE INDEX IF NOT EXISTS idx_todo_followup_suggestions_todo_state
  ON todo_followup_suggestions(todo_id, state, created_at_ms);
CREATE INDEX IF NOT EXISTS idx_todo_followup_suggestions_generation_key
  ON todo_followup_suggestions(generation_key);

CREATE TABLE IF NOT EXISTS todo_followup_generation_jobs (
  todo_id TEXT PRIMARY KEY,
  trigger_kind TEXT NOT NULL,
  status TEXT NOT NULL,
  attempts INTEGER NOT NULL DEFAULT 0,
  next_retry_at_ms INTEGER,
  last_error TEXT,
  include_manual_followups INTEGER NOT NULL DEFAULT 0,
  manual_override_followup INTEGER NOT NULL DEFAULT 0,
  task_type_hint TEXT,
  created_at_ms INTEGER NOT NULL,
  updated_at_ms INTEGER NOT NULL,
  FOREIGN KEY(todo_id) REFERENCES todos(id) ON DELETE CASCADE
);
CREATE INDEX IF NOT EXISTS idx_todo_followup_generation_jobs_status_due
  ON todo_followup_generation_jobs(status, next_retry_at_ms, updated_at_ms);

PRAGMA user_version = 35;
"#,
    )?;
    Ok(())
}

pub(crate) fn app_dir_from_conn(conn: &Connection) -> Result<PathBuf> {
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
DELETE FROM todo_followup_generation_jobs;
DELETE FROM tag_merge_feedback;
DELETE FROM message_tag_autofill_events;
DELETE FROM message_tag_autofill_jobs;
DELETE FROM message_tags;
DELETE FROM message_attachments;
DELETE FROM attachment_derivations;
DELETE FROM cloud_media_backup;
DELETE FROM attachment_variants;
DELETE FROM attachment_exif;
DELETE FROM attachment_metadata;
DELETE FROM attachment_places;
DELETE FROM attachment_annotations;
DELETE FROM attachment_chunk_embedding_jobs;
DELETE FROM attachment_text_chunks;
DELETE FROM attachment_deletions;
DELETE FROM attachments;
DELETE FROM messages;
DELETE FROM tags;
DELETE FROM conversations;
DELETE FROM todo_deletions;
DELETE FROM todo_checklist_suggestions;
DELETE FROM todo_followup_suggestions;
DELETE FROM todo_checklist_items;
DELETE FROM todos;
DELETE FROM todo_activity_attachments;
DELETE FROM todo_activities;
DELETE FROM todo_recurrences;
DELETE FROM todo_series;
DELETE FROM events;
DELETE FROM detached_ask_completion_claims;
DELETE FROM embedding_artifact_manifests;
DELETE FROM knowledge_document_usage;
DELETE FROM knowledge_embeddings;
DELETE FROM knowledge_index_jobs;
DELETE FROM knowledge_units;
DELETE FROM knowledge_documents;
UPDATE knowledge_rebuild_state
SET status = 'empty',
    rebuild_required = 0,
    stale_reason = NULL,
    last_error = NULL,
    last_rebuild_started_at_ms = NULL,
    last_rebuild_completed_at_ms = NULL,
    current_document_id = NULL,
    current_stage = NULL,
    documents_indexed = 0,
    units_indexed = 0,
    embeddings_indexed = 0,
    total_documents = 0,
    cancel_requested = 0,
    last_indexed_model_name = NULL,
    last_indexed_dim = NULL;
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
