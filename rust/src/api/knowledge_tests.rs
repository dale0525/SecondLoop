use std::fmt::Write;

use rusqlite::params;

use crate::api::knowledge::db_request_knowledge_rebuild;
use crate::crypto::encrypt_bytes;
use crate::db;
use crate::knowledge::read_knowledge_index_status;

fn encode_blob_hex(bytes: &[u8]) -> String {
    let mut out = String::with_capacity(bytes.len() * 2);
    for byte in bytes {
        write!(&mut out, "{byte:02x}").expect("write hex");
    }
    out
}

#[test]
fn read_knowledge_index_status_returns_safe_empty_status_when_state_row_is_missing() {
    let dir = tempfile::tempdir().expect("tempdir");
    let app_dir = dir.path().to_path_buf();
    let conn = db::open(&app_dir).expect("open");
    let key = [32u8; 32];

    conn.execute(
        "DELETE FROM knowledge_rebuild_state WHERE state_key = 1",
        [],
    )
    .expect("delete state row");

    let status = read_knowledge_index_status(&conn, &key).expect("status");
    assert_eq!(status.status, "empty");
    assert!(!status.rebuild_required);
    assert_eq!(status.stale_reason, None);
    assert_eq!(status.last_error, None);
    assert_eq!(status.documents_indexed, 0);
    assert_eq!(status.units_indexed, 0);
    assert_eq!(status.embeddings_indexed, 0);
    assert_eq!(status.total_documents, 0);
    assert_eq!(status.last_indexed_model_name, None);
    assert_eq!(status.last_indexed_dim, None);
    assert_eq!(
        status.versions,
        crate::knowledge::KnowledgeVersionSet::current()
    );
}

#[test]
fn request_knowledge_rebuild_succeeds_even_if_initial_job_batch_fails() {
    let dir = tempfile::tempdir().expect("tempdir");
    let app_dir = dir.path().to_path_buf();
    let app_dir_string = app_dir.to_string_lossy().into_owned();
    let conn = db::open(&app_dir).expect("open");
    let key = [31u8; 32];

    let conv = db::create_conversation(&conn, &key, "Inbox").expect("conversation");
    let msg = db::insert_message(
        &conn,
        &key,
        &conv.id,
        "user",
        "job failure after rebuild request",
    )
    .expect("message");
    conn.execute(
        "UPDATE messages SET is_memory = 1, needs_embedding = 1 WHERE id = ?1",
        params![msg.id],
    )
    .expect("mark memory");

    let document_id = format!("message:{}", msg.id);
    let corrupt_blob = encrypt_bytes(
        &key,
        &[0xff, 0xfe],
        format!("knowledge.document.raw:{document_id}").as_bytes(),
    )
    .expect("encrypt corrupt raw text");
    let corrupt_blob_hex = encode_blob_hex(&corrupt_blob);
    conn.execute_batch(&format!(
        r#"
CREATE TRIGGER corrupt_knowledge_document_after_insert
AFTER INSERT ON knowledge_documents
WHEN NEW.document_id = '{document_id}'
BEGIN
  UPDATE knowledge_documents
  SET raw_text = X'{corrupt_blob_hex}'
  WHERE document_id = NEW.document_id;
END;
"#
    ))
    .expect("create corruption trigger");

    db_request_knowledge_rebuild(app_dir_string, key.to_vec()).expect("request rebuild");

    let status = read_knowledge_index_status(&conn, &key).expect("status");
    assert_eq!(status.status, "failed");
    assert!(status
        .last_error
        .as_deref()
        .is_some_and(|value| value.contains("utf-8")));
}

#[test]
fn knowledge_search_returns_anchor_rich_hits_for_message_and_attachment_sources() {
    let fixture = crate::knowledge::retrieval::test_support::seeded_fixture();
    let app_dir = fixture.app_dir.to_string_lossy().into_owned();

    let orchard_hits = crate::api::knowledge::db_search_knowledge(
        app_dir.clone(),
        fixture.key.to_vec(),
        "orchard planning".to_string(),
        Some(fixture.conversation_id.clone()),
        None,
        8,
    )
    .expect("orchard hits");
    assert!(orchard_hits
        .iter()
        .any(|hit| hit.anchors.message_id.is_some()));

    let attachment_hits = crate::api::knowledge::db_search_knowledge(
        app_dir,
        fixture.key.to_vec(),
        "roadmap-q1".to_string(),
        None,
        None,
        8,
    )
    .expect("attachment hits");
    assert!(attachment_hits
        .iter()
        .any(|hit| hit.anchors.attachment_sha256.is_some()));
}

#[test]
fn knowledge_viewer_api_loads_document_summary_and_paged_units() {
    let fixture = crate::knowledge::retrieval::test_support::seeded_fixture();
    let app_dir = fixture.app_dir.to_string_lossy().into_owned();

    let document = crate::api::knowledge::db_get_knowledge_document(
        app_dir.clone(),
        fixture.key.to_vec(),
        fixture.transcript_document_id.clone(),
    )
    .expect("document view");
    assert_eq!(
        document.document.document_id,
        fixture.transcript_document_id
    );
    assert!(document.total_units > 0);
    assert!(document.chunk_count > 0);

    let page = crate::api::knowledge::db_list_knowledge_viewer_units(
        app_dir,
        fixture.key.to_vec(),
        fixture.transcript_document_id,
        Some(crate::knowledge::KnowledgeUnitKind::Chunk),
        1,
        0,
    )
    .expect("viewer page");
    assert_eq!(page.units.len(), 1);
    assert!(page.total >= 1);
}

#[test]
fn knowledge_viewer_api_reads_units_around_anchor_and_search_hits() {
    let fixture = crate::knowledge::retrieval::test_support::seeded_fixture();
    let app_dir = fixture.app_dir.to_string_lossy().into_owned();

    let hits = crate::api::knowledge::db_search_knowledge_document_units(
        app_dir.clone(),
        fixture.key.to_vec(),
        fixture.transcript_document_id.clone(),
        "freeze-signal".to_string(),
        3,
    )
    .expect("document search hits");
    let first_hit = hits.first().expect("first hit");
    assert!(first_hit.unit_id.is_some());

    let around = crate::api::knowledge::db_list_knowledge_units_around_anchor(
        app_dir,
        fixture.key.to_vec(),
        fixture.transcript_document_id,
        first_hit.anchors.clone(),
        1,
        1,
    )
    .expect("around anchor");
    assert!(around
        .iter()
        .any(|unit| Some(unit.unit_id.as_str()) == first_hit.unit_id.as_deref()));
}

#[test]
fn knowledge_debug_stats_reports_generated_memory_and_usage_counts() {
    let dir = tempfile::tempdir().expect("tempdir");
    let app_dir = dir.path().to_path_buf();
    let app_dir_string = app_dir.to_string_lossy().into_owned();
    let conn = db::open(&app_dir).expect("open");
    let key = [29u8; 32];

    let conv = db::create_conversation(&conn, &key, "Inbox").expect("conversation");
    db::insert_message(
        &conn,
        &key,
        &conv.id,
        "user",
        "Please answer in Chinese and keep responses short and practical.",
    )
    .expect("preference");
    db::insert_message(
        &conn,
        &key,
        &conv.id,
        "user",
        "I'm building a memory optimization prototype.",
    )
    .expect("profile");

    crate::knowledge::ensure_knowledge_rebuild_requested(&conn).expect("request rebuild");
    crate::knowledge::process_pending_knowledge_index_jobs_active(&conn, &key, 256)
        .expect("process jobs");
    crate::db::touch_knowledge_documents_usage(
        &conn,
        &["generated:preference:response-language".to_string()],
        crate::knowledge::usage::now_ms(),
    )
    .expect("touch usage");

    let stats = crate::api::knowledge::db_get_knowledge_debug_stats(app_dir_string, key.to_vec())
        .expect("debug stats");

    assert!(stats.total_documents >= 3);
    assert!(stats.generated_documents >= 3);
    assert!(stats.preference_documents >= 2);
    assert!(stats.profile_documents >= 1);
    assert!(stats.usage_stat_documents >= 1);
    assert!(stats.summary_documents + stats.generated_documents <= stats.total_documents);
    assert!(stats.generated_memory_retrieval_enabled);
    assert!(stats.hotness_rerank_enabled);
    assert!(stats.session_digest_enabled);
}

#[test]
fn touch_knowledge_documents_usage_succeeds_inside_active_transaction() {
    let fixture = crate::knowledge::retrieval::test_support::seeded_fixture();
    fixture
        .conn
        .execute("BEGIN IMMEDIATE", [])
        .expect("begin transaction");

    crate::db::touch_knowledge_documents_usage(
        &fixture.conn,
        std::slice::from_ref(&fixture.transcript_document_id),
        crate::knowledge::usage::now_ms(),
    )
    .expect("touch usage inside transaction");

    fixture
        .conn
        .execute("COMMIT", [])
        .expect("commit transaction");

    let usage_rows: i64 = fixture
        .conn
        .query_row(
            "SELECT COUNT(*) FROM knowledge_document_usage WHERE document_id = ?1",
            params![fixture.transcript_document_id],
            |row| row.get(0),
        )
        .expect("usage row count");
    assert_eq!(usage_rows, 1);
}
