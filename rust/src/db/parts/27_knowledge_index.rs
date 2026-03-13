fn knowledge_document_text_aad(document_id: &str, field: &str) -> Vec<u8> {
    format!("knowledge.document.{field}:{document_id}").into_bytes()
}

fn knowledge_unit_text_aad(unit_id: &str, field: &str) -> Vec<u8> {
    format!("knowledge.unit.{field}:{unit_id}").into_bytes()
}

pub fn encode_knowledge_document_text(
    key: &[u8; 32],
    document_id: &str,
    field: &str,
    text: &str,
) -> Result<Vec<u8>> {
    encrypt_bytes(key, text.as_bytes(), &knowledge_document_text_aad(document_id, field))
}

pub fn decode_knowledge_document_text(
    key: &[u8; 32],
    document_id: &str,
    field: &str,
    blob: &[u8],
) -> Result<String> {
    let bytes = decrypt_bytes(key, blob, &knowledge_document_text_aad(document_id, field))?;
    String::from_utf8(bytes).map_err(|_| anyhow!("knowledge document text is not valid utf-8"))
}

pub fn encode_knowledge_unit_text(
    key: &[u8; 32],
    unit_id: &str,
    field: &str,
    text: &str,
) -> Result<Vec<u8>> {
    encrypt_bytes(key, text.as_bytes(), &knowledge_unit_text_aad(unit_id, field))
}

pub fn decode_knowledge_unit_text(
    key: &[u8; 32],
    unit_id: &str,
    field: &str,
    blob: &[u8],
) -> Result<String> {
    let bytes = decrypt_bytes(key, blob, &knowledge_unit_text_aad(unit_id, field))?;
    String::from_utf8(bytes).map_err(|_| anyhow!("knowledge unit text is not valid utf-8"))
}

pub fn ensure_knowledge_rebuild_state_defaults(conn: &Connection) -> Result<()> {
    conn.execute(
        r#"INSERT OR IGNORE INTO knowledge_rebuild_state(
               state_key,
               knowledge_schema_version,
               normalization_version,
               segmentation_version,
               embedding_policy_version,
               retrieval_policy_version,
               last_indexed_model_name,
               last_indexed_dim,
               status,
               rebuild_required,
               stale_reason,
               last_error,
               last_rebuild_started_at_ms,
               last_rebuild_completed_at_ms,
               current_document_id,
               current_stage,
               documents_indexed,
               units_indexed,
               embeddings_indexed,
               total_documents,
               cancel_requested
           ) VALUES (?1, ?2, ?3, ?4, ?5, ?6, NULL, NULL, 'empty', 0, NULL, NULL, NULL, NULL, NULL, NULL, 0, 0, 0, 0, 0)"#,
        params![
            1i64,
            crate::knowledge::KNOWLEDGE_SCHEMA_VERSION,
            crate::knowledge::KNOWLEDGE_NORMALIZATION_VERSION,
            crate::knowledge::KNOWLEDGE_SEGMENTATION_VERSION,
            crate::knowledge::KNOWLEDGE_EMBEDDING_POLICY_VERSION,
            crate::knowledge::KNOWLEDGE_RETRIEVAL_POLICY_VERSION,
        ],
    )?;
    Ok(())
}

pub fn load_knowledge_usage_map(
    conn: &Connection,
    document_ids: &std::collections::BTreeSet<String>,
) -> Result<std::collections::BTreeMap<String, crate::knowledge::usage::KnowledgeUsageStats>> {
    let mut out = std::collections::BTreeMap::new();
    if document_ids.is_empty() {
        return Ok(out);
    }

    let mut stmt = conn.prepare(
        r#"SELECT document_id, retrieve_count, last_retrieved_at_ms
           FROM knowledge_document_usage
           WHERE document_id = ?1"#,
    )?;

    for document_id in document_ids {
        let stats = stmt.query_row(params![document_id], |row| {
            Ok(crate::knowledge::usage::KnowledgeUsageStats {
                retrieve_count: row.get(1)?,
                last_retrieved_at_ms: row.get(2)?,
            })
        });
        if let Ok(stats) = stats {
            out.insert(document_id.clone(), stats);
        }
    }

    Ok(out)
}

pub fn touch_knowledge_documents_usage(conn: &Connection, document_ids: &[String], now_ms: i64) -> Result<usize> {
    let unique = document_ids
        .iter()
        .filter(|value| !value.trim().is_empty())
        .cloned()
        .collect::<std::collections::BTreeSet<_>>();
    if unique.is_empty() {
        return Ok(0);
    }

    let tx = conn.unchecked_transaction()?;
    for document_id in &unique {
        tx.execute(
            r#"INSERT INTO knowledge_document_usage(document_id, retrieve_count, last_retrieved_at_ms)
               VALUES (?1, 1, ?2)
               ON CONFLICT(document_id)
               DO UPDATE SET
                 retrieve_count = knowledge_document_usage.retrieve_count + 1,
                 last_retrieved_at_ms = excluded.last_retrieved_at_ms"#,
            params![document_id, now_ms],
        )?;
    }
    tx.commit()?;
    Ok(unique.len())
}

pub fn reset_knowledge_index(conn: &Connection) -> Result<()> {
    conn.execute_batch(
        r#"
DELETE FROM knowledge_document_usage;
DELETE FROM knowledge_embeddings;
DELETE FROM knowledge_index_jobs;
DELETE FROM knowledge_units;
DELETE FROM knowledge_documents;
UPDATE knowledge_rebuild_state
SET status = 'empty',
    rebuild_required = 0,
    stale_reason = NULL,
    last_error = NULL,
    last_rebuild_started_at_ms = NULL,
    last_rebuild_completed_at_ms = NULL,
    current_document_id = NULL,
    current_stage = NULL,
    documents_indexed = 0,
    units_indexed = 0,
    embeddings_indexed = 0,
    total_documents = 0,
    cancel_requested = 0,
    last_indexed_model_name = NULL,
    last_indexed_dim = NULL
WHERE state_key = 1;
"#,
    )?;
    ensure_knowledge_rebuild_state_defaults(conn)
}

pub fn read_knowledge_embedding_model_state(conn: &Connection) -> Result<(String, i64)> {
    let model_name = get_active_embedding_model_name(conn)?
        .unwrap_or_else(|| crate::embedding::DEFAULT_MODEL_NAME.to_string());
    let dim = current_embedding_dim(conn)? as i64;
    Ok((model_name, dim))
}
