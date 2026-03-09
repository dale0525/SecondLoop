use rusqlite::params;
use sha2::{Digest, Sha256};

use crate::crypto::encrypt_bytes;
use crate::db;
use crate::knowledge::embedding_batch::{
    average_piece_embeddings, prepare_embedding_inputs, EmbeddingBatchPolicy,
};
use crate::knowledge::index_jobs::failed_job_update;
use crate::knowledge::{
    ensure_knowledge_rebuild_requested, list_knowledge_documents,
    process_pending_knowledge_index_jobs_active, read_knowledge_index_status,
};

#[test]
fn knowledge_job_processes_stages_and_finishes_rebuild() {
    let dir = tempfile::tempdir().expect("tempdir");
    let app_dir = dir.path();
    let conn = db::open(app_dir).expect("open");
    let key = [9u8; 32];

    let conv = db::create_conversation(&conn, &key, "Inbox").expect("conversation");
    db::insert_message(&conn, &key, &conv.id, "user", "hello world from knowledge")
        .expect("message");

    ensure_knowledge_rebuild_requested(&conn).expect("request rebuild");
    let processed =
        process_pending_knowledge_index_jobs_active(&conn, &key, 32).expect("process jobs");
    assert!(processed > 0);

    let status = read_knowledge_index_status(&conn, &key).expect("status");
    assert_eq!(status.status, "complete");
    assert!(status.documents_indexed >= 1);
    assert!(status.units_indexed >= 1);
}

#[test]
fn knowledge_rebuild_detects_version_mismatch_after_policy_change() {
    let dir = tempfile::tempdir().expect("tempdir");
    let app_dir = dir.path();
    let conn = db::open(app_dir).expect("open");
    let key = [8u8; 32];

    let conv = db::create_conversation(&conn, &key, "Inbox").expect("conversation");
    db::insert_message(&conn, &key, &conv.id, "user", "knowledge rebuild mismatch")
        .expect("message");

    ensure_knowledge_rebuild_requested(&conn).expect("request rebuild");
    process_pending_knowledge_index_jobs_active(&conn, &key, 32).expect("process jobs");

    conn.execute(
        "UPDATE knowledge_rebuild_state SET normalization_version = 999 WHERE state_key = 1",
        [],
    )
    .expect("mutate state");

    let status = read_knowledge_index_status(&conn, &key).expect("status");
    assert_eq!(status.status, "stale");
    assert!(status.rebuild_required);
}

#[test]
fn knowledge_rebuild_status_preserves_active_and_failed_states_during_version_mismatch() {
    let dir = tempfile::tempdir().expect("tempdir");
    let app_dir = dir.path();
    let conn = db::open(app_dir).expect("open");
    let key = [13u8; 32];

    db::ensure_knowledge_rebuild_state_defaults(&conn).expect("state defaults");

    for raw_status in ["requested", "running", "failed", "cancelled"] {
        let last_error = if raw_status == "failed" {
            Some("temporary failure")
        } else {
            None
        };
        conn.execute(
            r#"UPDATE knowledge_rebuild_state
               SET status = ?1,
                   rebuild_required = 0,
                   normalization_version = 999,
                   stale_reason = NULL,
                   last_error = ?2
               WHERE state_key = 1"#,
            params![raw_status, last_error],
        )
        .expect("mutate active state");

        let status = read_knowledge_index_status(&conn, &key).expect("status");
        assert_eq!(status.status, raw_status);
        assert!(status.rebuild_required);
        assert_eq!(status.stale_reason, None);
        assert_eq!(status.last_error.as_deref(), last_error);
    }
}

#[test]
fn knowledge_rebuild_initialization_skips_corrupt_messages_and_preserves_valid_documents() {
    let dir = tempfile::tempdir().expect("tempdir");
    let app_dir = dir.path();
    let conn = db::open(app_dir).expect("open");
    let key = [6u8; 32];

    let conv = db::create_conversation(&conn, &key, "Inbox").expect("conversation");
    let good = db::insert_message(&conn, &key, &conv.id, "user", "stable knowledge document")
        .expect("good message");
    conn.execute(
        "UPDATE messages SET is_memory = 1, needs_embedding = 1 WHERE id = ?1",
        params![good.id],
    )
    .expect("mark good memory");

    ensure_knowledge_rebuild_requested(&conn).expect("request rebuild");
    process_pending_knowledge_index_jobs_active(&conn, &key, 32).expect("initial rebuild");
    let before_docs = list_knowledge_documents(&conn, &key, 100, 0).expect("before docs");
    assert!(!before_docs.is_empty());

    let bad =
        db::insert_message(&conn, &key, &conv.id, "user", "will corrupt").expect("bad message");
    let bad_blob = encrypt_bytes(&key, &[0xff, 0xfe], b"message.content").expect("encrypt");
    conn.execute(
        "UPDATE messages SET is_memory = 1, needs_embedding = 1, content = ?2 WHERE id = ?1",
        params![bad.id, bad_blob],
    )
    .expect("poison message");

    ensure_knowledge_rebuild_requested(&conn).expect("request rebuild again");
    process_pending_knowledge_index_jobs_active(&conn, &key, 32)
        .expect("rebuild should skip corrupt source rows");

    let after_docs = list_knowledge_documents(&conn, &key, 100, 0).expect("after docs");
    assert_eq!(after_docs.len(), before_docs.len());
    assert!(after_docs
        .iter()
        .all(|doc| doc.anchors.message_id.as_deref() != Some(bad.id.as_str())));
}

#[test]
fn knowledge_chunk_stage_keeps_existing_segment_rows() {
    let dir = tempfile::tempdir().expect("tempdir");
    let app_dir = dir.path();
    let conn = db::open(app_dir).expect("open");
    let key = [5u8; 32];

    let conv = db::create_conversation(&conn, &key, "Inbox").expect("conversation");
    let msg = db::insert_message(
        &conn,
        &key,
        &conv.id,
        "user",
        "first paragraph\n\nsecond paragraph for chunking",
    )
    .expect("message");
    conn.execute(
        "UPDATE messages SET is_memory = 1, needs_embedding = 1 WHERE id = ?1",
        params![msg.id],
    )
    .expect("mark memory");

    ensure_knowledge_rebuild_requested(&conn).expect("request rebuild");
    process_pending_knowledge_index_jobs_active(&conn, &key, 1).expect("normalize");
    process_pending_knowledge_index_jobs_active(&conn, &key, 1).expect("segment");

    let segment_unit_id: String = conn
        .query_row(
            "SELECT unit_id FROM knowledge_units WHERE document_id = ?1 AND unit_kind = 'segment' ORDER BY ordinal ASC LIMIT 1",
            params![format!("message:{}", msg.id)],
            |row| row.get(0),
        )
        .expect("segment id");
    conn.execute(
        "UPDATE knowledge_units SET updated_at_ms = 42 WHERE unit_id = ?1",
        params![segment_unit_id.clone()],
    )
    .expect("stamp segment");

    process_pending_knowledge_index_jobs_active(&conn, &key, 1).expect("chunk");

    let updated_at_ms: i64 = conn
        .query_row(
            "SELECT updated_at_ms FROM knowledge_units WHERE unit_id = ?1",
            params![segment_unit_id],
            |row| row.get(0),
        )
        .expect("updated at");
    assert_eq!(updated_at_ms, 42);
}

#[test]
fn knowledge_chunk_stage_treats_empty_segments_as_zero_chunks() {
    let dir = tempfile::tempdir().expect("tempdir");
    let app_dir = dir.path();
    let conn = db::open(app_dir).expect("open");
    let key = [6u8; 32];
    let document_id = "message:empty-segments";

    db::ensure_knowledge_rebuild_state_defaults(&conn).expect("state defaults");
    conn.execute(
        "UPDATE knowledge_rebuild_state SET status = 'running' WHERE state_key = 1",
        [],
    )
    .expect("set running");

    seed_knowledge_document(
        &conn,
        &key,
        document_id,
        "raw source text that normalizes away",
    );
    conn.execute(
        r#"UPDATE knowledge_documents
           SET normalized_text = ?2
           WHERE document_id = ?1"#,
        params![
            document_id,
            db::encode_knowledge_document_text(&key, document_id, "normalized", "  \n\n  ")
                .expect("encode normalized"),
        ],
    )
    .expect("clear normalized text");

    for stage in ["segment", "chunk", "embed", "finalize"] {
        conn.execute(
            r#"INSERT INTO knowledge_index_jobs(
                   document_id, stage, status, attempts, next_retry_at_ms, last_error, created_at_ms, updated_at_ms
               ) VALUES (?1, ?2, 'pending', 0, NULL, NULL, 1, 1)"#,
            params![document_id, stage],
        )
        .expect("insert stage job");
    }

    let processed = process_pending_knowledge_index_jobs_active(&conn, &key, 8)
        .expect("zero-chunk document should complete");
    assert_eq!(processed, 4);

    let stage_statuses = ["segment", "chunk", "embed", "finalize"]
        .into_iter()
        .map(|stage| {
            conn.query_row(
                r#"SELECT status FROM knowledge_index_jobs
                   WHERE document_id = ?1 AND stage = ?2"#,
                params![document_id, stage],
                |row| row.get::<_, String>(0),
            )
            .expect("stage status")
        })
        .collect::<Vec<_>>();
    assert_eq!(stage_statuses, vec!["done", "done", "done", "done"]);

    let unit_counts: (i64, i64) = conn
        .query_row(
            r#"SELECT
                   COALESCE(SUM(CASE WHEN unit_kind = 'segment' THEN 1 ELSE 0 END), 0),
                   COALESCE(SUM(CASE WHEN unit_kind = 'chunk' THEN 1 ELSE 0 END), 0)
               FROM knowledge_units
               WHERE document_id = ?1"#,
            params![document_id],
            |row| Ok((row.get(0)?, row.get(1)?)),
        )
        .expect("unit counts");
    assert_eq!(unit_counts, (0, 0));

    let embedding_count: i64 = conn
        .query_row(
            r#"SELECT COUNT(*)
               FROM knowledge_embeddings
               WHERE target_id = ?1"#,
            params![document_id],
            |row| row.get(0),
        )
        .expect("document embeddings");
    assert_eq!(embedding_count, 1);

    let status = read_knowledge_index_status(&conn, &key).expect("status after zero chunks");
    assert_eq!(status.status, "complete");
    assert_eq!(status.documents_indexed, 1);
    assert_eq!(status.units_indexed, 0);
    assert_eq!(status.embeddings_indexed, 1);
}

#[test]
fn knowledge_failed_job_update_uses_single_now_snapshot_for_retry_window() {
    let update = failed_job_update(0, 1_234_567);

    assert_eq!(update.next_attempts, 1);
    assert!(!update.exhausted);
    assert_eq!(update.updated_at_ms, 1_234_567);
    assert_eq!(update.next_retry_at_ms, Some(1_239_567));
}

#[test]
fn knowledge_job_failure_does_not_block_other_documents_in_same_batch() {
    let dir = tempfile::tempdir().expect("tempdir");
    let app_dir = dir.path();
    let conn = db::open(app_dir).expect("open");
    let key = [4u8; 32];

    db::ensure_knowledge_rebuild_state_defaults(&conn).expect("state defaults");
    conn.execute(
        "UPDATE knowledge_rebuild_state SET status = 'running' WHERE state_key = 1",
        [],
    )
    .expect("set running");

    let good_document_id = "message:good";
    let bad_document_id = "message:bad";
    let anchor_json = serde_json::json!({}).to_string();
    let raw_good = db::encode_knowledge_document_text(
        &key,
        good_document_id,
        "raw",
        "healthy knowledge document",
    )
    .expect("good raw");
    let normalized_good = db::encode_knowledge_document_text(
        &key,
        good_document_id,
        "normalized",
        "healthy knowledge document",
    )
    .expect("good normalized");
    let raw_bad = encrypt_bytes(
        &key,
        &[0xff, 0xfe],
        format!("knowledge.document.raw:{bad_document_id}").as_bytes(),
    )
    .expect("bad raw");
    let normalized_bad = db::encode_knowledge_document_text(
        &key,
        bad_document_id,
        "normalized",
        "broken knowledge document",
    )
    .expect("bad normalized");

    for (document_id, raw_text, normalized_text) in [
        (good_document_id, raw_good, normalized_good),
        (bad_document_id, raw_bad, normalized_bad),
    ] {
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
                raw_text,
                normalized_text,
                crate::knowledge::KNOWLEDGE_SCHEMA_VERSION,
                crate::knowledge::KNOWLEDGE_NORMALIZATION_VERSION,
                crate::knowledge::KNOWLEDGE_SEGMENTATION_VERSION,
                crate::knowledge::KNOWLEDGE_EMBEDDING_POLICY_VERSION,
                crate::knowledge::KNOWLEDGE_RETRIEVAL_POLICY_VERSION,
            ],
        )
        .expect("insert seeded document");
    }

    conn.execute(
        r#"INSERT INTO knowledge_index_jobs(
               document_id, stage, status, attempts, next_retry_at_ms, last_error, created_at_ms, updated_at_ms
           ) VALUES (?1, 'normalize', 'pending', 0, NULL, NULL, 1, 1)"#,
        params![bad_document_id],
    )
    .expect("insert bad job");
    conn.execute(
        r#"INSERT INTO knowledge_index_jobs(
               document_id, stage, status, attempts, next_retry_at_ms, last_error, created_at_ms, updated_at_ms
           ) VALUES (?1, 'normalize', 'pending', 0, NULL, NULL, 1, 2)"#,
        params![good_document_id],
    )
    .expect("insert good job");

    let error = process_pending_knowledge_index_jobs_active(&conn, &key, 2)
        .expect_err("bad document should still surface an error");
    assert!(error.to_string().contains("utf-8"));

    let good_status: String = conn
        .query_row(
            "SELECT status FROM knowledge_index_jobs WHERE document_id = ?1 AND stage = 'normalize'",
            params![good_document_id],
            |row| row.get(0),
        )
        .expect("good job status");
    let bad_status: String = conn
        .query_row(
            "SELECT status FROM knowledge_index_jobs WHERE document_id = ?1 AND stage = 'normalize'",
            params![bad_document_id],
            |row| row.get(0),
        )
        .expect("bad job status");
    assert_eq!(good_status, "done");
    assert_eq!(bad_status, "failed");
}

#[test]
fn knowledge_embed_stage_averages_split_document_and_unit_embeddings() {
    let dir = tempfile::tempdir().expect("tempdir");
    let app_dir = dir.path();
    let conn = db::open(app_dir).expect("open");
    let key = [3u8; 32];

    db::ensure_knowledge_rebuild_state_defaults(&conn).expect("state defaults");
    conn.execute(
        "UPDATE knowledge_rebuild_state SET status = 'running' WHERE state_key = 1",
        [],
    )
    .expect("set running");

    let document_id = "message:long-doc";
    let unit_id = "message:long-doc:chunk:0";
    let long_text = (0..600)
        .map(|index| format!("token{index}"))
        .collect::<Vec<_>>()
        .join(" ");
    seed_knowledge_document(&conn, &key, document_id, &long_text);
    seed_knowledge_unit(&conn, &key, unit_id, document_id, "chunk", 0, &long_text);
    conn.execute(
        r#"INSERT INTO knowledge_index_jobs(
               document_id, stage, status, attempts, next_retry_at_ms, last_error, created_at_ms, updated_at_ms
           ) VALUES (?1, 'embed', 'pending', 0, NULL, NULL, 1, 1)"#,
        params![document_id],
    )
    .expect("insert embed job");

    let processed =
        process_pending_knowledge_index_jobs_active(&conn, &key, 1).expect("process embed");
    assert_eq!(processed, 1);

    let (_, dim) = db::read_knowledge_embedding_model_state(&conn).expect("embedding state");
    let expected = merged_test_embedding(&long_text, dim as usize);
    let document_embedding = read_embedding(&conn, "document", document_id);
    let unit_embedding = read_embedding(&conn, "unit", unit_id);
    assert_embeddings_close(&document_embedding, &expected);
    assert_embeddings_close(&unit_embedding, &expected);

    let row_count: i64 = conn
        .query_row(
            "SELECT COUNT(*) FROM knowledge_embeddings WHERE target_id IN (?1, ?2)",
            params![document_id, unit_id],
            |row| row.get(0),
        )
        .expect("embedding row count");
    assert_eq!(row_count, 2);

    let status = read_knowledge_index_status(&conn, &key).expect("status");
    assert_eq!(status.embeddings_indexed, 2);
}

#[test]
fn knowledge_rebuild_keeps_embedding_model_snapshot_across_batches() {
    let dir = tempfile::tempdir().expect("tempdir");
    let app_dir = dir.path();
    let conn = db::open(app_dir).expect("open");
    let key = [14u8; 32];

    let conv = db::create_conversation(&conn, &key, "Inbox").expect("conversation");
    db::insert_message(&conn, &key, &conv.id, "user", "knowledge snapshot test").expect("message");

    ensure_knowledge_rebuild_requested(&conn).expect("request rebuild");
    let processed =
        process_pending_knowledge_index_jobs_active(&conn, &key, 3).expect("process first batch");
    assert_eq!(processed, 3);

    db::set_active_embedding_model_name(&conn, crate::embedding::PRODUCTION_MODEL_NAME)
        .expect("switch active embedding model");

    let processed =
        process_pending_knowledge_index_jobs_active(&conn, &key, 2).expect("process embed batch");
    assert_eq!(processed, 2);

    let mut stmt = conn
        .prepare(
            r#"SELECT DISTINCT model_name
               FROM knowledge_embeddings
               ORDER BY model_name ASC"#,
        )
        .expect("prepare embeddings query");
    let stored_models = stmt
        .query_map([], |row| row.get::<_, String>(0))
        .expect("query models")
        .collect::<Result<Vec<_>, _>>()
        .expect("collect models");
    assert_eq!(
        stored_models,
        vec![crate::embedding::DEFAULT_MODEL_NAME.to_string()]
    );

    let status = read_knowledge_index_status(&conn, &key).expect("status");
    assert_eq!(
        status.last_indexed_model_name.as_deref(),
        Some(crate::embedding::DEFAULT_MODEL_NAME)
    );
}

#[test]
fn knowledge_rebuild_skips_retry_after_job_exhaustion_and_can_complete() {
    let dir = tempfile::tempdir().expect("tempdir");
    let app_dir = dir.path();
    let conn = db::open(app_dir).expect("open");
    let key = [2u8; 32];

    db::ensure_knowledge_rebuild_state_defaults(&conn).expect("state defaults");
    conn.execute(
        "UPDATE knowledge_rebuild_state SET status = 'running' WHERE state_key = 1",
        [],
    )
    .expect("set running");

    let document_id = "message:poisoned";
    let raw_bad = encrypt_bytes(
        &key,
        &[0xff, 0xfe],
        format!("knowledge.document.raw:{document_id}").as_bytes(),
    )
    .expect("encrypt bad raw");
    let normalized = db::encode_knowledge_document_text(
        &key,
        document_id,
        "normalized",
        "broken knowledge document",
    )
    .expect("encode normalized");
    let anchor_json = serde_json::json!({}).to_string();
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
    .expect("insert poisoned document");
    conn.execute(
        r#"INSERT INTO knowledge_index_jobs(
               document_id, stage, status, attempts, next_retry_at_ms, last_error, created_at_ms, updated_at_ms
           ) VALUES (?1, 'normalize', 'failed', 4, 0, 'previous failure', 1, 1)"#,
        params![document_id],
    )
    .expect("insert failing job");

    let error = process_pending_knowledge_index_jobs_active(&conn, &key, 1)
        .expect_err("final failing attempt should still surface an error");
    assert!(error.to_string().contains("utf-8"));

    let (job_status, attempts, next_retry_at_ms): (String, i64, Option<i64>) = conn
        .query_row(
            r#"SELECT status, attempts, next_retry_at_ms
               FROM knowledge_index_jobs
               WHERE document_id = ?1 AND stage = 'normalize'"#,
            params![document_id],
            |row| Ok((row.get(0)?, row.get(1)?, row.get(2)?)),
        )
        .expect("job row");
    assert_eq!(job_status, "exhausted");
    assert_eq!(attempts, 5);
    assert_eq!(next_retry_at_ms, None);

    let status = read_knowledge_index_status(&conn, &key).expect("status after exhaustion");
    assert_eq!(status.status, "complete");
    assert!(status
        .last_error
        .as_deref()
        .unwrap_or_default()
        .contains("utf-8"));

    let processed = process_pending_knowledge_index_jobs_active(&conn, &key, 1)
        .expect("exhausted job should not be retried");
    assert_eq!(processed, 0);
}

#[test]
fn knowledge_rebuild_clears_failed_status_when_only_exhausted_jobs_remain() {
    let dir = tempfile::tempdir().expect("tempdir");
    let app_dir = dir.path();
    let conn = db::open(app_dir).expect("open");
    let key = [16u8; 32];

    db::ensure_knowledge_rebuild_state_defaults(&conn).expect("state defaults");
    conn.execute(
        r#"UPDATE knowledge_rebuild_state
           SET status = 'failed',
               last_error = 'previous exhaustion'
           WHERE state_key = 1"#,
        [],
    )
    .expect("set failed state");

    let exhausted_document_id = "message:exhausted-doc";
    seed_knowledge_document(
        &conn,
        &key,
        exhausted_document_id,
        "poisoned source document",
    );
    conn.execute(
        r#"INSERT INTO knowledge_index_jobs(
               document_id, stage, status, attempts, next_retry_at_ms, last_error, created_at_ms, updated_at_ms
           ) VALUES (?1, 'normalize', 'exhausted', 5, NULL, 'permanent failure', 1, 1)"#,
        params![exhausted_document_id],
    )
    .expect("insert exhausted job");

    let recovering_document_id = "message:recovering-doc";
    seed_knowledge_document(
        &conn,
        &key,
        recovering_document_id,
        "first paragraph

second paragraph for continued indexing",
    );
    for stage in ["segment", "chunk"] {
        conn.execute(
            r#"INSERT INTO knowledge_index_jobs(
                   document_id, stage, status, attempts, next_retry_at_ms, last_error, created_at_ms, updated_at_ms
               ) VALUES (?1, ?2, 'pending', 0, NULL, NULL, 1, 1)"#,
            params![recovering_document_id, stage],
        )
        .expect("insert recovering job");
    }

    let processed =
        process_pending_knowledge_index_jobs_active(&conn, &key, 1).expect("process segment");
    assert_eq!(processed, 1);

    let (status, last_error): (String, Option<String>) = conn
        .query_row(
            "SELECT status, last_error FROM knowledge_rebuild_state WHERE state_key = 1",
            [],
            |row| Ok((row.get(0)?, row.get(1)?)),
        )
        .expect("read rebuild state");
    assert_eq!(status, "running");
    assert_eq!(last_error, None);

    let chunk_status: String = conn
        .query_row(
            r#"SELECT status FROM knowledge_index_jobs
               WHERE document_id = ?1 AND stage = 'chunk'"#,
            params![recovering_document_id],
            |row| row.get(0),
        )
        .expect("chunk status");
    assert_eq!(chunk_status, "pending");
}

#[test]
fn knowledge_stage_selection_allows_downstream_stages_after_prior_stage_exhaustion() {
    let dir = tempfile::tempdir().expect("tempdir");
    let app_dir = dir.path();
    let conn = db::open(app_dir).expect("open");
    let key = [15u8; 32];
    let document_id = "message:exhausted-upstream";

    db::ensure_knowledge_rebuild_state_defaults(&conn).expect("state defaults");
    conn.execute(
        "UPDATE knowledge_rebuild_state SET status = 'running' WHERE state_key = 1",
        [],
    )
    .expect("set running");

    seed_knowledge_document(
        &conn,
        &key,
        document_id,
        "first paragraph\n\nsecond paragraph for downstream stages",
    );

    conn.execute(
        r#"INSERT INTO knowledge_index_jobs(
               document_id, stage, status, attempts, next_retry_at_ms, last_error, created_at_ms, updated_at_ms
           ) VALUES (?1, 'normalize', 'exhausted', 5, NULL, 'permanent failure', 1, 1)"#,
        params![document_id],
    )
    .expect("insert exhausted normalize job");
    for stage in ["segment", "chunk", "embed", "finalize"] {
        conn.execute(
            r#"INSERT INTO knowledge_index_jobs(
                   document_id, stage, status, attempts, next_retry_at_ms, last_error, created_at_ms, updated_at_ms
               ) VALUES (?1, ?2, 'pending', 0, NULL, NULL, 1, 1)"#,
            params![document_id, stage],
        )
        .expect("insert downstream job");
    }

    let processed = process_pending_knowledge_index_jobs_active(&conn, &key, 8)
        .expect("downstream stages should run after upstream exhaustion");
    assert_eq!(processed, 4);

    let downstream_statuses = ["segment", "chunk", "embed", "finalize"]
        .into_iter()
        .map(|stage| {
            conn.query_row(
                r#"SELECT status FROM knowledge_index_jobs
                   WHERE document_id = ?1 AND stage = ?2"#,
                params![document_id, stage],
                |row| row.get::<_, String>(0),
            )
            .expect("downstream job status")
        })
        .collect::<Vec<_>>();
    assert_eq!(downstream_statuses, vec!["done", "done", "done", "done"]);

    let status =
        read_knowledge_index_status(&conn, &key).expect("status after downstream recovery");
    assert_eq!(status.status, "complete");
    assert_eq!(status.documents_indexed, 1);
    assert!(status.units_indexed > 0);
    assert!(status.embeddings_indexed > 0);
}

#[test]
fn knowledge_stage_selection_waits_for_prior_stage_retry_window() {
    let dir = tempfile::tempdir().expect("tempdir");
    let app_dir = dir.path();
    let conn = db::open(app_dir).expect("open");
    let key = [14u8; 32];
    let document_id = "message:stage-blocked";

    db::ensure_knowledge_rebuild_state_defaults(&conn).expect("state defaults");
    conn.execute(
        "UPDATE knowledge_rebuild_state SET status = 'running' WHERE state_key = 1",
        [],
    )
    .expect("set running");

    seed_knowledge_document(&conn, &key, document_id, "pre-collected normalized text");
    conn.execute(
        r#"UPDATE knowledge_documents
           SET raw_text = ?2,
               normalized_text = ?3
           WHERE document_id = ?1"#,
        params![
            document_id,
            db::encode_knowledge_document_text(&key, document_id, "raw", "raw source text")
                .expect("encode raw"),
            db::encode_knowledge_document_text(
                &key,
                document_id,
                "normalized",
                "pre-collected normalized text",
            )
            .expect("encode normalized"),
        ],
    )
    .expect("override doc text");

    let retry_at_ms = 9_999_999_999_999_i64;
    conn.execute(
        r#"INSERT INTO knowledge_index_jobs(
               document_id, stage, status, attempts, next_retry_at_ms, last_error, created_at_ms, updated_at_ms
           ) VALUES (?1, 'normalize', 'failed', 1, ?2, 'temporary failure', 1, 1)"#,
        params![document_id, retry_at_ms],
    )
    .expect("insert normalize job");
    conn.execute(
        r#"INSERT INTO knowledge_index_jobs(
               document_id, stage, status, attempts, next_retry_at_ms, last_error, created_at_ms, updated_at_ms
           ) VALUES (?1, 'segment', 'pending', 0, NULL, NULL, 1, 1)"#,
        params![document_id],
    )
    .expect("insert segment job");

    let processed = process_pending_knowledge_index_jobs_active(&conn, &key, 8)
        .expect("blocked later stages should be skipped");
    assert_eq!(processed, 0);

    let segment_status: String = conn
        .query_row(
            r#"SELECT status FROM knowledge_index_jobs
               WHERE document_id = ?1 AND stage = 'segment'"#,
            params![document_id],
            |row| row.get(0),
        )
        .expect("segment status");
    assert_eq!(segment_status, "pending");

    let unit_count: i64 = conn
        .query_row(
            "SELECT COUNT(*) FROM knowledge_units WHERE document_id = ?1",
            params![document_id],
            |row| row.get(0),
        )
        .expect("unit count");
    assert_eq!(unit_count, 0);
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

fn read_embedding(conn: &rusqlite::Connection, target_kind: &str, target_id: &str) -> Vec<f32> {
    let json: String = conn
        .query_row(
            r#"SELECT embedding_json
               FROM knowledge_embeddings
               WHERE target_kind = ?1 AND target_id = ?2"#,
            params![target_kind, target_id],
            |row| row.get(0),
        )
        .expect("read embedding");
    serde_json::from_str(&json).expect("decode embedding json")
}

fn merged_test_embedding(text: &str, dim: usize) -> Vec<f32> {
    let policy = EmbeddingBatchPolicy::default();
    let prepared = prepare_embedding_inputs(&[text.to_string()], policy);
    let pieces = prepared
        .into_iter()
        .map(|input| test_deterministic_embedding(&input.text, dim))
        .collect::<Vec<_>>();
    average_piece_embeddings(vec![pieces], 1)
        .into_iter()
        .next()
        .unwrap_or_default()
}

fn test_deterministic_embedding(text: &str, dim: usize) -> Vec<f32> {
    let dim = dim.max(8);
    let mut vector = vec![0f32; dim];
    for token in text.split_whitespace() {
        let hash = Sha256::digest(token.as_bytes());
        let index = usize::from(hash[0]) % dim;
        let sign = if hash[1] % 2 == 0 { 1.0 } else { -1.0 };
        vector[index] += sign;
    }
    let norm = vector.iter().map(|value| value * value).sum::<f32>().sqrt();
    if norm > 0.0 {
        for value in &mut vector {
            *value /= norm;
        }
    }
    vector
}

fn assert_embeddings_close(actual: &[f32], expected: &[f32]) {
    assert_eq!(actual.len(), expected.len());
    for (actual_value, expected_value) in actual.iter().zip(expected.iter()) {
        assert!((actual_value - expected_value).abs() < 1e-6);
    }
}
