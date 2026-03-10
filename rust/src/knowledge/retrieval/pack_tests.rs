use crate::knowledge::embedding_batch::estimate_tokens;
use crate::knowledge::normalize_retrieval_request;

use super::pack::pack_context_blocks;
use super::recall::recall_knowledge_candidates;
use super::rerank::rerank_knowledge_candidates;
use super::test_support::seeded_fixture;

#[test]
fn knowledge_retrieval_pack_honors_token_budget_and_preserves_anchor_lines() {
    let fixture = seeded_fixture();
    let request = normalize_retrieval_request(
        "freeze-signal budget decision",
        Some(fixture.conversation_id.clone()),
        None,
        Some(4),
        Some(12),
        None,
    );

    let recalled = recall_knowledge_candidates(&fixture.conn, &fixture.key, &request)
        .expect("recall candidates");
    let reranked = rerank_knowledge_candidates(&fixture.conn, &fixture.key, &request, recalled)
        .expect("rerank candidates");
    let blocks = pack_context_blocks(&request, &reranked);

    let total_tokens = blocks
        .iter()
        .map(|block| estimate_tokens(&block.rendered_text))
        .sum::<usize>();
    assert!(total_tokens <= request.token_budget);
    assert!(blocks.iter().any(|block| {
        block.rendered_text.contains("attachment_sha256=")
            || block.rendered_text.contains("message_id=")
    }));
}
