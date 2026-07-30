use crate::api::AppState;
use agent_runtime::{
    prompt_composer::AppPromptConfig,
    skill::SkillRegistry,
    skill_catalog::SkillCatalog,
    skill_manager::SkillManager,
    storage::Storage,
    tools::RuntimeConfig,
    turn::{ModelClient, ModelEventStream},
};
use axum::{Router, http::StatusCode, middleware, routing::get};
use model_gateway::responses::GatewayRequest;
use std::{path::PathBuf, sync::Arc};

struct RecoveryModel;

#[async_trait::async_trait]
impl ModelClient for RecoveryModel {
    async fn stream(&self, _request: GatewayRequest) -> anyhow::Result<ModelEventStream> {
        anyhow::bail!("the Agent runtime is unavailable while App configuration is being repaired")
    }
}

pub fn state(
    storage: Storage,
    app_id: &str,
    skills_root: PathBuf,
    control_plane: crate::developer_control_plane::DeveloperControlPlane,
) -> AppState {
    let mut prompt = AppPromptConfig::default();
    prompt.identity.app_id = app_id.to_owned();
    prompt.identity.display_name = "AgentWeave Recovery".into();
    let cwd = std::env::current_dir().unwrap_or_else(|_| PathBuf::from("."));
    AppState::new_with_model_app_and_skill_manager(
        storage,
        RecoveryModel,
        SkillManager::from_registry_and_catalog(SkillRegistry::empty(), SkillCatalog::empty()),
        RuntimeConfig::read_only(&cwd, &cwd).without_builtin_tools(),
        prompt,
    )
    .with_skills_root(skills_root)
    .with_developer_control_plane(control_plane)
}

pub fn router_for_transport(
    state: Arc<AppState>,
    transport_auth: crate::local_transport::TransportAuth,
) -> Router {
    Router::new()
        .route("/health", get(|| async { "ok" }))
        .route(
            "/host/bootstrap",
            get(|| async { StatusCode::SERVICE_UNAVAILABLE }),
        )
        .merge(crate::dev_api::recovery_routes())
        .merge(crate::developer_control_plane_api::recovery_routes())
        .route_layer(middleware::from_fn_with_state(
            transport_auth,
            crate::local_transport::require_transport,
        ))
        .with_state(state)
}

#[cfg(test)]
#[path = "recovery_api_tests.rs"]
mod tests;
