use crate::api;
use agent_runtime::credential::SecretMaterial;
use agent_runtime::platform::{CapabilitySet, PlatformId};
use agent_runtime::prompt_composer::AppPromptConfig;
use agent_runtime::skill_policy::SkillManagementPolicy;
use agent_runtime::storage::Storage;
use agent_runtime::storage_protection::StorageOpenOptions;
use agent_runtime::tools::{CommandMode, RuntimeConfig};
use agent_runtime::turn::ModelClient;
use agent_server::owner_api::OwnerApiConfig;
use agent_server::tenant_skills::{
    FilesystemTenantSkillManagerFactory, TenantSkillManagerConfig, TenantSkillManagerRegistry,
    TenantSkillRuntime,
};
use std::path::{Path, PathBuf};
use std::sync::Arc;

use super::server_skill_startup::{
    BuiltinSkillsMode, ManagedSkillsConfig, load_app_package_source_from_env,
    load_builtin_skill_source,
};

const DEFAULT_SKILLS_ROOT: &str = "skills";

pub(super) fn skills_root_from_env() -> PathBuf {
    std::env::var("AGENTWEAVE_SKILLS_ROOT")
        .map(PathBuf::from)
        .unwrap_or_else(|_| PathBuf::from(DEFAULT_SKILLS_ROOT))
}

pub(super) fn runtime_config_from_env() -> RuntimeConfig {
    let workspace_root = std::env::var("AGENTWEAVE_WORKSPACE_ROOT")
        .map(PathBuf::from)
        .unwrap_or_else(|_| std::env::current_dir().unwrap_or_else(|_| PathBuf::from(".")));
    let mut config = RuntimeConfig::workspace_write(workspace_root.clone(), workspace_root)
        .without_builtin_tools();
    if std::env::var("AGENTWEAVE_COMMAND_MODE").as_deref() == Ok("allowed") {
        config = config.with_command_mode(CommandMode::Allowed);
    }
    if let Ok(app_root) = std::env::var("AGENTWEAVE_APP_ROOT") {
        config = config.excluding_workspace_roots([PathBuf::from(app_root)]);
    }
    config
}

pub(super) fn sqlite_database_path(url: &str) -> Option<PathBuf> {
    let value = url
        .strip_prefix("sqlite://")
        .or_else(|| url.strip_prefix("sqlite:"))?
        .split('?')
        .next()?;
    (!value.is_empty() && value != ":memory:").then(|| PathBuf::from(value))
}

pub(super) async fn open_storage(
    database_url: &str,
    storage_protection_key: Option<Arc<SecretMaterial>>,
) -> anyhow::Result<(Storage, Option<PathBuf>)> {
    let database_path = sqlite_database_path(database_url);
    if let Some(path) = &database_path {
        agent_server::data_protection::apply_pending_restore(path).await?;
    }
    let storage_options = storage_protection_key
        .map(|key| StorageOpenOptions::default().with_key(key))
        .unwrap_or_default();
    let storage = Storage::connect_with_options(database_url, storage_options).await?;
    Ok((storage, database_path))
}

pub(super) fn apply_storage_protection(
    state: api::AppState,
    database_path: &Option<PathBuf>,
    key: &Option<Arc<SecretMaterial>>,
) -> anyhow::Result<api::AppState> {
    match (key.as_deref(), database_path) {
        (Some(key), Some(path)) => state.with_borrowed_data_protection(path.clone(), key),
        _ => Ok(state),
    }
}

pub(super) fn apply_connector_foundation(
    state: api::AppState,
    foundation: Option<super::server_app::ResolvedConnectorFoundation>,
) -> api::AppState {
    match foundation {
        Some(foundation) => {
            let state = state.with_connector_actions(
                foundation.mail_actions,
                foundation.calendar_actions,
                foundation.contacts_actions,
            );
            let state = match foundation.oauth_broker {
                Some(broker) => state.with_oauth_broker(broker),
                None => state,
            };
            match foundation.account_manager {
                Some(manager) => state.with_mail_account_manager(manager),
                None => state,
            }
        }
        None => state,
    }
}

pub(super) async fn build_managed_tenant_registry(
    skills_root: &Path,
    managed: ManagedSkillsConfig,
    builtin_mode: BuiltinSkillsMode,
    management_policy: SkillManagementPolicy,
    storage_protection_key: Option<Arc<SecretMaterial>>,
    credential_vault_key: Option<Arc<SecretMaterial>>,
) -> anyhow::Result<TenantSkillManagerRegistry> {
    let builtin = load_builtin_skill_source(skills_root, builtin_mode).await?;
    let mut sources = vec![builtin];
    if let Some(app_packages) = load_app_package_source_from_env().await? {
        sources.push(app_packages);
    }
    let factory = FilesystemTenantSkillManagerFactory::new(TenantSkillManagerConfig {
        data_root: managed.app_data_root,
        cache_root: managed.cache_root,
        sources,
        platform: PlatformId::Desktop,
        capabilities: CapabilitySet::desktop_runtime(),
        protected_packages: Vec::new(),
        allowed_overrides: Vec::new(),
        runtime_version: env!("CARGO_PKG_VERSION").parse()?,
        management_policy,
        storage_protection_key,
        credential_vault_key,
    })
    .await?;
    Ok(TenantSkillManagerRegistry::new(factory))
}

pub(super) async fn build_tenant_app_state<C>(
    runtime: Arc<TenantSkillRuntime>,
    model: C,
    runtime_config: RuntimeConfig,
    app_prompt: AppPromptConfig,
    owner_management: Option<OwnerApiConfig>,
) -> anyhow::Result<api::AppState>
where
    C: ModelClient + 'static,
{
    let memory_tools =
        super::server_app::resolve_memory_tools(&runtime.storage, &app_prompt).await?;
    let task_tools = super::server_app::resolve_task_tools(&runtime.storage, &app_prompt).await?;
    let automation_tools =
        super::server_app::resolve_automation_tools(&runtime.storage, &app_prompt, &runtime_config)
            .await?;
    let attachment_tools =
        super::server_app::resolve_attachment_tools(&runtime.storage, &app_prompt).await?;
    let credential_root = runtime.data_root.join("credentials");
    let connector_foundation = super::server_app::resolve_connector_tools(
        &runtime.storage,
        &app_prompt,
        &runtime_config,
        runtime.credential_vault_key.clone(),
        Some(&credential_root),
    )
    .await?;
    let connector_tools = connector_foundation
        .as_ref()
        .map(|foundation| foundation.tools.clone());
    let mail_actions = connector_foundation
        .as_ref()
        .and_then(|foundation| foundation.mail_actions.clone());
    let state = if let Some(owner_management) = owner_management {
        api::AppState::new_with_model_app_foundations_skill_manager_and_owner(
            runtime.storage.clone(),
            model,
            runtime.manager.clone(),
            runtime_config,
            app_prompt,
            api::AppFoundationRuntimes::new(memory_tools, task_tools, connector_tools)
                .with_automation_tools(automation_tools)
                .with_attachment_tools(attachment_tools)
                .with_mail_actions(mail_actions),
            owner_management,
        )
    } else {
        api::AppState::new_with_model_app_foundations_and_skill_manager(
            runtime.storage.clone(),
            model,
            runtime.manager.clone(),
            runtime_config,
            app_prompt,
            api::AppFoundationRuntimes::new(memory_tools, task_tools, connector_tools)
                .with_automation_tools(automation_tools)
                .with_attachment_tools(attachment_tools)
                .with_mail_actions(mail_actions),
        )
    };
    Ok(apply_connector_foundation(state, connector_foundation))
}
