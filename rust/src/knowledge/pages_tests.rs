use crate::knowledge::pages::{
    apply_wrong_reason, state_default_answer_policy, KnowledgePage, KnowledgePageState,
    KnowledgePageType, KnowledgeWrongReason,
};

#[test]
fn page_state_active_is_answer_eligible_by_default() {
    let page = KnowledgePage::new(
        "preferences",
        KnowledgePageType::Preferences,
        "Preferences",
        100,
    );
    assert_eq!(page.state, KnowledgePageState::Active);
    assert!(page.answer_policy.default_allowed);
    assert_eq!(page.user_state_label(), "current_valid");
}

#[test]
fn state_default_answer_policy_requires_temporal_framing_for_outdated_pages() {
    let policy = state_default_answer_policy(KnowledgePageState::Outdated);
    assert!(policy.default_allowed);
    assert!(policy.requires_temporal_framing);
}

#[test]
fn marking_page_wrong_moves_it_to_needs_review() {
    let updated = apply_wrong_reason(
        KnowledgePageState::Active,
        KnowledgeWrongReason::StatementWrong,
    );
    assert_eq!(updated, KnowledgePageState::NeedsReview);
}

#[test]
fn marking_page_outdated_moves_it_to_outdated() {
    let updated = apply_wrong_reason(KnowledgePageState::Active, KnowledgeWrongReason::Outdated);
    assert_eq!(updated, KnowledgePageState::Outdated);
}

#[test]
fn marking_page_incomplete_moves_it_to_needs_review() {
    let updated = apply_wrong_reason(KnowledgePageState::Active, KnowledgeWrongReason::Incomplete);
    assert_eq!(updated, KnowledgePageState::NeedsReview);
}

#[test]
fn marking_page_should_not_remember_archives_it() {
    let updated = apply_wrong_reason(
        KnowledgePageState::Active,
        KnowledgeWrongReason::ShouldNotRemember,
    );
    assert_eq!(updated, KnowledgePageState::Archived);
}
