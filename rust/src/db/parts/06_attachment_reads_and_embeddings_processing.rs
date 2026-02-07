pub fn read_attachment_place_display_name(
    conn: &Connection,
    key: &[u8; 32],
    attachment_sha256: &str,
) -> Result<Option<String>> {
    read_attachment_place_display_name_optional(conn, key, attachment_sha256)
}

fn read_attachment_annotation_caption_long_optional(
    conn: &Connection,
    key: &[u8; 32],
    attachment_sha256: &str,
) -> Result<Option<String>> {
    let row: Option<(String, Vec<u8>)> = conn
        .query_row(
            r#"SELECT lang, payload
               FROM attachment_annotations
               WHERE attachment_sha256 = ?1
                 AND status = 'ok'
                 AND payload IS NOT NULL"#,
            params![attachment_sha256],
            |row| Ok((row.get(0)?, row.get(1)?)),
        )
        .optional()?;

    let Some((lang, payload_blob)) = row else {
        return Ok(None);
    };

    let aad = format!("attachment.annotation:{attachment_sha256}:{lang}");
    let json = match decrypt_bytes(key, &payload_blob, aad.as_bytes()) {
        Ok(v) => v,
        Err(_) => return Ok(None),
    };

    let payload: serde_json::Value = match serde_json::from_slice(&json) {
        Ok(v) => v,
        Err(_) => return Ok(None),
    };

    let caption_long = payload
        .get("caption_long")
        .and_then(|v| v.as_str())
        .unwrap_or_default()
        .trim();

    if caption_long.is_empty() {
        return Ok(None);
    }

    Ok(Some(caption_long.to_string()))
}

fn read_attachment_annotation_excerpt_optional(
    conn: &Connection,
    key: &[u8; 32],
    attachment_sha256: &str,
) -> Result<Option<String>> {
    let row: Option<(String, Vec<u8>)> = conn
        .query_row(
            r#"SELECT lang, payload
               FROM attachment_annotations
               WHERE attachment_sha256 = ?1
                 AND status = 'ok'
                 AND payload IS NOT NULL"#,
            params![attachment_sha256],
            |row| Ok((row.get(0)?, row.get(1)?)),
        )
        .optional()?;

    let Some((lang, payload_blob)) = row else {
        return Ok(None);
    };

    let aad = format!("attachment.annotation:{attachment_sha256}:{lang}");
    let json = match decrypt_bytes(key, &payload_blob, aad.as_bytes()) {
        Ok(v) => v,
        Err(_) => return Ok(None),
    };

    let payload: serde_json::Value = match serde_json::from_slice(&json) {
        Ok(v) => v,
        Err(_) => return Ok(None),
    };

    let extracted_excerpt = payload_str_trimmed(&payload, "extracted_text_excerpt");
    let extracted_full = payload_str_trimmed(&payload, "extracted_text_full");
    let extracted = extracted_excerpt.or(extracted_full);

    let readable_excerpt = payload_str_trimmed(&payload, "readable_text_excerpt");
    let readable_full = payload_str_trimmed(&payload, "readable_text_full");
    let readable = readable_excerpt.or(readable_full);

    let ocr_excerpt = payload_str_trimmed(&payload, "ocr_text_excerpt");
    let ocr_full = payload_str_trimmed(&payload, "ocr_text_full");
    let ocr = ocr_excerpt.or(ocr_full);

    let prefer_ocr = match (ocr, extracted) {
        (Some(_), Some(extracted_text)) => looks_degraded_ascii_text(extracted_text),
        _ => false,
    };

    let document_excerpt = if prefer_ocr {
        ocr.or(readable).or(extracted)
    } else {
        extracted.or(readable).or(ocr)
    };

    let excerpt = document_excerpt
        .or_else(|| payload_str_trimmed(&payload, "transcript_excerpt"))
        .or_else(|| payload_str_trimmed(&payload, "transcript_full"))
        .unwrap_or_default();

    if excerpt.is_empty() {
        return Ok(None);
    }

    Ok(Some(excerpt.to_string()))
}

fn payload_str_trimmed<'a>(payload: &'a serde_json::Value, key: &str) -> Option<&'a str> {
    payload
        .get(key)
        .and_then(|v| v.as_str())
        .map(str::trim)
        .filter(|v| !v.is_empty())
}

fn looks_degraded_ascii_text(raw: &str) -> bool {
    let normalized = raw.split_whitespace().collect::<Vec<_>>().join(" ");
    if normalized.chars().count() < 24 {
        return false;
    }

    let mut meaningful_count = 0usize;
    let mut non_space_count = 0usize;
    let mut noisy_count = 0usize;
    for ch in normalized.chars() {
        if ch.is_whitespace() {
            continue;
        }
        non_space_count += 1;
        if is_meaningful_char(ch) {
            meaningful_count += 1;
        } else {
            noisy_count += 1;
        }
    }
    if meaningful_count == 0 {
        return false;
    }

    let mut considered = 0usize;
    let mut single_char_tokens = 0usize;
    let mut total_len = 0usize;
    for token in normalized.split_whitespace() {
        let meaningful_len = token.chars().filter(|c| is_meaningful_char(*c)).count();
        if meaningful_len == 0 {
            continue;
        }
        considered += 1;
        total_len += meaningful_len;
        if meaningful_len == 1 {
            single_char_tokens += 1;
        }
    }

    if considered < 8 {
        return false;
    }

    let single_ratio = single_char_tokens as f64 / considered as f64;
    let avg_len = total_len as f64 / considered as f64;
    let noisy_ratio = if non_space_count == 0 {
        0.0
    } else {
        noisy_count as f64 / non_space_count as f64
    };

    if single_ratio >= 0.5 {
        return true;
    }
    if avg_len < 1.8 {
        return true;
    }
    if meaningful_count >= 20 && noisy_ratio > 0.45 {
        return true;
    }
    if considered >= 12 && single_ratio >= 0.4 && noisy_ratio > 0.2 {
        return true;
    }
    false
}

fn is_meaningful_char(ch: char) -> bool {
    ch.is_alphanumeric() || matches!(ch, '_')
}

pub fn read_attachment_annotation_caption_long(
    conn: &Connection,
    key: &[u8; 32],
    attachment_sha256: &str,
) -> Result<Option<String>> {
    read_attachment_annotation_caption_long_optional(conn, key, attachment_sha256)
}

fn build_message_embedding_plaintext(
    conn: &Connection,
    key: &[u8; 32],
    message_id: &str,
    content: &str,
) -> Result<String> {
    let mut out = format!("passage: {content}");

    let include_image_caption = kv_get_string(conn, "media_annotation.search_enabled")?
        .unwrap_or_else(|| "0".to_string())
        .trim()
        == "1";

    let mut stmt = conn.prepare(
        r#"SELECT attachment_sha256
           FROM message_attachments
           WHERE message_id = ?1
           ORDER BY created_at ASC"#,
    )?;
    let mut rows = stmt.query(params![message_id])?;

    let mut extra = String::new();
    while let Some(row) = rows.next()? {
        let attachment_sha256: String = row.get(0)?;

        if let Some(display_name) =
            read_attachment_place_display_name_optional(conn, key, &attachment_sha256)?
        {
            extra.push_str("\nlocation: ");
            extra.push_str(&display_name);
        }

        if let Some(meta) = read_attachment_metadata(conn, key, &attachment_sha256)? {
            let name = meta
                .title
                .filter(|s| !s.trim().is_empty())
                .or_else(|| meta.filenames.first().cloned());
            if let Some(name) = name {
                extra.push_str("\nattachment: ");
                extra.push_str(&name);
            }
        }

        if include_image_caption {
            if let Some(caption_long) =
                read_attachment_annotation_caption_long_optional(conn, key, &attachment_sha256)?
            {
                extra.push_str("\nimage_caption: ");
                extra.push_str(&caption_long);
            }
        }

        if let Some(excerpt) =
            read_attachment_annotation_excerpt_optional(conn, key, &attachment_sha256)?
        {
            extra.push_str("\nattachment_excerpt: ");
            extra.push_str(&excerpt);
        }

        if extra.len() > MAX_ATTACHMENT_ENRICHMENT_CHARS {
            break;
        }
    }

    let extra = truncate_utf8_to_max_bytes(&extra, MAX_ATTACHMENT_ENRICHMENT_CHARS);
    if !extra.trim().is_empty() {
        out.push_str(extra);
    }

    Ok(out)
}

pub fn build_message_rag_context(
    conn: &Connection,
    key: &[u8; 32],
    message_id: &str,
    content: &str,
) -> Result<String> {
    let enriched = build_message_embedding_plaintext(conn, key, message_id, content)?;
    let without_prefix = enriched.strip_prefix("passage: ").unwrap_or(&enriched);
    Ok(without_prefix.trim().to_string())
}

pub fn process_pending_message_embeddings<E: Embedder + ?Sized>(
    conn: &Connection,
    key: &[u8; 32],
    embedder: &E,
    limit: usize,
) -> Result<usize> {
    let expected_dim = current_embedding_dim(conn)?;
    let space_id = embedding_space_id(embedder.model_name(), expected_dim)?;
    ensure_vec_tables_for_space(conn, &space_id, expected_dim)?;
    let message_table = message_embeddings_table(&space_id)?;
    let update_sql = format!(
        r#"UPDATE "{message_table}"
           SET embedding = ?2, message_id = ?3, model_name = ?4
           WHERE rowid = ?1"#
    );
    let insert_sql = format!(
        r#"INSERT INTO "{message_table}"(rowid, embedding, message_id, model_name)
           VALUES (?1, ?2, ?3, ?4)"#
    );

    let mut stmt = conn.prepare(
        r#"SELECT rowid, id, content
           FROM messages
           WHERE COALESCE(needs_embedding, 1) = 1
             AND COALESCE(is_deleted, 0) = 0
             AND COALESCE(is_memory, 1) = 1
           ORDER BY created_at ASC
           LIMIT ?1"#,
    )?;

    let mut rows = stmt.query(params![i64::try_from(limit).unwrap_or(i64::MAX)])?;
    let mut message_rowids: Vec<i64> = Vec::new();
    let mut message_ids: Vec<String> = Vec::new();
    let mut plaintexts: Vec<String> = Vec::new();

    while let Some(row) = rows.next()? {
        let rowid: i64 = row.get(0)?;
        let id: String = row.get(1)?;
        let content_blob: Vec<u8> = row.get(2)?;

        let content_bytes = decrypt_bytes(key, &content_blob, b"message.content")?;
        let content = String::from_utf8(content_bytes)
            .map_err(|_| anyhow!("message content is not valid utf-8"))?;

        message_rowids.push(rowid);
        message_ids.push(id);
        plaintexts.push(build_message_embedding_plaintext(
            conn,
            key,
            message_ids.last().expect("message_ids non-empty"),
            &content,
        )?);
    }

    if plaintexts.is_empty() {
        return Ok(0);
    }

    let embeddings = embedder.embed(&plaintexts)?;
    if embeddings.len() != plaintexts.len() {
        return Err(anyhow!(
            "embedder output length mismatch: expected {}, got {}",
            plaintexts.len(),
            embeddings.len()
        ));
    }
    for embedding in &embeddings {
        if embedding.len() != expected_dim {
            return Err(anyhow!(
                "embedder dim mismatch: expected {expected_dim}, got {} (model_name={})",
                embedding.len(),
                embedder.model_name()
            ));
        }
    }

    for i in 0..message_ids.len() {
        let updated = conn.execute(
            &update_sql,
            params![
                message_rowids[i],
                embeddings[i].as_bytes(),
                message_ids[i],
                embedder.model_name()
            ],
        )?;
        if updated == 0 {
            conn.execute(
                &insert_sql,
                params![
                    message_rowids[i],
                    embeddings[i].as_bytes(),
                    message_ids[i],
                    embedder.model_name()
                ],
            )?;
        }
        conn.execute(
            r#"UPDATE messages SET needs_embedding = 0 WHERE rowid = ?1"#,
            params![message_rowids[i]],
        )?;
    }

    Ok(message_ids.len())
}

pub fn process_pending_todo_embeddings<E: Embedder + ?Sized>(
    conn: &Connection,
    key: &[u8; 32],
    embedder: &E,
    limit: usize,
) -> Result<usize> {
    let expected_dim = current_embedding_dim(conn)?;
    let space_id = embedding_space_id(embedder.model_name(), expected_dim)?;
    ensure_vec_tables_for_space(conn, &space_id, expected_dim)?;
    let todo_table = todo_embeddings_table(&space_id)?;
    let update_sql = format!(
        r#"UPDATE "{todo_table}"
           SET embedding = ?2, todo_id = ?3, model_name = ?4
           WHERE rowid = ?1"#
    );
    let insert_sql = format!(
        r#"INSERT INTO "{todo_table}"(rowid, embedding, todo_id, model_name)
           VALUES (?1, ?2, ?3, ?4)"#
    );

    let mut stmt = conn.prepare(
        r#"SELECT rowid, id, title, status, due_at_ms
           FROM todos
           WHERE COALESCE(needs_embedding, 1) = 1
             AND status != 'dismissed'
           ORDER BY updated_at_ms ASC
           LIMIT ?1"#,
    )?;

    let mut rows = stmt.query(params![i64::try_from(limit).unwrap_or(i64::MAX)])?;
    let mut todo_rowids: Vec<i64> = Vec::new();
    let mut todo_ids: Vec<String> = Vec::new();
    let mut plaintexts: Vec<String> = Vec::new();

    while let Some(row) = rows.next()? {
        let rowid: i64 = row.get(0)?;
        let id: String = row.get(1)?;
        let title_blob: Vec<u8> = row.get(2)?;
        let status: String = row.get(3)?;
        let due_at_ms: Option<i64> = row.get(4)?;

        let title_bytes = decrypt_bytes(key, &title_blob, b"todo.title")?;
        let title =
            String::from_utf8(title_bytes).map_err(|_| anyhow!("todo title is not valid utf-8"))?;

        let mut text = format!("TODO [{status}] {title}");
        if let Some(ms) = due_at_ms {
            text.push_str(&format!(" (due_at_ms={ms})"));
        }

        todo_rowids.push(rowid);
        todo_ids.push(id);
        plaintexts.push(format!("passage: {text}"));
    }

    if plaintexts.is_empty() {
        return Ok(0);
    }

    let embeddings = embedder.embed(&plaintexts)?;
    if embeddings.len() != plaintexts.len() {
        return Err(anyhow!(
            "embedder output length mismatch: expected {}, got {}",
            plaintexts.len(),
            embeddings.len()
        ));
    }
    for embedding in &embeddings {
        if embedding.len() != expected_dim {
            return Err(anyhow!(
                "embedder dim mismatch: expected {expected_dim}, got {} (model_name={})",
                embedding.len(),
                embedder.model_name()
            ));
        }
    }

    for i in 0..todo_ids.len() {
        let updated = conn.execute(
            &update_sql,
            params![
                todo_rowids[i],
                embeddings[i].as_bytes(),
                todo_ids[i],
                embedder.model_name()
            ],
        )?;
        if updated == 0 {
            conn.execute(
                &insert_sql,
                params![
                    todo_rowids[i],
                    embeddings[i].as_bytes(),
                    todo_ids[i],
                    embedder.model_name()
                ],
            )?;
        }

        conn.execute(
            r#"UPDATE todos SET needs_embedding = 0 WHERE rowid = ?1"#,
            params![todo_rowids[i]],
        )?;
    }

    Ok(todo_ids.len())
}

fn status_embedding_hint(status: &str) -> String {
    match status {
        "inbox" => "inbox needs confirmation not started 待确认 未开始".to_string(),
        "in_progress" => "in_progress doing ongoing 进行中".to_string(),
        "done" => "done completed finished 完成 已完成".to_string(),
        "dismissed" => "dismissed deleted removed 已删除".to_string(),
        _ => status.to_string(),
    }
}

pub fn process_pending_todo_activity_embeddings<E: Embedder + ?Sized>(
    conn: &Connection,
    key: &[u8; 32],
    embedder: &E,
    limit: usize,
) -> Result<usize> {
    let expected_dim = current_embedding_dim(conn)?;
    let space_id = embedding_space_id(embedder.model_name(), expected_dim)?;
    ensure_vec_tables_for_space(conn, &space_id, expected_dim)?;
    let activity_table = todo_activity_embeddings_table(&space_id)?;
    let update_sql = format!(
        r#"UPDATE "{activity_table}"
           SET embedding = ?2, activity_id = ?3, todo_id = ?4, model_name = ?5
           WHERE rowid = ?1"#
    );
    let insert_sql = format!(
        r#"INSERT INTO "{activity_table}"(rowid, embedding, activity_id, todo_id, model_name)
           VALUES (?1, ?2, ?3, ?4, ?5)"#
    );

    let mut stmt = conn.prepare(
        r#"SELECT a.rowid, a.id, a.todo_id, a.type, a.from_status, a.to_status, a.content
           FROM todo_activities a
           LEFT JOIN todos t ON t.id = a.todo_id
           WHERE COALESCE(a.needs_embedding, 1) = 1
             AND (t.status IS NULL OR t.status != 'dismissed')
           ORDER BY a.created_at_ms ASC
           LIMIT ?1"#,
    )?;

    let mut rows = stmt.query(params![i64::try_from(limit).unwrap_or(i64::MAX)])?;
    let mut activity_rowids: Vec<i64> = Vec::new();
    let mut activity_ids: Vec<String> = Vec::new();
    let mut todo_ids: Vec<String> = Vec::new();
    let mut plaintexts: Vec<String> = Vec::new();

    while let Some(row) = rows.next()? {
        let rowid: i64 = row.get(0)?;
        let id: String = row.get(1)?;
        let todo_id: String = row.get(2)?;
        let activity_type: String = row.get(3)?;
        let from_status: Option<String> = row.get(4)?;
        let to_status: Option<String> = row.get(5)?;
        let content_blob: Option<Vec<u8>> = row.get(6)?;

        let content = if let Some(blob) = content_blob {
            let aad = format!("todo_activity.content:{id}");
            let bytes = decrypt_bytes(key, &blob, aad.as_bytes())?;
            Some(
                String::from_utf8(bytes)
                    .map_err(|_| anyhow!("todo activity content is not valid utf-8"))?,
            )
        } else {
            None
        };

        let text =
            if let Some(content) = content.as_deref().map(str::trim).filter(|s| !s.is_empty()) {
                format!("TODO activity note: {content}")
            } else if activity_type == "status_change" {
                let from = from_status.as_deref().unwrap_or("unknown");
                let to = to_status.as_deref().unwrap_or("unknown");
                format!(
                    "TODO status changed from {} to {}",
                    status_embedding_hint(from),
                    status_embedding_hint(to)
                )
            } else {
                format!("TODO activity {activity_type}")
            };

        activity_rowids.push(rowid);
        activity_ids.push(id);
        todo_ids.push(todo_id);
        plaintexts.push(format!("passage: {text}"));
    }

    if plaintexts.is_empty() {
        return Ok(0);
    }

    let embeddings = embedder.embed(&plaintexts)?;
    if embeddings.len() != plaintexts.len() {
        return Err(anyhow!(
            "embedder output length mismatch: expected {}, got {}",
            plaintexts.len(),
            embeddings.len()
        ));
    }
    for embedding in &embeddings {
        if embedding.len() != expected_dim {
            return Err(anyhow!(
                "embedder dim mismatch: expected {expected_dim}, got {} (model_name={})",
                embedding.len(),
                embedder.model_name()
            ));
        }
    }

    for i in 0..activity_ids.len() {
        let updated = conn.execute(
            &update_sql,
            params![
                activity_rowids[i],
                embeddings[i].as_bytes(),
                activity_ids[i],
                todo_ids[i],
                embedder.model_name()
            ],
        )?;
        if updated == 0 {
            conn.execute(
                &insert_sql,
                params![
                    activity_rowids[i],
                    embeddings[i].as_bytes(),
                    activity_ids[i],
                    todo_ids[i],
                    embedder.model_name()
                ],
            )?;
        }
        conn.execute(
            r#"UPDATE todo_activities SET needs_embedding = 0 WHERE rowid = ?1"#,
            params![activity_rowids[i]],
        )?;
    }

    Ok(activity_ids.len())
}

pub fn process_pending_message_embeddings_default(
    conn: &Connection,
    key: &[u8; 32],
    limit: usize,
) -> Result<usize> {
    let space_id = embedding_space_id(crate::embedding::DEFAULT_MODEL_NAME, DEFAULT_EMBEDDING_DIM)?;
    ensure_vec_tables_for_space(conn, &space_id, DEFAULT_EMBEDDING_DIM)?;
    let message_table = message_embeddings_table(&space_id)?;
    let update_sql = format!(
        r#"UPDATE "{message_table}"
           SET embedding = ?2, message_id = ?3, model_name = ?4
           WHERE rowid = ?1"#
    );
    let insert_sql = format!(
        r#"INSERT INTO "{message_table}"(rowid, embedding, message_id, model_name)
           VALUES (?1, ?2, ?3, ?4)"#
    );

    let mut stmt = conn.prepare(
        r#"SELECT rowid, id, content
           FROM messages
           WHERE COALESCE(needs_embedding, 1) = 1
             AND COALESCE(is_deleted, 0) = 0
             AND COALESCE(is_memory, 1) = 1
           ORDER BY created_at ASC
           LIMIT ?1"#,
    )?;

    let mut rows = stmt.query(params![i64::try_from(limit).unwrap_or(i64::MAX)])?;
    let mut message_rowids: Vec<i64> = Vec::new();
    let mut message_ids: Vec<String> = Vec::new();
    let mut plaintexts: Vec<String> = Vec::new();

    while let Some(row) = rows.next()? {
        let rowid: i64 = row.get(0)?;
        let id: String = row.get(1)?;
        let content_blob: Vec<u8> = row.get(2)?;

        let content_bytes = decrypt_bytes(key, &content_blob, b"message.content")?;
        let content = String::from_utf8(content_bytes)
            .map_err(|_| anyhow!("message content is not valid utf-8"))?;

        message_rowids.push(rowid);
        message_ids.push(id);
        plaintexts.push(build_message_embedding_plaintext(
            conn,
            key,
            message_ids.last().expect("message_ids non-empty"),
            &content,
        )?);
    }

    if plaintexts.is_empty() {
        return Ok(0);
    }

    for i in 0..message_ids.len() {
        let embedding = default_embed_text(&plaintexts[i]);
        if embedding.len() != DEFAULT_EMBEDDING_DIM {
            return Err(anyhow!(
                "default embed dim mismatch: expected {}, got {}",
                DEFAULT_EMBEDDING_DIM,
                embedding.len()
            ));
        }

        let updated = conn.execute(
            &update_sql,
            params![
                message_rowids[i],
                embedding.as_bytes(),
                message_ids[i],
                crate::embedding::DEFAULT_MODEL_NAME
            ],
        )?;
        if updated == 0 {
            conn.execute(
                &insert_sql,
                params![
                    message_rowids[i],
                    embedding.as_bytes(),
                    message_ids[i],
                    crate::embedding::DEFAULT_MODEL_NAME
                ],
            )?;
        }
        conn.execute(
            r#"UPDATE messages SET needs_embedding = 0 WHERE rowid = ?1"#,
            params![message_rowids[i]],
        )?;
    }

    Ok(message_ids.len())
}

pub fn process_pending_todo_embeddings_default(
    conn: &Connection,
    key: &[u8; 32],
    limit: usize,
) -> Result<usize> {
    let space_id = embedding_space_id(crate::embedding::DEFAULT_MODEL_NAME, DEFAULT_EMBEDDING_DIM)?;
    ensure_vec_tables_for_space(conn, &space_id, DEFAULT_EMBEDDING_DIM)?;
    let todo_table = todo_embeddings_table(&space_id)?;
    let update_sql = format!(
        r#"UPDATE "{todo_table}"
           SET embedding = ?2, todo_id = ?3, model_name = ?4
           WHERE rowid = ?1"#
    );
    let insert_sql = format!(
        r#"INSERT INTO "{todo_table}"(rowid, embedding, todo_id, model_name)
           VALUES (?1, ?2, ?3, ?4)"#
    );

    let mut stmt = conn.prepare(
        r#"SELECT rowid, id, title, status, due_at_ms
           FROM todos
           WHERE COALESCE(needs_embedding, 1) = 1
             AND status != 'dismissed'
           ORDER BY updated_at_ms ASC
           LIMIT ?1"#,
    )?;

    let mut rows = stmt.query(params![i64::try_from(limit).unwrap_or(i64::MAX)])?;
    let mut todo_rowids: Vec<i64> = Vec::new();
    let mut todo_ids: Vec<String> = Vec::new();
    let mut plaintexts: Vec<String> = Vec::new();

    while let Some(row) = rows.next()? {
        let rowid: i64 = row.get(0)?;
        let id: String = row.get(1)?;
        let title_blob: Vec<u8> = row.get(2)?;
        let status: String = row.get(3)?;
        let due_at_ms: Option<i64> = row.get(4)?;

        let title_bytes = decrypt_bytes(key, &title_blob, b"todo.title")?;
        let title =
            String::from_utf8(title_bytes).map_err(|_| anyhow!("todo title is not valid utf-8"))?;

        let mut text = format!("TODO [{status}] {title}");
        if let Some(ms) = due_at_ms {
            text.push_str(&format!(" (due_at_ms={ms})"));
        }

        todo_rowids.push(rowid);
        todo_ids.push(id);
        plaintexts.push(format!("passage: {text}"));
    }

    if plaintexts.is_empty() {
        return Ok(0);
    }

    for i in 0..todo_ids.len() {
        let embedding = default_embed_text(&plaintexts[i]);
        if embedding.len() != DEFAULT_EMBEDDING_DIM {
            return Err(anyhow!(
                "default embed dim mismatch: expected {}, got {}",
                DEFAULT_EMBEDDING_DIM,
                embedding.len()
            ));
        }

        let updated = conn.execute(
            &update_sql,
            params![
                todo_rowids[i],
                embedding.as_bytes(),
                todo_ids[i],
                crate::embedding::DEFAULT_MODEL_NAME
            ],
        )?;
        if updated == 0 {
            conn.execute(
                &insert_sql,
                params![
                    todo_rowids[i],
                    embedding.as_bytes(),
                    todo_ids[i],
                    crate::embedding::DEFAULT_MODEL_NAME
                ],
            )?;
        }

        conn.execute(
            r#"UPDATE todos SET needs_embedding = 0 WHERE rowid = ?1"#,
            params![todo_rowids[i]],
        )?;
    }

    Ok(todo_ids.len())
}

pub fn process_pending_todo_activity_embeddings_default(
    conn: &Connection,
    key: &[u8; 32],
    limit: usize,
) -> Result<usize> {
    let space_id = embedding_space_id(crate::embedding::DEFAULT_MODEL_NAME, DEFAULT_EMBEDDING_DIM)?;
    ensure_vec_tables_for_space(conn, &space_id, DEFAULT_EMBEDDING_DIM)?;
    let activity_table = todo_activity_embeddings_table(&space_id)?;
    let update_sql = format!(
        r#"UPDATE "{activity_table}"
           SET embedding = ?2, activity_id = ?3, todo_id = ?4, model_name = ?5
           WHERE rowid = ?1"#
    );
    let insert_sql = format!(
        r#"INSERT INTO "{activity_table}"(rowid, embedding, activity_id, todo_id, model_name)
           VALUES (?1, ?2, ?3, ?4, ?5)"#
    );

    let mut stmt = conn.prepare(
        r#"SELECT a.rowid, a.id, a.todo_id, a.type, a.from_status, a.to_status, a.content
           FROM todo_activities a
           LEFT JOIN todos t ON t.id = a.todo_id
           WHERE COALESCE(a.needs_embedding, 1) = 1
             AND (t.status IS NULL OR t.status != 'dismissed')
           ORDER BY a.created_at_ms ASC
           LIMIT ?1"#,
    )?;

    let mut rows = stmt.query(params![i64::try_from(limit).unwrap_or(i64::MAX)])?;
    let mut activity_rowids: Vec<i64> = Vec::new();
    let mut activity_ids: Vec<String> = Vec::new();
    let mut todo_ids: Vec<String> = Vec::new();
    let mut plaintexts: Vec<String> = Vec::new();

    while let Some(row) = rows.next()? {
        let rowid: i64 = row.get(0)?;
        let id: String = row.get(1)?;
        let todo_id: String = row.get(2)?;
        let activity_type: String = row.get(3)?;
        let from_status: Option<String> = row.get(4)?;
        let to_status: Option<String> = row.get(5)?;
        let content_blob: Option<Vec<u8>> = row.get(6)?;

        let content = if let Some(blob) = content_blob {
            let aad = format!("todo_activity.content:{id}");
            let bytes = decrypt_bytes(key, &blob, aad.as_bytes())?;
            Some(
                String::from_utf8(bytes)
                    .map_err(|_| anyhow!("todo activity content is not valid utf-8"))?,
            )
        } else {
            None
        };

        let text =
            if let Some(content) = content.as_deref().map(str::trim).filter(|s| !s.is_empty()) {
                format!("TODO activity note: {content}")
            } else if activity_type == "status_change" {
                let from = from_status.as_deref().unwrap_or("unknown");
                let to = to_status.as_deref().unwrap_or("unknown");
                format!(
                    "TODO status changed from {} to {}",
                    status_embedding_hint(from),
                    status_embedding_hint(to)
                )
            } else {
                format!("TODO activity {activity_type}")
            };

        activity_rowids.push(rowid);
        activity_ids.push(id);
        todo_ids.push(todo_id);
        plaintexts.push(format!("passage: {text}"));
    }

    if plaintexts.is_empty() {
        return Ok(0);
    }

    for i in 0..activity_ids.len() {
        let embedding = default_embed_text(&plaintexts[i]);
        if embedding.len() != DEFAULT_EMBEDDING_DIM {
            return Err(anyhow!(
                "default embed dim mismatch: expected {}, got {}",
                DEFAULT_EMBEDDING_DIM,
                embedding.len()
            ));
        }

        let updated = conn.execute(
            &update_sql,
            params![
                activity_rowids[i],
                embedding.as_bytes(),
                activity_ids[i],
                todo_ids[i],
                crate::embedding::DEFAULT_MODEL_NAME
            ],
        )?;
        if updated == 0 {
            conn.execute(
                &insert_sql,
                params![
                    activity_rowids[i],
                    embedding.as_bytes(),
                    activity_ids[i],
                    todo_ids[i],
                    crate::embedding::DEFAULT_MODEL_NAME
                ],
            )?;
        }

        conn.execute(
            r#"UPDATE todo_activities SET needs_embedding = 0 WHERE rowid = ?1"#,
            params![activity_rowids[i]],
        )?;
    }

    Ok(activity_ids.len())
}

pub fn rebuild_message_embeddings<E: Embedder + ?Sized>(
    conn: &Connection,
    key: &[u8; 32],
    embedder: &E,
    batch_limit: usize,
) -> Result<usize> {
    let expected_dim = current_embedding_dim(conn)?;
    let space_id = embedding_space_id(embedder.model_name(), expected_dim)?;
    ensure_vec_tables_for_space(conn, &space_id, expected_dim)?;
    let message_table = message_embeddings_table(&space_id)?;

    conn.execute_batch(&format!(
        r#"
BEGIN;
DELETE FROM "{message_table}";
UPDATE messages
SET needs_embedding = CASE
  WHEN COALESCE(is_deleted, 0) = 0 AND COALESCE(is_memory, 1) = 1 THEN 1
  ELSE 0
END;
COMMIT;
"#
    ))?;

    let batch_limit = batch_limit.max(1);
    let mut total = 0usize;
    loop {
        let processed = process_pending_message_embeddings(conn, key, embedder, batch_limit)?;
        total += processed;
        if processed == 0 {
            break;
        }
    }

    Ok(total)
}

pub fn rebuild_message_embeddings_default(
    conn: &Connection,
    key: &[u8; 32],
    batch_limit: usize,
) -> Result<usize> {
    let space_id = embedding_space_id(crate::embedding::DEFAULT_MODEL_NAME, DEFAULT_EMBEDDING_DIM)?;
    ensure_vec_tables_for_space(conn, &space_id, DEFAULT_EMBEDDING_DIM)?;
    let message_table = message_embeddings_table(&space_id)?;

    conn.execute_batch(&format!(
        r#"
BEGIN;
DELETE FROM "{message_table}";
UPDATE messages
SET needs_embedding = CASE
  WHEN COALESCE(is_deleted, 0) = 0 AND COALESCE(is_memory, 1) = 1 THEN 1
  ELSE 0
END;
COMMIT;
"#
    ))?;

    let batch_limit = batch_limit.max(1);
    let mut total = 0usize;
    loop {
        let processed = process_pending_message_embeddings_default(conn, key, batch_limit)?;
        total += processed;
        if processed == 0 {
            break;
        }
    }

    Ok(total)
}
