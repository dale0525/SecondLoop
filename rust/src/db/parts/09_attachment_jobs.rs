pub fn enqueue_semantic_parse_job(conn: &Connection, message_id: &str, now_ms: i64) -> Result<()> {
    let message_id = message_id.trim();
    if message_id.is_empty() {
        return Err(anyhow!("message_id is required"));
    }

    conn.execute(
        r#"
INSERT OR IGNORE INTO semantic_parse_jobs(
  message_id,
  status,
  attempts,
  next_retry_at_ms,
  last_error,
  applied_action_kind,
  applied_todo_id,
  applied_todo_title,
  applied_prev_todo_status,
  undone_at_ms,
  created_at_ms,
  updated_at_ms
)
VALUES (?1, 'pending', 0, NULL, NULL, NULL, NULL, NULL, NULL, NULL, ?2, ?2)
"#,
        params![message_id, now_ms],
    )?;
    Ok(())
}

pub fn list_due_semantic_parse_jobs(
    conn: &Connection,
    now_ms: i64,
    limit: i64,
) -> Result<Vec<SemanticParseJob>> {
    let limit = limit.clamp(1, 500);
    let mut stmt = conn.prepare(
        r#"
SELECT message_id,
       status,
       attempts,
       next_retry_at_ms,
       last_error,
       applied_action_kind,
       applied_todo_id,
       applied_prev_todo_status,
       undone_at_ms,
       created_at_ms,
       updated_at_ms
FROM semantic_parse_jobs
WHERE status IN ('pending', 'failed', 'running')
  AND (next_retry_at_ms IS NULL OR next_retry_at_ms <= ?1)
ORDER BY updated_at_ms ASC, message_id ASC
LIMIT ?2
"#,
    )?;

    let mut rows = stmt.query(params![now_ms, limit])?;
    let mut result = Vec::new();
    while let Some(row) = rows.next()? {
        result.push(SemanticParseJob {
            message_id: row.get(0)?,
            status: row.get(1)?,
            attempts: row.get(2)?,
            next_retry_at_ms: row.get(3)?,
            last_error: row.get(4)?,
            applied_action_kind: row.get(5)?,
            applied_todo_id: row.get(6)?,
            applied_todo_title: None,
            applied_prev_todo_status: row.get(7)?,
            undone_at_ms: row.get(8)?,
            created_at_ms: row.get(9)?,
            updated_at_ms: row.get(10)?,
        });
    }
    Ok(result)
}

pub fn list_semantic_parse_jobs_by_message_ids(
    conn: &Connection,
    key: &[u8; 32],
    message_ids: &[String],
) -> Result<Vec<SemanticParseJob>> {
    if message_ids.is_empty() {
        return Ok(Vec::new());
    }

    let mut placeholders = String::new();
    for i in 0..message_ids.len() {
        if i > 0 {
            placeholders.push(',');
        }
        placeholders.push('?');
        placeholders.push_str(&(i + 1).to_string());
    }

    let sql = format!(
        r#"
SELECT message_id,
       status,
       attempts,
       next_retry_at_ms,
       last_error,
       applied_action_kind,
       applied_todo_id,
       applied_todo_title,
       applied_prev_todo_status,
       undone_at_ms,
       created_at_ms,
       updated_at_ms
FROM semantic_parse_jobs
WHERE message_id IN ({placeholders})
ORDER BY updated_at_ms ASC, message_id ASC
"#
    );

    let mut stmt = conn.prepare(&sql)?;
    let params = rusqlite::params_from_iter(message_ids.iter());
    let mut rows = stmt.query(params)?;

    let mut result = Vec::new();
    while let Some(row) = rows.next()? {
        let message_id: String = row.get(0)?;
        let title_blob: Option<Vec<u8>> = row.get(7)?;
        let applied_todo_title = match title_blob {
            Some(blob) => {
                let aad = semantic_parse_job_title_aad(&message_id);
                let bytes = decrypt_bytes(key, &blob, &aad)?;
                Some(
                    String::from_utf8(bytes)
                        .map_err(|_| anyhow!("job title is not valid utf-8"))?,
                )
            }
            None => None,
        };

        result.push(SemanticParseJob {
            message_id,
            status: row.get(1)?,
            attempts: row.get(2)?,
            next_retry_at_ms: row.get(3)?,
            last_error: row.get(4)?,
            applied_action_kind: row.get(5)?,
            applied_todo_id: row.get(6)?,
            applied_todo_title,
            applied_prev_todo_status: row.get(8)?,
            undone_at_ms: row.get(9)?,
            created_at_ms: row.get(10)?,
            updated_at_ms: row.get(11)?,
        });
    }
    Ok(result)
}

pub fn mark_semantic_parse_job_running(
    conn: &Connection,
    message_id: &str,
    now_ms: i64,
) -> Result<()> {
    conn.execute(
        r#"
UPDATE semantic_parse_jobs
SET status = 'running',
    updated_at_ms = ?2
WHERE message_id = ?1
  AND status IN ('pending', 'failed', 'running')
"#,
        params![message_id, now_ms],
    )?;
    Ok(())
}

pub fn mark_semantic_parse_job_failed(
    conn: &Connection,
    message_id: &str,
    attempts: i64,
    next_retry_at_ms: i64,
    last_error: &str,
    now_ms: i64,
) -> Result<()> {
    conn.execute(
        r#"
UPDATE semantic_parse_jobs
SET status = 'failed',
    attempts = ?2,
    next_retry_at_ms = ?3,
    last_error = ?4,
    updated_at_ms = ?5
WHERE message_id = ?1
"#,
        params![message_id, attempts, next_retry_at_ms, last_error, now_ms],
    )?;
    Ok(())
}

pub fn mark_semantic_parse_job_retry(
    conn: &Connection,
    message_id: &str,
    now_ms: i64,
) -> Result<()> {
    conn.execute(
        r#"
UPDATE semantic_parse_jobs
SET status = 'pending',
    next_retry_at_ms = NULL,
    last_error = NULL,
    updated_at_ms = ?2
WHERE message_id = ?1
  AND status != 'succeeded'
"#,
        params![message_id, now_ms],
    )?;
    Ok(())
}

pub fn mark_semantic_parse_job_succeeded(
    conn: &Connection,
    key: &[u8; 32],
    message_id: &str,
    applied_action_kind: &str,
    applied_todo_id: Option<&str>,
    applied_todo_title: Option<&str>,
    applied_prev_todo_status: Option<&str>,
    now_ms: i64,
) -> Result<()> {
    let message_id = message_id.trim();
    if message_id.is_empty() {
        return Err(anyhow!("message_id is required"));
    }
    let applied_action_kind = applied_action_kind.trim();
    if applied_action_kind.is_empty() {
        return Err(anyhow!("applied_action_kind is required"));
    }

    let title_blob = match applied_todo_title {
        Some(title) if !title.trim().is_empty() => {
            let aad = semantic_parse_job_title_aad(message_id);
            Some(encrypt_bytes(key, title.trim().as_bytes(), &aad)?)
        }
        _ => None,
    };

    conn.execute(
        r#"
UPDATE semantic_parse_jobs
SET status = 'succeeded',
    next_retry_at_ms = NULL,
    last_error = NULL,
    applied_action_kind = ?2,
    applied_todo_id = ?3,
    applied_todo_title = ?4,
    applied_prev_todo_status = ?5,
    updated_at_ms = ?6
WHERE message_id = ?1
"#,
        params![
            message_id,
            applied_action_kind,
            applied_todo_id,
            title_blob,
            applied_prev_todo_status,
            now_ms
        ],
    )?;
    Ok(())
}

pub fn mark_semantic_parse_job_canceled(
    conn: &Connection,
    message_id: &str,
    now_ms: i64,
) -> Result<()> {
    conn.execute(
        r#"
UPDATE semantic_parse_jobs
SET status = 'canceled',
    next_retry_at_ms = NULL,
    last_error = NULL,
    updated_at_ms = ?2
WHERE message_id = ?1
  AND status != 'succeeded'
"#,
        params![message_id, now_ms],
    )?;
    Ok(())
}

pub fn mark_semantic_parse_job_undone(
    conn: &Connection,
    message_id: &str,
    now_ms: i64,
) -> Result<()> {
    conn.execute(
        r#"
UPDATE semantic_parse_jobs
SET undone_at_ms = ?2,
    updated_at_ms = ?2
WHERE message_id = ?1
"#,
        params![message_id, now_ms],
    )?;
    Ok(())
}

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

    let blob = fs::read(app_dir.join(stored_path))?;
    let aad = format!("attachment.variant.bytes:{attachment_sha256}:{variant}");
    decrypt_bytes(key, &blob, aad.as_bytes())
}

pub fn enqueue_cloud_media_backup(
    conn: &Connection,
    attachment_sha256: &str,
    desired_variant: &str,
    now_ms: i64,
) -> Result<()> {
    let desired_variant = desired_variant.trim();
    if desired_variant.is_empty() {
        return Err(anyhow!("desired_variant is required"));
    }

    conn.execute(
        r#"
INSERT INTO cloud_media_backup(
  attachment_sha256,
  desired_variant,
  status,
  attempts,
  next_retry_at,
  last_error,
  updated_at
)
VALUES (?1, ?2, 'pending', 0, NULL, NULL, ?3)
ON CONFLICT(attachment_sha256) DO UPDATE SET
  desired_variant = excluded.desired_variant,
  status = CASE
    WHEN cloud_media_backup.status = 'uploaded' THEN 'uploaded'
    ELSE 'pending'
  END,
  next_retry_at = NULL,
  last_error = NULL,
  updated_at = excluded.updated_at
"#,
        params![attachment_sha256, desired_variant, now_ms],
    )?;
    Ok(())
}

pub fn backfill_cloud_media_backup_images(
    conn: &Connection,
    desired_variant: &str,
    now_ms: i64,
) -> Result<u64> {
    let desired_variant = desired_variant.trim();
    if desired_variant.is_empty() {
        return Err(anyhow!("desired_variant is required"));
    }

    let affected = conn.execute(
        r#"
INSERT INTO cloud_media_backup(
  attachment_sha256,
  desired_variant,
  status,
  attempts,
  next_retry_at,
  last_error,
  updated_at
)
SELECT sha256, ?1, 'pending', 0, NULL, NULL, ?2
FROM attachments
WHERE mime_type LIKE 'image/%'
ON CONFLICT(attachment_sha256) DO UPDATE SET
  desired_variant = excluded.desired_variant,
  status = CASE
    WHEN cloud_media_backup.status = 'uploaded' THEN 'uploaded'
    ELSE 'pending'
  END,
  next_retry_at = NULL,
  last_error = NULL,
  updated_at = excluded.updated_at
"#,
        params![desired_variant, now_ms],
    )?;

    Ok(affected as u64)
}

pub fn list_due_cloud_media_backups(
    conn: &Connection,
    now_ms: i64,
    limit: i64,
) -> Result<Vec<CloudMediaBackup>> {
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
WHERE status != 'uploaded'
  AND (next_retry_at IS NULL OR next_retry_at <= ?1)
ORDER BY cmb.updated_at ASC, cmb.attachment_sha256 ASC
LIMIT ?2
"#,
    )?;

    let mut rows = stmt.query(params![now_ms, limit])?;
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
) -> Result<()> {
    conn.execute(
        r#"
UPDATE cloud_media_backup
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

pub fn mark_cloud_media_backup_uploaded(
    conn: &Connection,
    attachment_sha256: &str,
    now_ms: i64,
) -> Result<()> {
    conn.execute(
        r#"
UPDATE cloud_media_backup
SET status = 'uploaded',
    next_retry_at = NULL,
    last_error = NULL,
    updated_at = ?2
WHERE attachment_sha256 = ?1
"#,
        params![attachment_sha256, now_ms],
    )?;
    Ok(())
}

pub fn cloud_media_backup_summary(conn: &Connection) -> Result<CloudMediaBackupSummary> {
    let mut pending = 0i64;
    let mut failed = 0i64;
    let mut uploaded = 0i64;

    let mut stmt =
        conn.prepare(r#"SELECT status, COUNT(*) FROM cloud_media_backup GROUP BY status"#)?;
    let mut rows = stmt.query([])?;
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
            r#"SELECT MAX(updated_at) FROM cloud_media_backup WHERE status = 'uploaded'"#,
            [],
            |row| row.get(0),
        )
        .optional()?
        .flatten();

    let (last_error, last_error_at_ms): (Option<String>, Option<i64>) = conn
        .query_row(
            r#"
SELECT last_error, updated_at
FROM cloud_media_backup
WHERE last_error IS NOT NULL
ORDER BY updated_at DESC
LIMIT 1
"#,
            [],
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
