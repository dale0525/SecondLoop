use crate::api::knowledge;
use crate::db;
use rusqlite::params;

fn insert_generated_document(
    conn: &rusqlite::Connection,
    key: &[u8; 32],
    document_id: &str,
    summary: &str,
    updated_at_ms: i64,
) {
    let anchor_json = serde_json::to_string(&crate::knowledge::KnowledgeAnchorSet::default())
        .expect("anchor json");
    let raw =
        db::encode_knowledge_document_text(key, document_id, "raw", summary).expect("encode raw");
    let normalized = db::encode_knowledge_document_text(key, document_id, "normalized", summary)
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
           ) VALUES (?1, 'generated', 'summary', 'summary', NULL, 1.0, NULL, ?2, ?3, ?4, ?5, 1, ?6, ?7, ?8, ?9, ?10, ?11, NULL)"#,
        params![
            document_id,
            summary,
            anchor_json,
            raw,
            normalized,
            updated_at_ms,
            crate::knowledge::KNOWLEDGE_SCHEMA_VERSION,
            crate::knowledge::KNOWLEDGE_NORMALIZATION_VERSION,
            crate::knowledge::KNOWLEDGE_SEGMENTATION_VERSION,
            crate::knowledge::KNOWLEDGE_EMBEDDING_POLICY_VERSION,
            crate::knowledge::KNOWLEDGE_RETRIEVAL_POLICY_VERSION,
        ],
    )
    .expect("insert generated document");
}

#[test]
fn correcting_muted_page_preserves_answer_muted_governance() {
    let dir = tempfile::tempdir().expect("tempdir");
    let app_dir_string = dir.path().to_string_lossy().into_owned();
    let conn = db::open(dir.path()).expect("open");
    let key = [81u8; 32];

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

    knowledge::db_set_knowledge_page_answer_allowed(
        app_dir_string.clone(),
        key.to_vec(),
        "page:preferences".to_string(),
        false,
        Some("Mute answers.".to_string()),
    )
    .expect("mute page");

    let corrected = knowledge::db_correct_knowledge_page(
        app_dir_string,
        key.to_vec(),
        "page:preferences".to_string(),
        Some("Reply Preferences".to_string()),
        Some("Always answer in Chinese first.".to_string()),
        Some("Always answer in Chinese first. Keep answers concise.".to_string()),
    )
    .expect("correct page");

    assert_eq!(
        corrected.page.state,
        crate::knowledge::KnowledgePageState::AnswerMuted
    );
    assert!(!corrected.page.answer_policy.default_allowed);
    assert!(!corrected.page.answer_policy.requires_temporal_framing);
}

#[test]
fn correcting_outdated_page_preserves_outdated_governance() {
    let dir = tempfile::tempdir().expect("tempdir");
    let app_dir_string = dir.path().to_string_lossy().into_owned();
    let conn = db::open(dir.path()).expect("open");
    let key = [82u8; 32];

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

    knowledge::db_mark_knowledge_page_wrong(
        app_dir_string.clone(),
        key.to_vec(),
        "page:preferences".to_string(),
        crate::knowledge::KnowledgeWrongReason::Outdated,
        Some("Outdated source".to_string()),
    )
    .expect("mark outdated");

    let corrected = knowledge::db_correct_knowledge_page(
        app_dir_string,
        key.to_vec(),
        "page:preferences".to_string(),
        Some("Reply Preferences".to_string()),
        Some("Always answer in Chinese first.".to_string()),
        Some("Always answer in Chinese first. Keep answers concise.".to_string()),
    )
    .expect("correct page");

    assert_eq!(
        corrected.page.state,
        crate::knowledge::KnowledgePageState::Outdated
    );
    assert!(corrected.page.answer_policy.default_allowed);
    assert!(corrected.page.answer_policy.requires_temporal_framing);
}

#[test]
fn correcting_archived_page_preserves_archived_governance() {
    let dir = tempfile::tempdir().expect("tempdir");
    let app_dir_string = dir.path().to_string_lossy().into_owned();
    let conn = db::open(dir.path()).expect("open");
    let key = [83u8; 32];

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

    knowledge::db_archive_knowledge_page(
        app_dir_string.clone(),
        key.to_vec(),
        "page:preferences".to_string(),
        Some("Archive page".to_string()),
    )
    .expect("archive page");

    let corrected = knowledge::db_correct_knowledge_page(
        app_dir_string,
        key.to_vec(),
        "page:preferences".to_string(),
        Some("Reply Preferences".to_string()),
        Some("Always answer in Chinese first.".to_string()),
        Some("Always answer in Chinese first. Keep answers concise.".to_string()),
    )
    .expect("correct page");

    assert_eq!(
        corrected.page.state,
        crate::knowledge::KnowledgePageState::Archived
    );
    assert!(!corrected.page.answer_policy.default_allowed);
    assert!(!corrected.page.answer_policy.requires_temporal_framing);
}

#[test]
fn knowledge_page_reads_skip_recompile_when_pages_are_current() {
    let dir = tempfile::tempdir().expect("tempdir");
    let app_dir_string = dir.path().to_string_lossy().into_owned();
    let conn = db::open(dir.path()).expect("open");
    let key = [84u8; 32];

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

    conn.execute(
        "UPDATE knowledge_rebuild_state SET pages_refresh_required = 0 WHERE state_key = 1",
        [],
    )
    .expect("mark pages current");
    conn.execute_batch(
        r#"
CREATE TRIGGER fail_knowledge_claim_insert
BEFORE INSERT ON knowledge_claims
BEGIN
    SELECT RAISE(FAIL, 'unexpected page recompile');
END;
"#,
    )
    .expect("create failing trigger");

    let detail = knowledge::db_get_knowledge_page_detail(
        app_dir_string.clone(),
        key.to_vec(),
        "page:preferences".to_string(),
    )
    .expect("read page detail");
    assert_eq!(detail.page.page_id, "page:preferences");

    let summaries = knowledge::db_list_knowledge_page_summaries(app_dir_string, key.to_vec())
        .expect("list summaries");
    assert!(summaries
        .iter()
        .any(|page| page.page_id == "page:preferences"));
}

#[test]
fn listing_recent_knowledge_page_changes_refreshes_pages_when_required() {
    let dir = tempfile::tempdir().expect("tempdir");
    let app_dir_string = dir.path().to_string_lossy().into_owned();
    let conn = db::open(dir.path()).expect("open");
    let key = [85u8; 32];

    insert_generated_document(
        &conn,
        &key,
        "generated:preference:response-language",
        "User prefers responses in Chinese.",
        100,
    );
    crate::knowledge::compiler::refresh_knowledge_pages(&conn, &key).expect("refresh pages");
    crate::db::mark_knowledge_pages_refreshed(&conn, 100).expect("mark pages refreshed");

    insert_generated_document(
        &conn,
        &key,
        "generated:preference:response-style",
        "User prefers short and practical responses.",
        200,
    );
    crate::db::mark_knowledge_pages_refresh_required(&conn).expect("mark pages stale");

    let recent_changes =
        knowledge::db_list_recent_knowledge_page_changes(app_dir_string, key.to_vec(), 8)
            .expect("list recent changes");

    assert!(
        recent_changes.iter().any(|record| {
            record.page_id == "page:preferences"
                && record.change_type == crate::knowledge::KnowledgePageChangeType::Updated
        }),
        "recent changes: {recent_changes:?}"
    );
    assert!(
        !crate::db::knowledge_pages_refresh_required(&conn).expect("load refresh flag"),
        "recent changes API should consume pending page refreshes"
    );
}
