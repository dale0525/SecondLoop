use super::*;

impl ToolRegistry {
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
