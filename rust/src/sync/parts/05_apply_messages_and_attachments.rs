fn apply_message_insert(
    conn: &Connection,
    db_key: &[u8; 32],
    op: &serde_json::Value,
) -> Result<()> {
    let device_id = op["device_id"]
        .as_str()
        .ok_or_else(|| anyhow!("message op missing device_id"))?;
    let seq = op["seq"]
        .as_i64()
        .ok_or_else(|| anyhow!("message op missing seq"))?;
    let payload = &op["payload"];
    let message_id = payload["message_id"]
        .as_str()
        .ok_or_else(|| anyhow!("message op missing message_id"))?;
    let conversation_id = payload["conversation_id"]
        .as_str()
        .ok_or_else(|| anyhow!("message op missing conversation_id"))?;
    let role = payload["role"]
        .as_str()
        .ok_or_else(|| anyhow!("message op missing role"))?;
    let content = payload["content"]
        .as_str()
        .ok_or_else(|| anyhow!("message op missing content"))?;
    let created_at_ms = payload["created_at_ms"]
        .as_i64()
        .ok_or_else(|| anyhow!("message op missing created_at_ms"))?;
    let is_memory = payload["is_memory"]
        .as_bool()
        .unwrap_or_else(|| role != "assistant");

    let content_blob = encrypt_bytes(db_key, content.as_bytes(), b"message.content")?;
    let insert_result = conn.execute(
        r#"INSERT INTO messages
           (id, conversation_id, role, content, created_at, updated_at, updated_by_device_id, updated_by_seq, is_deleted, needs_embedding, is_memory)
           VALUES (?1, ?2, ?3, ?4, ?5, ?5, ?6, ?7, 0, ?8, ?9)
           ON CONFLICT(id) DO NOTHING"#,
        params![
            message_id,
            conversation_id,
            role,
            content_blob.as_slice(),
            created_at_ms,
            device_id,
            seq,
            if is_memory { 1 } else { 0 },
            if is_memory { 1 } else { 0 }
        ],
    );
    let inserted_message = match insert_result {
        Ok(changed) => changed > 0,
        Err(e) if is_foreign_key_constraint(&e) => {
            ensure_placeholder_conversation_row(conn, db_key, conversation_id, created_at_ms)?;
            conn.execute(
                r#"INSERT INTO messages
                   (id, conversation_id, role, content, created_at, updated_at, updated_by_device_id, updated_by_seq, is_deleted, needs_embedding, is_memory)
                   VALUES (?1, ?2, ?3, ?4, ?5, ?5, ?6, ?7, 0, ?8, ?9)
                   ON CONFLICT(id) DO NOTHING"#,
                params![
                    message_id,
                    conversation_id,
                    role,
                    content_blob.as_slice(),
                    created_at_ms,
                    device_id,
                    seq,
                    if is_memory { 1 } else { 0 },
                    if is_memory { 1 } else { 0 }
                ],
            )? > 0
        }
        Err(e) => return Err(e.into()),
    };

    // Heuristic for legacy Ask AI flows: when an assistant message is marked non-memory, treat the
    // immediately preceding user message (same device/seq ordering) as non-memory too.
    if role == "assistant" && !is_memory {
        if let Some(prev_seq) = seq.checked_sub(1) {
            let _ = conn.execute(
                r#"UPDATE messages
                   SET is_memory = 0,
                       needs_embedding = 0
                   WHERE conversation_id = ?1
                     AND role = 'user'
                     AND updated_by_device_id = ?2
                     AND updated_by_seq = ?3
                     AND COALESCE(is_memory, 1) != 0"#,
                params![conversation_id, device_id, prev_seq],
            )?;
        }
    }

    conn.execute(
        r#"UPDATE conversations
           SET updated_at = CASE WHEN updated_at < ?2 THEN ?2 ELSE updated_at END
           WHERE id = ?1"#,
        params![conversation_id, created_at_ms],
    )?;

    if role == "user" && inserted_message {
        let _ = crate::db::run_message_tag_autofill_for_message(
            conn, db_key, message_id, "sync_message_insert", created_at_ms,
        );
    }

    Ok(())
}

fn message_version_newer(
    incoming_updated_at: i64,
    incoming_device_id: &str,
    incoming_seq: i64,
    existing_updated_at: i64,
    existing_device_id: &str,
    existing_seq: i64,
) -> bool {
    if incoming_updated_at != existing_updated_at {
        return incoming_updated_at > existing_updated_at;
    }
    if incoming_device_id != existing_device_id {
        return incoming_device_id > existing_device_id;
    }
    incoming_seq > existing_seq
}

fn apply_message_set_v2(
    conn: &Connection,
    db_key: &[u8; 32],
    op: &serde_json::Value,
) -> Result<()> {
    let device_id = op["device_id"]
        .as_str()
        .ok_or_else(|| anyhow!("message.set.v2 missing device_id"))?;
    let seq = op["seq"]
        .as_i64()
        .ok_or_else(|| anyhow!("message.set.v2 missing seq"))?;
    let payload = &op["payload"];

    let message_id = payload["message_id"]
        .as_str()
        .ok_or_else(|| anyhow!("message.set.v2 missing message_id"))?;
    let role = payload["role"]
        .as_str()
        .ok_or_else(|| anyhow!("message.set.v2 missing role"))?;
    let content = payload["content"]
        .as_str()
        .ok_or_else(|| anyhow!("message.set.v2 missing content"))?;
    let created_at_ms = payload["created_at_ms"]
        .as_i64()
        .ok_or_else(|| anyhow!("message.set.v2 missing created_at_ms"))?;
    let updated_at_ms = payload["updated_at_ms"]
        .as_i64()
        .ok_or_else(|| anyhow!("message.set.v2 missing updated_at_ms"))?;
    let is_deleted = payload["is_deleted"]
        .as_bool()
        .ok_or_else(|| anyhow!("message.set.v2 missing is_deleted"))?;
    let incoming_is_memory = payload["is_memory"].as_bool();

    let payload_conversation_id = payload["conversation_id"].as_str();
    let existing_conversation_id: Option<String> = conn
        .query_row(
            r#"SELECT conversation_id FROM messages WHERE id = ?1"#,
            params![message_id],
            |row| row.get(0),
        )
        .optional()?;
    let conversation_id = match (payload_conversation_id, existing_conversation_id) {
        (Some(id), _) => id.to_string(),
        (None, Some(id)) => id,
        (None, None) => {
            return Err(anyhow!(
                "message.set.v2 missing conversation_id for unknown message: {message_id}"
            ))
        }
    };

    let existing: Option<(i64, String, i64, i64)> = conn
        .query_row(
            r#"SELECT updated_at, updated_by_device_id, updated_by_seq, COALESCE(is_memory, 1)
               FROM messages
               WHERE id = ?1"#,
            params![message_id],
            |row| Ok((row.get(0)?, row.get(1)?, row.get(2)?, row.get(3)?)),
        )
        .optional()?;
    let mut inserted_message = false;

    if let Some((existing_updated_at, existing_device_id, existing_seq, existing_is_memory_i64)) =
        existing
    {
        if !message_version_newer(
            updated_at_ms,
            device_id,
            seq,
            existing_updated_at,
            &existing_device_id,
            existing_seq,
        ) {
            return Ok(());
        }

        let is_memory = incoming_is_memory.unwrap_or(existing_is_memory_i64 != 0);
        let content_blob = encrypt_bytes(db_key, content.as_bytes(), b"message.content")?;
        conn.execute(
            r#"UPDATE messages
               SET role = ?2,
                   content = ?3,
                   updated_at = ?4,
                   updated_by_device_id = ?5,
                   updated_by_seq = ?6,
                   is_deleted = ?7,
                   is_memory = ?8,
                   needs_embedding = CASE WHEN ?7 = 0 AND ?8 = 1 THEN 1 ELSE 0 END
               WHERE id = ?1"#,
            params![
                message_id,
                role,
                content_blob,
                updated_at_ms,
                device_id,
                seq,
                if is_deleted { 1 } else { 0 },
                if is_memory { 1 } else { 0 }
            ],
        )?;
    } else {
        let content_blob = encrypt_bytes(db_key, content.as_bytes(), b"message.content")?;
        let is_memory = incoming_is_memory.unwrap_or_else(|| role != "assistant");
        let needs_embedding = !is_deleted && is_memory;
        let insert_result = conn.execute(
            r#"INSERT INTO messages
               (id, conversation_id, role, content, created_at, updated_at, updated_by_device_id, updated_by_seq, is_deleted, needs_embedding, is_memory)
               VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?11)"#,
            params![
                message_id,
                conversation_id.as_str(),
                role,
                content_blob.as_slice(),
                created_at_ms,
                updated_at_ms,
                device_id,
                seq,
                if is_deleted { 1 } else { 0 },
                if needs_embedding { 1 } else { 0 },
                if is_memory { 1 } else { 0 }
            ],
        );
        match insert_result {
            Ok(_) => inserted_message = true,
            Err(e) if is_foreign_key_constraint(&e) => {
                ensure_placeholder_conversation_row(
                    conn,
                    db_key,
                    conversation_id.as_str(),
                    created_at_ms,
                )?;
                conn.execute(
                    r#"INSERT INTO messages
                       (id, conversation_id, role, content, created_at, updated_at, updated_by_device_id, updated_by_seq, is_deleted, needs_embedding, is_memory)
                       VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?11)"#,
                    params![
                        message_id,
                        conversation_id.as_str(),
                        role,
                        content_blob.as_slice(),
                        created_at_ms,
                        updated_at_ms,
                        device_id,
                        seq,
                        if is_deleted { 1 } else { 0 },
                        if needs_embedding { 1 } else { 0 },
                        if is_memory { 1 } else { 0 }
                    ],
                )?;
                inserted_message = true;
            }
            Err(e) => return Err(e.into()),
        }
    }

    conn.execute(
        r#"UPDATE conversations
           SET updated_at = CASE WHEN updated_at < ?2 THEN ?2 ELSE updated_at END
           WHERE id = ?1"#,
        params![conversation_id.as_str(), updated_at_ms],
    )?;

    if role == "user" && inserted_message {
        let _ = crate::db::run_message_tag_autofill_for_message(
            conn, db_key, message_id, "sync_message_set_insert", updated_at_ms,
        );
    }

    Ok(())
}

fn sync_system_key_from_tag_id(tag_id: &str) -> Option<&str> {
    let key = tag_id.strip_prefix("system.tag.")?;
    if is_sync_system_key(key) {
        Some(key)
    } else {
        None
    }
}

fn ensure_sync_system_tag_row(
    conn: &Connection,
    db_key: &[u8; 32],
    tag_id: &str,
    system_key: &str,
    ts_ms: i64,
) -> Result<()> {
    let aad = format!("tag.name:{tag_id}");
    let name_blob = encrypt_bytes(db_key, system_key.as_bytes(), aad.as_bytes())?;
    conn.execute(
        r#"INSERT OR IGNORE INTO tags(id, name, system_key, is_system, color, created_at_ms, updated_at_ms)
           VALUES (?1, ?2, ?3, 1, NULL, ?4, ?5)"#,
        params![tag_id, name_blob, system_key, ts_ms, ts_ms],
    )?;
    Ok(())
}

fn apply_message_tag_set(
    conn: &Connection,
    db_key: &[u8; 32],
    payload: &serde_json::Value,
) -> Result<()> {
    let message_id = payload["message_id"]
        .as_str()
        .ok_or_else(|| anyhow!("message.tag_set.v1 missing message_id"))?;
    let created_at_ms = payload["created_at_ms"]
        .as_i64()
        .ok_or_else(|| anyhow!("message.tag_set.v1 missing created_at_ms"))?;

    let message_exists: Option<i64> = conn
        .query_row(
            r#"SELECT 1 FROM messages WHERE id = ?1"#,
            params![message_id],
            |row| row.get(0),
        )
        .optional()?;
    if message_exists.is_none() {
        return Ok(());
    }

    let tag_values = payload["tag_ids"]
        .as_array()
        .ok_or_else(|| anyhow!("message.tag_set.v1 missing tag_ids"))?;

    let mut desired_tag_ids = BTreeSet::<String>::new();
    for value in tag_values {
        let Some(raw_tag_id) = value.as_str() else {
            continue;
        };
        let tag_id = raw_tag_id.trim();
        if tag_id.is_empty() {
            continue;
        }

        let tag_exists: Option<i64> = conn
            .query_row(
                r#"SELECT 1 FROM tags WHERE id = ?1"#,
                params![tag_id],
                |row| row.get(0),
            )
            .optional()?;

        if tag_exists.is_none() {
            if let Some(system_key) = sync_system_key_from_tag_id(tag_id) {
                ensure_sync_system_tag_row(conn, db_key, tag_id, system_key, created_at_ms)?;
            }
        }

        let tag_exists_after: Option<i64> = conn
            .query_row(
                r#"SELECT 1 FROM tags WHERE id = ?1"#,
                params![tag_id],
                |row| row.get(0),
            )
            .optional()?;
        if tag_exists_after.is_some() {
            desired_tag_ids.insert(tag_id.to_string());
        }
    }

    let desired_tag_ids: Vec<String> = desired_tag_ids.into_iter().collect();

    let mut stmt = conn.prepare(
        r#"SELECT tag_id
           FROM message_tags
           WHERE message_id = ?1
           ORDER BY tag_id ASC"#,
    )?;
    let mut rows = stmt.query(params![message_id])?;
    let mut existing_tag_ids = Vec::<String>::new();
    while let Some(row) = rows.next()? {
        existing_tag_ids.push(row.get(0)?);
    }

    if existing_tag_ids == desired_tag_ids {
        return Ok(());
    }

    conn.execute(
        r#"DELETE FROM message_tags WHERE message_id = ?1"#,
        params![message_id],
    )?;
    for tag_id in &desired_tag_ids {
        conn.execute(
            r#"INSERT INTO message_tags(message_id, tag_id, created_at_ms)
               VALUES (?1, ?2, ?3)"#,
            params![message_id, tag_id, created_at_ms],
        )?;
    }

    Ok(())
}

fn apply_attachment_upsert(
    conn: &Connection,
    _db_key: &[u8; 32],
    payload: &serde_json::Value,
) -> Result<()> {
    let sha256 = payload["sha256"]
        .as_str()
        .ok_or_else(|| anyhow!("attachment op missing sha256"))?;
    let mime_type = payload["mime_type"]
        .as_str()
        .ok_or_else(|| anyhow!("attachment op missing mime_type"))?;
    let byte_len = payload["byte_len"]
        .as_i64()
        .ok_or_else(|| anyhow!("attachment op missing byte_len"))?;
    let created_at_ms = payload["created_at_ms"]
        .as_i64()
        .ok_or_else(|| anyhow!("attachment op missing created_at_ms"))?;

    let existing_delete: Option<(i64, String, i64)> = conn
        .query_row(
            r#"SELECT deleted_at_ms, deleted_by_device_id, deleted_by_seq
               FROM attachment_deletions
               WHERE sha256 = ?1"#,
            params![sha256],
            |row| Ok((row.get(0)?, row.get(1)?, row.get(2)?)),
        )
        .optional()?;

    if let Some((deleted_at_ms, _, _)) = existing_delete {
        // Ignore upserts that are older than (or equal to) the delete tombstone.
        if created_at_ms <= deleted_at_ms {
            return Ok(());
        }
        // Allow resurrection when the new attachment is created after the deletion.
        conn.execute(
            r#"DELETE FROM attachment_deletions WHERE sha256 = ?1"#,
            params![sha256],
        )?;
    }

    let path = format!("attachments/{sha256}.bin");

    conn.execute(
        r#"
INSERT INTO attachments(sha256, mime_type, path, byte_len, created_at)
VALUES (?1, ?2, ?3, ?4, ?5)
ON CONFLICT(sha256) DO UPDATE SET
  mime_type = excluded.mime_type,
  path = excluded.path,
  byte_len = excluded.byte_len,
  created_at = min(attachments.created_at, excluded.created_at)
"#,
        params![sha256, mime_type, path, byte_len, created_at_ms],
    )?;

    Ok(())
}

fn apply_attachment_delete(
    conn: &Connection,
    _db_key: &[u8; 32],
    op: &serde_json::Value,
) -> Result<()> {
    let device_id = op["device_id"]
        .as_str()
        .ok_or_else(|| anyhow!("attachment.delete.v1 missing device_id"))?;
    let seq = op["seq"]
        .as_i64()
        .ok_or_else(|| anyhow!("attachment.delete.v1 missing seq"))?;
    let payload = &op["payload"];

    let sha256 = payload["sha256"]
        .as_str()
        .ok_or_else(|| anyhow!("attachment.delete.v1 missing sha256"))?;
    let deleted_at_ms = payload["deleted_at_ms"]
        .as_i64()
        .ok_or_else(|| anyhow!("attachment.delete.v1 missing deleted_at_ms"))?;

    let existing_delete: Option<(i64, String, i64)> = conn
        .query_row(
            r#"SELECT deleted_at_ms, deleted_by_device_id, deleted_by_seq
               FROM attachment_deletions
               WHERE sha256 = ?1"#,
            params![sha256],
            |row| Ok((row.get(0)?, row.get(1)?, row.get(2)?)),
        )
        .optional()?;

    let should_update_tombstone = match existing_delete {
        None => true,
        Some((existing_at, existing_device, existing_seq)) => message_version_newer(
            deleted_at_ms,
            device_id,
            seq,
            existing_at,
            &existing_device,
            existing_seq,
        ),
    };

    if should_update_tombstone {
        conn.execute(
            r#"
INSERT INTO attachment_deletions(sha256, deleted_at_ms, deleted_by_device_id, deleted_by_seq)
VALUES (?1, ?2, ?3, ?4)
ON CONFLICT(sha256) DO UPDATE SET
  deleted_at_ms = excluded.deleted_at_ms,
  deleted_by_device_id = excluded.deleted_by_device_id,
  deleted_by_seq = excluded.deleted_by_seq
"#,
            params![sha256, deleted_at_ms, device_id, seq],
        )?;
    }

    // Best-effort: delete local cached files.
    if let Ok(app_dir) = app_dir_from_conn(conn) {
        let _ = fs::remove_file(app_dir.join(format!("attachments/{sha256}.bin")));
        let _ = fs::remove_dir_all(app_dir.join(format!("attachments/variants/{sha256}")));
    }

    // Best-effort: delete any messages referencing this attachment.
    let mut stmt = conn.prepare(
        r#"SELECT message_id
           FROM message_attachments
           WHERE attachment_sha256 = ?1"#,
    )?;
    let mut rows = stmt.query(params![sha256])?;
    let mut message_ids: Vec<String> = Vec::new();
    while let Some(row) = rows.next()? {
        let message_id: String = row.get(0)?;
        message_ids.push(message_id);
    }

    for message_id in message_ids {
        let existing: Option<(i64, String, i64)> = conn
            .query_row(
                r#"SELECT updated_at, updated_by_device_id, updated_by_seq
                   FROM messages
                   WHERE id = ?1"#,
                params![message_id.as_str()],
                |row| Ok((row.get(0)?, row.get(1)?, row.get(2)?)),
            )
            .optional()?;
        let Some((existing_updated_at, existing_device_id, existing_seq)) = existing else {
            continue;
        };

        if !message_version_newer(
            deleted_at_ms,
            device_id,
            seq,
            existing_updated_at,
            &existing_device_id,
            existing_seq,
        ) {
            continue;
        }

        let _ = conn.execute(
            r#"UPDATE messages
               SET updated_at = ?2,
                   updated_by_device_id = ?3,
                   updated_by_seq = ?4,
                   is_deleted = 1,
                   needs_embedding = 0
               WHERE id = ?1"#,
            params![message_id, deleted_at_ms, device_id, seq],
        )?;
    }

    // Remove attachment metadata and any orphaned links (in case they were inserted with
    // foreign_keys temporarily disabled).
    let _ = conn.execute(
        r#"DELETE FROM message_attachments WHERE attachment_sha256 = ?1"#,
        params![sha256],
    )?;
    let _ = conn.execute(
        r#"DELETE FROM todo_activity_attachments WHERE attachment_sha256 = ?1"#,
        params![sha256],
    )?;
    let _ = conn.execute(
        r#"DELETE FROM attachment_variants WHERE attachment_sha256 = ?1"#,
        params![sha256],
    )?;
    let _ = conn.execute(
        r#"DELETE FROM attachment_exif WHERE attachment_sha256 = ?1"#,
        params![sha256],
    )?;
    let _ = conn.execute(
        r#"DELETE FROM attachment_metadata WHERE attachment_sha256 = ?1"#,
        params![sha256],
    )?;
    let _ = conn.execute(
        r#"DELETE FROM attachment_places WHERE attachment_sha256 = ?1"#,
        params![sha256],
    )?;
    let _ = conn.execute(
        r#"DELETE FROM attachment_annotations WHERE attachment_sha256 = ?1"#,
        params![sha256],
    )?;
    let _ = conn.execute(
        r#"DELETE FROM cloud_media_backup WHERE attachment_sha256 = ?1"#,
        params![sha256],
    )?;

    conn.execute(
        r#"DELETE FROM attachments WHERE sha256 = ?1"#,
        params![sha256],
    )?;

    Ok(())
}

fn apply_message_attachment_link(
    conn: &Connection,
    _db_key: &[u8; 32],
    payload: &serde_json::Value,
) -> Result<()> {
    let message_id = payload["message_id"]
        .as_str()
        .ok_or_else(|| anyhow!("message attachment op missing message_id"))?;
    let attachment_sha256 = payload["attachment_sha256"]
        .as_str()
        .ok_or_else(|| anyhow!("message attachment op missing attachment_sha256"))?;
    let created_at_ms = payload["created_at_ms"]
        .as_i64()
        .ok_or_else(|| anyhow!("message attachment op missing created_at_ms"))?;

    let existing: Option<i64> = conn
        .query_row(
            r#"SELECT 1
               FROM message_attachments
               WHERE message_id = ?1 AND attachment_sha256 = ?2"#,
            params![message_id, attachment_sha256],
            |row| row.get(0),
        )
        .optional()?;
    if existing.is_some() {
        return Ok(());
    }

    let message_exists: Option<i64> = conn
        .query_row(
            r#"SELECT 1 FROM messages WHERE id = ?1"#,
            params![message_id],
            |row| row.get(0),
        )
        .optional()?;
    let attachment_exists: Option<i64> = conn
        .query_row(
            r#"SELECT 1 FROM attachments WHERE sha256 = ?1"#,
            params![attachment_sha256],
            |row| row.get(0),
        )
        .optional()?;

    if message_exists.is_none() || attachment_exists.is_none() {
        // Avoid hard sync failures due to cross-device ordering. Accept orphan links temporarily;
        // they'll resolve once the message/attachment arrives.
        conn.execute_batch("PRAGMA foreign_keys = OFF;")?;
    }

    let insert_result = conn.execute(
        r#"INSERT OR IGNORE INTO message_attachments(message_id, attachment_sha256, created_at)
           VALUES (?1, ?2, ?3)"#,
        params![message_id, attachment_sha256, created_at_ms],
    );

    if message_exists.is_none() || attachment_exists.is_none() {
        let _ = conn.execute_batch("PRAGMA foreign_keys = ON;");
    }

    insert_result?;
    Ok(())
}

fn apply_attachment_exif_upsert(
    conn: &Connection,
    db_key: &[u8; 32],
    payload: &serde_json::Value,
) -> Result<()> {
    let attachment_sha256 = payload["attachment_sha256"]
        .as_str()
        .ok_or_else(|| anyhow!("attachment exif op missing attachment_sha256"))?;
    let created_at_ms = payload["created_at_ms"].as_i64().unwrap_or(0);
    let updated_at_ms = payload["updated_at_ms"]
        .as_i64()
        .ok_or_else(|| anyhow!("attachment exif op missing updated_at_ms"))?;

    let captured_at_ms = payload.get("captured_at_ms").and_then(|v| v.as_i64());
    let latitude = payload.get("latitude").and_then(|v| v.as_f64());
    let longitude = payload.get("longitude").and_then(|v| v.as_f64());

    let existing_updated_at_ms: Option<i64> = conn
        .query_row(
            r#"SELECT updated_at_ms FROM attachment_exif WHERE attachment_sha256 = ?1"#,
            params![attachment_sha256],
            |row| row.get(0),
        )
        .optional()?;
    if existing_updated_at_ms.unwrap_or(0) >= updated_at_ms {
        return Ok(());
    }

    let meta = crate::db::AttachmentExifMetadata {
        captured_at_ms,
        latitude,
        longitude,
    };
    let json = serde_json::to_vec(&meta)?;
    let aad = format!("attachment.exif:{attachment_sha256}");
    let blob = encrypt_bytes(db_key, &json, aad.as_bytes())?;

    let attachment_exists: Option<i64> = conn
        .query_row(
            r#"SELECT 1 FROM attachments WHERE sha256 = ?1"#,
            params![attachment_sha256],
            |row| row.get(0),
        )
        .optional()?;
    if attachment_exists.is_none() {
        // Avoid hard sync failures due to cross-device ordering. We'll accept orphan EXIF rows
        // temporarily; they'll resolve once the attachment arrives.
        conn.execute_batch("PRAGMA foreign_keys = OFF;")?;
    }

    let insert_result = conn.execute(
        r#"
INSERT INTO attachment_exif(attachment_sha256, metadata, created_at_ms, updated_at_ms)
VALUES (?1, ?2, ?3, ?4)
ON CONFLICT(attachment_sha256) DO UPDATE SET
  metadata = excluded.metadata,
  created_at_ms = min(attachment_exif.created_at_ms, excluded.created_at_ms),
  updated_at_ms = max(attachment_exif.updated_at_ms, excluded.updated_at_ms)
"#,
        params![attachment_sha256, blob, created_at_ms, updated_at_ms],
    );

    if attachment_exists.is_none() {
        let _ = conn.execute_batch("PRAGMA foreign_keys = ON;");
    }

    insert_result?;
    Ok(())
}

fn apply_attachment_place_upsert(
    conn: &Connection,
    db_key: &[u8; 32],
    payload: &serde_json::Value,
) -> Result<()> {
    let attachment_sha256 = payload["attachment_sha256"]
        .as_str()
        .ok_or_else(|| anyhow!("attachment place op missing attachment_sha256"))?;
    let lang = payload["lang"]
        .as_str()
        .ok_or_else(|| anyhow!("attachment place op missing lang"))?;
    let created_at_ms = payload
        .get("created_at_ms")
        .and_then(|v| v.as_i64())
        .unwrap_or(0);
    let updated_at_ms = payload["updated_at_ms"]
        .as_i64()
        .ok_or_else(|| anyhow!("attachment place op missing updated_at_ms"))?;

    let place_payload = payload
        .get("payload")
        .ok_or_else(|| anyhow!("attachment place op missing payload"))?;

    let existing_updated_at_ms: Option<i64> = conn
        .query_row(
            r#"SELECT updated_at FROM attachment_places WHERE attachment_sha256 = ?1"#,
            params![attachment_sha256],
            |row| row.get(0),
        )
        .optional()?;
    if existing_updated_at_ms.unwrap_or(0) >= updated_at_ms {
        return Ok(());
    }

    let json = serde_json::to_vec(place_payload)?;
    let aad = format!("attachment.place:{attachment_sha256}:{lang}");
    let blob = encrypt_bytes(db_key, &json, aad.as_bytes())?;

    let attachment_exists: Option<i64> = conn
        .query_row(
            r#"SELECT 1 FROM attachments WHERE sha256 = ?1"#,
            params![attachment_sha256],
            |row| row.get(0),
        )
        .optional()?;
    if attachment_exists.is_none() {
        // Avoid hard sync failures due to cross-device ordering. We'll accept orphan place rows
        // temporarily; they'll resolve once the attachment arrives.
        conn.execute_batch("PRAGMA foreign_keys = OFF;")?;
    }

    let insert_result = conn.execute(
        r#"
INSERT INTO attachment_places(
  attachment_sha256,
  status,
  lang,
  payload,
  attempts,
  next_retry_at,
  last_error,
  created_at,
  updated_at
)
VALUES (?1, 'ok', ?2, ?3, 0, NULL, NULL, ?4, ?5)
ON CONFLICT(attachment_sha256) DO UPDATE SET
  status = 'ok',
  lang = excluded.lang,
  payload = excluded.payload,
  attempts = 0,
  next_retry_at = NULL,
  last_error = NULL,
  created_at = min(attachment_places.created_at, excluded.created_at),
  updated_at = max(attachment_places.updated_at, excluded.updated_at)
"#,
        params![attachment_sha256, lang, blob, created_at_ms, updated_at_ms],
    );

    if attachment_exists.is_none() {
        let _ = conn.execute_batch("PRAGMA foreign_keys = ON;");
    }

    insert_result?;

    conn.execute(
        r#"
UPDATE messages
SET needs_embedding = 1
WHERE id IN (
  SELECT message_id
  FROM message_attachments
  WHERE attachment_sha256 = ?1
)
  AND COALESCE(is_deleted, 0) = 0
  AND COALESCE(is_memory, 1) = 1
"#,
        params![attachment_sha256],
    )?;


    Ok(())
}

fn apply_attachment_annotation_upsert(
    conn: &Connection,
    db_key: &[u8; 32],
    payload: &serde_json::Value,
) -> Result<()> {
    let attachment_sha256 = payload["attachment_sha256"]
        .as_str()
        .ok_or_else(|| anyhow!("attachment annotation op missing attachment_sha256"))?;
    let lang = payload["lang"]
        .as_str()
        .ok_or_else(|| anyhow!("attachment annotation op missing lang"))?;
    let model_name = payload
        .get("model_name")
        .and_then(|v| v.as_str())
        .unwrap_or("unknown")
        .trim();
    let model_name = if model_name.is_empty() {
        "unknown"
    } else {
        model_name
    };
    let created_at_ms = payload
        .get("created_at_ms")
        .and_then(|v| v.as_i64())
        .unwrap_or(0);
    let updated_at_ms = payload["updated_at_ms"]
        .as_i64()
        .ok_or_else(|| anyhow!("attachment annotation op missing updated_at_ms"))?;

    let annotation_payload = payload
        .get("payload")
        .ok_or_else(|| anyhow!("attachment annotation op missing payload"))?;

    let existing_updated_at_ms: Option<i64> = conn
        .query_row(
            r#"SELECT updated_at FROM attachment_annotations WHERE attachment_sha256 = ?1"#,
            params![attachment_sha256],
            |row| row.get(0),
        )
        .optional()?;
    if existing_updated_at_ms.unwrap_or(0) >= updated_at_ms {
        return Ok(());
    }

    let json = serde_json::to_vec(annotation_payload)?;
    let aad = format!("attachment.annotation:{attachment_sha256}:{lang}");
    let blob = encrypt_bytes(db_key, &json, aad.as_bytes())?;

    let attachment_exists: Option<i64> = conn
        .query_row(
            r#"SELECT 1 FROM attachments WHERE sha256 = ?1"#,
            params![attachment_sha256],
            |row| row.get(0),
        )
        .optional()?;
    if attachment_exists.is_none() {
        // Avoid hard sync failures due to cross-device ordering. We'll accept orphan annotation rows
        // temporarily; they'll resolve once the attachment arrives.
        conn.execute_batch("PRAGMA foreign_keys = OFF;")?;
    }

    let insert_result = conn.execute(
        r#"
INSERT INTO attachment_annotations(
  attachment_sha256,
  status,
  lang,
  model_name,
  payload,
  attempts,
  next_retry_at,
  last_error,
  created_at,
  updated_at
)
VALUES (?1, 'ok', ?2, ?3, ?4, 0, NULL, NULL, ?5, ?6)
ON CONFLICT(attachment_sha256) DO UPDATE SET
  status = 'ok',
  lang = excluded.lang,
  model_name = excluded.model_name,
  payload = excluded.payload,
  attempts = 0,
  next_retry_at = NULL,
  last_error = NULL,
  created_at = min(attachment_annotations.created_at, excluded.created_at),
  updated_at = max(attachment_annotations.updated_at, excluded.updated_at)
"#,
        params![
            attachment_sha256,
            lang,
            model_name,
            blob,
            created_at_ms,
            updated_at_ms
        ],
    );

    if attachment_exists.is_none() {
        let _ = conn.execute_batch("PRAGMA foreign_keys = ON;");
    }

    insert_result?;

    conn.execute(
        r#"
UPDATE messages
SET needs_embedding = 1
WHERE id IN (
  SELECT message_id
  FROM message_attachments
  WHERE attachment_sha256 = ?1
)
  AND COALESCE(is_deleted, 0) = 0
  AND COALESCE(is_memory, 1) = 1
"#,
        params![attachment_sha256],
    )?;

    if let Ok(queued_autofill) = crate::db::enqueue_message_tag_autofill_jobs_for_attachment_messages(
        conn, attachment_sha256, updated_at_ms,
    ) {
        if queued_autofill > 0 {
            let limit = i64::from(queued_autofill).clamp(1, 32);
            let _ = crate::db::process_pending_message_tag_autofill_jobs(conn, db_key, updated_at_ms, limit);
        }
    }

    Ok(())
}
