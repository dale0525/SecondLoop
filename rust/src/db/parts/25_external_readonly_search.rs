fn process_pending_external_document_embeddings_with_default(
    conn: &Connection,
    key: &[u8; 32],
    limit: usize,
) -> Result<usize> {
    let space_id = upsert_external_embedding_space(
        conn,
        crate::embedding::DEFAULT_MODEL_NAME,
        DEFAULT_EMBEDDING_DIM,
    )?;
    let vec_table = ensure_external_chunk_vec_table_for_space(conn, &space_id, DEFAULT_EMBEDDING_DIM)?;

    let mut stmt = conn.prepare(&format!(
        r#"SELECT c.rowid, c.doc_id, c.chunk_index, c.chunk_text
           FROM external_document_chunks c
           JOIN external_documents d ON d.doc_id = c.doc_id
           WHERE COALESCE(d.is_deleted, 0) = 0
             AND NOT EXISTS (
               SELECT 1 FROM "{vec_table}" v WHERE v.rowid = c.rowid
             )
           ORDER BY c.updated_at_ms ASC, c.doc_id ASC, c.chunk_index ASC
           LIMIT ?1"#
    ))?;
    let mut rows = stmt.query(params![i64::try_from(limit.max(1)).unwrap_or(i64::MAX)])?;
    let mut rowids = Vec::<i64>::new();
    let mut doc_ids = Vec::<String>::new();
    let mut chunk_indices = Vec::<i64>::new();
    let mut texts = Vec::<String>::new();
    while let Some(row) = rows.next()? {
        let rowid: i64 = row.get(0)?;
        let doc_id: String = row.get(1)?;
        let chunk_index: i64 = row.get(2)?;
        let blob: Vec<u8> = row.get(3)?;
        let text = decode_external_chunk_text(key, &doc_id, chunk_index, &blob)?;
        if text.trim().is_empty() {
            continue;
        }
        rowids.push(rowid);
        doc_ids.push(doc_id);
        chunk_indices.push(chunk_index);
        texts.push(format!("passage: {}", text.trim()));
    }

    if texts.is_empty() {
        return Ok(0);
    }

    let update_sql = format!(
        r#"UPDATE "{vec_table}"
           SET embedding = ?2, chunk_rowid = ?3, doc_id = ?4, chunk_index = ?5, model_name = ?6
           WHERE rowid = ?1"#
    );
    let insert_sql = format!(
        r#"INSERT INTO "{vec_table}"(rowid, embedding, chunk_rowid, doc_id, chunk_index, model_name)
           VALUES (?1, ?2, ?3, ?4, ?5, ?6)"#
    );

    for index in 0..texts.len() {
        let embedding = default_embed_text(&texts[index]);
        let updated = conn.execute(
            &update_sql,
            params![
                rowids[index],
                embedding.as_bytes(),
                rowids[index],
                doc_ids[index],
                chunk_indices[index],
                crate::embedding::DEFAULT_MODEL_NAME,
            ],
        )?;
        if updated == 0 {
            conn.execute(
                &insert_sql,
                params![
                    rowids[index],
                    embedding.as_bytes(),
                    rowids[index],
                    doc_ids[index],
                    chunk_indices[index],
                    crate::embedding::DEFAULT_MODEL_NAME,
                ],
            )?;
        }
    }
    Ok(texts.len())
}

fn process_pending_external_document_embeddings_with_embedder<E: Embedder + ?Sized>(
    conn: &Connection,
    key: &[u8; 32],
    embedder: &E,
    limit: usize,
) -> Result<usize> {
    let dim = embedder.dim().max(1);
    let space_id = upsert_external_embedding_space(conn, embedder.model_name(), dim)?;
    let vec_table = ensure_external_chunk_vec_table_for_space(conn, &space_id, dim)?;

    let mut stmt = conn.prepare(&format!(
        r#"SELECT c.rowid, c.doc_id, c.chunk_index, c.chunk_text
           FROM external_document_chunks c
           JOIN external_documents d ON d.doc_id = c.doc_id
           WHERE COALESCE(d.is_deleted, 0) = 0
             AND NOT EXISTS (
               SELECT 1 FROM "{vec_table}" v WHERE v.rowid = c.rowid
             )
           ORDER BY c.updated_at_ms ASC, c.doc_id ASC, c.chunk_index ASC
           LIMIT ?1"#
    ))?;
    let mut rows = stmt.query(params![i64::try_from(limit.max(1)).unwrap_or(i64::MAX)])?;
    let mut rowids = Vec::<i64>::new();
    let mut doc_ids = Vec::<String>::new();
    let mut chunk_indices = Vec::<i64>::new();
    let mut texts = Vec::<String>::new();
    while let Some(row) = rows.next()? {
        let rowid: i64 = row.get(0)?;
        let doc_id: String = row.get(1)?;
        let chunk_index: i64 = row.get(2)?;
        let blob: Vec<u8> = row.get(3)?;
        let text = decode_external_chunk_text(key, &doc_id, chunk_index, &blob)?;
        if text.trim().is_empty() {
            continue;
        }
        rowids.push(rowid);
        doc_ids.push(doc_id);
        chunk_indices.push(chunk_index);
        texts.push(format!("passage: {}", text.trim()));
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

    let update_sql = format!(
        r#"UPDATE "{vec_table}"
           SET embedding = ?2, chunk_rowid = ?3, doc_id = ?4, chunk_index = ?5, model_name = ?6
           WHERE rowid = ?1"#
    );
    let insert_sql = format!(
        r#"INSERT INTO "{vec_table}"(rowid, embedding, chunk_rowid, doc_id, chunk_index, model_name)
           VALUES (?1, ?2, ?3, ?4, ?5, ?6)"#
    );

    for index in 0..texts.len() {
        let updated = conn.execute(
            &update_sql,
            params![
                rowids[index],
                embeddings[index].as_bytes(),
                rowids[index],
                doc_ids[index],
                chunk_indices[index],
                embedder.model_name(),
            ],
        )?;
        if updated == 0 {
            conn.execute(
                &insert_sql,
                params![
                    rowids[index],
                    embeddings[index].as_bytes(),
                    rowids[index],
                    doc_ids[index],
                    chunk_indices[index],
                    embedder.model_name(),
                ],
            )?;
        }
    }
    Ok(texts.len())
}

pub fn process_pending_external_document_embeddings_default(
    app_dir: &Path,
    key: &[u8; 32],
    limit: usize,
) -> Result<usize> {
    let conn = open_external_readonly_db(app_dir)?;
    process_pending_external_document_embeddings_with_default(&conn, key, limit)
}

pub fn process_pending_external_document_embeddings<E: Embedder + ?Sized>(
    app_dir: &Path,
    key: &[u8; 32],
    embedder: &E,
    limit: usize,
) -> Result<usize> {
    let conn = open_external_readonly_db(app_dir)?;
    process_pending_external_document_embeddings_with_embedder(&conn, key, embedder, limit)
}

pub fn process_pending_external_document_embeddings_active(
    app_dir: &Path,
    key: &[u8; 32],
    limit: usize,
) -> Result<usize> {
    let main_conn = open(app_dir)?;
    let external_conn = open_external_readonly_db(app_dir)?;
    let desired = desired_embedding_model_name(&main_conn)?;

    if desired == crate::embedding::DEFAULT_MODEL_NAME {
        return process_pending_external_document_embeddings_with_default(&external_conn, key, limit);
    }

    if desired == crate::embedding::PRODUCTION_MODEL_NAME {
        #[cfg(all(
            any(target_os = "windows", target_os = "macos", target_os = "linux"),
            not(frb_expand)
        ))]
        {
            match crate::embedding::FastEmbedder::get_or_try_init(app_dir) {
                Ok(embedder) => {
                    return process_pending_external_document_embeddings_with_embedder(
                        &external_conn,
                        key,
                        &embedder,
                        limit,
                    );
                }
                Err(_) => {
                    return process_pending_external_document_embeddings_with_default(
                        &external_conn,
                        key,
                        limit,
                    );
                }
            }
        }

        #[cfg(not(all(
            any(target_os = "windows", target_os = "macos", target_os = "linux"),
            not(frb_expand)
        )))]
        {
            return process_pending_external_document_embeddings_with_default(&external_conn, key, limit);
        }
    }

    process_pending_external_document_embeddings_with_default(&external_conn, key, limit)
}

fn search_similar_external_document_chunks_by_embedding_conn(
    conn: &Connection,
    key: &[u8; 32],
    model_name: &str,
    dim: usize,
    query_vector: &[f32],
    top_k: usize,
) -> Result<Vec<SimilarExternalDocumentChunk>> {
    let space_id = embedding_space_id(model_name, dim)?;
    let vec_table = ensure_external_chunk_vec_table_for_space(conn, &space_id, dim)?;
    let top_k = top_k.max(1);
    let candidate_k = (top_k.saturating_mul(10)).min(1000);

    let mut stmt = conn.prepare(&format!(
        r#"SELECT doc_id, chunk_index, distance
           FROM "{vec_table}"
           WHERE embedding match ?1 AND k = ?2 AND model_name = ?3
           ORDER BY distance ASC"#
    ))?;
    let mut rows = stmt.query(params![
        query_vector.as_bytes(),
        i64::try_from(candidate_k).unwrap_or(i64::MAX),
        model_name
    ])?;

    let mut out = Vec::<SimilarExternalDocumentChunk>::new();
    let mut seen = BTreeSet::<(String, i64)>::new();
    while let Some(row) = rows.next()? {
        let doc_id: String = row.get(0)?;
        let chunk_index: i64 = row.get(1)?;
        let distance: f64 = row.get(2)?;
        if !seen.insert((doc_id.clone(), chunk_index)) {
            continue;
        }

        let info: Option<(String, Vec<u8>, i64, Vec<u8>)> = conn
            .query_row(
                r#"SELECT d.batch_id, d.title, d.created_at_ms, c.chunk_text
                   FROM external_documents d
                   JOIN external_document_chunks c ON c.doc_id = d.doc_id
                   WHERE d.doc_id = ?1 AND c.chunk_index = ?2"#,
                params![doc_id, chunk_index],
                |row| Ok((row.get(0)?, row.get(1)?, row.get(2)?, row.get(3)?)),
            )
            .optional()?;
        let Some((batch_id, title_blob, created_at_ms, chunk_blob)) = info else {
            continue;
        };
        let title = decode_external_document_title(key, &doc_id, &title_blob)?;
        let chunk_text = decode_external_chunk_text(key, &doc_id, chunk_index, &chunk_blob)?;
        if chunk_text.trim().is_empty() {
            continue;
        }

        out.push(SimilarExternalDocumentChunk {
            batch_id,
            doc_id,
            title,
            chunk_index,
            distance,
            snippet: attachment_chunk_snippet(&chunk_text),
            created_at_ms,
        });
        if out.len() >= top_k {
            break;
        }
    }
    Ok(out)
}

pub fn search_similar_external_document_chunks_default(
    app_dir: &Path,
    key: &[u8; 32],
    query: &str,
    top_k: usize,
) -> Result<Vec<SimilarExternalDocumentChunk>> {
    let conn = open_external_readonly_db(app_dir)?;
    let _ = process_pending_external_document_embeddings_with_default(&conn, key, 1024)?;
    let query_vector = default_embed_text(&format!("query: {query}"));
    search_similar_external_document_chunks_by_embedding_conn(
        &conn,
        key,
        crate::embedding::DEFAULT_MODEL_NAME,
        DEFAULT_EMBEDDING_DIM,
        &query_vector,
        top_k,
    )
}

pub fn search_similar_external_document_chunks_by_embedding(
    app_dir: &Path,
    key: &[u8; 32],
    model_name: &str,
    query_vector: &[f32],
    top_k: usize,
) -> Result<Vec<SimilarExternalDocumentChunk>> {
    let conn = open_external_readonly_db(app_dir)?;
    search_similar_external_document_chunks_by_embedding_conn(
        &conn,
        key,
        model_name,
        query_vector.len(),
        query_vector,
        top_k,
    )
}

pub fn search_similar_external_document_chunks<E: Embedder + ?Sized>(
    app_dir: &Path,
    key: &[u8; 32],
    embedder: &E,
    query: &str,
    top_k: usize,
) -> Result<Vec<SimilarExternalDocumentChunk>> {
    let conn = open_external_readonly_db(app_dir)?;
    let _ = process_pending_external_document_embeddings_with_embedder(&conn, key, embedder, 1024)?;
    let mut vectors = embedder.embed(&[format!("query: {query}")])?;
    if vectors.len() != 1 {
        return Err(anyhow!(
            "embedder output length mismatch: expected 1, got {}",
            vectors.len()
        ));
    }
    let query_vector = vectors.remove(0);
    search_similar_external_document_chunks_by_embedding_conn(
        &conn,
        key,
        embedder.model_name(),
        query_vector.len(),
        &query_vector,
        top_k,
    )
}

pub fn search_similar_external_document_chunks_active(
    app_dir: &Path,
    key: &[u8; 32],
    query: &str,
    top_k: usize,
) -> Result<Vec<SimilarExternalDocumentChunk>> {
    let main_conn = open(app_dir)?;
    let desired = desired_embedding_model_name(&main_conn)?;
    if desired == crate::embedding::DEFAULT_MODEL_NAME {
        return search_similar_external_document_chunks_default(app_dir, key, query, top_k);
    }

    if desired == crate::embedding::PRODUCTION_MODEL_NAME {
        #[cfg(all(
            any(target_os = "windows", target_os = "macos", target_os = "linux"),
            not(frb_expand)
        ))]
        {
            if let Ok(embedder) = crate::embedding::FastEmbedder::get_or_try_init(app_dir) {
                return search_similar_external_document_chunks(app_dir, key, &embedder, query, top_k);
            }
        }
    }

    search_similar_external_document_chunks_default(app_dir, key, query, top_k)
}

pub fn build_external_document_chunk_rag_context(
    app_dir: &Path,
    key: &[u8; 32],
    doc_id: &str,
    chunk_index: i64,
) -> Result<String> {
    let conn = open_external_readonly_db(app_dir)?;
    let row: (Vec<u8>, Vec<u8>, Option<String>) = conn.query_row(
        r#"SELECT d.title, c.chunk_text, d.source_rel_path
           FROM external_documents d
           JOIN external_document_chunks c ON c.doc_id = d.doc_id
           WHERE d.doc_id = ?1 AND c.chunk_index = ?2"#,
        params![doc_id, chunk_index],
        |row| Ok((row.get(0)?, row.get(1)?, row.get(2)?)),
    )?;
    let title = decode_external_document_title(key, doc_id, &row.0)?;
    let chunk_text = decode_external_chunk_text(key, doc_id, chunk_index, &row.1)?;
    let rel_path = row.2.unwrap_or_default();
    let mut out = String::new();
    out.push_str("EXTERNAL_DOCUMENT\n");
    out.push_str("title: ");
    out.push_str(title.trim());
    if !rel_path.trim().is_empty() {
        out.push_str("\npath: ");
        out.push_str(rel_path.trim());
    }
    out.push_str("\ncontent: ");
    out.push_str(chunk_text.trim());
    Ok(out)
}

pub fn request_external_import_cancel(app_dir: &Path, batch_id: &str) -> Result<()> {
    fs::create_dir_all(external_readonly_root_dir(app_dir))?;
    fs::write(external_cancel_flag_path(app_dir, batch_id), b"1")?;
    let conn = open_external_readonly_db(app_dir)?;
    let has_batch: Option<i64> = conn
        .query_row(
            r#"SELECT 1 FROM external_import_batches WHERE batch_id = ?1"#,
            params![batch_id],
            |row| row.get(0),
        )
        .optional()?;
    if has_batch.is_some() {
        let stats_json = build_external_stats_json(0, 0, 0, 0);
        let _ = update_external_import_batch(&conn, batch_id, "cancelling", &stats_json, None, None);
    }
    Ok(())
}
