pub struct AppFoundationRuntimes {
    pub memory_tools: Option<agent_runtime::memory_tools::MemoryToolRuntime>,
    pub task_tools: Option<agent_runtime::task_tools::TaskToolRuntime>,
    pub automation_tools: Option<agent_runtime::automation_tools::AutomationToolRuntime>,
    pub connector_tools: Option<agent_runtime::connector_tools::ConnectorToolRuntime>,
}

impl AppFoundationRuntimes {
    pub fn new(
        memory_tools: Option<agent_runtime::memory_tools::MemoryToolRuntime>,
        task_tools: Option<agent_runtime::task_tools::TaskToolRuntime>,
        connector_tools: Option<agent_runtime::connector_tools::ConnectorToolRuntime>,
    ) -> Self {
        Self {
            memory_tools,
            task_tools,
            automation_tools: None,
            connector_tools,
        }
    }

    pub fn with_automation_tools(
        mut self,
        automation_tools: Option<agent_runtime::automation_tools::AutomationToolRuntime>,
    ) -> Self {
        self.automation_tools = automation_tools;
        self
    }
}
