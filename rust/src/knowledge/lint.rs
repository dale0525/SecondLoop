use serde::{Deserialize, Serialize};

#[derive(Clone, Copy, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum KnowledgeLintKind {
    Conflict,
    Staleness,
    Fragmentation,
    UnusedKnowledge,
    EvidenceWeakness,
    RegenerationRisk,
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct KnowledgeLintRecord {
    pub lint_id: String,
    pub page_id: String,
    pub kind: KnowledgeLintKind,
    pub summary: String,
    pub created_at_ms: i64,
}
