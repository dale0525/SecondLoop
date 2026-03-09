use crate::db;
use crate::knowledge::{
    list_knowledge_units, process_pending_knowledge_index_jobs_active, KnowledgeUnitKind,
};
use rusqlite::params;

const OVER_PAGE_UNIT_COUNT: usize = 10_001;

#[test]
fn knowledge_chunk_stage_pages_all_segment_units() {
    let dir = tempfile::tempdir().expect("tempdir");
    let app_dir = dir.path();
    let conn = db::open(app_dir).expect("open");
    let key = [17u8; 32];
    let document_id = "message:paged-segments";

    db::ensure_knowledge_rebuild_state_defaults(&conn).expect("state defaults");
    conn.execute(
        "UPDATE knowledge_rebuild_state SET status = 'running' WHERE state_key = 1",
        [],
    )
    .expect("set running");

    seed_knowledge_document(&conn, &key, document_id, "document body for chunk paging");
    conn.execute_batch("BEGIN IMMEDIATE;")
        .expect("begin unit seed transaction");
    for ordinal in 0..OVER_PAGE_UNIT_COUNT {
        let unit_id = format!("{document_id}:segment:{ordinal:05}");
        seed_knowledge_unit(
            &conn,
            &key,
            &unit_id,
            document_id,
            "segment",
            ordinal as i64,
            &large_unit_text("segment", ordinal, 193),
        );
    }
    conn.execute_batch("COMMIT;")
        .expect("commit unit seed transaction");
    conn.execute(
        r#"INSERT INTO knowledge_index_jobs(
               document_id, stage, status, attempts, next_retry_at_ms, last_error, created_at_ms, updated_at_ms
           ) VALUES (?1, 'chunk', 'pending', 0, NULL, NULL, 1, 1)"#,
        params![document_id],
    )
    .expect("insert chunk job");

    let processed = process_pending_knowledge_index_jobs_active(&conn, &key, 1)
        .expect("process chunk stage with paged segment units");
    assert_eq!(processed, 1);

    let chunks = list_knowledge_units(
        &conn,
        &key,
        document_id,
        Some(KnowledgeUnitKind::Chunk),
        OVER_PAGE_UNIT_COUNT + 10,
        0,
    )
    .expect("load chunk units");
    assert_eq!(chunks.len(), OVER_PAGE_UNIT_COUNT);
    assert!(chunks
        .last()
        .expect("last chunk")
        .normalized_text
        .contains("segment-10000-token-000"));
}

#[test]
fn knowledge_embed_stage_pages_all_section_and_chunk_units() {
    let dir = tempfile::tempdir().expect("tempdir");
    let app_dir = dir.path();
    let conn = db::open(app_dir).expect("open");
    let key = [18u8; 32];
    let document_id = "message:paged-embeds";

    db::ensure_knowledge_rebuild_state_defaults(&conn).expect("state defaults");
    conn.execute(
        "UPDATE knowledge_rebuild_state SET status = 'running' WHERE state_key = 1",
        [],
    )
    .expect("set running");

    seed_knowledge_document(&conn, &key, document_id, "document body for embed paging");
    conn.execute_batch("BEGIN IMMEDIATE;")
        .expect("begin unit seed transaction");
    for ordinal in 0..OVER_PAGE_UNIT_COUNT {
        let section_id = format!("{document_id}:section:{ordinal:05}");
        seed_knowledge_unit(
            &conn,
            &key,
            &section_id,
            document_id,
            "section",
            ordinal as i64,
            &large_unit_text("section", ordinal, 8),
        );
        let chunk_id = format!("{document_id}:chunk:{ordinal:05}");
        seed_knowledge_unit(
            &conn,
            &key,
            &chunk_id,
            document_id,
            "chunk",
            ordinal as i64,
            &large_unit_text("chunk", ordinal, 8),
        );
    }
    conn.execute_batch("COMMIT;")
        .expect("commit unit seed transaction");
    conn.execute(
        r#"INSERT INTO knowledge_index_jobs(
               document_id, stage, status, attempts, next_retry_at_ms, last_error, created_at_ms, updated_at_ms
           ) VALUES (?1, 'embed', 'pending', 0, NULL, NULL, 1, 1)"#,
        params![document_id],
    )
    .expect("insert embed job");

    let processed = process_pending_knowledge_index_jobs_active(&conn, &key, 1)
        .expect("process embed stage with paged units");
    assert_eq!(processed, 1);

    let embedding_count: i64 = conn
        .query_row(
            "SELECT COUNT(*) FROM knowledge_embeddings WHERE target_id = ?1 OR target_id IN (SELECT unit_id FROM knowledge_units WHERE document_id = ?1)",
            params![document_id],
            |row| row.get(0),
        )
        .expect("embedding count");
    assert_eq!(embedding_count, 1 + (OVER_PAGE_UNIT_COUNT as i64 * 2));

    let last_section_id = format!("{document_id}:section:{:05}", OVER_PAGE_UNIT_COUNT - 1);
    let last_chunk_id = format!("{document_id}:chunk:{:05}", OVER_PAGE_UNIT_COUNT - 1);
    let last_unit_embeddings: i64 = conn
        .query_row(
            r#"SELECT COUNT(*)
               FROM knowledge_embeddings
               WHERE target_kind = 'unit'
                 AND target_id IN (?1, ?2)"#,
            params![last_section_id, last_chunk_id],
            |row| row.get(0),
        )
        .expect("last unit embeddings");
    assert_eq!(last_unit_embeddings, 2);
}

fn seed_knowledge_document(
    conn: &rusqlite::Connection,
    key: &[u8; 32],
    document_id: &str,
    text: &str,
) {
    let anchor_json = serde_json::json!({}).to_string();
    let raw = db::encode_knowledge_document_text(key, document_id, "raw", text)
        .expect("encode raw document");
    let normalized = db::encode_knowledge_document_text(key, document_id, "normalized", text)
        .expect("encode normalized document");
    conn.execute(
        r#"INSERT INTO knowledge_documents(
               document_id,
               origin_type,
               source_kind,
               role,
               language,
               quality_score,
               title,
               summary,
               anchor_json,
               raw_text,
               normalized_text,
               created_at_ms,
               updated_at_ms,
               schema_version,
               normalization_version,
               segmentation_version,
               embedding_policy_version,
               retrieval_policy_version,
               last_indexed_at_ms
           ) VALUES (?1, 'message', 'raw_text', 'body', NULL, 1.0, NULL, NULL, ?2, ?3, ?4, 1, 1, ?5, ?6, ?7, ?8, ?9, NULL)"#,
        params![
            document_id,
            anchor_json,
            raw,
            normalized,
            crate::knowledge::KNOWLEDGE_SCHEMA_VERSION,
            crate::knowledge::KNOWLEDGE_NORMALIZATION_VERSION,
            crate::knowledge::KNOWLEDGE_SEGMENTATION_VERSION,
            crate::knowledge::KNOWLEDGE_EMBEDDING_POLICY_VERSION,
            crate::knowledge::KNOWLEDGE_RETRIEVAL_POLICY_VERSION,
        ],
    )
    .expect("insert knowledge document");
}

fn seed_knowledge_unit(
    conn: &rusqlite::Connection,
    key: &[u8; 32],
    unit_id: &str,
    document_id: &str,
    unit_kind: &str,
    ordinal: i64,
    text: &str,
) {
    let anchor_json = serde_json::json!({}).to_string();
    let raw = db::encode_knowledge_unit_text(key, unit_id, "raw", text).expect("encode raw unit");
    let normalized = db::encode_knowledge_unit_text(key, unit_id, "normalized", text)
        .expect("encode normalized unit");
    conn.execute(
        r#"INSERT INTO knowledge_units(
               unit_id,
               document_id,
               parent_unit_id,
               unit_kind,
               source_kind,
               role,
               ordinal,
               token_count,
               anchor_json,
               raw_text,
               normalized_text,
               prev_unit_id,
               next_unit_id,
               created_at_ms,
               updated_at_ms
           ) VALUES (?1, ?2, NULL, ?3, 'raw_text', 'body', ?4, ?5, ?6, ?7, ?8, NULL, NULL, 1, 1)"#,
        params![
            unit_id,
            document_id,
            unit_kind,
            ordinal,
            text.split_whitespace().count() as i64,
            anchor_json,
            raw,
            normalized
        ],
    )
    .expect("insert knowledge unit");
}

fn large_unit_text(kind: &str, ordinal: usize, token_count: usize) -> String {
    (0..token_count)
        .map(|token| format!("{kind}-{ordinal:05}-token-{token:03}"))
        .collect::<Vec<_>>()
        .join(" ")
}
