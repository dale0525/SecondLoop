use crate::knowledge::history::{KnowledgePageChangeRecord, KnowledgePageChangeType};

#[test]
fn change_record_round_trips_basic_fields() {
    let record = KnowledgePageChangeRecord {
        change_id: "chg_1".to_string(),
        page_id: "preferences".to_string(),
        change_type: KnowledgePageChangeType::Corrected,
        actor: "user".to_string(),
        reason: Some("manual fix".to_string()),
        answer_impacted: true,
        created_at_ms: 100,
    };

    assert_eq!(record.change_type, KnowledgePageChangeType::Corrected);
    assert!(record.answer_impacted);
}
