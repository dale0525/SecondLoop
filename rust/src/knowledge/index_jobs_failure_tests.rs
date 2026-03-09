use crate::crypto::encrypt_bytes;
use crate::db;
use crate::knowledge::process_pending_knowledge_index_jobs_active;
use rusqlite::params;

#[test]
fn knowledge_mark_job_failed_rolls_back_job_update_when_state_write_fails() {
    let dir = tempfile::tempdir().expect("tempdir");
    let app_dir = dir.path();
    let conn = db::open(app_dir).expect("open");
    let key = [20u8; 32];
    let document_id = "message:failed-job-rollback";
    let anchor_json = serde_json::json!({}).to_string();
    let raw_bad = encrypt_bytes(
        &key,
        &[0xff, 0xfe],
        format!("knowledge.document.raw:{document_id}").as_bytes(),
    )
    .expect("bad raw");
    let normalized = db::encode_knowledge_document_text(
        &key,
        document_id,
        "normalized",
        "broken knowledge document",
    )
    .expect("normalized");

    db::ensure_knowledge_rebuild_state_defaults(&conn).expect("state defaults");
    conn.execute(
        "UPDATE knowledge_rebuild_state SET status = 'running' WHERE state_key = 1",
        [],
    )
    .expect("set running");
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
            raw_bad,
            normalized,
            crate::knowledge::KNOWLEDGE_SCHEMA_VERSION,
            crate::knowledge::KNOWLEDGE_NORMALIZATION_VERSION,
            crate::knowledge::KNOWLEDGE_SEGMENTATION_VERSION,
            crate::knowledge::KNOWLEDGE_EMBEDDING_POLICY_VERSION,
            crate::knowledge::KNOWLEDGE_RETRIEVAL_POLICY_VERSION,
        ],
    )
    .expect("insert doc");
    conn.execute(
        r#"INSERT INTO knowledge_index_jobs(
               document_id, stage, status, attempts, next_retry_at_ms, last_error, created_at_ms, updated_at_ms
           ) VALUES (?1, 'normalize', 'pending', 0, NULL, NULL, 1, 1)"#,
        params![document_id],
    )
    .expect("insert job");
    conn.execute_batch(
        r#"CREATE TEMP TRIGGER fail_mark_job_failed_state_update
           BEFORE UPDATE ON knowledge_rebuild_state
           WHEN NEW.status = 'failed'
           BEGIN
             SELECT RAISE(FAIL, 'forced rebuild_state failure');
           END;"#,
    )
    .expect("create trigger");

    let error = process_pending_knowledge_index_jobs_active(&conn, &key, 1)
        .expect_err("mark_job_failed should surface the state write failure");
    assert!(error
        .to_string()
        .contains("failed to record knowledge job failure"));
    assert!(error.to_string().contains("forced rebuild_state failure"));

    let job_row: (String, i64, Option<String>) = conn
        .query_row(
            r#"SELECT status, attempts, last_error
               FROM knowledge_index_jobs
               WHERE document_id = ?1 AND stage = 'normalize'"#,
            params![document_id],
            |row| Ok((row.get(0)?, row.get(1)?, row.get(2)?)),
        )
        .expect("job row");
    assert_eq!(job_row, ("pending".to_string(), 0, None));

    let rebuild_status: String = conn
        .query_row(
            "SELECT status FROM knowledge_rebuild_state WHERE state_key = 1",
            [],
            |row| row.get(0),
        )
        .expect("rebuild status");
    assert_eq!(rebuild_status, "running");
}

#[test]
fn knowledge_stage_commit_failure_rolls_back_and_records_failed_job() {
    let dir = tempfile::tempdir().expect("tempdir");
    let app_dir = dir.path();
    let conn = db::open(app_dir).expect("open");
    let key = [21u8; 32];
    let document_id = "message:commit-failure";
    let anchor_json = serde_json::json!({}).to_string();
    let raw =
        db::encode_knowledge_document_text(&key, document_id, "raw", "raw text").expect("raw");
    let normalized =
        db::encode_knowledge_document_text(&key, document_id, "normalized", "normalized text")
            .expect("normalized");

    db::ensure_knowledge_rebuild_state_defaults(&conn).expect("state defaults");
    conn.execute(
        "UPDATE knowledge_rebuild_state SET status = 'running' WHERE state_key = 1",
        [],
    )
    .expect("set running");
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
    .expect("insert doc");
    conn.execute(
        r#"INSERT INTO knowledge_index_jobs(
               document_id, stage, status, attempts, next_retry_at_ms, last_error, created_at_ms, updated_at_ms
           ) VALUES (?1, 'normalize', 'pending', 0, NULL, NULL, 1, 1)"#,
        params![document_id],
    )
    .expect("insert job");
    conn.execute_batch(
        r#"CREATE TEMP TABLE fail_commit_parent(id INTEGER PRIMARY KEY);
           CREATE TEMP TABLE fail_commit_child(
             id INTEGER PRIMARY KEY,
             parent_id INTEGER,
             FOREIGN KEY(parent_id) REFERENCES fail_commit_parent(id) DEFERRABLE INITIALLY DEFERRED
           );
           CREATE TEMP TRIGGER fail_stage_commit_after_document_update
           AFTER UPDATE ON knowledge_documents
           BEGIN
             INSERT INTO fail_commit_child(id, parent_id)
             VALUES(COALESCE((SELECT MAX(id) + 1 FROM fail_commit_child), 1), 999);
           END;"#,
    )
    .expect("create commit failure trigger");

    let error = process_pending_knowledge_index_jobs_active(&conn, &key, 1)
        .expect_err("stage COMMIT failure should surface as an error");
    let error_text = error.to_string();
    assert!(
        error_text.contains("FOREIGN KEY constraint failed"),
        "unexpected error: {error_text}"
    );
    assert!(
        !error_text.contains("failed to record knowledge job failure"),
        "unexpected wrapped error: {error_text}"
    );

    let job_row: (String, i64, Option<i64>, Option<String>) = conn
        .query_row(
            r#"SELECT status, attempts, next_retry_at_ms, last_error
               FROM knowledge_index_jobs
               WHERE document_id = ?1 AND stage = 'normalize'"#,
            params![document_id],
            |row| Ok((row.get(0)?, row.get(1)?, row.get(2)?, row.get(3)?)),
        )
        .expect("job row");
    assert_eq!(job_row.0, "failed");
    assert_eq!(job_row.1, 1);
    assert!(job_row.2.is_some());
    assert!(job_row
        .3
        .as_deref()
        .unwrap_or_default()
        .contains("FOREIGN KEY constraint failed"));

    let rebuild_row: (String, Option<String>, Option<String>, Option<String>) = conn
        .query_row(
            r#"SELECT status, last_error, current_document_id, current_stage
               FROM knowledge_rebuild_state
               WHERE state_key = 1"#,
            [],
            |row| Ok((row.get(0)?, row.get(1)?, row.get(2)?, row.get(3)?)),
        )
        .expect("rebuild row");
    assert_eq!(rebuild_row.0, "failed");
    assert!(rebuild_row
        .1
        .as_deref()
        .unwrap_or_default()
        .contains("FOREIGN KEY constraint failed"));
    assert_eq!(rebuild_row.2.as_deref(), Some(document_id));
    assert_eq!(rebuild_row.3.as_deref(), Some("normalize"));

    conn.execute_batch("BEGIN IMMEDIATE; ROLLBACK;")
        .expect("transaction should be closed after commit failure handling");
}
