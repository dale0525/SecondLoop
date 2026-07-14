#![cfg_attr(test, allow(deprecated))]

use agent_runtime::{
    skill_management::OwnerSkillManagementService,
    skill_policy::{ActorContext, SkillGrant, SkillManagementMode, SkillManagementPolicy},
    skill_state::SkillStateStore,
    storage::Storage,
    tools::{CommandMode, RuntimeConfig},
};
use agent_server::api;
use agent_server::owner_api::{OwnerApiConfig, OwnerAuth};
use agent_server::tenant_skills::{SINGLE_USER_TENANT_ID, TenantSkillRuntime};
use model_gateway::{
    provider::{EndpointType, ProviderProfile},
    responses::GatewayHttpClient,
};
use std::{collections::BTreeMap, path::PathBuf, sync::Arc};

const DEFAULT_DATABASE_URL: &str = "sqlite://agentweave.db?mode=rwc";
const DEFAULT_SKILLS_ROOT: &str = "skills";
const DEFAULT_MODEL_BASE_URL: &str = "http://127.0.0.1:11434/v1";
const DEFAULT_MODEL_NAME: &str = "local-agent-model";
mod server_app;
mod server_automation;
#[path = "server_skill_startup.rs"]
mod server_skill_startup;
#[cfg(test)]
#[path = "server_skill_startup_tests.rs"]
mod server_skill_startup_tests;
#[path = "server_tenant_startup.rs"]
mod server_tenant_startup;
use server_skill_startup::{
    LoadedSkillManager, builtin_skills_mode_from_lookup, load_skill_manager_with_mode,
    managed_skills_config_from_lookup,
};
#[cfg(test)]
use server_skill_startup::{ManagedSkillsConfig, load_skill_manager};
use server_tenant_startup::{build_managed_tenant_registry, build_tenant_app_state};
#[tokio::main]
async fn main() -> anyhow::Result<()> {
    tracing_subscriber::fmt()
        .with_env_filter(tracing_subscriber::EnvFilter::from_default_env())
        .init();

    let skills_root = skills_root_from_env();
    let managed_skills = managed_skills_config_from_lookup(|name| std::env::var_os(name))?;
    let builtin_mode = builtin_skills_mode_from_lookup(|name| std::env::var_os(name))?;
    let owner_host = owner_host_config_from_lookup(|name| std::env::var_os(name))?;
    let base_runtime_config = runtime_config_from_env();
    let connector_catalog = base_runtime_config
        .connectors
        .iter()
        .map(|connector| connector.id.clone())
        .collect::<Vec<_>>();
    let model = GatewayHttpClient::new(model_profile_from_env());
    let (state, automation_storage) = if let Some(managed_skills) = managed_skills {
        let policy = owner_host
            .as_ref()
            .map(|host| host.policy.clone())
            .unwrap_or_else(|| SkillManagementPolicy {
                mode: SkillManagementMode::DiagnosticsOnly,
                ..SkillManagementPolicy::default()
            });
        let registry =
            build_managed_tenant_registry(&skills_root, managed_skills, builtin_mode, policy)
                .await?;
        let runtime = registry.for_tenant(SINGLE_USER_TENANT_ID).await?;
        let control_roots = vec![
            skills_root.clone(),
            runtime.data_root.clone(),
            runtime.cache_root.clone(),
            runtime.database_path.clone(),
        ];
        let runtime_config = base_runtime_config.excluding_workspace_roots(control_roots);
        let resolved_app = server_app::resolve_app(&runtime.manager, &runtime_config).await?;
        let owner_management =
            build_tenant_owner_api_config(owner_host, &runtime, connector_catalog).await?;
        let storage = runtime.storage.clone();
        let state = build_tenant_app_state(
            runtime,
            model,
            runtime_config,
            resolved_app.prompt,
            owner_management,
        )
        .await?
        .with_host_discovery(resolved_app.host_discovery)?;
        (state, storage)
    } else {
        let database_url = std::env::var("AGENTWEAVE_DATABASE_URL")
            .unwrap_or_else(|_| DEFAULT_DATABASE_URL.into());
        let storage = Storage::connect(&database_url).await?;
        let loaded =
            load_skill_manager_with_mode(&skills_root, storage.clone(), None, builtin_mode).await?;
        if owner_host.is_none() {
            reconcile_managed_startup(&loaded, storage.clone()).await?;
        }
        let mut control_roots = loaded.control_roots(&skills_root);
        if let Some(database_path) = sqlite_database_path(&database_url) {
            control_roots.push(database_path);
        }
        let runtime_config = base_runtime_config.excluding_workspace_roots(control_roots);
        let resolved_app = server_app::resolve_app(&loaded.manager, &runtime_config).await?;
        let owner_management =
            build_owner_api_config(owner_host, &loaded, storage.clone(), connector_catalog).await?;
        let memory_tools = server_app::resolve_memory_tools(&storage, &resolved_app.prompt).await?;
        let task_tools = server_app::resolve_task_tools(&storage, &resolved_app.prompt).await?;
        let automation_tools =
            server_app::resolve_automation_tools(&storage, &resolved_app.prompt).await?;
        let connector_foundation =
            server_app::resolve_connector_tools(&storage, &resolved_app.prompt).await?;
        let connector_tools = connector_foundation
            .as_ref()
            .map(|foundation| foundation.tools.clone());
        let state = if let Some(owner_management) = owner_management {
            api::AppState::new_with_model_app_foundations_skill_manager_and_owner(
                storage.clone(),
                model,
                loaded.manager,
                runtime_config,
                resolved_app.prompt,
                api::AppFoundationRuntimes::new(memory_tools, task_tools, connector_tools)
                    .with_automation_tools(automation_tools),
                owner_management,
            )
        } else {
            api::AppState::new_with_model_app_foundations_and_skill_manager(
                storage.clone(),
                model,
                loaded.manager,
                runtime_config,
                resolved_app.prompt,
                api::AppFoundationRuntimes::new(memory_tools, task_tools, connector_tools)
                    .with_automation_tools(automation_tools),
            )
        }
        .with_host_discovery(resolved_app.host_discovery)?;
        let state = match connector_foundation {
            Some(foundation) => state.with_mail_actions(foundation.actions),
            None => state,
        };
        (state, storage)
    };
    let state = state.with_default_automation(&automation_storage).await?;
    let scheduler_worker_enabled = state.has_automation_tools()
        || std::env::var("AGENTWEAVE_SCHEDULER_WORKER").as_deref() == Ok("1");
    let state = Arc::new(state.with_skills_root(skills_root.clone()));
    let transport = agent_server::local_transport::prepare_from_environment().await?;
    let app = api::router_for_transport(
        state,
        std::env::var("AGENTWEAVE_DEV_API").as_deref() == Ok("1"),
        transport.auth(),
    );
    let addr = transport.address();
    let listener = transport.into_listener();
    let scheduler_cancellation = tokio_util::sync::CancellationToken::new();
    let scheduler_task = if scheduler_worker_enabled {
        Some(
            server_automation::start_scheduler_worker(
                &automation_storage,
                scheduler_cancellation.clone(),
            )
            .await?,
        )
    } else {
        None
    };
    tracing::info!("agent server listening on http://{addr}");
    let serve_result = axum::serve(listener, app).await;
    scheduler_cancellation.cancel();
    if let Some(task) = scheduler_task {
        task.await??;
    }
    serve_result?;
    Ok(())
}

async fn build_tenant_owner_api_config(
    host: Option<OwnerHostConfig>,
    runtime: &TenantSkillRuntime,
    connector_catalog: Vec<String>,
) -> anyhow::Result<Option<OwnerApiConfig>> {
    let Some(host) = host else {
        return Ok(None);
    };
    let service = runtime
        .management
        .clone()
        .with_prepared_transfer_roots(
            runtime.data_root.join("skill-imports"),
            runtime.data_root.join("skill-exports"),
        )
        .await?
        .with_connector_catalog(connector_catalog)?;
    Ok(Some(OwnerApiConfig::new(service, owner_auth(host)?)))
}

fn runtime_config_from_env() -> RuntimeConfig {
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

fn skills_root_from_env() -> PathBuf {
    std::env::var("AGENTWEAVE_SKILLS_ROOT")
        .map(PathBuf::from)
        .unwrap_or_else(|_| PathBuf::from(DEFAULT_SKILLS_ROOT))
}

fn sqlite_database_path(url: &str) -> Option<PathBuf> {
    let value = url
        .strip_prefix("sqlite://")
        .or_else(|| url.strip_prefix("sqlite:"))?
        .split('?')
        .next()?;
    (!value.is_empty() && value != ":memory:").then(|| PathBuf::from(value))
}

#[derive(Clone)]
struct OwnerHostConfig {
    policy: SkillManagementPolicy,
    token: Arc<[u8]>,
    actor: ActorContext,
    approver_token: Option<Arc<[u8]>>,
    approver_actor: Option<ActorContext>,
}

fn owner_host_config_from_lookup<F>(lookup: F) -> anyhow::Result<Option<OwnerHostConfig>>
where
    F: Fn(&str) -> Option<std::ffi::OsString>,
{
    let mode = lookup("AGENTWEAVE_SKILL_MANAGEMENT_MODE")
        .map(|value| {
            value.into_string().map_err(|_| {
                anyhow::anyhow!("AGENTWEAVE_SKILL_MANAGEMENT_MODE must be valid UTF-8")
            })
        })
        .transpose()?;
    let Some(mode) = mode else {
        return Ok(None);
    };
    if mode == "disabled" {
        return Ok(None);
    }
    let policy = match mode.as_str() {
        "diagnostics_only" => SkillManagementPolicy {
            mode: SkillManagementMode::DiagnosticsOnly,
            ..SkillManagementPolicy::default()
        },
        "owner_only" => SkillManagementPolicy::owner_only(),
        "organization_managed" => SkillManagementPolicy {
            mode: SkillManagementMode::OrganizationManaged,
            ..SkillManagementPolicy::default()
        },
        _ => anyhow::bail!("unsupported AGENTWEAVE_SKILL_MANAGEMENT_MODE"),
    };
    let token = lookup("AGENTWEAVE_OWNER_TOKEN")
        .ok_or_else(|| {
            anyhow::anyhow!("AGENTWEAVE_OWNER_TOKEN is required when skill management is enabled")
        })?
        .into_encoded_bytes();
    if token.is_empty() {
        anyhow::bail!("AGENTWEAVE_OWNER_TOKEN cannot be empty");
    }
    let actor = match policy.mode {
        SkillManagementMode::OwnerOnly => ActorContext::owner(
            "local-owner",
            [
                SkillGrant::Inspect,
                SkillGrant::CreateDraft,
                SkillGrant::EditDraft,
                SkillGrant::Validate,
                SkillGrant::Test,
                SkillGrant::Activate,
                SkillGrant::Import,
                SkillGrant::Export,
                SkillGrant::Rollback,
                SkillGrant::Disable,
                SkillGrant::DeleteManaged,
            ],
        ),
        SkillManagementMode::DiagnosticsOnly | SkillManagementMode::OrganizationManaged => {
            ActorContext::anonymous().with_grants([SkillGrant::Inspect])
        }
        SkillManagementMode::Disabled => unreachable!("disabled mode returned above"),
    };
    let (approver_token, approver_actor) = if policy.mode == SkillManagementMode::OwnerOnly {
        let approver_token = lookup("AGENTWEAVE_APPROVER_TOKEN")
            .ok_or_else(|| {
                anyhow::anyhow!(
                    "AGENTWEAVE_APPROVER_TOKEN is required when owner activation approval is enabled"
                )
            })?
            .into_encoded_bytes();
        if approver_token.is_empty() {
            anyhow::bail!("AGENTWEAVE_APPROVER_TOKEN cannot be empty");
        }
        if token == approver_token {
            anyhow::bail!("owner and approver bearer tokens must be distinct");
        }
        (
            Some(Arc::from(approver_token)),
            Some(ActorContext::owner(
                "local-approver",
                [
                    SkillGrant::Inspect,
                    SkillGrant::Activate,
                    SkillGrant::Rollback,
                    SkillGrant::DeleteManaged,
                ],
            )),
        )
    } else {
        (None, None)
    };
    Ok(Some(OwnerHostConfig {
        policy,
        token: Arc::from(token),
        actor,
        approver_token,
        approver_actor,
    }))
}

async fn build_owner_api_config(
    host: Option<OwnerHostConfig>,
    loaded: &LoadedSkillManager,
    storage: Storage,
    connector_catalog: Vec<String>,
) -> anyhow::Result<Option<OwnerApiConfig>> {
    let Some(host) = host else {
        return Ok(None);
    };
    let revisions = loaded.managed_store.clone().ok_or_else(|| {
        anyhow::anyhow!("AGENTWEAVE_MANAGED_SKILLS=1 is required when skill management is enabled")
    })?;
    let state = SkillStateStore::new(storage);
    let app_data_root = revisions
        .paths()
        .quarantine
        .parent()
        .ok_or_else(|| anyhow::anyhow!("skill quarantine root has no app-data parent"))?;
    let import_root = app_data_root.join("skill-imports");
    let export_root = app_data_root.join("skill-exports");
    let service = OwnerSkillManagementService::new(
        loaded.manager.clone(),
        revisions,
        state,
        host.policy.clone(),
    )
    .with_prepared_transfer_roots(import_root, export_root)
    .await?
    .with_connector_catalog(connector_catalog)?;
    loaded
        .manager
        .startup_reconcile()
        .await
        .map_err(|error| anyhow::anyhow!("managed skill startup reconciliation failed: {error}"))?;
    Ok(Some(OwnerApiConfig::new(service, owner_auth(host)?)))
}

fn owner_auth(host: OwnerHostConfig) -> anyhow::Result<OwnerAuth> {
    let mut principals = vec![(host.token, host.actor)];
    if let (Some(token), Some(actor)) = (host.approver_token, host.approver_actor) {
        principals.push((token, actor));
    }
    OwnerAuth::from_principals(principals)
}

async fn reconcile_managed_startup(
    loaded: &LoadedSkillManager,
    storage: Storage,
) -> anyhow::Result<()> {
    let Some(revisions) = loaded.managed_store.clone() else {
        return Ok(());
    };
    let service = OwnerSkillManagementService::new(
        loaded.manager.clone(),
        revisions,
        SkillStateStore::new(storage),
        SkillManagementPolicy {
            mode: SkillManagementMode::DiagnosticsOnly,
            ..SkillManagementPolicy::default()
        },
    );
    loaded
        .manager
        .startup_reconcile()
        .await
        .map_err(|error| anyhow::anyhow!("managed skill startup reconciliation failed: {error}"))?;
    drop(service);
    Ok(())
}

fn model_profile_from_env() -> ProviderProfile {
    ProviderProfile {
        id: "default".into(),
        name: "Default".into(),
        endpoint_type: model_endpoint_type_from_env(),
        base_url: std::env::var("AGENTWEAVE_MODEL_BASE_URL")
            .unwrap_or_else(|_| DEFAULT_MODEL_BASE_URL.into()),
        model: std::env::var("AGENTWEAVE_MODEL_NAME").unwrap_or_else(|_| DEFAULT_MODEL_NAME.into()),
        api_key: std::env::var("AGENTWEAVE_MODEL_API_KEY").ok(),
        headers: BTreeMap::new(),
    }
}

fn model_endpoint_type_from_env() -> EndpointType {
    match std::env::var("AGENTWEAVE_MODEL_ENDPOINT_TYPE")
        .unwrap_or_else(|_| "chat_completions".into())
        .as_str()
    {
        "responses" => EndpointType::Responses,
        "completion" => EndpointType::Completion,
        _ => EndpointType::ChatCompletions,
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use agent_runtime::platform::PlatformId;
    use agent_runtime::skill_store::{SkillRevisionStore, SkillStorePaths};
    use agent_runtime::turn::{ModelClient, ModelEventStream};
    use agent_runtime::{skill_package::SkillPackageId, skill_state::SkillLayerRecord};
    use axum::{
        body::Body,
        http::{Request, StatusCode},
    };
    use futures::stream;
    use model_gateway::responses::{GatewayEvent, GatewayRequest};
    use std::path::Path;
    use std::sync::Mutex;
    use tower::ServiceExt;

    #[path = "main_startup_tests.rs"]
    mod startup_tests;

    struct CapturingModel {
        tool_names: Arc<Mutex<Vec<String>>>,
    }

    #[async_trait::async_trait]
    impl ModelClient for CapturingModel {
        async fn stream(&self, request: GatewayRequest) -> anyhow::Result<ModelEventStream> {
            *self.tool_names.lock().unwrap() = request
                .tools
                .into_iter()
                .map(|tool| tool.advertised_name().to_string())
                .collect();
            Ok(Box::pin(stream::iter(vec![
                Ok(GatewayEvent::TextDelta {
                    text: "done".into(),
                }),
                Ok(GatewayEvent::Completed),
            ])))
        }
    }

    #[test]
    fn server_runtime_config_disables_builtin_tools_by_default() {
        assert!(!runtime_config_from_env().built_in_tools_enabled);
    }

    #[test]
    fn managed_skills_are_disabled_without_explicit_opt_in() {
        let config = managed_skills_config_from_lookup(|_| None).unwrap();
        assert!(config.is_none());
    }

    #[test]
    fn managed_skills_opt_in_requires_both_roots_without_global_env_mutation() {
        let error = managed_skills_config_from_lookup(|name| match name {
            "AGENTWEAVE_MANAGED_SKILLS" => Some("1".into()),
            "AGENTWEAVE_APP_DATA_ROOT" => Some("/tmp/app".into()),
            _ => None,
        })
        .err()
        .unwrap();
        assert!(error.to_string().contains("AGENTWEAVE_CACHE_ROOT"));

        let config = managed_skills_config_from_lookup(|name| match name {
            "AGENTWEAVE_MANAGED_SKILLS" => Some("1".into()),
            "AGENTWEAVE_APP_DATA_ROOT" => Some("/tmp/app".into()),
            "AGENTWEAVE_CACHE_ROOT" => Some("/tmp/cache".into()),
            _ => None,
        })
        .unwrap()
        .unwrap();
        assert_eq!(config.app_data_root, PathBuf::from("/tmp/app"));
        assert_eq!(config.cache_root, PathBuf::from("/tmp/cache"));
    }

    #[test]
    fn builtin_skills_mode_requires_a_closed_authoritative_value() {
        use server_skill_startup::{BuiltinSkillsMode, builtin_skills_mode_from_lookup};

        assert_eq!(
            builtin_skills_mode_from_lookup(|_| None).unwrap(),
            BuiltinSkillsMode::Auto
        );
        assert_eq!(
            builtin_skills_mode_from_lookup(|_| Some("bundle".into())).unwrap(),
            BuiltinSkillsMode::Bundle
        );
        assert!(
            builtin_skills_mode_from_lookup(|_| Some("direct".into()))
                .unwrap_err()
                .to_string()
                .contains("auto, directory, or bundle")
        );
    }

    #[test]
    fn owner_management_policy_is_not_enabled_by_a_token_alone() {
        let config = owner_host_config_from_lookup(|name| match name {
            "AGENTWEAVE_OWNER_TOKEN" => Some("secret-token".into()),
            _ => None,
        })
        .unwrap();

        assert!(config.is_none());
    }

    #[test]
    fn enabled_owner_management_requires_a_nonempty_token() {
        let missing = owner_host_config_from_lookup(|name| match name {
            "AGENTWEAVE_SKILL_MANAGEMENT_MODE" => Some("owner_only".into()),
            _ => None,
        })
        .err()
        .unwrap();
        assert!(missing.to_string().contains("AGENTWEAVE_OWNER_TOKEN"));

        let empty = owner_host_config_from_lookup(|name| match name {
            "AGENTWEAVE_SKILL_MANAGEMENT_MODE" => Some("diagnostics_only".into()),
            "AGENTWEAVE_OWNER_TOKEN" => Some("".into()),
            _ => None,
        })
        .err()
        .unwrap();
        assert!(empty.to_string().contains("cannot be empty"));
    }

    #[test]
    fn owner_host_context_is_fixed_and_minimally_granted() {
        let config = owner_host_config_from_lookup(|name| match name {
            "AGENTWEAVE_SKILL_MANAGEMENT_MODE" => Some("owner_only".into()),
            "AGENTWEAVE_OWNER_TOKEN" => Some("secret-token".into()),
            "AGENTWEAVE_APPROVER_TOKEN" => Some("approver-token".into()),
            _ => None,
        })
        .unwrap()
        .unwrap();

        assert_eq!(config.policy.mode, SkillManagementMode::OwnerOnly);
        assert_eq!(config.actor.actor_id, "local-owner");
        assert_eq!(config.actor.role, "owner");
        assert_eq!(
            config.actor.grants,
            [
                SkillGrant::Inspect,
                SkillGrant::CreateDraft,
                SkillGrant::EditDraft,
                SkillGrant::Validate,
                SkillGrant::Test,
                SkillGrant::Activate,
                SkillGrant::Import,
                SkillGrant::Export,
                SkillGrant::Rollback,
                SkillGrant::Disable,
                SkillGrant::DeleteManaged,
            ]
            .into_iter()
            .collect()
        );
        assert_eq!(config.token.as_ref(), b"secret-token");
        assert_eq!(
            config.approver_token.as_deref(),
            Some(b"approver-token".as_slice())
        );
        let approver = config.approver_actor.as_ref().unwrap();
        assert_eq!(approver.actor_id, "local-approver");
        assert_eq!(
            approver.grants,
            [
                SkillGrant::Inspect,
                SkillGrant::Activate,
                SkillGrant::Rollback,
                SkillGrant::DeleteManaged,
            ]
            .into_iter()
            .collect()
        );
    }

    #[test]
    fn owner_only_requires_a_distinct_approver_token() {
        let missing = owner_host_config_from_lookup(|name| match name {
            "AGENTWEAVE_SKILL_MANAGEMENT_MODE" => Some("owner_only".into()),
            "AGENTWEAVE_OWNER_TOKEN" => Some("owner-token".into()),
            _ => None,
        })
        .err()
        .unwrap();
        assert!(missing.to_string().contains("AGENTWEAVE_APPROVER_TOKEN"));

        let duplicate = owner_host_config_from_lookup(|name| match name {
            "AGENTWEAVE_SKILL_MANAGEMENT_MODE" => Some("owner_only".into()),
            "AGENTWEAVE_OWNER_TOKEN" | "AGENTWEAVE_APPROVER_TOKEN" => Some("same-token".into()),
            _ => None,
        })
        .err()
        .unwrap();
        assert!(duplicate.to_string().contains("distinct"));
    }

    #[tokio::test]
    async fn production_state_and_runner_share_one_skill_manager() {
        let root = unique_test_dir("shared-manager");
        let package_root = root.join("runtime");
        write_runtime_package(&package_root, "first_tool").await;
        let storage = Storage::connect("sqlite::memory:").await.unwrap();
        let manager = load_skill_manager(&root, storage.clone(), None)
            .await
            .unwrap()
            .manager;
        let session = storage.create_session("Shared manager").await.unwrap();
        let tool_names = Arc::new(Mutex::new(Vec::new()));
        let state = Arc::new(
            api::AppState::new_with_model_and_skill_manager(
                storage,
                CapturingModel {
                    tool_names: tool_names.clone(),
                },
                manager.clone(),
                RuntimeConfig::workspace_write(root.clone(), root.clone()).without_builtin_tools(),
            )
            .with_skills_root(root.clone()),
        );

        write_runtime_package(&package_root, "second_tool").await;
        manager.reload().await.unwrap();
        let response = api::router(state)
            .oneshot(
                Request::builder()
                    .method("POST")
                    .uri(format!("/sessions/{}/messages", session.id))
                    .header("content-type", "application/json")
                    .body(Body::from(r#"{"content":"check tools"}"#))
                    .unwrap(),
            )
            .await
            .unwrap();

        assert_eq!(response.status(), StatusCode::OK);
        let names = tool_names.lock().unwrap().clone();
        assert!(names.iter().any(|name| name == "second_tool"));
        assert!(!names.iter().any(|name| name == "first_tool"));
        remove_test_dir(root).await;
    }

    #[tokio::test]
    async fn verified_bundle_selection_uses_dynamic_source_and_composes_managed() {
        let source_root = unique_test_dir("bundle-source");
        let root = unique_test_dir("bundle-manager");
        let package_root = source_root.join("runtime");
        write_runtime_package(&package_root, "bundle_tool").await;
        tokio::fs::write(
            package_root.join("agentweave.json"),
            serde_json::json!({
                "schemaVersion": 1,
                "id": "com.example.bundle",
                "version": "0.1.0",
                "displayName": "Bundle",
                "kind": "native_runtime",
                "package": { "includeInstructions": false, "includeRuntime": true },
                "compatibility": { "platforms": ["desktop"] },
                "requires": {
                    "packages": [],
                    "capabilities": ["shell.process"],
                    "runtimeTools": [],
                    "connectors": []
                }
            })
            .to_string(),
        )
        .await
        .unwrap();
        agent_runtime::skill_bundle::build_skill_bundle(
            agent_runtime::skill_bundle::BuildSkillBundleRequest {
                source_roots: vec![source_root.clone()],
                output_root: root.clone(),
                platform: PlatformId::Desktop,
                runtime_version: env!("CARGO_PKG_VERSION").parse().unwrap(),
                generated_at: "2026-01-02T03:04:05Z".into(),
            },
        )
        .await
        .unwrap();

        let storage = Storage::connect("sqlite::memory:").await.unwrap();
        let manager = load_skill_manager(&root, storage, None)
            .await
            .unwrap()
            .manager;

        assert_eq!(
            manager.current_snapshot().registry().tools()[0].name,
            "bundle_tool"
        );
        manager.reload().await.unwrap();

        let app_root = unique_test_dir("bundle-managed-app");
        let cache_root = unique_test_dir("bundle-managed-cache");
        let storage = Storage::connect("sqlite::memory:").await.unwrap();
        let managed = load_skill_manager(
            &root,
            storage,
            Some(ManagedSkillsConfig {
                app_data_root: app_root.clone(),
                cache_root: cache_root.clone(),
            }),
        )
        .await
        .unwrap();
        assert!(managed.managed_store.is_some());
        assert_eq!(
            managed.manager.current_snapshot().registry().tools()[0].name,
            "bundle_tool"
        );
        remove_test_dir(source_root).await;
        remove_test_dir(root).await;
        remove_test_dir(app_root).await;
        remove_test_dir(cache_root).await;
    }

    #[cfg(unix)]
    #[tokio::test]
    async fn dangling_bundle_manifest_never_falls_back_to_directory_discovery() {
        use std::os::unix::fs as unix_fs;

        let root = unique_test_dir("dangling-bundle-manifest");
        tokio::fs::create_dir_all(&root).await.unwrap();
        unix_fs::symlink("missing-manifest", root.join("skill-bundle.json")).unwrap();
        let storage = Storage::connect("sqlite::memory:").await.unwrap();

        let error = load_skill_manager(&root, storage, None)
            .await
            .err()
            .unwrap();

        assert!(format!("{error:#}").contains("requires AGENTWEAVE_BUILTIN_SKILLS_MODE=bundle"));
        tokio::fs::remove_file(root.join("skill-bundle.json"))
            .await
            .unwrap();
        remove_test_dir(root).await;
    }

    #[tokio::test]
    async fn production_loader_composes_builtin_and_managed_without_publishing_failed_promotion() {
        let root = unique_test_dir("managed-composition");
        write_runtime_package(&root.join("builtin"), "builtin_tool").await;
        let app_root = unique_test_dir("managed-app");
        let cache_root = unique_test_dir("managed-cache");
        let storage = Storage::connect("sqlite::memory:").await.unwrap();
        let loaded = load_skill_manager(
            &root,
            storage.clone(),
            Some(ManagedSkillsConfig {
                app_data_root: app_root.clone(),
                cache_root: cache_root.clone(),
            }),
        )
        .await
        .unwrap();
        let store = loaded.managed_store.clone().unwrap();
        let managed_source = loaded.managed_source.clone().unwrap();
        let state = SkillStateStore::new(storage);
        let valid_source = unique_test_dir("managed-valid-source");
        write_instruction_package(&valid_source, "com.example.server-managed").await;
        let valid = store
            .create_staging_revision(&valid_source, "owner-1")
            .await
            .unwrap();
        let valid = store.promote_revision(&valid.revision_id).await.unwrap();
        state
            .activate_revision(
                &SkillPackageId::parse("com.example.server-managed").unwrap(),
                &valid.revision_id,
                SkillLayerRecord::Managed,
                "owner-1",
            )
            .await
            .unwrap();
        let corrupt_source = unique_test_dir("managed-corrupt-source");
        write_instruction_package(&corrupt_source, "com.example.server-corrupt").await;
        let corrupt = store
            .create_staging_revision(&corrupt_source, "owner-1")
            .await
            .unwrap();
        let corrupt = store.promote_revision(&corrupt.revision_id).await.unwrap();
        state
            .activate_revision(
                &SkillPackageId::parse("com.example.server-corrupt").unwrap(),
                &corrupt.revision_id,
                SkillLayerRecord::Managed,
                "owner-1",
            )
            .await
            .unwrap();
        make_test_tree_writable(&corrupt.path).await;
        tokio::fs::write(corrupt.path.join("SKILL.md"), "corrupt")
            .await
            .unwrap();

        loaded.manager.reload().await.unwrap();

        let snapshot = loaded.manager.current_snapshot();
        let package_ids = snapshot
            .packages()
            .iter()
            .map(|resolved| resolved.package.descriptor.id.as_str())
            .collect::<Vec<_>>();
        assert!(package_ids.contains(&"com.example.server-runtime"));
        assert!(package_ids.contains(&"com.example.server-managed"));
        assert!(!package_ids.contains(&"com.example.server-corrupt"));
        assert_eq!(managed_source.issues().len(), 1);

        let failed_source = unique_test_dir("managed-failed-source");
        write_instruction_package(&failed_source, "com.example.server-failed").await;
        let failed = store
            .create_staging_revision(&failed_source, "owner-1")
            .await
            .unwrap();
        let collision = store
            .paths()
            .managed
            .join("com.example.server-failed/revisions")
            .join(&failed.revision_id);
        tokio::fs::create_dir_all(collision.parent().unwrap())
            .await
            .unwrap();
        tokio::fs::create_dir(&collision).await.unwrap();
        let generation = loaded.manager.current_snapshot().generation();
        let promotion_store = store.clone();
        let failed_revision = failed.revision_id.clone();
        let reload = loaded
            .manager
            .reload_with_pre_publish(move |_| async move {
                promotion_store.promote_revision(&failed_revision).await?;
                Ok(())
            })
            .await;

        assert!(reload.is_err());
        assert_eq!(loaded.manager.current_snapshot().generation(), generation);
        remove_test_dir(root).await;
        remove_test_dir(app_root).await;
        remove_test_dir(cache_root).await;
        remove_test_dir(valid_source).await;
        remove_test_dir(corrupt_source).await;
        remove_test_dir(failed_source).await;
    }

    async fn write_runtime_package(package_root: &Path, tool_name: &str) {
        tokio::fs::create_dir_all(package_root).await.unwrap();
        tokio::fs::write(
            package_root.join("agentweave.json"),
            serde_json::json!({
                "schemaVersion": 1,
                "id": "com.example.server-runtime",
                "version": "1.0.0",
                "displayName": "Server runtime",
                "kind": "native_runtime",
                "package": {
                    "includeInstructions": false,
                    "includeRuntime": true
                }
            })
            .to_string(),
        )
        .await
        .unwrap();
        tokio::fs::write(
            package_root.join("skill.json"),
            serde_json::json!({
                "name": "server-runtime",
                "description": "Server runtime test skill.",
                "version": "1.0.0",
                "entry": {
                    "type": "command",
                    "command": "node",
                    "args": ["index.js"]
                },
                "tools": [{
                    "name": tool_name,
                    "description": "Test tool.",
                    "input_schema": { "type": "object" }
                }]
            })
            .to_string(),
        )
        .await
        .unwrap();
        tokio::fs::write(package_root.join("index.js"), "process.stdin.resume();\n")
            .await
            .unwrap();
    }

    async fn write_instruction_package(package_root: &Path, id: &str) {
        tokio::fs::create_dir_all(package_root).await.unwrap();
        let name = id.rsplit('.').next().unwrap();
        tokio::fs::write(
            package_root.join("agentweave.json"),
            serde_json::json!({
                "schemaVersion": 1,
                "id": id,
                "version": "1.0.0",
                "displayName": name,
                "kind": "instruction_only",
                "package": {
                    "includeInstructions": true,
                    "includeRuntime": false
                }
            })
            .to_string(),
        )
        .await
        .unwrap();
        tokio::fs::write(
            package_root.join("SKILL.md"),
            format!("---\nname: {name}\ndescription: {name}\n---\n{name}\n"),
        )
        .await
        .unwrap();
    }

    async fn make_test_tree_writable(root: &Path) {
        let mut entries = tokio::fs::read_dir(root).await.unwrap();
        while let Some(entry) = entries.next_entry().await.unwrap() {
            let mut permissions = entry.metadata().await.unwrap().permissions();
            set_test_writable(&mut permissions, false);
            tokio::fs::set_permissions(entry.path(), permissions)
                .await
                .unwrap();
        }
        let mut permissions = tokio::fs::metadata(root).await.unwrap().permissions();
        set_test_writable(&mut permissions, true);
        tokio::fs::set_permissions(root, permissions).await.unwrap();
    }

    fn unique_test_dir(name: &str) -> PathBuf {
        std::env::temp_dir().join(format!("agentweave-main-{name}-{}", uuid::Uuid::new_v4()))
    }

    async fn remove_test_dir(path: PathBuf) {
        if path.exists() {
            let mut stack = vec![path.clone()];
            while let Some(current) = stack.pop() {
                let mut permissions = tokio::fs::symlink_metadata(&current)
                    .await
                    .unwrap()
                    .permissions();
                set_test_writable(&mut permissions, current.is_dir());
                tokio::fs::set_permissions(&current, permissions)
                    .await
                    .unwrap();
                if current.is_dir() {
                    let mut entries = tokio::fs::read_dir(&current).await.unwrap();
                    while let Some(entry) = entries.next_entry().await.unwrap() {
                        stack.push(entry.path());
                    }
                }
            }
            tokio::fs::remove_dir_all(path).await.unwrap();
        }
    }

    fn set_test_writable(permissions: &mut std::fs::Permissions, directory: bool) {
        #[cfg(unix)]
        {
            use std::os::unix::fs::PermissionsExt;
            let owner_access = if directory { 0o700 } else { 0o600 };
            permissions.set_mode(permissions.mode() | owner_access);
        }
        #[cfg(not(unix))]
        permissions.set_readonly(false);
    }
}
