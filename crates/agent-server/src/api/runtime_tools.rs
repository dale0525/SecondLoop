use super::*;

impl AppState {
    pub(crate) fn memory_tools_for(
        &self,
        request: &crate::identity_api::RequestSecurityContext,
    ) -> anyhow::Result<Option<agent_runtime::memory_tools::MemoryToolRuntime>> {
        self.memory_tools
            .as_ref()
            .map(|runtime| runtime.for_scope(request.memory_scope()?))
            .transpose()
    }

    pub(crate) fn task_tools_for(
        &self,
        request: &crate::identity_api::RequestSecurityContext,
    ) -> anyhow::Result<Option<agent_runtime::task_tools::TaskToolRuntime>> {
        self.task_tools
            .as_ref()
            .map(|runtime| runtime.for_scope(request.task_scope()?))
            .transpose()
    }

    pub(crate) fn attachment_tools_for(
        &self,
        request: &crate::identity_api::RequestSecurityContext,
    ) -> anyhow::Result<Option<agent_runtime::attachment_tools::AttachmentToolRuntime>> {
        self.attachment_tools
            .as_ref()
            .map(|runtime| Ok(runtime.for_scope(request.attachment_scope()?)))
            .transpose()
    }

    pub(crate) fn automation_tools_for(
        &self,
        request: &crate::identity_api::RequestSecurityContext,
    ) -> anyhow::Result<Option<agent_runtime::automation_tools::AutomationToolRuntime>> {
        self.automation_tools
            .as_ref()
            .map(|runtime| Ok(runtime.for_scope(request.automation_scope()?)))
            .transpose()
    }

    pub(crate) fn structured_content_for(
        &self,
        request: &crate::identity_api::RequestSecurityContext,
    ) -> agent_runtime::structured_content_tools::StructuredContentToolRuntime {
        Self::new_structured_content_tools(&self.storage, request.conversation_scope())
    }

    pub(crate) fn connector_tools_for(
        &self,
        request: &crate::identity_api::RequestSecurityContext,
    ) -> anyhow::Result<Option<agent_runtime::connector_tools::ConnectorToolRuntime>> {
        let Some(runtime) = &self.connector_tools else {
            return Ok(None);
        };
        if !request.is_authenticated() {
            return Ok(Some(runtime.clone()));
        }
        let provider =
            agent_runtime::connector_tools::EphemeralConnectorContextProvider::fail_closed(
                request.credential_scope(),
                std::time::Duration::from_secs(30),
            )?;
        Ok(Some(
            runtime.with_context_provider(std::sync::Arc::new(provider)),
        ))
    }

    pub(crate) async fn oauth_broker_for(
        &self,
        request: &crate::identity_api::RequestSecurityContext,
    ) -> anyhow::Result<Option<agent_runtime::oauth::OAuthBroker>> {
        let Some(broker) = &self.oauth_broker else {
            return Ok(None);
        };
        if !request.is_authenticated() {
            return Ok(Some(broker.clone()));
        }
        broker.for_scope(request.credential_scope()).await.map(Some)
    }

    pub(super) fn new_structured_content_tools(
        storage: &Storage,
        scope: &ConversationScope,
    ) -> agent_runtime::structured_content_tools::StructuredContentToolRuntime {
        let service = agent_runtime::structured_content_store::StructuredContentService::new(
            storage.clone(),
            scope.clone(),
            scope.agent_id.clone(),
        )
        .expect("App conversation scope must support structured content");
        agent_runtime::structured_content_tools::StructuredContentToolRuntime::new(service)
    }

    #[cfg(test)]
    pub(crate) fn structured_content(
        &self,
    ) -> agent_runtime::structured_content_store::StructuredContentService {
        self.structured_content_tools.service()
    }

    pub fn with_data_protection(
        mut self,
        database_path: impl Into<std::path::PathBuf>,
        key: agent_runtime::credential::SecretMaterial,
    ) -> anyhow::Result<Self> {
        if !self
            .app_prompt
            .identity
            .enabled_capabilities
            .iter()
            .any(|capability| capability == "data-protection")
        {
            return Ok(self);
        }
        self.data_protection = Some(crate::data_protection::DataProtectionService::new(
            self.storage.clone(),
            database_path,
            &self.app_prompt.identity.app_id,
            &key,
        )?);
        Ok(self)
    }

    pub fn with_borrowed_data_protection(
        mut self,
        database_path: impl Into<std::path::PathBuf>,
        key: &agent_runtime::credential::SecretMaterial,
    ) -> anyhow::Result<Self> {
        if !self
            .app_prompt
            .identity
            .enabled_capabilities
            .iter()
            .any(|capability| capability == "data-protection")
        {
            return Ok(self);
        }
        self.data_protection = Some(crate::data_protection::DataProtectionService::new(
            self.storage.clone(),
            database_path,
            &self.app_prompt.identity.app_id,
            key,
        )?);
        Ok(self)
    }

    #[cfg(test)]
    pub fn with_test_data_protection(
        mut self,
        database_path: impl Into<std::path::PathBuf>,
        key: agent_runtime::credential::SecretMaterial,
    ) -> anyhow::Result<Self> {
        self.data_protection = Some(crate::data_protection::DataProtectionService::new(
            self.storage.clone(),
            database_path,
            &self.app_prompt.identity.app_id,
            &key,
        )?);
        Ok(self)
    }

    pub(crate) fn data_protection(&self) -> Option<&crate::data_protection::DataProtectionService> {
        self.data_protection.as_ref()
    }

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
        registry =
            registry.try_with_structured_content_tools(self.structured_content_tools.clone())?;
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

    pub fn has_automation_tools(&self) -> bool {
        self.automation_tools.is_some()
    }

    pub fn allows_background_execution(&self, enabled_by_host: bool) -> bool {
        self.runtime_config.agent_app_policy.as_ref().map_or(
            self.has_automation_tools() || enabled_by_host,
            |policy| {
                policy.allows_background_execution(self.has_automation_tools(), enabled_by_host)
            },
        )
    }

    pub fn allows_automation_api(&self, enabled_by_host: bool) -> bool {
        self.runtime_config.agent_app_policy.is_none()
            || self.allows_background_execution(enabled_by_host)
    }

    pub(crate) fn connector_tools(
        &self,
    ) -> Option<agent_runtime::connector_tools::ConnectorToolRuntime> {
        if self.identity_runtime().is_some() {
            return None;
        }
        self.connector_tools.clone()
    }
}
