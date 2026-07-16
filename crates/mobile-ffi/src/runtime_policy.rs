use super::MobileRuntime;
use agent_runtime::app_manifest::ExternalSideEffectPolicy;
use agent_runtime::prompt_composer::AppPromptConfig;
use agent_runtime::tools::RuntimeConfig;
use anyhow::Result;

impl MobileRuntime {
    pub(super) fn ensure_background_execution_allowed(&self) -> Result<()> {
        if !background_execution_allowed(&self.runtime_config, &self.app_prompt) {
            anyhow::bail!("background execution is denied by the active Agent App policy");
        }
        Ok(())
    }

    pub(super) fn ensure_external_side_effect_allowed(&self) -> Result<()> {
        if !external_side_effect_allowed(&self.runtime_config) {
            anyhow::bail!("external side effects are denied by the active Agent App policy");
        }
        Ok(())
    }
}

fn external_side_effect_allowed(runtime_config: &RuntimeConfig) -> bool {
    runtime_config
        .agent_app_policy
        .as_ref()
        .is_none_or(|policy| policy.external_side_effects() != ExternalSideEffectPolicy::Deny)
}

fn background_execution_allowed(
    runtime_config: &RuntimeConfig,
    app_prompt: &AppPromptConfig,
) -> bool {
    let declared = app_prompt
        .identity
        .enabled_capabilities
        .iter()
        .any(|capability| capability == "scheduler");
    runtime_config
        .agent_app_policy
        .as_ref()
        .is_none_or(|policy| policy.allows_background_execution(declared, true))
}

#[cfg(test)]
mod tests {
    use super::*;
    use agent_runtime::app_definition::AgentAppRuntimePolicy;
    use agent_runtime::app_manifest::AgentAppManifest;

    fn policy(background: &str) -> AgentAppRuntimePolicy {
        let manifest = serde_json::json!({
            "schemaVersion": 1,
            "appId": "com.example.mobile-policy",
            "package": {"id": "com.example.mobile-policy.app", "version": "0.1.0"},
            "requires": {"packages": [], "capabilities": [], "runtimeTools": [], "connectors": []},
            "features": [],
            "policy": {
                "externalSideEffects": "deny",
                "network": "deny",
                "backgroundExecution": background,
                "memoryPersistence": "disabled",
                "skillManagement": "disabled"
            },
            "branding": {"displayName": "Mobile Policy"},
            "instructions": {"system": "prompts/system.md"}
        });
        let manifest =
            AgentAppManifest::parse_json(&serde_json::to_vec(&manifest).unwrap()).unwrap();
        AgentAppRuntimePolicy::compile(&manifest)
    }

    #[test]
    fn mobile_background_host_calls_obey_the_compiled_app_policy() {
        let mut prompt = AppPromptConfig::default();
        prompt
            .identity
            .enabled_capabilities
            .push("scheduler".into());
        let disabled =
            RuntimeConfig::workspace_write(".", ".").with_agent_app_policy(policy("disabled"));
        assert!(!background_execution_allowed(&disabled, &prompt));

        let declared =
            RuntimeConfig::workspace_write(".", ".").with_agent_app_policy(policy("declared_only"));
        assert!(background_execution_allowed(&declared, &prompt));
        prompt.identity.enabled_capabilities.clear();
        assert!(!background_execution_allowed(&declared, &prompt));
        assert!(!external_side_effect_allowed(&disabled));
    }
}
