use crate::db;
use crate::knowledge;
use crate::rag::knowledge_contexts::try_build_knowledge_context_entries;
use crate::rag::Focus;
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
fn try_build_knowledge_contexts_for_this_thread_keeps_stable_pages_but_not_dynamic_compiled_pages()
{
    let dir = tempfile::tempdir().expect("tempdir");
    let conn = db::open(dir.path()).expect("open");
    let key = [95u8; 32];
    let planning_conv =
        db::create_conversation(&conn, &key, "Planning").expect("planning conversation");
    let other_conv = db::create_conversation(&conn, &key, "Other").expect("other conversation");

    insert_document(
        &conn,
        &key,
        "generated:preference:response-language",
        "generated",
        1,
        Some(&other_conv.id),
        "User prefers responses in Chinese.",
    );
    insert_document(
        &conn,
        &key,
        "generated:pattern:active-task-focus",
        "generated",
        2,
        Some(&planning_conv.id),
        "Current thread planning signal.",
    );
    insert_document(
        &conn,
        &key,
        "generated:pattern:active-task-focus-other",
        "generated",
        3,
        Some(&other_conv.id),
        "Other thread planning signal.",
    );

    knowledge::compiler::refresh_knowledge_pages(&conn, &key).expect("refresh pages");

    let entries = try_build_knowledge_context_entries(
        &conn,
        &key,
        "Plan my week in Chinese.",
        6,
        Focus::ThisThread,
        &planning_conv.id,
        None,
    )
    .expect("knowledge context entries");

    assert!(
        entries
            .iter()
            .any(|entry| entry.block.document_id == "page:preferences"),
        "entries: {entries:?}"
    );
    assert!(
        entries.iter().all(|entry| {
            entry.block.document_id != "page:current-focus"
                && entry.block.document_id != "page:active-threads"
        }),
        "entries: {entries:?}"
    );
    assert!(
        entries
            .iter()
            .any(|entry| entry.block.document_id == "generated:pattern:active-task-focus"),
        "entries: {entries:?}"
    );
    assert!(
        entries.iter().all(|entry| !entry
            .rendered_text
            .contains("Other thread planning signal.")),
        "entries: {entries:?}"
    );
}
