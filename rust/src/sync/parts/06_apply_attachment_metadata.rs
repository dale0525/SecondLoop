fn normalize_string_set(values: &[String], max_len: usize) -> Vec<String> {
    let mut set = std::collections::BTreeSet::<String>::new();
    for raw in values {
        let trimmed = raw.trim();
        if trimmed.is_empty() {
            continue;
        }
        set.insert(trimmed.to_string());
        if set.len() >= max_len * 2 {
            // Avoid unbounded growth when ingesting pathological payloads.
            break;
        }
    }

    set.into_iter().take(max_len).collect()
}

type AttachmentMetadataDbRow = (
    Option<Vec<u8>>,
    Option<Vec<u8>>,
    Option<Vec<u8>>,
    i64,
    i64,
    i64,
);

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

fn apply_attachment_metadata_upsert(
    conn: &Connection,
    db_key: &[u8; 32],
    payload: &serde_json::Value,
) -> Result<()> {
    let attachment_sha256 = payload["attachment_sha256"]
        .as_str()
        .ok_or_else(|| anyhow!("attachment metadata op missing attachment_sha256"))?;
    let created_at_ms = payload.get("created_at_ms").and_then(|v| v.as_i64()).unwrap_or(0);
    let updated_at_ms = payload["updated_at_ms"]
        .as_i64()
        .ok_or_else(|| anyhow!("attachment metadata op missing updated_at_ms"))?;

    let incoming_title = payload
        .get("title")
        .and_then(|v| v.as_str())
        .map(|s| s.trim().to_string())
        .filter(|s| !s.is_empty());
    let incoming_filenames = payload
        .get("filenames")
        .and_then(|v| v.as_array())
        .map(|arr| {
            arr.iter()
                .filter_map(|v| v.as_str())
                .map(|s| s.to_string())
                .collect::<Vec<String>>()
        })
        .unwrap_or_default();
    let incoming_source_urls = payload
        .get("source_urls")
        .and_then(|v| v.as_array())
        .map(|arr| {
            arr.iter()
                .filter_map(|v| v.as_str())
                .map(|s| s.to_string())
                .collect::<Vec<String>>()
        })
        .unwrap_or_default();

    let existing: Option<AttachmentMetadataDbRow> = conn
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
        existing_title,
        existing_filenames,
        existing_source_urls,
        existing_title_updated_at_ms,
        existing_created_at_ms,
        existing_updated_at_ms,
    ) = match existing {
        Some(v) => v,
        None => (None, None, None, 0, i64::MAX, 0),
    };

    let existing_title = match existing_title {
        Some(blob) => {
            let aad = format!("attachment.metadata.title:{attachment_sha256}");
            let bytes = decrypt_bytes(db_key, &blob, aad.as_bytes()).unwrap_or_default();
            let s = String::from_utf8(bytes).unwrap_or_default();
            let trimmed = s.trim().to_string();
            if trimmed.is_empty() {
                None
            } else {
                Some(trimmed)
            }
        }
        None => None,
    };

    let existing_filenames = match existing_filenames {
        Some(blob) => {
            let aad = format!("attachment.metadata.filenames:{attachment_sha256}");
            let bytes = decrypt_bytes(db_key, &blob, aad.as_bytes()).unwrap_or_default();
            serde_json::from_slice::<Vec<String>>(&bytes).unwrap_or_default()
        }
        None => Vec::new(),
    };
    let existing_source_urls = match existing_source_urls {
        Some(blob) => {
            let aad = format!("attachment.metadata.source_urls:{attachment_sha256}");
            let bytes = decrypt_bytes(db_key, &blob, aad.as_bytes()).unwrap_or_default();
            serde_json::from_slice::<Vec<String>>(&bytes).unwrap_or_default()
        }
        None => Vec::new(),
    };

    let mut merged_filenames: Vec<String> = existing_filenames;
    merged_filenames.extend(incoming_filenames);
    merged_filenames = normalize_string_set(&merged_filenames, 16);

    let mut merged_source_urls: Vec<String> = existing_source_urls;
    merged_source_urls.extend(incoming_source_urls);
    merged_source_urls = normalize_string_set(&merged_source_urls, 16);

    let (merged_title, merged_title_updated_at_ms) = if let Some(title) = incoming_title {
        if updated_at_ms > existing_title_updated_at_ms {
            (Some(title), updated_at_ms)
        } else {
            (existing_title, existing_title_updated_at_ms)
        }
    } else {
        (existing_title, existing_title_updated_at_ms)
    };

    let next_created_at_ms = existing_created_at_ms.min(created_at_ms);
    let next_created_at_ms = if next_created_at_ms == i64::MAX {
        created_at_ms
    } else {
        next_created_at_ms
    };
    let next_updated_at_ms = existing_updated_at_ms.max(updated_at_ms);

    let title_blob = match merged_title.as_deref() {
        Some(s) => {
            let aad = format!("attachment.metadata.title:{attachment_sha256}");
            Some(encrypt_bytes(db_key, s.as_bytes(), aad.as_bytes())?)
        }
        None => None,
    };
    let filenames_blob = if merged_filenames.is_empty() {
        None
    } else {
        let json = serde_json::to_vec(&merged_filenames)?;
        let aad = format!("attachment.metadata.filenames:{attachment_sha256}");
        Some(encrypt_bytes(db_key, &json, aad.as_bytes())?)
    };
    let source_urls_blob = if merged_source_urls.is_empty() {
        None
    } else {
        let json = serde_json::to_vec(&merged_source_urls)?;
        let aad = format!("attachment.metadata.source_urls:{attachment_sha256}");
        Some(encrypt_bytes(db_key, &json, aad.as_bytes())?)
    };

    let attachment_exists: Option<i64> = conn
        .query_row(
            r#"SELECT 1 FROM attachments WHERE sha256 = ?1"#,
            params![attachment_sha256],
            |row| row.get(0),
        )
        .optional()?;
    if attachment_exists.is_none() {
        conn.execute_batch("PRAGMA foreign_keys = OFF;")?;
    }

    let insert_result = conn.execute(
        r#"
INSERT INTO attachment_metadata(
  attachment_sha256, title, filenames, source_urls, title_updated_at_ms, created_at_ms, updated_at_ms
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
            next_created_at_ms,
            next_updated_at_ms
        ],
    );

    if attachment_exists.is_none() {
        let _ = conn.execute_batch("PRAGMA foreign_keys = ON;");
    }

    insert_result?;

    mark_attachment_referencing_messages_needs_embedding(conn, attachment_sha256)?;

    Ok(())
}
