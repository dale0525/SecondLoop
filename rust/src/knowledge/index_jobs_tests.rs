use std::path::Path;

use rusqlite::params;

use crate::crypto::encrypt_bytes;
use crate::db;
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
        process_pending_knowledge_index_jobs_active(&conn, &key, Path::new(app_dir), 32)
            .expect("process jobs");
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
    process_pending_knowledge_index_jobs_active(&conn, &key, Path::new(app_dir), 32)
        .expect("process jobs");

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
    process_pending_knowledge_index_jobs_active(&conn, &key, Path::new(app_dir), 32)
        .expect("initial rebuild");
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
    process_pending_knowledge_index_jobs_active(&conn, &key, Path::new(app_dir), 32)
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
    process_pending_knowledge_index_jobs_active(&conn, &key, Path::new(app_dir), 1)
        .expect("normalize");
    process_pending_knowledge_index_jobs_active(&conn, &key, Path::new(app_dir), 1)
        .expect("segment");

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

    process_pending_knowledge_index_jobs_active(&conn, &key, Path::new(app_dir), 1).expect("chunk");

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

    let error = process_pending_knowledge_index_jobs_active(&conn, &key, Path::new(app_dir), 2)
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
