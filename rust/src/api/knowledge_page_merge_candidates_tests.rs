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
fn merge_knowledge_page_into_allows_potential_duplicate_topic_pages() {
    let dir = tempfile::tempdir().expect("tempdir");
    let app_dir = dir.path().to_path_buf();
    let app_dir_string = app_dir.to_string_lossy().into_owned();
    let conn = db::open(&app_dir).expect("open");
    let key = [41u8; 32];
    let now = 1_710_000_000_000i64;

    insert_generated_document(
        &conn,
        &key,
        "generated:misc:launch-plan",
        "Launch plan summary",
        now,
    );
    insert_generated_document(
        &conn,
        &key,
        "generated:misc:launch-strategy",
        "Launch strategy summary",
        now + 1,
    );
    crate::knowledge::compiler::refresh_knowledge_pages(&conn, &key).expect("refresh pages");
    crate::db::mark_knowledge_pages_refreshed(&conn, now + 2).expect("mark pages refreshed");

    let candidates = crate::api::knowledge::db_list_mergeable_knowledge_page_summaries(
        app_dir_string.clone(),
        key.to_vec(),
        "page:topics:launch_strategy".to_string(),
    )
    .expect("list mergeable pages");
    assert_eq!(
        candidates
            .iter()
            .map(|page| page.page_id.as_str())
            .collect::<Vec<_>>(),
        vec!["page:topics:launch_plan"]
    );

    let merged = crate::api::knowledge::db_merge_knowledge_page_into(
        app_dir_string,
        key.to_vec(),
        "page:topics:launch_strategy".to_string(),
        "page:topics:launch_plan".to_string(),
        None,
    )
    .expect("merge potential duplicate pages");
    assert_eq!(merged.page.page_id, "page:topics:launch_strategy");
    assert_eq!(
        merged.page.state,
        crate::knowledge::KnowledgePageState::Archived
    );
}
