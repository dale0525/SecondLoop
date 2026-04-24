struct AttachmentsResetGuard {
    attachments_dir: PathBuf,
    staged_dir: Option<PathBuf>,
}

const ATTACHMENTS_RESET_STAGED_PREFIX: &str = "attachments.reset-staged-";

fn is_attachment_reset_staging_name(name: &str) -> bool {
    name.starts_with(ATTACHMENTS_RESET_STAGED_PREFIX)
}

pub(crate) fn attachment_reset_staging_dirs_have_entries(app_dir: &Path) -> Result<bool> {
    match fs::read_dir(app_dir) {
        Ok(entries) => {
            for entry in entries {
                let entry = entry?;
                let name = entry.file_name();
                if !is_attachment_reset_staging_name(&name.to_string_lossy()) {
                    continue;
                }
                if entry.file_type()?.is_dir() {
                    match fs::read_dir(entry.path()) {
                        Ok(mut entries) => {
                            if entries.next().is_some() {
                                return Ok(true);
                            }
                        }
                        Err(e) if e.kind() == std::io::ErrorKind::NotFound => {}
                        Err(e) => return Err(e.into()),
                    }
                }
            }
            Ok(false)
        }
        Err(e) if e.kind() == std::io::ErrorKind::NotFound => Ok(false),
        Err(e) => Err(e.into()),
    }
}

fn remove_stale_attachment_reset_staging_dirs(app_dir: &Path) -> Result<()> {
    match fs::read_dir(app_dir) {
        Ok(entries) => {
            for entry in entries {
                let entry = entry?;
                let name = entry.file_name();
                if !is_attachment_reset_staging_name(&name.to_string_lossy()) {
                    continue;
                }
                if entry.file_type()?.is_dir() {
                    best_effort_remove_dir_all(&entry.path())?;
                }
            }
            Ok(())
        }
        Err(e) if e.kind() == std::io::ErrorKind::NotFound => Ok(()),
        Err(e) => Err(e.into()),
    }
}

impl AttachmentsResetGuard {
    fn prepare(app_dir: &Path) -> Result<Self> {
        let attachments_dir = app_dir.join("attachments");
        let staged_dir = if attachments_dir.exists() {
            if !attachments_dir.is_dir() {
                return Err(anyhow!("attachments path is not a directory"));
            }
            let staged_dir = app_dir.join(format!(
                "attachments.reset-staged-{}",
                uuid::Uuid::new_v4()
            ));
            fs::rename(&attachments_dir, &staged_dir)?;
            Some(staged_dir)
        } else {
            None
        };
        Ok(Self {
            attachments_dir,
            staged_dir,
        })
    }

    fn restore(&mut self) -> Result<()> {
        best_effort_remove_dir_all(&self.attachments_dir)?;
        if let Some(staged_dir) = self.staged_dir.take() {
            fs::rename(staged_dir, &self.attachments_dir)?;
        }
        Ok(())
    }

    fn finish(mut self) -> Result<()> {
        if let Some(staged_dir) = self.staged_dir.take() {
            best_effort_remove_dir_all(&staged_dir)?;
        }
        Ok(())
    }
}

pub fn reset_vault_data_preserving_llm_profiles(conn: &Connection) -> Result<()> {
    let app_dir = app_dir_from_conn(conn).ok();
    conn.execute_batch("BEGIN IMMEDIATE;")?;
    let mut attachments_guard = None;

    if let Some(app_dir) = app_dir.as_ref() {
        if let Err(error) = remove_stale_attachment_reset_staging_dirs(app_dir) {
            let _ = conn.execute_batch("ROLLBACK;");
            return Err(error);
        }
        match AttachmentsResetGuard::prepare(app_dir) {
            Ok(guard) => attachments_guard = Some(guard),
            Err(error) => {
                let _ = conn.execute_batch("ROLLBACK;");
                return Err(error);
            }
        }
    }

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
DELETE FROM knowledge_document_feedback;
DELETE FROM knowledge_page_lints;
DELETE FROM knowledge_page_history;
DELETE FROM knowledge_page_versions;
DELETE FROM knowledge_pages;
DELETE FROM knowledge_claims;
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
    pages_refresh_required = 1,
    last_pages_refresh_completed_at_ms = NULL,
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
            if let Err(error) = conn.execute_batch("COMMIT;") {
                let rollback_result = conn.execute_batch("ROLLBACK;");
                if let Some(guard) = attachments_guard.as_mut() {
                    guard.restore()?;
                }
                if let Err(rollback_error) = rollback_result {
                    return Err(anyhow!(
                        "{error}; transaction rollback failed: {rollback_error}"
                    ));
                }
                return Err(error.into());
            }
            if let Some(guard) = attachments_guard {
                guard.finish()?;
            }
            if let Some(app_dir) = app_dir.as_ref() {
                migration_archive_remove_rollback_snapshots_except_active(app_dir)?;
                best_effort_remove_dir_all(&migration_archive_staging_dir(app_dir))?;
                remove_external_readonly_data(app_dir)?;
            }
            Ok(())
        }
        Err(error) => {
            let _ = conn.execute_batch("ROLLBACK;");
            if let Some(guard) = attachments_guard.as_mut() {
                if let Err(restore_error) = guard.restore() {
                    return Err(anyhow!(
                        "{error}; attachment restore failed: {restore_error}"
                    ));
                }
            }
            Err(error)
        }
    }
}
