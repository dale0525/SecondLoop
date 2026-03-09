const ATTACHMENT_CHUNK_WINDOW_CHARS: usize = 900;
const ATTACHMENT_CHUNK_OVERLAP_CHARS: usize = 180;
const ATTACHMENT_CHUNK_SNIPPET_LIMIT: usize = 220;
const ATTACHMENT_CHUNK_SEARCH_CANDIDATE_MULTIPLIER: usize = 8;

fn attachment_chunk_source_kinds(payload: &serde_json::Value) -> Vec<(String, String)> {
    const KIND_AND_KEYS: &[(&str, &[&str])] = &[
        (
            "extracted_text_full",
            &["extracted_text_full", "extracted_text_excerpt"],
        ),
        (
            "readable_text_full",
            &["readable_text_full", "readable_text_excerpt"],
        ),
        (
            "ocr_text_full",
            &["ocr_text_full", "ocr_text_excerpt", "ocr_text"],
        ),
        (
            "transcript_full",
            &["transcript_full", "transcript_excerpt"],
        ),
    ];

    let mut out = Vec::<(String, String)>::new();
    for (kind, keys) in KIND_AND_KEYS {
        for key in *keys {
            let text = payload
                .get(*key)
                .and_then(|v| v.as_str())
                .map(str::trim)
                .filter(|v| !v.is_empty());
            let Some(text) = text else {
                continue;
            };

            if out.iter().any(|(existing_kind, existing)| {
                existing_kind == kind && existing.as_str() == text
            }) {
                continue;
            }

            out.push(((*kind).to_string(), text.to_string()));
            break;
        }
    }

    out
}

fn collect_char_boundaries(text: &str) -> Vec<usize> {
    let mut out = Vec::<usize>::new();
    out.push(0);
    for (idx, _) in text.char_indices() {
        if idx > 0 {
            out.push(idx);
        }
    }
    out.push(text.len());
    out.sort_unstable();
    out.dedup();
    out
}

fn split_attachment_text_into_chunks(text: &str) -> Vec<(usize, usize)> {
    let trimmed = text.trim();
    if trimmed.is_empty() {
        return Vec::new();
    }

    let boundaries = collect_char_boundaries(trimmed);
    if boundaries.len() < 2 {
        return Vec::new();
    }

    let total_chars = boundaries.len().saturating_sub(1);
    let step_chars = ATTACHMENT_CHUNK_WINDOW_CHARS
        .saturating_sub(ATTACHMENT_CHUNK_OVERLAP_CHARS)
        .max(1);

    let mut out = Vec::<(usize, usize)>::new();
    let mut start_char = 0usize;

    while start_char < total_chars {
        let mut end_char = (start_char + ATTACHMENT_CHUNK_WINDOW_CHARS).min(total_chars);
        if end_char <= start_char {
            end_char = (start_char + 1).min(total_chars);
        }

        let start_offset = boundaries[start_char];
        let end_offset = boundaries[end_char];

        if end_offset > start_offset {
            out.push((start_offset, end_offset));
        }

        if end_char >= total_chars {
            break;
        }

        let next_start = end_char.saturating_sub(ATTACHMENT_CHUNK_OVERLAP_CHARS);
        if next_start <= start_char {
            start_char = start_char.saturating_add(step_chars);
        } else {
            start_char = next_start;
        }
    }

    out
}

fn attachment_chunk_snippet(text: &str) -> String {
    let normalized = text
        .replace("\r\n", "\n")
        .split_whitespace()
        .collect::<Vec<_>>()
        .join(" ");

    if normalized.is_empty() {
        return String::new();
    }

    let mut out = String::new();
    for ch in normalized.chars() {
        if out.chars().count() >= ATTACHMENT_CHUNK_SNIPPET_LIMIT {
            break;
        }
        out.push(ch);
    }

    if out.len() < normalized.len() {
        out.push('…');
    }

    out
}

fn read_chunk_text_by_offsets(
    conn: &Connection,
    key: &[u8; 32],
    attachment_sha256: &str,
    kind: &str,
    start_offset: i64,
    end_offset: i64,
) -> Result<String> {
    let payload_json = read_attachment_annotation_payload_json(conn, key, attachment_sha256)?;
    let Some(payload_json) = payload_json else {
        return Ok(String::new());
    };

    let payload: serde_json::Value = serde_json::from_str(&payload_json)
        .map_err(|e| anyhow!("invalid attachment annotation payload json: {e}"))?;

    let source_text = attachment_chunk_source_kinds(&payload)
        .into_iter()
        .find_map(|(source_kind, source_text)| {
            if source_kind == kind {
                Some(source_text)
            } else {
                None
            }
        })
        .unwrap_or_default();

    if source_text.is_empty() {
        return Ok(String::new());
    }

    let start_offset = usize::try_from(start_offset).unwrap_or(0).min(source_text.len());
    let end_offset = usize::try_from(end_offset)
        .unwrap_or(source_text.len())
        .min(source_text.len());

    if end_offset <= start_offset {
        return Ok(String::new());
    }

    let mut start = start_offset;
    while start > 0 && !source_text.is_char_boundary(start) {
        start -= 1;
    }

    let mut end = end_offset;
    while end > start && !source_text.is_char_boundary(end) {
        end -= 1;
    }

    if end <= start {
        return Ok(String::new());
    }

    Ok(source_text[start..end].trim().to_string())
}

pub fn read_attachment_chunk_text(
    conn: &Connection,
    key: &[u8; 32],
    attachment_sha256: &str,
    kind: &str,
    chunk_index: i64,
) -> Result<String> {
    let offsets: Option<(i64, i64)> = conn
        .query_row(
            r#"SELECT start_offset, end_offset
               FROM attachment_text_chunks
               WHERE attachment_sha256 = ?1
                 AND kind = ?2
                 AND chunk_index = ?3"#,
            params![attachment_sha256, kind, chunk_index],
            |row| Ok((row.get(0)?, row.get(1)?)),
        )
        .optional()?;

    let Some((start_offset, end_offset)) = offsets else {
        return Ok(String::new());
    };

    read_chunk_text_by_offsets(
        conn,
        key,
        attachment_sha256,
        kind,
        start_offset,
        end_offset,
    )
}

fn attachment_chunk_plaintext(chunk_text: &str) -> String {
    format!("passage: {}", chunk_text.trim())
}

pub fn read_attachment_by_sha256(
    conn: &Connection,
    attachment_sha256: &str,
) -> Result<Option<Attachment>> {
    conn.query_row(
        r#"SELECT sha256, mime_type, path, byte_len, created_at
           FROM attachments
           WHERE sha256 = ?1"#,
        params![attachment_sha256],
        |row| {
            Ok(Attachment {
                sha256: row.get(0)?,
                mime_type: row.get(1)?,
                path: row.get(2)?,
                byte_len: row.get(3)?,
                created_at_ms: row.get(4)?,
            })
        },
    )
    .optional()
    .map_err(Into::into)
}

pub fn list_pending_attachment_chunk_index_shas(
    conn: &Connection,
    limit: usize,
) -> Result<Vec<String>> {
    let limit = i64::try_from(limit.max(1)).unwrap_or(i64::MAX).clamp(1, 5000);
    let mut stmt = conn.prepare(
        r#"
SELECT aa.attachment_sha256
FROM attachment_annotations aa
WHERE aa.status = 'ok'
  AND aa.payload IS NOT NULL
  AND (
    NOT EXISTS (
      SELECT 1
      FROM attachment_text_chunks c
      WHERE c.attachment_sha256 = aa.attachment_sha256
    )
    OR aa.updated_at > COALESCE(
      (
        SELECT MAX(c.updated_at_ms)
        FROM attachment_text_chunks c
        WHERE c.attachment_sha256 = aa.attachment_sha256
      ),
      0
    )
  )
ORDER BY aa.updated_at ASC, aa.attachment_sha256 ASC
LIMIT ?1
"#,
    )?;

    let mut rows = stmt.query(params![limit])?;
    let mut out = Vec::<String>::new();
    while let Some(row) = rows.next()? {
        out.push(row.get(0)?);
    }
    Ok(out)
}

pub fn process_attachment_text_chunks(
    conn: &Connection,
    key: &[u8; 32],
    limit: usize,
) -> Result<usize> {
    let shas = list_pending_attachment_chunk_index_shas(conn, limit)?;
    if shas.is_empty() {
        return Ok(0);
    }

    let mut processed = 0usize;

    for sha in shas {
        let payload_json = read_attachment_annotation_payload_json(conn, key, &sha)?;
        let Some(payload_json) = payload_json else {
            continue;
        };

        let payload: serde_json::Value = match serde_json::from_str(&payload_json) {
            Ok(v) => v,
            Err(_) => continue,
        };

        let sources = attachment_chunk_source_kinds(&payload);
        let now = now_ms();

        conn.execute_batch("BEGIN IMMEDIATE;")?;
        let update_result = (|| -> Result<()> {
            conn.execute(
                r#"DELETE FROM attachment_chunk_embedding_jobs WHERE attachment_sha256 = ?1"#,
                params![sha],
            )?;
            conn.execute(
                r#"DELETE FROM attachment_text_chunks WHERE attachment_sha256 = ?1"#,
                params![sha],
            )?;

            for (kind, source_text) in sources {
                let chunks = split_attachment_text_into_chunks(&source_text);
                for (chunk_index, (start_offset, end_offset)) in chunks.into_iter().enumerate() {
                    if end_offset <= start_offset {
                        continue;
                    }
                    let text_len = i64::try_from(end_offset.saturating_sub(start_offset)).unwrap_or(0);
                    if text_len <= 0 {
                        continue;
                    }

                    let chunk_index_i64 = i64::try_from(chunk_index).unwrap_or(i64::MAX);
                    conn.execute(
                        r#"
INSERT INTO attachment_text_chunks(
  attachment_sha256,
  kind,
  chunk_index,
  start_offset,
  end_offset,
  text_len,
  created_at_ms,
  updated_at_ms
)
VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?7)
"#,
                        params![
                            sha,
                            kind,
                            chunk_index_i64,
                            i64::try_from(start_offset).unwrap_or(i64::MAX),
                            i64::try_from(end_offset).unwrap_or(i64::MAX),
                            text_len,
                            now,
                        ],
                    )?;

                    conn.execute(
                        r#"
INSERT INTO attachment_chunk_embedding_jobs(
  attachment_sha256,
  kind,
  chunk_index,
  status,
  attempts,
  next_retry_at_ms,
  last_error,
  created_at_ms,
  updated_at_ms
)
VALUES (?1, ?2, ?3, 'pending', 0, NULL, NULL, ?4, ?4)
"#,
                        params![sha, kind, chunk_index_i64, now],
                    )?;
                }
            }

            Ok(())
        })();

        match update_result {
            Ok(()) => {
                conn.execute_batch("COMMIT;")?;
                processed += 1;
            }
            Err(e) => {
                let _ = conn.execute_batch("ROLLBACK;");
                return Err(e);
            }
        }
    }

    Ok(processed)
}

pub fn process_pending_attachment_chunk_embeddings<E: Embedder + ?Sized>(
    conn: &Connection,
    key: &[u8; 32],
    embedder: &E,
    limit: usize,
) -> Result<usize> {
    let expected_dim = current_embedding_dim(conn)?;
    let space_id = embedding_space_id(embedder.model_name(), expected_dim)?;
    ensure_attachment_chunk_vec_table_for_space(conn, &space_id, expected_dim)?;
    let vec_table = attachment_chunk_embeddings_table(&space_id)?;

    let limit = i64::try_from(limit.max(1)).unwrap_or(i64::MAX).clamp(1, 5000);

    let mut stmt = conn.prepare(
        r#"
SELECT c.rowid,
       c.attachment_sha256,
       c.kind,
       c.chunk_index,
       c.start_offset,
       c.end_offset
FROM attachment_chunk_embedding_jobs j
JOIN attachment_text_chunks c
  ON c.attachment_sha256 = j.attachment_sha256
 AND c.kind = j.kind
 AND c.chunk_index = j.chunk_index
WHERE j.status = 'pending'
  AND (j.next_retry_at_ms IS NULL OR j.next_retry_at_ms <= ?1)
ORDER BY j.updated_at_ms ASC, c.attachment_sha256 ASC, c.kind ASC, c.chunk_index ASC
LIMIT ?2
"#,
    )?;

    let now = now_ms();
    let mut rows = stmt.query(params![now, limit])?;

    let mut rowids = Vec::<i64>::new();
    let mut shas = Vec::<String>::new();
    let mut kinds = Vec::<String>::new();
    let mut indices = Vec::<i64>::new();
    let mut texts = Vec::<String>::new();

    while let Some(row) = rows.next()? {
        let rowid: i64 = row.get(0)?;
        let sha: String = row.get(1)?;
        let kind: String = row.get(2)?;
        let chunk_index: i64 = row.get(3)?;
        let start_offset: i64 = row.get(4)?;
        let end_offset: i64 = row.get(5)?;

        let chunk_text = read_chunk_text_by_offsets(
            conn,
            key,
            &sha,
            &kind,
            start_offset,
            end_offset,
        )?;
        if chunk_text.trim().is_empty() {
            continue;
        }

        rowids.push(rowid);
        shas.push(sha);
        kinds.push(kind);
        indices.push(chunk_index);
        texts.push(attachment_chunk_plaintext(&chunk_text));
    }

    if texts.is_empty() {
        return Ok(0);
    }

    let embeddings = embedder.embed(&texts)?;
    if embeddings.len() != texts.len() {
        return Err(anyhow!(
            "embedder output length mismatch: expected {}, got {}",
            texts.len(),
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

    let update_sql = format!(
        r#"
UPDATE "{vec_table}"
SET embedding = ?2,
    chunk_rowid = ?3,
    attachment_sha256 = ?4,
    kind = ?5,
    chunk_index = ?6,
    model_name = ?7
WHERE rowid = ?1
"#
    );
    let insert_sql = format!(
        r#"
INSERT INTO "{vec_table}"(rowid, embedding, chunk_rowid, attachment_sha256, kind, chunk_index, model_name)
VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7)
"#
    );

    let now = now_ms();
    for i in 0..rowids.len() {
        let updated = conn.execute(
            &update_sql,
            params![
                rowids[i],
                embeddings[i].as_bytes(),
                rowids[i],
                shas[i],
                kinds[i],
                indices[i],
                embedder.model_name(),
            ],
        )?;
        if updated == 0 {
            conn.execute(
                &insert_sql,
                params![
                    rowids[i],
                    embeddings[i].as_bytes(),
                    rowids[i],
                    shas[i],
                    kinds[i],
                    indices[i],
                    embedder.model_name(),
                ],
            )?;
        }

        conn.execute(
            r#"
UPDATE attachment_chunk_embedding_jobs
SET status = 'done',
    attempts = attempts + 1,
    next_retry_at_ms = NULL,
    last_error = NULL,
    updated_at_ms = ?4
WHERE attachment_sha256 = ?1
  AND kind = ?2
  AND chunk_index = ?3
"#,
            params![shas[i], kinds[i], indices[i], now],
        )?;
    }

    Ok(rowids.len())
}

pub fn process_pending_attachment_chunk_embeddings_default(
    conn: &Connection,
    key: &[u8; 32],
    limit: usize,
) -> Result<usize> {
    let expected_dim = DEFAULT_EMBEDDING_DIM;
    let space_id = embedding_space_id(crate::embedding::DEFAULT_MODEL_NAME, expected_dim)?;
    ensure_attachment_chunk_vec_table_for_space(conn, &space_id, expected_dim)?;
    let vec_table = attachment_chunk_embeddings_table(&space_id)?;

    let limit = i64::try_from(limit.max(1)).unwrap_or(i64::MAX).clamp(1, 5000);

    let mut stmt = conn.prepare(
        r#"
SELECT c.rowid,
       c.attachment_sha256,
       c.kind,
       c.chunk_index,
       c.start_offset,
       c.end_offset
FROM attachment_chunk_embedding_jobs j
JOIN attachment_text_chunks c
  ON c.attachment_sha256 = j.attachment_sha256
 AND c.kind = j.kind
 AND c.chunk_index = j.chunk_index
WHERE j.status = 'pending'
  AND (j.next_retry_at_ms IS NULL OR j.next_retry_at_ms <= ?1)
ORDER BY j.updated_at_ms ASC, c.attachment_sha256 ASC, c.kind ASC, c.chunk_index ASC
LIMIT ?2
"#,
    )?;

    let now = now_ms();
    let mut rows = stmt.query(params![now, limit])?;

    let mut rowids = Vec::<i64>::new();
    let mut shas = Vec::<String>::new();
    let mut kinds = Vec::<String>::new();
    let mut indices = Vec::<i64>::new();
    let mut texts = Vec::<String>::new();

    while let Some(row) = rows.next()? {
        let rowid: i64 = row.get(0)?;
        let sha: String = row.get(1)?;
        let kind: String = row.get(2)?;
        let chunk_index: i64 = row.get(3)?;
        let start_offset: i64 = row.get(4)?;
        let end_offset: i64 = row.get(5)?;

        let chunk_text = read_chunk_text_by_offsets(
            conn,
            key,
            &sha,
            &kind,
            start_offset,
            end_offset,
        )?;
        if chunk_text.trim().is_empty() {
            continue;
        }

        rowids.push(rowid);
        shas.push(sha);
        kinds.push(kind);
        indices.push(chunk_index);
        texts.push(attachment_chunk_plaintext(&chunk_text));
    }

    if texts.is_empty() {
        return Ok(0);
    }

    let update_sql = format!(
        r#"
UPDATE "{vec_table}"
SET embedding = ?2,
    chunk_rowid = ?3,
    attachment_sha256 = ?4,
    kind = ?5,
    chunk_index = ?6,
    model_name = ?7
WHERE rowid = ?1
"#
    );
    let insert_sql = format!(
        r#"
INSERT INTO "{vec_table}"(rowid, embedding, chunk_rowid, attachment_sha256, kind, chunk_index, model_name)
VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7)
"#
    );

    let now = now_ms();
    for i in 0..rowids.len() {
        let embedding = default_embed_text(&texts[i]);
        if embedding.len() != expected_dim {
            return Err(anyhow!(
                "default embed dim mismatch: expected {}, got {}",
                expected_dim,
                embedding.len()
            ));
        }

        let updated = conn.execute(
            &update_sql,
            params![
                rowids[i],
                embedding.as_bytes(),
                rowids[i],
                shas[i],
                kinds[i],
                indices[i],
                crate::embedding::DEFAULT_MODEL_NAME,
            ],
        )?;
        if updated == 0 {
            conn.execute(
                &insert_sql,
                params![
                    rowids[i],
                    embedding.as_bytes(),
                    rowids[i],
                    shas[i],
                    kinds[i],
                    indices[i],
                    crate::embedding::DEFAULT_MODEL_NAME,
                ],
            )?;
        }

        conn.execute(
            r#"
UPDATE attachment_chunk_embedding_jobs
SET status = 'done',
    attempts = attempts + 1,
    next_retry_at_ms = NULL,
    last_error = NULL,
    updated_at_ms = ?4
WHERE attachment_sha256 = ?1
  AND kind = ?2
  AND chunk_index = ?3
"#,
            params![shas[i], kinds[i], indices[i], now],
        )?;
    }

    Ok(rowids.len())
}

pub fn process_pending_attachment_chunk_embeddings_active(
    conn: &Connection,
    key: &[u8; 32],
    app_dir: &Path,
    limit: usize,
) -> Result<usize> {
    let desired = desired_embedding_model_name(conn)?;

    if desired == crate::embedding::DEFAULT_MODEL_NAME {
        set_active_embedding_model_name(conn, crate::embedding::DEFAULT_MODEL_NAME)?;
        return process_pending_attachment_chunk_embeddings_default(conn, key, limit);
    }

    if desired == crate::embedding::PRODUCTION_MODEL_NAME {
        #[cfg(all(
            any(target_os = "windows", target_os = "macos", target_os = "linux"),
            not(frb_expand)
        ))]
        {
            match crate::embedding::FastEmbedder::get_or_try_init(app_dir) {
                Ok(embedder) => {
                    set_active_embedding_model_name(conn, crate::embedding::PRODUCTION_MODEL_NAME)?;
                    return process_pending_attachment_chunk_embeddings(conn, key, &embedder, limit);
                }
                Err(e) => return Err(anyhow!("production embeddings unavailable: {e}")),
            }
        }

        #[cfg(not(all(
            any(target_os = "windows", target_os = "macos", target_os = "linux"),
            not(frb_expand)
        )))]
        {
            set_active_embedding_model_name(conn, crate::embedding::DEFAULT_MODEL_NAME)?;
            return process_pending_attachment_chunk_embeddings_default(conn, key, limit);
        }
    }

    set_active_embedding_model_name(conn, crate::embedding::DEFAULT_MODEL_NAME)?;
    process_pending_attachment_chunk_embeddings_default(conn, key, limit)
}

pub fn search_similar_attachment_chunks<E: Embedder + ?Sized>(
    conn: &Connection,
    key: &[u8; 32],
    embedder: &E,
    query: &str,
    top_k: usize,
) -> Result<Vec<SimilarAttachmentChunk>> {
    let query_payload = format!("query: {query}");
    let mut vectors = embedder.embed(&[query_payload])?;
    if vectors.len() != 1 {
        return Err(anyhow!(
            "embedder output length mismatch: expected 1, got {}",
            vectors.len()
        ));
    }

    let query_vector = vectors.pop().unwrap_or_default();
    if query_vector.is_empty() {
        return Err(anyhow!("embedder returned empty embeddings"));
    }

    search_similar_attachment_chunks_by_embedding(conn, key, embedder.model_name(), &query_vector, top_k)
}

pub fn search_similar_attachment_chunks_active(
    conn: &Connection,
    key: &[u8; 32],
    app_dir: &Path,
    query: &str,
    top_k: usize,
) -> Result<Vec<SimilarAttachmentChunk>> {
    let desired = desired_embedding_model_name(conn)?;

    if desired == crate::embedding::DEFAULT_MODEL_NAME {
        set_active_embedding_model_name(conn, crate::embedding::DEFAULT_MODEL_NAME)?;
        return search_similar_attachment_chunks_default(conn, key, query, top_k);
    }

    if desired == crate::embedding::PRODUCTION_MODEL_NAME {
        #[cfg(all(
            any(target_os = "windows", target_os = "macos", target_os = "linux"),
            not(frb_expand)
        ))]
        {
            match crate::embedding::FastEmbedder::get_or_try_init(app_dir) {
                Ok(embedder) => {
                    set_active_embedding_model_name(conn, crate::embedding::PRODUCTION_MODEL_NAME)?;
                    return search_similar_attachment_chunks(conn, key, &embedder, query, top_k);
                }
                Err(e) => return Err(anyhow!("production embeddings unavailable: {e}")),
            }
        }

        #[cfg(not(all(
            any(target_os = "windows", target_os = "macos", target_os = "linux"),
            not(frb_expand)
        )))]
        {
            set_active_embedding_model_name(conn, crate::embedding::DEFAULT_MODEL_NAME)?;
            return search_similar_attachment_chunks_default(conn, key, query, top_k);
        }
    }

    set_active_embedding_model_name(conn, crate::embedding::DEFAULT_MODEL_NAME)?;
    search_similar_attachment_chunks_default(conn, key, query, top_k)
}

pub fn search_similar_attachment_chunks_default(
    conn: &Connection,
    key: &[u8; 32],
    query: &str,
    top_k: usize,
) -> Result<Vec<SimilarAttachmentChunk>> {
    let query_vector = default_embed_text(&format!("query: {query}"));
    search_similar_attachment_chunks_by_embedding(
        conn,
        key,
        crate::embedding::DEFAULT_MODEL_NAME,
        &query_vector,
        top_k,
    )
}

pub fn search_similar_attachment_chunks_by_embedding(
    conn: &Connection,
    key: &[u8; 32],
    model_name: &str,
    query_vector: &[f32],
    top_k: usize,
) -> Result<Vec<SimilarAttachmentChunk>> {
    if top_k == 0 {
        return Ok(Vec::new());
    }

    let dim = current_embedding_dim(conn)?;
    if query_vector.len() != dim {
        return Err(anyhow!(
            "query vector dim mismatch: expected {dim}, got {} (model_name={model_name})",
            query_vector.len()
        ));
    }

    let space_id = embedding_space_id(model_name, dim)?;
    ensure_attachment_chunk_vec_table_for_space(conn, &space_id, dim)?;
    let vec_table = attachment_chunk_embeddings_table(&space_id)?;

    let candidate_k = (top_k.saturating_mul(ATTACHMENT_CHUNK_SEARCH_CANDIDATE_MULTIPLIER))
        .max(top_k)
        .min(1000);

    let mut stmt = conn.prepare(&format!(
        r#"
SELECT chunk_rowid, attachment_sha256, kind, chunk_index, distance
FROM "{vec_table}"
WHERE embedding match ?1 AND k = ?2 AND model_name = ?3
ORDER BY distance ASC
"#
    ))?;

    let mut rows = stmt.query(params![
        query_vector.as_bytes(),
        i64::try_from(candidate_k).unwrap_or(i64::MAX),
        model_name,
    ])?;

    let mut out = Vec::<SimilarAttachmentChunk>::new();
    let mut seen = std::collections::HashSet::<(String, String, i64)>::new();

    while let Some(row) = rows.next()? {
        let chunk_rowid: i64 = row.get(0)?;
        let attachment_sha256: String = row.get(1)?;
        let kind: String = row.get(2)?;
        let chunk_index: i64 = row.get(3)?;
        let distance: f64 = row.get(4)?;

        if !seen.insert((attachment_sha256.clone(), kind.clone(), chunk_index)) {
            continue;
        }

        let offsets: Option<(i64, i64)> = conn
            .query_row(
                r#"SELECT start_offset, end_offset
                   FROM attachment_text_chunks
                   WHERE rowid = ?1"#,
                params![chunk_rowid],
                |r| Ok((r.get(0)?, r.get(1)?)),
            )
            .optional()?;

        let Some((start_offset, end_offset)) = offsets else {
            continue;
        };

        let chunk_text = read_chunk_text_by_offsets(
            conn,
            key,
            &attachment_sha256,
            &kind,
            start_offset,
            end_offset,
        )?;
        if chunk_text.trim().is_empty() {
            continue;
        }

        out.push(SimilarAttachmentChunk {
            attachment_sha256,
            kind,
            chunk_index,
            distance,
            snippet: attachment_chunk_snippet(&chunk_text),
        });

        if out.len() >= top_k {
            break;
        }
    }

    Ok(out)
}

pub fn list_recent_attachments_for_resources(conn: &Connection, limit: usize) -> Result<Vec<Attachment>> {
    let limit = i64::try_from(limit.max(1)).unwrap_or(i64::MAX).clamp(1, 500);
    let mut stmt = conn.prepare(
        r#"
SELECT sha256, mime_type, path, byte_len, created_at
FROM attachments
ORDER BY created_at DESC, sha256 DESC
LIMIT ?1
"#,
    )?;

    let mut rows = stmt.query(params![limit])?;
    let mut out = Vec::<Attachment>::new();
    while let Some(row) = rows.next()? {
        out.push(Attachment {
            sha256: row.get(0)?,
            mime_type: row.get(1)?,
            path: row.get(2)?,
            byte_len: row.get(3)?,
            created_at_ms: row.get(4)?,
        });
    }

    Ok(out)
}

#[cfg(test)]
mod tests {
    use super::attachment_chunk_source_kinds;
    use serde_json::json;

    #[test]
    fn attachment_chunk_sources_ignore_display_only_turn_view_without_canonical_transcript() {
        let payload = json!({
            "transcript_turns_v1": {
                "builder_version": "turns_v1",
                "status": "ok",
                "turns": [
                    {
                        "start_ms": 12000,
                        "end_ms": 18000,
                        "text": "display-only turn",
                        "segment_count": 1
                    }
                ]
            }
        });

        let sources = attachment_chunk_source_kinds(&payload);

        assert!(sources.is_empty());
    }

    #[test]
    fn attachment_chunk_sources_keep_canonical_transcript_and_ignore_turn_view() {
        let payload_excerpt_only = json!({
            "transcript_excerpt": "raw transcript excerpt",
            "transcript_turns_v1": {
                "builder_version": "turns_v1",
                "status": "ok",
                "turns": [
                    {
                        "start_ms": 12000,
                        "end_ms": 18000,
                        "text": "display-only turn",
                        "segment_count": 1
                    }
                ]
            }
        });

        let excerpt_only_sources = attachment_chunk_source_kinds(&payload_excerpt_only);

        assert_eq!(
            excerpt_only_sources,
            vec![(
                "transcript_full".to_string(),
                "raw transcript excerpt".to_string()
            )]
        );
        assert!(!excerpt_only_sources
            .iter()
            .any(|(_, text)| text.contains("display-only turn")));

        let payload_with_full = json!({
            "transcript_full": "raw transcript full",
            "transcript_excerpt": "raw transcript excerpt",
            "transcript_turns_v1": {
                "builder_version": "turns_v1",
                "status": "ok",
                "turns": [
                    {
                        "start_ms": 12000,
                        "end_ms": 18000,
                        "text": "display-only turn",
                        "segment_count": 1
                    }
                ]
            }
        });

        let full_sources = attachment_chunk_source_kinds(&payload_with_full);

        assert!(full_sources
            .iter()
            .any(|(kind, text)| kind == "transcript_full" && text == "raw transcript full"));
        assert!(!full_sources
            .iter()
            .any(|(_, text)| text.contains("display-only turn")));
    }
}
