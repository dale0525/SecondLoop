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
DELETE FROM todos;
DELETE FROM todo_activity_attachments;
DELETE FROM todo_activities;
DELETE FROM todo_recurrences;
DELETE FROM todo_series;
DELETE FROM events;
DELETE FROM detached_ask_completion_claims;
DELETE FROM embedding_artifact_manifests;
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
