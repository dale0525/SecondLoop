use agent_runtime::app_definition::AgentAppRuntimeInventory;
use agent_runtime::mobile_host::MobileRuntimeInit;
use agent_runtime::skill_manager::SkillManager;
use agent_runtime::tools::RuntimeConfig;

pub(crate) fn runtime_inventory(
    skill_manager: &SkillManager,
    init: &MobileRuntimeInit,
    runtime_config: &RuntimeConfig,
) -> anyhow::Result<AgentAppRuntimeInventory> {
    let snapshot = skill_manager.current_snapshot();
    Ok(AgentAppRuntimeInventory {
        runtime_version: env!("CARGO_PKG_VERSION").parse()?,
        platform: init.platform,
        packages: snapshot
            .packages()
            .iter()
            .map(|resolved| {
                (
                    resolved.package.descriptor.id.as_str().to_string(),
                    resolved.package.descriptor.version.clone(),
                )
            })
            .collect(),
        providers: [
            (
                identity_oidc::OIDC_IDENTITY_PROVIDER_ID.to_string(),
                env!("CARGO_PKG_VERSION").parse()?,
            ),
            (
                entitlement_providers::HTTP_ENTITLEMENT_PROVIDER_ID.to_string(),
                env!("CARGO_PKG_VERSION").parse()?,
            ),
            (
                entitlement_providers::STATIC_ENTITLEMENT_PROVIDER_ID.to_string(),
                env!("CARGO_PKG_VERSION").parse()?,
            ),
            (
                entitlement_providers::STRIPE_PROJECTION_PROVIDER_ID.to_string(),
                env!("CARGO_PKG_VERSION").parse()?,
            ),
        ]
        .into_iter()
        .collect(),
        capabilities: init.capabilities.names().iter().cloned().collect(),
        runtime_tools: snapshot
            .registry()
            .tools()
            .iter()
            .map(|tool| tool.name.clone())
            .chain(
                agent_runtime::memory_tools::MEMORY_TOOL_NAMES
                    .into_iter()
                    .chain(agent_runtime::mail_connector_transport::MAIL_TOOL_NAMES)
                    .map(str::to_string),
            )
            .collect(),
        connectors: runtime_config
            .connectors
            .iter()
            .map(|connector| connector.id.clone())
            .chain([agent_runtime::mail_connector_transport::MAIL_CONNECTOR_ID.to_string()])
            .collect(),
    })
}
