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
const VAULT_ROLLBACK_SNAPSHOT_AAD: &[u8] = b"vault.rollback_snapshot.v1";

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
                        "citations_json": message.citations_json,
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
            let archive_body = migration_archive_rewrite_embedded_attachment_refs(
                &message.content,
                &attachments,
            );
            let markdown = migration_archive_markdown_doc(&item, &archive_body, &attachment_paths, &[]);
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
                    "manual_importance_nudge_score": todo.manual_importance_nudge_score.unwrap_or(0),
                    "manual_urgency_nudge_score": todo.manual_urgency_nudge_score.unwrap_or(0),
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
            let archive_body = migration_archive_rewrite_embedded_attachment_refs(
                &activity_content,
                &attachments,
            );
            let markdown = migration_archive_markdown_doc(
                &item,
                &archive_body,
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

fn vault_rollback_copy_dir_recursive(src: &Path, dst: &Path) -> Result<()> {
    if !src.exists() {
        return Ok(());
    }
    fs::create_dir_all(dst)?;
    for entry in fs::read_dir(src)? {
        let entry = entry?;
        let file_type = entry.file_type()?;
        let dst_path = dst.join(entry.file_name());
        if file_type.is_dir() {
            vault_rollback_copy_dir_recursive(&entry.path(), &dst_path)?;
        } else if file_type.is_file() {
            if let Some(parent) = dst_path.parent() {
                fs::create_dir_all(parent)?;
            }
            fs::copy(entry.path(), dst_path)?;
        }
    }
    Ok(())
}

fn vault_rollback_write_encrypted_snapshot(
    conn: &Connection,
    key: &[u8; 32],
    app_dir: &Path,
    snapshot_path: &Path,
) -> Result<()> {
    let stage_dir = migration_archive_staging_dir(app_dir).join(uuid::Uuid::new_v4().to_string());
    fs::create_dir_all(&stage_dir)?;

    let snapshot_result = (|| -> Result<()> {
        let db_snapshot_path = stage_dir.join("secondloop.sqlite3");
        let db_snapshot_path_string = db_snapshot_path.to_string_lossy().into_owned();
        conn.execute("VACUUM main INTO ?1", params![db_snapshot_path_string])?;
        vault_rollback_copy_dir_recursive(
            &app_dir.join("attachments"),
            &stage_dir.join("attachments"),
        )?;
        let zip_bytes = migration_archive_write_zip_bytes(&stage_dir)?;
        let encrypted = encrypt_bytes(key, &zip_bytes, VAULT_ROLLBACK_SNAPSHOT_AAD)?;
        if let Some(parent) = snapshot_path.parent() {
            fs::create_dir_all(parent)?;
        }
        fs::write(snapshot_path, encrypted)?;
        Ok(())
    })();

    let _ = fs::remove_dir_all(&stage_dir);
    snapshot_result
}

fn vault_rollback_extract_zip_bytes(app_dir: &Path, zip_bytes: &[u8]) -> Result<PathBuf> {
    let stage_dir = migration_archive_staging_dir(app_dir).join(uuid::Uuid::new_v4().to_string());
    fs::create_dir_all(&stage_dir)?;

    let extract_result = (|| -> Result<()> {
        let mut archive = zip::ZipArchive::new(std::io::Cursor::new(zip_bytes))?;
        for index in 0..archive.len() {
            let mut entry = archive.by_index(index)?;
            let Some(name) = entry.enclosed_name().map(|value| value.to_path_buf()) else {
                continue;
            };
            let out_path = stage_dir.join(name);
            if entry.is_dir() {
                fs::create_dir_all(&out_path)?;
                continue;
            }
            if let Some(parent) = out_path.parent() {
                fs::create_dir_all(parent)?;
            }
            let mut out = fs::File::create(&out_path)?;
            std::io::copy(&mut entry, &mut out)?;
        }
        Ok(())
    })();

    if let Err(err) = extract_result {
        let _ = fs::remove_dir_all(&stage_dir);
        return Err(err);
    }

    Ok(stage_dir)
}

fn vault_rollback_restore_from_encrypted_snapshot(
    app_dir: &Path,
    key: &[u8; 32],
    snapshot_path: &Path,
) -> Result<()> {
    let encrypted = fs::read(snapshot_path)?;
    let zip_bytes = decrypt_bytes(key, &encrypted, VAULT_ROLLBACK_SNAPSHOT_AAD)?;
    let stage_dir = vault_rollback_extract_zip_bytes(app_dir, &zip_bytes)?;

    let restore_result = (|| -> Result<()> {
        fs::create_dir_all(app_dir)?;
        best_effort_remove_file(&app_dir.join("secondloop.sqlite3"))?;
        best_effort_remove_file(&app_dir.join("secondloop.sqlite3-wal"))?;
        best_effort_remove_file(&app_dir.join("secondloop.sqlite3-shm"))?;
        fs::copy(
            stage_dir.join("secondloop.sqlite3"),
            app_dir.join("secondloop.sqlite3"),
        )?;

        let attachments_dir = app_dir.join("attachments");
        best_effort_remove_dir_all(&attachments_dir)?;
        let staged_attachments = stage_dir.join("attachments");
        if staged_attachments.exists() {
            vault_rollback_copy_dir_recursive(&staged_attachments, &attachments_dir)?;
        } else {
            fs::create_dir_all(&attachments_dir)?;
        }
        Ok(())
    })();

    let _ = fs::remove_dir_all(&stage_dir);
    if restore_result.is_ok() {
        migration_archive_remove_snapshot(Some(snapshot_path));
    }
    restore_result
}

pub fn migration_archive_create_rollback_snapshot(
    app_dir: &Path,
    key: &[u8; 32],
) -> Result<Option<PathBuf>> {
    let conn = open(app_dir)?;
    let snapshot_dir = migration_archive_root_dir(app_dir).join("rollback");
    fs::create_dir_all(&snapshot_dir)?;
    let snapshot_path = snapshot_dir.join(format!("{}.bin", uuid::Uuid::new_v4()));
    vault_rollback_write_encrypted_snapshot(&conn, key, app_dir, &snapshot_path)?;
    Ok(Some(snapshot_path))
}

pub fn migration_archive_restore_rollback_snapshot(
    app_dir: &Path,
    key: &[u8; 32],
    snapshot_path: &Path,
) -> Result<()> {
    vault_rollback_restore_from_encrypted_snapshot(app_dir, key, snapshot_path)
}

pub fn migration_archive_remove_rollback_snapshot(snapshot_path: &Path) -> Result<()> {
    best_effort_remove_file(snapshot_path)
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

fn migration_archive_rebuild_derived_indexes(_conn: &Connection, _key: &[u8; 32]) -> Result<()> {
    Ok(())
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
