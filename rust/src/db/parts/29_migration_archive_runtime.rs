fn migration_archive_message_title(message: &Message) -> String {
    let first_line = message
        .content
        .lines()
        .find(|line| !line.trim().is_empty())
        .map(|line| line.trim())
        .unwrap_or("Message");
    first_line.chars().take(80).collect::<String>()
}

fn migration_archive_todo_activity_title(activity: &TodoActivity) -> String {
    let fallback = match activity.activity_type.as_str() {
        "note" => "Todo note",
        "status_change" => "Todo status change",
        _ => "Todo activity",
    };
    let first_line = activity
        .content
        .as_deref()
        .unwrap_or("")
        .lines()
        .find(|line| !line.trim().is_empty())
        .map(|line| line.trim())
        .unwrap_or(fallback);
    first_line.chars().take(80).collect::<String>()
}

fn migration_archive_message_updated_at_ms(conn: &Connection, message_id: &str) -> Result<i64> {
    conn.query_row(
        r#"SELECT updated_at FROM messages WHERE id = ?1"#,
        params![message_id],
        |row| row.get(0),
    )
    .map_err(|e| anyhow!("read message updated_at failed: {e}"))
}

fn migration_archive_register_attachment_refs(
    attachments: Vec<Attachment>,
    owner_item_id: &str,
    attachment_map: &mut std::collections::BTreeMap<String, MigrationArchiveAttachment>,
) -> Vec<String> {
    let mut paths = Vec::<String>::new();
    for attachment in attachments {
        let archive_path = migration_archive_attachment_path(&attachment.sha256, &attachment.mime_type);
        let entry = attachment_map
            .entry(attachment.sha256.clone())
            .or_insert_with(|| MigrationArchiveAttachment {
                sha256: attachment.sha256.clone(),
                archive_path: archive_path.clone(),
                original_filename: Path::new(&attachment.path)
                    .file_name()
                    .and_then(|value| value.to_str())
                    .unwrap_or("attachment.bin")
                    .to_string(),
                mime_type: Some(attachment.mime_type.clone()),
                size_bytes: attachment.byte_len,
                item_ids: Vec::new(),
            });
        if !entry.item_ids.iter().any(|id| id == owner_item_id) {
            entry.item_ids.push(owner_item_id.to_string());
        }
        paths.push(archive_path);
    }
    paths
}

fn migration_archive_collect_message_attachment_refs(
    conn: &Connection,
    key: &[u8; 32],
    _app_dir: &Path,
    message_id: &str,
    attachment_map: &mut std::collections::BTreeMap<String, MigrationArchiveAttachment>,
) -> Result<Vec<String>> {
    let attachments = list_message_attachments(conn, key, message_id)?;
    Ok(migration_archive_register_attachment_refs(
        attachments,
        message_id,
        attachment_map,
    ))
}

fn migration_archive_collect_todo_activity_attachment_refs(
    conn: &Connection,
    key: &[u8; 32],
    activity_id: &str,
    attachment_map: &mut std::collections::BTreeMap<String, MigrationArchiveAttachment>,
) -> Result<Vec<String>> {
    let attachments = list_todo_activity_attachments(conn, key, activity_id)?;
    Ok(migration_archive_register_attachment_refs(
        attachments,
        activity_id,
        attachment_map,
    ))
}

fn migration_archive_copy_attachments(
    conn: &Connection,
    key: &[u8; 32],
    app_dir: &Path,
    stage_dir: &Path,
    attachments: &std::collections::BTreeMap<String, MigrationArchiveAttachment>,
) -> Result<()> {
    for attachment in attachments.values() {
        let bytes = read_attachment_bytes(conn, key, app_dir, &attachment.sha256)?;
        let full_path = stage_dir.join(&attachment.archive_path);
        if let Some(parent) = full_path.parent() {
            fs::create_dir_all(parent)?;
        }
        fs::write(full_path, bytes)?;
    }
    Ok(())
}

const MIGRATION_ARCHIVE_ROLLBACK_SNAPSHOT_AAD: &[u8] = b"migration_archive.rollback_snapshot";

fn migration_archive_write_zip_to_writer<W: std::io::Write + std::io::Seek>(
    stage_dir: &Path,
    writer: W,
) -> Result<W> {
    let mut writer = zip::ZipWriter::new(writer);
    let options = zip::write::FileOptions::default()
        .compression_method(zip::CompressionMethod::Deflated);
    let mut files = Vec::<PathBuf>::new();
    collect_files_recursively(stage_dir, &mut files)?;
    files.sort();
    for path in files {
        let rel = path
            .strip_prefix(stage_dir)
            .unwrap_or(&path)
            .to_string_lossy()
            .replace('\\', "/");
        writer.start_file(rel, options)?;
        let bytes = fs::read(&path)?;
        use std::io::Write as _;
        writer.write_all(&bytes)?;
    }
    Ok(writer.finish()?)
}

fn migration_archive_write_zip_bytes(stage_dir: &Path) -> Result<Vec<u8>> {
    let cursor = migration_archive_write_zip_to_writer(stage_dir, std::io::Cursor::new(Vec::new()))?;
    Ok(cursor.into_inner())
}

fn migration_archive_write_zip(stage_dir: &Path, output_path: &Path) -> Result<()> {
    if let Some(parent) = output_path.parent() {
        fs::create_dir_all(parent)?;
    }
    let file = fs::File::create(output_path)?;
    let _ = migration_archive_write_zip_to_writer(stage_dir, file)?;
    Ok(())
}

pub fn export_migration_archive(
    conn: &Connection,
    key: &[u8; 32],
    app_dir: &Path,
    output_path: &Path,
) -> Result<MigrationArchiveManifest> {
    let mut on_event = |_progress: MigrationArchiveProgress| {};
    export_migration_archive_with_callbacks(conn, key, app_dir, output_path, &mut on_event)
}

fn migration_archive_build_stage(
    conn: &Connection,
    key: &[u8; 32],
    app_dir: &Path,
    stage_dir: &Path,
    on_stage: &mut dyn FnMut(&str, i64) -> Result<()>,
) -> Result<MigrationArchiveManifest> {
    on_stage("collecting", 1)?;
    let mut items = Vec::<MigrationArchiveItem>::new();
    let mut relations = Vec::<MigrationArchiveRelation>::new();
    let mut attachments = std::collections::BTreeMap::<String, MigrationArchiveAttachment>::new();
    let conversations = list_conversations(conn, key)?;
    let todos = list_todos(conn, key)?;
    let events = list_events(conn, key)?;
    let mut item_titles = std::collections::BTreeMap::<String, String>::new();

    on_stage("writing_markdown", 2)?;
    for conversation in &conversations {
        let item = MigrationArchiveItem {
            id: conversation.id.clone(),
            entity_type: "conversation".to_string(),
            markdown_path: migration_archive_markdown_path_for_id(&conversation.id),
            created_at_ms: conversation.created_at_ms,
            updated_at_ms: conversation.updated_at_ms,
            title: conversation.title.clone(),
            tags: Vec::new(),
            status: None,
            extra_json: None,
        };
        item_titles.insert(item.id.clone(), item.title.clone());
        let markdown = migration_archive_markdown_doc(&item, "", &[], &[]);
        let full_path = stage_dir.join(&item.markdown_path);
        if let Some(parent) = full_path.parent() {
            fs::create_dir_all(parent)?;
        }
        fs::write(full_path, markdown)?;
        items.push(item);
    }

    for conversation in &conversations {
        for message in list_messages(conn, key, &conversation.id)? {
            let tags = list_message_tags(conn, key, &message.id)?
                .into_iter()
                .map(|tag| tag.name)
                .collect::<Vec<String>>();
            let title = migration_archive_message_title(&message);
            let attachment_paths = migration_archive_collect_message_attachment_refs(
                conn,
                key,
                app_dir,
                &message.id,
                &mut attachments,
            )?;
            let updated_at_ms = migration_archive_message_updated_at_ms(conn, &message.id)?;
            let item = MigrationArchiveItem {
                id: message.id.clone(),
                entity_type: "message".to_string(),
                markdown_path: migration_archive_markdown_path_for_id(&message.id),
                created_at_ms: message.created_at_ms,
                updated_at_ms,
                title: title.clone(),
                tags,
                status: None,
                extra_json: Some(
                    serde_json::json!({
                        "conversation_id": message.conversation_id,
                        "role": message.role,
                        "is_memory": message.is_memory,
                        "content": message.content,
                    })
                    .to_string(),
                ),
            };
            item_titles.insert(item.id.clone(), item.title.clone());
            relations.push(MigrationArchiveRelation {
                from_id: item.id.clone(),
                to_id: conversation.id.clone(),
                relation_type: "belongs_to_conversation".to_string(),
            });
            let markdown = migration_archive_markdown_doc(&item, &message.content, &attachment_paths, &[]);
            let full_path = stage_dir.join(&item.markdown_path);
            if let Some(parent) = full_path.parent() {
                fs::create_dir_all(parent)?;
            }
            fs::write(full_path, markdown)?;
            items.push(item);
        }
    }

    for todo in &todos {
        let mut internal_links = Vec::<String>::new();
        if let Some(source_entry_id) = todo.source_entry_id.as_ref() {
            let title = item_titles
                .get(source_entry_id)
                .cloned()
                .unwrap_or_else(|| source_entry_id.clone());
            internal_links.push(migration_archive_wikilink(source_entry_id, &title));
            relations.push(MigrationArchiveRelation {
                from_id: todo.id.clone(),
                to_id: source_entry_id.clone(),
                relation_type: "source_entry".to_string(),
            });
        }
        let item = MigrationArchiveItem {
            id: todo.id.clone(),
            entity_type: "todo".to_string(),
            markdown_path: migration_archive_markdown_path_for_id(&todo.id),
            created_at_ms: todo.created_at_ms,
            updated_at_ms: todo.updated_at_ms,
            title: todo.title.clone(),
            tags: Vec::new(),
            status: Some(todo.status.clone()),
            extra_json: Some(
                serde_json::json!({
                    "due_at_ms": todo.due_at_ms,
                    "review_stage": todo.review_stage,
                    "next_review_at_ms": todo.next_review_at_ms,
                    "last_review_at_ms": todo.last_review_at_ms,
                })
                .to_string(),
            ),
        };
        item_titles.insert(item.id.clone(), item.title.clone());
        let markdown = migration_archive_markdown_doc(&item, "", &[], &internal_links);
        let full_path = stage_dir.join(&item.markdown_path);
        if let Some(parent) = full_path.parent() {
            fs::create_dir_all(parent)?;
        }
        fs::write(full_path, markdown)?;
        items.push(item);

        for activity in list_todo_activities(conn, key, &todo.id)? {
            let title = migration_archive_todo_activity_title(&activity);
            let activity_content = activity.content.clone().unwrap_or_default();
            let attachment_paths = migration_archive_collect_todo_activity_attachment_refs(
                conn,
                key,
                &activity.id,
                &mut attachments,
            )?;
            let mut activity_links = vec![migration_archive_wikilink(&todo.id, &todo.title)];
            relations.push(MigrationArchiveRelation {
                from_id: activity.id.clone(),
                to_id: todo.id.clone(),
                relation_type: "belongs_to_todo".to_string(),
            });
            if let Some(source_message_id) = activity.source_message_id.as_ref() {
                let source_title = item_titles
                    .get(source_message_id)
                    .cloned()
                    .unwrap_or_else(|| source_message_id.clone());
                activity_links.push(migration_archive_wikilink(source_message_id, &source_title));
                relations.push(MigrationArchiveRelation {
                    from_id: activity.id.clone(),
                    to_id: source_message_id.clone(),
                    relation_type: "source_message".to_string(),
                });
            }
            let item = MigrationArchiveItem {
                id: activity.id.clone(),
                entity_type: "todo_activity".to_string(),
                markdown_path: migration_archive_markdown_path_for_id(&activity.id),
                created_at_ms: activity.created_at_ms,
                updated_at_ms: activity.created_at_ms,
                title: title.clone(),
                tags: Vec::new(),
                status: None,
                extra_json: Some(
                    serde_json::json!({
                        "todo_id": activity.todo_id,
                        "activity_type": activity.activity_type,
                        "from_status": activity.from_status,
                        "to_status": activity.to_status,
                        "content": activity_content,
                        "source_message_id": activity.source_message_id,
                    })
                    .to_string(),
                ),
            };
            item_titles.insert(item.id.clone(), item.title.clone());
            let markdown = migration_archive_markdown_doc(
                &item,
                &activity_content,
                &attachment_paths,
                &activity_links,
            );
            let full_path = stage_dir.join(&item.markdown_path);
            if let Some(parent) = full_path.parent() {
                fs::create_dir_all(parent)?;
            }
            fs::write(full_path, markdown)?;
            items.push(item);
        }
    }

    for event in &events {
        let mut internal_links = Vec::<String>::new();
        if let Some(source_entry_id) = event.source_entry_id.as_ref() {
            let title = item_titles
                .get(source_entry_id)
                .cloned()
                .unwrap_or_else(|| source_entry_id.clone());
            internal_links.push(migration_archive_wikilink(source_entry_id, &title));
            relations.push(MigrationArchiveRelation {
                from_id: event.id.clone(),
                to_id: source_entry_id.clone(),
                relation_type: "source_entry".to_string(),
            });
        }
        let item = MigrationArchiveItem {
            id: event.id.clone(),
            entity_type: "event".to_string(),
            markdown_path: migration_archive_markdown_path_for_id(&event.id),
            created_at_ms: event.created_at_ms,
            updated_at_ms: event.updated_at_ms,
            title: event.title.clone(),
            tags: Vec::new(),
            status: None,
            extra_json: Some(
                serde_json::json!({
                    "start_at_ms": event.start_at_ms,
                    "end_at_ms": event.end_at_ms,
                    "tz": event.tz,
                    "source_entry_id": event.source_entry_id,
                })
                .to_string(),
            ),
        };
        item_titles.insert(item.id.clone(), item.title.clone());
        let markdown = migration_archive_markdown_doc(&item, "", &[], &internal_links);
        let full_path = stage_dir.join(&item.markdown_path);
        if let Some(parent) = full_path.parent() {
            fs::create_dir_all(parent)?;
        }
        fs::write(full_path, markdown)?;
        items.push(item);
    }

    on_stage("copying_attachments", 3)?;
    migration_archive_copy_attachments(conn, key, app_dir, stage_dir, &attachments)?;
    let attachments_vec = attachments.into_values().collect::<Vec<MigrationArchiveAttachment>>();
    fs::create_dir_all(stage_dir.join("attachments"))?;
    let manifest = MigrationArchiveManifest {
        schema_version: MIGRATION_ARCHIVE_SCHEMA_VERSION,
        archive_kind: "migration".to_string(),
        exported_at_ms: now_ms(),
        app_version: env!("CARGO_PKG_VERSION").to_string(),
        items,
        attachments: attachments_vec.clone(),
        relations,
    };
    validate_migration_archive_manifest(&manifest)?;
    fs::write(
        stage_dir.join("attachments/index.json"),
        serde_json::to_vec_pretty(&attachments_vec)?,
    )?;
    fs::write(
        stage_dir.join("export-manifest.json"),
        serde_json::to_vec_pretty(&manifest)?,
    )?;
    Ok(manifest)
}

fn migration_archive_write_encrypted_snapshot(
    conn: &Connection,
    key: &[u8; 32],
    app_dir: &Path,
    snapshot_path: &Path,
) -> Result<()> {
    let stage_dir = migration_archive_staging_dir(app_dir).join(uuid::Uuid::new_v4().to_string());
    fs::create_dir_all(&stage_dir)?;

    let snapshot_result = (|| -> Result<()> {
        let mut on_stage = |_stage: &str, _done: i64| Ok(());
        let _manifest = migration_archive_build_stage(conn, key, app_dir, &stage_dir, &mut on_stage)?;
        let zip_bytes = migration_archive_write_zip_bytes(&stage_dir)?;
        let encrypted = encrypt_bytes(key, &zip_bytes, MIGRATION_ARCHIVE_ROLLBACK_SNAPSHOT_AAD)?;
        if let Some(parent) = snapshot_path.parent() {
            fs::create_dir_all(parent)?;
        }
        fs::write(snapshot_path, encrypted)?;
        Ok(())
    })();

    let _ = fs::remove_dir_all(&stage_dir);
    snapshot_result
}

fn migration_archive_materialize_encrypted_snapshot(
    app_dir: &Path,
    key: &[u8; 32],
    snapshot_path: &Path,
) -> Result<MaterializedExternalImportSource> {
    let encrypted = fs::read(snapshot_path)?;
    let zip_bytes = decrypt_bytes(key, &encrypted, MIGRATION_ARCHIVE_ROLLBACK_SNAPSHOT_AAD)?;
    materialize_external_import_source_from_zip_bytes(app_dir, "rollback-snapshot", &zip_bytes)
}

fn migration_archive_restore_from_encrypted_snapshot(
    app_dir: &Path,
    key: &[u8; 32],
    snapshot_path: &Path,
) -> Result<()> {
    let rollback_result = match migration_archive_materialize_encrypted_snapshot(
        app_dir,
        key,
        snapshot_path,
    ) {
        Ok(source) => {
            let result = migration_archive_replace_vault_with_source_root(app_dir, key, &source.root_dir)
                .map(|_| ());
            cleanup_materialized_external_import_source(&source);
            result
        }
        Err(err) => Err(err),
    };
    migration_archive_remove_snapshot(Some(snapshot_path));
    rollback_result
}

pub fn export_migration_archive_with_callbacks(
    conn: &Connection,
    key: &[u8; 32],
    app_dir: &Path,
    output_path: &Path,
    on_event: &mut dyn FnMut(MigrationArchiveProgress),
) -> Result<MigrationArchiveManifest> {
    let total_steps = 5;
    migration_archive_record_progress(app_dir, on_event, "export", "preparing", 0, total_steps, "in_progress")?;
    let stage_dir = migration_archive_staging_dir(app_dir).join(uuid::Uuid::new_v4().to_string());
    fs::create_dir_all(&stage_dir)?;

    let export_result = (|| -> Result<MigrationArchiveManifest> {
        let mut on_stage = |stage: &str, done: i64| {
            migration_archive_record_progress(app_dir, on_event, "export", stage, done, total_steps, "in_progress")
        };
        let manifest = migration_archive_build_stage(conn, key, app_dir, &stage_dir, &mut on_stage)?;
        migration_archive_record_progress(app_dir, on_event, "export", "zipping", 4, total_steps, "in_progress")?;
        migration_archive_write_zip(&stage_dir, output_path)?;
        migration_archive_record_terminal_state(
            app_dir,
            on_event,
            "export",
            "completed",
            5,
            total_steps,
            "completed",
            None,
            Some(manifest.items.len() as i64),
            Some(manifest.attachments.len() as i64),
            Some(manifest.relations.len() as i64),
        )?;
        Ok(manifest)
    })();

    let _ = fs::remove_dir_all(&stage_dir);
    export_result
}

fn migration_archive_estimated_size_bytes(conn: &Connection) -> Result<i64> {
    let structured_bytes: i64 = conn.query_row(
        r#"
SELECT (
  COALESCE((SELECT SUM(LENGTH(title)) FROM conversations), 0) +
  COALESCE((SELECT SUM(LENGTH(content)) FROM messages WHERE COALESCE(is_deleted, 0) = 0), 0) +
  COALESCE((SELECT SUM(LENGTH(title)) FROM todos), 0) +
  COALESCE((SELECT SUM(LENGTH(content)) FROM todo_activities), 0) +
  COALESCE((SELECT SUM(LENGTH(title)) FROM events), 0)
)
"#,
        [],
        |row| row.get(0),
    )?;
    let attachment_bytes: i64 = conn.query_row(
        r#"SELECT COALESCE(SUM(byte_len), 0) FROM attachments"#,
        [],
        |row| row.get(0),
    )?;
    let metadata_overhead: i64 = conn.query_row(
        r#"
SELECT (
  ((SELECT COUNT(*) FROM conversations) +
   (SELECT COUNT(*) FROM messages WHERE COALESCE(is_deleted, 0) = 0) +
   (SELECT COUNT(*) FROM todos) +
   (SELECT COUNT(*) FROM todo_activities) +
   (SELECT COUNT(*) FROM events)) * 256 +
  (SELECT COUNT(*) FROM attachments) * 160
)
"#,
        [],
        |row| row.get(0),
    )?;
    Ok(structured_bytes + attachment_bytes + metadata_overhead)
}

fn migration_archive_with_immediate_transaction<T>(
    conn: &Connection,
    f: impl FnOnce() -> Result<T>,
) -> Result<T> {
    conn.execute_batch("BEGIN IMMEDIATE;")?;
    match f() {
        Ok(value) => match conn.execute_batch("COMMIT;") {
            Ok(()) => Ok(value),
            Err(error) => {
                let _ = conn.execute_batch("ROLLBACK;");
                Err(error.into())
            }
        },
        Err(error) => {
            let _ = conn.execute_batch("ROLLBACK;");
            Err(error)
        }
    }
}

const MIGRATION_ARCHIVE_REBUILD_BATCH_SIZE: usize = 512;
const MIGRATION_ARCHIVE_REBUILD_STALL_ROUNDS: usize = 3;

fn migration_archive_rebuild_derived_indexes(conn: &Connection, key: &[u8; 32]) -> Result<()> {
    crate::knowledge::ensure_knowledge_rebuild_requested(conn)?;

    let mut stall_rounds = 0usize;
    loop {
        let processed = crate::knowledge::process_pending_knowledge_index_jobs_active(
            conn,
            key,
            MIGRATION_ARCHIVE_REBUILD_BATCH_SIZE,
        )?;
        let status = crate::knowledge::read_knowledge_index_status(conn, key)?;
        match status.status.as_str() {
            "complete" | "completed" | "empty" => return Ok(()),
            "failed" | "cancelled" => {
                return Err(anyhow!(
                    "knowledge rebuild did not complete: {}{}",
                    status.status,
                    status
                        .last_error
                        .as_deref()
                        .map(|e| format!(" ({e})"))
                        .unwrap_or_default()
                ));
            }
            _ => {}
        }

        if processed == 0 {
            stall_rounds += 1;
            if stall_rounds >= MIGRATION_ARCHIVE_REBUILD_STALL_ROUNDS {
                return Err(anyhow!("knowledge rebuild stalled with status {}", status.status));
            }
        } else {
            stall_rounds = 0;
        }
    }
}

pub fn migration_archive_export_estimate(
    conn: &Connection,
) -> Result<MigrationArchiveExportEstimate> {
    let item_count: i64 = conn.query_row(
        r#"
SELECT (
  (SELECT COUNT(*) FROM conversations) +
  (SELECT COUNT(*) FROM messages WHERE COALESCE(is_deleted, 0) = 0) +
  (SELECT COUNT(*) FROM todos) +
  (SELECT COUNT(*) FROM todo_activities) +
  (SELECT COUNT(*) FROM events)
)
"#,
        [],
        |row| row.get(0),
    )?;
    let attachment_count: i64 = conn.query_row(r#"SELECT COUNT(*) FROM attachments"#, [], |row| row.get(0))?;
    let estimated_size_bytes = migration_archive_estimated_size_bytes(conn)?;
    Ok(MigrationArchiveExportEstimate {
        schema_version: MIGRATION_ARCHIVE_SCHEMA_VERSION,
        archive_kind: "migration".to_string(),
        item_count,
        attachment_count,
        estimated_size_bytes,
    })
}


fn migration_archive_parse_item_extra(item: &MigrationArchiveItem) -> Result<serde_json::Value> {
    match item.extra_json.as_deref() {
        Some(raw) if !raw.trim().is_empty() => Ok(serde_json::from_str(raw)?),
        _ => Ok(serde_json::json!({})),
    }
}

fn migration_archive_restore_conversation(
    conn: &Connection,
    key: &[u8; 32],
    item: &MigrationArchiveItem,
) -> Result<()> {
    let title_blob = encrypt_bytes(key, item.title.as_bytes(), b"conversation.title")?;
    conn.execute(
        r#"INSERT OR REPLACE INTO conversations(id, title, created_at, updated_at)
           VALUES (?1, ?2, ?3, ?4)"#,
        params![item.id, title_blob, item.created_at_ms, item.updated_at_ms],
    )?;
    Ok(())
}

fn migration_archive_restore_message_tags(
    conn: &Connection,
    key: &[u8; 32],
    message_id: &str,
    tag_names: &[String],
) -> Result<()> {
    ensure_system_tags(conn, key)?;

    let now = now_ms();
    let mut tag_ids = Vec::<String>::new();
    for tag_name in tag_names {
        let trimmed = tag_name.trim();
        if trimmed.is_empty() {
            continue;
        }

        let tag_id = if let Some(system_key) = map_to_system_key(trimmed) {
            read_tag_by_system_key(conn, key, system_key)?
                .map(|tag| tag.id)
                .ok_or_else(|| anyhow!("missing system tag: {system_key}"))?
        } else if let Some(existing) = find_existing_custom_tag_by_name(conn, key, trimmed)? {
            existing.id
        } else {
            let tag_id = uuid::Uuid::new_v4().to_string();
            let aad = format!("tag.name:{tag_id}");
            let name_blob = encrypt_bytes(key, trimmed.as_bytes(), aad.as_bytes())?;
            conn.execute(
                r#"INSERT INTO tags(id, name, system_key, is_system, color, created_at_ms, updated_at_ms)
                   VALUES (?1, ?2, NULL, 0, NULL, ?3, ?4)"#,
                params![tag_id, name_blob, now, now],
            )?;
            tag_id
        };

        if !tag_ids.iter().any(|existing| existing == &tag_id) {
            tag_ids.push(tag_id);
        }
    }

    conn.execute(
        r#"DELETE FROM message_tags WHERE message_id = ?1"#,
        params![message_id],
    )?;
    for tag_id in tag_ids {
        conn.execute(
            r#"INSERT INTO message_tags(message_id, tag_id, created_at_ms)
               VALUES (?1, ?2, ?3)"#,
            params![message_id, tag_id, now],
        )?;
    }
    Ok(())
}

fn migration_archive_restore_message(
    conn: &Connection,
    key: &[u8; 32],
    item: &MigrationArchiveItem,
) -> Result<()> {
    let extra = migration_archive_parse_item_extra(item)?;
    let conversation_id = extra["conversation_id"]
        .as_str()
        .ok_or_else(|| anyhow!("message extra_json missing conversation_id"))?;
    let role = extra["role"]
        .as_str()
        .ok_or_else(|| anyhow!("message extra_json missing role"))?;
    let content = extra["content"]
        .as_str()
        .ok_or_else(|| anyhow!("message extra_json missing content"))?;
    let is_memory = extra["is_memory"].as_bool().unwrap_or(true);
    let device_id = get_or_create_device_id(conn)?;
    let seq = next_device_seq(conn, &device_id)?;
    let content_blob = encrypt_bytes(key, content.as_bytes(), b"message.content")?;
    conn.execute(
        r#"INSERT OR REPLACE INTO messages(
             id, conversation_id, role, content, created_at, updated_at,
             updated_by_device_id, updated_by_seq, is_deleted, needs_embedding, is_memory
           ) VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, 0, ?9, ?10)"#,
        params![
            item.id,
            conversation_id,
            role,
            content_blob,
            item.created_at_ms,
            item.updated_at_ms,
            device_id,
            seq,
            if is_memory { 1 } else { 0 },
            if is_memory { 1 } else { 0 },
        ],
    )?;
    if !item.tags.is_empty() {
        migration_archive_restore_message_tags(conn, key, &item.id, &item.tags)?;
    }
    Ok(())
}

fn migration_archive_restore_todo(
    conn: &Connection,
    key: &[u8; 32],
    item: &MigrationArchiveItem,
    source_entry_id: Option<&str>,
) -> Result<()> {
    let extra = migration_archive_parse_item_extra(item)?;
    let title_blob = encrypt_bytes(key, item.title.as_bytes(), b"todo.title")?;
    conn.execute(
        r#"INSERT OR REPLACE INTO todos(
             id, title, due_at_ms, status, source_entry_id,
             created_at_ms, updated_at_ms, review_stage, next_review_at_ms, last_review_at_ms, needs_embedding
           ) VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, 1)"#,
        params![
            item.id,
            title_blob,
            extra["due_at_ms"].as_i64(),
            item.status.as_deref().unwrap_or("open"),
            source_entry_id,
            item.created_at_ms,
            item.updated_at_ms,
            extra["review_stage"].as_i64(),
            extra["next_review_at_ms"].as_i64(),
            extra["last_review_at_ms"].as_i64(),
        ],
    )?;
    Ok(())
}

fn migration_archive_restore_todo_activity(
    conn: &Connection,
    key: &[u8; 32],
    item: &MigrationArchiveItem,
) -> Result<()> {
    let extra = migration_archive_parse_item_extra(item)?;
    let todo_id = extra["todo_id"]
        .as_str()
        .ok_or_else(|| anyhow!("todo_activity extra_json missing todo_id"))?;
    let activity_type = extra["activity_type"].as_str().unwrap_or("note");
    let content_blob = match extra.get("content") {
        Some(serde_json::Value::String(content)) => {
            let aad = format!("todo_activity.content:{}", item.id);
            Some(encrypt_bytes(key, content.as_bytes(), aad.as_bytes())?)
        }
        _ => None,
    };
    conn.execute(
        r#"INSERT OR REPLACE INTO todo_activities(
             id, todo_id, type, from_status, to_status, content, source_message_id, created_at_ms, needs_embedding
           ) VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9)"#,
        params![
            item.id,
            todo_id,
            activity_type,
            extra["from_status"].as_str(),
            extra["to_status"].as_str(),
            content_blob,
            extra["source_message_id"].as_str(),
            item.created_at_ms,
            if content_blob.is_some() { 1 } else { 0 },
        ],
    )?;
    Ok(())
}

fn migration_archive_restore_event(
    conn: &Connection,
    key: &[u8; 32],
    item: &MigrationArchiveItem,
    source_entry_id: Option<&str>,
) -> Result<()> {
    let extra = migration_archive_parse_item_extra(item)?;
    let title_blob = encrypt_bytes(key, item.title.as_bytes(), b"event.title")?;
    conn.execute(
        r#"INSERT OR REPLACE INTO events(
             id, title, start_at_ms, end_at_ms, tz, source_entry_id, created_at_ms, updated_at_ms
           ) VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8)"#,
        params![
            item.id,
            title_blob,
            extra["start_at_ms"].as_i64().unwrap_or(item.created_at_ms),
            extra["end_at_ms"].as_i64().unwrap_or(item.updated_at_ms),
            extra["tz"].as_str().unwrap_or("UTC"),
            source_entry_id.or_else(|| extra["source_entry_id"].as_str()),
            item.created_at_ms,
            item.updated_at_ms,
        ],
    )?;
    Ok(())
}

fn migration_archive_restore_attachment(
    conn: &Connection,
    key: &[u8; 32],
    app_dir: &Path,
    source_root: &Path,
    item_entity_type_by_id: &std::collections::BTreeMap<String, String>,
    attachment: &MigrationArchiveAttachment,
    written_attachment_paths: &mut Vec<std::path::PathBuf>,
) -> Result<()> {
    let bytes = fs::read(source_root.join(&attachment.archive_path))?;
    let rel_path = format!("attachments/{}.bin", attachment.sha256);
    let full_path = app_dir.join(&rel_path);
    fs::create_dir_all(app_dir.join("attachments"))?;
    let aad = format!("attachment.bytes:{}", attachment.sha256);
    let blob = encrypt_bytes(key, &bytes, aad.as_bytes())?;
    fs::write(&full_path, blob)?;
    written_attachment_paths.push(full_path.clone());
    conn.execute(
        r#"INSERT OR REPLACE INTO attachments(sha256, mime_type, path, byte_len, created_at)
           VALUES (?1, ?2, ?3, ?4, ?5)"#,
        params![
            attachment.sha256,
            attachment
                .mime_type
                .clone()
                .unwrap_or_else(|| "application/octet-stream".to_string()),
            rel_path,
            attachment.size_bytes,
            now_ms(),
        ],
    )?;
    for item_id in &attachment.item_ids {
        match item_entity_type_by_id.get(item_id).map(String::as_str) {
            Some("message") => {
                conn.execute(
                    r#"INSERT OR IGNORE INTO message_attachments(message_id, attachment_sha256, created_at)
                       VALUES (?1, ?2, ?3)"#,
                    params![item_id, attachment.sha256, now_ms()],
                )?;
            }
            Some("todo_activity") => {
                conn.execute(
                    r#"INSERT OR IGNORE INTO todo_activity_attachments(activity_id, attachment_sha256, created_at_ms)
                       VALUES (?1, ?2, ?3)"#,
                    params![item_id, attachment.sha256, now_ms()],
                )?;
            }
            Some(other) => {
                return Err(anyhow!("unsupported attachment owner type: {other}"));
            }
            None => {
                return Err(anyhow!("attachment owner item not found: {item_id}"));
            }
        }
    }
    Ok(())
}

fn migration_archive_restore_from_materialized_source_with_callbacks(
    app_dir: &Path,
    key: &[u8; 32],
    source_root: &Path,
    on_event: &mut dyn FnMut(MigrationArchiveProgress),
) -> Result<MigrationArchiveManifest> {
    let manifest = parse_migration_archive_manifest_json(&fs::read_to_string(
        source_root.join("export-manifest.json"),
    )?)?;
    let conn = open(app_dir)?;
    let mut written_attachment_paths = Vec::<std::path::PathBuf>::new();
    let restore_result: Result<()> = migration_archive_with_immediate_transaction(&conn, || {
        let item_entity_type_by_id = manifest
            .items
            .iter()
            .map(|item| (item.id.clone(), item.entity_type.clone()))
            .collect::<std::collections::BTreeMap<String, String>>();
        let source_entry_by_todo = manifest
            .relations
            .iter()
            .filter(|relation| {
                relation.relation_type == "source_entry"
                    && item_entity_type_by_id
                        .get(&relation.from_id)
                        .map(String::as_str)
                        == Some("todo")
            })
            .map(|relation| (relation.from_id.clone(), relation.to_id.clone()))
            .collect::<std::collections::BTreeMap<String, String>>();
        let source_entry_by_event = manifest
            .relations
            .iter()
            .filter(|relation| {
                relation.relation_type == "source_entry"
                    && item_entity_type_by_id
                        .get(&relation.from_id)
                        .map(String::as_str)
                        == Some("event")
            })
            .map(|relation| (relation.from_id.clone(), relation.to_id.clone()))
            .collect::<std::collections::BTreeMap<String, String>>();

        for item in manifest.items.iter().filter(|item| item.entity_type == "conversation") {
            migration_archive_restore_conversation(&conn, key, item)?;
        }
        for item in manifest.items.iter().filter(|item| item.entity_type == "message") {
            migration_archive_restore_message(&conn, key, item)?;
        }
        for item in manifest.items.iter().filter(|item| item.entity_type == "todo") {
            migration_archive_restore_todo(
                &conn,
                key,
                item,
                source_entry_by_todo.get(&item.id).map(String::as_str),
            )?;
        }
        for item in manifest
            .items
            .iter()
            .filter(|item| item.entity_type == "todo_activity")
        {
            migration_archive_restore_todo_activity(&conn, key, item)?;
        }
        for item in manifest.items.iter().filter(|item| item.entity_type == "event") {
            migration_archive_restore_event(
                &conn,
                key,
                item,
                source_entry_by_event.get(&item.id).map(String::as_str),
            )?;
        }
        migration_archive_record_progress(app_dir, on_event, "import", "base_items_restored", 3, 6, "in_progress")?;
        for attachment in &manifest.attachments {
            migration_archive_restore_attachment(
                &conn,
                key,
                app_dir,
                source_root,
                &item_entity_type_by_id,
                attachment,
                &mut written_attachment_paths,
            )?;
        }
        migration_archive_record_progress(app_dir, on_event, "import", "attachments_restored", 4, 6, "in_progress")?;
        migration_archive_record_progress(app_dir, on_event, "import", "relations_restored", 5, 6, "in_progress")?;
        Ok(())
    });
    match restore_result {
        Ok(()) => Ok(manifest),
        Err(err) => {
            for path in written_attachment_paths {
                let _ = fs::remove_file(path);
            }
            Err(err)
        }
    }
}

fn migration_archive_replace_vault_with_source_root(
    app_dir: &Path,
    key: &[u8; 32],
    source_root: &Path,
) -> Result<MigrationArchiveManifest> {
    let mut on_event = |_progress: MigrationArchiveProgress| {};
    migration_archive_replace_vault_with_source_root_with_callbacks(
        app_dir,
        key,
        source_root,
        &mut on_event,
    )
}

fn migration_archive_replace_vault_with_source_root_with_callbacks(
    app_dir: &Path,
    key: &[u8; 32],
    source_root: &Path,
    on_event: &mut dyn FnMut(MigrationArchiveProgress),
) -> Result<MigrationArchiveManifest> {
    let conn = open(app_dir)?;
    reset_vault_data_preserving_llm_profiles(&conn)?;
    migration_archive_record_progress(app_dir, on_event, "import", "vault_cleared", 2, 6, "in_progress")?;
    drop(conn);

    let manifest = migration_archive_restore_from_materialized_source_with_callbacks(
        app_dir,
        key,
        source_root,
        on_event,
    )?;
    let conn = open(app_dir)?;
    migration_archive_rebuild_derived_indexes(&conn, key)?;
    drop(conn);
    migration_archive_record_terminal_state(
        app_dir,
        on_event,
        "import",
        "reindex_completed",
        6,
        6,
        "completed",
        None,
        Some(manifest.items.len() as i64),
        Some(manifest.attachments.len() as i64),
        Some(manifest.relations.len() as i64),
    )?;
    Ok(manifest)
}

fn migration_archive_replace_vault_with_archive_with_callbacks(
    app_dir: &Path,
    key: &[u8; 32],
    archive_path: &Path,
    on_event: &mut dyn FnMut(MigrationArchiveProgress),
) -> Result<MigrationArchiveManifest> {
    let source = materialize_external_import_source(app_dir, archive_path)?;
    let result = migration_archive_replace_vault_with_source_root_with_callbacks(
        app_dir,
        key,
        &source.root_dir,
        on_event,
    );
    cleanup_materialized_external_import_source(&source);
    result
}

fn migration_archive_remove_snapshot(snapshot_path: Option<&Path>) {
    if let Some(path) = snapshot_path {
        let _ = fs::remove_file(path);
    }
}

pub fn import_migration_archive(
    app_dir: &Path,
    key: &[u8; 32],
    archive_path: &Path,
) -> Result<MigrationArchiveManifest> {
    let mut on_event = |_progress: MigrationArchiveProgress| {};
    import_migration_archive_with_callbacks(app_dir, key, archive_path, &mut on_event)
}

pub fn import_migration_archive_with_callbacks(
    app_dir: &Path,
    key: &[u8; 32],
    archive_path: &Path,
    on_event: &mut dyn FnMut(MigrationArchiveProgress),
) -> Result<MigrationArchiveManifest> {
    let conn = open(app_dir)?;
    let estimate = migration_archive_export_estimate(&conn)?;
    drop(conn);

    let snapshot_path = if estimate.item_count > 0 || estimate.attachment_count > 0 {
        let snapshot_dir = migration_archive_root_dir(app_dir).join("rollback");
        fs::create_dir_all(&snapshot_dir)?;
        let path = snapshot_dir.join(format!("{}.bin", uuid::Uuid::new_v4()));
        let conn = open(app_dir)?;
        migration_archive_write_encrypted_snapshot(&conn, key, app_dir, &path)?;
        Some(path)
    } else {
        None
    };
    migration_archive_record_progress(app_dir, on_event, "import", "snapshot_created", 1, 6, "in_progress")?;

    match migration_archive_replace_vault_with_archive_with_callbacks(app_dir, key, archive_path, on_event) {
        Ok(manifest) => {
            migration_archive_remove_snapshot(snapshot_path.as_deref());
            Ok(manifest)
        }
        Err(err) => {
            let original_error = err.to_string();
            let rollback_result = if let Some(path) = snapshot_path.as_ref() {
                migration_archive_restore_from_encrypted_snapshot(app_dir, key, path)
            } else {
                Ok(())
            };
            migration_archive_remove_snapshot(snapshot_path.as_deref());
            match rollback_result {
                Ok(()) => {
                    migration_archive_record_terminal_state(
                        app_dir,
                        on_event,
                        "import",
                        "rollback",
                        6,
                        6,
                        "rollback",
                        Some(original_error.clone()),
                        None,
                        None,
                        None,
                    )?;
                    Err(anyhow!(original_error))
                }
                Err(rollback_error) => {
                    migration_archive_record_terminal_state(
                        app_dir,
                        on_event,
                        "import",
                        "rollback",
                        6,
                        6,
                        "rollback",
                        Some(format!("{original_error}; rollback failed: {rollback_error}")),
                        None,
                        None,
                        None,
                    )?;
                    Err(anyhow!("{original_error}; rollback failed: {rollback_error}"))
                }
            }
        }
    }
}

pub fn inspect_migration_archive(
    app_dir: &Path,
    archive_path: &Path,
) -> Result<MigrationArchiveManifest> {
    let source = materialize_external_import_source(app_dir, archive_path)?;
    let result = (|| -> Result<MigrationArchiveManifest> {
        parse_migration_archive_manifest_json(&fs::read_to_string(
            source.root_dir.join("export-manifest.json"),
        )?)
    })();
    cleanup_materialized_external_import_source(&source);
    result
}
