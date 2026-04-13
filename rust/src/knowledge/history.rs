use serde::{Deserialize, Serialize};

#[derive(Clone, Copy, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum KnowledgePageChangeType {
    Created,
    Updated,
    Corrected,
    Downgraded,
    Muted,
    Archived,
    Removed,
    Merged,
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct KnowledgePageChangeRecord {
    pub change_id: String,
    pub page_id: String,
    pub change_type: KnowledgePageChangeType,
    pub actor: String,
    pub reason: Option<String>,
    pub answer_impacted: bool,
    pub created_at_ms: i64,
}
