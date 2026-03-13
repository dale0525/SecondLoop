use crate::knowledge::{
    list_knowledge_documents, normalize_retrieval_request, KnowledgeRetrievalLayer, KnowledgeRole,
    KnowledgeUnitKind,
};
use rusqlite::params;

use super::recall::recall_knowledge_candidates;
use super::rerank::rerank_knowledge_candidates;
use super::test_support::seeded_fixture;
use super::{load_document_units, KnowledgeCandidate};

#[test]
fn knowledge_retrieval_rerank_expands_neighbors_and_prefers_evidence_over_metadata() {
    let fixture = seeded_fixture();
    let request = normalize_retrieval_request(
        "freeze-signal budget freeze overview",
        Some(fixture.conversation_id.clone()),
        None,
        None,
        Some(8),
        None,
    );

    let recalled = recall_knowledge_candidates(&fixture.conn, &fixture.key, &request)
        .expect("recall candidates");
    let reranked = rerank_knowledge_candidates(&fixture.conn, &fixture.key, &request, recalled)
        .expect("rerank candidates");

    assert_ne!(
        reranked.first().map(|candidate| candidate.role),
        Some(KnowledgeRole::Metadata)
    );

    let target_chunk = reranked
        .iter()
        .find(|candidate| {
            candidate.unit_kind == Some(KnowledgeUnitKind::Chunk)
                && candidate.normalized_text.contains("freeze-signal")
        })
        .expect("target chunk");

    let neighbor_ids = [
        target_chunk.prev_unit_id.clone(),
        target_chunk.next_unit_id.clone(),
    ]
    .into_iter()
    .flatten()
    .collect::<Vec<_>>();

    assert!(neighbor_ids.iter().any(|neighbor_id| reranked
        .iter()
        .any(|candidate| candidate.unit_id.as_deref() == Some(neighbor_id.as_str()))));
}

#[test]
fn knowledge_retrieval_rerank_injects_parent_section_for_chunk_seed() {
    let dir = tempfile::tempdir().expect("tempdir");
    let conn = crate::db::open(dir.path()).expect("open");
    let key = [61u8; 32];

    let document_id = "synthetic:rerank-parent-section";
    let anchor_json = serde_json::json!({}).to_string();
    let raw =
        crate::db::encode_knowledge_document_text(&key, document_id, "raw", "synthetic doc text")
            .expect("encode raw");
    let normalized = crate::db::encode_knowledge_document_text(
        &key,
        document_id,
        "normalized",
        "synthetic doc text",
    )
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
           ) VALUES (?1, 'generated', 'raw_text', 'body', NULL, 1.0, NULL, NULL, ?2, ?3, ?4, 1, 1, ?5, ?6, ?7, ?8, ?9, NULL)"#,
        params![
            document_id,
            anchor_json,
            raw,
            normalized,
            crate::knowledge::KNOWLEDGE_SCHEMA_VERSION,
            crate::knowledge::KNOWLEDGE_NORMALIZATION_VERSION,
            crate::knowledge::KNOWLEDGE_SEGMENTATION_VERSION,
            crate::knowledge::KNOWLEDGE_EMBEDDING_POLICY_VERSION,
            crate::knowledge::KNOWLEDGE_RETRIEVAL_POLICY_VERSION,
        ],
    )
    .expect("insert knowledge document");

    let parent_section_id = "section-parent";
    let sibling_section_id = "section-sibling";
    let chunk_id = "chunk-1";

    let insert_unit = |unit_id: &str,
                       parent_unit_id: Option<&str>,
                       unit_kind: &str,
                       ordinal: i64,
                       text: &str| {
        let raw = crate::db::encode_knowledge_unit_text(&key, unit_id, "raw", text)
            .expect("encode unit raw");
        let normalized = crate::db::encode_knowledge_unit_text(&key, unit_id, "normalized", text)
            .expect("encode unit normalized");
        conn.execute(
            r#"INSERT INTO knowledge_units(
                   unit_id,
                   document_id,
                   parent_unit_id,
                   unit_kind,
                   source_kind,
                   role,
                   ordinal,
                   token_count,
                   anchor_json,
                   raw_text,
                   normalized_text,
                   prev_unit_id,
                   next_unit_id,
                   created_at_ms,
                   updated_at_ms
               ) VALUES (?1, ?2, ?3, ?4, 'raw_text', 'body', ?5, ?6, ?7, ?8, ?9, NULL, NULL, 1, 1)"#,
            params![
                unit_id,
                document_id,
                parent_unit_id,
                unit_kind,
                ordinal,
                text.split_whitespace().count() as i64,
                serde_json::json!({}).to_string(),
                raw,
                normalized
            ],
        )
        .expect("insert knowledge unit");
    };

    // Parent section is far away ordinal-wise, but is the explicit parent.
    insert_unit(
        parent_section_id,
        None,
        "section",
        1010,
        "parent section text",
    );
    // Sibling section shares chunk ordinal, making ordinal-based selection wrong.
    insert_unit(
        sibling_section_id,
        None,
        "section",
        10,
        "sibling section text",
    );
    insert_unit(chunk_id, Some(parent_section_id), "chunk", 10, "chunk text");

    let document = list_knowledge_documents(&conn, &key, 16, 0)
        .expect("documents")
        .into_iter()
        .find(|doc| doc.document_id == document_id)
        .expect("target document");

    let chunk = load_document_units(&conn, &key, document_id, KnowledgeUnitKind::Chunk)
        .expect("load chunks")
        .into_iter()
        .find(|unit| unit.unit_id == chunk_id)
        .expect("target chunk");

    let seed =
        KnowledgeCandidate::from_unit(&document, &chunk, KnowledgeRetrievalLayer::Chunk, 1.0, 1.0);

    let request = normalize_retrieval_request("chunk text", None, None, None, Some(8), None);
    let reranked =
        rerank_knowledge_candidates(&conn, &key, &request, vec![seed]).expect("rerank candidates");

    assert!(
        reranked.iter().any(|candidate| {
            candidate.unit_kind == Some(KnowledgeUnitKind::Section)
                && candidate.unit_id.as_deref() == Some(parent_section_id)
        }),
        "expected parent section {parent_section_id} to be injected"
    );
}

#[test]
fn knowledge_hotness_score_prefers_recent_frequent_usage() {
    let now_ms = 1_800_000_000_000i64;
    let cold =
        crate::knowledge::usage::hotness_score(0, Some(now_ms - 45 * 24 * 60 * 60 * 1000), now_ms);
    let hot = crate::knowledge::usage::hotness_score(12, Some(now_ms - 2 * 60 * 60 * 1000), now_ms);
    assert!(
        hot > cold,
        "expected hot score {hot} to exceed cold score {cold}"
    );
}

#[test]
fn knowledge_retrieval_rerank_prefers_hot_recent_candidate_when_semantic_gap_is_small() {
    let dir = tempfile::tempdir().expect("tempdir");
    let conn = crate::db::open(dir.path()).expect("open");
    let key = [62u8; 32];

    let insert_doc = |document_id: &str, text: &str| {
        let anchor_json = serde_json::json!({}).to_string();
        let raw = crate::db::encode_knowledge_document_text(&key, document_id, "raw", text)
            .expect("encode raw");
        let normalized =
            crate::db::encode_knowledge_document_text(&key, document_id, "normalized", text)
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
               ) VALUES (?1, 'generated', 'raw_text', 'body', NULL, 1.0, NULL, NULL, ?2, ?3, ?4, 1, 1, ?5, ?6, ?7, ?8, ?9, NULL)"#,
            params![
                document_id,
                anchor_json,
                raw,
                normalized,
                crate::knowledge::KNOWLEDGE_SCHEMA_VERSION,
                crate::knowledge::KNOWLEDGE_NORMALIZATION_VERSION,
                crate::knowledge::KNOWLEDGE_SEGMENTATION_VERSION,
                crate::knowledge::KNOWLEDGE_EMBEDDING_POLICY_VERSION,
                crate::knowledge::KNOWLEDGE_RETRIEVAL_POLICY_VERSION,
            ],
        )
        .expect("insert knowledge document");
    };

    insert_doc("doc:cold", "orchard planning notes with budget checkpoints");
    insert_doc("doc:hot", "orchard planning notes with budget checkpoints");

    let now_ms = crate::knowledge::usage::now_ms();
    conn.execute(
        r#"INSERT INTO knowledge_document_usage(document_id, retrieve_count, last_retrieved_at_ms)
           VALUES (?1, ?2, ?3)"#,
        params!["doc:hot", 12i64, now_ms - 2 * 60 * 60 * 1000],
    )
    .expect("insert usage hot");
    conn.execute(
        r#"INSERT INTO knowledge_document_usage(document_id, retrieve_count, last_retrieved_at_ms)
           VALUES (?1, ?2, ?3)"#,
        params!["doc:cold", 0i64, now_ms - 45 * 24 * 60 * 60 * 1000],
    )
    .expect("insert usage cold");

    let docs = list_knowledge_documents(&conn, &key, 16, 0).expect("documents");
    let cold_doc = docs
        .iter()
        .find(|doc| doc.document_id == "doc:cold")
        .expect("cold doc");
    let hot_doc = docs
        .iter()
        .find(|doc| doc.document_id == "doc:hot")
        .expect("hot doc");

    let request = normalize_retrieval_request(
        "orchard budget checkpoints",
        None,
        None,
        Some(4),
        Some(64),
        None,
    );
    let cold = KnowledgeCandidate::from_document(cold_doc, 0.78, 0.10);
    let hot = KnowledgeCandidate::from_document(hot_doc, 0.74, 0.10);
    let reranked = rerank_knowledge_candidates(&conn, &key, &request, vec![cold, hot])
        .expect("rerank candidates");

    assert_eq!(
        reranked
            .first()
            .map(|candidate| candidate.document.document_id.as_str()),
        Some("doc:hot")
    );
}
