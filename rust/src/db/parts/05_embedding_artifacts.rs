fn embedding_artifact_producer_priority(producer_class: &str) -> Result<i64> {
    match producer_class.trim() {
        "byok" => Ok(4),
        "cloud" | "secondloop_cloud" | "secondloop-cloud" => Ok(3),
        "desktop" => Ok(2),
        "mobile" => Ok(1),
        other => Err(anyhow!(
            "unsupported embedding artifact producer_class: {other}"
        )),
    }
}

fn embedding_artifact_quality_priority(quality_tier: &str) -> Result<i64> {
    match quality_tier.trim() {
        "full" => Ok(2),
        "reduced" => Ok(1),
        other => Err(anyhow!(
            "unsupported embedding artifact quality_tier: {other}"
        )),
    }
}

fn embedding_artifact_vector_format_priority(vector_format: &str) -> Result<i64> {
    match vector_format.trim() {
        "f32" => Ok(3),
        "f16" => Ok(2),
        "int8" => Ok(1),
        other => Err(anyhow!(
            "unsupported embedding artifact vector_format: {other}"
        )),
    }
}

pub fn embedding_artifact_blob_storage_id(blob_ref: &str) -> String {
    let mut hasher = Sha256::new();
    hasher.update(blob_ref.trim().as_bytes());
    let digest = hasher.finalize();
    let mut out = String::with_capacity(digest.len() * 2);
    for byte in digest {
        use std::fmt::Write;
        let _ = write!(&mut out, "{byte:02x}");
    }
    out
}

pub fn embedding_artifact_blob_rel_path(blob_ref: &str) -> String {
    format!(
        "embedding_artifacts/{}.bin",
        embedding_artifact_blob_storage_id(blob_ref)
    )
}

pub fn has_embedding_artifact_blob(app_dir: &Path, blob_ref: &str) -> bool {
    app_dir.join(embedding_artifact_blob_rel_path(blob_ref)).exists()
}

pub fn write_embedding_artifact_blob(
    app_dir: &Path,
    key: &[u8; 32],
    blob_ref: &str,
    plaintext: &[u8],
) -> Result<()> {
    let rel_path = embedding_artifact_blob_rel_path(blob_ref);
    let full_path = app_dir.join(&rel_path);
    if let Some(parent) = full_path.parent() {
        fs::create_dir_all(parent)?;
    }
    let aad = format!("embedding_artifact.blob:{}", blob_ref.trim());
    let ciphertext = encrypt_bytes(key, plaintext, aad.as_bytes())?;
    fs::write(full_path, ciphertext)?;
    Ok(())
}

pub fn read_embedding_artifact_blob(
    app_dir: &Path,
    key: &[u8; 32],
    blob_ref: &str,
) -> Result<Vec<u8>> {
    let rel_path = embedding_artifact_blob_rel_path(blob_ref);
    let ciphertext = fs::read(app_dir.join(rel_path))?;
    let aad = format!("embedding_artifact.blob:{}", blob_ref.trim());
    decrypt_bytes(key, &ciphertext, aad.as_bytes())
}

pub fn encode_f32_embedding_artifact_blob(vector: &[f32]) -> Vec<u8> {
    vector.as_bytes().to_vec()
}

pub fn decode_f32_embedding_artifact_blob(bytes: &[u8], dim: usize) -> Result<Vec<f32>> {
    if bytes.len() != dim.saturating_mul(std::mem::size_of::<f32>()) {
        return Err(anyhow!(
            "embedding artifact blob byte length mismatch: expected {}, got {}",
            dim.saturating_mul(std::mem::size_of::<f32>()),
            bytes.len()
        ));
    }
    let mut out = Vec::with_capacity(dim);
    for chunk in bytes.chunks_exact(4) {
        out.push(f32::from_le_bytes([chunk[0], chunk[1], chunk[2], chunk[3]]));
    }
    Ok(out)
}

pub fn embedding_artifact_profile_id(model_name: &str, dim: usize) -> String {
    format!("model:{}|dim:{}|policy:v1", model_name.trim(), dim)
}

fn validate_embedding_artifact_manifest_input(input: &EmbeddingArtifactManifestInput<'_>) -> Result<()> {
    if input.source_kind.trim().is_empty() {
        return Err(anyhow!("embedding artifact source_kind cannot be empty"));
    }
    if input.source_id.trim().is_empty() {
        return Err(anyhow!("embedding artifact source_id cannot be empty"));
    }
    if input.source_revision < 0 {
        return Err(anyhow!(
            "embedding artifact source_revision cannot be negative"
        ));
    }
    if input.chunk_hash.trim().is_empty() {
        return Err(anyhow!("embedding artifact chunk_hash cannot be empty"));
    }
    if input.chunk_ordinal < 0 {
        return Err(anyhow!(
            "embedding artifact chunk_ordinal cannot be negative"
        ));
    }
    if input.profile_id.trim().is_empty() {
        return Err(anyhow!("embedding artifact profile_id cannot be empty"));
    }
    embedding_artifact_producer_priority(input.producer_class)?;
    embedding_artifact_quality_priority(input.quality_tier)?;
    embedding_artifact_vector_format_priority(input.vector_format)?;
    if input.dimension <= 0 {
        return Err(anyhow!("embedding artifact dimension must be positive"));
    }
    if input.blob_ref.trim().is_empty() {
        return Err(anyhow!("embedding artifact blob_ref cannot be empty"));
    }
    Ok(())
}

fn read_embedding_artifact_manifest(
    row: &rusqlite::Row<'_>,
) -> rusqlite::Result<EmbeddingArtifactManifest> {
    Ok(EmbeddingArtifactManifest {
        artifact_id: row.get(0)?,
        source_kind: row.get(1)?,
        source_id: row.get(2)?,
        source_revision: row.get(3)?,
        chunk_hash: row.get(4)?,
        chunk_ordinal: row.get(5)?,
        profile_id: row.get(6)?,
        producer_device_id: row.get(7)?,
        producer_class: row.get(8)?,
        quality_tier: row.get(9)?,
        vector_format: row.get(10)?,
        dimension: row.get(11)?,
        blob_ref: row.get(12)?,
        status: row.get(13)?,
        supersedes_artifact_id: row.get(14)?,
        created_at_ms: row.get(15)?,
        updated_at_ms: row.get(16)?,
    })
}

fn list_embedding_artifact_candidates(
    conn: &Connection,
    source_kind: &str,
    source_id: &str,
    source_revision: i64,
    chunk_hash: &str,
    profile_id: &str,
) -> Result<Vec<EmbeddingArtifactManifest>> {
    let mut stmt = conn.prepare(
        r#"SELECT artifact_id,
                  source_kind,
                  source_id,
                  source_revision,
                  chunk_hash,
                  chunk_ordinal,
                  profile_id,
                  producer_device_id,
                  producer_class,
                  quality_tier,
                  vector_format,
                  dimension,
                  blob_ref,
                  status,
                  supersedes_artifact_id,
                  created_at_ms,
                  updated_at_ms
           FROM embedding_artifact_manifests
           WHERE source_kind = ?1
             AND source_id = ?2
             AND source_revision = ?3
             AND chunk_hash = ?4
             AND profile_id = ?5"#,
    )?;

    let mut rows = stmt.query(params![
        source_kind,
        source_id,
        source_revision,
        chunk_hash,
        profile_id
    ])?;
    let mut out = Vec::new();
    while let Some(row) = rows.next()? {
        out.push(read_embedding_artifact_manifest(row)?);
    }
    Ok(out)
}

fn embedding_artifact_sort_key(
    manifest: &EmbeddingArtifactManifest,
) -> Result<(i64, i64, i64, i64, &str)> {
    Ok((
        embedding_artifact_producer_priority(&manifest.producer_class)?,
        embedding_artifact_quality_priority(&manifest.quality_tier)?,
        embedding_artifact_vector_format_priority(&manifest.vector_format)?,
        manifest.created_at_ms,
        manifest.artifact_id.as_str(),
    ))
}

fn choose_best_embedding_artifact(
    manifests: &[EmbeddingArtifactManifest],
) -> Result<Option<&EmbeddingArtifactManifest>> {
    let mut best: Option<&EmbeddingArtifactManifest> = None;
    let mut best_key: Option<(i64, i64, i64, i64, &str)> = None;

    for manifest in manifests {
        if manifest.status != "ready" {
            continue;
        }
        let candidate_key = embedding_artifact_sort_key(manifest)?;
        if best_key
            .as_ref()
            .map(|key| candidate_key > *key)
            .unwrap_or(true)
        {
            best = Some(manifest);
            best_key = Some(candidate_key);
        }
    }

    Ok(best)
}

fn insert_embedding_artifact_manifest_row(
    conn: &Connection,
    artifact_id: &str,
    input: &EmbeddingArtifactManifestInput<'_>,
    created_at_ms: i64,
    updated_at_ms: i64,
) -> Result<()> {
    conn.execute(
        r#"INSERT INTO embedding_artifact_manifests(
               artifact_id,
               source_kind,
               source_id,
               source_revision,
               chunk_hash,
               chunk_ordinal,
               profile_id,
               producer_device_id,
               producer_class,
               quality_tier,
               vector_format,
               dimension,
               blob_ref,
               status,
               supersedes_artifact_id,
               created_at_ms,
               updated_at_ms
           ) VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?11, ?12, ?13, 'ready', NULL, ?14, ?15)"#,
        params![
            artifact_id,
            input.source_kind.trim(),
            input.source_id.trim(),
            input.source_revision,
            input.chunk_hash.trim(),
            input.chunk_ordinal,
            input.profile_id.trim(),
            input.producer_device_id.map(str::trim).filter(|v| !v.is_empty()),
            input.producer_class.trim(),
            input.quality_tier.trim(),
            input.vector_format.trim(),
            input.dimension,
            input.blob_ref.trim(),
            created_at_ms,
            updated_at_ms,
        ],
    )?;
    Ok(())
}

fn resolve_embedding_artifact_identity_status(
    conn: &Connection,
    artifact_id: &str,
    input: &EmbeddingArtifactManifestInput<'_>,
    updated_at_ms: i64,
) -> Result<()> {
    let manifests = list_embedding_artifact_candidates(
        conn,
        input.source_kind.trim(),
        input.source_id.trim(),
        input.source_revision,
        input.chunk_hash.trim(),
        input.profile_id.trim(),
    )?;

    let Some(best) = choose_best_embedding_artifact(&manifests)? else {
        return Err(anyhow!(
            "embedding artifact candidate set unexpectedly empty"
        ));
    };

    if best.artifact_id == artifact_id {
        let previous_best = manifests
            .iter()
            .filter(|manifest| manifest.artifact_id != artifact_id && manifest.status == "ready")
            .max_by(|left, right| {
                embedding_artifact_sort_key(left)
                    .expect("left sort key")
                    .cmp(&embedding_artifact_sort_key(right).expect("right sort key"))
            });

        conn.execute(
            r#"UPDATE embedding_artifact_manifests
               SET status = 'superseded', updated_at_ms = ?2
               WHERE source_kind = ?1
                 AND source_id = ?3
                 AND source_revision = ?4
                 AND chunk_hash = ?5
                 AND profile_id = ?6
                 AND artifact_id != ?7
                 AND status != 'tombstoned'"#,
            params![
                input.source_kind.trim(),
                updated_at_ms,
                input.source_id.trim(),
                input.source_revision,
                input.chunk_hash.trim(),
                input.profile_id.trim(),
                artifact_id,
            ],
        )?;

        conn.execute(
            r#"UPDATE embedding_artifact_manifests
               SET status = 'ready',
                   supersedes_artifact_id = ?2,
                   updated_at_ms = ?3
               WHERE artifact_id = ?1"#,
            params![
                artifact_id,
                previous_best.map(|manifest| manifest.artifact_id.as_str()),
                updated_at_ms,
            ],
        )?;
    } else {
        conn.execute(
            r#"UPDATE embedding_artifact_manifests
               SET status = 'superseded',
                   updated_at_ms = ?2
               WHERE artifact_id = ?1"#,
            params![artifact_id, updated_at_ms],
        )?;
    }

    Ok(())
}

fn record_embedding_artifact_manifest_with_id(
    conn: &Connection,
    artifact_id: &str,
    input: EmbeddingArtifactManifestInput<'_>,
    created_at_ms: i64,
    updated_at_ms: i64,
) -> Result<EmbeddingArtifactManifest> {
    validate_embedding_artifact_manifest_input(&input)?;

    if let Some(existing) = get_embedding_artifact_manifest_by_id(conn, artifact_id)? {
        return Ok(existing);
    }

    let run_body = || -> Result<EmbeddingArtifactManifest> {
        insert_embedding_artifact_manifest_row(conn, artifact_id, &input, created_at_ms, updated_at_ms)?;
        resolve_embedding_artifact_identity_status(conn, artifact_id, &input, updated_at_ms)?;
        get_embedding_artifact_manifest_by_id(conn, artifact_id)?.ok_or_else(|| {
            anyhow!("embedding artifact not found after insert: {artifact_id}")
        })
    };

    if !conn.is_autocommit() {
        return run_body();
    }

    conn.execute_batch("BEGIN IMMEDIATE;")?;
    let result = run_body();
    match result {
        Ok(manifest) => {
            conn.execute_batch("COMMIT;")?;
            Ok(manifest)
        }
        Err(err) => {
            let _ = conn.execute_batch("ROLLBACK;");
            Err(err)
        }
    }
}

pub fn record_embedding_artifact_manifest(
    conn: &Connection,
    input: EmbeddingArtifactManifestInput<'_>,
) -> Result<EmbeddingArtifactManifest> {
    let artifact_id = uuid::Uuid::new_v4().to_string();
    let created_at_ms = input.created_at_ms.unwrap_or_else(now_ms);
    record_embedding_artifact_manifest_with_id(conn, &artifact_id, input, created_at_ms, created_at_ms)
}

pub fn create_embedding_artifact_manifest(
    conn: &Connection,
    key: &[u8; 32],
    input: EmbeddingArtifactManifestInput<'_>,
) -> Result<EmbeddingArtifactManifest> {
    let artifact_id = uuid::Uuid::new_v4().to_string();
    let created_at_ms = input.created_at_ms.unwrap_or_else(now_ms);
    let manifest = record_embedding_artifact_manifest_with_id(
        conn,
        &artifact_id,
        input.clone(),
        created_at_ms,
        created_at_ms,
    )?;

    let device_id = get_or_create_device_id(conn)?;
    let seq = next_device_seq(conn, &device_id)?;
    let op = serde_json::json!({
        "op_id": uuid::Uuid::new_v4().to_string(),
        "device_id": device_id,
        "seq": seq,
        "ts_ms": created_at_ms,
        "type": "embedding.artifact.upsert.v1",
        "payload": {
            "artifact_id": manifest.artifact_id,
            "source_kind": manifest.source_kind,
            "source_id": manifest.source_id,
            "source_revision": manifest.source_revision,
            "chunk_hash": manifest.chunk_hash,
            "chunk_ordinal": manifest.chunk_ordinal,
            "profile_id": manifest.profile_id,
            "producer_device_id": manifest.producer_device_id,
            "producer_class": manifest.producer_class,
            "quality_tier": manifest.quality_tier,
            "vector_format": manifest.vector_format,
            "dimension": manifest.dimension,
            "blob_ref": manifest.blob_ref,
            "created_at_ms": manifest.created_at_ms,
            "updated_at_ms": manifest.updated_at_ms,
        }
    });
    insert_oplog(conn, key, &op)?;
    Ok(manifest)
}

pub fn import_embedding_artifact_manifest(
    conn: &Connection,
    artifact_id: &str,
    input: EmbeddingArtifactManifestInput<'_>,
    created_at_ms: i64,
    updated_at_ms: i64,
) -> Result<EmbeddingArtifactManifest> {
    record_embedding_artifact_manifest_with_id(conn, artifact_id, input, created_at_ms, updated_at_ms)
}

pub fn clone_embedding_artifact_manifest_for_source(
    conn: &Connection,
    key: &[u8; 32],
    source_kind: &str,
    source_id: &str,
    source_revision: i64,
    chunk_hash: &str,
    chunk_ordinal: i64,
    cache_hit: &EmbeddingArtifactManifest,
) -> Result<EmbeddingArtifactManifest> {
    create_embedding_artifact_manifest(
        conn,
        key,
        EmbeddingArtifactManifestInput {
            source_kind,
            source_id,
            source_revision,
            chunk_hash,
            chunk_ordinal,
            profile_id: cache_hit.profile_id.as_str(),
            producer_device_id: cache_hit.producer_device_id.as_deref(),
            producer_class: cache_hit.producer_class.as_str(),
            quality_tier: cache_hit.quality_tier.as_str(),
            vector_format: cache_hit.vector_format.as_str(),
            dimension: cache_hit.dimension,
            blob_ref: cache_hit.blob_ref.as_str(),
            created_at_ms: Some(now_ms()),
        },
    )
}

pub fn get_embedding_artifact_manifest_by_id(
    conn: &Connection,
    artifact_id: &str,
) -> Result<Option<EmbeddingArtifactManifest>> {
    let mut stmt = conn.prepare(
        r#"SELECT artifact_id,
                  source_kind,
                  source_id,
                  source_revision,
                  chunk_hash,
                  chunk_ordinal,
                  profile_id,
                  producer_device_id,
                  producer_class,
                  quality_tier,
                  vector_format,
                  dimension,
                  blob_ref,
                  status,
                  supersedes_artifact_id,
                  created_at_ms,
                  updated_at_ms
           FROM embedding_artifact_manifests
           WHERE artifact_id = ?1"#,
    )?;

    stmt.query_row(params![artifact_id], read_embedding_artifact_manifest)
        .optional()
        .map_err(Into::into)
}

pub fn list_embedding_artifact_manifests_for_identity(
    conn: &Connection,
    source_kind: &str,
    source_id: &str,
    source_revision: i64,
    chunk_hash: &str,
    profile_id: &str,
) -> Result<Vec<EmbeddingArtifactManifest>> {
    let mut manifests = list_embedding_artifact_candidates(
        conn,
        source_kind,
        source_id,
        source_revision,
        chunk_hash,
        profile_id,
    )?;

    manifests.sort_by(|left, right| {
        embedding_artifact_sort_key(right)
            .expect("right sort key")
            .cmp(&embedding_artifact_sort_key(left).expect("left sort key"))
    });
    Ok(manifests)
}

pub fn get_active_embedding_artifact_for_identity(
    conn: &Connection,
    source_kind: &str,
    source_id: &str,
    source_revision: i64,
    chunk_hash: &str,
    profile_id: &str,
) -> Result<Option<EmbeddingArtifactManifest>> {
    let manifests = list_embedding_artifact_manifests_for_identity(
        conn,
        source_kind,
        source_id,
        source_revision,
        chunk_hash,
        profile_id,
    )?;

    Ok(manifests.into_iter().find(|manifest| manifest.status == "ready"))
}

pub fn find_best_embedding_artifact_cache_hit(
    conn: &Connection,
    chunk_hash: &str,
    profile_id: &str,
) -> Result<Option<EmbeddingArtifactManifest>> {
    let mut stmt = conn.prepare(
        r#"SELECT artifact_id,
                  source_kind,
                  source_id,
                  source_revision,
                  chunk_hash,
                  chunk_ordinal,
                  profile_id,
                  producer_device_id,
                  producer_class,
                  quality_tier,
                  vector_format,
                  dimension,
                  blob_ref,
                  status,
                  supersedes_artifact_id,
                  created_at_ms,
                  updated_at_ms
           FROM embedding_artifact_manifests
           WHERE chunk_hash = ?1
             AND profile_id = ?2
             AND status = 'ready'"#,
    )?;

    let mut rows = stmt.query(params![chunk_hash.trim(), profile_id.trim()])?;
    let mut manifests = Vec::new();
    while let Some(row) = rows.next()? {
        manifests.push(read_embedding_artifact_manifest(row)?);
    }

    let Some(best) = choose_best_embedding_artifact(&manifests)? else {
        return Ok(None);
    };
    Ok(Some(best.clone()))
}

pub fn list_active_embedding_artifacts_for_source_revision(
    conn: &Connection,
    source_kind: &str,
    source_id: &str,
    source_revision: i64,
    profile_id: &str,
) -> Result<Vec<EmbeddingArtifactManifest>> {
    let mut stmt = conn.prepare(
        r#"SELECT artifact_id,
                  source_kind,
                  source_id,
                  source_revision,
                  chunk_hash,
                  chunk_ordinal,
                  profile_id,
                  producer_device_id,
                  producer_class,
                  quality_tier,
                  vector_format,
                  dimension,
                  blob_ref,
                  status,
                  supersedes_artifact_id,
                  created_at_ms,
                  updated_at_ms
           FROM embedding_artifact_manifests
           WHERE source_kind = ?1
             AND source_id = ?2
             AND source_revision = ?3
             AND profile_id = ?4
             AND status = 'ready'
           ORDER BY chunk_ordinal ASC, created_at_ms DESC, artifact_id DESC"#,
    )?;

    let mut rows = stmt.query(params![
        source_kind.trim(),
        source_id.trim(),
        source_revision,
        profile_id.trim(),
    ])?;
    let mut out = Vec::new();
    while let Some(row) = rows.next()? {
        out.push(read_embedding_artifact_manifest(row)?);
    }
    Ok(out)
}

pub fn list_distinct_embedding_artifact_blob_refs(conn: &Connection) -> Result<Vec<String>> {
    let mut stmt = conn.prepare(
        r#"SELECT DISTINCT blob_ref
           FROM embedding_artifact_manifests
           WHERE status = 'ready'
           ORDER BY created_at_ms ASC, blob_ref ASC"#,
    )?;
    let mut rows = stmt.query([])?;
    let mut out = Vec::new();
    while let Some(row) = rows.next()? {
        out.push(row.get(0)?);
    }
    Ok(out)
}
