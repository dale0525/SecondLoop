use crate::{db, knowledge};

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
