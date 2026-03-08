use crate::knowledge::{
    build_chunk_units, segment_document_text, ContentKnowledgeDocument, KnowledgeAnchorSet,
    KnowledgeOriginType, KnowledgeRole, KnowledgeSourceKind, KnowledgeVersionSet,
};

#[test]
fn knowledge_chunking_respects_token_budget_and_links_neighbors() {
    let doc = ContentKnowledgeDocument {
        document_id: "doc-1".to_string(),
        origin_type: KnowledgeOriginType::Attachment,
        source_kind: KnowledgeSourceKind::Transcript,
        role: KnowledgeRole::Evidence,
        language: Some("en".to_string()),
        quality_score: 1.0,
        created_at_ms: 1,
        updated_at_ms: 1,
        versions: KnowledgeVersionSet::current(),
        anchors: KnowledgeAnchorSet::default(),
        title: None,
        summary: None,
        raw_text: "Speaker A: one two three four five six.\n\nSpeaker B: seven eight nine ten eleven twelve.\n\nSpeaker A: thirteen fourteen fifteen sixteen seventeen eighteen.".to_string(),
        normalized_text: "Speaker A: one two three four five six.\n\nSpeaker B: seven eight nine ten eleven twelve.\n\nSpeaker A: thirteen fourteen fifteen sixteen seventeen eighteen.".to_string(),
    };

    let segments = segment_document_text(&doc);
    let chunks = build_chunk_units(&doc, &segments, 8, 10);

    assert!(chunks.len() >= 2);
    assert!(chunks.iter().all(|chunk| chunk.token_count <= 10));
    assert_eq!(
        chunks
            .first()
            .and_then(|value| value.next_unit_id.as_deref()),
        Some(chunks[1].unit_id.as_str())
    );
    assert_eq!(
        chunks[1].prev_unit_id.as_deref(),
        Some(chunks[0].unit_id.as_str())
    );
}
