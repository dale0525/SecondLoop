use crate::knowledge::{
    normalize_retrieval_request, search_knowledge, KnowledgeRole, KnowledgeSourceKind,
};

use super::test_support::seeded_fixture;

#[test]
fn knowledge_eval_long_transcript_fact_lookup_returns_transcript_evidence() {
    let fixture = seeded_fixture();
    let request = normalize_retrieval_request(
        "freeze-signal budget decision",
        Some(fixture.conversation_id.clone()),
        None,
        Some(6),
        Some(24),
        None,
    );

    let hits = search_knowledge(&fixture.conn, &fixture.key, &request).expect("search hits");

    assert!(hits.iter().take(3).any(|hit| {
        hit.document_id == fixture.transcript_document_id
            && hit.source_kind == KnowledgeSourceKind::Transcript
            && hit.snippet.contains("freeze-signal")
    }));
}

#[test]
fn knowledge_eval_mixed_source_recall_returns_multiple_knowledge_kinds() {
    let fixture = seeded_fixture();
    let request = normalize_retrieval_request(
        "roadmap-q1 freeze-signal orchard invoice",
        Some(fixture.conversation_id.clone()),
        None,
        Some(10),
        Some(36),
        None,
    );

    let hits = search_knowledge(&fixture.conn, &fixture.key, &request).expect("search hits");

    let mut unique_source_kinds = Vec::<KnowledgeSourceKind>::new();
    for hit in &hits {
        if !unique_source_kinds.contains(&hit.source_kind) {
            unique_source_kinds.push(hit.source_kind);
        }
    }

    assert!(hits.iter().any(|hit| {
        hit.source_kind == KnowledgeSourceKind::Transcript
            || hit.source_kind == KnowledgeSourceKind::OcrText
            || hit.source_kind == KnowledgeSourceKind::ReadableText
    }));
    assert!(unique_source_kinds.len() >= 2);
}

#[test]
fn knowledge_eval_metadata_does_not_dominate_direct_evidence() {
    let fixture = seeded_fixture();
    let request = normalize_retrieval_request(
        "freeze-signal budget freeze overview",
        Some(fixture.conversation_id.clone()),
        None,
        Some(8),
        Some(24),
        None,
    );

    let hits = search_knowledge(&fixture.conn, &fixture.key, &request).expect("search hits");

    assert_ne!(
        hits.first().map(|hit| hit.role),
        Some(KnowledgeRole::Metadata)
    );
}

#[test]
fn knowledge_eval_transcript_anchor_accuracy_preserves_section_labels() {
    let fixture = seeded_fixture();
    let request = normalize_retrieval_request(
        "freeze-signal budget decision",
        Some(fixture.conversation_id.clone()),
        None,
        Some(6),
        Some(24),
        None,
    );

    let hits = search_knowledge(&fixture.conn, &fixture.key, &request).expect("search hits");
    let transcript_hit = hits
        .iter()
        .find(|hit| hit.document_id == fixture.transcript_document_id)
        .expect("transcript hit");

    assert_eq!(
        transcript_hit.anchors.section_label.as_deref(),
        Some("Speaker Charlie")
    );
    assert!(transcript_hit.anchors.attachment_sha256.is_some());
}
