use crate::api::knowledge;
use crate::db;

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
