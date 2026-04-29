fn apply_embedding_artifact_upsert(
    conn: &Connection,
    payload: &serde_json::Value,
) -> Result<()> {
    let artifact_id = payload["artifact_id"]
        .as_str()
        .ok_or_else(|| anyhow!("embedding.artifact.upsert.v1 missing artifact_id"))?;
    let source_kind = payload["source_kind"]
        .as_str()
        .ok_or_else(|| anyhow!("embedding.artifact.upsert.v1 missing source_kind"))?;
    let source_id = payload["source_id"]
        .as_str()
        .ok_or_else(|| anyhow!("embedding.artifact.upsert.v1 missing source_id"))?;
    let source_revision = payload["source_revision"]
        .as_i64()
        .ok_or_else(|| anyhow!("embedding.artifact.upsert.v1 missing source_revision"))?;
    let chunk_hash = payload["chunk_hash"]
        .as_str()
        .ok_or_else(|| anyhow!("embedding.artifact.upsert.v1 missing chunk_hash"))?;
    let chunk_ordinal = payload["chunk_ordinal"]
        .as_i64()
        .ok_or_else(|| anyhow!("embedding.artifact.upsert.v1 missing chunk_ordinal"))?;
    let profile_id = payload["profile_id"]
        .as_str()
        .ok_or_else(|| anyhow!("embedding.artifact.upsert.v1 missing profile_id"))?;
    let producer_class = payload["producer_class"]
        .as_str()
        .ok_or_else(|| anyhow!("embedding.artifact.upsert.v1 missing producer_class"))?;
    let quality_tier = payload["quality_tier"]
        .as_str()
        .ok_or_else(|| anyhow!("embedding.artifact.upsert.v1 missing quality_tier"))?;
    let vector_format = payload["vector_format"]
        .as_str()
        .ok_or_else(|| anyhow!("embedding.artifact.upsert.v1 missing vector_format"))?;
    let dimension = payload["dimension"]
        .as_i64()
        .ok_or_else(|| anyhow!("embedding.artifact.upsert.v1 missing dimension"))?;
    let blob_ref = payload["blob_ref"]
        .as_str()
        .ok_or_else(|| anyhow!("embedding.artifact.upsert.v1 missing blob_ref"))?;
    let created_at_ms = payload["created_at_ms"]
        .as_i64()
        .ok_or_else(|| anyhow!("embedding.artifact.upsert.v1 missing created_at_ms"))?;
    let updated_at_ms = payload["updated_at_ms"]
        .as_i64()
        .ok_or_else(|| anyhow!("embedding.artifact.upsert.v1 missing updated_at_ms"))?;

    crate::db::import_embedding_artifact_manifest(
        conn,
        artifact_id,
        crate::db::EmbeddingArtifactManifestInput {
            source_kind,
            source_id,
            source_revision,
            chunk_hash,
            chunk_ordinal,
            profile_id,
            producer_device_id: payload["producer_device_id"].as_str(),
            producer_class,
            quality_tier,
            vector_format,
            dimension,
            blob_ref,
            created_at_ms: Some(created_at_ms),
        },
        created_at_ms,
        updated_at_ms,
    )?;
    Ok(())
}
