use serde::{Deserialize, Serialize};

#[derive(Clone, Copy, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum KnowledgeClaimType {
    Identity,
    Preference,
    Focus,
    Thread,
    Event,
    Relationship,
    Topic,
    Question,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum KnowledgeClaimTimeScope {
    Stable,
    Current,
    Recent,
    Historical,
    Unknown,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum KnowledgeClaimStatus {
    Candidate,
    Active,
    Supporting,
    Disputed,
    Outdated,
    Dismissed,
}

#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
pub struct KnowledgeClaim {
    pub claim_id: String,
    pub subject_id: String,
    pub claim_type: KnowledgeClaimType,
    pub facet_key: String,
    pub statement: String,
    pub normalized_value: Option<String>,
    pub time_scope: KnowledgeClaimTimeScope,
    pub valid_from_ms: Option<i64>,
    pub valid_until_ms: Option<i64>,
    pub confidence: f64,
    pub source_ref_ids: Vec<String>,
    pub source_count: i64,
    pub conflict_with_claim_ids: Vec<String>,
    pub status: KnowledgeClaimStatus,
    pub human_confirmed: bool,
    pub human_corrected: bool,
    pub answer_allowed: bool,
    pub created_at_ms: i64,
    pub updated_at_ms: i64,
}

impl KnowledgeClaim {
    pub fn new(
        claim_id: impl Into<String>,
        subject_id: impl Into<String>,
        claim_type: KnowledgeClaimType,
        facet_key: impl Into<String>,
        statement: impl Into<String>,
        now_ms: i64,
    ) -> Self {
        Self {
            claim_id: claim_id.into(),
            subject_id: subject_id.into(),
            claim_type,
            facet_key: facet_key.into(),
            statement: statement.into(),
            normalized_value: None,
            time_scope: KnowledgeClaimTimeScope::Unknown,
            valid_from_ms: None,
            valid_until_ms: None,
            confidence: 0.5,
            source_ref_ids: Vec::new(),
            source_count: 0,
            conflict_with_claim_ids: Vec::new(),
            status: KnowledgeClaimStatus::Candidate,
            human_confirmed: false,
            human_corrected: false,
            answer_allowed: true,
            created_at_ms: now_ms,
            updated_at_ms: now_ms,
        }
    }

    pub fn activate(mut self, now_ms: i64) -> Self {
        self.status = KnowledgeClaimStatus::Active;
        self.updated_at_ms = now_ms;
        self
    }

    pub fn mark_disputed(mut self, conflict_with_claim_id: impl Into<String>, now_ms: i64) -> Self {
        self.status = KnowledgeClaimStatus::Disputed;
        self.answer_allowed = false;
        self.conflict_with_claim_ids
            .push(conflict_with_claim_id.into());
        self.updated_at_ms = now_ms;
        self
    }
}
