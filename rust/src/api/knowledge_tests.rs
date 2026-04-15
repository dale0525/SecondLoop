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
fn knowledge_memory_feedback_overrides_detail_and_page_policy_controls_ask_ai_usage() {
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
        contexts.iter().all(|ctx| {
            !ctx.contains("Always reply in Chinese unless I ask for another language.")
        }),
        "marked inaccurate memories should not remain answer-eligible: {contexts:?}"
    );

    crate::api::knowledge::db_set_knowledge_page_answer_allowed(
        app_dir_string.clone(),
        key.to_vec(),
        "page:preferences".to_string(),
        false,
        Some("Do not use this page in answers right now.".to_string()),
    )
    .expect("disable page answer usage");

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

#[test]
fn knowledge_memory_feedback_survives_rebuild_reset() {
    let dir = tempfile::tempdir().expect("tempdir");
    let app_dir = dir.path().to_path_buf();
    let app_dir_string = app_dir.to_string_lossy().into_owned();
    let conn = db::open(&app_dir).expect("open");
    let key = [28u8; 32];

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
    .expect("seed feedback");

    crate::knowledge::ensure_knowledge_rebuild_requested(&conn).expect("request rebuild again");
    crate::knowledge::process_pending_knowledge_index_jobs_active(&conn, &key, 256)
        .expect("process jobs again");

    let rebuilt =
        crate::api::knowledge::db_get_knowledge_document(app_dir_string, key.to_vec(), document_id)
            .expect("rebuilt document");

    assert_eq!(
        rebuilt.document.title.as_deref(),
        Some("Preferred reply language")
    );
    assert_eq!(
        rebuilt.document.summary.as_deref(),
        Some("Always reply in Chinese unless I ask for another language.")
    );
    assert_eq!(
        rebuilt.document.memory_feedback.status,
        Some(crate::knowledge::KnowledgeMemoryStatus::Confirmed)
    );
    assert!(!rebuilt.document.memory_feedback.use_for_ask_ai);
    assert!(rebuilt.document.memory_feedback.marked_inaccurate);
}

#[test]
fn knowledge_pages_api_lists_page_summaries_and_reads_detail() {
    let dir = tempfile::tempdir().expect("tempdir");
    let app_dir = dir.path().to_path_buf();
    let app_dir_string = app_dir.to_string_lossy().into_owned();
    let conn = db::open(&app_dir).expect("open");
    let key = [33u8; 32];

    let conv = db::create_conversation(&conn, &key, "Inbox").expect("conversation");
    db::insert_message(
        &conn,
        &key,
        &conv.id,
        "user",
        "Please answer in Chinese and keep responses short and practical.",
    )
    .expect("seed preference");

    crate::knowledge::ensure_knowledge_rebuild_requested(&conn).expect("request rebuild");
    crate::knowledge::process_pending_knowledge_index_jobs_active(&conn, &key, 256)
        .expect("process jobs");

    let summaries = crate::api::knowledge::db_list_knowledge_page_summaries(
        app_dir_string.clone(),
        key.to_vec(),
    )
    .expect("list page summaries");
    let preferences = summaries
        .iter()
        .find(|page| page.page_id == "page:preferences")
        .expect("preferences summary");
    assert_eq!(
        preferences.page_type,
        crate::knowledge::KnowledgePageType::Preferences
    );
    assert_eq!(preferences.title, "Preferences");
    assert!(preferences.answer_policy.default_allowed);

    let detail = crate::api::knowledge::db_get_knowledge_page_detail(
        app_dir_string,
        key.to_vec(),
        "page:preferences".to_string(),
    )
    .expect("page detail");
    assert_eq!(detail.page.page_id, "page:preferences");
    assert!(!detail.history.is_empty());
    assert!(detail.page.current_body.contains("Chinese"));
    assert!(detail
        .source_document_ids
        .iter()
        .any(|document_id| document_id == "generated:preference:response-language"));
    assert!(!detail.version_snapshots.is_empty());
    assert!(detail
        .version_snapshots
        .iter()
        .any(|snapshot| snapshot.title == "Preferences"));
    assert!(detail
        .evidence_entries
        .iter()
        .any(|entry| entry.kind == crate::knowledge::KnowledgePageEvidenceKind::Support));
}

#[test]
fn knowledge_pages_api_keeps_audit_only_pages_in_summary_listing() {
    let dir = tempfile::tempdir().expect("tempdir");
    let app_dir = dir.path().to_path_buf();
    let app_dir_string = app_dir.to_string_lossy().into_owned();
    let conn = db::open(&app_dir).expect("open");
    let key = [91u8; 32];

    let conv = db::create_conversation(&conn, &key, "Inbox").expect("conversation");
    db::insert_message(
        &conn,
        &key,
        &conv.id,
        "user",
        "Please answer in Chinese and keep responses short and practical.",
    )
    .expect("seed preference");

    crate::knowledge::ensure_knowledge_rebuild_requested(&conn).expect("request rebuild");
    crate::knowledge::process_pending_knowledge_index_jobs_active(&conn, &key, 256)
        .expect("process jobs");
    crate::api::knowledge::db_remove_knowledge_page(
        app_dir_string.clone(),
        key.to_vec(),
        "page:preferences".to_string(),
        None,
    )
    .expect("remove page");

    let summaries =
        crate::api::knowledge::db_list_knowledge_page_summaries(app_dir_string, key.to_vec())
            .expect("list page summaries");
    let preferences = summaries
        .iter()
        .find(|page| page.page_id == "page:preferences")
        .expect("removed preferences summary");
    assert_eq!(
        preferences.state,
        crate::knowledge::KnowledgePageState::Removed
    );
}

#[test]
fn knowledge_page_actions_update_state_history_and_answer_policy() {
    let dir = tempfile::tempdir().expect("tempdir");
    let app_dir = dir.path().to_path_buf();
    let app_dir_string = app_dir.to_string_lossy().into_owned();
    let conn = db::open(&app_dir).expect("open");
    let key = [34u8; 32];

    let conv = db::create_conversation(&conn, &key, "Inbox").expect("conversation");
    db::insert_message(
        &conn,
        &key,
        &conv.id,
        "user",
        "Please answer in Chinese and keep responses short and practical.",
    )
    .expect("seed preference");

    crate::knowledge::ensure_knowledge_rebuild_requested(&conn).expect("request rebuild");
    crate::knowledge::process_pending_knowledge_index_jobs_active(&conn, &key, 256)
        .expect("process jobs");

    let corrected = crate::api::knowledge::db_correct_knowledge_page(
        app_dir_string.clone(),
        key.to_vec(),
        "page:preferences".to_string(),
        Some("Reply Preferences".to_string()),
        Some("Always answer in Chinese first.".to_string()),
        Some("Always answer in Chinese first. Keep the tone concise.".to_string()),
    )
    .expect("correct page");
    assert_eq!(corrected.page.title, "Reply Preferences");
    assert!(corrected.page.human_corrected);
    assert_eq!(
        corrected.history.first().map(|item| item.change_type),
        Some(crate::knowledge::history::KnowledgePageChangeType::Corrected)
    );

    let outdated = crate::api::knowledge::db_mark_knowledge_page_wrong(
        app_dir_string.clone(),
        key.to_vec(),
        "page:preferences".to_string(),
        crate::knowledge::KnowledgeWrongReason::Outdated,
        Some("Language preference changed recently.".to_string()),
    )
    .expect("mark page wrong");
    assert_eq!(
        outdated.page.state,
        crate::knowledge::KnowledgePageState::Outdated
    );
    assert!(outdated.page.answer_policy.default_allowed);
    assert!(outdated.page.answer_policy.requires_temporal_framing);
    assert_eq!(
        outdated.history.first().map(|item| item.reason.as_deref()),
        Some(Some("Language preference changed recently."))
    );

    let muted = crate::api::knowledge::db_set_knowledge_page_answer_allowed(
        app_dir_string.clone(),
        key.to_vec(),
        "page:preferences".to_string(),
        false,
        Some("Do not use until reviewed.".to_string()),
    )
    .expect("mute page answers");
    assert_eq!(
        muted.page.state,
        crate::knowledge::KnowledgePageState::AnswerMuted
    );
    assert!(!muted.page.answer_policy.default_allowed);
    assert!(!muted.page.answer_policy.requires_temporal_framing);
    assert_eq!(
        muted.history.first().map(|item| item.change_type),
        Some(crate::knowledge::history::KnowledgePageChangeType::Muted)
    );

    assert!(muted.version_snapshots.len() >= 3);
    assert!(muted
        .version_snapshots
        .iter()
        .any(|snapshot| snapshot.title == "Reply Preferences"));
    assert!(muted
        .version_snapshots
        .iter()
        .any(|snapshot| snapshot.title == "Preferences"));

    for revision in 0..9 {
        let edited = crate::api::knowledge::db_correct_knowledge_page(
            app_dir.to_string_lossy().into_owned(),
            key.to_vec(),
            "page:preferences".to_string(),
            None,
            Some(format!("Muted summary revision {revision}")),
            Some(format!("Muted body revision {revision}")),
        )
        .expect("edit muted page");
        assert_eq!(
            edited.page.state,
            crate::knowledge::KnowledgePageState::AnswerMuted
        );
    }

    let unmuted_after_many_muted_versions =
        crate::api::knowledge::db_set_knowledge_page_answer_allowed(
            app_dir_string.clone(),
            key.to_vec(),
            "page:preferences".to_string(),
            true,
            Some("Restore previous governance after many muted edits.".to_string()),
        )
        .expect("unmute page answers after many muted versions");
    assert_eq!(
        unmuted_after_many_muted_versions.page.state,
        crate::knowledge::KnowledgePageState::Outdated
    );
    assert!(
        unmuted_after_many_muted_versions
            .page
            .answer_policy
            .requires_temporal_framing
    );

    let unmuted = crate::api::knowledge::db_set_knowledge_page_answer_allowed(
        app_dir_string.clone(),
        key.to_vec(),
        "page:preferences".to_string(),
        true,
        Some("Reviewed and allowed again.".to_string()),
    )
    .expect("unmute page answers");
    assert_eq!(
        unmuted.page.state,
        crate::knowledge::KnowledgePageState::Outdated
    );
    assert!(unmuted.page.answer_policy.default_allowed);
    assert!(unmuted.page.answer_policy.requires_temporal_framing);

    let cleared_body = crate::api::knowledge::db_correct_knowledge_page(
        app_dir.to_string_lossy().into_owned(),
        key.to_vec(),
        "page:preferences".to_string(),
        None,
        Some("Always answer in Chinese first.".to_string()),
        Some(String::new()),
    )
    .expect("clear body");
    assert_eq!(cleared_body.page.current_body, "");

    let reset_overrides = crate::api::knowledge::db_correct_knowledge_page(
        app_dir.to_string_lossy().into_owned(),
        key.to_vec(),
        "page:preferences".to_string(),
        Some(String::new()),
        Some(String::new()),
        None,
    )
    .expect("reset title and summary overrides");
    assert_eq!(reset_overrides.page.title, "Preferences");
    assert_ne!(
        reset_overrides.page.current_summary,
        "Always answer in Chinese first."
    );
    assert!(reset_overrides.page.current_summary.contains("Chinese"));
}

#[test]
fn open_question_page_detail_keeps_only_document_ids_in_source_document_ids() {
    let dir = tempfile::tempdir().expect("tempdir");
    let app_dir = dir.path().to_path_buf();
    let app_dir_string = app_dir.to_string_lossy().into_owned();
    let conn = db::open(&app_dir).expect("open");
    let key = [79u8; 32];

    let conv = db::create_conversation(&conn, &key, "Inbox").expect("conversation");
    db::insert_message(&conn, &key, &conv.id, "user", "Please answer in Chinese.")
        .expect("seed preference");

    crate::knowledge::ensure_knowledge_rebuild_requested(&conn).expect("request rebuild");
    crate::knowledge::process_pending_knowledge_index_jobs_active(&conn, &key, 256)
        .expect("process jobs");

    crate::api::knowledge::db_upsert_knowledge_memory_feedback(
        app_dir_string.clone(),
        key.to_vec(),
        "generated:preference:response-language".to_string(),
        Some(crate::knowledge::KnowledgeMemoryStatus::Confirmed),
        false,
        false,
        true,
        None,
        None,
    )
    .expect("mark generated memory inaccurate");

    let detail = crate::api::knowledge::db_get_knowledge_page_detail(
        app_dir_string,
        key.to_vec(),
        "page:open-questions:preference:response_language".to_string(),
    )
    .expect("open question detail");

    assert!(
        detail
            .source_document_ids
            .iter()
            .all(|document_id| !document_id.starts_with("message:")),
        "source_document_ids: {:?}",
        detail.source_document_ids
    );
    assert!(
        detail
            .source_document_ids
            .iter()
            .all(|document_id| !document_id.starts_with("attachment:")),
        "source_document_ids: {:?}",
        detail.source_document_ids
    );
    assert!(
        detail
            .source_document_ids
            .iter()
            .any(|document_id| document_id == "generated:preference:response-language"),
        "source_document_ids: {:?}",
        detail.source_document_ids
    );
}

#[test]
fn repeated_page_reads_do_not_append_recompile_history_after_manual_correction() {
    let dir = tempfile::tempdir().expect("tempdir");
    let app_dir = dir.path().to_path_buf();
    let app_dir_string = app_dir.to_string_lossy().into_owned();
    let conn = db::open(&app_dir).expect("open");
    let key = [39u8; 32];

    let conv = db::create_conversation(&conn, &key, "Inbox").expect("conversation");
    db::insert_message(
        &conn,
        &key,
        &conv.id,
        "user",
        "Please answer in Chinese and keep responses short and practical.",
    )
    .expect("seed preference");

    crate::knowledge::ensure_knowledge_rebuild_requested(&conn).expect("request rebuild");
    crate::knowledge::process_pending_knowledge_index_jobs_active(&conn, &key, 256)
        .expect("process jobs");

    let corrected = crate::api::knowledge::db_correct_knowledge_page(
        app_dir_string.clone(),
        key.to_vec(),
        "page:preferences".to_string(),
        Some("Reply Preferences".to_string()),
        Some("Always answer in Chinese first.".to_string()),
        Some("Always answer in Chinese first. Keep the tone concise.".to_string()),
    )
    .expect("correct page");
    let corrected_history_len = corrected.history.len();
    let corrected_version_len = corrected.version_snapshots.len();

    let reread = crate::api::knowledge::db_get_knowledge_page_detail(
        app_dir_string.clone(),
        key.to_vec(),
        "page:preferences".to_string(),
    )
    .expect("read corrected page once");
    assert_eq!(reread.history.len(), corrected_history_len);
    assert_eq!(reread.version_snapshots.len(), corrected_version_len);

    let reread_again = crate::api::knowledge::db_get_knowledge_page_detail(
        app_dir_string,
        key.to_vec(),
        "page:preferences".to_string(),
    )
    .expect("read corrected page twice");
    assert_eq!(reread_again.history.len(), corrected_history_len);
    assert_eq!(reread_again.version_snapshots.len(), corrected_version_len);
}

#[test]
fn removed_page_stays_removed_across_refresh_reads() {
    let dir = tempfile::tempdir().expect("tempdir");
    let app_dir = dir.path().to_path_buf();
    let app_dir_string = app_dir.to_string_lossy().into_owned();
    let conn = db::open(&app_dir).expect("open");
    let key = [43u8; 32];

    let conv = db::create_conversation(&conn, &key, "Inbox").expect("conversation");
    db::insert_message(
        &conn,
        &key,
        &conv.id,
        "user",
        "Please answer in Chinese and keep responses short and practical.",
    )
    .expect("seed preference");

    crate::knowledge::ensure_knowledge_rebuild_requested(&conn).expect("request rebuild");
    crate::knowledge::process_pending_knowledge_index_jobs_active(&conn, &key, 256)
        .expect("process jobs");

    let removed = crate::api::knowledge::db_remove_knowledge_page(
        app_dir_string.clone(),
        key.to_vec(),
        "page:preferences".to_string(),
        Some("User explicitly removed this page.".to_string()),
    )
    .expect("remove page");
    assert_eq!(
        removed.page.state,
        crate::knowledge::KnowledgePageState::Removed
    );

    let reread = crate::api::knowledge::db_get_knowledge_page_detail(
        app_dir_string.clone(),
        key.to_vec(),
        "page:preferences".to_string(),
    )
    .expect("reread removed page");
    assert_eq!(
        reread.page.state,
        crate::knowledge::KnowledgePageState::Removed
    );
    assert!(!reread.page.answer_policy.default_allowed);

    let summaries =
        crate::api::knowledge::db_list_knowledge_page_summaries(app_dir_string, key.to_vec())
            .expect("list summaries");
    assert!(
        summaries
            .iter()
            .all(|page| page.page_id != "page:preferences"),
        "removed page should stay hidden from summaries"
    );
}

#[test]
fn correct_knowledge_page_rolls_back_when_history_table_is_unavailable() {
    let dir = tempfile::tempdir().expect("tempdir");
    let conn = db::open(dir.path()).expect("open");
    let key = [80u8; 32];
    let now = 1_710_000_000_000i64;

    let mut page = crate::knowledge::KnowledgePage::new(
        "page:preferences",
        crate::knowledge::KnowledgePageType::Preferences,
        "Preferences",
        now,
    );
    page.current_summary = "Reply in Chinese.".to_string();
    page.current_body = "Reply in Chinese.".to_string();
    page.primary_evidence_ids = vec!["doc:primary".to_string()];
    page.source_count = 1;

    db::upsert_compiled_knowledge_pages(
        &conn,
        &key,
        &[crate::knowledge::compiler::CompiledKnowledgePageRecord {
            page,
            source_document_ids: vec!["doc:primary".to_string()],
            claim_ids: vec!["claim:primary".to_string()],
        }],
    )
    .expect("seed page");

    conn.execute_batch(
        r#"
CREATE TRIGGER fail_knowledge_page_history_insert
BEFORE INSERT ON knowledge_page_history
BEGIN
    SELECT RAISE(FAIL, 'forced history insert failure');
END;
"#,
    )
    .expect("create failing trigger");

    let error = db::apply_knowledge_page_correction(
        &conn,
        &key,
        "page:preferences",
        Some("Corrected Preferences".to_string()),
        Some("Manual summary".to_string()),
        None,
    )
    .expect_err("correction should fail when history insert fails");
    assert!(error.to_string().contains("forced history insert failure"));

    let row = conn
        .query_row(
            "SELECT manual_title, manual_summary, human_corrected FROM knowledge_pages WHERE page_id = ?1",
            ["page:preferences"],
            |row| {
                Ok((
                    row.get::<_, Option<Vec<u8>>>(0)?,
                    row.get::<_, Option<Vec<u8>>>(1)?,
                    row.get::<_, i64>(2)?,
                ))
            },
        )
        .expect("load stored page row");

    assert!(row.0.is_none(), "manual title should roll back");
    assert!(row.1.is_none(), "manual summary should roll back");
    assert_eq!(row.2, 0, "human_corrected should roll back");
}

#[test]
fn set_answer_allowed_rolls_back_when_history_table_is_unavailable() {
    let dir = tempfile::tempdir().expect("tempdir");
    let conn = db::open(dir.path()).expect("open");
    let key = [81u8; 32];
    let now = 1_710_000_000_000i64;

    let mut page = crate::knowledge::KnowledgePage::new(
        "page:preferences",
        crate::knowledge::KnowledgePageType::Preferences,
        "Preferences",
        now,
    );
    page.current_summary = "Reply in Chinese.".to_string();
    page.current_body = "Reply in Chinese.".to_string();
    page.primary_evidence_ids = vec!["doc:primary".to_string()];
    page.source_count = 1;

    db::upsert_compiled_knowledge_pages(
        &conn,
        &key,
        &[crate::knowledge::compiler::CompiledKnowledgePageRecord {
            page,
            source_document_ids: vec!["doc:primary".to_string()],
            claim_ids: vec!["claim:primary".to_string()],
        }],
    )
    .expect("seed page");

    conn.execute_batch(
        r#"
CREATE TRIGGER fail_knowledge_page_history_insert
BEFORE INSERT ON knowledge_page_history
BEGIN
    SELECT RAISE(FAIL, 'forced history insert failure');
END;
"#,
    )
    .expect("create failing trigger");

    let error = db::set_knowledge_page_answer_allowed(&conn, &key, "page:preferences", false, None)
        .expect_err("answer policy mutation should fail when history insert fails");
    assert!(error.to_string().contains("forced history insert failure"));

    let row = conn
        .query_row(
            "SELECT state, answer_default_allowed FROM knowledge_pages WHERE page_id = ?1",
            ["page:preferences"],
            |row| Ok((row.get::<_, String>(0)?, row.get::<_, i64>(1)?)),
        )
        .expect("load stored page row");

    assert_eq!(row.0, "active", "state should roll back");
    assert_eq!(row.1, 1, "answer_default_allowed should roll back");
}

#[test]
fn knowledge_page_detail_exposes_classified_evidence_entries() {
    let dir = tempfile::tempdir().expect("tempdir");
    let app_dir = dir.path().to_path_buf();
    let conn = db::open(&app_dir).expect("open");
    let key = [36u8; 32];
    let now = 1_710_000_000_000i64;

    let mut page = crate::knowledge::KnowledgePage::new(
        "page:preferences",
        crate::knowledge::KnowledgePageType::Preferences,
        "Preferences",
        now,
    );
    page.current_summary = "Reply in Chinese by default.".to_string();
    page.current_body = "Reply in Chinese by default.".to_string();
    page.primary_evidence_ids = vec!["generated:preference:response-language".to_string()];
    page.source_count = 3;

    db::replace_knowledge_claims(
        &conn,
        &key,
        &[
            crate::knowledge::KnowledgeClaim {
                claim_id: "claim:support".to_string(),
                subject_id: "user:self".to_string(),
                claim_type: crate::knowledge::KnowledgeClaimType::Preference,
                facet_key: "response_language".to_string(),
                statement: "User prefers replies in Chinese.".to_string(),
                normalized_value: Some("Chinese".to_string()),
                time_scope: crate::knowledge::KnowledgeClaimTimeScope::Stable,
                valid_from_ms: None,
                valid_until_ms: None,
                confidence: 0.9,
                source_ref_ids: vec!["generated:preference:response-language".to_string()],
                source_count: 1,
                conflict_with_claim_ids: vec![],
                status: crate::knowledge::KnowledgeClaimStatus::Active,
                human_confirmed: false,
                human_corrected: false,
                answer_allowed: true,
                created_at_ms: now,
                updated_at_ms: now,
            },
            crate::knowledge::KnowledgeClaim {
                claim_id: "claim:conflict".to_string(),
                subject_id: "user:self".to_string(),
                claim_type: crate::knowledge::KnowledgeClaimType::Preference,
                facet_key: "response_language".to_string(),
                statement: "User prefers replies in English.".to_string(),
                normalized_value: Some("English".to_string()),
                time_scope: crate::knowledge::KnowledgeClaimTimeScope::Stable,
                valid_from_ms: None,
                valid_until_ms: None,
                confidence: 0.4,
                source_ref_ids: vec!["generated:preference:response-style".to_string()],
                source_count: 1,
                conflict_with_claim_ids: vec!["claim:support".to_string()],
                status: crate::knowledge::KnowledgeClaimStatus::Disputed,
                human_confirmed: false,
                human_corrected: false,
                answer_allowed: false,
                created_at_ms: now + 1,
                updated_at_ms: now + 1,
            },
            crate::knowledge::KnowledgeClaim {
                claim_id: "claim:supplement".to_string(),
                subject_id: "user:self".to_string(),
                claim_type: crate::knowledge::KnowledgeClaimType::Preference,
                facet_key: "response_format".to_string(),
                statement: "The user once preferred bullet formatting.".to_string(),
                normalized_value: None,
                time_scope: crate::knowledge::KnowledgeClaimTimeScope::Historical,
                valid_from_ms: None,
                valid_until_ms: None,
                confidence: 0.3,
                source_ref_ids: vec!["generated:preference:response-format".to_string()],
                source_count: 1,
                conflict_with_claim_ids: vec![],
                status: crate::knowledge::KnowledgeClaimStatus::Dismissed,
                human_confirmed: false,
                human_corrected: false,
                answer_allowed: false,
                created_at_ms: now + 2,
                updated_at_ms: now + 2,
            },
        ],
    )
    .expect("seed claims");

    db::upsert_compiled_knowledge_pages(
        &conn,
        &key,
        &[crate::knowledge::compiler::CompiledKnowledgePageRecord {
            page,
            source_document_ids: vec![
                "generated:preference:response-language".to_string(),
                "generated:preference:response-style".to_string(),
                "generated:preference:response-format".to_string(),
            ],
            claim_ids: vec![
                "claim:support".to_string(),
                "claim:conflict".to_string(),
                "claim:supplement".to_string(),
            ],
        }],
    )
    .expect("seed page");

    let detail = db::get_knowledge_page_detail(&conn, &key, "page:preferences")
        .expect("load page detail")
        .expect("page detail");

    assert!(detail
        .evidence_entries
        .iter()
        .any(|entry| entry.kind == crate::knowledge::KnowledgePageEvidenceKind::Support));
    assert!(detail
        .evidence_entries
        .iter()
        .any(|entry| entry.kind == crate::knowledge::KnowledgePageEvidenceKind::Conflict));
    assert!(detail
        .evidence_entries
        .iter()
        .any(|entry| entry.kind == crate::knowledge::KnowledgePageEvidenceKind::Supplement));
}

#[test]
fn merge_knowledge_page_into_combines_target_content_and_archives_source() {
    let dir = tempfile::tempdir().expect("tempdir");
    let app_dir = dir.path().to_path_buf();
    let app_dir_string = app_dir.to_string_lossy().into_owned();
    let conn = db::open(&app_dir).expect("open");
    let key = [35u8; 32];
    let now = 1_710_000_000_000i64;

    let mut target_page = crate::knowledge::KnowledgePage::new(
        "page:topics:target",
        crate::knowledge::KnowledgePageType::Topics,
        "Target Topic",
        now,
    );
    target_page.current_summary = "Target summary".to_string();
    target_page.current_body = "Target detail".to_string();
    target_page.primary_evidence_ids = vec!["doc:target".to_string()];
    target_page.related_page_ids = vec!["page:topics:neighbor".to_string()];
    target_page
        .related_page_ids
        .push("page:topics:source".to_string());
    target_page.source_count = 1;
    target_page.confidence_level = 0.62;

    let mut source_page = crate::knowledge::KnowledgePage::new(
        "page:topics:source",
        crate::knowledge::KnowledgePageType::Topics,
        "Source Topic",
        now + 1,
    );
    source_page.current_summary = "Source summary".to_string();
    source_page.current_body = "Source detail".to_string();
    source_page.primary_evidence_ids = vec!["doc:source".to_string()];
    source_page.related_page_ids = vec!["page:topics:target".to_string()];
    source_page.source_count = 1;
    source_page.confidence_level = 0.87;

    let mut neighbor_page = crate::knowledge::KnowledgePage::new(
        "page:topics:neighbor",
        crate::knowledge::KnowledgePageType::Topics,
        "Neighbor Topic",
        now + 2,
    );
    neighbor_page.current_summary = "Neighbor summary".to_string();
    neighbor_page.current_body = "Neighbor detail".to_string();
    neighbor_page.primary_evidence_ids = vec!["doc:neighbor".to_string()];
    neighbor_page.related_page_ids = vec!["page:topics:source".to_string()];
    neighbor_page.source_count = 1;
    neighbor_page.confidence_level = 0.51;

    db::upsert_compiled_knowledge_pages(
        &conn,
        &key,
        &[
            crate::knowledge::compiler::CompiledKnowledgePageRecord {
                page: target_page,
                source_document_ids: vec!["doc:target".to_string()],
                claim_ids: vec!["claim:target".to_string()],
            },
            crate::knowledge::compiler::CompiledKnowledgePageRecord {
                page: source_page,
                source_document_ids: vec!["doc:source".to_string()],
                claim_ids: vec!["claim:source".to_string()],
            },
            crate::knowledge::compiler::CompiledKnowledgePageRecord {
                page: neighbor_page,
                source_document_ids: vec!["doc:neighbor".to_string()],
                claim_ids: vec!["claim:neighbor".to_string()],
            },
        ],
    )
    .expect("seed pages");
    crate::db::mark_knowledge_pages_refreshed(&conn, now + 2).expect("mark pages refreshed");

    let merged = crate::api::knowledge::db_merge_knowledge_page_into(
        app_dir_string.clone(),
        key.to_vec(),
        "page:topics:source".to_string(),
        "page:topics:target".to_string(),
        None,
    )
    .expect("merge knowledge page");

    assert_eq!(
        merged.page.state,
        crate::knowledge::KnowledgePageState::Archived
    );
    assert_eq!(
        merged.history.first().map(|item| item.change_type),
        Some(crate::knowledge::history::KnowledgePageChangeType::Merged)
    );

    let target_detail = db::get_knowledge_page_detail(&conn, &key, "page:topics:target")
        .expect("load target detail")
        .expect("target detail after merge");

    assert!(target_detail
        .page
        .current_summary
        .contains("Target summary"));
    assert!(target_detail
        .page
        .current_summary
        .contains("Source summary"));
    assert!(target_detail.page.current_body.contains("Target detail"));
    assert!(target_detail.page.current_body.contains("Source detail"));
    assert_eq!(
        target_detail.page.state,
        crate::knowledge::KnowledgePageState::Active
    );
    assert_eq!(target_detail.page.source_count, 2);
    assert_eq!(target_detail.page.confidence_level, 0.87);
    assert!(target_detail
        .source_document_ids
        .iter()
        .any(|document_id| document_id == "doc:target"));
    assert!(target_detail
        .source_document_ids
        .iter()
        .any(|document_id| document_id == "doc:source"));
    assert!(target_detail
        .claim_ids
        .iter()
        .any(|claim_id| claim_id == "claim:target"));
    assert!(target_detail
        .claim_ids
        .iter()
        .any(|claim_id| claim_id == "claim:source"));
    assert!(target_detail
        .page
        .primary_evidence_ids
        .iter()
        .any(|document_id| document_id == "doc:target"));
    assert!(target_detail
        .page
        .primary_evidence_ids
        .iter()
        .any(|document_id| document_id == "doc:source"));
    assert_eq!(
        target_detail
            .history
            .first()
            .and_then(|item| item.reason.as_deref()),
        Some("Merged content and provenance from page:topics:source.")
    );

    let neighbor_detail = db::get_knowledge_page_detail(&conn, &key, "page:topics:neighbor")
        .expect("load neighbor detail")
        .expect("neighbor detail after merge");
    assert!(neighbor_detail
        .page
        .related_page_ids
        .iter()
        .any(|page_id| page_id == "page:topics:target"));
    assert!(neighbor_detail
        .page
        .related_page_ids
        .iter()
        .all(|page_id| page_id != "page:topics:source"));
}

#[test]
fn merge_knowledge_page_into_rejects_different_page_types() {
    let dir = tempfile::tempdir().expect("tempdir");
    let app_dir = dir.path().to_path_buf();
    let app_dir_string = app_dir.to_string_lossy().into_owned();
    let conn = db::open(&app_dir).expect("open");
    let key = [38u8; 32];
    let now = 1_710_000_000_000i64;

    let mut target_page = crate::knowledge::KnowledgePage::new(
        "page:about-me",
        crate::knowledge::KnowledgePageType::AboutMe,
        "About Me",
        now,
    );
    target_page.current_summary = "Identity summary".to_string();
    target_page.current_body = "Identity detail".to_string();
    target_page.primary_evidence_ids = vec!["doc:about".to_string()];
    target_page.source_count = 1;

    let mut source_page = crate::knowledge::KnowledgePage::new(
        "page:preferences",
        crate::knowledge::KnowledgePageType::Preferences,
        "Preferences",
        now + 1,
    );
    source_page.current_summary = "Preference summary".to_string();
    source_page.current_body = "Preference detail".to_string();
    source_page.primary_evidence_ids = vec!["doc:preferences".to_string()];
    source_page.source_count = 1;

    db::upsert_compiled_knowledge_pages(
        &conn,
        &key,
        &[
            crate::knowledge::compiler::CompiledKnowledgePageRecord {
                page: target_page,
                source_document_ids: vec!["doc:about".to_string()],
                claim_ids: vec!["claim:about".to_string()],
            },
            crate::knowledge::compiler::CompiledKnowledgePageRecord {
                page: source_page,
                source_document_ids: vec!["doc:preferences".to_string()],
                claim_ids: vec!["claim:preferences".to_string()],
            },
        ],
    )
    .expect("seed pages");
    crate::db::mark_knowledge_pages_refreshed(&conn, now + 2).expect("mark pages refreshed");

    let error = crate::api::knowledge::db_merge_knowledge_page_into(
        app_dir_string,
        key.to_vec(),
        "page:preferences".to_string(),
        "page:about-me".to_string(),
        None,
    )
    .expect_err("merge should reject different page types");
    assert!(error
        .to_string()
        .contains("knowledge pages can only be merged within the same page type"));
}

#[test]
fn merge_knowledge_page_into_rejects_unrelated_mergeable_pages() {
    let dir = tempfile::tempdir().expect("tempdir");
    let app_dir = dir.path().to_path_buf();
    let app_dir_string = app_dir.to_string_lossy().into_owned();
    let conn = db::open(&app_dir).expect("open");
    let key = [39u8; 32];
    let now = 1_710_000_000_000i64;

    let mut target_page = crate::knowledge::KnowledgePage::new(
        "page:topics:alpha",
        crate::knowledge::KnowledgePageType::Topics,
        "Topic Alpha",
        now,
    );
    target_page.current_summary = "Alpha summary".to_string();
    target_page.current_body = "Alpha detail".to_string();
    target_page.primary_evidence_ids = vec!["doc:alpha".to_string()];
    target_page.source_count = 1;

    let mut source_page = crate::knowledge::KnowledgePage::new(
        "page:topics:beta",
        crate::knowledge::KnowledgePageType::Topics,
        "Topic Beta",
        now + 1,
    );
    source_page.current_summary = "Beta summary".to_string();
    source_page.current_body = "Beta detail".to_string();
    source_page.primary_evidence_ids = vec!["doc:beta".to_string()];
    source_page.source_count = 1;

    db::upsert_compiled_knowledge_pages(
        &conn,
        &key,
        &[
            crate::knowledge::compiler::CompiledKnowledgePageRecord {
                page: target_page,
                source_document_ids: vec!["doc:alpha".to_string()],
                claim_ids: vec!["claim:alpha".to_string()],
            },
            crate::knowledge::compiler::CompiledKnowledgePageRecord {
                page: source_page,
                source_document_ids: vec!["doc:beta".to_string()],
                claim_ids: vec!["claim:beta".to_string()],
            },
        ],
    )
    .expect("seed pages");
    crate::db::mark_knowledge_pages_refreshed(&conn, now + 2).expect("mark pages refreshed");

    let error = crate::api::knowledge::db_merge_knowledge_page_into(
        app_dir_string,
        key.to_vec(),
        "page:topics:beta".to_string(),
        "page:topics:alpha".to_string(),
        None,
    )
    .expect_err("merge should reject unrelated mergeable pages");
    assert!(error
        .to_string()
        .contains("knowledge pages can only be merged when they are explicitly related"));
}

#[test]
fn merge_knowledge_page_into_rejects_removed_target_pages() {
    let dir = tempfile::tempdir().expect("tempdir");
    let app_dir = dir.path().to_path_buf();
    let app_dir_string = app_dir.to_string_lossy().into_owned();
    let conn = db::open(&app_dir).expect("open");
    let key = [40u8; 32];
    let now = 1_710_000_000_000i64;

    let mut target_page = crate::knowledge::KnowledgePage::new(
        "page:topics:target",
        crate::knowledge::KnowledgePageType::Topics,
        "Target Topic",
        now,
    );
    target_page.current_summary = "Target summary".to_string();
    target_page.current_body = "Target detail".to_string();
    target_page.primary_evidence_ids = vec!["doc:target".to_string()];
    target_page.related_page_ids = vec!["page:topics:source".to_string()];
    target_page.source_count = 1;

    let mut source_page = crate::knowledge::KnowledgePage::new(
        "page:topics:source",
        crate::knowledge::KnowledgePageType::Topics,
        "Source Topic",
        now + 1,
    );
    source_page.current_summary = "Source summary".to_string();
    source_page.current_body = "Source detail".to_string();
    source_page.primary_evidence_ids = vec!["doc:source".to_string()];
    source_page.related_page_ids = vec!["page:topics:target".to_string()];
    source_page.source_count = 1;

    db::upsert_compiled_knowledge_pages(
        &conn,
        &key,
        &[
            crate::knowledge::compiler::CompiledKnowledgePageRecord {
                page: target_page,
                source_document_ids: vec!["doc:target".to_string()],
                claim_ids: vec!["claim:target".to_string()],
            },
            crate::knowledge::compiler::CompiledKnowledgePageRecord {
                page: source_page,
                source_document_ids: vec!["doc:source".to_string()],
                claim_ids: vec!["claim:source".to_string()],
            },
        ],
    )
    .expect("seed pages");

    crate::api::knowledge::db_remove_knowledge_page(
        app_dir_string.clone(),
        key.to_vec(),
        "page:topics:target".to_string(),
        Some("Removed target page.".to_string()),
    )
    .expect("remove target page");

    let error = crate::api::knowledge::db_merge_knowledge_page_into(
        app_dir_string,
        key.to_vec(),
        "page:topics:source".to_string(),
        "page:topics:target".to_string(),
        None,
    )
    .expect_err("merge should reject removed target");
    assert!(error
        .to_string()
        .contains("knowledge page merge target must stay on normal wiki surfaces"));
}

#[test]
fn related_pages_do_not_create_fragmentation_lints_by_default() {
    let dir = tempfile::tempdir().expect("tempdir");
    let app_dir = dir.path().to_path_buf();
    let conn = db::open(&app_dir).expect("open");
    let key = [37u8; 32];
    let now = 1_710_000_000_000i64;

    let mut page = crate::knowledge::KnowledgePage::new(
        "page:preferences",
        crate::knowledge::KnowledgePageType::Preferences,
        "Preferences",
        now,
    );
    page.current_summary = "Reply in Chinese.".to_string();
    page.current_body = "Reply in Chinese.".to_string();
    page.primary_evidence_ids = vec!["doc:language".to_string()];
    page.related_page_ids = vec!["page:about-me".to_string()];
    page.source_count = 2;

    db::upsert_compiled_knowledge_pages(
        &conn,
        &key,
        &[crate::knowledge::compiler::CompiledKnowledgePageRecord {
            page,
            source_document_ids: vec!["doc:language".to_string(), "doc:style".to_string()],
            claim_ids: vec!["claim:language".to_string()],
        }],
    )
    .expect("upsert page");

    let detail = db::get_knowledge_page_detail(&conn, &key, "page:preferences")
        .expect("load detail")
        .expect("page detail");

    assert!(!detail
        .lint_records
        .iter()
        .any(|lint| lint.kind == crate::knowledge::KnowledgeLintKind::Fragmentation));
}
