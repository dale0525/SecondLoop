const ATTACHMENT_CHUNK_MAX_CHARS: usize = 420;
const ATTACHMENT_CHUNK_OVERLAP_CHARS: usize = 80;

fn payload_non_empty_string(payload: &serde_json::Value, key: &str) -> Option<String> {
    payload
        .get(key)
        .and_then(|v| v.as_str())
        .map(str::trim)
        .filter(|v| !v.is_empty())
        .map(std::string::ToString::to_string)
}

fn select_attachment_chunk_source(payload: &serde_json::Value) -> Option<(String, String)> {
    for key in [
        "manual_full_text",
        "full_text",
        "extracted_text_full",
        "readable_text_full",
        "transcript_full",
        "ocr_text_full",
        "ocr_text",
        "knowledge_markdown_full",
        "video_description_full",
    ] {
        if let Some(text) = payload_non_empty_string(payload, key) {
            return Some((key.to_string(), text));
        }
    }
    None
}

fn build_attachment_chunk_fingerprint(kind: &str, text: &str) -> String {
    let mut hasher = Sha256::new();
    hasher.update(kind.as_bytes());
    hasher.update([0u8]);
    hasher.update(text.as_bytes());
    let digest = hasher.finalize();
    let mut out = String::with_capacity(digest.len() * 2);
    for byte in digest {
        use std::fmt::Write as _;
        let _ = write!(&mut out, "{byte:02x}");
    }
    out
}

fn split_text_into_chunks(text: &str) -> Vec<(i64, i64)> {
    let mut char_offsets = Vec::<usize>::new();
    for (idx, _) in text.char_indices() {
        char_offsets.push(idx);
    }
    char_offsets.push(text.len());

    if char_offsets.len() <= 1 {
        return Vec::new();
    }

    let total_chars = char_offsets.len() - 1;
    let mut ranges = Vec::<(i64, i64)>::new();
    let mut start_char = 0usize;
    let overlap = ATTACHMENT_CHUNK_OVERLAP_CHARS.min(ATTACHMENT_CHUNK_MAX_CHARS / 2);

    while start_char < total_chars {
        let end_char = (start_char + ATTACHMENT_CHUNK_MAX_CHARS).min(total_chars);
        let start_byte = char_offsets[start_char] as i64;
        let end_byte = char_offsets[end_char] as i64;

        if end_byte > start_byte {
            ranges.push((start_byte, end_byte));
        }

        if end_char >= total_chars {
            break;
        }

        let next_start = end_char.saturating_sub(overlap);
        if next_start <= start_char {
            start_char = end_char;
        } else {
            start_char = next_start;
        }
    }

    ranges
}

fn read_attachment_chunk_text_by_range(
    conn: &Connection,
    key: &[u8; 32],
    attachment_sha256: &str,
    kind: &str,
    start_offset: i64,
    end_offset: i64,
) -> Result<Option<String>> {
    let Some(payload_json) = read_attachment_annotation_payload_json(conn, key, attachment_sha256)?
    else {
        return Ok(None);
    };

    let payload: serde_json::Value = match serde_json::from_str(&payload_json) {
        Ok(v) => v,
        Err(_) => return Ok(None),
    };

    let Some(source_text) = payload.get(kind).and_then(|v| v.as_str()) else {
        return Ok(None);
    };

    let mut start = start_offset.max(0) as usize;
    let mut end = end_offset.max(0) as usize;
    let text_len = source_text.len();
    if start > text_len {
        start = text_len;
    }
    if end > text_len {
        end = text_len;
    }

    while start > 0 && !source_text.is_char_boundary(start) {
        start -= 1;
    }
    while end < text_len && !source_text.is_char_boundary(end) {
        end += 1;
    }

    if end <= start {
        return Ok(None);
    }

    let chunk = source_text[start..end].trim();
    if chunk.is_empty() {
        return Ok(None);
    }

    Ok(Some(chunk.to_string()))
}

pub fn process_attachment_chunk_index_default(
    conn: &Connection,
    key: &[u8; 32],
    limit: usize,
) -> Result<usize> {
    let limit = i64::try_from(limit.clamp(1, 500)).unwrap_or(500);

    let mut stmt = conn.prepare(
        r#"SELECT a.sha256
           FROM attachments a
           JOIN attachment_annotations aa ON aa.attachment_sha256 = a.sha256
           WHERE aa.status = 'ok'
             AND aa.payload IS NOT NULL
           ORDER BY a.created_at DESC, a.sha256 DESC
           LIMIT ?1"#,
    )?;

    let mut rows = stmt.query(params![limit])?;
    let mut attachment_shas = Vec::<String>::new();
    while let Some(row) = rows.next()? {
        attachment_shas.push(row.get(0)?);
    }

    let mut reindexed = 0usize;

    for attachment_sha256 in attachment_shas {
        let Some(payload_json) = read_attachment_annotation_payload_json(conn, key, &attachment_sha256)?
        else {
            continue;
        };

        let payload: serde_json::Value = match serde_json::from_str(&payload_json) {
            Ok(v) => v,
            Err(_) => continue,
        };

        let Some((source_kind, source_text)) = select_attachment_chunk_source(&payload) else {
            continue;
        };

        let source_fingerprint = build_attachment_chunk_fingerprint(&source_kind, &source_text);

        let existing_state: Option<(String, String)> = conn
            .query_row(
                r#"SELECT source_kind, source_fingerprint
                   FROM attachment_chunk_index_state
                   WHERE attachment_sha256 = ?1"#,
                params![attachment_sha256],
                |row| Ok((row.get(0)?, row.get(1)?)),
            )
            .optional()?;

        if existing_state
            .as_ref()
            .is_some_and(|(kind, fingerprint)| kind == &source_kind && fingerprint == &source_fingerprint)
        {
            continue;
        }

        let chunks = split_text_into_chunks(&source_text);
        if chunks.is_empty() {
            continue;
        }

        let now = now_ms();

        conn.execute(
            r#"DELETE FROM attachment_text_chunks WHERE attachment_sha256 = ?1"#,
            params![attachment_sha256],
        )?;

        for (chunk_index, (start_offset, end_offset)) in chunks.iter().enumerate() {
            let text_len = end_offset.saturating_sub(*start_offset);
            conn.execute(
                r#"INSERT INTO attachment_text_chunks(
                       attachment_sha256,
                       kind,
                       chunk_index,
                       start_offset,
                       end_offset,
                       text_len,
                       needs_embedding,
                       created_at_ms,
                       updated_at_ms
                   )
                   VALUES (?1, ?2, ?3, ?4, ?5, ?6, 1, ?7, ?7)"#,
                params![
                    attachment_sha256,
                    source_kind,
                    i64::try_from(chunk_index).unwrap_or(i64::MAX),
                    *start_offset,
                    *end_offset,
                    text_len,
                    now
                ],
            )?;
        }

        conn.execute(
            r#"INSERT INTO attachment_chunk_index_state(
                   attachment_sha256,
                   source_kind,
                   source_fingerprint,
                   chunk_count,
                   updated_at_ms
               )
               VALUES (?1, ?2, ?3, ?4, ?5)
               ON CONFLICT(attachment_sha256) DO UPDATE SET
                 source_kind = excluded.source_kind,
                 source_fingerprint = excluded.source_fingerprint,
                 chunk_count = excluded.chunk_count,
                 updated_at_ms = excluded.updated_at_ms"#,
            params![
                attachment_sha256,
                source_kind,
                source_fingerprint,
                i64::try_from(chunks.len()).unwrap_or(i64::MAX),
                now
            ],
        )?;

        reindexed = reindexed.saturating_add(1);
    }

    Ok(reindexed)
}

pub fn process_pending_attachment_chunk_embeddings_default(
    conn: &Connection,
    key: &[u8; 32],
    limit: usize,
) -> Result<usize> {
    let space_id = embedding_space_id(crate::embedding::DEFAULT_MODEL_NAME, DEFAULT_EMBEDDING_DIM)?;
    ensure_vec_tables_for_space(conn, &space_id, DEFAULT_EMBEDDING_DIM)?;
    let table = attachment_chunk_embeddings_table(&space_id)?;

    let update_sql = format!(
        r#"UPDATE "{table}"
           SET embedding = ?2,
               attachment_sha256 = ?3,
               kind = ?4,
               chunk_index = ?5,
               model_name = ?6
           WHERE rowid = ?1"#
    );
    let insert_sql = format!(
        r#"INSERT INTO "{table}"(rowid, embedding, attachment_sha256, kind, chunk_index, model_name)
           VALUES (?1, ?2, ?3, ?4, ?5, ?6)"#
    );

    let mut stmt = conn.prepare(
        r#"SELECT rowid, attachment_sha256, kind, chunk_index, start_offset, end_offset
           FROM attachment_text_chunks
           WHERE COALESCE(needs_embedding, 1) = 1
           ORDER BY updated_at_ms ASC, rowid ASC
           LIMIT ?1"#,
    )?;

    let mut rows = stmt.query(params![i64::try_from(limit.clamp(1, 1000)).unwrap_or(1000)])?;

    let mut rowids = Vec::<i64>::new();
    let mut shas = Vec::<String>::new();
    let mut kinds = Vec::<String>::new();
    let mut indices = Vec::<i64>::new();
    let mut texts = Vec::<String>::new();

    while let Some(row) = rows.next()? {
        let rowid: i64 = row.get(0)?;
        let attachment_sha256: String = row.get(1)?;
        let kind: String = row.get(2)?;
        let chunk_index: i64 = row.get(3)?;
        let start_offset: i64 = row.get(4)?;
        let end_offset: i64 = row.get(5)?;

        let Some(chunk_text) = read_attachment_chunk_text_by_range(
            conn,
            key,
            &attachment_sha256,
            &kind,
            start_offset,
            end_offset,
        )?
        else {
            continue;
        };

        rowids.push(rowid);
        shas.push(attachment_sha256);
        kinds.push(kind);
        indices.push(chunk_index);
        texts.push(format!("passage: {chunk_text}"));
    }

    if rowids.is_empty() {
        return Ok(0);
    }

    for idx in 0..rowids.len() {
        let embedding = default_embed_text(&texts[idx]);

        let updated = conn.execute(
            &update_sql,
            params![
                rowids[idx],
                embedding.as_bytes(),
                shas[idx],
                kinds[idx],
                indices[idx],
                crate::embedding::DEFAULT_MODEL_NAME
            ],
        )?;
        if updated == 0 {
            conn.execute(
                &insert_sql,
                params![
                    rowids[idx],
                    embedding.as_bytes(),
                    shas[idx],
                    kinds[idx],
                    indices[idx],
                    crate::embedding::DEFAULT_MODEL_NAME
                ],
            )?;
        }

        conn.execute(
            r#"UPDATE attachment_text_chunks SET needs_embedding = 0 WHERE rowid = ?1"#,
            params![rowids[idx]],
        )?;
    }

    Ok(rowids.len())
}

fn chunk_search_normalize(input: &str) -> String {
    let mut out = String::with_capacity(input.len());
    for ch in input.chars() {
        if ch.is_alphanumeric() {
            out.extend(ch.to_lowercase());
        } else {
            out.push(' ');
        }
    }
    out.split_whitespace().collect::<Vec<_>>().join(" ")
}

fn chunk_search_score(query: &str, candidate: &str) -> u64 {
    let query_norm = chunk_search_normalize(query);
    let cand_norm = chunk_search_normalize(candidate);

    if query_norm.is_empty() || cand_norm.is_empty() {
        return 0;
    }

    let mut score = 0u64;

    if cand_norm == query_norm {
        score = score.saturating_add(20_000);
    }

    if cand_norm.contains(&query_norm) {
        score = score.saturating_add(8_000);
    }

    for token in query_norm.split_whitespace() {
        if token.len() < 2 {
            continue;
        }
        if cand_norm.contains(token) {
            score = score.saturating_add((token.len() as u64).saturating_mul(700));
        }
    }

    score
}

pub fn search_similar_attachment_chunks_default(
    conn: &Connection,
    key: &[u8; 32],
    query: &str,
    top_k: usize,
) -> Result<Vec<SimilarAttachmentChunk>> {
    let top_k = top_k.max(1);
    let mut stmt = conn.prepare(
        r#"SELECT attachment_sha256, kind, chunk_index, start_offset, end_offset
           FROM attachment_text_chunks
           ORDER BY updated_at_ms DESC, rowid DESC
           LIMIT ?1"#,
    )?;

    let candidate_k = i64::try_from((top_k.saturating_mul(30)).clamp(30, 1000)).unwrap_or(1000);
    let mut rows = stmt.query(params![candidate_k])?;

    let mut hits = Vec::<SimilarAttachmentChunk>::new();
    while let Some(row) = rows.next()? {
        let attachment_sha256: String = row.get(0)?;
        let kind: String = row.get(1)?;
        let chunk_index: i64 = row.get(2)?;
        let start_offset: i64 = row.get(3)?;
        let end_offset: i64 = row.get(4)?;

        let Some(chunk_text) = read_attachment_chunk_text_by_range(
            conn,
            key,
            &attachment_sha256,
            &kind,
            start_offset,
            end_offset,
        )?
        else {
            continue;
        };

        let score = chunk_search_score(query, &chunk_text);
        if score == 0 {
            continue;
        }

        let distance = 1.0 / (score as f64 + 1.0);
        hits.push(SimilarAttachmentChunk {
            attachment_sha256,
            kind,
            chunk_index,
            start_offset,
            end_offset,
            text: chunk_text,
            distance,
        });
    }

    hits.sort_by(|a, b| {
        a.distance
            .partial_cmp(&b.distance)
            .unwrap_or(std::cmp::Ordering::Equal)
            .then_with(|| a.attachment_sha256.cmp(&b.attachment_sha256))
            .then_with(|| a.kind.cmp(&b.kind))
            .then_with(|| a.chunk_index.cmp(&b.chunk_index))
    });
    if hits.len() > top_k {
        hits.truncate(top_k);
    }

    Ok(hits)
}

pub fn list_recent_indexed_attachment_shas(conn: &Connection, limit: usize) -> Result<Vec<String>> {
    let mut stmt = conn.prepare(
        r#"SELECT attachment_sha256
           FROM attachment_chunk_index_state
           ORDER BY updated_at_ms DESC, attachment_sha256 DESC
           LIMIT ?1"#,
    )?;
    let mut rows = stmt.query(params![i64::try_from(limit.clamp(1, 500)).unwrap_or(500)])?;
    let mut out = Vec::<String>::new();
    while let Some(row) = rows.next()? {
        out.push(row.get(0)?);
    }
    Ok(out)
}

pub fn read_attachment_by_sha_optional(conn: &Connection, sha256: &str) -> Result<Option<Attachment>> {
    let row: Option<(String, String, i64, i64)> = conn
        .query_row(
            r#"SELECT mime_type, path, byte_len, created_at
               FROM attachments
               WHERE sha256 = ?1"#,
            params![sha256],
            |row| Ok((row.get(0)?, row.get(1)?, row.get(2)?, row.get(3)?)),
        )
        .optional()?;

    let Some((mime_type, path, byte_len, created_at_ms)) = row else {
        return Ok(None);
    };

    Ok(Some(Attachment {
        sha256: sha256.to_string(),
        mime_type,
        path,
        byte_len,
        created_at_ms,
    }))
}
