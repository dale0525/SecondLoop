use rusqlite::params;

use crate::crypto::encrypt_bytes;
use crate::db;
use crate::knowledge::{
    ensure_knowledge_rebuild_requested, list_knowledge_documents, list_knowledge_units,
    list_knowledge_units_around_anchor, process_pending_knowledge_index_jobs_active,
    KnowledgeAnchorSet, KnowledgeUnitKind,
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

#[test]
fn list_knowledge_units_around_anchor_scans_beyond_first_page_limit() {
    let dir = tempfile::tempdir().expect("tempdir");
    let app_dir = dir.path();
    let conn = db::open(app_dir).expect("open");
    let key = [24u8; 32];

    let document_id = "synthetic:anchor-window";
    let anchor_json = serde_json::json!({}).to_string();
    let raw = db::encode_knowledge_document_text(&key, document_id, "raw", "synthetic doc text")
        .expect("encode raw");
    let normalized =
        db::encode_knowledge_document_text(&key, document_id, "normalized", "synthetic doc text")
            .expect("encode normalized");

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
           ) VALUES (?1, 'generated', 'raw_text', 'body', NULL, 1.0, NULL, NULL, ?2, ?3, ?4, 1, 1, ?5, ?6, ?7, ?8, ?9, NULL)"#,
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

    let query_anchor = KnowledgeAnchorSet {
        message_id: Some("synthetic-message".to_string()),
        ..Default::default()
    };

    let mut insert_unit = conn
        .prepare(
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
               ) VALUES (?1, ?2, NULL, 'chunk', 'raw_text', 'body', ?3, ?4, ?5, ?6, ?7, NULL, NULL, 1, 1)"#,
        )
        .expect("prepare insert unit");

    for ordinal in 0..2050i64 {
        let unit_id = format!("unit-{ordinal}");
        let text = "filler text";
        let raw = db::encode_knowledge_unit_text(&key, &unit_id, "raw", text).expect("raw unit");
        let normalized =
            db::encode_knowledge_unit_text(&key, &unit_id, "normalized", text).expect("norm unit");
        insert_unit
            .execute(params![
                unit_id,
                document_id,
                ordinal,
                text.split_whitespace().count() as i64,
                serde_json::json!({}).to_string(),
                raw,
                normalized,
            ])
            .expect("insert filler unit");
    }

    let match_unit_id = "unit-match";
    let match_text = "matching unit text";
    let match_raw =
        db::encode_knowledge_unit_text(&key, match_unit_id, "raw", match_text).expect("raw");
    let match_normalized =
        db::encode_knowledge_unit_text(&key, match_unit_id, "normalized", match_text)
            .expect("normalized");
    insert_unit
        .execute(params![
            match_unit_id,
            document_id,
            2500i64,
            match_text.split_whitespace().count() as i64,
            serde_json::to_string(&query_anchor).expect("anchor json"),
            match_raw,
            match_normalized,
        ])
        .expect("insert match unit");

    let around = list_knowledge_units_around_anchor(&conn, &key, document_id, &query_anchor, 1, 1)
        .expect("around anchor");

    assert!(
        around
            .iter()
            .any(|unit| unit.unit_id.as_str() == match_unit_id),
        "expected around window to include {match_unit_id}"
    );
}
