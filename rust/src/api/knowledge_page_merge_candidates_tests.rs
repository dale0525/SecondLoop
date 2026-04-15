use crate::db;

#[test]
fn list_mergeable_knowledge_page_summaries_allows_slug_equivalent_topic_pages() {
    let dir = tempfile::tempdir().expect("tempdir");
    let app_dir = dir.path().to_path_buf();
    let app_dir_string = app_dir.to_string_lossy().into_owned();
    let conn = db::open(&app_dir).expect("open");
    let key = [41u8; 32];
    let now = 1_710_000_000_000i64;

    db::upsert_compiled_knowledge_pages(
        &conn,
        &key,
        &[
            crate::knowledge::compiler::CompiledKnowledgePageRecord {
                page: {
                    let mut page = crate::knowledge::KnowledgePage::new(
                        "page:topics:launch_plan",
                        crate::knowledge::KnowledgePageType::Topics,
                        "Launch Plan",
                        now,
                    );
                    page.current_summary = "Launch plan summary".to_string();
                    page.current_body = "Launch plan detail".to_string();
                    page.primary_evidence_ids = vec!["doc:launch-plan".to_string()];
                    page.source_count = 1;
                    page
                },
                source_document_ids: vec!["doc:launch-plan".to_string()],
                claim_ids: vec!["claim:launch-plan".to_string()],
            },
            crate::knowledge::compiler::CompiledKnowledgePageRecord {
                page: {
                    let mut page = crate::knowledge::KnowledgePage::new(
                        "page:topics:launch-plan",
                        crate::knowledge::KnowledgePageType::Topics,
                        "Launch Plan",
                        now + 1,
                    );
                    page.current_summary = "Launch plan summary duplicate".to_string();
                    page.current_body = "Launch plan detail duplicate".to_string();
                    page.primary_evidence_ids = vec!["doc:launch-plan-duplicate".to_string()];
                    page.source_count = 1;
                    page
                },
                source_document_ids: vec!["doc:launch-plan-duplicate".to_string()],
                claim_ids: vec!["claim:launch-plan-duplicate".to_string()],
            },
        ],
    )
    .expect("seed pages");
    crate::db::mark_knowledge_pages_refreshed(&conn, now + 2).expect("mark pages refreshed");

    let candidates = crate::api::knowledge::db_list_mergeable_knowledge_page_summaries(
        app_dir_string.clone(),
        key.to_vec(),
        "page:topics:launch_plan".to_string(),
    )
    .expect("list mergeable pages");
    assert_eq!(
        candidates
            .iter()
            .map(|page| page.page_id.as_str())
            .collect::<Vec<_>>(),
        vec!["page:topics:launch-plan"]
    );

    let merged = crate::api::knowledge::db_merge_knowledge_page_into(
        app_dir_string,
        key.to_vec(),
        "page:topics:launch-plan".to_string(),
        "page:topics:launch_plan".to_string(),
        None,
    )
    .expect("merge potential duplicate pages");
    assert_eq!(merged.page.page_id, "page:topics:launch-plan");
    assert_eq!(
        merged.page.state,
        crate::knowledge::KnowledgePageState::Archived
    );
}

#[test]
fn list_mergeable_knowledge_page_summaries_rejects_same_primary_token_people_pages() {
    let dir = tempfile::tempdir().expect("tempdir");
    let app_dir = dir.path().to_path_buf();
    let app_dir_string = app_dir.to_string_lossy().into_owned();
    let conn = db::open(&app_dir).expect("open");
    let key = [42u8; 32];
    let now = 1_710_000_000_000i64;

    db::upsert_compiled_knowledge_pages(
        &conn,
        &key,
        &[
            crate::knowledge::compiler::CompiledKnowledgePageRecord {
                page: {
                    let mut page = crate::knowledge::KnowledgePage::new(
                        "page:people:sam_altman",
                        crate::knowledge::KnowledgePageType::People,
                        "Sam Altman",
                        now,
                    );
                    page.current_summary = "OpenAI leader".to_string();
                    page.current_body = "Person detail".to_string();
                    page.primary_evidence_ids = vec!["doc:sam-altman".to_string()];
                    page.source_count = 1;
                    page
                },
                source_document_ids: vec!["doc:sam-altman".to_string()],
                claim_ids: vec!["claim:sam-altman".to_string()],
            },
            crate::knowledge::compiler::CompiledKnowledgePageRecord {
                page: {
                    let mut page = crate::knowledge::KnowledgePage::new(
                        "page:people:sam_bankman_fried",
                        crate::knowledge::KnowledgePageType::People,
                        "Sam Bankman-Fried",
                        now + 1,
                    );
                    page.current_summary = "Different person".to_string();
                    page.current_body = "Other person detail".to_string();
                    page.primary_evidence_ids = vec!["doc:sam-bankman-fried".to_string()];
                    page.source_count = 1;
                    page
                },
                source_document_ids: vec!["doc:sam-bankman-fried".to_string()],
                claim_ids: vec!["claim:sam-bankman-fried".to_string()],
            },
        ],
    )
    .expect("seed pages");
    crate::db::mark_knowledge_pages_refreshed(&conn, now + 2).expect("mark pages refreshed");

    let candidates = crate::api::knowledge::db_list_mergeable_knowledge_page_summaries(
        app_dir_string,
        key.to_vec(),
        "page:people:sam_altman".to_string(),
    )
    .expect("list mergeable pages");

    assert!(
        candidates.is_empty(),
        "unexpected candidates: {candidates:?}"
    );
}
