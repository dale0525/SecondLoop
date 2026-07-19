use crate::events::RuntimeEvent;
use crate::model_config::StoredModelConfig;
use crate::platform::{CapabilitySet, PlatformId};
use crate::prompt_composer::AppPromptConfig;
use crate::session::{ConversationScope, Message, Session, messages_to_model_history};
use crate::skill::SkillRegistry;
use crate::skill_catalog::SkillCatalog;
use crate::skill_management::OwnerSkillManagementService;
use crate::skill_manager::SkillManager;
use crate::skill_policy::ActorContext;
use crate::storage::Storage;
use crate::tools::RuntimeConfig;
use crate::turn::{ModelClient, TurnRunner};
use serde::{Deserialize, Serialize};
use std::sync::Arc;

#[derive(Debug, Clone, Deserialize, Serialize, PartialEq, Eq)]
pub struct MobileRuntimeInit {
    pub platform: PlatformId,
    pub capabilities: CapabilitySet,
}

#[derive(Debug, Clone, Deserialize, Serialize, PartialEq)]
pub struct MobileTurnResult {
    pub assistant_text: String,
    pub events: Vec<RuntimeEvent>,
}

#[derive(Debug, Clone, Deserialize, Serialize, PartialEq, Eq)]
pub struct MobileRuntimeDiagnostics {
    pub platform: PlatformId,
    pub capabilities: CapabilitySet,
    pub built_in_tools_enabled: bool,
    pub registered_skill_tool_count: usize,
    pub configured_external_tool_count: usize,
    pub configured_connector_count: usize,
}

#[async_trait::async_trait]
pub trait SecretResolver: Send + Sync {
    async fn resolve_secret(&self, secret_id: &str) -> anyhow::Result<Option<String>>;
}

pub async fn resolve_model_api_key<R>(
    model_config: &StoredModelConfig,
    resolver: &R,
) -> anyhow::Result<Option<String>>
where
    R: SecretResolver,
{
    match &model_config.secret_id {
        Some(secret_id) => resolver.resolve_secret(secret_id).await,
        None => Ok(None),
    }
}

pub struct MobileRuntimeHost<C> {
    storage: Storage,
    model: Arc<C>,
    skill_manager: SkillManager,
    runtime_config: RuntimeConfig,
    init: MobileRuntimeInit,
    app_prompt: AppPromptConfig,
    conversation_scope: ConversationScope,
    memory: Option<crate::memory_tools::MemoryToolRuntime>,
    connector_tools: Option<crate::connector_tools::ConnectorToolRuntime>,
    mail_actions: Option<crate::foundation_actions::MailActionService>,
}

impl<C> MobileRuntimeHost<C>
where
    C: ModelClient,
{
    pub fn new_for_test(
        storage: Storage,
        model: C,
        skills: SkillRegistry,
        skill_catalog: SkillCatalog,
        runtime_config: RuntimeConfig,
        init: MobileRuntimeInit,
    ) -> Self {
        let skill_manager = SkillManager::from_registry_and_catalog_with_context(
            skills,
            skill_catalog,
            init.platform,
            init.capabilities.clone(),
        );
        Self::new_for_test_with_manager(storage, model, skill_manager, runtime_config, init)
            .expect("mobile manager created from init must have matching runtime context")
    }

    pub fn new_for_test_with_manager(
        storage: Storage,
        model: C,
        skill_manager: SkillManager,
        runtime_config: RuntimeConfig,
        init: MobileRuntimeInit,
    ) -> anyhow::Result<Self> {
        validate_mobile_manager_context(&init, &skill_manager)?;
        let runtime_config = mobile_safe_runtime_config(&init, runtime_config);
        let app_prompt = AppPromptConfig::default();
        let conversation_scope = ConversationScope::local(&app_prompt.identity.app_id);
        Ok(Self {
            storage,
            model: Arc::new(model),
            skill_manager,
            runtime_config,
            init,
            app_prompt,
            conversation_scope,
            memory: None,
            connector_tools: None,
            mail_actions: None,
        })
    }

    pub fn with_app_prompt(mut self, app_prompt: AppPromptConfig) -> Self {
        self.conversation_scope = ConversationScope::local(&app_prompt.identity.app_id);
        self.app_prompt = app_prompt;
        self
    }

    pub fn with_mail_actions(
        mut self,
        mail_actions: Option<crate::foundation_actions::MailActionService>,
    ) -> Self {
        self.mail_actions = mail_actions;
        self
    }

    pub fn with_foundations(
        mut self,
        memory: Option<crate::memory_tools::MemoryToolRuntime>,
        connector_tools: Option<crate::connector_tools::ConnectorToolRuntime>,
    ) -> Self {
        self.memory = memory;
        self.connector_tools = connector_tools;
        self
    }

    pub async fn create_session(&self, title: &str) -> anyhow::Result<Session> {
        self.storage
            .create_scoped_session(&self.conversation_scope, title)
            .await
    }

    pub async fn list_sessions(&self) -> anyhow::Result<Vec<Session>> {
        self.storage
            .list_scoped_sessions(&self.conversation_scope)
            .await
    }

    pub async fn get_messages(&self, session_id: &str) -> anyhow::Result<Vec<Message>> {
        self.storage
            .list_scoped_messages(&self.conversation_scope, session_id)
            .await
    }

    pub async fn delete_session(&self, session_id: &str) -> anyhow::Result<()> {
        if let Some(memory) = &self.memory {
            memory.on_session_end(session_id, Vec::new()).await?;
        }
        self.storage
            .delete_scoped_session(&self.conversation_scope, session_id)
            .await
    }

    pub fn init(&self) -> &MobileRuntimeInit {
        &self.init
    }

    pub fn diagnostics(&self) -> MobileRuntimeDiagnostics {
        let skill_manager = mobile_safe_snapshot_manager(&self.init, &self.skill_manager);
        let snapshot = skill_manager.current_snapshot();
        mobile_runtime_diagnostics(&self.init, &self.runtime_config, snapshot.registry())
    }

    pub async fn send_message(
        &self,
        session_id: &str,
        content: &str,
    ) -> anyhow::Result<MobileTurnResult> {
        if !self
            .storage
            .session_exists_scoped(&self.conversation_scope, session_id)
            .await?
        {
            anyhow::bail!("session not found");
        }
        self.storage
            .append_scoped_message(&self.conversation_scope, session_id, "user", content)
            .await?;
        self.send_message_after_user_persisted(session_id, content)
            .await
    }

    pub async fn send_message_after_user_persisted(
        &self,
        session_id: &str,
        content: &str,
    ) -> anyhow::Result<MobileTurnResult> {
        let mut messages = self
            .storage
            .list_scoped_messages(&self.conversation_scope, session_id)
            .await?;
        let current = messages
            .pop()
            .ok_or_else(|| anyhow::anyhow!("persisted user message is missing"))?;
        anyhow::ensure!(
            current.role == "user" && current.content == content,
            "persisted user message does not match the active turn"
        );
        let history = messages_to_model_history(&messages)?;
        let skill_manager = mobile_safe_snapshot_manager(&self.init, &self.skill_manager);
        let mut runner = TurnRunner::new_with_manager_and_config(
            self.model.clone(),
            skill_manager,
            self.runtime_config.clone(),
        )
        .with_app_prompt(self.app_prompt.clone());
        if let Some(memory) = &self.memory {
            runner = runner
                .with_memory_tools(memory.clone())
                .with_memory_candidate_extractor(Arc::new(
                    crate::memory_lifecycle::ExplicitMemoryCandidateExtractor,
                ));
        }
        if let Some(connectors) = &self.connector_tools {
            runner = runner.with_connector_tools(connectors.clone());
        }
        if let Some(actions) = &self.mail_actions {
            runner = runner.with_mail_actions(actions.clone());
        }
        let events = runner
            .run_request(
                crate::turn_request::TurnRequest::new(content)
                    .with_session_id(session_id)
                    .with_conversation_history(history),
            )
            .await?;
        let assistant_text = assistant_text_from_events(&events);
        self.storage
            .append_scoped_assistant_with_events(
                &self.conversation_scope,
                session_id,
                &assistant_text,
                &events,
            )
            .await?;
        Ok(MobileTurnResult {
            assistant_text,
            events,
        })
    }
}

pub struct HttpMobileRuntimeHost<R> {
    storage: Storage,
    skill_manager: SkillManager,
    runtime_config: RuntimeConfig,
    init: MobileRuntimeInit,
    model_config: StoredModelConfig,
    secret_resolver: R,
    management: Option<(OwnerSkillManagementService, ActorContext)>,
    app_prompt: AppPromptConfig,
    conversation_scope: ConversationScope,
    memory: Option<crate::memory_tools::MemoryToolRuntime>,
    connector_tools: Option<crate::connector_tools::ConnectorToolRuntime>,
    mail_actions: Option<crate::foundation_actions::MailActionService>,
    gateway_credential_provider:
        Option<Arc<dyn model_gateway::credentials::GatewayCredentialProvider>>,
}

impl<R> HttpMobileRuntimeHost<R>
where
    R: SecretResolver,
{
    #[deprecated(note = "production mobile hosts must use new_with_manager")]
    pub fn new(
        storage: Storage,
        skills: SkillRegistry,
        skill_catalog: SkillCatalog,
        runtime_config: RuntimeConfig,
        init: MobileRuntimeInit,
        model_config: StoredModelConfig,
        secret_resolver: R,
    ) -> Self {
        let skill_manager = SkillManager::from_registry_and_catalog_with_context(
            skills,
            skill_catalog,
            init.platform,
            init.capabilities.clone(),
        );
        Self::new_with_manager(
            storage,
            skill_manager,
            runtime_config,
            init,
            model_config,
            secret_resolver,
        )
        .expect("mobile manager created from init must have matching runtime context")
    }

    pub fn new_with_manager(
        storage: Storage,
        skill_manager: SkillManager,
        runtime_config: RuntimeConfig,
        init: MobileRuntimeInit,
        model_config: StoredModelConfig,
        secret_resolver: R,
    ) -> anyhow::Result<Self> {
        validate_mobile_manager_context(&init, &skill_manager)?;
        let runtime_config = mobile_safe_runtime_config(&init, runtime_config);
        let app_prompt = AppPromptConfig::default();
        let conversation_scope = ConversationScope::local(&app_prompt.identity.app_id);
        Ok(Self {
            storage,
            skill_manager,
            runtime_config,
            init,
            model_config,
            secret_resolver,
            management: None,
            app_prompt,
            conversation_scope,
            memory: None,
            connector_tools: None,
            mail_actions: None,
            gateway_credential_provider: None,
        })
    }

    pub fn with_app_prompt(mut self, app_prompt: AppPromptConfig) -> Self {
        self.conversation_scope = ConversationScope::local(&app_prompt.identity.app_id);
        self.app_prompt = app_prompt;
        self
    }

    pub fn with_conversation_scope(
        mut self,
        conversation_scope: ConversationScope,
    ) -> anyhow::Result<Self> {
        conversation_scope.validate()?;
        anyhow::ensure!(
            conversation_scope.app_id == self.app_prompt.identity.app_id,
            "mobile conversation scope does not match the active Agent App"
        );
        self.conversation_scope = conversation_scope;
        Ok(self)
    }

    pub fn with_gateway_credential_provider(
        mut self,
        provider: Option<Arc<dyn model_gateway::credentials::GatewayCredentialProvider>>,
    ) -> Self {
        self.gateway_credential_provider = provider;
        self
    }

    pub fn with_mail_actions(
        mut self,
        mail_actions: Option<crate::foundation_actions::MailActionService>,
    ) -> Self {
        self.mail_actions = mail_actions;
        self
    }

    pub fn with_foundations(
        mut self,
        memory: Option<crate::memory_tools::MemoryToolRuntime>,
        connector_tools: Option<crate::connector_tools::ConnectorToolRuntime>,
    ) -> Self {
        self.memory = memory;
        self.connector_tools = connector_tools;
        self
    }

    pub fn with_owner_turn_context(
        mut self,
        service: OwnerSkillManagementService,
        actor: ActorContext,
    ) -> Self {
        if service.policy().can_author_conversationally(&actor) {
            self.management = Some((service, actor));
        }
        self
    }

    pub async fn create_session(&self, title: &str) -> anyhow::Result<Session> {
        self.storage
            .create_scoped_session(&self.conversation_scope, title)
            .await
    }

    pub async fn list_sessions(&self) -> anyhow::Result<Vec<Session>> {
        self.storage
            .list_scoped_sessions(&self.conversation_scope)
            .await
    }

    pub async fn get_messages(&self, session_id: &str) -> anyhow::Result<Vec<Message>> {
        self.storage
            .list_scoped_messages(&self.conversation_scope, session_id)
            .await
    }

    pub async fn delete_session(&self, session_id: &str) -> anyhow::Result<()> {
        if let Some(memory) = &self.memory {
            memory.on_session_end(session_id, Vec::new()).await?;
        }
        self.storage
            .delete_scoped_session(&self.conversation_scope, session_id)
            .await
    }

    pub fn init(&self) -> &MobileRuntimeInit {
        &self.init
    }

    pub fn diagnostics(&self) -> MobileRuntimeDiagnostics {
        let skill_manager = mobile_safe_snapshot_manager(&self.init, &self.skill_manager);
        let snapshot = skill_manager.current_snapshot();
        mobile_runtime_diagnostics(&self.init, &self.runtime_config, snapshot.registry())
    }

    pub async fn send_message(
        &self,
        session_id: &str,
        content: &str,
    ) -> anyhow::Result<MobileTurnResult> {
        if !self
            .storage
            .session_exists_scoped(&self.conversation_scope, session_id)
            .await?
        {
            anyhow::bail!("session not found");
        }
        self.storage
            .append_scoped_message(&self.conversation_scope, session_id, "user", content)
            .await?;
        self.send_message_after_user_persisted(session_id, content)
            .await
    }

    pub async fn send_message_after_user_persisted(
        &self,
        session_id: &str,
        content: &str,
    ) -> anyhow::Result<MobileTurnResult> {
        let mut messages = self
            .storage
            .list_scoped_messages(&self.conversation_scope, session_id)
            .await?;
        let current = messages
            .pop()
            .ok_or_else(|| anyhow::anyhow!("persisted user message is missing"))?;
        anyhow::ensure!(
            current.role == "user" && current.content == content,
            "persisted user message does not match the active turn"
        );
        let history = messages_to_model_history(&messages)?;
        self.model_config
            .validate()
            .map_err(|message| anyhow::anyhow!(message))?;
        let api_key = resolve_model_api_key(&self.model_config, &self.secret_resolver).await?;
        let profile = self.model_config.to_provider_profile(api_key);
        let model = match &self.gateway_credential_provider {
            Some(provider) => {
                model_gateway::responses::GatewayHttpClient::with_credential_provider(
                    profile,
                    provider.clone(),
                )
            }
            None => model_gateway::responses::GatewayHttpClient::new(profile),
        };
        let skill_manager = mobile_safe_snapshot_manager(&self.init, &self.skill_manager);
        let mut runner = TurnRunner::new_with_manager_and_config(
            model,
            skill_manager,
            self.runtime_config.clone(),
        )
        .with_app_prompt(self.app_prompt.clone());
        if let Some(memory) = &self.memory {
            runner = runner
                .with_memory_tools(memory.clone())
                .with_memory_candidate_extractor(Arc::new(
                    crate::memory_lifecycle::ExplicitMemoryCandidateExtractor,
                ));
        }
        if let Some(connectors) = &self.connector_tools {
            runner = runner.with_connector_tools(connectors.clone());
        }
        if let Some(actions) = &self.mail_actions {
            runner = runner.with_mail_actions(actions.clone());
        }
        let events = if let Some((service, actor)) = &self.management {
            runner = runner.with_skill_management(service.clone());
            runner
                .run_request(
                    crate::turn_request::TurnRequest::new(content)
                        .with_session_id(session_id)
                        .with_conversation_history(history)
                        .with_actor_context(actor.clone()),
                )
                .await?
        } else {
            runner
                .run_request(
                    crate::turn_request::TurnRequest::new(content)
                        .with_session_id(session_id)
                        .with_conversation_history(history),
                )
                .await?
        };
        let assistant_text = assistant_text_from_events(&events);
        self.storage
            .append_scoped_assistant_with_events(
                &self.conversation_scope,
                session_id,
                &assistant_text,
                &events,
            )
            .await?;
        Ok(MobileTurnResult {
            assistant_text,
            events,
        })
    }
}

fn mobile_safe_runtime_config(
    init: &MobileRuntimeInit,
    mut runtime_config: RuntimeConfig,
) -> RuntimeConfig {
    if init.platform == PlatformId::Android {
        runtime_config = runtime_config.without_builtin_tools();
        runtime_config.external_tools.clear();
        runtime_config.connectors.clear();
        runtime_config
    } else {
        runtime_config
    }
}

fn mobile_safe_skill_registry(init: &MobileRuntimeInit, skills: SkillRegistry) -> SkillRegistry {
    if init.platform == PlatformId::Android {
        skills.with_platform_capabilities(init.platform, init.capabilities.clone())
    } else {
        skills
    }
}

fn mobile_safe_snapshot_manager(
    init: &MobileRuntimeInit,
    skill_manager: &SkillManager,
) -> SkillManager {
    let snapshot = skill_manager.current_snapshot();
    let registry = mobile_safe_skill_registry(init, snapshot.registry().clone());
    SkillManager::from_registry_and_catalog_with_context(
        registry,
        snapshot.catalog().clone(),
        init.platform,
        init.capabilities.clone(),
    )
}

fn validate_mobile_manager_context(
    init: &MobileRuntimeInit,
    skill_manager: &SkillManager,
) -> anyhow::Result<()> {
    let context = skill_manager
        .runtime_context()
        .ok_or_else(|| anyhow::anyhow!("mobile skill manager runtime context is required"))?;
    if context.platform() != init.platform || context.capabilities() != &init.capabilities {
        anyhow::bail!("mobile skill manager runtime context does not match mobile init");
    }
    Ok(())
}

fn mobile_runtime_diagnostics(
    init: &MobileRuntimeInit,
    runtime_config: &RuntimeConfig,
    skills: &SkillRegistry,
) -> MobileRuntimeDiagnostics {
    MobileRuntimeDiagnostics {
        platform: init.platform,
        capabilities: init.capabilities.clone(),
        built_in_tools_enabled: runtime_config.built_in_tools_enabled,
        registered_skill_tool_count: skills.tools().len(),
        configured_external_tool_count: runtime_config.external_tools.len(),
        configured_connector_count: runtime_config.connectors.len(),
    }
}

pub(crate) fn assistant_text_from_events(events: &[RuntimeEvent]) -> String {
    events
        .iter()
        .find_map(|event| {
            if let RuntimeEvent::AssistantMessageFinished { text } = event {
                Some(text.clone())
            } else {
                None
            }
        })
        .unwrap_or_else(|| {
            events
                .iter()
                .filter_map(|event| {
                    if let RuntimeEvent::AssistantTextDelta { text } = event {
                        Some(text.as_str())
                    } else {
                        None
                    }
                })
                .collect()
        })
}

#[async_trait::async_trait]
impl<C> ModelClient for Arc<C>
where
    C: ModelClient,
{
    async fn stream(
        &self,
        request: model_gateway::responses::GatewayRequest,
    ) -> anyhow::Result<crate::turn::ModelEventStream> {
        self.as_ref().stream(request).await
    }
}

#[cfg(test)]
#[path = "mobile_host_tests.rs"]
mod tests;
