use crate::db;
use crate::rag::knowledge_contexts::collect_compiled_page_contexts;
use rusqlite::params;

fn insert_document(
    conn: &rusqlite::Connection,
    key: &[u8; 32],
    document_id: &str,
    origin_type: &str,
    updated_at_ms: i64,
    conversation_id: Option<&str>,
    text: &str,
) {
    let anchor_json = serde_json::to_string(&crate::knowledge::KnowledgeAnchorSet {
        conversation_id: conversation_id.map(|value| value.to_string()),
        ..crate::knowledge::KnowledgeAnchorSet::default()
    })
    .expect("anchor json");
    let raw =
        db::encode_knowledge_document_text(key, document_id, "raw", text).expect("encode raw");
    let normalized = db::encode_knowledge_document_text(key, document_id, "normalized", text)
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
           ) VALUES (?1, ?2, 'summary', 'summary', NULL, 1.0, NULL, NULL, ?3, ?4, ?5, 1, ?6, ?7, ?8, ?9, ?10, ?11, NULL)"#,
        params![
            document_id,
            origin_type,
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
    .expect("insert document");
}

#[test]
fn collect_compiled_page_contexts_reads_preferences_page() {
    let dir = tempfile::tempdir().expect("tempdir");
    let conn = db::open(dir.path()).expect("open");
    let key = [61u8; 32];
    let conv = db::create_conversation(&conn, &key, "Inbox").expect("conversation");

    for index in 0..64 {
        insert_document(
            &conn,
            &key,
            &format!("message:seed-{index:03}"),
            "message",
            10_000 - index,
            Some(&conv.id),
            "source memory",
        );
    }
    insert_document(
        &conn,
        &key,
        "generated:preference:response-language",
        "generated",
        1,
        Some(&conv.id),
        "User prefers responses in Chinese.",
    );

    let blocks = collect_compiled_page_contexts(&conn, &key, "plan my week", 4, Some(&conv.id))
        .expect("compiled page contexts");

    assert!(blocks
        .iter()
        .any(|block| block.document_id == "page:preferences"));
    assert!(blocks
        .iter()
        .any(|block| block.rendered_text.contains("source=wiki_page")));
}

#[test]
fn collect_compiled_page_contexts_skips_deleted_generated_documents() {
    let dir = tempfile::tempdir().expect("tempdir");
    let conn = db::open(dir.path()).expect("open");
    let key = [64u8; 32];
    let conv = db::create_conversation(&conn, &key, "Inbox").expect("conversation");

    insert_document(
        &conn,
        &key,
        "generated:preference:response-language",
        "generated",
        1,
        Some(&conv.id),
        "User prefers responses in Chinese.",
    );
    crate::db::upsert_knowledge_memory_feedback(
        &conn,
        &key,
        "generated:preference:response-language",
        Some(crate::knowledge::KnowledgeMemoryStatus::Confirmed),
        true,
        true,
        false,
        None,
        None,
    )
    .expect("mark deleted");

    let blocks = collect_compiled_page_contexts(&conn, &key, "plan my week", 4, Some(&conv.id))
        .expect("compiled page contexts");

    assert!(
        blocks
            .iter()
            .all(|block| block.document_id != "page:preferences"),
        "blocks: {blocks:?}"
    );
}

#[test]
fn collect_compiled_page_contexts_matches_keywords_found_only_in_page_body() {
    let dir = tempfile::tempdir().expect("tempdir");
    let conn = db::open(dir.path()).expect("open");
    let key = [94u8; 32];
    let conv = db::create_conversation(&conn, &key, "Inbox").expect("conversation");

    insert_document(
        &conn,
        &key,
        "generated:preference:response-language",
        "generated",
        10,
        Some(&conv.id),
        "User prefers bilingual replies.",
    );
    crate::knowledge::compiler::refresh_knowledge_pages(&conn, &key).expect("refresh pages");
    crate::db::apply_knowledge_page_correction(
        &conn,
        &key,
        "page:preferences",
        None,
        Some("Language guidance stays generic.".to_string()),
        Some("Reply in Mandarin when the user asks for Chinese.".to_string()),
    )
    .expect("correct page");

    let blocks = collect_compiled_page_contexts(&conn, &key, "Mandarin", 4, Some(&conv.id))
        .expect("compiled page contexts");

    assert!(
        blocks
            .iter()
            .any(|block| block.document_id == "page:preferences"),
        "blocks: {blocks:?}"
    );
}
