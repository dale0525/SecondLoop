use std::path::Path;

use anyhow::{anyhow, Result};

use crate::{db, knowledge};

fn key_from_bytes(bytes: Vec<u8>) -> Result<[u8; 32]> {
    if bytes.len() != 32 {
        return Err(anyhow!("invalid key length"));
    }
    let mut key = [0u8; 32];
    key.copy_from_slice(&bytes);
    Ok(key)
}

fn read_knowledge_debug_stats(
    conn: &rusqlite::Connection,
) -> Result<knowledge::KnowledgeDebugStats> {
    let (
        total_documents,
        generated_documents,
        summary_documents,
        source_documents,
        preference_documents,
        profile_documents,
        event_documents,
        pattern_documents,
        last_synthesis_at_ms,
    ) = conn.query_row(
        r#"
        SELECT
            COUNT(*),
            COALESCE(SUM(CASE WHEN origin_type = 'generated' THEN 1 ELSE 0 END), 0),
            COALESCE(SUM(CASE WHEN source_kind = 'summary' AND origin_type != 'generated' THEN 1 ELSE 0 END), 0),
            COALESCE(SUM(CASE WHEN origin_type != 'generated' AND source_kind != 'summary' THEN 1 ELSE 0 END), 0),
            COALESCE(SUM(CASE WHEN origin_type = 'generated' AND document_id LIKE 'generated:preference:%' THEN 1 ELSE 0 END), 0),
            COALESCE(SUM(CASE WHEN origin_type = 'generated' AND document_id LIKE 'generated:profile:%' THEN 1 ELSE 0 END), 0),
            COALESCE(SUM(CASE WHEN origin_type = 'generated' AND document_id LIKE 'generated:event:%' THEN 1 ELSE 0 END), 0),
            COALESCE(SUM(CASE WHEN origin_type = 'generated' AND document_id LIKE 'generated:pattern:%' THEN 1 ELSE 0 END), 0),
            MAX(CASE WHEN origin_type = 'generated' THEN updated_at_ms END)
        FROM knowledge_documents
        "#,
        [],
        |row| {
            Ok((
                row.get(0)?,
                row.get(1)?,
                row.get(2)?,
                row.get(3)?,
                row.get(4)?,
                row.get(5)?,
                row.get(6)?,
                row.get(7)?,
                row.get(8)?,
            ))
        },
    )?;
    let (usage_stat_documents, last_retrieved_at_ms) = conn.query_row(
        "SELECT COUNT(*), MAX(last_retrieved_at_ms) FROM knowledge_document_usage",
        [],
        |row| Ok((row.get(0)?, row.get(1)?)),
    )?;

    Ok(knowledge::KnowledgeDebugStats {
        total_documents,
        generated_documents,
        source_documents,
        summary_documents,
        preference_documents,
        profile_documents,
        event_documents,
        pattern_documents,
        usage_stat_documents,
        last_synthesis_at_ms,
        last_retrieved_at_ms,
        generated_memory_retrieval_enabled: true,
        hotness_rerank_enabled: true,
        session_digest_enabled: true,
    })
}

#[flutter_rust_bridge::frb]
pub fn db_get_knowledge_index_status(
    app_dir: String,
    key: Vec<u8>,
) -> Result<knowledge::KnowledgeIndexStatus> {
    let key = key_from_bytes(key)?;
    let conn = db::open(Path::new(&app_dir))?;
    knowledge::read_knowledge_index_status(&conn, &key)
}

#[flutter_rust_bridge::frb]
pub fn db_request_knowledge_rebuild(app_dir: String, key: Vec<u8>) -> Result<()> {
    let key = key_from_bytes(key)?;
    let conn = db::open(Path::new(&app_dir))?;
    knowledge::ensure_knowledge_rebuild_requested(&conn)?;
    let _ = knowledge::process_pending_knowledge_index_jobs_active(&conn, &key, 1);
    Ok(())
}

#[flutter_rust_bridge::frb]
pub fn db_process_pending_knowledge_index_jobs(
    app_dir: String,
    key: Vec<u8>,
    limit: u32,
) -> Result<u32> {
    let key = key_from_bytes(key)?;
    let conn = db::open(Path::new(&app_dir))?;
    Ok(knowledge::process_pending_knowledge_index_jobs_active(&conn, &key, limit as usize)? as u32)
}

#[flutter_rust_bridge::frb]
pub fn db_cancel_knowledge_rebuild(app_dir: String, key: Vec<u8>) -> Result<()> {
    let key = key_from_bytes(key)?;
    let conn = db::open(Path::new(&app_dir))?;
    knowledge::cancel_knowledge_rebuild(&conn, &key)
}

#[flutter_rust_bridge::frb]
pub fn db_get_knowledge_debug_stats(
    app_dir: String,
    key: Vec<u8>,
) -> Result<knowledge::KnowledgeDebugStats> {
    let _validated_key = key_from_bytes(key)?;
    let conn = db::open(Path::new(&app_dir))?;
    read_knowledge_debug_stats(&conn)
}

#[flutter_rust_bridge::frb]
pub fn db_list_knowledge_documents(
    app_dir: String,
    key: Vec<u8>,
    limit: u32,
    offset: u32,
) -> Result<Vec<knowledge::ContentKnowledgeDocument>> {
    let key = key_from_bytes(key)?;
    let conn = db::open(Path::new(&app_dir))?;
    knowledge::list_knowledge_documents(&conn, &key, limit as usize, offset as usize)
}

#[flutter_rust_bridge::frb]
pub fn db_list_generated_memory_documents(
    app_dir: String,
    key: Vec<u8>,
    limit: u32,
    offset: u32,
) -> Result<Vec<knowledge::ContentKnowledgeDocument>> {
    let key = key_from_bytes(key)?;
    let conn = db::open(Path::new(&app_dir))?;
    knowledge::list_knowledge_documents_by_origin(
        &conn,
        &key,
        knowledge::KnowledgeOriginType::Generated,
        limit as usize,
        offset as usize,
    )
}

#[flutter_rust_bridge::frb]
#[allow(clippy::too_many_arguments)]
pub fn db_upsert_knowledge_memory_feedback(
    app_dir: String,
    key: Vec<u8>,
    document_id: String,
    status: Option<knowledge::KnowledgeMemoryStatus>,
    use_for_ask_ai: bool,
    is_deleted: bool,
    marked_inaccurate: bool,
    corrected_title: Option<String>,
    corrected_summary: Option<String>,
) -> Result<knowledge::KnowledgeMemoryFeedback> {
    let _validated_key = key_from_bytes(key)?;
    let conn = db::open(Path::new(&app_dir))?;
    db::upsert_knowledge_memory_feedback(
        &conn,
        &document_id,
        status,
        use_for_ask_ai,
        is_deleted,
        marked_inaccurate,
        corrected_title,
        corrected_summary,
    )
}

#[flutter_rust_bridge::frb]
pub fn db_list_knowledge_units(
    app_dir: String,
    key: Vec<u8>,
    document_id: String,
    unit_kind: Option<knowledge::KnowledgeUnitKind>,
    limit: u32,
    offset: u32,
) -> Result<Vec<knowledge::KnowledgeUnit>> {
    let key = key_from_bytes(key)?;
    let conn = db::open(Path::new(&app_dir))?;
    knowledge::list_knowledge_units(
        &conn,
        &key,
        &document_id,
        unit_kind,
        limit as usize,
        offset as usize,
    )
}

#[flutter_rust_bridge::frb]
pub fn db_search_knowledge(
    app_dir: String,
    key: Vec<u8>,
    query: String,
    conversation_id: Option<String>,
    document_id: Option<String>,
    limit: u32,
) -> Result<Vec<knowledge::KnowledgeSearchResult>> {
    let key = key_from_bytes(key)?;
    let conn = db::open(Path::new(&app_dir))?;
    let request = knowledge::normalize_retrieval_request(
        &query,
        conversation_id,
        document_id,
        Some(limit.max(1) as usize),
        None,
        None,
    );
    knowledge::search_knowledge(&conn, &key, &request)
}

#[flutter_rust_bridge::frb]
pub fn db_get_knowledge_document(
    app_dir: String,
    key: Vec<u8>,
    document_id: String,
) -> Result<knowledge::KnowledgeViewerDocument> {
    let key = key_from_bytes(key)?;
    let conn = db::open(Path::new(&app_dir))?;
    knowledge::read_knowledge_viewer_document(&conn, &key, &document_id)
}

#[flutter_rust_bridge::frb]
pub fn db_list_knowledge_viewer_units(
    app_dir: String,
    key: Vec<u8>,
    document_id: String,
    unit_kind: Option<knowledge::KnowledgeUnitKind>,
    limit: u32,
    offset: u32,
) -> Result<knowledge::KnowledgeViewerPage> {
    let key = key_from_bytes(key)?;
    let conn = db::open(Path::new(&app_dir))?;
    knowledge::list_knowledge_viewer_units(
        &conn,
        &key,
        &document_id,
        unit_kind,
        limit as usize,
        offset as usize,
    )
}

#[flutter_rust_bridge::frb]
pub fn db_list_recent_knowledge_viewer_units(
    app_dir: String,
    key: Vec<u8>,
    document_id: String,
    unit_kind: Option<knowledge::KnowledgeUnitKind>,
    limit: u32,
) -> Result<Vec<knowledge::KnowledgeUnit>> {
    let key = key_from_bytes(key)?;
    let conn = db::open(Path::new(&app_dir))?;
    knowledge::list_recent_knowledge_viewer_units(
        &conn,
        &key,
        &document_id,
        unit_kind,
        limit as usize,
    )
}

#[flutter_rust_bridge::frb]
pub fn db_search_knowledge_document_units(
    app_dir: String,
    key: Vec<u8>,
    document_id: String,
    query: String,
    limit: u32,
) -> Result<Vec<knowledge::KnowledgeSearchResult>> {
    let key = key_from_bytes(key)?;
    let conn = db::open(Path::new(&app_dir))?;
    knowledge::search_document_knowledge(&conn, &key, &document_id, &query, limit as usize)
}

#[flutter_rust_bridge::frb]
pub fn db_list_knowledge_units_around_anchor(
    app_dir: String,
    key: Vec<u8>,
    document_id: String,
    anchor: knowledge::KnowledgeAnchorSet,
    before: u32,
    after: u32,
) -> Result<Vec<knowledge::KnowledgeUnit>> {
    let key = key_from_bytes(key)?;
    let conn = db::open(Path::new(&app_dir))?;
    knowledge::list_knowledge_units_around_anchor(
        &conn,
        &key,
        &document_id,
        &anchor,
        before as usize,
        after as usize,
    )
}
