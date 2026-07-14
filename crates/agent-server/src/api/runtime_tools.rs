use super::*;

impl AppState {
    pub(crate) fn configured_tool_registry(&self) -> anyhow::Result<ToolRegistry> {
        let mut registry = ToolRegistry::try_new(self.skills(), &self.runtime_config)?;
        if let Some(memory) = &self.memory_tools {
            registry = registry.try_with_memory_tools(memory.clone())?;
        }
        if let Some(tasks) = &self.task_tools {
            registry = registry.try_with_task_tools(tasks.clone())?;
        }
        if let Some(automation) = &self.automation_tools {
            registry = registry.try_with_automation_tools(automation.clone())?;
        }
        if let Some(attachments) = &self.attachment_tools {
            registry = registry.try_with_attachment_tools(attachments.clone())?;
        }
        if let Some(connectors) = &self.connector_tools {
            registry = registry.try_with_connector_tools(connectors.clone())?;
        }
        Ok(registry)
    }

    pub(crate) fn memory_tools(&self) -> Option<agent_runtime::memory_tools::MemoryToolRuntime> {
        self.memory_tools.clone()
    }

    pub(crate) fn task_tools(&self) -> Option<agent_runtime::task_tools::TaskToolRuntime> {
        self.task_tools.clone()
    }

    pub(crate) fn automation_tools(
        &self,
    ) -> Option<agent_runtime::automation_tools::AutomationToolRuntime> {
        self.automation_tools.clone()
    }

    pub(crate) fn attachment_tools(
        &self,
    ) -> Option<agent_runtime::attachment_tools::AttachmentToolRuntime> {
        self.attachment_tools.clone()
    }

    pub fn has_automation_tools(&self) -> bool {
        self.automation_tools.is_some()
    }

    pub(crate) fn connector_tools(
        &self,
    ) -> Option<agent_runtime::connector_tools::ConnectorToolRuntime> {
        self.connector_tools.clone()
    }
}
