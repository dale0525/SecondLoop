use crate::app_manifest::{
    AgentAppEntitlementConfiguration, AgentAppIdentityConfiguration, AgentAppManifest,
    AgentAppModelAccess, AgentAppModelAuthentication, AgentAppModelConfigurationPolicy,
    AgentAppPolicy, AppNetworkPolicy, AppSkillManagementPolicy, BackgroundExecutionPolicy,
    ExternalSideEffectPolicy, LoadedAgentAppManifest, MemoryPersistencePolicy,
};
use crate::entitlement::EntitlementMode;
use crate::identity::IdentityMode;
use crate::model_access::{
    ModelAccessPolicy, ModelAccessProfile, ModelAuthentication, ModelConfigurationPolicy,
};
use crate::platform::PlatformId;
use crate::prompt_composer::AppPromptConfig;
use semver::Version;
use serde::{Deserialize, Serialize};
use std::collections::{BTreeMap, BTreeSet};
use std::path::Path;

pub const AGENT_APP_HOST_DISCOVERY_SCHEMA_VERSION: u32 = 2;

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct AgentAppRuntimeInventory {
    pub runtime_version: Version,
    pub platform: PlatformId,
    pub packages: BTreeMap<String, Version>,
    pub providers: BTreeMap<String, Version>,
    pub capabilities: BTreeSet<String>,
    pub runtime_tools: BTreeSet<String>,
    pub connectors: BTreeSet<String>,
}

#[derive(Clone, Debug)]
pub struct ResolvedAgentApp {
    pub loaded: LoadedAgentAppManifest,
    pub prompt: AppPromptConfig,
    host_discovery: AgentAppHostDiscovery,
    runtime_policy: AgentAppRuntimePolicy,
}

/// A fail-closed dispatch policy compiled from one validated App manifest.
/// Restricted network modes deny process-capable tools; they do not claim OS-level isolation.
#[derive(Clone, Debug, Deserialize, Serialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct AgentAppRuntimePolicy {
    external_side_effects: ExternalSideEffectPolicy,
    network: AppNetworkPolicy,
    background_execution: BackgroundExecutionPolicy,
    memory_persistence: MemoryPersistencePolicy,
    skill_management: AppSkillManagementPolicy,
    model_access: ModelAccessPolicy,
    identity: AgentAppIdentityConfiguration,
    entitlements: AgentAppEntitlementConfiguration,
    declared_runtime_tools: BTreeSet<String>,
    declared_connectors: BTreeSet<String>,
}

impl AgentAppRuntimePolicy {
    pub fn compile(manifest: &AgentAppManifest) -> Self {
        Self {
            external_side_effects: manifest.policy.external_side_effects,
            network: manifest.policy.network,
            background_execution: manifest.policy.background_execution,
            memory_persistence: manifest.policy.memory_persistence,
            skill_management: manifest.policy.skill_management,
            model_access: compile_model_access(manifest),
            identity: manifest.effective_identity(),
            entitlements: manifest.effective_entitlements(),
            declared_runtime_tools: manifest
                .requires
                .runtime_tools
                .iter()
                .map(|tool| tool.as_str().to_string())
                .collect(),
            declared_connectors: manifest
                .requires
                .connectors
                .iter()
                .map(|connector| connector.as_str().to_string())
                .collect(),
        }
    }

    pub fn external_side_effects(&self) -> ExternalSideEffectPolicy {
        self.external_side_effects
    }

    pub fn network(&self) -> AppNetworkPolicy {
        self.network
    }

    pub fn background_execution(&self) -> BackgroundExecutionPolicy {
        self.background_execution
    }

    pub fn memory_persistence(&self) -> MemoryPersistencePolicy {
        self.memory_persistence
    }

    pub fn skill_management(&self) -> AppSkillManagementPolicy {
        self.skill_management
    }

    pub fn model_access(&self) -> &ModelAccessPolicy {
        &self.model_access
    }

    pub fn identity(&self) -> &AgentAppIdentityConfiguration {
        &self.identity
    }

    pub fn entitlements(&self) -> &AgentAppEntitlementConfiguration {
        &self.entitlements
    }

    pub fn allows_user_model_configuration(&self) -> bool {
        self.model_access.configuration_policy == ModelConfigurationPolicy::UserConfigurable
    }

    pub fn declares_runtime_tool(&self, tool: &str) -> bool {
        self.declared_runtime_tools.contains(tool)
    }

    pub fn declares_connector(&self, connector: &str) -> bool {
        self.declared_connectors.contains(connector)
    }

    pub fn allows_background_execution(
        &self,
        declared_by_app: bool,
        enabled_by_host: bool,
    ) -> bool {
        match self.background_execution {
            BackgroundExecutionPolicy::Disabled => false,
            BackgroundExecutionPolicy::DeclaredOnly => declared_by_app,
            BackgroundExecutionPolicy::Enabled => declared_by_app || enabled_by_host,
        }
    }
}

fn compile_model_access(manifest: &AgentAppManifest) -> ModelAccessPolicy {
    let access = manifest.effective_model_access();
    let identity = manifest.effective_identity();
    let entitlements = manifest.effective_entitlements();
    let policy = ModelAccessPolicy {
        configuration_policy: match access.configuration_policy {
            AgentAppModelConfigurationPolicy::UserConfigurable => {
                ModelConfigurationPolicy::UserConfigurable
            }
            AgentAppModelConfigurationPolicy::AppManaged => ModelConfigurationPolicy::AppManaged,
        },
        profile: access.profile.map(|profile| ModelAccessProfile {
            provider_id: profile.provider_id.as_str().to_string(),
            endpoint_type: profile.endpoint_type,
            base_url: profile.base_url,
            model_name: profile.model_name,
            authentication: match profile.authentication {
                AgentAppModelAuthentication::None => ModelAuthentication::None,
                AgentAppModelAuthentication::UserIdentity => ModelAuthentication::UserIdentity,
            },
            headers: profile.headers,
        }),
        identity_mode: match identity.mode {
            crate::app_manifest::AgentAppIdentityMode::LocalSingleUser => {
                IdentityMode::LocalSingleUser
            }
            crate::app_manifest::AgentAppIdentityMode::Required => IdentityMode::Required,
        },
        entitlement_mode: match entitlements.mode {
            crate::app_manifest::AgentAppEntitlementMode::Disabled => EntitlementMode::Disabled,
            crate::app_manifest::AgentAppEntitlementMode::Required => EntitlementMode::Required,
        },
    };
    debug_assert!(policy.validate().is_ok());
    policy
}

#[derive(Clone, Debug, Deserialize, Serialize, PartialEq, Eq)]
pub struct AgentAppDiagnostics {
    pub app_id: String,
    pub version: String,
    pub display_name: String,
    pub manifest_sha256: String,
}

#[derive(Clone, Debug, Deserialize, Serialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct AgentAppHostIdentity {
    pub app_id: String,
    pub package_id: String,
    pub version: String,
    pub display_name: String,
    pub short_name: Option<String>,
    pub description: Option<String>,
    pub accent_color: Option<String>,
}

#[derive(Clone, Debug, Deserialize, Serialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct AgentAppHostPackageRequirement {
    pub id: String,
    pub version: String,
}

#[derive(Clone, Debug, Deserialize, Serialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct AgentAppHostRequirements {
    pub packages: Vec<AgentAppHostPackageRequirement>,
    pub capabilities: BTreeSet<String>,
    pub runtime_tools: BTreeSet<String>,
    pub connectors: BTreeSet<String>,
}

#[derive(Clone, Debug, Deserialize, Serialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct AgentAppHostAccessConfiguration {
    pub model_access: AgentAppModelAccess,
    pub identity: AgentAppIdentityConfiguration,
    pub entitlements: AgentAppEntitlementConfiguration,
}

#[derive(Clone, Debug, Deserialize, Serialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct AgentAppHostDiscovery {
    pub schema_version: u32,
    pub manifest_sha256: String,
    pub runtime_version: String,
    pub platform: PlatformId,
    pub identity: AgentAppHostIdentity,
    pub features: BTreeSet<String>,
    pub requirements: AgentAppHostRequirements,
    pub policy: AgentAppPolicy,
    pub access: AgentAppHostAccessConfiguration,
}

impl AgentAppHostDiscovery {
    pub fn declares_feature(&self, feature: &str) -> bool {
        self.features.contains(feature)
    }

    pub fn requires_package(&self, package_id: &str) -> bool {
        self.requirements
            .packages
            .iter()
            .any(|package| package.id == package_id)
    }

    pub fn requires_capability(&self, capability: &str) -> bool {
        self.requirements.capabilities.contains(capability)
    }

    pub fn requires_runtime_tool(&self, tool: &str) -> bool {
        self.requirements.runtime_tools.contains(tool)
    }

    pub fn requires_connector(&self, connector: &str) -> bool {
        self.requirements.connectors.contains(connector)
    }

    fn from_manifest(
        manifest: &AgentAppManifest,
        manifest_sha256: &str,
        inventory: &AgentAppRuntimeInventory,
    ) -> Self {
        Self {
            schema_version: AGENT_APP_HOST_DISCOVERY_SCHEMA_VERSION,
            manifest_sha256: manifest_sha256.to_string(),
            runtime_version: inventory.runtime_version.to_string(),
            platform: inventory.platform,
            identity: AgentAppHostIdentity {
                app_id: manifest.app_id.as_str().to_string(),
                package_id: manifest.package.id.as_str().to_string(),
                version: manifest.package.version.to_string(),
                display_name: manifest.branding.display_name.clone(),
                short_name: manifest.branding.short_name.clone(),
                description: manifest.branding.description.clone(),
                accent_color: manifest.branding.accent_color.clone(),
            },
            features: manifest
                .features
                .iter()
                .map(|feature| feature.as_str().to_string())
                .collect(),
            requirements: AgentAppHostRequirements {
                packages: manifest
                    .requires
                    .packages
                    .iter()
                    .map(|package| AgentAppHostPackageRequirement {
                        id: package.id.as_str().to_string(),
                        version: package.version.to_string(),
                    })
                    .collect(),
                capabilities: manifest
                    .requires
                    .capabilities
                    .iter()
                    .map(|capability| capability.as_str().to_string())
                    .collect(),
                runtime_tools: manifest
                    .requires
                    .runtime_tools
                    .iter()
                    .map(|tool| tool.as_str().to_string())
                    .collect(),
                connectors: manifest
                    .requires
                    .connectors
                    .iter()
                    .map(|connector| connector.as_str().to_string())
                    .collect(),
            },
            policy: manifest.policy.clone(),
            access: AgentAppHostAccessConfiguration {
                model_access: manifest.effective_model_access(),
                identity: manifest.effective_identity(),
                entitlements: manifest.effective_entitlements(),
            },
        }
    }
}

impl ResolvedAgentApp {
    pub async fn load(
        root: &Path,
        inventory: &AgentAppRuntimeInventory,
        max_prompt_resource_bytes: usize,
    ) -> anyhow::Result<Self> {
        let loaded = AgentAppManifest::load(root).await?;
        validate_app_compatibility(&loaded.manifest, inventory)?;
        let prompt =
            AppPromptConfig::from_loaded_manifest(&loaded, max_prompt_resource_bytes).await?;
        let host_discovery = AgentAppHostDiscovery::from_manifest(
            &loaded.manifest,
            loaded.manifest_sha256(),
            inventory,
        );
        let runtime_policy = AgentAppRuntimePolicy::compile(&loaded.manifest);
        Ok(Self {
            loaded,
            prompt,
            host_discovery,
            runtime_policy,
        })
    }

    pub fn diagnostics(&self) -> AgentAppDiagnostics {
        AgentAppDiagnostics {
            app_id: self.prompt.identity.app_id.clone(),
            version: self.prompt.identity.version.clone(),
            display_name: self.prompt.identity.display_name.clone(),
            manifest_sha256: self.loaded.manifest_sha256().to_string(),
        }
    }

    pub fn host_discovery(&self) -> &AgentAppHostDiscovery {
        &self.host_discovery
    }

    pub fn runtime_policy(&self) -> &AgentAppRuntimePolicy {
        &self.runtime_policy
    }
}

pub fn validate_app_compatibility(
    manifest: &AgentAppManifest,
    inventory: &AgentAppRuntimeInventory,
) -> anyhow::Result<()> {
    anyhow::ensure!(
        manifest.supports_platform(inventory.platform),
        "Agent App {} does not support platform {}",
        manifest.app_id.as_str(),
        platform_name(inventory.platform)
    );
    if let Some(requirement) = &manifest.compatibility.runtime {
        anyhow::ensure!(
            requirement.matches(&inventory.runtime_version),
            "Agent App requires runtime {requirement}, found {}",
            inventory.runtime_version
        );
    }
    for requirement in &manifest.requires.packages {
        let version = inventory
            .packages
            .get(requirement.id.as_str())
            .ok_or_else(|| {
                anyhow::anyhow!(
                    "required App package is unavailable: {}",
                    requirement.id.as_str()
                )
            })?;
        anyhow::ensure!(
            requirement.version.matches(version),
            "required App package {} expects {}, found {version}",
            requirement.id.as_str(),
            requirement.version
        );
    }
    for binding in [
        manifest.effective_identity().provider,
        manifest.effective_entitlements().provider,
    ]
    .into_iter()
    .flatten()
    {
        let version = inventory
            .providers
            .get(binding.id.as_str())
            .ok_or_else(|| {
                anyhow::anyhow!(
                    "required App provider is unavailable: {}",
                    binding.id.as_str()
                )
            })?;
        anyhow::ensure!(
            binding.version.matches(version),
            "required App provider {} expects {}, found {version}",
            binding.id.as_str(),
            binding.version
        );
    }
    validate_required_set(
        "capability",
        manifest
            .requires
            .capabilities
            .iter()
            .map(|item| item.as_str()),
        &inventory.capabilities,
    )?;
    validate_required_set(
        "runtime tool",
        manifest
            .requires
            .runtime_tools
            .iter()
            .map(|item| item.as_str()),
        &inventory.runtime_tools,
    )?;
    validate_required_set(
        "connector",
        manifest
            .requires
            .connectors
            .iter()
            .map(|item| item.as_str()),
        &inventory.connectors,
    )?;
    Ok(())
}

fn validate_required_set<'a>(
    label: &str,
    required: impl Iterator<Item = &'a str>,
    available: &BTreeSet<String>,
) -> anyhow::Result<()> {
    for item in required {
        anyhow::ensure!(
            available.contains(item),
            "required App {label} is unavailable: {item}"
        );
    }
    Ok(())
}

fn platform_name(platform: PlatformId) -> &'static str {
    match platform {
        PlatformId::Desktop => "desktop",
        PlatformId::Android => "android",
        PlatformId::Ios => "ios",
        PlatformId::Web => "web",
        PlatformId::Server => "server",
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::app_manifest::AgentAppManifest;

    fn manifest() -> AgentAppManifest {
        AgentAppManifest::parse_json(
            br##"{
              "schemaVersion": 1,
              "appId": "com.example.secretary",
              "package": {"id": "com.example.secretary.app", "version": "1.0.0"},
              "compatibility": {"runtime": ">=0.1.0, <1.0.0", "platforms": ["server"]},
              "requires": {
                "packages": [{"id": "agentweave.foundation.memory", "version": "^0.1"}],
                "capabilities": ["memory.read"],
                "runtimeTools": ["memory.search"],
                "connectors": ["mail.fake"]
              },
              "features": ["mail.workflows", "memory.management"],
              "policy": {
                "externalSideEffects": "require_approval",
                "network": "declared_only",
                "backgroundExecution": "disabled",
                "memoryPersistence": "local_only",
                "skillManagement": "disabled"
              },
              "branding": {
                "displayName": "Secretary",
                "shortName": "Sec",
                "description": "A bounded assistant",
                "accentColor": "#315C49"
              },
              "instructions": {"system": "prompts/system.md"}
            }"##,
        )
        .unwrap()
    }

    fn inventory_fixture() -> AgentAppRuntimeInventory {
        AgentAppRuntimeInventory {
            runtime_version: "0.1.0".parse().unwrap(),
            platform: PlatformId::Server,
            packages: BTreeMap::from([(
                "agentweave.foundation.memory".into(),
                "0.1.2".parse().unwrap(),
            )]),
            providers: BTreeMap::new(),
            capabilities: BTreeSet::from(["memory.read".into()]),
            runtime_tools: BTreeSet::from(["memory.search".into()]),
            connectors: BTreeSet::from(["mail.fake".into()]),
        }
    }

    fn managed_manifest() -> AgentAppManifest {
        let mut value = serde_json::to_value(manifest()).unwrap();
        value["schemaVersion"] = serde_json::json!(2);
        value["modelAccess"] = serde_json::json!({
            "configurationPolicy": "app_managed",
            "profile": {
                "providerId": "example.gateway",
                "endpointType": "responses",
                "baseUrl": "https://gateway.example.test/v1",
                "modelName": "managed-model",
                "authentication": "user_identity",
                "headers": {}
            }
        });
        value["identity"] = serde_json::json!({
            "mode": "required",
            "provider": {
                "id": "agentweave.identity.oidc",
                "version": "^1.0.0",
                "publicConfig": {"issuer": "https://identity.example.test"}
            }
        });
        value["entitlements"] = serde_json::json!({
            "mode": "required",
            "provider": {
                "id": "agentweave.entitlements.http",
                "version": "^1.0.0",
                "publicConfig": {"endpoint": "https://access.example.test"}
            }
        });
        AgentAppManifest::parse_json(&serde_json::to_vec(&value).unwrap()).unwrap()
    }

    #[test]
    fn compatible_inventory_is_accepted() {
        validate_app_compatibility(&manifest(), &inventory_fixture()).unwrap();
    }

    #[test]
    fn missing_or_incompatible_requirements_fail_closed() {
        let mut inventory = inventory_fixture();
        inventory.packages.clear();
        assert!(
            validate_app_compatibility(&manifest(), &inventory)
                .unwrap_err()
                .to_string()
                .contains("package")
        );
        let mut inventory = inventory_fixture();
        inventory.capabilities.clear();
        assert!(
            validate_app_compatibility(&manifest(), &inventory)
                .unwrap_err()
                .to_string()
                .contains("capability")
        );
    }

    #[test]
    fn required_access_providers_are_version_checked() {
        let manifest = managed_manifest();
        let mut inventory = inventory_fixture();

        let missing = validate_app_compatibility(&manifest, &inventory).unwrap_err();
        assert!(missing.to_string().contains("provider is unavailable"));

        inventory
            .providers
            .insert("agentweave.identity.oidc".into(), "1.2.0".parse().unwrap());
        inventory.providers.insert(
            "agentweave.entitlements.http".into(),
            "2.0.0".parse().unwrap(),
        );
        let incompatible = validate_app_compatibility(&manifest, &inventory).unwrap_err();
        assert!(incompatible.to_string().contains("expects ^1.0.0"));

        inventory.providers.insert(
            "agentweave.entitlements.http".into(),
            "1.1.0".parse().unwrap(),
        );
        validate_app_compatibility(&manifest, &inventory).unwrap();
    }

    #[test]
    fn platform_and_future_runtime_mismatches_fail_closed() {
        let mut inventory = inventory_fixture();
        inventory.platform = PlatformId::Android;
        assert!(validate_app_compatibility(&manifest(), &inventory).is_err());
        let mut inventory = inventory_fixture();
        inventory.runtime_version = "2.0.0".parse().unwrap();
        assert!(validate_app_compatibility(&manifest(), &inventory).is_err());
    }

    #[test]
    fn host_discovery_contains_only_validated_app_declarations() {
        let manifest = manifest();
        let mut inventory = inventory_fixture();
        inventory.capabilities.insert("host.unrelated".into());
        inventory.runtime_tools.insert("host.unrelated".into());
        inventory.connectors.insert("host.unrelated".into());
        validate_app_compatibility(&manifest, &inventory).unwrap();

        let discovery =
            AgentAppHostDiscovery::from_manifest(&manifest, "manifest-hash", &inventory);

        assert_eq!(
            discovery.schema_version,
            AGENT_APP_HOST_DISCOVERY_SCHEMA_VERSION
        );
        assert_eq!(discovery.manifest_sha256, "manifest-hash");
        assert_eq!(discovery.runtime_version, "0.1.0");
        assert_eq!(discovery.platform, PlatformId::Server);
        assert_eq!(discovery.identity.app_id, "com.example.secretary");
        assert_eq!(discovery.identity.package_id, "com.example.secretary.app");
        assert_eq!(discovery.identity.display_name, "Secretary");
        assert_eq!(discovery.identity.short_name.as_deref(), Some("Sec"));
        assert_eq!(discovery.identity.accent_color.as_deref(), Some("#315C49"));
        assert!(discovery.declares_feature("mail.workflows"));
        assert!(discovery.declares_feature("memory.management"));
        assert!(discovery.requires_package("agentweave.foundation.memory"));
        assert!(discovery.requires_capability("memory.read"));
        assert!(discovery.requires_runtime_tool("memory.search"));
        assert!(discovery.requires_connector("mail.fake"));
        assert!(!discovery.requires_capability("host.unrelated"));
        assert!(!discovery.requires_runtime_tool("host.unrelated"));
        assert!(!discovery.requires_connector("host.unrelated"));
        assert_eq!(
            discovery.access.model_access.configuration_policy,
            AgentAppModelConfigurationPolicy::UserConfigurable
        );
        assert_eq!(
            discovery.access.identity.mode,
            crate::app_manifest::AgentAppIdentityMode::LocalSingleUser
        );
        assert_eq!(
            discovery.access.entitlements.mode,
            crate::app_manifest::AgentAppEntitlementMode::Disabled
        );
    }

    #[test]
    fn runtime_policy_compiles_only_enforceable_manifest_declarations() {
        let policy = AgentAppRuntimePolicy::compile(&manifest());

        assert_eq!(
            policy.external_side_effects(),
            ExternalSideEffectPolicy::RequireApproval
        );
        assert_eq!(policy.network(), AppNetworkPolicy::DeclaredOnly);
        assert_eq!(
            policy.background_execution(),
            BackgroundExecutionPolicy::Disabled
        );
        assert_eq!(
            policy.memory_persistence(),
            MemoryPersistencePolicy::LocalOnly
        );
        assert_eq!(
            policy.skill_management(),
            AppSkillManagementPolicy::Disabled
        );
        assert!(policy.allows_user_model_configuration());
        assert!(policy.declares_runtime_tool("memory.search"));
        assert!(!policy.declares_runtime_tool("host.unrelated"));
        assert!(policy.declares_connector("mail.fake"));
        assert!(!policy.declares_connector("host.unrelated"));
        assert!(!policy.allows_background_execution(true, true));
    }

    #[test]
    fn host_discovery_uses_a_versioned_camel_case_wire_contract() {
        let discovery = AgentAppHostDiscovery::from_manifest(
            &manifest(),
            "manifest-hash",
            &inventory_fixture(),
        );
        let value = serde_json::to_value(&discovery).unwrap();

        assert_eq!(value["schemaVersion"], 2);
        assert_eq!(value["manifestSha256"], "manifest-hash");
        assert_eq!(value["runtimeVersion"], "0.1.0");
        assert_eq!(value["platform"], "server");
        assert_eq!(
            value["requirements"]["runtimeTools"],
            serde_json::json!(["memory.search"])
        );
        assert_eq!(
            value["access"]["modelAccess"]["configurationPolicy"],
            "user_configurable"
        );

        let round_trip: AgentAppHostDiscovery = serde_json::from_value(value.clone()).unwrap();
        assert_eq!(round_trip, discovery);
        let mut invalid = value;
        invalid["unknown"] = serde_json::json!(true);
        assert!(serde_json::from_value::<AgentAppHostDiscovery>(invalid).is_err());
    }

    #[tokio::test]
    async fn resolved_app_binds_discovery_to_the_loaded_manifest() {
        let root = tempfile::tempdir().unwrap();
        std::fs::create_dir_all(root.path().join("prompts")).unwrap();
        std::fs::write(
            root.path().join("agent-app.json"),
            manifest().canonical_json().unwrap(),
        )
        .unwrap();
        std::fs::write(root.path().join("prompts/system.md"), "Bounded assistant").unwrap();

        let resolved = ResolvedAgentApp::load(root.path(), &inventory_fixture(), 4096)
            .await
            .unwrap();

        assert_eq!(
            resolved.host_discovery().manifest_sha256,
            resolved.loaded.manifest_sha256()
        );
        assert_eq!(
            resolved.host_discovery().identity.app_id,
            resolved.prompt.identity.app_id
        );
    }
}
