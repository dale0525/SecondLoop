use crate::knowledge::{normalize_retrieval_request, KnowledgeRole, KnowledgeUnitKind};

use super::recall::recall_knowledge_candidates;
use super::rerank::rerank_knowledge_candidates;
use super::test_support::seeded_fixture;

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
