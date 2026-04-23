pub fn link_attachment_to_message(
    conn: &Connection,
    key: &[u8; 32],
    message_id: &str,
    attachment_sha256: &str,
) -> Result<()> {
    backfill_attachments_oplog_if_needed(conn, key)?;

    let now = now_ms();
    let inserted = conn.execute(
        r#"INSERT OR IGNORE INTO message_attachments(message_id, attachment_sha256, created_at)
           VALUES (?1, ?2, ?3)"#,
        params![message_id, attachment_sha256, now],
    )?;
    if inserted == 0 {
        return Ok(());
    }

    let device_id = get_or_create_device_id(conn)?;
    let seq = next_device_seq(conn, &device_id)?;
    let op = serde_json::json!({
        "op_id": uuid::Uuid::new_v4().to_string(),
        "device_id": device_id,
        "seq": seq,
        "ts_ms": now,
        "type": "message.attachment.link.v1",
        "payload": {
            "message_id": message_id,
            "attachment_sha256": attachment_sha256,
            "created_at_ms": now,
        }
    });
    insert_oplog(conn, key, &op)?;

    // Best-effort: auto-enqueue content enrichment for URL manifests and document-like files.
    if let Ok(mime_type) = read_attachment_mime_type(conn, attachment_sha256) {
        let _ = maybe_auto_enqueue_content_enrichment_for_attachment(
            conn,
            attachment_sha256,
            &mime_type,
            now,
        );
    }
    Ok(())
}

fn sanitize_variant_id(raw: &str) -> String {
    let raw = raw.trim();
    if raw.is_empty() {
        return "variant".to_string();
    }
    let mut out = String::with_capacity(raw.len().min(64));
    for ch in raw.chars() {
        if out.len() >= 64 {
            break;
        }
        if ch.is_ascii_alphanumeric() || ch == '_' || ch == '-' {
            out.push(ch);
        } else {
            out.push('_');
        }
    }
    if out.is_empty() {
        "variant".to_string()
    } else {
        out
    }
}

pub fn upsert_attachment_variant(
    conn: &Connection,
    key: &[u8; 32],
    app_dir: &Path,
    attachment_sha256: &str,
    variant: &str,
    bytes: &[u8],
    mime_type: &str,
) -> Result<AttachmentVariant> {
    let variant = variant.trim();
    if variant.is_empty() {
        return Err(anyhow!("variant is required"));
    }

    let safe_variant = sanitize_variant_id(variant);
    let rel_dir = format!("attachments/variants/{attachment_sha256}");
    let rel_path = format!("{rel_dir}/{safe_variant}.bin");

    let full_dir = app_dir.join(&rel_dir);
    fs::create_dir_all(&full_dir)?;

    let full_path = full_dir.join(format!("{safe_variant}.bin"));
    let aad = format!("attachment.variant.bytes:{attachment_sha256}:{variant}");
    let blob = encrypt_bytes(key, bytes, aad.as_bytes())?;
    fs::write(&full_path, blob)?;

    let now = now_ms();
    conn.execute(
        r#"INSERT OR IGNORE INTO attachment_variants(
             attachment_sha256,
             variant,
             mime_type,
             path,
             byte_len,
             created_at
           ) VALUES (?1, ?2, ?3, ?4, ?5, ?6)"#,
        params![
            attachment_sha256,
            variant,
            mime_type,
            rel_path.as_str(),
            bytes.len() as i64,
            now
        ],
    )?;

    let (stored_mime_type, stored_path, stored_byte_len, stored_created_at_ms): (
        String,
        String,
        i64,
        i64,
    ) = conn.query_row(
        r#"SELECT mime_type, path, byte_len, created_at
           FROM attachment_variants
           WHERE attachment_sha256 = ?1 AND variant = ?2"#,
        params![attachment_sha256, variant],
        |row| Ok((row.get(0)?, row.get(1)?, row.get(2)?, row.get(3)?)),
    )?;

    Ok(AttachmentVariant {
        attachment_sha256: attachment_sha256.to_string(),
        variant: variant.to_string(),
        mime_type: stored_mime_type,
        path: stored_path,
        byte_len: stored_byte_len,
        created_at_ms: stored_created_at_ms,
    })
}

pub fn read_attachment_variant_bytes(
    conn: &Connection,
    key: &[u8; 32],
    app_dir: &Path,
    attachment_sha256: &str,
    variant: &str,
) -> Result<Vec<u8>> {
    let variant = variant.trim();
    if variant.is_empty() {
        return Err(anyhow!("variant is required"));
    }

    let stored_path: Option<String> = conn
        .query_row(
            r#"SELECT path
               FROM attachment_variants
               WHERE attachment_sha256 = ?1 AND variant = ?2"#,
            params![attachment_sha256, variant],
            |row| row.get(0),
        )
        .optional()?;
    let stored_path = stored_path.ok_or_else(|| anyhow!("attachment variant not found"))?;

    let blob = read_file_with_domain_not_found(
        &app_dir.join(stored_path),
        "attachment variant not found",
    )?;
    let aad = format!("attachment.variant.bytes:{attachment_sha256}:{variant}");
    decrypt_bytes(key, &blob, aad.as_bytes())
}

pub fn enqueue_cloud_media_backup(
    conn: &Connection,
    attachment_sha256: &str,
    desired_variant: &str,
    now_ms: i64,
    scope_id: Option<&str>,
) -> Result<()> {
    let desired_variant = desired_variant.trim();
    if desired_variant.is_empty() {
        return Err(anyhow!("desired_variant is required"));
    }

    let scope_id = normalize_cloud_media_backup_scope_id(scope_id);
    upsert_cloud_media_backup_row(conn, attachment_sha256, desired_variant, now_ms, &scope_id)?;
    Ok(())
}

fn normalize_cloud_media_backup_scope_id(scope_id: Option<&str>) -> String {
    scope_id.unwrap_or("").trim().to_string()
}

fn upsert_cloud_media_backup_row(
    conn: &Connection,
    attachment_sha256: &str,
    desired_variant: &str,
    now_ms: i64,
    scope_id: &str,
) -> Result<u64> {
    let affected = conn.execute(
        r#"
INSERT INTO cloud_media_backup(
  scope_id,
  attachment_sha256,
  desired_variant,
  status,
  attempts,
  next_retry_at,
  last_error,
  updated_at
)
VALUES (?1, ?2, ?3, 'pending', 0, NULL, NULL, ?4)
ON CONFLICT(scope_id, attachment_sha256) DO UPDATE SET
  desired_variant = excluded.desired_variant,
  status = CASE
    WHEN cloud_media_backup.status = 'uploaded' THEN 'uploaded'
    ELSE 'pending'
  END,
  next_retry_at = NULL,
  last_error = NULL,
  updated_at = excluded.updated_at
"#,
        params![scope_id, attachment_sha256, desired_variant, now_ms],
    )?;
    Ok(affected as u64)
}

fn prune_cloud_media_backup_rows_missing_local_bytes(
    conn: &Connection,
    scope_id: &str,
) -> Result<u64> {
    let Ok(app_dir) = app_dir_from_conn(conn) else {
        return Ok(0);
    };

    let mut stmt = conn.prepare(
        r#"
SELECT cmb.attachment_sha256, a.path
FROM cloud_media_backup cmb
LEFT JOIN attachments a ON a.sha256 = cmb.attachment_sha256
WHERE cmb.scope_id = ?1
"#,
    )?;

    let mut rows = stmt.query(params![scope_id])?;
    let mut stale_attachment_sha256s = Vec::new();
    while let Some(row) = rows.next()? {
        let attachment_sha256: String = row.get(0)?;
        let path: Option<String> = row.get(1)?;
        let Some(path) = path else {
            stale_attachment_sha256s.push(attachment_sha256);
            continue;
        };

        if !app_dir.join(path).is_file() {
            stale_attachment_sha256s.push(attachment_sha256);
        }
    }

    let mut pruned = 0u64;
    for attachment_sha256 in stale_attachment_sha256s {
        pruned += conn.execute(
            r#"DELETE FROM cloud_media_backup WHERE scope_id = ?1 AND attachment_sha256 = ?2"#,
            params![scope_id, attachment_sha256],
        )? as u64;
    }
    Ok(pruned)
}

pub fn backfill_cloud_media_backup_images(
    conn: &Connection,
    desired_variant: &str,
    now_ms: i64,
    scope_id: Option<&str>,
) -> Result<u64> {
    let desired_variant = desired_variant.trim();
    if desired_variant.is_empty() {
        return Err(anyhow!("desired_variant is required"));
    }

    let scope_id = normalize_cloud_media_backup_scope_id(scope_id);
    let _ = prune_cloud_media_backup_rows_missing_local_bytes(conn, &scope_id)?;

    let Ok(app_dir) = app_dir_from_conn(conn) else {
        return Ok(0);
    };

    let mut stmt = conn.prepare(
        r#"
SELECT sha256, path
FROM attachments
ORDER BY created_at ASC, sha256 ASC
"#,
    )?;

    let mut rows = stmt.query([])?;
    let mut affected = 0u64;
    while let Some(row) = rows.next()? {
        let attachment_sha256: String = row.get(0)?;
        let path: String = row.get(1)?;
        if !app_dir.join(path).is_file() {
            continue;
        }

        affected += upsert_cloud_media_backup_row(
            conn,
            &attachment_sha256,
            desired_variant,
            now_ms,
            &scope_id,
        )?;
    }

    Ok(affected)
}

pub fn list_due_cloud_media_backups(
    conn: &Connection,
    now_ms: i64,
    limit: i64,
    scope_id: Option<&str>,
) -> Result<Vec<CloudMediaBackup>> {
    let scope_id = normalize_cloud_media_backup_scope_id(scope_id);
    let _ = prune_cloud_media_backup_rows_missing_local_bytes(conn, &scope_id)?;

    let limit = limit.clamp(1, 500);
    let mut stmt = conn.prepare(
        r#"
SELECT cmb.attachment_sha256,
       cmb.desired_variant,
       COALESCE(a.byte_len, 0) AS byte_len,
       cmb.status,
       cmb.attempts,
       cmb.next_retry_at,
       cmb.last_error,
       cmb.updated_at
FROM cloud_media_backup cmb
LEFT JOIN attachments a ON a.sha256 = cmb.attachment_sha256
WHERE cmb.scope_id = ?1
  AND status != 'uploaded'
  AND (next_retry_at IS NULL OR next_retry_at <= ?2)
ORDER BY cmb.updated_at ASC, cmb.attachment_sha256 ASC
LIMIT ?3
"#,
    )?;

    let mut rows = stmt.query(params![scope_id, now_ms, limit])?;
    let mut result = Vec::new();
    while let Some(row) = rows.next()? {
        result.push(CloudMediaBackup {
            attachment_sha256: row.get(0)?,
            desired_variant: row.get(1)?,
            byte_len: row.get(2)?,
            status: row.get(3)?,
            attempts: row.get(4)?,
            next_retry_at_ms: row.get(5)?,
            last_error: row.get(6)?,
            updated_at_ms: row.get(7)?,
        });
    }
    Ok(result)
}

pub fn mark_cloud_media_backup_failed(
    conn: &Connection,
    attachment_sha256: &str,
    attempts: i64,
    next_retry_at_ms: i64,
    last_error: &str,
    now_ms: i64,
    scope_id: Option<&str>,
) -> Result<()> {
    let scope_id = normalize_cloud_media_backup_scope_id(scope_id);
    conn.execute(
        r#"
UPDATE cloud_media_backup
SET status = 'failed',
    attempts = ?3,
    next_retry_at = ?4,
    last_error = ?5,
    updated_at = ?6
WHERE scope_id = ?1
  AND attachment_sha256 = ?2
"#,
        params![
            scope_id,
            attachment_sha256,
            attempts,
            next_retry_at_ms,
            last_error,
            now_ms
        ],
    )?;
    Ok(())
}

pub fn mark_cloud_media_backup_uploaded(
    conn: &Connection,
    attachment_sha256: &str,
    now_ms: i64,
    scope_id: Option<&str>,
) -> Result<()> {
    let scope_id = normalize_cloud_media_backup_scope_id(scope_id);
    conn.execute(
        r#"
UPDATE cloud_media_backup
SET status = 'uploaded',
    next_retry_at = NULL,
    last_error = NULL,
    updated_at = ?3
WHERE scope_id = ?1
  AND attachment_sha256 = ?2
"#,
        params![scope_id, attachment_sha256, now_ms],
    )?;
    Ok(())
}

pub fn cloud_media_backup_summary(
    conn: &Connection,
    scope_id: Option<&str>,
) -> Result<CloudMediaBackupSummary> {
    let scope_id = normalize_cloud_media_backup_scope_id(scope_id);
    let _ = prune_cloud_media_backup_rows_missing_local_bytes(conn, &scope_id)?;

    let mut pending = 0i64;
    let mut failed = 0i64;
    let mut uploaded = 0i64;

    let mut stmt = conn.prepare(
        r#"SELECT status, COUNT(*) FROM cloud_media_backup WHERE scope_id = ?1 GROUP BY status"#,
    )?;
    let mut rows = stmt.query(params![scope_id.as_str()])?;
    while let Some(row) = rows.next()? {
        let status: String = row.get(0)?;
        let count: i64 = row.get(1)?;
        match status.as_str() {
            "pending" => pending = count,
            "failed" => failed = count,
            "uploaded" => uploaded = count,
            _ => {}
        }
    }

    let last_uploaded_at_ms: Option<i64> = conn
        .query_row(
            r#"SELECT MAX(updated_at) FROM cloud_media_backup WHERE scope_id = ?1 AND status = 'uploaded'"#,
            params![scope_id.as_str()],
            |row| row.get(0),
        )
        .optional()?
        .flatten();

    let (last_error, last_error_at_ms): (Option<String>, Option<i64>) = conn
        .query_row(
            r#"
SELECT last_error, updated_at
FROM cloud_media_backup
WHERE scope_id = ?1
  AND last_error IS NOT NULL
ORDER BY updated_at DESC
LIMIT 1
"#,
            params![scope_id.as_str()],
            |row| Ok((row.get(0)?, row.get(1)?)),
        )
        .optional()?
        .unwrap_or((None, None));

    Ok(CloudMediaBackupSummary {
        pending,
        failed,
        uploaded,
        last_uploaded_at_ms,
        last_error,
        last_error_at_ms,
    })
}

pub fn list_message_attachments(
    conn: &Connection,
    _key: &[u8; 32],
    message_id: &str,
) -> Result<Vec<Attachment>> {
    let mut stmt = conn.prepare(
        r#"
SELECT a.sha256, a.mime_type, a.path, a.byte_len, a.created_at
FROM attachments a
JOIN message_attachments ma ON ma.attachment_sha256 = a.sha256
WHERE ma.message_id = ?1
ORDER BY a.created_at ASC, a.sha256 ASC
"#,
    )?;

    let mut rows = stmt.query(params![message_id])?;
    let mut result = Vec::new();
    while let Some(row) = rows.next()? {
        result.push(Attachment {
            sha256: row.get(0)?,
            mime_type: row.get(1)?,
            path: row.get(2)?,
            byte_len: row.get(3)?,
            created_at_ms: row.get(4)?,
        });
    }
    Ok(result)
}

pub fn list_recent_attachments(
    conn: &Connection,
    _key: &[u8; 32],
    limit: i64,
) -> Result<Vec<Attachment>> {
    let limit = limit.clamp(1, 500);
    let mut stmt = conn.prepare(
        r#"
SELECT sha256, mime_type, path, byte_len, created_at
FROM attachments
ORDER BY created_at DESC, sha256 DESC
LIMIT ?1
"#,
    )?;

    let mut rows = stmt.query(params![limit])?;
    let mut result = Vec::new();
    while let Some(row) = rows.next()? {
        result.push(Attachment {
            sha256: row.get(0)?,
            mime_type: row.get(1)?,
            path: row.get(2)?,
            byte_len: row.get(3)?,
            created_at_ms: row.get(4)?,
        });
    }
    Ok(result)
}
