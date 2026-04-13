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
        .find(|page| page.page_type == knowledge::KnowledgePageType::Topics)
        .expect("topics page");

    assert_eq!(topics.page_id, "page:topics");
    assert_eq!(topics.source_count, 513);
    assert!(topics.current_body.contains("Topic signal 000"));
    assert!(topics.current_body.contains("Topic signal 512"));
}
