use crate::structured_content_store::{PublishStructuredContentRequest, StructuredContentService};
use crate::tools::{ToolDefinition, ToolPermission, ToolPersistence, ToolSource};
use chrono::Utc;
use serde::Deserialize;
use serde_json::{Value, json};

pub const STRUCTURED_CONTENT_TOOL_NAMES: [&str; 3] = [
    "structured_content_publish",
    "structured_content_get",
    "structured_content_delete",
];

#[derive(Clone)]
pub struct StructuredContentToolRuntime {
    service: StructuredContentService,
    context: Option<StructuredContentTurnContext>,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct StructuredContentTurnContext {
    pub session_id: String,
    pub turn_id: String,
}

impl StructuredContentTurnContext {
    pub fn new(session_id: impl Into<String>, turn_id: impl Into<String>) -> anyhow::Result<Self> {
        let context = Self {
            session_id: session_id.into(),
            turn_id: turn_id.into(),
        };
        anyhow::ensure!(
            !context.session_id.is_empty(),
            "structured content session is required"
        );
        anyhow::ensure!(
            !context.turn_id.is_empty(),
            "structured content turn is required"
        );
        Ok(context)
    }
}

impl StructuredContentToolRuntime {
    pub fn new(service: StructuredContentService) -> Self {
        Self {
            service,
            context: None,
        }
    }

    pub fn with_turn_context(mut self, context: StructuredContentTurnContext) -> Self {
        self.context = Some(context);
        self
    }

    pub fn service(&self) -> StructuredContentService {
        self.service.clone()
    }

    pub fn definitions(&self) -> Vec<ToolDefinition> {
        definitions()
    }

    pub fn handles(&self, name: &str) -> bool {
        STRUCTURED_CONTENT_TOOL_NAMES.contains(&name)
    }

    pub fn parallel_safe(&self, name: &str) -> bool {
        name == "structured_content_get"
    }

    pub async fn execute(&self, name: &str, arguments: Value) -> anyhow::Result<Value> {
        let context = self
            .context
            .as_ref()
            .ok_or_else(|| anyhow::anyhow!("structured content tool has no turn context"))?;
        match name {
            "structured_content_publish" => {
                let request: PublishStructuredContentRequest = serde_json::from_value(arguments)?;
                serde_json::to_value(
                    self.service
                        .publish(
                            &context.session_id,
                            Some(&context.turn_id),
                            request,
                            Utc::now(),
                        )
                        .await?,
                )
                .map_err(Into::into)
            }
            "structured_content_get" => {
                let request: ContentIdArguments = serde_json::from_value(arguments)?;
                serde_json::to_value(
                    self.service
                        .get(&context.session_id, &request.content_id)
                        .await?,
                )
                .map_err(Into::into)
            }
            "structured_content_delete" => {
                let request: DeleteContentArguments = serde_json::from_value(arguments)?;
                let deleted = self
                    .service
                    .delete(
                        &context.session_id,
                        Some(&context.turn_id),
                        &request.content_id,
                        request.expected_revision,
                        Utc::now(),
                    )
                    .await?;
                Ok(json!({ "deleted": deleted }))
            }
            _ => anyhow::bail!("unknown structured content tool: {name}"),
        }
    }
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
struct ContentIdArguments {
    content_id: String,
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
struct DeleteContentArguments {
    content_id: String,
    expected_revision: u64,
}

fn definitions() -> Vec<ToolDefinition> {
    vec![
        definition(
            "structured_content_publish",
            "Publish or update a safe declarative chat card. Private action parameters are stored behind short-lived opaque bindings and never placed in the public card payload.",
            publish_schema(),
            ToolPermission::PersistData,
        ),
        definition(
            "structured_content_get",
            "Read the current revision of a structured chat card in this conversation.",
            json!({
                "type": "object",
                "properties": {"contentId": {"type": "string", "minLength": 1, "maxLength": 255}},
                "required": ["contentId"],
                "additionalProperties": false
            }),
            ToolPermission::ReadSensitive,
        ),
        definition(
            "structured_content_delete",
            "Delete a structured chat card using its current revision. The content ID remains tombstoned and cannot be reused.",
            json!({
                "type": "object",
                "properties": {
                    "contentId": {"type": "string", "minLength": 1, "maxLength": 255},
                    "expectedRevision": {"type": "integer", "minimum": 1}
                },
                "required": ["contentId", "expectedRevision"],
                "additionalProperties": false
            }),
            ToolPermission::DestructiveWrite,
        ),
    ]
}

fn definition(
    name: &str,
    description: &str,
    input_schema: Value,
    permission: ToolPermission,
) -> ToolDefinition {
    ToolDefinition {
        name: name.into(),
        namespace: Some("structured-content".into()),
        description: description.into(),
        input_schema,
        output_schema: None,
        permission,
        persistence: ToolPersistence::MetadataOnly,
        source: ToolSource::HostCapability {
            capability: "agentweave.host.structured-content/v1".into(),
        },
    }
}

fn publish_schema() -> Value {
    json!({
        "type": "object",
        "properties": {
            "contentId": {"type": ["string", "null"], "maxLength": 255},
            "expectedRevision": {"type": ["integer", "null"], "minimum": 1},
            "mimeType": {"type": "string", "minLength": 3, "maxLength": 128},
            "schemaVersion": {"type": "string", "minLength": 1, "maxLength": 64},
            "payload": {"type": "object"},
            "fallbackText": {"type": "string", "minLength": 1, "maxLength": 32768},
            "audience": {"type": "string", "enum": ["user", "owner", "developer"]},
            "bindings": {
                "type": "array",
                "maxItems": 16,
                "items": {
                    "type": "object",
                    "properties": {
                        "actionId": {"type": "string", "minLength": 1, "maxLength": 255},
                        "intent": {"type": "string", "enum": ["oauth.start", "oauth.status", "oauth.cancel", "schedule.create", "schedule.status"]},
                        "idempotencyKey": {"type": "string", "minLength": 1, "maxLength": 255},
                        "expiresAt": {"type": "string", "format": "date-time"},
                        "parameters": {"type": "object"},
                        "inputSchema": {"type": "object"},
                        "constraints": {"type": "object"}
                    },
                    "required": ["actionId", "intent", "idempotencyKey", "expiresAt"],
                    "additionalProperties": false
                }
            }
        },
        "required": ["mimeType", "schemaVersion", "payload", "fallbackText"],
        "additionalProperties": false
    })
}
