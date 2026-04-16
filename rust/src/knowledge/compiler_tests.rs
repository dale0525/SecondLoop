use crate::{db, knowledge};
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
fn refresh_knowledge_pages_compiles_preferences_page_from_generated_documents() {
    let dir = tempfile::tempdir().expect("tempdir");
    let conn = db::open(dir.path()).expect("open");
    let key = [41u8; 32];

    let conv = db::create_conversation(&conn, &key, "Inbox").expect("conversation");
    db::insert_message(
        &conn,
        &key,
        &conv.id,
        "user",
        "Please answer in Chinese and keep responses short and practical.",
    )
    .expect("seed preference");

    knowledge::ensure_knowledge_rebuild_requested(&conn).expect("request rebuild");
    knowledge::process_pending_knowledge_index_jobs_active(&conn, &key, 256).expect("process jobs");

    let pages =
        knowledge::compiler::refresh_knowledge_pages(&conn, &key).expect("refresh knowledge pages");
    let preferences = pages
        .iter()
        .find(|page| page.page_type == knowledge::KnowledgePageType::Preferences)
        .expect("preferences page");

    assert_eq!(preferences.page_id, "page:preferences");
    assert_eq!(preferences.title, "Preferences");
    assert!(preferences.current_body.contains("Chinese"));
    assert!(preferences.current_body.contains("practical"));
    assert!(preferences.source_count >= 1);
    assert!(preferences
        .primary_evidence_ids
        .iter()
        .any(|document_id| document_id == "generated:preference:response-language"));
}

#[test]
fn refresh_knowledge_pages_excludes_muted_generated_documents_from_compiled_pages() {
    let dir = tempfile::tempdir().expect("tempdir");
    let conn = db::open(dir.path()).expect("open");
    let key = [95u8; 32];

    insert_generated_document(
        &conn,
        &key,
        "generated:preference:response-language",
        "User prefers responses in Chinese.",
        1_000,
    );
    db::upsert_knowledge_memory_feedback(
        &conn,
        &key,
        "generated:preference:response-language",
        Some(crate::knowledge::KnowledgeMemoryStatus::Confirmed),
        false,
        false,
        false,
        None,
        None,
    )
    .expect("mute generated memory");

    let pages =
        knowledge::compiler::refresh_knowledge_pages(&conn, &key).expect("refresh knowledge pages");

    assert!(
        pages.iter().all(|page| page.page_id != "page:preferences"),
        "pages: {pages:?}"
    );
}

#[test]
fn refresh_knowledge_pages_rolls_back_claim_updates_when_page_refresh_fails() {
    let dir = tempfile::tempdir().expect("tempdir");
    let conn = db::open(dir.path()).expect("open");
    let key = [97u8; 32];

    insert_generated_document(
        &conn,
        &key,
        "generated:preference:response-language",
        "User prefers responses in Chinese.",
        1_000,
    );

    knowledge::compiler::refresh_knowledge_pages(&conn, &key).expect("initial refresh");

    let initial_claim_count: i64 = conn
        .query_row("SELECT COUNT(*) FROM knowledge_claims", [], |row| {
            row.get(0)
        })
        .expect("initial claim count");
    assert_eq!(initial_claim_count, 1);

    insert_generated_document(
        &conn,
        &key,
        "generated:preference:response-style",
        "User prefers concise responses.",
        2_000,
    );
    conn.execute_batch(
        r#"CREATE TRIGGER abort_preferences_page_refresh
           BEFORE UPDATE ON knowledge_pages
           WHEN NEW.page_id = 'page:preferences'
           BEGIN
             SELECT RAISE(ABORT, 'stop page refresh');
           END;"#,
    )
    .expect("create page refresh abort trigger");

    let error = knowledge::compiler::refresh_knowledge_pages(&conn, &key)
        .expect_err("refresh should abort when page refresh fails");
    assert!(error.to_string().contains("stop page refresh"));

    let claim_count_after_failure: i64 = conn
        .query_row("SELECT COUNT(*) FROM knowledge_claims", [], |row| {
            row.get(0)
        })
        .expect("claim count after failure");
    assert_eq!(claim_count_after_failure, 1);

    let page_count_after_failure: i64 = conn
        .query_row("SELECT COUNT(*) FROM knowledge_pages", [], |row| row.get(0))
        .expect("page count after failure");
    assert_eq!(page_count_after_failure, 1);
}

#[test]
fn refresh_knowledge_pages_paginates_generated_documents_past_first_512() {
    let dir = tempfile::tempdir().expect("tempdir");
    let conn = db::open(dir.path()).expect("open");
    let key = [42u8; 32];

    for index in 0..513 {
        insert_generated_document(
            &conn,
            &key,
            &format!("generated:pattern:topic-{index:03}"),
            &format!("Topic signal {index:03}"),
            10_000 - index as i64,
        );
    }

    let pages =
        knowledge::compiler::refresh_knowledge_pages(&conn, &key).expect("refresh knowledge pages");
    let topics = pages
        .iter()
        .filter(|page| page.page_type == knowledge::KnowledgePageType::Topics)
        .collect::<Vec<_>>();

    assert_eq!(topics.len(), 513);
    assert!(topics
        .iter()
        .any(|page| page.page_id == "page:topics:topic_000"));
    assert!(topics
        .iter()
        .any(|page| page.page_id == "page:topics:topic_512"));
    assert!(topics
        .iter()
        .any(|page| page.current_body.contains("Topic signal 000")));
    assert!(topics
        .iter()
        .any(|page| page.current_body.contains("Topic signal 512")));
}

#[test]
fn refresh_knowledge_pages_compiles_unknown_generated_documents_into_topic_pages() {
    let dir = tempfile::tempdir().expect("tempdir");
    let conn = db::open(dir.path()).expect("open");
    let key = [142u8; 32];

    insert_generated_document(
        &conn,
        &key,
        "generated:misc:travel-rhythm",
        "User is alternating between Beijing and Shanghai this month.",
        7_654,
    );

    let pages =
        knowledge::compiler::refresh_knowledge_pages(&conn, &key).expect("refresh knowledge pages");
    let topic_page = pages
        .iter()
        .find(|page| page.page_id == "page:topics:travel_rhythm")
        .expect("topic page for unknown generated document");

    assert_eq!(topic_page.page_type, knowledge::KnowledgePageType::Topics);
    assert!(topic_page.current_body.contains("Beijing"));
    assert!(topic_page
        .primary_evidence_ids
        .iter()
        .any(|document_id| document_id == "generated:misc:travel-rhythm"));
    assert_eq!(
        knowledge::compiler::primary_page_ids_for_generated_document(
            "generated:misc:travel-rhythm"
        ),
        vec!["page:topics:travel_rhythm".to_string()]
    );
}

#[test]
fn refresh_knowledge_pages_compiles_active_threads_page_from_active_task_pattern() {
    let dir = tempfile::tempdir().expect("tempdir");
    let conn = db::open(dir.path()).expect("open");
    let key = [43u8; 32];

    insert_generated_document(
        &conn,
        &key,
        "generated:pattern:active-task-focus",
        "User is actively working across these task threads: Draft roadmap [in_progress]. Review launch notes [open].",
        12_345,
    );

    let pages =
        knowledge::compiler::refresh_knowledge_pages(&conn, &key).expect("refresh knowledge pages");

    let current_focus = pages
        .iter()
        .find(|page| page.page_type == knowledge::KnowledgePageType::CurrentFocus)
        .expect("current focus page");
    let active_threads = pages
        .iter()
        .find(|page| page.page_type == knowledge::KnowledgePageType::ActiveThreads)
        .expect("active threads page");

    assert_eq!(current_focus.page_id, "page:current-focus");
    assert_eq!(active_threads.page_id, "page:active-threads");
    assert!(active_threads.current_body.contains("Draft roadmap"));
    assert!(active_threads.current_body.contains("Review launch notes"));
}

#[test]
fn refresh_knowledge_pages_persists_thread_claims_for_active_threads_page() {
    let dir = tempfile::tempdir().expect("tempdir");
    let conn = db::open(dir.path()).expect("open");
    let key = [44u8; 32];

    insert_generated_document(
        &conn,
        &key,
        "generated:pattern:active-task-focus",
        "User is actively working across these task threads: Draft roadmap [in_progress]. Review launch notes [open].",
        23_456,
    );

    knowledge::compiler::refresh_knowledge_pages(&conn, &key).expect("refresh knowledge pages");

    let active_threads = db::get_knowledge_page_detail(&conn, &key, "page:active-threads")
        .expect("load active threads detail")
        .expect("active threads detail");
    assert!(
        active_threads
            .claim_ids
            .iter()
            .any(|claim_id| claim_id.starts_with("claim:thread:")),
        "claim ids: {:?}",
        active_threads.claim_ids
    );

    let thread_claim_count: i64 = conn
        .query_row(
            r#"SELECT COUNT(*)
               FROM knowledge_claims
               WHERE claim_type = 'thread'"#,
            [],
            |row| row.get(0),
        )
        .expect("thread claim count");
    assert_eq!(thread_claim_count, 1);
}

#[test]
fn refresh_knowledge_pages_compiles_people_pages_from_relationship_memories() {
    let dir = tempfile::tempdir().expect("tempdir");
    let conn = db::open(dir.path()).expect("open");
    let key = [47u8; 32];

    let conv = db::create_conversation(&conn, &key, "People").expect("conversation");
    db::insert_message(
        &conn,
        &key,
        &conv.id,
        "user",
        "Alice Chen is my manager and approves budget requests.",
    )
    .expect("seed relationship");

    knowledge::ensure_knowledge_rebuild_requested(&conn).expect("request rebuild");
    knowledge::process_pending_knowledge_index_jobs_active(&conn, &key, 256).expect("process jobs");

    let pages =
        knowledge::compiler::refresh_knowledge_pages(&conn, &key).expect("refresh knowledge pages");

    let people_page = pages
        .iter()
        .find(|page| page.page_id == "page:people:alice_chen")
        .expect("people page");
    assert_eq!(people_page.page_type, knowledge::KnowledgePageType::People);
    assert_eq!(people_page.title, "Alice Chen");
    assert!(people_page.current_body.contains("manager"));
}

#[test]
fn refresh_knowledge_pages_compiles_people_pages_from_relation_first_sentence() {
    let dir = tempfile::tempdir().expect("tempdir");
    let conn = db::open(dir.path()).expect("open");
    let key = [48u8; 32];

    let conv = db::create_conversation(&conn, &key, "People").expect("conversation");
    db::insert_message(
        &conn,
        &key,
        &conv.id,
        "user",
        "My manager is Alice Chen and she approves budget requests.",
    )
    .expect("seed relation-first relationship");

    knowledge::ensure_knowledge_rebuild_requested(&conn).expect("request rebuild");
    knowledge::process_pending_knowledge_index_jobs_active(&conn, &key, 256).expect("process jobs");

    let pages =
        knowledge::compiler::refresh_knowledge_pages(&conn, &key).expect("refresh knowledge pages");

    let people_page = pages
        .iter()
        .find(|page| page.page_id == "page:people:alice_chen")
        .expect("people page");
    assert_eq!(people_page.page_type, knowledge::KnowledgePageType::People);
    assert_eq!(people_page.title, "Alice Chen");
    assert!(people_page.current_body.contains("Alice Chen"));
}

#[test]
fn refresh_knowledge_pages_compiles_people_pages_for_accented_relationship_names() {
    let dir = tempfile::tempdir().expect("tempdir");
    let conn = db::open(dir.path()).expect("open");
    let key = [49u8; 32];

    let conv = db::create_conversation(&conn, &key, "People").expect("conversation");
    db::insert_message(
        &conn,
        &key,
        &conv.id,
        "user",
        "Élodie Durand is my manager and approves budget requests.",
    )
    .expect("seed accented relationship");

    knowledge::ensure_knowledge_rebuild_requested(&conn).expect("request rebuild");
    knowledge::process_pending_knowledge_index_jobs_active(&conn, &key, 256).expect("process jobs");

    let pages =
        knowledge::compiler::refresh_knowledge_pages(&conn, &key).expect("refresh knowledge pages");

    let people_page = pages
        .iter()
        .find(|page| page.page_id == "page:people:élodie_durand")
        .expect("people page");
    assert_eq!(people_page.page_type, knowledge::KnowledgePageType::People);
    assert_eq!(people_page.title, "Élodie Durand");
    assert!(people_page
        .current_body
        .contains("approves budget requests"));
}

#[test]
fn refresh_knowledge_pages_compiles_people_pages_from_cjk_relationship_memories() {
    let dir = tempfile::tempdir().expect("tempdir");
    let conn = db::open(dir.path()).expect("open");
    let key = [50u8; 32];

    let conv = db::create_conversation(&conn, &key, "People").expect("conversation");
    db::insert_message(
        &conn,
        &key,
        &conv.id,
        "user",
        "张伟是我的经理，负责预算审批。",
    )
    .expect("seed cjk relationship");

    knowledge::ensure_knowledge_rebuild_requested(&conn).expect("request rebuild");
    knowledge::process_pending_knowledge_index_jobs_active(&conn, &key, 256).expect("process jobs");

    let pages =
        knowledge::compiler::refresh_knowledge_pages(&conn, &key).expect("refresh knowledge pages");

    let people_page = pages
        .iter()
        .find(|page| page.page_id == "page:people:张伟")
        .expect("people page");
    assert_eq!(people_page.page_type, knowledge::KnowledgePageType::People);
    assert_eq!(people_page.title, "张伟");
    assert!(people_page.current_body.contains("经理"));
}

#[test]
fn refresh_knowledge_pages_compiles_disputed_claims_into_open_questions_pages() {
    let dir = tempfile::tempdir().expect("tempdir");
    let conn = db::open(dir.path()).expect("open");
    let key = [45u8; 32];

    insert_generated_document(
        &conn,
        &key,
        "generated:preference:response-language",
        "User prefers responses in Chinese.",
        34_567,
    );
    db::upsert_knowledge_memory_feedback(
        &conn,
        &key,
        "generated:preference:response-language",
        Some(knowledge::KnowledgeMemoryStatus::Confirmed),
        false,
        false,
        true,
        None,
        None,
    )
    .expect("mark disputed");

    let pages =
        knowledge::compiler::refresh_knowledge_pages(&conn, &key).expect("refresh knowledge pages");

    let open_question = pages
        .iter()
        .find(|page| page.page_id == "page:open-questions:preference:response_language")
        .expect("open question page");
    assert_eq!(
        open_question.page_type,
        knowledge::KnowledgePageType::OpenQuestions
    );
    assert!(open_question.current_summary.contains("Chinese"));
    assert!(open_question.current_body.contains("Chinese"));
    assert!(!open_question.answer_policy.default_allowed);
    assert!(
        pages.iter().all(|page| page.page_id != "page:preferences"),
        "compiled pages should not keep disputed content in the main preferences page: {pages:?}"
    );
}

#[test]
fn refresh_knowledge_pages_ignores_dismissed_claims_when_counting_conflicts() {
    let dir = tempfile::tempdir().expect("tempdir");
    let conn = db::open(dir.path()).expect("open");
    let key = [46u8; 32];

    insert_generated_document(
        &conn,
        &key,
        "generated:preference:response-language",
        "User prefers responses in Chinese.",
        34_568,
    );
    insert_generated_document(
        &conn,
        &key,
        "generated:preference:alternate:response-language",
        "User prefers responses in English.",
        34_569,
    );
    db::upsert_knowledge_memory_feedback(
        &conn,
        &key,
        "generated:preference:alternate:response-language",
        Some(knowledge::KnowledgeMemoryStatus::Confirmed),
        true,
        true,
        false,
        None,
        None,
    )
    .expect("dismiss alternate preference");

    let pages =
        knowledge::compiler::refresh_knowledge_pages(&conn, &key).expect("refresh knowledge pages");
    let preferences = pages
        .iter()
        .find(|page| page.page_id == "page:preferences")
        .expect("preferences page");

    assert_eq!(preferences.conflict_count, 0);
}

#[test]
fn refresh_knowledge_pages_confidence_only_uses_sources_in_current_page_content() {
    let dir = tempfile::tempdir().expect("tempdir");
    let conn = db::open(dir.path()).expect("open");
    let key = [49u8; 32];
    let anchor_json = serde_json::to_string(&crate::knowledge::KnowledgeAnchorSet::default())
        .expect("anchor json");

    for (document_id, summary, quality_score, updated_at_ms) in [
        (
            "generated:preference:response-language",
            "User prefers responses in Chinese.",
            0.8_f64,
            11_i64,
        ),
        (
            "generated:preference:response-style",
            "User prefers responses in English.",
            0.2_f64,
            12_i64,
        ),
    ] {
        let raw = db::encode_knowledge_document_text(&key, document_id, "raw", summary)
            .expect("encode raw");
        let normalized =
            db::encode_knowledge_document_text(&key, document_id, "normalized", summary)
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
               ) VALUES (?1, 'generated', 'summary', 'summary', NULL, ?2, NULL, ?3, ?4, ?5, ?6, 1, ?7, ?8, ?9, ?10, ?11, ?12, NULL)"#,
            params![
                document_id,
                quality_score,
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
    db::upsert_knowledge_memory_feedback(
        &conn,
        &key,
        "generated:preference:response-style",
        Some(knowledge::KnowledgeMemoryStatus::Confirmed),
        false,
        false,
        true,
        None,
        None,
    )
    .expect("mark disputed");

    let pages =
        knowledge::compiler::refresh_knowledge_pages(&conn, &key).expect("refresh knowledge pages");
    let preferences = pages
        .iter()
        .find(|page| page.page_id == "page:preferences")
        .expect("preferences page");

    assert_eq!(
        preferences.current_summary,
        "User prefers responses in Chinese."
    );
    assert!((preferences.confidence_level - 0.8).abs() < f64::EPSILON);
}
