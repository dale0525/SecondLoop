use super::*;

impl ToolRegistry {
    pub fn try_with_memory_tools(
        mut self,
        memory: crate::memory_tools::MemoryToolRuntime,
    ) -> anyhow::Result<Self> {
        self.memory = Some(memory);
        self.validate()
    }

    pub fn try_with_task_tools(
        mut self,
        tasks: crate::task_tools::TaskToolRuntime,
    ) -> anyhow::Result<Self> {
        self.task_tools = Some(tasks);
        self.validate()
    }

    pub fn try_with_automation_tools(
        mut self,
        automation: crate::automation_tools::AutomationToolRuntime,
    ) -> anyhow::Result<Self> {
        self.automation_tools = Some(automation);
        self.validate()
    }

    pub fn try_with_attachment_tools(
        mut self,
        attachments: crate::attachment_tools::AttachmentToolRuntime,
    ) -> anyhow::Result<Self> {
        self.attachment_tools = Some(attachments);
        self.validate()
    }

    pub fn try_with_connector_tools(
        mut self,
        connectors: crate::connector_tools::ConnectorToolRuntime,
    ) -> anyhow::Result<Self> {
        self.connector_tools = Some(connectors);
        self.validate()
    }

    pub fn try_with_mail_actions(
        mut self,
        actions: crate::foundation_actions::MailActionService,
        context: Option<crate::foundation_actions::FoundationActionTurnContext>,
    ) -> anyhow::Result<Self> {
        self.mail_actions = Some(actions);
        self.foundation_action_context = context;
        self.validate()
    }

    pub fn parallel_safe(&self, name: &str) -> bool {
        if self
            .task_tools
            .as_ref()
            .is_some_and(|tasks| tasks.parallel_safe(name))
        {
            return true;
        }
        if self
            .automation_tools
            .as_ref()
            .is_some_and(|automation| automation.parallel_safe(name))
        {
            return true;
        }
        if self
            .attachment_tools
            .as_ref()
            .is_some_and(|attachments| attachments.parallel_safe(name))
        {
            return true;
        }
        if self
            .connector_tools
            .as_ref()
            .is_some_and(|connectors| connectors.parallel_safe(name))
        {
            return true;
        }
        self.definitions().into_iter().any(|definition| {
            definition.name == name
                && definition.permission == ToolPermission::ReadWorkspace
                && matches!(definition.source, ToolSource::BuiltIn)
        })
    }

    pub(super) fn runtime_timeout_attribution(
        &self,
        name: &str,
    ) -> Option<ToolExecutionAttribution> {
        if (self.built_in_tools_enabled && BuiltInTools::handles(name))
            || self
                .memory
                .as_ref()
                .is_some_and(|memory| memory.handles(name))
            || self
                .task_tools
                .as_ref()
                .is_some_and(|tasks| tasks.handles(name))
            || self
                .automation_tools
                .as_ref()
                .is_some_and(|automation| automation.handles(name))
            || self
                .attachment_tools
                .as_ref()
                .is_some_and(|attachments| attachments.handles(name))
            || self
                .connector_tools
                .as_ref()
                .is_some_and(|connectors| connectors.handles(name))
            || self.external_tool(name).is_some()
        {
            return None;
        }
        let binding = self.resolve_runtime_binding(name)?;
        if !permission_allowed(self.mode, self.command_mode, binding.tool.permission) {
            return None;
        }
        Some(ToolExecutionAttribution {
            source: binding.source,
            success: false,
        })
    }

    pub(super) fn resolve_runtime_binding(&self, name: &str) -> Option<RuntimeToolBinding> {
        let binding = self.skills.resolve_runtime_tool(name)?;
        if binding.canonical_id != name && self.runtime_alias_is_shadowed(name) {
            return None;
        }
        Some(binding)
    }

    pub(super) fn runtime_alias_is_shadowed(&self, name: &str) -> bool {
        SkillManagementTools::is_reserved_name(name)
            || (self.built_in_tools_enabled && BuiltInTools::handles(name))
            || self
                .memory
                .as_ref()
                .is_some_and(|memory| memory.handles(name))
            || self
                .task_tools
                .as_ref()
                .is_some_and(|tasks| tasks.handles(name))
            || self
                .automation_tools
                .as_ref()
                .is_some_and(|automation| automation.handles(name))
            || self
                .attachment_tools
                .as_ref()
                .is_some_and(|attachments| attachments.handles(name))
            || self
                .connector_tools
                .as_ref()
                .is_some_and(|connectors| connectors.handles(name))
            || self.external_tool(name).is_some()
            || self
                .skills
                .tools_with_runtime_sources()
                .iter()
                .any(|binding| binding.canonical_id == name)
    }
}
