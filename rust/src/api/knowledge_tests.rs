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
        "I'm a developer building a memory optimization prototype.",
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
    assert!(
        stats.source_documents + stats.summary_documents + stats.generated_documents
            <= stats.total_documents
    );
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

#[test]
fn knowledge_memory_feedback_overrides_detail_and_can_stop_ask_ai_usage() {
    let dir = tempfile::tempdir().expect("tempdir");
    let app_dir = dir.path().to_path_buf();
    let app_dir_string = app_dir.to_string_lossy().into_owned();
    let conn = db::open(&app_dir).expect("open");
    let key = [27u8; 32];

    let preference_conv =
        db::create_conversation(&conn, &key, "Preferences").expect("preference conversation");
    let planning_conv =
        db::create_conversation(&conn, &key, "Planning").expect("planning conversation");

    db::insert_message(
        &conn,
        &key,
        &preference_conv.id,
        "user",
        "Please answer in Chinese and keep responses short and practical.",
    )
    .expect("preference");
    db::insert_message(
        &conn,
        &key,
        &planning_conv.id,
        "user",
        "Help me plan next week's launch checklist.",
    )
    .expect("planning");

    crate::knowledge::ensure_knowledge_rebuild_requested(&conn).expect("request rebuild");
    crate::knowledge::process_pending_knowledge_index_jobs_active(&conn, &key, 256)
        .expect("process jobs");

    let document_id = "generated:preference:response-language".to_string();

    crate::api::knowledge::db_upsert_knowledge_memory_feedback(
        app_dir_string.clone(),
        key.to_vec(),
        document_id.clone(),
        Some(crate::knowledge::KnowledgeMemoryStatus::Confirmed),
        true,
        false,
        true,
        Some("Preferred reply language".to_string()),
        Some("Always reply in Chinese unless I ask for another language.".to_string()),
    )
    .expect("update feedback");

    let updated = crate::api::knowledge::db_get_knowledge_document(
        app_dir_string.clone(),
        key.to_vec(),
        document_id.clone(),
    )
    .expect("updated document");
    assert_eq!(
        updated.document.title.as_deref(),
        Some("Preferred reply language")
    );
    assert_eq!(
        updated.document.summary.as_deref(),
        Some("Always reply in Chinese unless I ask for another language.")
    );
    assert_eq!(
        updated.document.memory_feedback.status,
        Some(crate::knowledge::KnowledgeMemoryStatus::Confirmed)
    );
    assert!(updated.document.memory_feedback.use_for_ask_ai);
    assert!(updated.document.memory_feedback.marked_inaccurate);

    let contexts = crate::rag::try_build_knowledge_contexts_for_tests(
        &conn,
        &key,
        "Help me plan next week's launch checklist.",
        6,
        crate::rag::Focus::ThisThread,
        &planning_conv.id,
        None,
    )
    .expect("knowledge contexts");
    assert!(
        contexts.iter().any(|ctx| {
            ctx.contains("Always reply in Chinese unless I ask for another language.")
        }),
        "contexts: {contexts:?}"
    );

    crate::api::knowledge::db_upsert_knowledge_memory_feedback(
        app_dir_string.clone(),
        key.to_vec(),
        document_id.clone(),
        Some(crate::knowledge::KnowledgeMemoryStatus::Confirmed),
        false,
        false,
        true,
        Some("Preferred reply language".to_string()),
        Some("Always reply in Chinese unless I ask for another language.".to_string()),
    )
    .expect("disable ask ai usage");

    let contexts = crate::rag::try_build_knowledge_contexts_for_tests(
        &conn,
        &key,
        "Help me plan next week's launch checklist.",
        6,
        crate::rag::Focus::ThisThread,
        &planning_conv.id,
        None,
    )
    .expect("knowledge contexts after disable");
    assert!(
        contexts.iter().all(|ctx| {
            !ctx.contains("Always reply in Chinese unless I ask for another language.")
        }),
        "contexts: {contexts:?}"
    );
}

#[test]
fn knowledge_memory_delete_hides_cards_from_list_but_keeps_detail_restorable() {
    let dir = tempfile::tempdir().expect("tempdir");
    let app_dir = dir.path().to_path_buf();
    let app_dir_string = app_dir.to_string_lossy().into_owned();
    let conn = db::open(&app_dir).expect("open");
    let key = [26u8; 32];

    let conv = db::create_conversation(&conn, &key, "Inbox").expect("conversation");
    db::insert_message(
        &conn,
        &key,
        &conv.id,
        "user",
        "Please answer in Chinese and keep responses short and practical.",
    )
    .expect("preference");

    crate::knowledge::ensure_knowledge_rebuild_requested(&conn).expect("request rebuild");
    crate::knowledge::process_pending_knowledge_index_jobs_active(&conn, &key, 256)
        .expect("process jobs");

    let document_id = "generated:preference:response-language".to_string();
    let listed_before = crate::api::knowledge::db_list_knowledge_documents(
        app_dir_string.clone(),
        key.to_vec(),
        100,
        0,
    )
    .expect("list before delete");
    assert!(listed_before
        .iter()
        .any(|document| document.document_id == document_id));

    crate::api::knowledge::db_upsert_knowledge_memory_feedback(
        app_dir_string.clone(),
        key.to_vec(),
        document_id.clone(),
        None,
        true,
        true,
        false,
        None,
        None,
    )
    .expect("delete feedback");

    let listed_after = crate::api::knowledge::db_list_knowledge_documents(
        app_dir_string.clone(),
        key.to_vec(),
        100,
        0,
    )
    .expect("list after delete");
    assert!(listed_after
        .iter()
        .all(|document| document.document_id != document_id));

    let deleted_detail = crate::api::knowledge::db_get_knowledge_document(
        app_dir_string.clone(),
        key.to_vec(),
        document_id.clone(),
    )
    .expect("deleted detail");
    assert!(deleted_detail.document.memory_feedback.is_deleted);

    crate::api::knowledge::db_upsert_knowledge_memory_feedback(
        app_dir_string,
        key.to_vec(),
        document_id.clone(),
        None,
        true,
        false,
        false,
        None,
        None,
    )
    .expect("restore memory");

    let listed_restored = crate::api::knowledge::db_list_knowledge_documents(
        app_dir.to_string_lossy().into_owned(),
        key.to_vec(),
        100,
        0,
    )
    .expect("list after restore");
    assert!(listed_restored
        .iter()
        .any(|document| document.document_id == document_id));
}

#[test]
fn knowledge_memory_feedback_bumps_effective_updated_at_and_sort_order() {
    let dir = tempfile::tempdir().expect("tempdir");
    let app_dir = dir.path().to_path_buf();
    let app_dir_string = app_dir.to_string_lossy().into_owned();
    let conn = db::open(&app_dir).expect("open");
    let key = [24u8; 32];

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
        "I'm a developer building a release companion for launch week.",
    )
    .expect("profile");

    crate::knowledge::ensure_knowledge_rebuild_requested(&conn).expect("request rebuild");
    crate::knowledge::process_pending_knowledge_index_jobs_active(&conn, &key, 256)
        .expect("process jobs");

    let target_document_id = "generated:preference:response-language";
    let other_document_id = "generated:profile:self-profile";
    conn.execute(
        "UPDATE knowledge_documents SET updated_at_ms = ?2 WHERE document_id = ?1",
        params![target_document_id, 10_i64],
    )
    .expect("age target document");
    conn.execute(
        "UPDATE knowledge_documents SET updated_at_ms = ?2 WHERE document_id = ?1",
        params![other_document_id, 20_i64],
    )
    .expect("age comparison document");

    let feedback = crate::api::knowledge::db_upsert_knowledge_memory_feedback(
        app_dir_string.clone(),
        key.to_vec(),
        target_document_id.to_string(),
        Some(crate::knowledge::KnowledgeMemoryStatus::Confirmed),
        true,
        false,
        false,
        None,
        None,
    )
    .expect("update feedback");
    let feedback_updated_at = feedback.updated_at_ms.expect("feedback timestamp");

    let listed =
        crate::api::knowledge::db_list_knowledge_documents(app_dir_string, key.to_vec(), 100, 0)
            .expect("list documents");
    let target = listed
        .iter()
        .find(|document| document.document_id == target_document_id)
        .expect("target document");

    assert_eq!(
        listed.first().map(|document| document.document_id.as_str()),
        Some(target_document_id)
    );
    assert!(target.updated_at_ms >= feedback_updated_at);
}

#[test]
fn generated_memory_cards_expose_backend_native_section_status_and_source_count() {
    let dir = tempfile::tempdir().expect("tempdir");
    let app_dir = dir.path().to_path_buf();
    let app_dir_string = app_dir.to_string_lossy().into_owned();
    let conn = db::open(&app_dir).expect("open");
    let key = [25u8; 32];

    let conv = db::create_conversation(&conn, &key, "Inbox").expect("conversation");
    db::insert_message(
        &conn,
        &key,
        &conv.id,
        "user",
        "Please answer in Chinese and keep responses short and practical.",
    )
    .expect("preference");
    let _ = db::upsert_todo(
        &conn,
        &key,
        "todo-pattern-a",
        "Draft roadmap",
        None,
        "open",
        None,
        None,
        None,
        None,
        None,
        None,
    )
    .expect("todo a");
    let _ = db::upsert_todo(
        &conn,
        &key,
        "todo-pattern-b",
        "Review launch notes",
        None,
        "in_progress",
        None,
        None,
        None,
        None,
        None,
        None,
    )
    .expect("todo b");

    let generated =
        crate::knowledge::memory_synthesis::collect_generated_memory_documents(&conn, &key)
            .expect("collect generated");
    let generated_pattern = generated
        .iter()
        .find(|document| document.document_id == "generated:pattern:active-task-focus")
        .expect("generated pattern");
    assert_eq!(
        generated_pattern
            .memory_display
            .as_ref()
            .expect("generated pattern display")
            .source_count,
        2
    );

    crate::knowledge::ensure_knowledge_rebuild_requested(&conn).expect("request rebuild");
    crate::knowledge::process_pending_knowledge_index_jobs_active(&conn, &key, 256)
        .expect("process jobs");

    let stored_pattern_source_count: i64 = conn
        .query_row(
            "SELECT memory_source_count FROM knowledge_documents WHERE document_id = ?1",
            rusqlite::params!["generated:pattern:active-task-focus"],
            |row| row.get(0),
        )
        .expect("stored pattern source count");
    assert_eq!(stored_pattern_source_count, 2);

    let documents =
        crate::api::knowledge::db_list_knowledge_documents(app_dir_string, key.to_vec(), 100, 0)
            .expect("list documents");

    let preference = documents
        .iter()
        .find(|document| document.document_id == "generated:preference:response-language")
        .expect("preference document");
    let preference_display = preference
        .memory_display
        .as_ref()
        .expect("preference memory display");
    assert_eq!(
        preference_display.section,
        crate::knowledge::KnowledgeMemorySection::Preference
    );
    assert_eq!(
        preference_display.status,
        crate::knowledge::KnowledgeMemoryStatus::Inferred
    );
    assert_eq!(preference_display.source_count, 1);

    let pattern = documents
        .iter()
        .find(|document| document.document_id == "generated:pattern:active-task-focus")
        .expect("pattern document");
    let pattern_display = pattern
        .memory_display
        .as_ref()
        .expect("pattern memory display");
    assert_eq!(
        pattern_display.section,
        crate::knowledge::KnowledgeMemorySection::Project
    );
    assert_eq!(
        pattern_display.status,
        crate::knowledge::KnowledgeMemoryStatus::Inferred
    );
    assert_eq!(pattern_display.source_count, 2);
}

#[test]
fn generated_memory_documents_api_excludes_non_generated_documents() {
    let dir = tempfile::tempdir().expect("tempdir");
    let app_dir = dir.path().to_path_buf();
    let app_dir_string = app_dir.to_string_lossy().into_owned();
    let conn = db::open(&app_dir).expect("open");
    let key = [27u8; 32];

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
        "A normal source message that should not show in memory center listings.",
    )
    .expect("source message");

    crate::knowledge::ensure_knowledge_rebuild_requested(&conn).expect("request rebuild");
    crate::knowledge::process_pending_knowledge_index_jobs_active(&conn, &key, 256)
        .expect("process jobs");

    let generated = crate::api::knowledge::db_list_generated_memory_documents(
        app_dir_string,
        key.to_vec(),
        100,
        0,
    )
    .expect("generated memory docs");

    assert!(!generated.is_empty());
    assert!(generated
        .iter()
        .all(|document| document.origin_type == crate::knowledge::KnowledgeOriginType::Generated));
    assert!(generated
        .iter()
        .all(|document| !document.document_id.starts_with("message:")));
}
