use rusqlite::params;

use crate::crypto::encrypt_bytes;
use crate::db;
use crate::knowledge::{
    ensure_knowledge_rebuild_requested, list_knowledge_documents, list_knowledge_units,
    process_pending_knowledge_index_jobs_active, KnowledgeUnitKind,
};

#[test]
fn list_knowledge_documents_skips_corrupt_rows() {
    let dir = tempfile::tempdir().expect("tempdir");
    let app_dir = dir.path();
    let conn = db::open(app_dir).expect("open");
    let key = [21u8; 32];

    let conv = db::create_conversation(&conn, &key, "Inbox").expect("conversation");
    let good = db::insert_message(&conn, &key, &conv.id, "user", "stable knowledge document")
        .expect("good message");
    let bad = db::insert_message(&conn, &key, &conv.id, "user", "corrupt listed document")
        .expect("bad message");
    conn.execute(
        "UPDATE messages SET is_memory = 1, needs_embedding = 1 WHERE id IN (?1, ?2)",
        params![good.id, bad.id],
    )
    .expect("mark messages");

    ensure_knowledge_rebuild_requested(&conn).expect("request rebuild");
    process_pending_knowledge_index_jobs_active(&conn, &key, 64).expect("process jobs");

    let before_docs = list_knowledge_documents(&conn, &key, 100, 0).expect("before docs");
    assert_eq!(before_docs.len(), 2);

    let bad_document_id = format!("message:{}", bad.id);
    let bad_blob = encrypt_bytes(
        &key,
        &[0xff, 0xfe],
        format!("knowledge.document.raw:{bad_document_id}").as_bytes(),
    )
    .expect("encrypt corrupt raw text");
    conn.execute(
        "UPDATE knowledge_documents SET raw_text = ?2 WHERE document_id = ?1",
        params![bad_document_id, bad_blob],
    )
    .expect("corrupt knowledge document");

    let after_docs = list_knowledge_documents(&conn, &key, 100, 0).expect("after docs");
    assert_eq!(after_docs.len(), 1);
    assert_eq!(after_docs[0].document_id, format!("message:{}", good.id));
}

#[test]
fn list_knowledge_units_filters_by_kind_without_panicking() {
    let dir = tempfile::tempdir().expect("tempdir");
    let app_dir = dir.path();
    let conn = db::open(app_dir).expect("open");
    let key = [23u8; 32];

    let conv = db::create_conversation(&conn, &key, "Inbox").expect("conversation");
    let msg = db::insert_message(
        &conn,
        &key,
        &conv.id,
        "user",
        "first paragraph for sections

second paragraph for chunking",
    )
    .expect("message");
    conn.execute(
        "UPDATE messages SET is_memory = 1, needs_embedding = 1 WHERE id = ?1",
        params![msg.id],
    )
    .expect("mark memory");

    ensure_knowledge_rebuild_requested(&conn).expect("request rebuild");
    process_pending_knowledge_index_jobs_active(&conn, &key, 64).expect("process jobs");

    let document_id = format!("message:{}", msg.id);
    let segment_units = list_knowledge_units(
        &conn,
        &key,
        &document_id,
        Some(KnowledgeUnitKind::Segment),
        100,
        0,
    )
    .expect("segment units");

    assert!(!segment_units.is_empty());
    assert!(segment_units
        .iter()
        .all(|unit| unit.unit_kind == KnowledgeUnitKind::Segment));
}

#[test]
fn list_knowledge_units_skips_corrupt_rows() {
    let dir = tempfile::tempdir().expect("tempdir");
    let app_dir = dir.path();
    let conn = db::open(app_dir).expect("open");
    let key = [22u8; 32];

    let conv = db::create_conversation(&conn, &key, "Inbox").expect("conversation");
    let msg = db::insert_message(
        &conn,
        &key,
        &conv.id,
        "user",
        "first paragraph for sections\n\nsecond paragraph for chunking",
    )
    .expect("message");
    conn.execute(
        "UPDATE messages SET is_memory = 1, needs_embedding = 1 WHERE id = ?1",
        params![msg.id],
    )
    .expect("mark memory");

    ensure_knowledge_rebuild_requested(&conn).expect("request rebuild");
    process_pending_knowledge_index_jobs_active(&conn, &key, 64).expect("process jobs");

    let document_id = format!("message:{}", msg.id);
    let before_units =
        list_knowledge_units(&conn, &key, &document_id, None, 100, 0).expect("before units");
    assert!(before_units.len() > 1);

    let bad_unit_id = before_units[0].unit_id.clone();
    let bad_blob = encrypt_bytes(
        &key,
        &[0xff, 0xfe],
        format!("knowledge.unit.raw:{bad_unit_id}").as_bytes(),
    )
    .expect("encrypt corrupt unit raw text");
    conn.execute(
        "UPDATE knowledge_units SET raw_text = ?2 WHERE unit_id = ?1",
        params![bad_unit_id.clone(), bad_blob],
    )
    .expect("corrupt knowledge unit");

    let after_units =
        list_knowledge_units(&conn, &key, &document_id, None, 100, 0).expect("after units");
    assert_eq!(after_units.len(), before_units.len() - 1);
    assert!(after_units.iter().all(|unit| unit.unit_id != bad_unit_id));
}
