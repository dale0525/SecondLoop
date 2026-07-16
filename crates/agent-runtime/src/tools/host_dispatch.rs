use super::*;
use std::future::Future;

struct HostDispatchCall<'a> {
    name: &'a str,
    call_id: &'a str,
    arguments: &'a Value,
    started: Instant,
}

struct HostDispatchSpec {
    definitions: Vec<ToolDefinition>,
    label: &'static str,
    error_code: &'static str,
}

impl ToolRegistry {
    pub(super) async fn dispatch_task_tools(
        &self,
        name: &str,
        call_id: &str,
        arguments: &Value,
        started: Instant,
    ) -> Option<ToolDispatchOutcome> {
        let tasks = self.task_tools.as_ref()?;
        if !tasks.handles(name) {
            return None;
        }
        Some(
            self.dispatch_scoped_host_tool(
                HostDispatchCall {
                    name,
                    call_id,
                    arguments,
                    started,
                },
                HostDispatchSpec {
                    definitions: tasks.definitions(),
                    label: "Task",
                    error_code: "task_error",
                },
                |arguments| tasks.execute(name, arguments),
            )
            .await,
        )
    }

    pub(super) async fn dispatch_automation_tools(
        &self,
        name: &str,
        call_id: &str,
        arguments: &Value,
        started: Instant,
    ) -> Option<ToolDispatchOutcome> {
        let automation = self.automation_tools.as_ref()?;
        if !automation.handles(name) {
            return None;
        }
        Some(
            self.dispatch_scoped_host_tool(
                HostDispatchCall {
                    name,
                    call_id,
                    arguments,
                    started,
                },
                HostDispatchSpec {
                    definitions: automation.definitions(),
                    label: "Automation",
                    error_code: "automation_error",
                },
                |arguments| automation.execute(name, arguments),
            )
            .await,
        )
    }

    pub(super) async fn dispatch_structured_content_tools(
        &self,
        name: &str,
        call_id: &str,
        arguments: &Value,
        started: Instant,
    ) -> Option<ToolDispatchOutcome> {
        let structured = self.structured_content_tools.as_ref()?;
        if !structured.handles(name) {
            return None;
        }
        Some(
            self.dispatch_scoped_host_tool(
                HostDispatchCall {
                    name,
                    call_id,
                    arguments,
                    started,
                },
                HostDispatchSpec {
                    definitions: structured.definitions(),
                    label: "Structured content",
                    error_code: "structured_content_error",
                },
                |arguments| structured.execute(name, arguments),
            )
            .await,
        )
    }

    pub(super) async fn dispatch_attachment_tools(
        &self,
        name: &str,
        call_id: &str,
        arguments: &Value,
        started: Instant,
    ) -> Option<ToolDispatchOutcome> {
        let attachments = self.attachment_tools.as_ref()?;
        if !attachments.handles(name) {
            return None;
        }
        Some(
            self.dispatch_scoped_host_tool(
                HostDispatchCall {
                    name,
                    call_id,
                    arguments,
                    started,
                },
                HostDispatchSpec {
                    definitions: attachments.definitions(),
                    label: "Attachment",
                    error_code: "attachment_error",
                },
                |arguments| attachments.execute(name, arguments),
            )
            .await,
        )
    }

    async fn dispatch_scoped_host_tool<F, Fut>(
        &self,
        call: HostDispatchCall<'_>,
        spec: HostDispatchSpec,
        execute: F,
    ) -> ToolDispatchOutcome
    where
        F: FnOnce(Value) -> Fut,
        Fut: Future<Output = anyhow::Result<Value>>,
    {
        let Some(definition) = spec
            .definitions
            .into_iter()
            .find(|definition| definition.name == call.name)
        else {
            return ToolDispatchOutcome::unobserved(registry_failure(
                call.name,
                call.call_id,
                "unknown_tool",
                format!("{} host tool definition is unavailable", spec.label),
                false,
                registry_metadata(call.started),
            ));
        };
        if !permission_allowed(self.mode, self.command_mode, definition.permission) {
            return ToolDispatchOutcome::unobserved(registry_failure(
                call.name,
                call.call_id,
                "permission_denied",
                format!("{} host tool is not allowed by runtime policy", spec.label),
                false,
                registry_metadata(call.started),
            ));
        }
        let result = match execute(call.arguments.clone()).await {
            Ok(value) => ToolResult::success(
                call.name,
                call.call_id,
                value,
                registry_metadata(call.started),
            ),
            Err(error) => registry_failure(
                call.name,
                call.call_id,
                spec.error_code,
                error.to_string(),
                false,
                registry_metadata(call.started),
            ),
        };
        ToolDispatchOutcome::unobserved(result)
    }
}
