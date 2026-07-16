pub use crate::api_foundations::AppFoundationRuntimes;
use crate::owner_api::OwnerApiConfig;
use agent_runtime::{
    app_definition::AgentAppHostDiscovery,
    events::RuntimeEvent,
    prompt_composer::AppPromptConfig,
    session::{ConversationScope, Message, messages_to_model_history},
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
    extract::{Path, State},
    http::{HeaderValue, Method, StatusCode, header},
    middleware,
    response::{IntoResponse, Response},
    routing::{get, post},
};
use futures::StreamExt;
use model_gateway::{
    provider::{EndpointType, ProviderProfile},
    responses::{GatewayHttpClient, GatewayRequest},
};
use serde::{Deserialize, Serialize};
use std::{
    collections::{BTreeMap, BTreeSet},
    path::PathBuf,
    sync::{Arc, Weak},
};
use tokio::sync::Mutex;
use tower_http::cors::CorsLayer;

mod runtime_tools;
#[cfg(test)]
mod test_support;
#[cfg(test)]
use test_support::{DeterministicAgent, default_runtime_config};
#[derive(Clone)]
pub struct AppState {
    storage: Storage,
    agent: Arc<dyn AgentRunner>,
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
        let mut runner = TurnRunner::new_with_manager_and_config(
            model,
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
        let mut runner = TurnRunner::new_with_manager_and_config(
            model,
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

#[derive(Debug, Serialize)]
pub struct AppDiagnosticsResponse {
    pub app_id: String,
    pub version: String,
    pub display_name: String,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct UserMessageRequest {
    pub content: String,
    #[serde(default)]
    pub model_settings: Option<ModelConnectionTestRequest>,
}

#[derive(Debug, Serialize)]
pub struct UserMessageResponse {
    pub accepted: bool,
    pub user_message: Message,
    pub assistant_message: Message,
    pub events: Vec<RuntimeEvent>,
}

#[derive(Clone, Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ModelConnectionTestRequest {
    #[serde(default)]
    pub api_key: Option<String>,
    pub base_url: String,
    pub endpoint_type: EndpointType,
    pub model_name: String,
}

#[derive(Debug, Serialize)]
pub struct ModelConnectionTestResponse {
    pub ok: bool,
    pub message: String,
}

#[derive(Debug, Serialize)]
pub struct ErrorResponse {
    pub error: String,
}

#[derive(Debug)]
pub(crate) enum ApiError {
    BadRequest(&'static str),
    Conflict(&'static str),
    ConnectionFailed(anyhow::Error),
    NotFound(&'static str),
    PayloadTooLarge(&'static str),
    Internal(anyhow::Error),
}

impl IntoResponse for ApiError {
    fn into_response(self) -> Response {
        let (status, error) = match self {
            Self::BadRequest(message) => (StatusCode::BAD_REQUEST, message.to_string()),
            Self::Conflict(message) => (StatusCode::CONFLICT, message.to_string()),
            Self::ConnectionFailed(error) => (
                StatusCode::BAD_GATEWAY,
                format!("connection failed: {error}"),
            ),
            Self::NotFound(message) => (StatusCode::NOT_FOUND, message.to_string()),
            Self::PayloadTooLarge(message) => (StatusCode::PAYLOAD_TOO_LARGE, message.to_string()),
            Self::Internal(error) => {
                tracing::error!(?error, "agent-server request failed");
                (
                    StatusCode::INTERNAL_SERVER_ERROR,
                    "internal server error".to_string(),
                )
            }
        };

        (status, Json(ErrorResponse { error })).into_response()
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
    let mut router = Router::new()
        .route("/health", get(|| async { "ok" }))
        .route("/model/test", post(test_model_connection))
        .route("/host/bootstrap", get(host_bootstrap))
        .route("/diagnostics/app", get(app_diagnostics))
        .route("/sessions/{session_id}/messages", post(post_message))
        .merge(crate::conversation_api::routes())
        .merge(crate::turn_api::routes());
    router = router
        .merge(crate::foundation_api::router())
        .merge(crate::task_api::router())
        .merge(crate::attachment_api::router())
        .merge(crate::data_protection_api::router())
        .merge(crate::automation_api::router())
        .merge(crate::structured_content_api::router())
        .merge(crate::oauth_api::protected_router());
    if let Some(owner_routes) = crate::owner_api::router(&state) {
        router = router.merge(owner_routes);
    }
    if include_dev_routes {
        router = router.merge(crate::dev_api::routes());
    }
    let callback_router = crate::oauth_api::callback_router();
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

    pub(crate) fn host_discovery(&self) -> Option<&AgentAppHostDiscovery> {
        self.host_discovery.as_ref()
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
    Json(request): Json<ModelConnectionTestRequest>,
) -> Result<Json<ModelConnectionTestResponse>, ApiError> {
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
    Json(request): Json<UserMessageRequest>,
) -> Result<Json<UserMessageResponse>, ApiError> {
    post_message_for_actor(session_id, state, request, ActorContext::anonymous()).await
}

pub(crate) async fn post_message_for_actor(
    session_id: String,
    state: Arc<AppState>,
    request: UserMessageRequest,
    actor: ActorContext,
) -> Result<Json<UserMessageResponse>, ApiError> {
    let conversation_lock = state.conversation_lock(&session_id).await;
    let _conversation_guard = conversation_lock.lock().await;
    let session_exists = state
        .storage
        .session_exists_scoped(state.conversation_scope(), &session_id)
        .await
        .map_err(ApiError::Internal)?;
    if !session_exists {
        return Err(ApiError::NotFound("session not found"));
    }

    let history = state
        .storage
        .list_scoped_messages(state.conversation_scope(), &session_id)
        .await
        .map_err(ApiError::Internal)?;
    let history = messages_to_model_history(&history).map_err(ApiError::Internal)?;
    let events = run_agent_turn_for_actor(&state, &session_id, &request, actor, history).await?;
    let assistant_text = assistant_text_from_events(&events)
        .ok_or_else(|| ApiError::Internal(anyhow::anyhow!("agent turn did not finish")))?;
    let (user_message, assistant_message) = state
        .storage
        .append_scoped_turn_with_events(
            state.conversation_scope(),
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

async fn run_agent_turn_for_actor(
    state: &AppState,
    session_id: &str,
    request: &UserMessageRequest,
    actor: ActorContext,
    history: Vec<serde_json::Value>,
) -> Result<Vec<RuntimeEvent>, ApiError> {
    run_agent_turn_internal(state, session_id, request, actor, history, None).await
}

pub(crate) async fn run_agent_turn_observed_for_actor(
    state: &AppState,
    session_id: &str,
    turn_id: &str,
    request: &UserMessageRequest,
    actor: ActorContext,
    history: Vec<serde_json::Value>,
    observer: RuntimeEventObserver,
) -> Result<Vec<RuntimeEvent>, ApiError> {
    run_agent_turn_internal(
        state,
        session_id,
        request,
        actor,
        history,
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
    observer: Option<(&str, RuntimeEventObserver)>,
) -> Result<Vec<RuntimeEvent>, ApiError> {
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
    if let Some(model_settings) = request.model_settings.clone() {
        let profile = provider_profile_from_request(model_settings)?;
        let mut runner = TurnRunner::new_with_manager_and_config(
            GatewayHttpClient::new(profile),
            state.skill_manager(),
            state.runtime_config.clone(),
        )
        .with_app_prompt(state.app_prompt.clone());
        if let Some(owner_management) = state.owner_management() {
            runner = runner.with_skill_management(owner_management.management_service());
        }
        if let Some(memory) = &state.memory_tools {
            runner = runner
                .with_memory_tools(memory.clone())
                .with_memory_candidate_extractor(Arc::new(
                    agent_runtime::memory_lifecycle::ExplicitMemoryCandidateExtractor,
                ));
        }
        if let Some(tasks) = &state.task_tools {
            runner = runner.with_task_tools(tasks.clone());
        }
        if let Some(automation) = &state.automation_tools {
            runner = runner.with_automation_tools(automation.clone());
        }
        runner = runner.with_structured_content_tools(state.structured_content_tools.clone());
        if let Some(attachments) = &state.attachment_tools {
            runner = runner.with_attachment_tools(attachments.clone());
        }
        if let Some(connectors) = &state.connector_tools {
            runner = runner.with_connector_tools(connectors.clone());
        }
        if let Some(actions) = &state.mail_actions {
            runner = runner.with_mail_actions(actions.clone());
        }

        return match observer {
            Some((turn_id, observer)) => {
                runner
                    .run_request_observed(build_request(Some(turn_id)), observer)
                    .await
            }
            None => runner.run_request(build_request(None)).await,
        }
        .map_err(agent_turn_error);
    }

    match observer {
        Some((turn_id, observer)) => {
            state
                .agent
                .run_request_observed(build_request(Some(turn_id)), observer)
                .await
        }
        None => state.agent.run_request(build_request(None)).await,
    }
    .map_err(agent_turn_error)
}

fn agent_turn_error(error: anyhow::Error) -> ApiError {
    let message = error.to_string();
    if message.contains("model_endpoint_does_not_support_tools") {
        ApiError::BadRequest("model endpoint does not support runtime tools")
    } else if message.contains("upstream model request failed") {
        ApiError::ConnectionFailed(error)
    } else {
        ApiError::Internal(error)
    }
}

fn assistant_text_from_events(events: &[RuntimeEvent]) -> Option<String> {
    events.iter().find_map(|event| {
        if let RuntimeEvent::AssistantMessageFinished { text } = event {
            Some(text.clone())
        } else {
            None
        }
    })
}

fn provider_profile_from_request(
    request: ModelConnectionTestRequest,
) -> Result<ProviderProfile, ApiError> {
    let base_url = request.base_url.trim();
    if base_url.is_empty() {
        return Err(ApiError::BadRequest("base URL is required"));
    }

    let model = request.model_name.trim();
    if model.is_empty() {
        return Err(ApiError::BadRequest("model name is required"));
    }

    Ok(ProviderProfile {
        id: "settings-test".into(),
        name: "Settings Test".into(),
        endpoint_type: request.endpoint_type,
        base_url: base_url.to_string(),
        model: model.to_string(),
        api_key: request.api_key.and_then(|api_key| {
            let trimmed = api_key.trim();
            if trimmed.is_empty() {
                None
            } else {
                Some(trimmed.to_string())
            }
        }),
        headers: BTreeMap::new(),
    })
}

fn test_connection_gateway_request() -> GatewayRequest {
    GatewayRequest {
        input: vec![serde_json::json!({
            "role": "user",
            "content": "Reply with ok to confirm this connection."
        })],
        tools: Vec::new(),
    }
}

#[cfg(test)]
#[path = "api_tests.rs"]
mod tests;

#[cfg(test)]
#[path = "api_host_bootstrap_tests.rs"]
mod host_bootstrap_tests;

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
