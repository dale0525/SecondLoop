use crate::knowledge::{normalize_text_for_source, KnowledgeSourceKind};

#[test]
fn knowledge_normalization_collapses_noise_without_changing_structure() {
    let normalized = normalize_text_for_source(
        KnowledgeSourceKind::Transcript,
        "  [00:01]  SPEAKER A :  Hello   world  \n\n  [00:02] SPEAKER B: Hi  ",
    );

    assert!(normalized.contains("[00:01] Speaker A: Hello world"));
    assert!(normalized.contains("[00:02] Speaker B: Hi"));
}
