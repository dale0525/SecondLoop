#[derive(Clone, Debug, Deserialize, Serialize)]
pub struct AttachmentMetadata {
    pub title: Option<String>,
    pub filenames: Vec<String>,
    pub source_urls: Vec<String>,
    pub title_updated_at_ms: i64,
    pub created_at_ms: i64,
    pub updated_at_ms: i64,
}

type AttachmentMetadataDbRow = (
    Option<Vec<u8>>,
    Option<Vec<u8>>,
    Option<Vec<u8>>,
    i64,
    i64,
    i64,
);

fn normalize_string_set(values: &[String], max_len: usize) -> Vec<String> {
    let mut set = std::collections::BTreeSet::<String>::new();
    for raw in values {
        let trimmed = raw.trim();
        if trimmed.is_empty() {
            continue;
        }
        set.insert(trimmed.to_string());
        if set.len() >= max_len * 2 {
            break;
        }
    }

    set.into_iter().take(max_len).collect()
}

fn mark_attachment_referencing_messages_needs_embedding(
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

pub fn read_attachment_metadata(
    conn: &Connection,
    key: &[u8; 32],
    attachment_sha256: &str,
) -> Result<Option<AttachmentMetadata>> {
    let row: Option<AttachmentMetadataDbRow> = conn
        .query_row(
            r#"
	SELECT title, filenames, source_urls, title_updated_at_ms, created_at_ms, updated_at_ms
	FROM attachment_metadata
WHERE attachment_sha256 = ?1
"#,
            params![attachment_sha256],
            |row| {
                Ok((
                    row.get(0)?,
                    row.get(1)?,
                    row.get(2)?,
                    row.get(3)?,
                    row.get(4)?,
                    row.get(5)?,
                ))
            },
        )
        .optional()?;

    let Some((
        title_blob,
        filenames_blob,
        source_urls_blob,
        title_updated_at_ms,
        created_at_ms,
        updated_at_ms,
    )) = row
    else {
        return Ok(None);
    };

    let title = match title_blob {
        Some(blob) => {
            let aad = format!("attachment.metadata.title:{attachment_sha256}");
            let bytes = decrypt_bytes(key, &blob, aad.as_bytes())?;
            let s = String::from_utf8(bytes)
                .map_err(|_| anyhow!("attachment metadata title is not valid utf-8"))?;
            let trimmed = s.trim().to_string();
            if trimmed.is_empty() {
                None
            } else {
                Some(trimmed)
            }
        }
        None => None,
    };

    let filenames = match filenames_blob {
        Some(blob) => {
            let aad = format!("attachment.metadata.filenames:{attachment_sha256}");
            let bytes = decrypt_bytes(key, &blob, aad.as_bytes())?;
            serde_json::from_slice::<Vec<String>>(&bytes).unwrap_or_default()
        }
        None => Vec::new(),
    };
    let source_urls = match source_urls_blob {
        Some(blob) => {
            let aad = format!("attachment.metadata.source_urls:{attachment_sha256}");
            let bytes = decrypt_bytes(key, &blob, aad.as_bytes())?;
            serde_json::from_slice::<Vec<String>>(&bytes).unwrap_or_default()
        }
        None => Vec::new(),
    };

    Ok(Some(AttachmentMetadata {
        title,
        filenames,
        source_urls,
        title_updated_at_ms,
        created_at_ms,
        updated_at_ms,
    }))
}

pub fn upsert_attachment_metadata(
    conn: &Connection,
    key: &[u8; 32],
    attachment_sha256: &str,
    title: Option<&str>,
    filenames: &[String],
    source_urls: &[String],
) -> Result<()> {
    backfill_attachments_oplog_if_needed(conn, key)?;

    let attachment_sha256 = attachment_sha256.trim();
    if attachment_sha256.is_empty() {
        return Err(anyhow!("attachment_sha256 is required"));
    }

    let incoming_title = title
        .map(|v| v.trim())
        .filter(|v| !v.is_empty())
        .map(|v| v.to_string());
    let incoming_filenames = normalize_string_set(filenames, 16);
    let incoming_source_urls = normalize_string_set(source_urls, 16);

    if incoming_title.is_none() && incoming_filenames.is_empty() && incoming_source_urls.is_empty()
    {
        return Ok(());
    }

    conn.execute_batch("BEGIN IMMEDIATE;")?;

    let result = (|| -> Result<()> {
        let now = now_ms();

        let existing_row: Option<AttachmentMetadataDbRow> = conn
            .query_row(
                r#"
	SELECT title, filenames, source_urls, title_updated_at_ms, created_at_ms, updated_at_ms
	FROM attachment_metadata
WHERE attachment_sha256 = ?1
"#,
                params![attachment_sha256],
                |row| {
                    Ok((
                        row.get(0)?,
                        row.get(1)?,
                        row.get(2)?,
                        row.get(3)?,
                        row.get(4)?,
                        row.get(5)?,
                    ))
                },
            )
            .optional()?;

        let (
            existing_title_blob,
            existing_filenames_blob,
            existing_source_urls_blob,
            existing_title_updated_at_ms,
            existing_created_at_ms,
            existing_updated_at_ms,
        ) = match existing_row {
            Some(v) => v,
            None => (None, None, None, 0, now, 0),
        };

        let existing_title = match existing_title_blob {
            Some(blob) => {
                let aad = format!("attachment.metadata.title:{attachment_sha256}");
                match decrypt_bytes(key, &blob, aad.as_bytes())
                    .ok()
                    .and_then(|b| String::from_utf8(b).ok())
                {
                    Some(s) => {
                        let trimmed = s.trim().to_string();
                        if trimmed.is_empty() {
                            None
                        } else {
                            Some(trimmed)
                        }
                    }
                    None => None,
                }
            }
            None => None,
        };

        let existing_filenames_raw = match existing_filenames_blob {
            Some(blob) => {
                let aad = format!("attachment.metadata.filenames:{attachment_sha256}");
                match decrypt_bytes(key, &blob, aad.as_bytes()) {
                    Ok(bytes) => serde_json::from_slice::<Vec<String>>(&bytes).unwrap_or_default(),
                    Err(_) => Vec::new(),
                }
            }
            None => Vec::new(),
        };
        let existing_source_urls_raw = match existing_source_urls_blob {
            Some(blob) => {
                let aad = format!("attachment.metadata.source_urls:{attachment_sha256}");
                match decrypt_bytes(key, &blob, aad.as_bytes()) {
                    Ok(bytes) => serde_json::from_slice::<Vec<String>>(&bytes).unwrap_or_default(),
                    Err(_) => Vec::new(),
                }
            }
            None => Vec::new(),
        };

        let existing_filenames = normalize_string_set(&existing_filenames_raw, 16);
        let existing_source_urls = normalize_string_set(&existing_source_urls_raw, 16);

        let mut merged_filenames: Vec<String> = existing_filenames.clone();
        merged_filenames.extend(incoming_filenames.iter().cloned());
        merged_filenames = normalize_string_set(&merged_filenames, 16);

        let mut merged_source_urls: Vec<String> = existing_source_urls.clone();
        merged_source_urls.extend(incoming_source_urls.iter().cloned());
        merged_source_urls = normalize_string_set(&merged_source_urls, 16);

        let mut merged_title = existing_title.clone();
        let mut merged_title_updated_at_ms = existing_title_updated_at_ms;
        let mut title_changed = false;
        if let Some(title) = incoming_title.clone() {
            if now > existing_title_updated_at_ms
                && existing_title.as_deref() != Some(title.as_str())
            {
                merged_title = Some(title);
                merged_title_updated_at_ms = now;
                title_changed = true;
            }
        }

        let changed = title_changed
            || merged_filenames != existing_filenames
            || merged_source_urls != existing_source_urls;
        if !changed {
            return Ok(());
        }

        let title_blob = match merged_title.as_deref() {
            Some(s) => {
                let aad = format!("attachment.metadata.title:{attachment_sha256}");
                Some(encrypt_bytes(key, s.as_bytes(), aad.as_bytes())?)
            }
            None => None,
        };
        let filenames_blob = if merged_filenames.is_empty() {
            None
        } else {
            let json = serde_json::to_vec(&merged_filenames)?;
            let aad = format!("attachment.metadata.filenames:{attachment_sha256}");
            Some(encrypt_bytes(key, &json, aad.as_bytes())?)
        };
        let source_urls_blob = if merged_source_urls.is_empty() {
            None
        } else {
            let json = serde_json::to_vec(&merged_source_urls)?;
            let aad = format!("attachment.metadata.source_urls:{attachment_sha256}");
            Some(encrypt_bytes(key, &json, aad.as_bytes())?)
        };

        conn.execute(
            r#"
INSERT INTO attachment_metadata(
  attachment_sha256,
  title,
  filenames,
  source_urls,
  title_updated_at_ms,
  created_at_ms,
  updated_at_ms
)
VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7)
ON CONFLICT(attachment_sha256) DO UPDATE SET
  title = excluded.title,
  filenames = excluded.filenames,
  source_urls = excluded.source_urls,
  title_updated_at_ms = excluded.title_updated_at_ms,
  created_at_ms = min(attachment_metadata.created_at_ms, excluded.created_at_ms),
  updated_at_ms = max(attachment_metadata.updated_at_ms, excluded.updated_at_ms)
"#,
            params![
                attachment_sha256,
                title_blob,
                filenames_blob,
                source_urls_blob,
                merged_title_updated_at_ms,
                existing_created_at_ms,
                existing_updated_at_ms.max(now)
            ],
        )?;

        let device_id = get_or_create_device_id(conn)?;
        let seq = next_device_seq(conn, &device_id)?;

        let payload_title = if title_changed { merged_title.clone() } else { None };

        let op = serde_json::json!({
            "op_id": uuid::Uuid::new_v4().to_string(),
            "device_id": device_id,
            "seq": seq,
            "ts_ms": now,
            "type": "attachment.metadata.upsert.v1",
            "payload": {
                "attachment_sha256": attachment_sha256,
                "title": payload_title,
                "filenames": incoming_filenames,
                "source_urls": incoming_source_urls,
                "created_at_ms": existing_created_at_ms,
                "updated_at_ms": now,
            }
        });
        insert_oplog(conn, key, &op)?;

        mark_attachment_referencing_messages_needs_embedding(conn, attachment_sha256)?;

        Ok(())
    })();

    match result {
        Ok(()) => {
            conn.execute_batch("COMMIT;")?;
            Ok(())
        }
        Err(e) => {
            let _ = conn.execute_batch("ROLLBACK;");
            Err(e)
        }
    }
}
