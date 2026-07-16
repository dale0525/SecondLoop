use super::*;

const MAIL_SEND_PREVIEW: &str = "mail_send_preview";
const MAIL_SEND: &str = "mail_send";
const CANONICAL_MAIL_SEND_PREVIEW: &str = "connector__agentweave-mail__mail_send_preview";
const CANONICAL_MAIL_SEND: &str = "connector__agentweave-mail__mail_send";

pub(super) fn mail_send_preview_definition() -> ToolDefinition {
    ToolDefinition {
        name: MAIL_SEND_PREVIEW.into(),
        namespace: Some("foundation_mail".into()),
        description: "Create an authoritative Mail send preview and a durable action that waits for exact user approval.".into(),
        input_schema: serde_json::json!({
            "type": "object",
            "properties": {
                "accountId": {"type": "string"},
                "draftId": {"type": "string"},
                "expectedRevision": {"type": "integer", "minimum": 1}
            },
            "required": ["accountId", "draftId", "expectedRevision"],
            "additionalProperties": false
        }),
        output_schema: None,
        permission: ToolPermission::ReadSensitive,
        persistence: ToolPersistence::for_permission(ToolPermission::ReadSensitive),
        source: ToolSource::HostCapability {
            capability: "agentweave.foundation.mail/v1".into(),
        },
    }
}

impl ToolRegistry {
    pub(super) fn foundation_connector_definitions(
        &self,
        connectors: &crate::connector_tools::ConnectorToolRuntime,
    ) -> Vec<ToolDefinition> {
        let mut definitions = connectors.definitions();
        if self.mail_actions.is_some() {
            definitions.retain(|definition| !is_runtime_managed_mail_tool(&definition.name));
        }
        definitions
    }

    pub(super) async fn dispatch_foundation_mail_action(
        &self,
        name: &str,
        call_id: &str,
        arguments: &Value,
        started: Instant,
    ) -> Option<ToolDispatchOutcome> {
        let actions = self.mail_actions.as_ref()?;
        if matches!(
            name,
            MAIL_SEND | CANONICAL_MAIL_SEND | CANONICAL_MAIL_SEND_PREVIEW
        ) {
            return Some(ToolDispatchOutcome::unobserved(registry_failure(
                name,
                call_id,
                "tool_disabled",
                "Mail delivery is reserved for the Runtime approval resume path.",
                false,
                registry_metadata(started),
            )));
        }
        if name != MAIL_SEND_PREVIEW {
            return None;
        }
        let Some(context) = &self.foundation_action_context else {
            return Some(ToolDispatchOutcome::unobserved(registry_failure(
                name,
                call_id,
                "trusted_context_missing",
                "Mail approval requires a Host-injected session context.",
                false,
                registry_metadata(started),
            )));
        };
        let request = match serde_json::from_value::<
            crate::foundation_actions::AgentMailSendPreviewRequest,
        >(arguments.clone())
        {
            Ok(request) => request,
            Err(error) => {
                return Some(ToolDispatchOutcome::unobserved(registry_failure(
                    name,
                    call_id,
                    "invalid_arguments",
                    error.to_string(),
                    false,
                    registry_metadata(started),
                )));
            }
        };
        let result = match actions
            .request_send_from_agent_preview(request, context, call_id, chrono::Utc::now())
            .await
        {
            Ok(action) => match action.preview {
                Some(preview) => ToolResult::success(
                    name,
                    call_id,
                    serde_json::json!({
                        "status": "waiting_approval",
                        "preview": preview
                    }),
                    registry_metadata(started),
                ),
                None => registry_failure(
                    name,
                    call_id,
                    "foundation_action_error",
                    "Mail approval action is missing its authoritative preview.",
                    false,
                    registry_metadata(started),
                ),
            },
            Err(error) => registry_failure(
                name,
                call_id,
                "foundation_action_error",
                error.to_string(),
                false,
                registry_metadata(started),
            ),
        };
        Some(ToolDispatchOutcome::unobserved(result))
    }
}

fn is_runtime_managed_mail_tool(name: &str) -> bool {
    matches!(
        name,
        MAIL_SEND_PREVIEW | MAIL_SEND | CANONICAL_MAIL_SEND_PREVIEW | CANONICAL_MAIL_SEND
    )
}

#[cfg(test)]
#[path = "foundation_actions_tests.rs"]
mod tests;
