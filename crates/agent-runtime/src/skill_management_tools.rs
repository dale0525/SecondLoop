use crate::skill_management::{
    CreateSkillDraftRequest, DraftFileUpdate, OwnerSkillManagementService, SkillManagementError,
};
use crate::skill_package::SkillPackageKind;
use crate::skill_policy::{ActorContext, SkillManagementPolicy, SkillOperation};
use crate::tools::result::{ToolError, ToolResult, ToolResultMetadata};
use crate::tools::{ToolDefinition, ToolPermission, ToolPersistence, ToolSource};
use serde_json::{Value, json};

pub const CREATE_SKILL_DRAFT_TOOL: &str = "create_skill_draft";
pub const UPDATE_SKILL_DRAFT_TOOL: &str = "update_skill_draft";
pub const VALIDATE_SKILL_DRAFT_TOOL: &str = "validate_skill_draft";
pub const TEST_SKILL_DRAFT_TOOL: &str = "test_skill_draft";
pub const REQUEST_SKILL_ACTIVATION_TOOL: &str = "request_skill_activation";

#[derive(serde::Deserialize)]
#[serde(deny_unknown_fields)]
struct UpdateDraftArguments {
    revision_id: String,
    files: Vec<DraftFileUpdate>,
}

#[derive(serde::Deserialize)]
#[serde(deny_unknown_fields)]
struct RevisionArguments {
    revision_id: String,
}

#[derive(Clone)]
pub struct SkillManagementToolContext {
    pub service: OwnerSkillManagementService,
    pub actor: ActorContext,
}

impl std::fmt::Debug for SkillManagementToolContext {
    fn fmt(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        formatter
            .debug_struct("SkillManagementToolContext")
            .field("actor", &self.actor)
            .finish_non_exhaustive()
    }
}

pub struct SkillManagementTools;

impl SkillManagementTools {
    pub(crate) fn is_reserved_name(name: &str) -> bool {
        matches!(
            name,
            CREATE_SKILL_DRAFT_TOOL
                | UPDATE_SKILL_DRAFT_TOOL
                | VALIDATE_SKILL_DRAFT_TOOL
                | TEST_SKILL_DRAFT_TOOL
                | REQUEST_SKILL_ACTIVATION_TOOL
        )
    }

    pub fn definitions(
        service: &OwnerSkillManagementService,
        actor: &ActorContext,
    ) -> Vec<ToolDefinition> {
        Self::definitions_for_policy(service.policy(), actor)
    }

    pub fn definitions_for_policy(
        policy: &SkillManagementPolicy,
        actor: &ActorContext,
    ) -> Vec<ToolDefinition> {
        let allowed_kinds = [
            (SkillPackageKind::InstructionOnly, "instruction_only"),
            (SkillPackageKind::HostToolsOnly, "host_tools_only"),
        ]
        .into_iter()
        .filter_map(|(kind, name)| {
            policy
                .allows(actor, SkillOperation::CreateDraft, kind)
                .then_some(name)
        })
        .collect::<Vec<_>>();
        let mut definitions = Vec::new();
        if !allowed_kinds.is_empty() {
            definitions.push(definition(
                CREATE_SKILL_DRAFT_TOOL,
                "Create an inactive owner-managed skill draft.",
                create_draft_schema(&allowed_kinds),
            ));
        }
        for (operation, name, description, schema) in [
            (
                SkillOperation::EditDraft,
                UPDATE_SKILL_DRAFT_TOOL,
                "Update files in an inactive owner-managed skill draft.",
                update_draft_schema(),
            ),
            (
                SkillOperation::Validate,
                VALIDATE_SKILL_DRAFT_TOOL,
                "Validate an inactive owner-managed skill draft.",
                revision_schema(),
            ),
            (
                SkillOperation::Test,
                TEST_SKILL_DRAFT_TOOL,
                "Test an inactive owner-managed skill draft.",
                revision_schema(),
            ),
            (
                SkillOperation::Activate,
                REQUEST_SKILL_ACTIVATION_TOOL,
                "Request approval to activate a validated skill draft.",
                revision_schema(),
            ),
        ] {
            if policy
                .allowed_kinds
                .iter()
                .copied()
                .any(|kind| policy.allows(actor, operation, kind))
            {
                definitions.push(definition(name, description, schema));
            }
        }
        definitions
    }

    pub fn handles(context: &SkillManagementToolContext, name: &str) -> bool {
        Self::definitions(&context.service, &context.actor)
            .iter()
            .any(|definition| definition.name == name)
    }

    pub async fn execute(
        context: &SkillManagementToolContext,
        name: &str,
        call_id: &str,
        arguments: Value,
    ) -> ToolResult {
        macro_rules! parse_arguments {
            ($kind:ty) => {
                match serde_json::from_value::<$kind>(arguments) {
                    Ok(value) => value,
                    Err(error) => {
                        return failure(name, call_id, "invalid_arguments", error.to_string());
                    }
                }
            };
        }
        let result = match name {
            CREATE_SKILL_DRAFT_TOOL => {
                let request = parse_arguments!(CreateSkillDraftRequest);
                context
                    .service
                    .create_draft(&context.actor, request)
                    .await
                    .and_then(|value| Ok(serde_json::to_value(value)?))
            }
            UPDATE_SKILL_DRAFT_TOOL => {
                let request = parse_arguments!(UpdateDraftArguments);
                context
                    .service
                    .update_draft(&context.actor, &request.revision_id, request.files)
                    .await
                    .and_then(|value| Ok(serde_json::to_value(value)?))
            }
            VALIDATE_SKILL_DRAFT_TOOL => {
                let request = parse_arguments!(RevisionArguments);
                context
                    .service
                    .validate_draft(&context.actor, &request.revision_id)
                    .await
                    .and_then(|value| Ok(serde_json::to_value(value)?))
            }
            TEST_SKILL_DRAFT_TOOL => {
                let request = parse_arguments!(RevisionArguments);
                context
                    .service
                    .test_draft(&context.actor, &request.revision_id)
                    .await
                    .and_then(|value| Ok(serde_json::to_value(value)?))
            }
            REQUEST_SKILL_ACTIVATION_TOOL => {
                let request = parse_arguments!(RevisionArguments);
                context
                    .service
                    .request_activation(&context.actor, &request.revision_id)
                    .await
                    .and_then(|value| approval_value(&value))
            }
            _ => {
                return failure(
                    name,
                    call_id,
                    "unknown_tool",
                    format!("unknown tool: {name}"),
                );
            }
        };
        match result {
            Ok(value) => ToolResult::success(name, call_id, value, ToolResultMetadata::default()),
            Err(error) => {
                let (code, message) = classify_error(&error);
                failure(name, call_id, code, message)
            }
        }
    }
}

fn approval_value(approval: &crate::skill_state::SkillApprovalRecord) -> anyhow::Result<Value> {
    Ok(json!({
        "approval_id": approval.approval_id,
        "package_id": approval.package_id.as_str(),
        "revision_id": approval.revision_id,
        "operation": approval.operation,
        "requested_by": approval.requested_by,
        "status": approval.status.as_str(),
        "permission_diff": approval.permission_diff,
    }))
}

fn definition(name: &str, description: &str, input_schema: Value) -> ToolDefinition {
    ToolDefinition {
        name: name.into(),
        namespace: Some("agentweave_skill_management".into()),
        description: description.into(),
        input_schema,
        output_schema: None,
        permission: ToolPermission::ManageSkills,
        persistence: ToolPersistence::Full,
        source: ToolSource::BuiltIn,
    }
}

fn create_draft_schema(allowed_kinds: &[&str]) -> Value {
    json!({
        "type": "object",
        "additionalProperties": false,
        "required": ["package_id", "display_name", "description", "kind"],
        "properties": {
            "package_id": {"type": "string"},
            "display_name": {"type": "string"},
            "description": {"type": "string"},
            "kind": {
                "type": "string",
                "enum": allowed_kinds
            },
            "required_tools": {
                "type": "array",
                "items": {"type": "string"},
                "default": []
            }
        }
    })
}

fn revision_schema() -> Value {
    json!({
        "type": "object",
        "additionalProperties": false,
        "required": ["revision_id"],
        "properties": {"revision_id": {"type": "string"}}
    })
}

fn update_draft_schema() -> Value {
    json!({
        "type": "object",
        "additionalProperties": false,
        "required": ["revision_id", "files"],
        "properties": {
            "revision_id": {"type": "string"},
            "files": {
                "type": "array",
                "minItems": 1,
                "items": {
                    "type": "object",
                    "additionalProperties": false,
                    "required": ["path", "content"],
                    "properties": {
                        "path": {"type": "string"},
                        "content": {"type": "string"}
                    }
                }
            }
        }
    })
}

fn classify_error(error: &anyhow::Error) -> (&'static str, String) {
    match error.downcast_ref::<SkillManagementError>() {
        Some(SkillManagementError::Denied { .. }) => (
            "permission_denied",
            "skill management operation denied".into(),
        ),
        Some(SkillManagementError::InvalidRequest(_)) => (
            "invalid_arguments",
            "invalid skill management request".into(),
        ),
        Some(SkillManagementError::NotFound { .. }) => {
            ("not_found", "skill management resource not found".into())
        }
        Some(SkillManagementError::Conflict { .. }) => {
            ("conflict", "skill management state conflict".into())
        }
        Some(SkillManagementError::Internal { .. }) => {
            ("internal_error", "skill management operation failed".into())
        }
        None => ("internal_error", "skill management operation failed".into()),
    }
}

fn failure(tool: &str, call_id: &str, code: &str, message: impl Into<String>) -> ToolResult {
    ToolResult::failure(
        tool,
        call_id,
        ToolError {
            code: code.into(),
            message: message.into(),
            retryable: false,
        },
        ToolResultMetadata::default(),
    )
}
