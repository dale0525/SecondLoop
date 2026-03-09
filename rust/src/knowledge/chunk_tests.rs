use crate::knowledge::{
    build_chunk_units, build_section_units, build_segment_units, segment_document_text,
    ContentKnowledgeDocument, KnowledgeAnchorSet, KnowledgeOriginType, KnowledgeRole,
    KnowledgeSourceKind, KnowledgeVersionSet,
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

#[test]
fn knowledge_units_preserve_raw_and_normalized_text_separately() {
    let doc = ContentKnowledgeDocument {
        document_id: "doc-raw-vs-normalized".to_string(),
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
        raw_text: "Speaker A:  One   Two.

Speaker B:   Three    Four."
            .to_string(),
        normalized_text: "speaker a: one two.

speaker b: three four."
            .to_string(),
    };

    let segments = segment_document_text(&doc);
    let sections = build_section_units(&doc, &segments);
    let segment_units = build_segment_units(&doc, &segments);
    let chunks = build_chunk_units(&doc, &segments, 100, 100);

    assert_eq!(sections[0].raw_text, "Speaker A:  One   Two.");
    assert_eq!(sections[0].normalized_text, "speaker a: one two.");
    assert_eq!(segment_units[1].raw_text, "Speaker B:   Three    Four.");
    assert_eq!(segment_units[1].normalized_text, "speaker b: three four.");
    assert_eq!(chunks[0].raw_text, doc.raw_text);
    assert_eq!(chunks[0].normalized_text, doc.normalized_text);
}

#[test]
fn knowledge_segmenting_does_not_cross_fill_missing_raw_paragraphs() {
    let doc = ContentKnowledgeDocument {
        document_id: "doc-misaligned-segments".to_string(),
        origin_type: KnowledgeOriginType::Attachment,
        source_kind: KnowledgeSourceKind::RawText,
        role: KnowledgeRole::Body,
        language: Some("en".to_string()),
        quality_score: 1.0,
        created_at_ms: 1,
        updated_at_ms: 1,
        versions: KnowledgeVersionSet::current(),
        anchors: KnowledgeAnchorSet::default(),
        title: None,
        summary: None,
        raw_text: "Alpha raw paragraph.".to_string(),
        normalized_text: "alpha normalized paragraph.

second normalized paragraph."
            .to_string(),
    };

    let segments = segment_document_text(&doc);

    assert_eq!(segments.len(), 2);
    assert_eq!(segments[0].raw_text, "Alpha raw paragraph.");
    assert_eq!(segments[0].normalized_text, "alpha normalized paragraph.");
    assert_eq!(segments[1].raw_text, "");
    assert_eq!(segments[1].normalized_text, "second normalized paragraph.");
}

#[test]
fn knowledge_chunking_does_not_cross_fill_raw_and_normalized_tail_parts() {
    let doc = ContentKnowledgeDocument {
        document_id: "doc-misaligned-tail".to_string(),
        origin_type: KnowledgeOriginType::Attachment,
        source_kind: KnowledgeSourceKind::RawText,
        role: KnowledgeRole::Body,
        language: Some("en".to_string()),
        quality_score: 1.0,
        created_at_ms: 1,
        updated_at_ms: 1,
        versions: KnowledgeVersionSet::current(),
        anchors: KnowledgeAnchorSet::default(),
        title: None,
        summary: None,
        raw_text: "alpha beta gamma delta epsilon".to_string(),
        normalized_text: "alpha beta gamma delta".to_string(),
    };

    let segments = segment_document_text(&doc);
    let chunks = build_chunk_units(&doc, &segments, 2, 2);

    assert_eq!(chunks.len(), 3);
    assert_eq!(chunks[0].raw_text, "alpha beta");
    assert_eq!(chunks[0].normalized_text, "alpha beta");
    assert_eq!(chunks[1].raw_text, "gamma delta");
    assert_eq!(chunks[1].normalized_text, "gamma delta");
    assert_eq!(chunks[2].raw_text, "epsilon");
    assert_eq!(chunks[2].normalized_text, "");
}
