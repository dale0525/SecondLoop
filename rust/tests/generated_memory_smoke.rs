use secondloop_rust::crypto::KdfParams;
use secondloop_rust::{auth, db, knowledge};

#[test]
fn generated_memory_smoke_indexes_and_retrieves_stable_documents() {
    let temp_dir = tempfile::tempdir().expect("tempdir");
    let app_dir = temp_dir.path().join("secondloop");

    let key = auth::init_master_password(&app_dir, "pw", KdfParams::for_test()).expect("init");
    let conn = db::open(&app_dir).expect("open db");
    let conversation = db::create_conversation(&conn, &key, "Inbox").expect("conversation");

    db::insert_message(
        &conn,
        &key,
        &conversation.id,
        "user",
        "Please answer in Chinese and keep responses short and practical.",
    )
    .expect("preference");
    db::insert_message(
        &conn,
        &key,
        &conversation.id,
        "user",
        "I'm a developer building a memory optimization prototype for my project.",
    )
    .expect("profile");

    knowledge::ensure_knowledge_rebuild_requested(&conn).expect("request rebuild");
    knowledge::process_pending_knowledge_index_jobs_active(&conn, &key, 256).expect("process jobs");

    let documents = knowledge::list_knowledge_documents(&conn, &key, 128, 0).expect("documents");
    let generated = documents
        .iter()
        .filter(|doc| doc.origin_type == knowledge::KnowledgeOriginType::Generated)
        .collect::<Vec<_>>();

    assert!(!generated.is_empty());
    assert!(generated
        .iter()
        .any(|doc| doc.document_id.starts_with("generated:preference:")));
    assert!(generated
        .iter()
        .any(|doc| doc.document_id.starts_with("generated:profile:")));

    let request = knowledge::normalize_retrieval_request(
        "Chinese practical responses",
        Some(conversation.id.clone()),
        None,
        Some(8),
        Some(400),
        None,
    );
    let results = knowledge::search_knowledge(&conn, &key, &request).expect("search");
    assert!(results
        .iter()
        .any(|result| result.document_id.starts_with("generated:preference:")));
}
