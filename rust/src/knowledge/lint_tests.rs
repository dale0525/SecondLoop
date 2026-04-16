use crate::knowledge::lint::{KnowledgeLintKind, KnowledgeLintRecord};

#[test]
fn lint_record_keeps_kind_and_summary() {
    let lint = KnowledgeLintRecord {
        lint_id: "lint_1".to_string(),
        page_id: "current_focus".to_string(),
        kind: KnowledgeLintKind::Conflict,
        summary: "Conflicting focus claims".to_string(),
        created_at_ms: 100,
    };

    assert_eq!(lint.kind, KnowledgeLintKind::Conflict);
    assert_eq!(lint.summary, "Conflicting focus claims");
}
