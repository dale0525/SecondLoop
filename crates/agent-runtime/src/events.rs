use crate::policy::ApprovalPolicy;
use crate::skill_policy::SkillOperation;
use crate::tools::{ToolPermission, ToolPersistence};
use serde::{Deserialize, Serialize};
use serde_json::Value;

#[derive(Debug, Clone, Deserialize, Serialize, PartialEq)]
#[serde(tag = "type", rename_all = "snake_case")]
pub enum RuntimeEvent {
    TurnStarted {
        turn_id: String,
    },
    AssistantTextDelta {
        text: String,
    },
    ReasoningDelta {
        text: String,
    },
    ApprovalRequired {
        call_id: String,
        name: String,
        permission: ToolPermission,
        policy: ApprovalPolicy,
    },
    SkillApprovalRequired {
        approval_id: String,
        operation: SkillOperation,
        package_id: String,
        revision_id: String,
        permission_diff: Value,
    },
    SkillSnapshotPublished {
        generation: u64,
    },
    SkillRevisionRolledBack {
        package_id: String,
        revision_id: String,
        generation: u64,
    },
    SkillSelected {
        skill_name: String,
        reason: crate::skill_catalog::SkillSelectionReason,
    },
    MemoryRecalled {
        memory_ids: Vec<String>,
    },
    MemoryRecallFailed {
        message: String,
    },
    MemoryCandidatesProposed {
        memory_ids: Vec<String>,
    },
    MemoryCandidateExtractionFailed {
        message: String,
    },
    MemoryCompactionSynced {
        memory_ids: Vec<String>,
    },
    SkillRecoveryCompleted {
        status: crate::skill_recovery::RecoveryStatus,
        generation: u64,
    },
    ToolCallStarted {
        call_id: String,
        name: String,
        arguments: Value,
        #[serde(default)]
        persistence: ToolPersistence,
    },
    ToolCallFinished {
        call_id: String,
        result: Value,
        #[serde(default)]
        persistence: ToolPersistence,
    },
    ToolObserverDiagnostic {
        operation: String,
        message: String,
    },
    UsageReported {
        input_tokens: u64,
        output_tokens: u64,
        total_tokens: u64,
        exceeded: bool,
    },
    ContextCompacted {
        original_items: usize,
        compacted_items: usize,
        budget_bytes: usize,
    },
    StructuredContentPublished {
        content: crate::structured_content::StructuredContent,
    },
    StructuredContentDeleted {
        content_id: String,
        owner: String,
        revision: u64,
        audience: crate::structured_content::StructuredContentAudience,
    },
    StructuredContentActionAccepted {
        receipt: crate::structured_content::StructuredActionReceipt,
    },
    SubagentStarted {
        subagent_id: String,
        task: String,
    },
    SubagentFinished {
        subagent_id: String,
    },
    SubagentFailed {
        subagent_id: String,
        message: String,
    },
    AssistantMessageFinished {
        text: String,
    },
    TurnFinished {
        turn_id: String,
    },
    TurnCancelled {
        turn_id: String,
    },
    TurnFailed {
        turn_id: String,
        message: String,
    },
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::skill_policy::SkillOperation;

    #[test]
    fn runtime_event_serializes_with_snake_case_type() {
        let event = RuntimeEvent::AssistantTextDelta {
            text: "hello".into(),
        };

        let json = serde_json::to_value(event).unwrap();
        assert_eq!(json["type"], "assistant_text_delta");
        assert_eq!(json["text"], "hello");
    }

    #[test]
    fn skill_approval_required_serializes_exact_payload() {
        let event = RuntimeEvent::SkillApprovalRequired {
            approval_id: "approval-1".into(),
            operation: SkillOperation::Activate,
            package_id: "com.example.calendar".into(),
            revision_id: "revision-1".into(),
            permission_diff: serde_json::json!({"added": ["calendar.write"]}),
        };

        assert_eq!(
            serde_json::to_value(event).unwrap(),
            serde_json::json!({
                "type": "skill_approval_required",
                "approval_id": "approval-1",
                "operation": "activate",
                "package_id": "com.example.calendar",
                "revision_id": "revision-1",
                "permission_diff": {"added": ["calendar.write"]}
            })
        );
    }

    #[test]
    fn skill_snapshot_published_serializes_exact_payload() {
        let event = RuntimeEvent::SkillSnapshotPublished { generation: 7 };

        assert_eq!(
            serde_json::to_value(event).unwrap(),
            serde_json::json!({
                "type": "skill_snapshot_published",
                "generation": 7
            })
        );
    }

    #[test]
    fn skill_revision_rolled_back_serializes_exact_payload() {
        let event = RuntimeEvent::SkillRevisionRolledBack {
            package_id: "com.example.calendar".into(),
            revision_id: "revision-1".into(),
            generation: 8,
        };

        assert_eq!(
            serde_json::to_value(event).unwrap(),
            serde_json::json!({
                "type": "skill_revision_rolled_back",
                "package_id": "com.example.calendar",
                "revision_id": "revision-1",
                "generation": 8
            })
        );
    }
}
