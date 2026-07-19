pub use crate::api_foundations::AppFoundationRuntimes;
use crate::model_access_api::validate_model_override;
use crate::owner_api::OwnerApiConfig;
use agent_runtime::{
    app_definition::AgentAppHostDiscovery,
    events::RuntimeEvent,
    prompt_composer::AppPromptConfig,
    session::{ConversationScope, messages_to_model_history},
    skill::SkillRegistry,
    skill_catalog::SkillCatalog,
    skill_manager::SkillManager,
    skill_policy::ActorContext,
    storage::Storage,
    tools::{RuntimeConfig, ToolRegistry},
    turn::{AgentRunner, ModelClient, RuntimeEventObserver, TurnRunner},
    turn_request::TurnRequest,
};
use axum::{
    Json, Router,
    extract::{Extension, Path, State},
    http::{HeaderValue, Method, header},
    middleware,
    routing::{get, post},
};
use futures::StreamExt;
use model_gateway::responses::GatewayHttpClient;
use std::{
    collections::{BTreeMap, BTreeSet},
    path::PathBuf,
    sync::{Arc, Weak},
};
use tokio::sync::Mutex;
use tower_http::cors::CorsLayer;

#[cfg(test)]
use axum::response::{IntoResponse, Response};
#[cfg(test)]
use model_gateway::provider::EndpointType;

mod runtime_tools;
mod turn_models;
use turn_models::{
    SharedModelClient, TurnModelClient, agent_turn_error, assistant_text_from_events,
    provider_profile_from_request, test_connection_gateway_request,
};
#[path = "api_types.rs"]
mod types;
pub(crate) use types::ApiError;
pub use types::{
    AppDiagnosticsResponse, ErrorResponse, ModelConnectionTestRequest, ModelConnectionTestResponse,
    UserMessageRequest, UserMessageResponse,
};
#[cfg(test)]
mod test_support;
#[cfg(test)]
use test_support::{DeterministicAgent, default_runtime_config};

#[derive(Clone)]
pub struct AppState {
    storage: Storage,
    agent: Arc<dyn AgentRunner>,
    model: Option<Arc<dyn ModelClient>>,
    skill_manager: SkillManager,
    skills_root: Option<PathBuf>,
    runtime_config: RuntimeConfig,
    dev_skill_mutations: Arc<Mutex<()>>,
    owner_management: Option<OwnerApiConfig>,
    app_prompt: AppPromptConfig,
    host_discovery: Option<AgentAppHostDiscovery>,
    conversation_scope: ConversationScope,
    conversation_locks: Arc<Mutex<BTreeMap<String, Weak<Mutex<()>>>>>,
    turn_coordinator: crate::turn_api::TurnCoordinator,
    memory_tools: Option<agent_runtime::memory_tools::MemoryToolRuntime>,
    task_tools: Option<agent_runtime::task_tools::TaskToolRuntime>,
    automation_tools: Option<agent_runtime::automation_tools::AutomationToolRuntime>,
    structured_content_tools: agent_runtime::structured_content_tools::StructuredContentToolRuntime,
    attachment_tools: Option<agent_runtime::attachment_tools::AttachmentToolRuntime>,
    data_protection: Option<crate::data_protection::DataProtectionService>,
    pub(crate) connector_tools: Option<agent_runtime::connector_tools::ConnectorToolRuntime>,
    pub(crate) mail_actions: Option<agent_runtime::foundation_actions::MailActionService>,
    pub(crate) calendar_actions: Option<agent_runtime::calendar_actions::CalendarActionService>,
    pub(crate) contacts_actions: Option<agent_runtime::contacts_actions::ContactsActionService>,
    pub(crate) mail_account_manager:
        Option<Arc<agent_runtime::mail_imap_smtp_accounts::ImapSmtpMailAccountManager>>,
    pub(crate) automation: Option<crate::automation_api::AutomationApiState>,
    pub(crate) oauth_broker: Option<agent_runtime::oauth::OAuthBroker>,
    identity_runtime: Option<crate::identity_api::IdentityRuntime>,
    developer_control_plane: Option<Arc<crate::developer_control_plane::DeveloperControlPlane>>,
}

impl AppState {
    pub fn new_with_model_and_skill_manager<C>(
        storage: Storage,
        model: C,
        skill_manager: SkillManager,
        runtime_config: RuntimeConfig,
    ) -> Self
    where
        C: ModelClient + 'static,
    {
        Self::new_with_model_app_and_skill_manager(
            storage,
            model,
            skill_manager,
            runtime_config,
            AppPromptConfig::default(),
        )
    }

    pub fn new_with_model_app_and_skill_manager<C>(
        storage: Storage,
        model: C,
        skill_manager: SkillManager,
        runtime_config: RuntimeConfig,
        app_prompt: AppPromptConfig,
    ) -> Self
    where
        C: ModelClient + 'static,
    {
        Self::new_with_model_app_foundations_and_skill_manager(
            storage,
            model,
            skill_manager,
            runtime_config,
            app_prompt,
            AppFoundationRuntimes::new(None, None, None),
        )
    }

    pub fn new_with_model_app_foundations_and_skill_manager<C>(
        storage: Storage,
        model: C,
        skill_manager: SkillManager,
        runtime_config: RuntimeConfig,
        app_prompt: AppPromptConfig,
        foundations: AppFoundationRuntimes,
    ) -> Self
    where
        C: ModelClient + 'static,
    {
        let AppFoundationRuntimes {
            memory_tools,
            task_tools,
            automation_tools,
            attachment_tools,
            connector_tools,
            mail_actions,
        } = foundations;
        let model: Arc<dyn ModelClient> = Arc::new(model);
        let mut runner = TurnRunner::new_with_manager_and_config(
            SharedModelClient(model.clone()),
            skill_manager.clone(),
            runtime_config.clone(),
        )
        .with_app_prompt(app_prompt.clone());
        if let Some(memory) = &memory_tools {
            runner = runner
                .with_memory_tools(memory.clone())
                .with_memory_candidate_extractor(Arc::new(
                    agent_runtime::memory_lifecycle::ExplicitMemoryCandidateExtractor,
                ));
        }
        if let Some(tasks) = &task_tools {
            runner = runner.with_task_tools(tasks.clone());
        }
        if let Some(automation) = &automation_tools {
            runner = runner.with_automation_tools(automation.clone());
        }
        if let Some(attachments) = &attachment_tools {
            runner = runner.with_attachment_tools(attachments.clone());
        }
        if let Some(connectors) = &connector_tools {
            runner = runner.with_connector_tools(connectors.clone());
        }
        if let Some(actions) = &mail_actions {
            runner = runner.with_mail_actions(actions.clone());
        }
        let conversation_scope = ConversationScope::local(&app_prompt.identity.app_id);
        let structured_content_tools =
            Self::new_structured_content_tools(&storage, &conversation_scope);
        runner = runner.with_structured_content_tools(structured_content_tools.clone());
        Self {
            storage,
            agent: Arc::new(runner),
            model: Some(model),
            skill_manager,
            skills_root: None,
            runtime_config,
            dev_skill_mutations: Arc::new(Mutex::new(())),
            owner_management: None,
            app_prompt,
            host_discovery: None,
            conversation_scope,
            conversation_locks: Arc::new(Mutex::new(BTreeMap::new())),
            turn_coordinator: crate::turn_api::TurnCoordinator::default(),
            memory_tools,
            task_tools,
            automation_tools,
            structured_content_tools,
            attachment_tools,
            data_protection: None,
            connector_tools,
            mail_actions,
            calendar_actions: None,
            contacts_actions: None,
            mail_account_manager: None,
            automation: None,
            oauth_broker: None,
            identity_runtime: None,
            developer_control_plane: None,
        }
    }

    pub fn new_with_model_skill_manager_and_owner<C>(
        storage: Storage,
        model: C,
        skill_manager: SkillManager,
        runtime_config: RuntimeConfig,
        owner_management: OwnerApiConfig,
    ) -> Self
    where
        C: ModelClient + 'static,
    {
        Self::new_with_model_app_skill_manager_and_owner(
            storage,
            model,
            skill_manager,
            runtime_config,
            AppPromptConfig::default(),
            owner_management,
        )
    }

    pub fn new_with_model_app_skill_manager_and_owner<C>(
        storage: Storage,
        model: C,
        skill_manager: SkillManager,
        runtime_config: RuntimeConfig,
        app_prompt: AppPromptConfig,
        owner_management: OwnerApiConfig,
    ) -> Self
    where
        C: ModelClient + 'static,
    {
        Self::new_with_model_app_foundations_skill_manager_and_owner(
            storage,
            model,
            skill_manager,
            runtime_config,
            app_prompt,
            AppFoundationRuntimes::new(None, None, None),
            owner_management,
        )
    }

    pub fn new_with_model_app_foundations_skill_manager_and_owner<C>(
        storage: Storage,
        model: C,
        skill_manager: SkillManager,
        runtime_config: RuntimeConfig,
        app_prompt: AppPromptConfig,
        foundations: AppFoundationRuntimes,
        owner_management: OwnerApiConfig,
    ) -> Self
    where
        C: ModelClient + 'static,
    {
        let AppFoundationRuntimes {
            memory_tools,
            task_tools,
            automation_tools,
            attachment_tools,
            connector_tools,
            mail_actions,
        } = foundations;
        let model: Arc<dyn ModelClient> = Arc::new(model);
        let mut runner = TurnRunner::new_with_manager_and_config(
            SharedModelClient(model.clone()),
            skill_manager.clone(),
            runtime_config.clone(),
        )
        .with_app_prompt(app_prompt.clone())
        .with_skill_management(owner_management.management_service());
        if let Some(memory) = &memory_tools {
            runner = runner
                .with_memory_tools(memory.clone())
                .with_memory_candidate_extractor(Arc::new(
                    agent_runtime::memory_lifecycle::ExplicitMemoryCandidateExtractor,
                ));
        }
        if let Some(tasks) = &task_tools {
            runner = runner.with_task_tools(tasks.clone());
        }
        if let Some(automation) = &automation_tools {
            runner = runner.with_automation_tools(automation.clone());
        }
        if let Some(attachments) = &attachment_tools {
            runner = runner.with_attachment_tools(attachments.clone());
        }
        if let Some(connectors) = &connector_tools {
            runner = runner.with_connector_tools(connectors.clone());
        }
        if let Some(actions) = &mail_actions {
            runner = runner.with_mail_actions(actions.clone());
        }
        let conversation_scope = ConversationScope::local(&app_prompt.identity.app_id);
        let structured_content_tools =
            Self::new_structured_content_tools(&storage, &conversation_scope);
        runner = runner.with_structured_content_tools(structured_content_tools.clone());
        Self {
            storage,
            agent: Arc::new(runner),
            model: Some(model),
            skill_manager,
            skills_root: None,
            runtime_config,
            dev_skill_mutations: Arc::new(Mutex::new(())),
            owner_management: Some(owner_management),
            app_prompt,
            host_discovery: None,
            conversation_scope,
            conversation_locks: Arc::new(Mutex::new(BTreeMap::new())),
            turn_coordinator: crate::turn_api::TurnCoordinator::default(),
            memory_tools,
            task_tools,
            automation_tools,
            structured_content_tools,
            attachment_tools,
            data_protection: None,
            connector_tools,
            mail_actions,
            calendar_actions: None,
            contacts_actions: None,
            mail_account_manager: None,
            automation: None,
            oauth_broker: None,
            identity_runtime: None,
            developer_control_plane: None,
        }
    }

    #[cfg(test)]
    pub fn new(storage: Storage) -> Self {
        Self::new_with_agent(storage, Arc::new(DeterministicAgent))
    }

    #[cfg(test)]
    pub fn new_with_agent(storage: Storage, agent: Arc<dyn AgentRunner>) -> Self {
        Self::new_with_agent_and_skill_manager(
            storage,
            agent,
            SkillManager::from_registry_and_catalog(SkillRegistry::empty(), SkillCatalog::empty()),
        )
    }

    #[cfg(test)]
    pub fn new_with_agent_and_skills(
        storage: Storage,
        agent: Arc<dyn AgentRunner>,
        skills: SkillRegistry,
    ) -> Self {
        Self::new_with_agent_and_skill_manager(
            storage,
            agent,
            SkillManager::from_registry_and_catalog(skills, SkillCatalog::empty()),
        )
    }

    #[cfg(test)]
    pub fn new_with_agent_and_skill_manager(
        storage: Storage,
        agent: Arc<dyn AgentRunner>,
        skill_manager: SkillManager,
    ) -> Self {
        let conversation_scope = ConversationScope::default();
        let structured_content_tools =
            Self::new_structured_content_tools(&storage, &conversation_scope);
        Self {
            storage,
            agent,
            model: None,
            skill_manager,
            skills_root: None,
            runtime_config: default_runtime_config(),
            dev_skill_mutations: Arc::new(Mutex::new(())),
            owner_management: None,
            app_prompt: AppPromptConfig::default(),
            host_discovery: None,
            conversation_scope,
            conversation_locks: Arc::new(Mutex::new(BTreeMap::new())),
            turn_coordinator: crate::turn_api::TurnCoordinator::default(),
            memory_tools: None,
            task_tools: None,
            automation_tools: None,
            structured_content_tools,
            attachment_tools: None,
            data_protection: None,
            connector_tools: None,
            mail_actions: None,
            calendar_actions: None,
            contacts_actions: None,
            mail_account_manager: None,
            automation: None,
            oauth_broker: None,
            identity_runtime: None,
            developer_control_plane: None,
        }
    }

    #[cfg(test)]
    pub fn with_runtime_config(mut self, runtime_config: RuntimeConfig) -> Self {
        self.runtime_config = runtime_config;
        self
    }

    pub fn with_connector_actions(
        mut self,
        mail_actions: Option<agent_runtime::foundation_actions::MailActionService>,
        calendar_actions: Option<agent_runtime::calendar_actions::CalendarActionService>,
        contacts_actions: Option<agent_runtime::contacts_actions::ContactsActionService>,
    ) -> Self {
        if self
            .runtime_config
            .agent_app_policy
            .as_ref()
            .is_some_and(|policy| {
                policy.external_side_effects()
                    == agent_runtime::app_manifest::ExternalSideEffectPolicy::Deny
            })
        {
            return self;
        }
        self.mail_actions = mail_actions;
        self.calendar_actions = calendar_actions;
        self.contacts_actions = contacts_actions;
        self
    }

    pub async fn with_default_automation(mut self, storage: &Storage) -> anyhow::Result<Self> {
        self.automation =
            Some(crate::automation_api::AutomationApiState::from_storage(storage).await?);
        Ok(self)
    }

    pub fn with_oauth_broker(mut self, oauth_broker: agent_runtime::oauth::OAuthBroker) -> Self {
        self.oauth_broker = Some(oauth_broker);
        self
    }

    pub fn with_identity_runtime(
        mut self,
        identity_runtime: crate::identity_api::IdentityRuntime,
    ) -> Self {
        self.identity_runtime = Some(identity_runtime);
        self
    }

    pub fn with_developer_control_plane(
        mut self,
        control_plane: crate::developer_control_plane::DeveloperControlPlane,
    ) -> Self {
        self.developer_control_plane = Some(Arc::new(control_plane));
        self
    }
    pub fn with_task_foundation(
        mut self,
        task_tools: agent_runtime::task_tools::TaskToolRuntime,
    ) -> Self {
        self.task_tools = Some(task_tools);
        self
    }

    pub fn with_automation_foundation(
        mut self,
        automation_tools: agent_runtime::automation_tools::AutomationToolRuntime,
    ) -> Self {
        self.automation_tools = Some(automation_tools);
        self
    }

    pub fn with_attachment_foundation(
        mut self,
        attachment_tools: agent_runtime::attachment_tools::AttachmentToolRuntime,
    ) -> Self {
        self.attachment_tools = Some(attachment_tools);
        self
    }

    #[cfg(test)]
    pub fn with_skill_catalog(mut self, skill_catalog: SkillCatalog) -> Self {
        let registry = self.skill_manager.current_snapshot().registry().clone();
        self.skill_manager = SkillManager::from_registry_and_catalog(registry, skill_catalog);
        self
    }

    #[cfg(test)]
    pub fn with_skill_manager(mut self, skill_manager: SkillManager) -> Self {
        self.skill_manager = skill_manager;
        self
    }

    pub fn with_skills_root(mut self, skills_root: PathBuf) -> Self {
        self.skills_root = Some(skills_root);
        self
    }

    pub fn with_host_discovery(
        mut self,
        host_discovery: Option<AgentAppHostDiscovery>,
    ) -> anyhow::Result<Self> {
        if let Some(discovery) = &host_discovery {
            anyhow::ensure!(
                discovery.identity.app_id == self.app_prompt.identity.app_id
                    && discovery.identity.version == self.app_prompt.identity.version
                    && discovery.identity.display_name == self.app_prompt.identity.display_name,
                "Host discovery identity does not match the active App prompt"
            );
            let prompt_capabilities = self
                .app_prompt
                .identity
                .enabled_capabilities
                .iter()
                .cloned()
                .collect::<BTreeSet<_>>();
            anyhow::ensure!(
                discovery.requirements.capabilities == prompt_capabilities,
                "Host discovery capabilities do not match the active App prompt"
            );
        }
        self.host_discovery = host_discovery;
        Ok(self)
    }
}

pub fn router(state: Arc<AppState>) -> Router {
    router_for_transport(state, false, None)
}

pub fn router_with_dev_routes(state: Arc<AppState>) -> Router {
    router_for_transport(state, true, None)
}

pub fn router_for_transport(
    state: Arc<AppState>,
    include_dev_routes: bool,
    transport_auth: Option<crate::local_transport::TransportAuth>,
) -> Router {
    let user_router = Router::new()
        .route("/sessions/{session_id}/messages", post(post_message))
        .merge(crate::conversation_api::routes())
        .merge(crate::turn_api::routes())
        .merge(crate::foundation_api::router())
        .merge(crate::task_api::router())
        .merge(crate::attachment_api::router())
        .merge(crate::data_protection_api::router())
        .merge(crate::automation_api::router())
        .merge(crate::structured_content_api::router())
        .merge(crate::oauth_api::protected_router())
        .route_layer(middleware::from_fn_with_state(
            state.clone(),
            crate::identity_api::require_identity,
        ));
    let mut router = Router::new()
        .route("/health", get(|| async { "ok" }))
        .route("/model/test", post(test_model_connection))
        .route("/host/bootstrap", get(host_bootstrap))
        .route("/diagnostics/app", get(app_diagnostics))
        .merge(crate::identity_api::routes())
        .merge(user_router);
    if let Some(owner_routes) = crate::owner_api::router(&state) {
        router = router.merge(owner_routes);
    }
    if include_dev_routes {
        router = router
            .merge(crate::dev_api::routes())
            .merge(crate::developer_control_plane_api::routes());
    }
    let callback_router = crate::oauth_api::callback_router().route_layer(
        middleware::from_fn_with_state(state.clone(), crate::identity_api::require_identity),
    );
    let router = match transport_auth {
        Some(auth) => router
            .route_layer(middleware::from_fn_with_state(
                auth,
                crate::local_transport::require_transport,
            ))
            .merge(callback_router),
        None => router.merge(callback_router).layer(desktop_cors_layer()),
    };
    router.with_state(state)
}

impl AppState {
    pub(crate) fn skills(&self) -> SkillRegistry {
        self.skill_manager.current_snapshot().registry().clone()
    }

    pub(crate) fn runtime_config(&self) -> RuntimeConfig {
        self.runtime_config.clone()
    }

    pub(crate) fn skill_catalog(&self) -> SkillCatalog {
        self.skill_manager.current_snapshot().catalog().clone()
    }

    pub(crate) fn skill_manager(&self) -> SkillManager {
        self.skill_manager.clone()
    }

    pub(crate) fn skills_root(&self) -> Option<PathBuf> {
        self.skills_root.clone()
    }

    pub(crate) fn dev_skill_mutations(&self) -> &Mutex<()> {
        &self.dev_skill_mutations
    }

    pub(crate) fn owner_management(&self) -> Option<&OwnerApiConfig> {
        self.owner_management.as_ref()
    }

    pub(crate) fn app_prompt(&self) -> &AppPromptConfig {
        &self.app_prompt
    }

    pub fn app_id(&self) -> &str {
        &self.app_prompt.identity.app_id
    }

    pub(crate) fn host_discovery(&self) -> Option<&AgentAppHostDiscovery> {
        self.host_discovery.as_ref()
    }

    pub(crate) fn identity_runtime(&self) -> Option<&crate::identity_api::IdentityRuntime> {
        self.identity_runtime.as_ref()
    }

    pub(crate) fn developer_control_plane(
        &self,
    ) -> Option<&crate::developer_control_plane::DeveloperControlPlane> {
        self.developer_control_plane.as_deref()
    }

    pub(crate) fn allows_user_model_configuration(&self) -> bool {
        self.host_discovery.as_ref().is_none_or(|discovery| {
            discovery.access.model_access.configuration_policy
                == agent_runtime::app_manifest::AgentAppModelConfigurationPolicy::UserConfigurable
        })
    }

    pub(crate) fn conversation_scope(&self) -> &ConversationScope {
        &self.conversation_scope
    }

    pub(crate) fn storage(&self) -> &Storage {
        &self.storage
    }

    pub(crate) async fn conversation_lock(&self, session_id: &str) -> Arc<Mutex<()>> {
        let mut locks = self.conversation_locks.lock().await;
        locks.retain(|_, lock| lock.strong_count() > 0);
        if let Some(lock) = locks.get(session_id).and_then(Weak::upgrade) {
            return lock;
        }
        let lock = Arc::new(Mutex::new(()));
        locks.insert(session_id.to_string(), Arc::downgrade(&lock));
        lock
    }

    pub(crate) fn turn_coordinator(&self) -> &crate::turn_api::TurnCoordinator {
        &self.turn_coordinator
    }
}

async fn app_diagnostics(State(state): State<Arc<AppState>>) -> Json<AppDiagnosticsResponse> {
    let identity = &state.app_prompt().identity;
    Json(AppDiagnosticsResponse {
        app_id: identity.app_id.clone(),
        version: identity.version.clone(),
        display_name: identity.display_name.clone(),
    })
}

async fn host_bootstrap(
    State(state): State<Arc<AppState>>,
) -> Result<Json<AgentAppHostDiscovery>, ApiError> {
    state
        .host_discovery()
        .cloned()
        .map(Json)
        .ok_or(ApiError::NotFound("resolved Agent App is unavailable"))
}

pub(crate) fn desktop_cors_layer() -> CorsLayer {
    CorsLayer::new()
        .allow_origin([
            HeaderValue::from_static("http://127.0.0.1:5173"),
            HeaderValue::from_static("http://localhost:5173"),
        ])
        .allow_methods([
            Method::GET,
            Method::POST,
            Method::PUT,
            Method::PATCH,
            Method::DELETE,
        ])
        .allow_headers([header::CONTENT_TYPE, header::AUTHORIZATION])
}

async fn test_model_connection(
    State(state): State<Arc<AppState>>,
    Json(request): Json<ModelConnectionTestRequest>,
) -> Result<Json<ModelConnectionTestResponse>, ApiError> {
    if !state.allows_user_model_configuration() {
        return Err(ApiError::BadRequest(
            "model settings are managed by the Agent App",
        ));
    }
    let profile = provider_profile_from_request(request)?;
    let client = GatewayHttpClient::new(profile);

    let mut events = client
        .stream(test_connection_gateway_request())
        .await
        .map_err(ApiError::ConnectionFailed)?;
    while let Some(event) = events.next().await {
        match event.map_err(ApiError::ConnectionFailed)? {
            model_gateway::responses::GatewayEvent::Error { message } => {
                return Err(ApiError::ConnectionFailed(anyhow::anyhow!(message)));
            }
            model_gateway::responses::GatewayEvent::Completed => break,
            _ => {}
        }
    }

    Ok(Json(ModelConnectionTestResponse {
        ok: true,
        message: "Connection succeeded".into(),
    }))
}

async fn post_message(
    Path(session_id): Path<String>,
    State(state): State<Arc<AppState>>,
    Extension(security): Extension<crate::identity_api::RequestSecurityContext>,
    Json(request): Json<UserMessageRequest>,
) -> Result<Json<UserMessageResponse>, ApiError> {
    post_message_for_actor_scoped(
        session_id,
        state,
        request,
        ActorContext::anonymous(),
        security,
    )
    .await
}

pub(crate) async fn post_message_for_actor(
    session_id: String,
    state: Arc<AppState>,
    request: UserMessageRequest,
    actor: ActorContext,
) -> Result<Json<UserMessageResponse>, ApiError> {
    let security = crate::identity_api::RequestSecurityContext::local(state.conversation_scope());
    post_message_for_actor_scoped(session_id, state, request, actor, security).await
}

async fn post_message_for_actor_scoped(
    session_id: String,
    state: Arc<AppState>,
    request: UserMessageRequest,
    actor: ActorContext,
    security: crate::identity_api::RequestSecurityContext,
) -> Result<Json<UserMessageResponse>, ApiError> {
    validate_model_override(&state, request.model_settings.is_some())?;
    let scope = security.conversation_scope();
    let conversation_lock = state.conversation_lock(&session_id).await;
    let _conversation_guard = conversation_lock.lock().await;
    let session_exists = state
        .storage
        .session_exists_scoped(scope, &session_id)
        .await
        .map_err(ApiError::Internal)?;
    if !session_exists {
        return Err(ApiError::NotFound("session not found"));
    }

    let history = state
        .storage
        .list_scoped_messages(scope, &session_id)
        .await
        .map_err(ApiError::Internal)?;
    let history = messages_to_model_history(&history).map_err(ApiError::Internal)?;
    let events =
        run_agent_turn_for_actor_scoped(&state, &session_id, &request, actor, history, &security)
            .await?;
    let assistant_text = assistant_text_from_events(&events)
        .ok_or_else(|| ApiError::Internal(anyhow::anyhow!("agent turn did not finish")))?;
    let (user_message, assistant_message) = state
        .storage
        .append_scoped_turn_with_events(
            scope,
            &session_id,
            &request.content,
            &assistant_text,
            &events,
        )
        .await
        .map_err(ApiError::Internal)?;

    Ok(Json(UserMessageResponse {
        accepted: true,
        user_message,
        assistant_message,
        events,
    }))
}

#[cfg(test)]
async fn run_agent_turn_for_actor(
    state: &AppState,
    session_id: &str,
    request: &UserMessageRequest,
    actor: ActorContext,
    history: Vec<serde_json::Value>,
) -> Result<Vec<RuntimeEvent>, ApiError> {
    let security = crate::identity_api::RequestSecurityContext::local(state.conversation_scope());
    run_agent_turn_for_actor_scoped(state, session_id, request, actor, history, &security).await
}

async fn run_agent_turn_for_actor_scoped(
    state: &AppState,
    session_id: &str,
    request: &UserMessageRequest,
    actor: ActorContext,
    history: Vec<serde_json::Value>,
    security: &crate::identity_api::RequestSecurityContext,
) -> Result<Vec<RuntimeEvent>, ApiError> {
    run_agent_turn_internal(state, session_id, request, actor, history, security, None).await
}

#[allow(clippy::too_many_arguments)]
pub(crate) async fn run_agent_turn_observed_for_actor(
    state: &AppState,
    session_id: &str,
    turn_id: &str,
    request: &UserMessageRequest,
    actor: ActorContext,
    history: Vec<serde_json::Value>,
    security: &crate::identity_api::RequestSecurityContext,
    observer: RuntimeEventObserver,
) -> Result<Vec<RuntimeEvent>, ApiError> {
    run_agent_turn_internal(
        state,
        session_id,
        request,
        actor,
        history,
        security,
        Some((turn_id, observer)),
    )
    .await
}

async fn run_agent_turn_internal(
    state: &AppState,
    session_id: &str,
    request: &UserMessageRequest,
    actor: ActorContext,
    history: Vec<serde_json::Value>,
    security: &crate::identity_api::RequestSecurityContext,
    observer: Option<(&str, RuntimeEventObserver)>,
) -> Result<Vec<RuntimeEvent>, ApiError> {
    validate_model_override(state, request.model_settings.is_some())?;
    let build_request = |turn_id: Option<&str>| {
        let request = TurnRequest::new(&request.content)
            .with_session_id(session_id)
            .with_conversation_history(history.clone())
            .with_actor_context(actor.clone());
        match turn_id {
            Some(turn_id) => request.with_turn_id(turn_id),
            None => request,
        }
    };
    let model = if let Some(model_settings) = request.model_settings.clone() {
        TurnModelClient::Override(GatewayHttpClient::new(provider_profile_from_request(
            model_settings,
        )?))
    } else if let Some(model) = &state.model {
        TurnModelClient::Shared(SharedModelClient(model.clone()))
    } else {
        if security.is_authenticated() {
            return Err(ApiError::Internal(anyhow::anyhow!(
                "authenticated turn has no Host-owned model runtime"
            )));
        }
        return match observer {
            Some((turn_id, observer)) => {
                state
                    .agent
                    .run_request_observed(build_request(Some(turn_id)), observer)
                    .await
            }
            None => state.agent.run_request(build_request(None)).await,
        }
        .map_err(agent_turn_error);
    };

    let mut runner = TurnRunner::new_with_manager_and_config(
        model,
        state.skill_manager(),
        state.runtime_config.clone(),
    )
    .with_app_prompt(state.app_prompt.clone());
    if let Some(owner_management) = state.owner_management() {
        runner = runner.with_skill_management(owner_management.management_service());
    }
    if let Some(memory) = state
        .memory_tools_for(security)
        .map_err(ApiError::Internal)?
    {
        runner = runner
            .with_memory_tools(memory)
            .with_memory_candidate_extractor(Arc::new(
                agent_runtime::memory_lifecycle::ExplicitMemoryCandidateExtractor,
            ));
    }
    if let Some(tasks) = state.task_tools_for(security).map_err(ApiError::Internal)? {
        runner = runner.with_task_tools(tasks);
    }
    if let Some(automation) = state
        .automation_tools_for(security)
        .map_err(ApiError::Internal)?
    {
        runner = runner.with_automation_tools(automation);
    }
    runner = runner.with_structured_content_tools(state.structured_content_for(security));
    if let Some(attachments) = state
        .attachment_tools_for(security)
        .map_err(ApiError::Internal)?
    {
        runner = runner.with_attachment_tools(attachments);
    }
    if let Some(connectors) = state
        .connector_tools_for(security)
        .map_err(ApiError::Internal)?
    {
        runner = runner.with_connector_tools(connectors);
    }
    if !security.is_authenticated()
        && let Some(actions) = &state.mail_actions
    {
        runner = runner.with_mail_actions(actions.clone());
    }

    match observer {
        Some((turn_id, observer)) => {
            runner
                .run_request_observed(build_request(Some(turn_id)), observer)
                .await
        }
        None => runner.run_request(build_request(None)).await,
    }
    .map_err(agent_turn_error)
}

#[cfg(test)]
#[path = "api_tests.rs"]
mod tests;

#[cfg(test)]
#[path = "api_host_bootstrap_tests.rs"]
mod host_bootstrap_tests;

#[cfg(test)]
#[path = "model_access_api_tests.rs"]
mod model_access_tests;

#[cfg(test)]
#[path = "api_conversation_tests.rs"]
mod conversation_tests;

#[cfg(test)]
#[path = "api_automation_tests.rs"]
mod automation_tests;

#[cfg(test)]
#[path = "api_foundation_tests.rs"]
mod foundation_tests;

#[cfg(test)]
#[path = "api_task_tests.rs"]
mod task_tests;
