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
fn knowledge_rebuild_initialization_is_atomic_when_source_collection_fails() {
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
    let error = process_pending_knowledge_index_jobs_active(&conn, &key, Path::new(app_dir), 32)
        .expect_err("rebuild should fail");
    assert!(error.to_string().contains("utf-8"));

    let after_docs = list_knowledge_documents(&conn, &key, 100, 0).expect("after docs");
    assert_eq!(after_docs.len(), before_docs.len());
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
