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
