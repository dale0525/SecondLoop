use super::{
    AgentAppRuntimePolicy, AppNetworkPolicy, ExternalSideEffectPolicy, ExternalToolConfig,
    RuntimeToolBinding, ToolDefinition, ToolDiscoveryItem, ToolPermission, ToolPersistence,
    ToolRegistry, ToolSource, Value,
};
use serde::Serialize;
use std::collections::BTreeMap;

pub(super) fn runtime_tool_definition(
    binding: &RuntimeToolBinding,
    name: String,
) -> ToolDefinition {
    let namespace = match &binding.source {
        ToolSource::RuntimeSkill { package_id, .. } => Some(package_id.clone()),
        _ => None,
    };
    ToolDefinition {
        name,
        namespace,
        description: binding.tool.description.clone(),
        input_schema: binding.tool.input_schema.clone(),
        output_schema: None,
        permission: binding.tool.permission,
        persistence: ToolPersistence::for_permission(binding.tool.permission),
        source: binding.source.clone(),
    }
}

pub(super) fn external_definitions(
    tools: &[ExternalToolConfig],
) -> anyhow::Result<Vec<ToolDefinition>> {
    tools
        .iter()
        .filter_map(|tool| tool.tool_definition().transpose())
        .collect()
}

pub(super) fn external_discovery(
    tools: &[ExternalToolConfig],
) -> anyhow::Result<Vec<ToolDiscoveryItem>> {
    tools
        .iter()
        .map(ExternalToolConfig::discovery_summary)
        .collect()
}

pub(super) fn app_policy_allows_discovery(
    policy: &AgentAppRuntimePolicy,
    item: &ToolDiscoveryItem,
) -> bool {
    app_policy_allows_tool(
        policy,
        &ToolDefinition {
            name: item.name.clone(),
            namespace: item.namespace.clone(),
            description: item.description.clone(),
            input_schema: Value::Null,
            output_schema: None,
            permission: item.permission,
            persistence: ToolPersistence::for_permission(item.permission),
            source: item.source.clone(),
        },
    )
}

pub(super) fn app_policy_allows_tool(
    policy: &AgentAppRuntimePolicy,
    definition: &ToolDefinition,
) -> bool {
    if definition.permission == ToolPermission::ExecuteCommand
        && policy.network() != AppNetworkPolicy::Unrestricted
    {
        return false;
    }
    if !matches!(definition.source, ToolSource::BuiltIn)
        && !policy.declares_runtime_tool(&definition.name)
    {
        return false;
    }
    if policy.external_side_effects() == ExternalSideEffectPolicy::Deny
        && tool_has_external_side_effect(definition)
    {
        return false;
    }
    match &definition.source {
        ToolSource::RuntimeSkill { .. } => policy.network() == AppNetworkPolicy::Unrestricted,
        ToolSource::Mcp { server } => {
            policy.network() != AppNetworkPolicy::Deny && policy.declares_connector(server)
        }
        ToolSource::AppConnector { connector } => {
            policy.network() != AppNetworkPolicy::Deny && policy.declares_connector(connector)
        }
        ToolSource::HostCapability { capability }
            if capability == "agentweave.host.automation/v1" =>
        {
            policy.background_execution()
                != crate::app_manifest::BackgroundExecutionPolicy::Disabled
        }
        ToolSource::HostCapability { capability }
            if capability == "agentweave.host.structured-content/v1" =>
        {
            true
        }
        ToolSource::HostCapability { capability } => {
            policy.network() == AppNetworkPolicy::Unrestricted
                || matches!(
                    capability.as_str(),
                    "agentweave.host.memory/v1"
                        | "agentweave.host.tasks/v1"
                        | "agentweave.host.attachments/v1"
                        | "agentweave.foundation.mail/v1"
                )
        }
        ToolSource::BuiltIn => true,
    }
}

pub(super) fn tool_has_external_side_effect(definition: &ToolDefinition) -> bool {
    definition.permission == ToolPermission::ExternalWrite
        || (definition.permission == ToolPermission::DestructiveWrite
            && matches!(
                definition.source,
                ToolSource::RuntimeSkill { .. }
                    | ToolSource::Mcp { .. }
                    | ToolSource::AppConnector { .. }
            ))
}

pub(super) fn serialized_len<T: Serialize>(value: &T) -> usize {
    serde_json::to_vec(value)
        .map(|bytes| bytes.len())
        .unwrap_or(usize::MAX)
}

impl ToolRegistry {
    pub(super) fn non_management_definitions(&self) -> Vec<ToolDefinition> {
        let mut definitions = self.unfiltered_non_management_definitions();
        if let Some(policy) = &self.agent_app_policy {
            definitions.retain(|definition| app_policy_allows_tool(policy, definition));
        }
        definitions
    }

    pub(super) fn unfiltered_non_management_definitions(&self) -> Vec<ToolDefinition> {
        let mut definitions = if self.built_in_tools_enabled {
            self.builtins.definitions()
        } else {
            Vec::new()
        };
        definitions.extend(self.external_definitions.clone());
        if let Some(memory) = &self.memory {
            definitions.extend(memory.definitions());
        }
        if let Some(tasks) = &self.task_tools {
            definitions.extend(tasks.definitions());
        }
        if let Some(automation) = &self.automation_tools {
            definitions.extend(automation.definitions());
        }
        if let Some(structured) = &self.structured_content_tools {
            definitions.extend(structured.definitions());
        }
        if let Some(attachments) = &self.attachment_tools {
            definitions.extend(attachments.definitions());
        }
        if let Some(connectors) = &self.connector_tools {
            definitions.extend(self.foundation_connector_definitions(connectors));
        }
        if self.mail_actions.is_some() {
            definitions.push(super::foundation_actions::mail_send_preview_definition());
        }

        let mut runtime_tools = self.skills.tools_with_runtime_sources();
        runtime_tools.sort_by(|left, right| left.canonical_id.cmp(&right.canonical_id));
        let mut local_counts = BTreeMap::<String, usize>::new();
        for binding in &runtime_tools {
            *local_counts.entry(binding.local_name.clone()).or_default() += 1;
            definitions.push(runtime_tool_definition(
                binding,
                binding.canonical_id.clone(),
            ));
        }
        for binding in runtime_tools {
            if local_counts.get(&binding.local_name) == Some(&1)
                && !self.runtime_alias_is_shadowed(&binding.local_name)
            {
                definitions.push(runtime_tool_definition(
                    &binding,
                    binding.local_name.clone(),
                ));
            }
        }
        if self.commands_blocked_by_exclusions {
            definitions
                .retain(|definition| definition.permission != ToolPermission::ExecuteCommand);
        }
        definitions
    }
}
