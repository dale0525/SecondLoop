pub fn insert_attachment(
    conn: &Connection,
    key: &[u8; 32],
    app_dir: &Path,
    bytes: &[u8],
    mime_type: &str,
) -> Result<Attachment> {
    backfill_attachments_oplog_if_needed(conn, key)?;

    let sha256 = sha256_hex(bytes);
    let rel_path = format!("attachments/{sha256}.bin");
    let full_path = app_dir.join(&rel_path);

    fs::create_dir_all(app_dir.join("attachments"))?;
    let aad = format!("attachment.bytes:{sha256}");
    let blob = encrypt_bytes(key, bytes, aad.as_bytes())?;
    fs::write(&full_path, blob)?;

    let now = now_ms();
    let inserted = conn.execute(
        r#"INSERT OR IGNORE INTO attachments(sha256, mime_type, path, byte_len, created_at)
           VALUES (?1, ?2, ?3, ?4, ?5)"#,
        params![sha256, mime_type, rel_path, bytes.len() as i64, now],
    )?;

    let (stored_mime_type, stored_path, stored_byte_len, stored_created_at_ms): (
        String,
        String,
        i64,
        i64,
    ) = conn.query_row(
        r#"SELECT mime_type, path, byte_len, created_at
           FROM attachments
           WHERE sha256 = ?1"#,
        params![sha256],
        |row| Ok((row.get(0)?, row.get(1)?, row.get(2)?, row.get(3)?)),
    )?;

    if inserted > 0 {
        let device_id = get_or_create_device_id(conn)?;
        let seq = next_device_seq(conn, &device_id)?;
        let op = serde_json::json!({
            "op_id": uuid::Uuid::new_v4().to_string(),
            "device_id": device_id,
            "seq": seq,
            "ts_ms": stored_created_at_ms,
            "type": "attachment.upsert.v1",
            "payload": {
                "sha256": sha256.as_str(),
                "mime_type": stored_mime_type.as_str(),
                "byte_len": stored_byte_len,
                "created_at_ms": stored_created_at_ms,
            }
        });
        insert_oplog(conn, key, &op)?;
    }

    Ok(Attachment {
        sha256,
        mime_type: stored_mime_type,
        path: stored_path,
        byte_len: stored_byte_len,
        created_at_ms: stored_created_at_ms,
    })
}

pub fn read_attachment_bytes(
    conn: &Connection,
    key: &[u8; 32],
    app_dir: &Path,
    sha256: &str,
) -> Result<Vec<u8>> {
    let stored_path: Option<String> = conn
        .query_row(
            r#"SELECT path FROM attachments WHERE sha256 = ?1"#,
            params![sha256],
            |row| row.get(0),
        )
        .optional()?;
    let stored_path = stored_path.ok_or_else(|| anyhow!("attachment not found"))?;

    let blob = fs::read(app_dir.join(stored_path))?;
    let aad = format!("attachment.bytes:{sha256}");
    decrypt_bytes(key, &blob, aad.as_bytes())
}

fn version_newer(
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

fn best_effort_remove_file(path: &Path) -> Result<()> {
    match fs::remove_file(path) {
        Ok(()) => Ok(()),
        Err(e) if e.kind() == std::io::ErrorKind::NotFound => Ok(()),
        Err(e) => Err(e.into()),
    }
}

fn best_effort_remove_dir_all(path: &Path) -> Result<()> {
    match fs::remove_dir_all(path) {
        Ok(()) => Ok(()),
        Err(e) if e.kind() == std::io::ErrorKind::NotFound => Ok(()),
        Err(e) => Err(e.into()),
    }
}

fn purge_attachment(conn: &Connection, key: &[u8; 32], app_dir: &Path, sha256: &str) -> Result<()> {
    let now = now_ms();
    let device_id = get_or_create_device_id(conn)?;
    let seq = next_device_seq(conn, &device_id)?;

    let op = serde_json::json!({
        "op_id": uuid::Uuid::new_v4().to_string(),
        "device_id": device_id,
        "seq": seq,
        "ts_ms": now,
        "type": "attachment.delete.v1",
        "payload": {
            "sha256": sha256,
            "deleted_at_ms": now,
        }
    });
    insert_oplog(conn, key, &op)?;

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
        Some((existing_at, existing_device, existing_seq)) => version_newer(
            now,
            &device_id,
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
            params![sha256, now, device_id, seq],
        )?;
    }

    best_effort_remove_file(&app_dir.join(format!("attachments/{sha256}.bin")))?;
    best_effort_remove_dir_all(&app_dir.join(format!("attachments/variants/{sha256}")))?;

    conn.execute(
        r#"DELETE FROM attachments WHERE sha256 = ?1"#,
        params![sha256],
    )?;

    Ok(())
}

pub fn purge_message_attachments(
    conn: &Connection,
    key: &[u8; 32],
    app_dir: &Path,
    message_id: &str,
) -> Result<u64> {
    let mut stmt = conn.prepare(
        r#"SELECT attachment_sha256
           FROM message_attachments
           WHERE message_id = ?1
           ORDER BY created_at ASC"#,
    )?;

    let mut rows = stmt.query(params![message_id])?;
    let mut attachment_sha256s: BTreeSet<String> = BTreeSet::new();
    while let Some(row) = rows.next()? {
        let sha: String = row.get(0)?;
        attachment_sha256s.insert(sha);
    }

    if attachment_sha256s.is_empty() {
        set_message_deleted(conn, key, message_id, true)?;
        return Ok(0);
    }

    let mut message_ids_to_delete: BTreeSet<String> = BTreeSet::new();
    for sha in &attachment_sha256s {
        let mut stmt = conn.prepare(
            r#"SELECT message_id
               FROM message_attachments
               WHERE attachment_sha256 = ?1"#,
        )?;
        let mut rows = stmt.query(params![sha])?;
        while let Some(row) = rows.next()? {
            let id: String = row.get(0)?;
            message_ids_to_delete.insert(id);
        }
    }

    // Delete all referencing messages (including the original message).
    for id in message_ids_to_delete {
        let _ = set_message_deleted(conn, key, &id, true);
    }

    for sha in &attachment_sha256s {
        purge_attachment(conn, key, app_dir, sha)?;
    }

    Ok(attachment_sha256s.len() as u64)
}

pub fn clear_local_attachment_cache(conn: &Connection, app_dir: &Path) -> Result<()> {
    best_effort_remove_dir_all(&app_dir.join("attachments"))?;
    let _ = conn.execute(r#"DELETE FROM attachment_variants"#, []);
    Ok(())
}

pub fn upsert_attachment_exif_metadata(
    conn: &Connection,
    key: &[u8; 32],
    attachment_sha256: &str,
    captured_at_ms: Option<i64>,
    latitude: Option<f64>,
    longitude: Option<f64>,
) -> Result<()> {
    backfill_attachments_oplog_if_needed(conn, key)?;
    if captured_at_ms.is_none() && latitude.is_none() && longitude.is_none() {
        return Ok(());
    }

    let now = now_ms();
    let metadata = AttachmentExifMetadata {
        captured_at_ms,
        latitude,
        longitude,
    };
    let json = serde_json::to_vec(&metadata)?;
    let aad = format!("attachment.exif:{attachment_sha256}");
    let blob = encrypt_bytes(key, &json, aad.as_bytes())?;

    conn.execute(
        r#"INSERT INTO attachment_exif(attachment_sha256, metadata, created_at_ms, updated_at_ms)
           VALUES (?1, ?2, ?3, ?4)
           ON CONFLICT(attachment_sha256) DO UPDATE SET
             metadata = excluded.metadata,
             updated_at_ms = excluded.updated_at_ms"#,
        params![attachment_sha256, blob, now, now],
    )?;

    let (stored_created_at_ms, stored_updated_at_ms): (i64, i64) = conn.query_row(
        r#"SELECT created_at_ms, updated_at_ms
           FROM attachment_exif
           WHERE attachment_sha256 = ?1"#,
        params![attachment_sha256],
        |row| Ok((row.get(0)?, row.get(1)?)),
    )?;

    let device_id = get_or_create_device_id(conn)?;
    let seq = next_device_seq(conn, &device_id)?;
    let op = serde_json::json!({
        "op_id": uuid::Uuid::new_v4().to_string(),
        "device_id": device_id,
        "seq": seq,
        "ts_ms": stored_updated_at_ms,
        "type": "attachment.exif.upsert.v1",
        "payload": {
            "attachment_sha256": attachment_sha256,
            "captured_at_ms": captured_at_ms,
            "latitude": latitude,
            "longitude": longitude,
            "created_at_ms": stored_created_at_ms,
            "updated_at_ms": stored_updated_at_ms,
        }
    });
    insert_oplog(conn, key, &op)?;

    Ok(())
}

pub fn read_attachment_exif_metadata(
    conn: &Connection,
    key: &[u8; 32],
    attachment_sha256: &str,
) -> Result<Option<AttachmentExifMetadata>> {
    let blob: Option<Vec<u8>> = conn
        .query_row(
            r#"SELECT metadata FROM attachment_exif WHERE attachment_sha256 = ?1"#,
            params![attachment_sha256],
            |row| row.get(0),
        )
        .optional()?;

    let blob = match blob {
        Some(blob) => blob,
        None => return Ok(None),
    };

    let aad = format!("attachment.exif:{attachment_sha256}");
    let json = decrypt_bytes(key, &blob, aad.as_bytes())?;
    let metadata: AttachmentExifMetadata = serde_json::from_slice(&json)?;
    Ok(Some(metadata))
}

pub fn enqueue_attachment_place(
    conn: &Connection,
    attachment_sha256: &str,
    lang: &str,
    now_ms: i64,
) -> Result<()> {
    let lang = lang.trim();
    if lang.is_empty() {
        return Err(anyhow!("lang is required"));
    }

    conn.execute(
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
VALUES (?1, 'pending', ?2, NULL, 0, NULL, NULL, ?3, ?3)
ON CONFLICT(attachment_sha256) DO UPDATE SET
  status = CASE
    WHEN attachment_places.status = 'ok' AND attachment_places.lang = excluded.lang THEN 'ok'
    ELSE 'pending'
  END,
  lang = excluded.lang,
  payload = CASE
    WHEN attachment_places.status = 'ok' AND attachment_places.lang = excluded.lang THEN attachment_places.payload
    ELSE NULL
  END,
  attempts = CASE
    WHEN attachment_places.status = 'ok' AND attachment_places.lang = excluded.lang THEN attachment_places.attempts
    ELSE 0
  END,
  next_retry_at = NULL,
  last_error = NULL,
  updated_at = excluded.updated_at
"#,
        params![attachment_sha256, lang, now_ms],
    )?;
    Ok(())
}

pub fn enqueue_attachment_annotation(
    conn: &Connection,
    attachment_sha256: &str,
    lang: &str,
    now_ms: i64,
) -> Result<()> {
    let lang = lang.trim();
    if lang.is_empty() {
        return Err(anyhow!("lang is required"));
    }

    conn.execute(
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
VALUES (?1, 'pending', ?2, NULL, NULL, 0, NULL, NULL, ?3, ?3)
ON CONFLICT(attachment_sha256) DO UPDATE SET
  status = CASE
    WHEN attachment_annotations.status = 'ok' AND attachment_annotations.lang = excluded.lang THEN 'ok'
    ELSE 'pending'
  END,
  lang = excluded.lang,
  model_name = CASE
    WHEN attachment_annotations.status = 'ok' AND attachment_annotations.lang = excluded.lang THEN attachment_annotations.model_name
    ELSE NULL
  END,
  payload = CASE
    WHEN attachment_annotations.status = 'ok' AND attachment_annotations.lang = excluded.lang THEN attachment_annotations.payload
    ELSE NULL
  END,
  attempts = CASE
    WHEN attachment_annotations.status = 'ok' AND attachment_annotations.lang = excluded.lang THEN attachment_annotations.attempts
    ELSE 0
  END,
  next_retry_at = NULL,
  last_error = NULL,
  updated_at = excluded.updated_at
"#,
        params![attachment_sha256, lang, now_ms],
    )?;
    Ok(())
}

pub fn list_due_attachment_places(
    conn: &Connection,
    now_ms: i64,
    limit: i64,
) -> Result<Vec<AttachmentPlaceJob>> {
    let limit = limit.clamp(1, 500);
    let mut stmt = conn.prepare(
        r#"
SELECT attachment_sha256, status, lang, attempts, next_retry_at, last_error, created_at, updated_at
FROM attachment_places
WHERE status != 'ok'
  AND (next_retry_at IS NULL OR next_retry_at <= ?1)
ORDER BY updated_at ASC, attachment_sha256 ASC
LIMIT ?2
"#,
    )?;

    let mut rows = stmt.query(params![now_ms, limit])?;
    let mut result = Vec::new();
    while let Some(row) = rows.next()? {
        result.push(AttachmentPlaceJob {
            attachment_sha256: row.get(0)?,
            status: row.get(1)?,
            lang: row.get(2)?,
            attempts: row.get(3)?,
            next_retry_at_ms: row.get(4)?,
            last_error: row.get(5)?,
            created_at_ms: row.get(6)?,
            updated_at_ms: row.get(7)?,
        });
    }
    Ok(result)
}

pub fn list_due_attachment_annotations(
    conn: &Connection,
    now_ms: i64,
    limit: i64,
) -> Result<Vec<AttachmentAnnotationJob>> {
    let limit = limit.clamp(1, 500);
    let mut stmt = conn.prepare(
        r#"
SELECT attachment_sha256, status, lang, model_name, attempts, next_retry_at, last_error, created_at, updated_at
FROM attachment_annotations
WHERE status != 'ok'
  AND (next_retry_at IS NULL OR next_retry_at <= ?1)
ORDER BY updated_at ASC, attachment_sha256 ASC
LIMIT ?2
"#,
    )?;

    let mut rows = stmt.query(params![now_ms, limit])?;
    let mut result = Vec::new();
    while let Some(row) = rows.next()? {
        result.push(AttachmentAnnotationJob {
            attachment_sha256: row.get(0)?,
            status: row.get(1)?,
            lang: row.get(2)?,
            model_name: row.get(3)?,
            attempts: row.get(4)?,
            next_retry_at_ms: row.get(5)?,
            last_error: row.get(6)?,
            created_at_ms: row.get(7)?,
            updated_at_ms: row.get(8)?,
        });
    }
    Ok(result)
}

fn mark_messages_linked_to_attachment_for_reembedding(
    conn: &Connection,
    attachment_sha256: &str,
) -> Result<()> {
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

pub fn mark_attachment_place_ok(
    conn: &Connection,
    key: &[u8; 32],
    attachment_sha256: &str,
    lang: &str,
    payload: &serde_json::Value,
    now_ms: i64,
) -> Result<()> {
    backfill_attachments_oplog_if_needed(conn, key)?;

    let lang = lang.trim();
    if lang.is_empty() {
        return Err(anyhow!("lang is required"));
    }

    let json = serde_json::to_vec(payload)?;
    let aad = format!("attachment.place:{attachment_sha256}:{lang}");
    let blob = encrypt_bytes(key, &json, aad.as_bytes())?;

    conn.execute(
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
VALUES (?1, 'ok', ?2, ?3, 0, NULL, NULL, ?4, ?4)
ON CONFLICT(attachment_sha256) DO UPDATE SET
  status = 'ok',
  lang = excluded.lang,
  payload = excluded.payload,
  next_retry_at = NULL,
  last_error = NULL,
  updated_at = excluded.updated_at
"#,
        params![attachment_sha256, lang, blob, now_ms],
    )?;

    let (stored_created_at_ms, stored_updated_at_ms): (i64, i64) = conn.query_row(
        r#"SELECT created_at, updated_at
           FROM attachment_places
           WHERE attachment_sha256 = ?1"#,
        params![attachment_sha256],
        |row| Ok((row.get(0)?, row.get(1)?)),
    )?;

    let device_id = get_or_create_device_id(conn)?;
    let seq = next_device_seq(conn, &device_id)?;
    let op = serde_json::json!({
        "op_id": uuid::Uuid::new_v4().to_string(),
        "device_id": device_id,
        "seq": seq,
        "ts_ms": stored_updated_at_ms,
        "type": "attachment.place.upsert.v1",
        "payload": {
            "attachment_sha256": attachment_sha256,
            "lang": lang,
            "payload": payload,
            "created_at_ms": stored_created_at_ms,
            "updated_at_ms": stored_updated_at_ms,
        }
    });
    insert_oplog(conn, key, &op)?;

    mark_messages_linked_to_attachment_for_reembedding(conn, attachment_sha256)?;
    Ok(())
}

pub fn mark_attachment_place_failed(
    conn: &Connection,
    attachment_sha256: &str,
    attempts: i64,
    next_retry_at_ms: i64,
    last_error: &str,
    now_ms: i64,
) -> Result<()> {
    conn.execute(
        r#"
UPDATE attachment_places
SET status = 'failed',
    attempts = ?2,
    next_retry_at = ?3,
    last_error = ?4,
    updated_at = ?5
WHERE attachment_sha256 = ?1
"#,
        params![
            attachment_sha256,
            attempts,
            next_retry_at_ms,
            last_error,
            now_ms
        ],
    )?;
    Ok(())
}

pub fn mark_attachment_annotation_ok(
    conn: &Connection,
    key: &[u8; 32],
    attachment_sha256: &str,
    lang: &str,
    model_name: &str,
    payload: &serde_json::Value,
    now_ms: i64,
) -> Result<()> {
    let lang = lang.trim();
    if lang.is_empty() {
        return Err(anyhow!("lang is required"));
    }
    let model_name = model_name.trim();
    if model_name.is_empty() {
        return Err(anyhow!("model_name is required"));
    }

    let json = serde_json::to_vec(payload)?;
    let aad = format!("attachment.annotation:{attachment_sha256}:{lang}");
    let blob = encrypt_bytes(key, &json, aad.as_bytes())?;

    conn.execute(
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
VALUES (?1, 'ok', ?2, ?3, ?4, 0, NULL, NULL, ?5, ?5)
ON CONFLICT(attachment_sha256) DO UPDATE SET
  status = 'ok',
  lang = excluded.lang,
  model_name = excluded.model_name,
  payload = excluded.payload,
  next_retry_at = NULL,
  last_error = NULL,
  updated_at = excluded.updated_at
"#,
        params![attachment_sha256, lang, model_name, blob, now_ms],
    )?;

    mark_messages_linked_to_attachment_for_reembedding(conn, attachment_sha256)?;
    Ok(())
}

pub fn mark_attachment_annotation_failed(
    conn: &Connection,
    attachment_sha256: &str,
    attempts: i64,
    next_retry_at_ms: i64,
    last_error: &str,
    now_ms: i64,
) -> Result<()> {
    conn.execute(
        r#"
UPDATE attachment_annotations
SET status = 'failed',
    attempts = ?2,
    next_retry_at = ?3,
    last_error = ?4,
    updated_at = ?5
WHERE attachment_sha256 = ?1
"#,
        params![
            attachment_sha256,
            attempts,
            next_retry_at_ms,
            last_error,
            now_ms
        ],
    )?;
    Ok(())
}

