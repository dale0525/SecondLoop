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
    let citations_json = extra["citations_json"].as_str();
    let device_id = get_or_create_device_id(conn)?;
    let seq = next_device_seq(conn, &device_id)?;
    let content_blob = encrypt_bytes(key, content.as_bytes(), b"message.content")?;
    conn.execute(
        r#"INSERT OR REPLACE INTO messages(
             id, conversation_id, role, content, created_at, updated_at,
             updated_by_device_id, updated_by_seq, is_deleted, needs_embedding, is_memory,
             citations_json
           ) VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, 0, ?9, ?10, ?11)"#,
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
            citations_json,
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
             created_at_ms, updated_at_ms, review_stage, next_review_at_ms, last_review_at_ms, manual_importance_nudge_score, manual_urgency_nudge_score, needs_embedding
           ) VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?11, ?12, 1)"#,
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
            extra["manual_importance_nudge_score"].as_i64().unwrap_or(0),
            extra["manual_urgency_nudge_score"].as_i64().unwrap_or(0),
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
        migration_archive_clear_active_rollback_marker_for_snapshot(path);
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
        migration_archive_mark_active_rollback_snapshot(&path)?;
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
