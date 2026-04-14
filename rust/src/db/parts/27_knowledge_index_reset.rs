pub fn reset_knowledge_index(conn: &Connection) -> Result<()> {
    conn.execute_batch(
        r#"
DELETE FROM knowledge_document_usage;
DELETE FROM knowledge_page_lints;
DELETE FROM knowledge_page_history;
DELETE FROM knowledge_page_versions;
DELETE FROM knowledge_pages;
DELETE FROM knowledge_claims;
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
