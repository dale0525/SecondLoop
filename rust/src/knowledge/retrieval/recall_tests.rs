use crate::knowledge::{normalize_retrieval_request, KnowledgeRetrievalLayer};

use super::recall::recall_knowledge_candidates;
use super::test_support::seeded_fixture;

#[test]
fn knowledge_retrieval_recall_returns_document_section_and_chunk_layers() {
    let fixture = seeded_fixture();
    let request = normalize_retrieval_request(
        "freeze-signal budget decision",
        Some(fixture.conversation_id.clone()),
        None,
        None,
        Some(8),
        None,
    );

    let candidates = recall_knowledge_candidates(&fixture.conn, &fixture.key, &request)
        .expect("recall candidates");

    assert!(candidates
        .iter()
        .any(|candidate| candidate.layer == KnowledgeRetrievalLayer::Document));
    assert!(candidates
        .iter()
        .any(|candidate| candidate.layer == KnowledgeRetrievalLayer::Section));
    assert!(candidates
        .iter()
        .any(|candidate| candidate.layer == KnowledgeRetrievalLayer::Chunk));
}

#[test]
fn knowledge_retrieval_recall_lexical_candidates_survive_missing_embeddings() {
    let fixture = seeded_fixture();
    fixture
        .conn
        .execute(
            "DELETE FROM knowledge_embeddings WHERE target_id = ?1",
            rusqlite::params![fixture.metadata_document_id.clone()],
        )
        .expect("delete metadata embedding");

    let request = normalize_retrieval_request("roadmap-q1", None, None, None, Some(8), None);
    let candidates = recall_knowledge_candidates(&fixture.conn, &fixture.key, &request)
        .expect("recall candidates");

    assert!(candidates.iter().any(|candidate| {
        candidate.document.document_id == fixture.metadata_document_id
            && candidate.lexical_score > 0.0
    }));
}
