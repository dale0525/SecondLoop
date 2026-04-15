use serde::{Deserialize, Serialize};

use crate::knowledge::{KnowledgeLintRecord, KnowledgePageChangeRecord, KnowledgePageChangeType};

#[derive(Clone, Copy, Debug, PartialEq, Eq, PartialOrd, Ord, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum KnowledgePageType {
    AboutMe,
    Preferences,
    CurrentFocus,
    ActiveThreads,
    RecentEvents,
    People,
    Topics,
    OpenQuestions,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum KnowledgePageState {
    Active,
    NeedsReview,
    Outdated,
    AnswerMuted,
    Archived,
    Removed,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum KnowledgeWrongReason {
    StatementWrong,
    Outdated,
    Incomplete,
    ShouldNotRemember,
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct KnowledgeAnswerPolicy {
    pub default_allowed: bool,
    pub requires_temporal_framing: bool,
}

impl Default for KnowledgeAnswerPolicy {
    fn default() -> Self {
        Self {
            default_allowed: true,
            requires_temporal_framing: false,
        }
    }
}

#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
pub struct KnowledgePage {
    pub page_id: String,
    pub page_type: KnowledgePageType,
    pub title: String,
    pub current_summary: String,
    pub current_body: String,
    pub state: KnowledgePageState,
    pub answer_policy: KnowledgeAnswerPolicy,
    pub confidence_level: f64,
    pub created_at_ms: i64,
    pub updated_at_ms: i64,
    pub last_used_at_ms: Option<i64>,
    pub source_count: i64,
    pub conflict_count: i64,
    pub human_corrected: bool,
    pub tags: Vec<String>,
    pub primary_evidence_ids: Vec<String>,
    pub related_page_ids: Vec<String>,
}

#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
pub struct KnowledgePageSummary {
    pub page_id: String,
    pub page_type: KnowledgePageType,
    pub title: String,
    pub current_summary: String,
    pub state: KnowledgePageState,
    pub answer_policy: KnowledgeAnswerPolicy,
    pub updated_at_ms: i64,
    pub last_used_at_ms: Option<i64>,
    pub source_count: i64,
    pub conflict_count: i64,
    pub human_corrected: bool,
    pub tags: Vec<String>,
    pub primary_evidence_ids: Vec<String>,
}

#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
pub struct KnowledgePageDetail {
    pub page: KnowledgePage,
    pub source_document_ids: Vec<String>,
    pub claim_ids: Vec<String>,
    pub history: Vec<KnowledgePageChangeRecord>,
    pub version_snapshots: Vec<KnowledgePageVersionSnapshot>,
    pub evidence_entries: Vec<KnowledgePageEvidenceEntry>,
    pub lint_records: Vec<KnowledgeLintRecord>,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum KnowledgePageEvidenceKind {
    Support,
    Conflict,
    Supplement,
}

#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
pub struct KnowledgePageEvidenceEntry {
    pub evidence_id: String,
    pub kind: KnowledgePageEvidenceKind,
    pub summary: String,
    pub source_ref_ids: Vec<String>,
    pub created_at_ms: i64,
}

#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
pub struct KnowledgePageVersionSnapshot {
    pub version_id: String,
    pub page_id: String,
    pub title: String,
    pub summary: String,
    pub body: String,
    pub state: KnowledgePageState,
    pub answer_policy: KnowledgeAnswerPolicy,
    pub confidence_level: f64,
    pub source_count: i64,
    pub conflict_count: i64,
    pub human_corrected: bool,
    pub actor: String,
    pub change_type: KnowledgePageChangeType,
    pub reason: Option<String>,
    pub created_at_ms: i64,
}

impl KnowledgePage {
    pub fn new(
        page_id: impl Into<String>,
        page_type: KnowledgePageType,
        title: impl Into<String>,
        now_ms: i64,
    ) -> Self {
        Self {
            page_id: page_id.into(),
            page_type,
            title: title.into(),
            current_summary: String::new(),
            current_body: String::new(),
            state: KnowledgePageState::Active,
            answer_policy: KnowledgeAnswerPolicy::default(),
            confidence_level: 0.5,
            created_at_ms: now_ms,
            updated_at_ms: now_ms,
            last_used_at_ms: None,
            source_count: 0,
            conflict_count: 0,
            human_corrected: false,
            tags: Vec::new(),
            primary_evidence_ids: Vec::new(),
            related_page_ids: Vec::new(),
        }
    }

    pub fn user_state_label(&self) -> &'static str {
        match self.state {
            KnowledgePageState::Active => "current_valid",
            KnowledgePageState::NeedsReview => "needs_attention",
            KnowledgePageState::Outdated => "possibly_outdated",
            KnowledgePageState::AnswerMuted => "not_used_for_answers",
            KnowledgePageState::Archived => "archived",
            KnowledgePageState::Removed => "removed",
        }
    }
}

impl From<&KnowledgePage> for KnowledgePageSummary {
    fn from(page: &KnowledgePage) -> Self {
        Self {
            page_id: page.page_id.clone(),
            page_type: page.page_type,
            title: page.title.clone(),
            current_summary: page.current_summary.clone(),
            state: page.state,
            answer_policy: page.answer_policy.clone(),
            updated_at_ms: page.updated_at_ms,
            last_used_at_ms: page.last_used_at_ms,
            source_count: page.source_count,
            conflict_count: page.conflict_count,
            human_corrected: page.human_corrected,
            tags: page.tags.clone(),
            primary_evidence_ids: page.primary_evidence_ids.clone(),
        }
    }
}

pub fn evidence_memory_status_for_page(
    page: &KnowledgePage,
) -> crate::knowledge::KnowledgeMemoryStatus {
    match page.state {
        KnowledgePageState::Outdated => crate::knowledge::KnowledgeMemoryStatus::MaybeOutdated,
        KnowledgePageState::NeedsReview
        | KnowledgePageState::AnswerMuted
        | KnowledgePageState::Archived
        | KnowledgePageState::Removed => crate::knowledge::KnowledgeMemoryStatus::Inferred,
        KnowledgePageState::Active => {
            if page.human_corrected {
                crate::knowledge::KnowledgeMemoryStatus::Confirmed
            } else {
                crate::knowledge::KnowledgeMemoryStatus::Inferred
            }
        }
    }
}

pub fn state_default_answer_policy(state: KnowledgePageState) -> KnowledgeAnswerPolicy {
    match state {
        KnowledgePageState::Active => KnowledgeAnswerPolicy {
            default_allowed: true,
            requires_temporal_framing: false,
        },
        KnowledgePageState::NeedsReview => KnowledgeAnswerPolicy {
            default_allowed: false,
            requires_temporal_framing: false,
        },
        KnowledgePageState::Outdated => KnowledgeAnswerPolicy {
            default_allowed: true,
            requires_temporal_framing: true,
        },
        KnowledgePageState::AnswerMuted
        | KnowledgePageState::Archived
        | KnowledgePageState::Removed => KnowledgeAnswerPolicy {
            default_allowed: false,
            requires_temporal_framing: false,
        },
    }
}

pub fn apply_wrong_reason(
    current: KnowledgePageState,
    reason: KnowledgeWrongReason,
) -> KnowledgePageState {
    match reason {
        KnowledgeWrongReason::StatementWrong => KnowledgePageState::NeedsReview,
        KnowledgeWrongReason::Outdated => KnowledgePageState::Outdated,
        KnowledgeWrongReason::Incomplete => match current {
            KnowledgePageState::Archived | KnowledgePageState::Removed => current,
            _ => KnowledgePageState::NeedsReview,
        },
        KnowledgeWrongReason::ShouldNotRemember => KnowledgePageState::Archived,
    }
}
