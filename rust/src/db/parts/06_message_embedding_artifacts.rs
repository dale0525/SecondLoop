#[derive(Clone, Debug)]
struct PendingMessageEmbeddingJob {
    rowid: i64,
    message_id: String,
    source_revision: i64,
    plaintext: String,
    chunk_hash: String,
}

fn default_message_artifact_quality_tier(producer_class: &str) -> &'static str {
    if producer_class == "mobile" {
        "reduced"
    } else {
        "full"
    }
}

fn default_local_message_artifact_producer_class() -> &'static str {
    if cfg!(any(target_os = "windows", target_os = "macos", target_os = "linux")) {
        "desktop"
    } else {
        "mobile"
    }
}

fn current_message_artifact_priority_tuple(producer_class: &str) -> Result<(i64, i64, i64)> {
    Ok((
        embedding_artifact_producer_priority(producer_class)?,
        embedding_artifact_quality_priority(default_message_artifact_quality_tier(producer_class))?,
        embedding_artifact_vector_format_priority("f32")?,
    ))
}

fn artifact_satisfies_current_message_priority(
    manifest: &EmbeddingArtifactManifest,
    producer_class: &str,
) -> Result<bool> {
    let current_priority = current_message_artifact_priority_tuple(producer_class)?;
    let manifest_priority = (
        embedding_artifact_producer_priority(&manifest.producer_class)?,
        embedding_artifact_quality_priority(&manifest.quality_tier)?,
        embedding_artifact_vector_format_priority(&manifest.vector_format)?,
    );
    Ok(manifest_priority >= current_priority)
}

fn detect_message_embedding_producer_class(
    conn: &Connection,
    key: &[u8; 32],
    model_name: &str,
) -> Result<&'static str> {
    if let Some((_profile_id, profile)) = load_active_embedding_profile_config(conn, key)? {
        if profile.model_name.trim() == model_name.trim() {
            return Ok("byok");
        }
    }

    if let Some(cache) = load_cloud_gateway_embeddings_cache(conn)? {
        if cache.effective_model_id.trim() == model_name.trim() {
            return Ok("cloud");
        }
    }

    if model_name.trim() == crate::embedding::PRODUCTION_MODEL_NAME {
        return Ok("desktop");
    }

    Ok("mobile")
}

fn load_pending_message_embedding_jobs(
    conn: &Connection,
    key: &[u8; 32],
    limit: usize,
) -> Result<Vec<PendingMessageEmbeddingJob>> {
    let mut stmt = conn.prepare(
        r#"SELECT rowid, id, content, updated_at
           FROM messages
           WHERE COALESCE(needs_embedding, 1) = 1
             AND COALESCE(is_deleted, 0) = 0
             AND COALESCE(is_memory, 1) = 1
           ORDER BY created_at ASC
           LIMIT ?1"#,
    )?;

    let mut rows = stmt.query(params![i64::try_from(limit).unwrap_or(i64::MAX)])?;
    let mut out = Vec::new();

    while let Some(row) = rows.next()? {
        let rowid: i64 = row.get(0)?;
        let message_id: String = row.get(1)?;
        let content_blob: Vec<u8> = row.get(2)?;
        let source_revision: i64 = row.get(3)?;

        let content_bytes = decrypt_bytes(key, &content_blob, b"message.content")?;
        let content = String::from_utf8(content_bytes)
            .map_err(|_| anyhow!("message content is not valid utf-8"))?;
        let plaintext = build_message_embedding_plaintext(conn, key, &message_id, &content)?;

        let mut hasher = Sha256::new();
        hasher.update(plaintext.as_bytes());
        let digest = hasher.finalize();
        let mut chunk_hash = String::with_capacity(digest.len() * 2);
        for byte in digest {
            use std::fmt::Write;
            let _ = write!(&mut chunk_hash, "{byte:02x}");
        }

        out.push(PendingMessageEmbeddingJob {
            rowid,
            message_id,
            source_revision,
            plaintext,
            chunk_hash,
        });
    }

    Ok(out)
}

fn upsert_message_embedding_row(
    conn: &Connection,
    message_table: &str,
    rowid: i64,
    message_id: &str,
    model_name: &str,
    embedding: &[f32],
) -> Result<()> {
    let update_sql = format!(
        r#"UPDATE "{message_table}"
           SET embedding = ?2, message_id = ?3, model_name = ?4
           WHERE rowid = ?1"#
    );
    let insert_sql = format!(
        r#"INSERT INTO "{message_table}"
           (rowid, embedding, message_id, model_name)
           VALUES (?1, ?2, ?3, ?4)"#
    );

    let updated = conn.execute(
        &update_sql,
        params![rowid, embedding.as_bytes(), message_id, model_name],
    )?;
    if updated == 0 {
        conn.execute(
            &insert_sql,
            params![rowid, embedding.as_bytes(), message_id, model_name],
        )?;
    }

    conn.execute(
        r#"UPDATE messages SET needs_embedding = 0 WHERE rowid = ?1"#,
        params![rowid],
    )?;
    Ok(())
}

fn try_materialize_message_embedding_from_artifact(
    conn: &Connection,
    key: &[u8; 32],
    app_dir: &Path,
    message_table: &str,
    model_name: &str,
    job: &PendingMessageEmbeddingJob,
    profile_id: &str,
    producer_class: &str,
) -> Result<bool> {
    if let Some(active) = get_active_embedding_artifact_for_identity(
        conn,
        "message",
        &job.message_id,
        job.source_revision,
        &job.chunk_hash,
        profile_id,
    )? {
        if artifact_satisfies_current_message_priority(&active, producer_class)?
            && has_embedding_artifact_blob(app_dir, &active.blob_ref)
        {
            let blob = read_embedding_artifact_blob(app_dir, key, &active.blob_ref)?;
            let embedding = decode_f32_embedding_artifact_blob(&blob, active.dimension as usize)?;
            upsert_message_embedding_row(
                conn,
                message_table,
                job.rowid,
                &job.message_id,
                model_name,
                &embedding,
            )?;
            return Ok(true);
        }
    }

    let Some(cache_hit) = find_best_embedding_artifact_cache_hit(conn, &job.chunk_hash, profile_id)? else {
        return Ok(false);
    };
    if !artifact_satisfies_current_message_priority(&cache_hit, producer_class)?
        || !has_embedding_artifact_blob(app_dir, &cache_hit.blob_ref)
    {
        return Ok(false);
    }

    let blob = read_embedding_artifact_blob(app_dir, key, &cache_hit.blob_ref)?;
    let embedding = decode_f32_embedding_artifact_blob(&blob, cache_hit.dimension as usize)?;
    upsert_message_embedding_row(
        conn,
        message_table,
        job.rowid,
        &job.message_id,
        model_name,
        &embedding,
    )?;

    let _ = clone_embedding_artifact_manifest_for_source(
        conn,
        key,
        "message",
        &job.message_id,
        job.source_revision,
        &job.chunk_hash,
        0,
        &cache_hit,
    )?;

    Ok(true)
}

fn store_message_embedding_artifact(
    conn: &Connection,
    key: &[u8; 32],
    app_dir: &Path,
    producer_class: &str,
    model_name: &str,
    dim: usize,
    job: &PendingMessageEmbeddingJob,
    embedding: &[f32],
) -> Result<()> {
    let profile_id = embedding_artifact_profile_id(model_name, dim);
    if let Some(active) = get_active_embedding_artifact_for_identity(
        conn,
        "message",
        &job.message_id,
        job.source_revision,
        &job.chunk_hash,
        &profile_id,
    )? {
        if artifact_satisfies_current_message_priority(&active, producer_class)? {
            return Ok(());
        }
    }

    let blob_ref = uuid::Uuid::new_v4().to_string();
    let blob = encode_f32_embedding_artifact_blob(embedding);
    write_embedding_artifact_blob(app_dir, key, &blob_ref, &blob)?;

    let producer_device_id = Some(get_or_create_device_id(conn)?);
    let _ = create_embedding_artifact_manifest(
        conn,
        key,
        EmbeddingArtifactManifestInput {
            source_kind: "message",
            source_id: &job.message_id,
            source_revision: job.source_revision,
            chunk_hash: &job.chunk_hash,
            chunk_ordinal: 0,
            profile_id: &profile_id,
            producer_device_id: producer_device_id.as_deref(),
            producer_class,
            quality_tier: default_message_artifact_quality_tier(producer_class),
            vector_format: "f32",
            dimension: i64::try_from(dim).unwrap_or(i64::MAX),
            blob_ref: &blob_ref,
            created_at_ms: Some(now_ms()),
        },
    )?;
    Ok(())
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
    let model_name = embedder.model_name().to_string();
    let producer_class = detect_message_embedding_producer_class(conn, key, &model_name)?;
    let profile_id = embedding_artifact_profile_id(&model_name, expected_dim);
    let app_dir = app_dir_from_conn(conn)?;
    let space_id = embedding_space_id(&model_name, expected_dim)?;
    ensure_vec_tables_for_space(conn, &space_id, expected_dim)?;
    let message_table = message_embeddings_table(&space_id)?;

    let jobs = load_pending_message_embedding_jobs(conn, key, limit)?;
    if jobs.is_empty() {
        return Ok(0);
    }

    let mut unresolved = Vec::new();
    let mut restored = 0usize;
    for job in jobs {
        if try_materialize_message_embedding_from_artifact(
            conn,
            key,
            app_dir.as_path(),
            &message_table,
            &model_name,
            &job,
            &profile_id,
            producer_class,
        )? {
            restored += 1;
            continue;
        }
        unresolved.push(job);
    }

    if unresolved.is_empty() {
        return Ok(restored);
    }

    let plaintexts: Vec<String> = unresolved.iter().map(|job| job.plaintext.clone()).collect();
    let embeddings = embedder.embed(&plaintexts)?;
    if embeddings.len() != unresolved.len() {
        return Err(anyhow!(
            "embedder output length mismatch: expected {}, got {}",
            unresolved.len(),
            embeddings.len()
        ));
    }

    for (job, embedding) in unresolved.iter().zip(embeddings.iter()) {
        if embedding.len() != expected_dim {
            return Err(anyhow!(
                "embedder dim mismatch: expected {expected_dim}, got {} (model_name={})",
                embedding.len(),
                model_name
            ));
        }
        upsert_message_embedding_row(
            conn,
            &message_table,
            job.rowid,
            &job.message_id,
            &model_name,
            embedding,
        )?;
        store_message_embedding_artifact(
            conn,
            key,
            app_dir.as_path(),
            producer_class,
            &model_name,
            expected_dim,
            job,
            embedding,
        )?;
    }

    Ok(restored + unresolved.len())
}

pub fn process_pending_message_embeddings_default(
    conn: &Connection,
    key: &[u8; 32],
    limit: usize,
) -> Result<usize> {
    let model_name = crate::embedding::DEFAULT_MODEL_NAME.to_string();
    let expected_dim = DEFAULT_EMBEDDING_DIM;
    let producer_class = default_local_message_artifact_producer_class();
    let profile_id = embedding_artifact_profile_id(&model_name, expected_dim);
    let app_dir = app_dir_from_conn(conn)?;
    let space_id = embedding_space_id(&model_name, DEFAULT_EMBEDDING_DIM)?;
    ensure_vec_tables_for_space(conn, &space_id, DEFAULT_EMBEDDING_DIM)?;
    let message_table = message_embeddings_table(&space_id)?;

    let jobs = load_pending_message_embedding_jobs(conn, key, limit)?;
    if jobs.is_empty() {
        return Ok(0);
    }

    let mut unresolved = Vec::new();
    let mut restored = 0usize;
    for job in jobs {
        if try_materialize_message_embedding_from_artifact(
            conn,
            key,
            app_dir.as_path(),
            &message_table,
            &model_name,
            &job,
            &profile_id,
            producer_class,
        )? {
            restored += 1;
            continue;
        }
        unresolved.push(job);
    }

    for job in &unresolved {
        let embedding = default_embed_text(&job.plaintext);
        if embedding.len() != expected_dim {
            return Err(anyhow!(
                "default embed dim mismatch: expected {}, got {}",
                expected_dim,
                embedding.len()
            ));
        }
        upsert_message_embedding_row(
            conn,
            &message_table,
            job.rowid,
            &job.message_id,
            &model_name,
            &embedding,
        )?;
        store_message_embedding_artifact(
            conn,
            key,
            app_dir.as_path(),
            producer_class,
            &model_name,
            expected_dim,
            job,
            &embedding,
        )?;
    }

    Ok(restored + unresolved.len())
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
