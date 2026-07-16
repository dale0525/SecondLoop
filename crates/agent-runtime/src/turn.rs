use crate::context::{compact_model_input_with_stats, exceeds_budget};
use crate::events::RuntimeEvent;
use crate::instructions::{InstructionConfig, InstructionContext};
use crate::prompt_composer::AppPromptConfig;
use crate::skill::SkillRegistry;
use crate::skill_catalog::SkillCatalog;
use crate::skill_management::OwnerSkillManagementService;
use crate::skill_management_tools::SkillManagementToolContext;
use crate::skill_manager::SkillManager;
use crate::skill_snapshot::SkillSnapshotLease;
use crate::tools::result::{ToolError, ToolResult, ToolResultMetadata};
use crate::tools::{RuntimeConfig, ToolDefinition, ToolRegistry};
use crate::turn_request::{BudgetPolicy, TurnRequest};
use async_trait::async_trait;
use futures::{Stream, StreamExt};
use model_gateway::responses::{GatewayEvent, GatewayRequest, GatewayTool};
use std::pin::Pin;
use std::sync::Arc;
use uuid::Uuid;

pub type ModelEventStream = Pin<Box<dyn Stream<Item = anyhow::Result<GatewayEvent>> + Send>>;
pub type RuntimeEventObserver = Arc<dyn Fn(RuntimeEvent) + Send + Sync>;

#[async_trait]
pub trait ModelClient: Send + Sync {
    async fn stream(&self, request: GatewayRequest) -> anyhow::Result<ModelEventStream>;
}

#[async_trait]
pub trait AgentRunner: Send + Sync {
    async fn run(&self, user_text: &str) -> anyhow::Result<Vec<RuntimeEvent>>;

    async fn run_request(&self, request: TurnRequest) -> anyhow::Result<Vec<RuntimeEvent>> {
        if request.actor_context != crate::skill_policy::ActorContext::anonymous() {
            anyhow::bail!("agent runner does not accept a host-authenticated actor");
        }
        self.run(&request.user_text).await
    }

    async fn run_request_observed(
        &self,
        request: TurnRequest,
        observer: RuntimeEventObserver,
    ) -> anyhow::Result<Vec<RuntimeEvent>> {
        let events = self.run_request(request).await?;
        for event in &events {
            observer(event.clone());
        }
        Ok(events)
    }
}

pub struct TurnRunner<C> {
    model: C,
    skill_manager: SkillManager,
    config: RuntimeConfig,
    max_steps: usize,
    management: Option<OwnerSkillManagementService>,
    execution_observer: Option<Arc<dyn crate::tools::ToolExecutionObserver>>,
    app_prompt: AppPromptConfig,
    memory: Option<crate::memory_tools::MemoryToolRuntime>,
    memory_candidate_extractor: Option<Arc<dyn crate::memory_lifecycle::MemoryCandidateExtractor>>,
    task_tools: Option<crate::task_tools::TaskToolRuntime>,
    automation_tools: Option<crate::automation_tools::AutomationToolRuntime>,
    structured_content_tools: Option<crate::structured_content_tools::StructuredContentToolRuntime>,
    attachment_tools: Option<crate::attachment_tools::AttachmentToolRuntime>,
    connector_tools: Option<crate::connector_tools::ConnectorToolRuntime>,
    mail_actions: Option<crate::foundation_actions::MailActionService>,
}

impl<C> TurnRunner<C>
where
    C: ModelClient,
{
    #[allow(deprecated)]
    #[deprecated(note = "production turns must use new_with_manager_and_config")]
    pub fn new(model: C, skills: SkillRegistry) -> Self {
        let workspace = std::env::current_dir().unwrap_or_else(|_| ".".into());
        let config = RuntimeConfig::workspace_write(workspace.clone(), workspace);
        Self::new_with_config(model, skills, config)
    }

    #[allow(deprecated)]
    #[deprecated(note = "production turns must use new_with_manager_and_config")]
    pub fn new_with_config(model: C, skills: SkillRegistry, config: RuntimeConfig) -> Self {
        Self::new_with_catalog_and_config(model, skills, SkillCatalog::empty(), config)
    }

    #[deprecated(note = "production turns must use new_with_manager_and_config")]
    pub fn new_with_catalog_and_config(
        model: C,
        skills: SkillRegistry,
        skill_catalog: SkillCatalog,
        config: RuntimeConfig,
    ) -> Self {
        let skill_manager = SkillManager::from_registry_and_catalog(skills, skill_catalog);
        Self::new_with_manager_and_config(model, skill_manager, config)
    }

    pub fn new_with_manager_and_config(
        model: C,
        skill_manager: SkillManager,
        config: RuntimeConfig,
    ) -> Self {
        let max_steps = config.max_tool_calls_per_turn.saturating_add(1);
        Self {
            model,
            skill_manager,
            config,
            max_steps,
            management: None,
            execution_observer: None,
            app_prompt: AppPromptConfig::default(),
            memory: None,
            memory_candidate_extractor: None,
            task_tools: None,
            automation_tools: None,
            structured_content_tools: None,
            attachment_tools: None,
            connector_tools: None,
            mail_actions: None,
        }
    }

    pub fn with_skill_management(mut self, service: OwnerSkillManagementService) -> Self {
        self.management = Some(service);
        self
    }

    pub fn with_app_prompt(mut self, app_prompt: AppPromptConfig) -> Self {
        self.app_prompt = app_prompt;
        self
    }

    pub fn with_memory_tools(mut self, memory: crate::memory_tools::MemoryToolRuntime) -> Self {
        self.memory = Some(memory);
        self
    }

    pub fn with_memory_candidate_extractor(
        mut self,
        extractor: Arc<dyn crate::memory_lifecycle::MemoryCandidateExtractor>,
    ) -> Self {
        self.memory_candidate_extractor = Some(extractor);
        self
    }

    pub fn with_connector_tools(
        mut self,
        connector_tools: crate::connector_tools::ConnectorToolRuntime,
    ) -> Self {
        self.connector_tools = Some(connector_tools);
        self
    }

    pub fn with_mail_actions(
        mut self,
        mail_actions: crate::foundation_actions::MailActionService,
    ) -> Self {
        self.mail_actions = Some(mail_actions);
        self
    }

    pub fn with_task_tools(mut self, task_tools: crate::task_tools::TaskToolRuntime) -> Self {
        self.task_tools = Some(task_tools);
        self
    }

    pub fn with_automation_tools(
        mut self,
        automation_tools: crate::automation_tools::AutomationToolRuntime,
    ) -> Self {
        self.automation_tools = Some(automation_tools);
        self
    }

    pub fn with_structured_content_tools(
        mut self,
        structured_content: crate::structured_content_tools::StructuredContentToolRuntime,
    ) -> Self {
        self.structured_content_tools = Some(structured_content);
        self
    }

    pub fn with_attachment_tools(
        mut self,
        attachment_tools: crate::attachment_tools::AttachmentToolRuntime,
    ) -> Self {
        self.attachment_tools = Some(attachment_tools);
        self
    }

    #[cfg(test)]
    pub(crate) fn with_execution_observer_for_test(
        mut self,
        observer: Arc<dyn crate::tools::ToolExecutionObserver>,
    ) -> Self {
        self.execution_observer = Some(observer);
        self
    }

    pub async fn run(&self, user_text: &str) -> anyhow::Result<Vec<RuntimeEvent>> {
        self.run_request(TurnRequest::new(user_text)).await
    }

    pub async fn run_request(&self, request: TurnRequest) -> anyhow::Result<Vec<RuntimeEvent>> {
        let lease = self.skill_manager.lease_snapshot_for_turn().await?;
        self.run_with_snapshot(request, lease, None).await
    }

    pub async fn run_request_observed(
        &self,
        request: TurnRequest,
        observer: RuntimeEventObserver,
    ) -> anyhow::Result<Vec<RuntimeEvent>> {
        let lease = self.skill_manager.lease_snapshot_for_turn().await?;
        self.run_with_snapshot(request, lease, Some(&observer))
            .await
    }

    async fn run_with_snapshot(
        &self,
        request: TurnRequest,
        lease: SkillSnapshotLease,
        observer: Option<&RuntimeEventObserver>,
    ) -> anyhow::Result<Vec<RuntimeEvent>> {
        let snapshot = lease.snapshot();
        let turn_id = request
            .turn_id
            .clone()
            .unwrap_or_else(|| Uuid::new_v4().to_string());
        let management = self
            .management
            .as_ref()
            .map(|service| SkillManagementToolContext {
                service: service.clone(),
                actor: request.actor_context.clone(),
            });
        let tool_observer = self
            .execution_observer
            .clone()
            .unwrap_or_else(|| Arc::new(self.skill_manager.clone()));
        let execution_lease = lease.execution_lease();
        let lease_cancellation = execution_lease
            .as_ref()
            .map(|lease| lease.cancellation_token());
        let mut tools = ToolRegistry::try_new_with_management(
            snapshot.registry().clone(),
            &self.config,
            management,
        )?;
        if let Some(memory) = &self.memory {
            tools = tools.try_with_memory_tools(memory.clone())?;
        }
        if let Some(tasks) = &self.task_tools {
            tools = tools.try_with_task_tools(tasks.clone())?;
        }
        if let Some(automation) = &self.automation_tools {
            tools = tools.try_with_automation_tools(automation.clone())?;
        }
        if let (Some(structured), Some(session_id)) = (
            &self.structured_content_tools,
            request.session_id.as_deref(),
        ) {
            let context = crate::structured_content_tools::StructuredContentTurnContext::new(
                session_id, &turn_id,
            )?;
            tools = tools
                .try_with_structured_content_tools(structured.clone().with_turn_context(context))?;
        }
        if let Some(attachments) = &self.attachment_tools {
            tools = tools.try_with_attachment_tools(attachments.clone())?;
        }
        if let Some(connectors) = &self.connector_tools {
            tools = tools.try_with_connector_tools(connectors.clone())?;
        }
        if let Some(actions) = &self.mail_actions {
            let context = request
                .session_id
                .clone()
                .map(|session_id| {
                    crate::foundation_actions::FoundationActionTurnContext::new(
                        session_id,
                        turn_id.clone(),
                    )
                })
                .transpose()?;
            tools = tools.try_with_mail_actions(actions.clone(), context)?;
        }
        let tools = tools
            .with_turn_execution_lease(execution_lease.clone())
            .with_execution_observer(tool_observer);
        let skill_catalog = snapshot.catalog();
        let mut events = Vec::new();
        emit(
            &mut events,
            observer,
            RuntimeEvent::TurnStarted {
                turn_id: turn_id.clone(),
            },
        );
        let mut budget = BudgetPolicy::new(request.token_budget);
        let mut instruction_config =
            InstructionConfig::new(self.config.workspace_root.clone(), self.config.cwd.clone());
        instruction_config.app_prompt = self.app_prompt.clone();
        instruction_config.goal_instructions =
            request.goal.as_ref().map(|goal| goal.objective.clone());
        if let Some(memory) = &self.memory {
            match memory.recall_for_turn(&request.user_text, 8).await {
                Ok(records) => {
                    if !records.is_empty() {
                        instruction_config.memory_context = Some(
                            crate::memory_tools::MemoryToolRuntime::render_recall_context(
                                &records,
                            )?,
                        );
                        emit(
                            &mut events,
                            observer,
                            RuntimeEvent::MemoryRecalled {
                                memory_ids: records
                                    .iter()
                                    .map(|record| record.id.as_str().to_string())
                                    .collect(),
                            },
                        );
                    }
                }
                Err(error) => emit(
                    &mut events,
                    observer,
                    RuntimeEvent::MemoryRecallFailed {
                        message: error.to_string(),
                    },
                ),
            }
        }
        instruction_config.skill_summaries = skill_catalog.summaries().to_vec();
        let triggered_skills = skill_catalog.triggered_skills(&request.user_text);
        for selection in &triggered_skills {
            emit(
                &mut events,
                observer,
                RuntimeEvent::SkillSelected {
                    skill_name: selection.name.clone(),
                    reason: selection.reason,
                },
            );
        }
        let triggered_skill_names = triggered_skills
            .iter()
            .map(|selection| selection.name.clone())
            .collect::<Vec<_>>();
        if !triggered_skill_names.is_empty() {
            match skill_catalog
                .load_instruction_documents(&triggered_skill_names, self.config.output_limit_bytes)
                .await
            {
                Ok(documents) => {
                    instruction_config.skill_instructions = documents;
                }
                Err(error) => {
                    emit(
                        &mut events,
                        observer,
                        RuntimeEvent::TurnFailed {
                            turn_id,
                            message: error.to_string(),
                        },
                    );
                    return Ok(events);
                }
            }
        }
        let instruction_context = InstructionContext::load(instruction_config)?;
        let mut input = instruction_context
            .try_model_input(&request.user_text, &request.conversation_history)?
            .input;
        if let Some(context_budget_bytes) = request.context_budget_bytes
            && exceeds_budget(&input, context_budget_bytes)?
        {
            let compacted = compact_model_input_with_stats(input, context_budget_bytes)?;
            emit(
                &mut events,
                observer,
                RuntimeEvent::ContextCompacted {
                    original_items: compacted.original_items,
                    compacted_items: compacted.compacted_items,
                    budget_bytes: context_budget_bytes,
                },
            );
            input = compacted.input;
            if let (Some(memory), Some(session_id)) = (&self.memory, request.session_id.as_deref())
            {
                match memory.on_compaction(session_id, Vec::new()).await {
                    Ok(records) => emit(
                        &mut events,
                        observer,
                        RuntimeEvent::MemoryCompactionSynced {
                            memory_ids: records
                                .iter()
                                .map(|record| record.id.as_str().to_string())
                                .collect(),
                        },
                    ),
                    Err(error) => emit(
                        &mut events,
                        observer,
                        RuntimeEvent::MemoryCandidateExtractionFailed {
                            message: error.to_string(),
                        },
                    ),
                }
            }
        }
        let gateway_tools = gateway_tools(tools.definitions());
        let mut final_text = String::new();
        let mut tool_calls = 0usize;
        let mut memory_tool_results = Vec::new();

        for _step in 0..self.max_steps {
            if turn_lease_is_invalid(execution_lease.as_ref()).await {
                push_turn_lease_fenced(&mut events, observer, &turn_id);
                return Ok(events);
            }
            let stream_request = GatewayRequest {
                input: input.clone(),
                tools: gateway_tools.clone(),
            };
            let stream = self.model.stream(stream_request);
            tokio::pin!(stream);
            let mut stream = match &lease_cancellation {
                Some(cancellation) => tokio::select! {
                    biased;
                    _ = cancellation.cancelled() => {
                        push_turn_lease_fenced(&mut events, observer, &turn_id);
                        return Ok(events);
                    }
                    stream = &mut stream => stream?,
                },
                None => stream.await?,
            };
            let mut saw_tool = false;

            loop {
                let event = match &lease_cancellation {
                    Some(cancellation) => tokio::select! {
                        biased;
                        _ = cancellation.cancelled() => {
                            push_turn_lease_fenced(&mut events, observer, &turn_id);
                            return Ok(events);
                        }
                        event = stream.next() => event,
                    },
                    None => stream.next().await,
                };
                let Some(event) = event else {
                    break;
                };
                match event? {
                    GatewayEvent::TextDelta { text } => {
                        final_text.push_str(&text);
                        emit(
                            &mut events,
                            observer,
                            RuntimeEvent::AssistantTextDelta { text },
                        );
                    }
                    GatewayEvent::ReasoningDelta { text } => {
                        emit(&mut events, observer, RuntimeEvent::ReasoningDelta { text });
                    }
                    GatewayEvent::ToolCall {
                        call_id,
                        name,
                        legacy_alias_selected,
                        arguments,
                    } => {
                        if turn_lease_is_invalid(execution_lease.as_ref()).await {
                            push_turn_lease_fenced(&mut events, observer, &turn_id);
                            return Ok(events);
                        }
                        saw_tool = true;
                        tool_calls += 1;
                        if tool_calls > self.config.max_tool_calls_per_turn {
                            emit(
                                &mut events,
                                observer,
                                RuntimeEvent::TurnFailed {
                                    turn_id: turn_id.clone(),
                                    message: "max tool calls exceeded".into(),
                                },
                            );
                            return Ok(events);
                        }
                        let persistence = tools.persistence_for(&name);
                        if let Some(requirement) = tools.approval_requirement(&name) {
                            emit(
                                &mut events,
                                observer,
                                RuntimeEvent::ApprovalRequired {
                                    call_id: call_id.clone(),
                                    name: name.clone(),
                                    permission: requirement.permission,
                                    policy: requirement.policy,
                                },
                            );
                            let result = ToolResult::failure(
                                name.clone(),
                                call_id.clone(),
                                ToolError {
                                    code: "approval_required".into(),
                                    message: "Tool call requires approval before execution.".into(),
                                    retryable: false,
                                },
                                ToolResultMetadata::default(),
                            )
                            .into_value();
                            emit(
                                &mut events,
                                observer,
                                RuntimeEvent::ToolCallFinished {
                                    call_id: call_id.clone(),
                                    result: result.clone(),
                                    persistence,
                                },
                            );
                            input.push(serde_json::json!({
                                "role": "assistant",
                                "tool_calls": [
                                    {
                                        "id": call_id.clone(),
                                        "type": "function",
                                        "function": {
                                            "name": name.clone(),
                                            "arguments": "{}"
                                        }
                                    }
                                ]
                            }));
                            input.push(serde_json::json!({
                                "role": "tool",
                                "tool_call_id": call_id,
                                "content": result
                            }));
                            continue;
                        }
                        emit(
                            &mut events,
                            observer,
                            RuntimeEvent::ToolCallStarted {
                                call_id: call_id.clone(),
                                name: name.clone(),
                                arguments: arguments.clone(),
                                persistence,
                            },
                        );
                        input.push(serde_json::json!({
                            "role": "assistant",
                            "tool_calls": [
                                {
                                    "id": call_id.clone(),
                                    "type": "function",
                                    "function": {
                                        "name": name.clone(),
                                        "arguments": arguments.to_string()
                                    }
                                }
                            ]
                        }));
                        let execution = tools.execute_provider_call(
                            &name,
                            legacy_alias_selected,
                            &call_id,
                            arguments,
                        );
                        tokio::pin!(execution);
                        let result = match &lease_cancellation {
                            Some(cancellation) => tokio::select! {
                                biased;
                                _ = cancellation.cancelled() => {
                                    push_turn_lease_fenced(&mut events, observer, &turn_id);
                                    return Ok(events);
                                }
                                result = &mut execution => result,
                            },
                            None => execution.await,
                        };
                        if execution_lease
                            .as_ref()
                            .is_some_and(|lease| lease.is_fenced())
                        {
                            push_turn_lease_fenced(&mut events, observer, &turn_id);
                            return Ok(events);
                        }
                        let result = result.into_value();
                        memory_tool_results.push(result.clone());
                        for diagnostic in tools.take_observer_diagnostics() {
                            emit(
                                &mut events,
                                observer,
                                RuntimeEvent::ToolObserverDiagnostic {
                                    operation: diagnostic.operation.into(),
                                    message: diagnostic.message,
                                },
                            );
                        }
                        emit(
                            &mut events,
                            observer,
                            RuntimeEvent::ToolCallFinished {
                                call_id: call_id.clone(),
                                result: result.clone(),
                                persistence,
                            },
                        );
                        input.push(serde_json::json!({
                            "role": "tool",
                            "tool_call_id": call_id,
                            "content": result
                        }));
                    }
                    GatewayEvent::Completed => {}
                    GatewayEvent::Error { message } => {
                        emit(
                            &mut events,
                            observer,
                            RuntimeEvent::TurnFailed {
                                turn_id: turn_id.clone(),
                                message,
                            },
                        );
                        return Ok(events);
                    }
                    GatewayEvent::Usage {
                        input_tokens,
                        output_tokens,
                    } => {
                        let usage = budget.record_usage(input_tokens, output_tokens);
                        emit(
                            &mut events,
                            observer,
                            RuntimeEvent::UsageReported {
                                input_tokens: usage.input_tokens,
                                output_tokens: usage.output_tokens,
                                total_tokens: usage.total_tokens,
                                exceeded: usage.exceeded,
                            },
                        );
                        if usage.exceeded {
                            emit(
                                &mut events,
                                observer,
                                RuntimeEvent::TurnFailed {
                                    turn_id: turn_id.clone(),
                                    message: "token budget exceeded".into(),
                                },
                            );
                            return Ok(events);
                        }
                    }
                    GatewayEvent::ResponseStarted { .. } => {}
                }
            }

            if execution_lease
                .as_ref()
                .is_some_and(|lease| lease.is_fenced())
                || turn_lease_is_invalid(execution_lease.as_ref()).await
            {
                push_turn_lease_fenced(&mut events, observer, &turn_id);
                return Ok(events);
            }
            if !saw_tool {
                emit(
                    &mut events,
                    observer,
                    RuntimeEvent::AssistantMessageFinished {
                        text: final_text.clone(),
                    },
                );
                self.extract_memory_candidates(
                    &request,
                    &final_text,
                    memory_tool_results,
                    &mut events,
                    observer,
                )
                .await;
                emit(
                    &mut events,
                    observer,
                    RuntimeEvent::TurnFinished { turn_id },
                );
                return Ok(events);
            }
        }

        emit(
            &mut events,
            observer,
            RuntimeEvent::TurnFailed {
                turn_id,
                message: "max agent steps exceeded".into(),
            },
        );
        Ok(events)
    }

    async fn extract_memory_candidates(
        &self,
        request: &TurnRequest,
        assistant_text: &str,
        tool_results: Vec<serde_json::Value>,
        events: &mut Vec<RuntimeEvent>,
        observer: Option<&RuntimeEventObserver>,
    ) {
        let (Some(memory), Some(extractor), Some(session_id)) = (
            &self.memory,
            &self.memory_candidate_extractor,
            request.session_id.as_deref(),
        ) else {
            return;
        };
        let transcript = crate::memory_lifecycle::MemoryTurnTranscript {
            session_id: session_id.to_string(),
            user_text: request.user_text.clone(),
            assistant_text: assistant_text.to_string(),
            tool_results,
        };
        let result = async {
            let candidates = extractor.extract_candidates(&transcript).await?;
            memory.post_turn_candidates(session_id, candidates).await
        }
        .await;
        match result {
            Ok(records) if !records.is_empty() => {
                emit(
                    events,
                    observer,
                    RuntimeEvent::MemoryCandidatesProposed {
                        memory_ids: records
                            .iter()
                            .map(|record| record.id.as_str().to_string())
                            .collect(),
                    },
                );
            }
            Ok(_) => {}
            Err(error) => emit(
                events,
                observer,
                RuntimeEvent::MemoryCandidateExtractionFailed {
                    message: error.to_string(),
                },
            ),
        }
    }
}

fn push_turn_lease_fenced(
    events: &mut Vec<RuntimeEvent>,
    observer: Option<&RuntimeEventObserver>,
    turn_id: &str,
) {
    emit(
        events,
        observer,
        RuntimeEvent::TurnFailed {
            turn_id: turn_id.to_string(),
            message: crate::skill_snapshot::TURN_LEASE_FENCED_MESSAGE.into(),
        },
    );
}

fn emit(
    events: &mut Vec<RuntimeEvent>,
    observer: Option<&RuntimeEventObserver>,
    event: RuntimeEvent,
) {
    if let Some(observer) = observer {
        observer(event.clone());
    }
    events.push(event);
}

async fn turn_lease_is_invalid(lease: Option<&crate::skill_snapshot::TurnExecutionLease>) -> bool {
    match lease {
        Some(lease) => match lease.ensure_authoritative().await {
            Ok(()) => false,
            Err(error) => {
                tracing::warn!(?error, "turn snapshot lease authority check failed");
                true
            }
        },
        None => false,
    }
}

#[async_trait]
impl<C> AgentRunner for TurnRunner<C>
where
    C: ModelClient,
{
    async fn run(&self, user_text: &str) -> anyhow::Result<Vec<RuntimeEvent>> {
        TurnRunner::run(self, user_text).await
    }

    async fn run_request(&self, request: TurnRequest) -> anyhow::Result<Vec<RuntimeEvent>> {
        TurnRunner::run_request(self, request).await
    }

    async fn run_request_observed(
        &self,
        request: TurnRequest,
        observer: RuntimeEventObserver,
    ) -> anyhow::Result<Vec<RuntimeEvent>> {
        TurnRunner::run_request_observed(self, request, observer).await
    }
}

#[async_trait]
impl ModelClient for model_gateway::responses::GatewayHttpClient {
    async fn stream(&self, request: GatewayRequest) -> anyhow::Result<ModelEventStream> {
        model_gateway::responses::GatewayHttpClient::stream(self, request).await
    }
}

fn gateway_tools(tools: Vec<ToolDefinition>) -> Vec<GatewayTool> {
    tools
        .into_iter()
        .map(|tool| {
            let canonical_id = match &tool.source {
                crate::tools::ToolSource::RuntimeSkill { package_id, .. } => {
                    let local_name = tool.name.rsplit('/').next().unwrap_or(&tool.name);
                    format!("{package_id}/{local_name}")
                }
                _ => tool.name.clone(),
            };
            if tool.name == canonical_id {
                GatewayTool::new(canonical_id, tool.description, tool.input_schema)
            } else {
                GatewayTool::advertised_alias(
                    canonical_id,
                    tool.name,
                    tool.description,
                    tool.input_schema,
                )
            }
        })
        .collect()
}

#[cfg(test)]
#[path = "turn_tests.rs"]
mod turn_tests;
