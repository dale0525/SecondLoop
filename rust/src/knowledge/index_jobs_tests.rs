use std::path::Path;

use crate::db;
use crate::knowledge::{
    ensure_knowledge_rebuild_requested, process_pending_knowledge_index_jobs_active,
    read_knowledge_index_status,
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

    let status = read_knowledge_index_status(&conn).expect("status");
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

    let status = read_knowledge_index_status(&conn).expect("status");
    assert_eq!(status.status, "stale");
    assert!(status.rebuild_required);
}
