#[derive(Clone, Debug)]
pub struct Todo {
    pub id: String,
    pub title: String,
    pub due_at_ms: Option<i64>,
    pub status: String,
    pub source_entry_id: Option<String>,
    pub created_at_ms: i64,
    pub updated_at_ms: i64,
    pub review_stage: Option<i64>,
    pub next_review_at_ms: Option<i64>,
    pub last_review_at_ms: Option<i64>,
    pub manual_importance_nudge_score: Option<i64>,
    pub manual_urgency_nudge_score: Option<i64>,
}

#[derive(Clone, Debug)]
pub struct TodoActivity {
    pub id: String,
    pub todo_id: String,
    pub activity_type: String,
    pub from_status: Option<String>,
    pub to_status: Option<String>,
    pub content: Option<String>,
    pub source_message_id: Option<String>,
    pub created_at_ms: i64,
}

#[derive(Clone, Debug)]
pub struct TodoChecklistItem {
    pub id: String,
    pub todo_id: String,
    pub content: String,
    pub is_done: bool,
    pub sort_order: i64,
    pub created_at_ms: i64,
    pub updated_at_ms: i64,
}

#[derive(Clone, Debug)]
pub struct TodoChecklistSuggestion {
    pub id: String,
    pub todo_id: String,
    pub content: String,
    pub sort_order: i64,
    pub state: String,
    pub source: String,
    pub generation_key: Option<String>,
    pub created_at_ms: i64,
    pub updated_at_ms: i64,
    pub dismissed_at_ms: Option<i64>,
    pub applied_checklist_item_id: Option<String>,
}

pub const TODO_CHECKLIST_SUGGESTION_STATE_PENDING: &str = "pending";
pub const TODO_CHECKLIST_SUGGESTION_STATE_APPLIED: &str = "applied";
pub const TODO_CHECKLIST_SUGGESTION_STATE_DISMISSED: &str = "dismissed";

#[derive(Clone, Debug)]
pub struct TodoChecklistProgress {
    pub todo_id: String,
    pub done_count: i64,
    pub total_count: i64,
}

#[derive(Clone, Debug)]
pub struct TodoFollowupSuggestionDraftInput {
    pub content: String,
    pub generation_mode: String,
    pub citations_json: Option<String>,
}

#[derive(Clone, Debug)]
pub struct TodoFollowupSuggestion {
    pub id: String,
    pub todo_id: String,
    pub content: String,
    pub state: String,
    pub source: String,
    pub generation_mode: String,
    pub generation_key: Option<String>,
    pub citations_json: Option<String>,
    pub created_at_ms: i64,
    pub updated_at_ms: i64,
    pub dismissed_at_ms: Option<i64>,
    pub applied_activity_id: Option<String>,
}

#[derive(Clone, Debug)]
pub struct TodoFollowupGenerationJob {
    pub todo_id: String,
    pub trigger_kind: String,
    pub status: String,
    pub attempts: i64,
    pub next_retry_at_ms: Option<i64>,
    pub last_error: Option<String>,
    pub include_manual_followups: bool,
    pub manual_override_followup: bool,
    pub task_type_hint: Option<String>,
    pub created_at_ms: i64,
    pub updated_at_ms: i64,
}

#[derive(Clone, Debug)]
pub struct NewSecretaryMemoryProposal {
    pub source_message_id: Option<String>,
    pub kind: String,
    pub title: String,
    pub body: String,
    pub confidence: f64,
    pub source_refs_json: Option<String>,
    pub action_hint: Option<String>,
    pub now_ms: i64,
}

#[derive(Clone, Debug)]
pub struct SecretaryMemoryProposalRecord {
    pub id: String,
    pub source_message_id: Option<String>,
    pub kind: String,
    pub title: String,
    pub body: String,
    pub confidence: f64,
    pub state: String,
    pub source_refs_json: Option<String>,
    pub action_hint: Option<String>,
    pub created_at_ms: i64,
    pub updated_at_ms: i64,
    pub accepted_at_ms: Option<i64>,
    pub dismissed_at_ms: Option<i64>,
}

#[derive(Clone, Debug)]
pub struct NewPlanningOutput {
    pub id: String,
    pub kind: String,
    pub title: String,
    pub body: String,
    pub items_json: String,
    pub source_refs_json: Option<String>,
    pub route: String,
    pub state: String,
    pub created_at_ms: i64,
    pub updated_at_ms: i64,
    pub expires_at_ms: Option<i64>,
}

#[derive(Clone, Debug)]
pub struct PlanningOutputRecord {
    pub id: String,
    pub kind: String,
    pub title: String,
    pub body: String,
    pub items_json: String,
    pub source_refs_json: Option<String>,
    pub route: String,
    pub state: String,
    pub created_at_ms: i64,
    pub updated_at_ms: i64,
    pub expires_at_ms: Option<i64>,
    pub dismissed_at_ms: Option<i64>,
}

#[derive(Clone, Debug)]
pub struct NewSecretaryRun {
    pub trigger_kind: String,
    pub route: String,
    pub status: String,
    pub input_summary: Option<String>,
    pub output_summary: Option<String>,
    pub error: Option<String>,
    pub now_ms: i64,
}

#[derive(Clone, Debug)]
pub struct SecretaryRunRecord {
    pub id: String,
    pub trigger_kind: String,
    pub route: String,
    pub status: String,
    pub input_summary: Option<String>,
    pub output_summary: Option<String>,
    pub error: Option<String>,
    pub created_at_ms: i64,
    pub updated_at_ms: i64,
}

#[derive(Clone, Debug)]
pub struct NewSecretaryToolCall {
    pub run_id: String,
    pub tool_name: String,
    pub status: String,
    pub requires_confirmation: bool,
    pub input_json: Option<String>,
    pub output_json: Option<String>,
    pub now_ms: i64,
}

#[derive(Clone, Debug)]
pub struct SecretaryToolCallRecord {
    pub id: String,
    pub run_id: String,
    pub tool_name: String,
    pub status: String,
    pub requires_confirmation: bool,
    pub input_json: Option<String>,
    pub output_json: Option<String>,
    pub created_at_ms: i64,
    pub updated_at_ms: i64,
}

#[derive(Clone, Debug)]
pub struct MemoryPageRecord {
    pub page_id: String,
    pub page_type: String,
    pub state: String,
    pub source_count: i64,
    pub title: String,
    pub summary: String,
    pub body: String,
    pub primary_evidence_json: String,
    pub source_document_ids_json: String,
    pub confidence_level: f64,
    pub human_corrected: bool,
    pub created_at_ms: i64,
    pub updated_at_ms: i64,
}

#[derive(Clone, Debug)]
pub struct CorrectMemoryPageInput {
    pub page_id: String,
    pub title: String,
    pub summary: String,
    pub body: String,
    pub reason: Option<String>,
    pub now_ms: i64,
}
