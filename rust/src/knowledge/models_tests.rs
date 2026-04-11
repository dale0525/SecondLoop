use crate::knowledge::models::{infer_generated_memory_section, GeneratedMemoryKind};
use crate::knowledge::{
    ContentKnowledgeDocument, KnowledgeAnchorSet, KnowledgeMemoryFeedback, KnowledgeMemorySection,
    KnowledgeOriginType, KnowledgeRole, KnowledgeSourceKind, KnowledgeUnit, KnowledgeUnitKind,
    KnowledgeVersionSet,
};

#[test]
fn knowledge_model_document_round_trips_through_json() {
    let value = ContentKnowledgeDocument {
        document_id: "doc-msg-1".to_string(),
        origin_type: KnowledgeOriginType::Message,
        source_kind: KnowledgeSourceKind::RawText,
        role: KnowledgeRole::Body,
        language: Some("en".to_string()),
        quality_score: 0.9,
        created_at_ms: 100,
        updated_at_ms: 120,
        versions: KnowledgeVersionSet::current(),
        anchors: KnowledgeAnchorSet {
            message_id: Some("msg-1".to_string()),
            conversation_id: Some("conv-1".to_string()),
            attachment_sha256: None,
            page_index: None,
            frame_index: None,
            start_ms: None,
            end_ms: None,
            speaker: None,
            section_label: Some("Body".to_string()),
            source_filename: None,
        },
        title: Some("Hello".to_string()),
        summary: None,
        raw_text: "raw text".to_string(),
        normalized_text: "raw text".to_string(),
        memory_display: None,
        memory_feedback: KnowledgeMemoryFeedback::default(),
    };

    let json = serde_json::to_string(&value).expect("serialize");
    let round_trip: ContentKnowledgeDocument = serde_json::from_str(&json).expect("deserialize");

    assert_eq!(round_trip.document_id, value.document_id);
    assert_eq!(round_trip.origin_type, KnowledgeOriginType::Message);
    assert_eq!(round_trip.source_kind, KnowledgeSourceKind::RawText);
    assert_eq!(round_trip.role, KnowledgeRole::Body);
    assert_eq!(round_trip.anchors.message_id.as_deref(), Some("msg-1"));
    assert_eq!(round_trip.versions.embedding_policy_version, 1);
}

#[test]
fn knowledge_model_unit_round_trips_through_json() {
    let value = KnowledgeUnit {
        unit_id: "unit-1".to_string(),
        document_id: "doc-1".to_string(),
        parent_unit_id: Some("section-1".to_string()),
        unit_kind: KnowledgeUnitKind::Chunk,
        source_kind: KnowledgeSourceKind::Transcript,
        role: KnowledgeRole::Evidence,
        ordinal: 3,
        token_count: 42,
        raw_text: "Speaker A: hi".to_string(),
        normalized_text: "speaker a: hi".to_string(),
        anchors: KnowledgeAnchorSet {
            message_id: None,
            conversation_id: None,
            attachment_sha256: Some("sha-1".to_string()),
            page_index: None,
            frame_index: None,
            start_ms: Some(1200),
            end_ms: Some(2400),
            speaker: Some("Speaker A".to_string()),
            section_label: Some("00:01-00:02".to_string()),
            source_filename: Some("clip.mp4".to_string()),
        },
        prev_unit_id: Some("unit-0".to_string()),
        next_unit_id: Some("unit-2".to_string()),
        created_at_ms: 100,
        updated_at_ms: 120,
    };

    let json = serde_json::to_string(&value).expect("serialize");
    let round_trip: KnowledgeUnit = serde_json::from_str(&json).expect("deserialize");

    assert_eq!(round_trip.unit_kind, KnowledgeUnitKind::Chunk);
    assert_eq!(round_trip.source_kind, KnowledgeSourceKind::Transcript);
    assert_eq!(round_trip.role, KnowledgeRole::Evidence);
    assert_eq!(round_trip.token_count, 42);
    assert_eq!(round_trip.anchors.start_ms, Some(1200));
    assert_eq!(round_trip.prev_unit_id.as_deref(), Some("unit-0"));
}

#[test]
fn generated_memory_kind_round_trips_through_json() {
    let json = serde_json::to_string(&GeneratedMemoryKind::Preference).expect("serialize");
    let round_trip: GeneratedMemoryKind = serde_json::from_str(&json).expect("deserialize");
    assert_eq!(round_trip, GeneratedMemoryKind::Preference);
    assert_eq!(round_trip.as_str(), "preference");
}

#[test]
fn infer_generated_memory_section_detects_chinese_project_signals() {
    let section = infer_generated_memory_section(
        "generated:profile:current-focus",
        Some("当前项目"),
        Some("用户正在推进新应用发布计划"),
        "这个项目的上线节奏需要和产品 roadmap 对齐。",
    );

    assert_eq!(section, Some(KnowledgeMemorySection::Project));
}
