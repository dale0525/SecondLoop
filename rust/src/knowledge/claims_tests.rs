use crate::knowledge::claims::{
    KnowledgeClaim, KnowledgeClaimStatus, KnowledgeClaimTimeScope, KnowledgeClaimType,
};

#[test]
fn knowledge_claim_new_starts_as_candidate() {
    let claim = KnowledgeClaim::new(
        "claim_1",
        "self",
        KnowledgeClaimType::Preference,
        "response_language",
        "The user prefers Chinese responses.",
        100,
    );

    assert_eq!(claim.status, KnowledgeClaimStatus::Candidate);
    assert_eq!(claim.time_scope, KnowledgeClaimTimeScope::Unknown);
    assert!(claim.answer_allowed);
    assert_eq!(claim.created_at_ms, 100);
    assert_eq!(claim.updated_at_ms, 100);
}

#[test]
fn knowledge_claim_activate_updates_status_and_timestamp() {
    let claim = KnowledgeClaim::new(
        "claim_1",
        "self",
        KnowledgeClaimType::Preference,
        "response_language",
        "The user prefers Chinese responses.",
        100,
    )
    .activate(200);

    assert_eq!(claim.status, KnowledgeClaimStatus::Active);
    assert_eq!(claim.updated_at_ms, 200);
}

#[test]
fn knowledge_claim_mark_disputed_disables_answer_usage() {
    let claim = KnowledgeClaim::new(
        "claim_1",
        "self",
        KnowledgeClaimType::Focus,
        "current_focus",
        "The user is focused on launch work.",
        100,
    )
    .mark_disputed("claim_2", 220);

    assert_eq!(claim.status, KnowledgeClaimStatus::Disputed);
    assert!(!claim.answer_allowed);
    assert_eq!(claim.conflict_with_claim_ids, vec!["claim_2".to_string()]);
    assert_eq!(claim.updated_at_ms, 220);
}
