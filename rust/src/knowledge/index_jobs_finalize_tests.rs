use crate::db;
use crate::knowledge::process_pending_knowledge_index_jobs_active;
use rusqlite::params;

#[test]
fn knowledge_finalize_retry_does_not_precommit_progress_counters() {
    let dir = tempfile::tempdir().expect("tempdir");
    let app_dir = dir.path();
    let conn = db::open(app_dir).expect("open");
    let key = [19u8; 32];
    let document_id = "message:finalize-counter-rollback";

    db::ensure_knowledge_rebuild_state_defaults(&conn).expect("state defaults");
    conn.execute(
        "UPDATE knowledge_rebuild_state SET status = 'running', total_documents = 1 WHERE state_key = 1",
        [],
    )
    .expect("set running");

    seed_knowledge_document(&conn, &key, document_id, "document for finalize rollback");
    seed_knowledge_unit(
        &conn,
        &key,
        &format!("{document_id}:chunk:0000"),
        document_id,
        "chunk",
        0,
        "chunk unit text",
    );
    conn.execute(
        r#"INSERT INTO knowledge_index_jobs(
               document_id, stage, status, attempts, next_retry_at_ms, last_error, created_at_ms, updated_at_ms
           ) VALUES (?1, 'finalize', 'pending', 0, NULL, NULL, 1, 1)"#,
        params![document_id],
    )
    .expect("insert finalize job");
    conn.execute_batch(
        r#"CREATE TEMP TRIGGER fail_finalize_mark_done
           BEFORE UPDATE ON knowledge_index_jobs
           WHEN NEW.document_id = 'message:finalize-counter-rollback'
             AND NEW.stage = 'finalize'
             AND NEW.status = 'done'
           BEGIN
             SELECT RAISE(FAIL, 'forced finalize mark_job_done failure');
           END;"#,
    )
    .expect("create finalize failure trigger");

    let error = process_pending_knowledge_index_jobs_active(&conn, &key, 1)
        .expect_err("finalize mark_job_done should fail");
    assert!(error
        .to_string()
        .contains("forced finalize mark_job_done failure"));

    let progress: (i64, i64) = conn
        .query_row(
            r#"SELECT documents_indexed, units_indexed
               FROM knowledge_rebuild_state
               WHERE state_key = 1"#,
            [],
            |row| Ok((row.get(0)?, row.get(1)?)),
        )
        .expect("progress counters");
    assert_eq!(progress, (0, 0));

    let finalize_status: String = conn
        .query_row(
            r#"SELECT status
               FROM knowledge_index_jobs
               WHERE document_id = ?1 AND stage = 'finalize'"#,
            params![document_id],
            |row| row.get(0),
        )
        .expect("finalize status");
    assert_eq!(finalize_status, "failed");
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
