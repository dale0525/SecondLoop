pub mod builtin;
pub mod command;
mod definition_support;
pub mod discovery;
mod foundation_actions;
mod host_dispatch;
pub mod patch;
pub mod path;
pub mod process;
mod registry_support;
pub mod result;
pub mod schema;
pub mod search;

use crate::app_definition::AgentAppRuntimePolicy;
use crate::app_manifest::{AppNetworkPolicy, ExternalSideEffectPolicy};
use crate::policy::{ApprovalPolicy, SandboxProfile};
use crate::skill::{SkillExecutionContext, SkillRegistry};
use crate::skill_management_tools::{SkillManagementToolContext, SkillManagementTools};
use crate::skill_runtime_source::RuntimeToolBinding;
use builtin::BuiltInTools;
use definition_support::{
    app_policy_allows_discovery, app_policy_allows_tool, external_definitions, external_discovery,
    serialized_len, tool_has_external_side_effect,
};
use discovery::{ConnectorMetadata, ExternalToolConfig, ExternalToolExecution, ToolDiscoveryItem};
use result::{ToolError, ToolResult, ToolResultMetadata};
use schema::{ToolDiagnostic, validate_tool_definition};
use serde::{Deserialize, Serialize};
use serde_json::Value;
use std::collections::{HashSet, VecDeque};
use std::path::PathBuf;
use std::sync::{Arc, Mutex};
use std::time::{Duration, Instant};

const DEFAULT_MAX_TOOL_CALLS_PER_TURN: usize = 16;
const DEFAULT_TOOL_TIMEOUT_MS: u64 = 30_000;
const DEFAULT_OUTPUT_LIMIT_BYTES: usize = 64 * 1024;
const TOOL_OBSERVER_TIMEOUT: Duration = Duration::from_secs(1);

#[derive(Debug, Clone, Copy, Deserialize, Serialize, PartialEq, Eq)]
pub enum CommandMode {
    Disabled,
    Allowed,
}

#[derive(Debug, Clone, Deserialize, Serialize, PartialEq)]
pub struct RuntimeConfig {
    pub workspace_root: PathBuf,
    pub cwd: PathBuf,
    #[serde(default)]
    pub excluded_workspace_roots: Vec<PathBuf>,
    pub mode: RuntimeMode,
    pub command_mode: CommandMode,
    #[serde(default = "default_built_in_tools_enabled")]
    pub built_in_tools_enabled: bool,
    pub max_tool_calls_per_turn: usize,
    pub tool_timeout_ms: u64,
    pub output_limit_bytes: usize,
    pub approval_policy: ApprovalPolicy,
    pub sandbox_profile: SandboxProfile,
    #[serde(default)]
    pub agent_app_policy: Option<AgentAppRuntimePolicy>,
    pub external_tools: Vec<ExternalToolConfig>,
    pub connectors: Vec<ConnectorMetadata>,
}

impl RuntimeConfig {
    pub fn workspace_write(workspace_root: impl Into<PathBuf>, cwd: impl Into<PathBuf>) -> Self {
        Self::new(workspace_root, cwd, RuntimeMode::WorkspaceWrite)
    }

    pub fn read_only(workspace_root: impl Into<PathBuf>, cwd: impl Into<PathBuf>) -> Self {
        Self::new(workspace_root, cwd, RuntimeMode::ReadOnly)
    }

    fn new(workspace_root: impl Into<PathBuf>, cwd: impl Into<PathBuf>, mode: RuntimeMode) -> Self {
        Self {
            workspace_root: workspace_root.into(),
            cwd: cwd.into(),
            excluded_workspace_roots: Vec::new(),
            mode,
            command_mode: CommandMode::Disabled,
            built_in_tools_enabled: true,
            max_tool_calls_per_turn: DEFAULT_MAX_TOOL_CALLS_PER_TURN,
            tool_timeout_ms: DEFAULT_TOOL_TIMEOUT_MS,
            output_limit_bytes: DEFAULT_OUTPUT_LIMIT_BYTES,
            approval_policy: ApprovalPolicy::Never,
            sandbox_profile: SandboxProfile::default(),
            agent_app_policy: None,
            external_tools: Vec::new(),
            connectors: Vec::new(),
        }
    }

    pub fn with_command_mode(mut self, command_mode: CommandMode) -> Self {
        self.command_mode = command_mode;
        self
    }

    pub fn without_builtin_tools(mut self) -> Self {
        self.built_in_tools_enabled = false;
        self
    }

    pub fn with_agent_app_policy(mut self, policy: AgentAppRuntimePolicy) -> Self {
        self.agent_app_policy = Some(policy);
        self
    }

    pub fn excluding_workspace_roots(mut self, roots: impl IntoIterator<Item = PathBuf>) -> Self {
        self.excluded_workspace_roots.extend(roots);
        self.excluded_workspace_roots.sort();
        self.excluded_workspace_roots.dedup();
        self
    }

    pub(crate) fn effective_command_mode(&self) -> CommandMode {
        if self.excluded_workspace_roots.is_empty() {
            self.command_mode
        } else {
            CommandMode::Disabled
        }
    }
}

fn default_built_in_tools_enabled() -> bool {
    true
}

#[derive(Debug, Clone, Copy, Deserialize, Serialize, PartialEq, Eq)]
pub enum RuntimeMode {
    ReadOnly,
    WorkspaceWrite,
}

#[derive(Debug, Clone, Copy, Deserialize, Serialize, PartialEq, Eq)]
#[serde(rename_all = "snake_case")]
pub enum ToolPermission {
    ReadWorkspace,
    WriteWorkspace,
    ExecuteCommand,
    ReadSensitive,
    PersistData,
    ExternalWrite,
    DestructiveWrite,
    CredentialAccess,
    ManageSkills,
}

#[derive(Debug, Clone, Copy, Default, Deserialize, Serialize, PartialEq, Eq)]
#[serde(rename_all = "snake_case")]
pub enum ToolPersistence {
    Full,
    #[default]
    MetadataOnly,
}

impl ToolPersistence {
    pub const fn for_permission(permission: ToolPermission) -> Self {
        match permission {
            ToolPermission::ReadSensitive | ToolPermission::CredentialAccess => Self::MetadataOnly,
            _ => Self::Full,
        }
    }
}

#[derive(Debug, Clone, Deserialize, Serialize, PartialEq)]
pub struct ToolDefinition {
    pub name: String,
    pub namespace: Option<String>,
    pub description: String,
    pub input_schema: Value,
    pub output_schema: Option<Value>,
    pub permission: ToolPermission,
    #[serde(default)]
    pub persistence: ToolPersistence,
    pub source: ToolSource,
}

impl ToolDefinition {
    pub const fn effective_persistence(&self) -> ToolPersistence {
        match self.permission {
            ToolPermission::ReadSensitive | ToolPermission::CredentialAccess => {
                ToolPersistence::MetadataOnly
            }
            _ => self.persistence,
        }
    }
}

#[derive(Debug, Clone, Deserialize, Serialize, PartialEq, Eq)]
pub enum ToolSource {
    BuiltIn,
    HostCapability {
        capability: String,
    },
    RuntimeSkill {
        skill_name: String,
        package_id: String,
        revision_id: Option<String>,
    },
    Mcp {
        server: String,
    },
    AppConnector {
        connector: String,
    },
}

#[async_trait::async_trait]
pub trait ToolExecutionObserver: Send + Sync {
    async fn finished(&self, source: &ToolSource, success: bool) -> anyhow::Result<()>;
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct ToolObserverDiagnostic {
    pub operation: &'static str,
    pub message: String,
}

struct ToolExecutionAttribution {
    source: ToolSource,
    success: bool,
}

struct ToolDispatchOutcome {
    result: ToolResult,
    attribution: Option<ToolExecutionAttribution>,
}

impl ToolDispatchOutcome {
    fn unobserved(result: ToolResult) -> Self {
        Self {
            result,
            attribution: None,
        }
    }
}

#[derive(Debug, Clone, Copy, Deserialize, Serialize, PartialEq, Eq)]
pub struct ApprovalRequirement {
    pub permission: ToolPermission,
    pub policy: ApprovalPolicy,
}

#[derive(Debug, Clone, Deserialize, Serialize, PartialEq)]
pub struct ToolDiscovery {
    pub tools: Vec<ToolDiscoveryItem>,
    pub connectors: Vec<ConnectorMetadata>,
}

pub fn permission_allowed(
    mode: RuntimeMode,
    command_mode: CommandMode,
    permission: ToolPermission,
) -> bool {
    match permission {
        ToolPermission::ReadWorkspace => true,
        ToolPermission::WriteWorkspace => mode == RuntimeMode::WorkspaceWrite,
        ToolPermission::ExecuteCommand => {
            mode == RuntimeMode::WorkspaceWrite && command_mode == CommandMode::Allowed
        }
        ToolPermission::ReadSensitive
        | ToolPermission::PersistData
        | ToolPermission::ExternalWrite
        | ToolPermission::DestructiveWrite
        | ToolPermission::CredentialAccess => true,
        ToolPermission::ManageSkills => false,
    }
}

pub struct ToolRegistry {
    builtins: BuiltInTools,
    built_in_tools_enabled: bool,
    skills: SkillRegistry,
    external_tools: Vec<ExternalToolConfig>,
    external_definitions: Vec<ToolDefinition>,
    external_discovery: Vec<ToolDiscoveryItem>,
    connectors: Vec<ConnectorMetadata>,
    connector_tools: Option<crate::connector_tools::ConnectorToolRuntime>,
    memory: Option<crate::memory_tools::MemoryToolRuntime>,
    task_tools: Option<crate::task_tools::TaskToolRuntime>,
    automation_tools: Option<crate::automation_tools::AutomationToolRuntime>,
    attachment_tools: Option<crate::attachment_tools::AttachmentToolRuntime>,
    mail_actions: Option<crate::foundation_actions::MailActionService>,
    foundation_action_context: Option<crate::foundation_actions::FoundationActionTurnContext>,
    workspace_root: PathBuf,
    cwd: PathBuf,
    mode: RuntimeMode,
    command_mode: CommandMode,
    commands_blocked_by_exclusions: bool,
    tool_timeout: Duration,
    output_limit_bytes: usize,
    approval_policy: ApprovalPolicy,
    agent_app_policy: Option<AgentAppRuntimePolicy>,
    management: Option<SkillManagementToolContext>,
    turn_execution_lease: Option<crate::skill_snapshot::TurnExecutionLease>,
    execution_observer: Option<Arc<dyn ToolExecutionObserver>>,
    observer_diagnostics: Arc<Mutex<VecDeque<ToolObserverDiagnostic>>>,
}

impl std::fmt::Debug for ToolRegistry {
    fn fmt(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        formatter
            .debug_struct("ToolRegistry")
            .field("built_in_tools_enabled", &self.built_in_tools_enabled)
            .field("external_tools", &self.external_tools.len())
            .field("has_memory", &self.memory.is_some())
            .field("has_task_tools", &self.task_tools.is_some())
            .field("has_automation_tools", &self.automation_tools.is_some())
            .field("has_attachment_tools", &self.attachment_tools.is_some())
            .field("has_mail_actions", &self.mail_actions.is_some())
            .field("has_connector_tools", &self.connector_tools.is_some())
            .field("has_management", &self.management.is_some())
            .field("has_execution_observer", &self.execution_observer.is_some())
            .finish_non_exhaustive()
    }
}

impl ToolRegistry {
    pub fn new(skills: SkillRegistry, config: &RuntimeConfig) -> Self {
        Self::try_new(skills, config).expect("runtime tool registry should be valid")
    }

    pub fn try_new(skills: SkillRegistry, config: &RuntimeConfig) -> anyhow::Result<Self> {
        Self::try_new_with_management(skills, config, None)
    }

    pub fn new_with_management(
        skills: SkillRegistry,
        config: &RuntimeConfig,
        management: Option<SkillManagementToolContext>,
    ) -> Self {
        Self::try_new_with_management(skills, config, management)
            .expect("runtime tool registry should be valid")
    }

    pub fn try_new_with_management(
        skills: SkillRegistry,
        config: &RuntimeConfig,
        management: Option<SkillManagementToolContext>,
    ) -> anyhow::Result<Self> {
        let external_definitions = external_definitions(&config.external_tools)?;
        let external_discovery = external_discovery(&config.external_tools)?;
        Self {
            builtins: BuiltInTools::new(config.clone()),
            built_in_tools_enabled: config.built_in_tools_enabled,
            skills,
            external_tools: config.external_tools.clone(),
            external_definitions,
            external_discovery,
            connectors: config.connectors.clone(),
            connector_tools: None,
            memory: None,
            task_tools: None,
            automation_tools: None,
            attachment_tools: None,
            mail_actions: None,
            foundation_action_context: None,
            workspace_root: config.workspace_root.clone(),
            cwd: config.cwd.clone(),
            mode: config.mode,
            command_mode: config.effective_command_mode(),
            commands_blocked_by_exclusions: !config.excluded_workspace_roots.is_empty(),
            tool_timeout: Duration::from_millis(config.tool_timeout_ms),
            output_limit_bytes: config.output_limit_bytes,
            approval_policy: config.approval_policy,
            agent_app_policy: config.agent_app_policy.clone(),
            management,
            turn_execution_lease: None,
            execution_observer: None,
            observer_diagnostics: Arc::new(Mutex::new(VecDeque::with_capacity(32))),
        }
        .validate()
    }

    pub fn with_execution_observer(mut self, observer: Arc<dyn ToolExecutionObserver>) -> Self {
        self.execution_observer = Some(observer);
        self
    }

    pub(crate) fn with_turn_execution_lease(
        mut self,
        lease: Option<crate::skill_snapshot::TurnExecutionLease>,
    ) -> Self {
        self.turn_execution_lease = lease;
        self
    }

    pub fn observer_diagnostics(&self) -> Vec<ToolObserverDiagnostic> {
        self.observer_diagnostics
            .lock()
            .expect("tool observer diagnostic lock poisoned")
            .iter()
            .cloned()
            .collect()
    }

    pub fn take_observer_diagnostics(&self) -> Vec<ToolObserverDiagnostic> {
        self.observer_diagnostics
            .lock()
            .expect("tool observer diagnostic lock poisoned")
            .drain(..)
            .collect()
    }

    pub fn definitions(&self) -> Vec<ToolDefinition> {
        let mut definitions = self.non_management_definitions();
        if let Some(context) = &self.management {
            definitions.extend(SkillManagementTools::definitions(
                &context.service,
                &context.actor,
            ));
        }
        definitions
    }

    pub fn diagnostics(&self) -> Vec<ToolDiagnostic> {
        let mut diagnostics: Vec<_> = self
            .definitions()
            .into_iter()
            .map(|definition| ToolDiagnostic {
                name: definition.name.clone(),
                namespace: definition.namespace.clone(),
                description: definition.description.clone(),
                permission: definition.permission,
                source: definition.source.clone(),
                schema: validate_tool_definition(&definition),
            })
            .collect();

        diagnostics.sort_by(|left, right| {
            left.namespace
                .cmp(&right.namespace)
                .then_with(|| left.name.cmp(&right.name))
        });
        diagnostics
    }

    pub fn approval_requirement(&self, name: &str) -> Option<ApprovalRequirement> {
        let definition = self
            .definitions()
            .into_iter()
            .find(|definition| definition.name == name)?;
        if self.agent_app_policy.as_ref().is_some_and(|policy| {
            policy.external_side_effects() == ExternalSideEffectPolicy::RequireApproval
                && tool_has_external_side_effect(&definition)
        }) {
            return Some(ApprovalRequirement {
                permission: definition.permission,
                policy: ApprovalPolicy::OnWrites,
            });
        }
        self.approval_policy
            .requires_approval(definition.permission)
            .then_some(ApprovalRequirement {
                permission: definition.permission,
                policy: self.approval_policy,
            })
    }

    pub fn persistence_for(&self, name: &str) -> ToolPersistence {
        self.definitions()
            .into_iter()
            .find(|definition| definition.name == name)
            .map(|definition| definition.effective_persistence())
            .unwrap_or(ToolPersistence::MetadataOnly)
    }

    pub fn discovery(&self) -> ToolDiscovery {
        let mut tools: Vec<_> = self
            .definitions()
            .into_iter()
            .map(|definition| ToolDiscoveryItem {
                name: definition.name,
                namespace: definition.namespace,
                summary: definition.description.clone(),
                description: definition.description,
                permission: definition.permission,
                source: definition.source,
                schema_loaded: true,
                deferred: false,
            })
            .collect();
        tools.extend(
            self.external_discovery
                .iter()
                .filter(|item| item.deferred)
                .filter(|item| {
                    self.agent_app_policy
                        .as_ref()
                        .is_none_or(|policy| app_policy_allows_discovery(policy, item))
                })
                .cloned(),
        );
        tools.sort_by(|left, right| {
            left.namespace
                .cmp(&right.namespace)
                .then_with(|| left.name.cmp(&right.name))
        });

        ToolDiscovery {
            tools,
            connectors: self
                .connectors
                .iter()
                .filter(|connector| {
                    self.agent_app_policy.as_ref().is_none_or(|policy| {
                        policy.network() != AppNetworkPolicy::Deny
                            && policy.declares_connector(&connector.id)
                    })
                })
                .cloned()
                .collect(),
        }
    }

    pub async fn execute(&self, name: &str, call_id: &str, arguments: Value) -> ToolResult {
        let started = Instant::now();
        if SkillManagementTools::is_reserved_name(name) {
            if let Some(context) = &self.management
                && SkillManagementTools::handles(context, name)
            {
                return SkillManagementTools::execute(context, name, call_id, arguments).await;
            }
            return registry_failure(
                name,
                call_id,
                "unknown_tool",
                format!("unknown tool: {name}"),
                false,
                registry_metadata(started),
            );
        }
        if let Some(policy) = &self.agent_app_policy
            && let Some(definition) = self
                .unfiltered_non_management_definitions()
                .into_iter()
                .find(|definition| definition.name == name)
            && !app_policy_allows_tool(policy, &definition)
        {
            return registry_failure(
                name,
                call_id,
                "permission_denied",
                "tool is not allowed by the active Agent App policy",
                false,
                registry_metadata(started),
            );
        }
        if self.approval_requirement(name).is_some() {
            return registry_failure(
                name,
                call_id,
                "approval_required",
                "tool call requires approval before execution",
                false,
                registry_metadata(started),
            );
        }
        let timeout_attribution = self.runtime_timeout_attribution(name);
        let execution = tokio::time::timeout(
            self.tool_timeout,
            self.execute_without_timeout(name, call_id, arguments, started),
        );

        let outcome = match execution.await {
            Ok(outcome) => outcome,
            Err(_) => ToolDispatchOutcome {
                result: registry_failure(
                    name,
                    call_id,
                    "timeout",
                    "tool execution timed out",
                    true,
                    registry_metadata(started),
                ),
                attribution: timeout_attribution,
            },
        };
        let result = self.apply_output_limit(outcome.result);
        if let Some(attribution) = outcome.attribution {
            self.observe_execution(&attribution.source, attribution.success)
                .await;
        }
        result
    }

    pub async fn execute_provider_call(
        &self,
        name: &str,
        legacy_alias_selected: bool,
        call_id: &str,
        arguments: Value,
    ) -> ToolResult {
        if legacy_alias_selected {
            self.push_alias_deprecation_diagnostic();
        }
        self.execute(name, call_id, arguments).await
    }

    async fn execute_without_timeout(
        &self,
        name: &str,
        call_id: &str,
        arguments: Value,
        started: Instant,
    ) -> ToolDispatchOutcome {
        if self.built_in_tools_enabled && BuiltInTools::handles(name) {
            return ToolDispatchOutcome::unobserved(
                self.builtins.execute(name, call_id, arguments).await,
            );
        }

        if let Some(memory) = &self.memory
            && memory.handles(name)
        {
            let Some(definition) = memory
                .definitions()
                .into_iter()
                .find(|definition| definition.name == name)
            else {
                return ToolDispatchOutcome::unobserved(registry_failure(
                    name,
                    call_id,
                    "unknown_tool",
                    "Memory host tool definition is unavailable",
                    false,
                    registry_metadata(started),
                ));
            };
            if !permission_allowed(self.mode, self.command_mode, definition.permission) {
                return ToolDispatchOutcome::unobserved(registry_failure(
                    name,
                    call_id,
                    "permission_denied",
                    "Memory host tool is not allowed by runtime policy",
                    false,
                    registry_metadata(started),
                ));
            }
            let result = match memory.execute(name, arguments).await {
                Ok(value) => ToolResult::success(name, call_id, value, registry_metadata(started)),
                Err(error) => registry_failure(
                    name,
                    call_id,
                    "memory_error",
                    error.to_string(),
                    false,
                    registry_metadata(started),
                ),
            };
            return ToolDispatchOutcome::unobserved(result);
        }

        if let Some(outcome) = self
            .dispatch_task_tools(name, call_id, &arguments, started)
            .await
        {
            return outcome;
        }
        if let Some(outcome) = self
            .dispatch_automation_tools(name, call_id, &arguments, started)
            .await
        {
            return outcome;
        }
        if let Some(outcome) = self
            .dispatch_attachment_tools(name, call_id, &arguments, started)
            .await
        {
            return outcome;
        }
        if let Some(outcome) = self
            .dispatch_foundation_mail_action(name, call_id, &arguments, started)
            .await
        {
            return outcome;
        }

        if let Some(connectors) = &self.connector_tools
            && connectors.handles(name)
        {
            let result = match connectors.execute(name, call_id, arguments).await {
                Ok(value) => ToolResult::success(name, call_id, value, registry_metadata(started)),
                Err(error) => registry_failure(
                    name,
                    call_id,
                    crate::connector_tools::connector_authorization_error_code(&error),
                    error.to_string(),
                    error.to_string().contains("timed out"),
                    registry_metadata(started),
                ),
            };
            return ToolDispatchOutcome::unobserved(result);
        }

        if let Some(tool) = self.external_tool(name) {
            if self.commands_blocked_by_exclusions
                && tool
                    .tool_definition()
                    .ok()
                    .flatten()
                    .is_some_and(|definition| {
                        definition.permission == ToolPermission::ExecuteCommand
                    })
            {
                return ToolDispatchOutcome::unobserved(registry_failure(
                    name,
                    call_id,
                    "permission_denied",
                    "command execution is unavailable when control-plane roots are excluded",
                    false,
                    registry_metadata(started),
                ));
            }
            return ToolDispatchOutcome::unobserved(
                self.execute_external_tool(tool, name, call_id, started),
            );
        }

        let Some(binding) = self.resolve_runtime_binding(name) else {
            return ToolDispatchOutcome::unobserved(registry_failure(
                name,
                call_id,
                "unknown_tool",
                format!("unknown tool: {name}"),
                false,
                ToolResultMetadata::default(),
            ));
        };
        if binding.canonical_id != name {
            self.push_alias_deprecation_diagnostic();
        }

        if !permission_allowed(self.mode, self.command_mode, binding.tool.permission) {
            return ToolDispatchOutcome::unobserved(registry_failure(
                name,
                call_id,
                "permission_denied",
                "tool is not allowed in the current runtime mode",
                false,
                registry_metadata(started),
            ));
        }

        let source = binding.source.clone();
        let result = match self
            .skills
            .execute_runtime_tool_for_turn(
                &binding,
                arguments,
                SkillExecutionContext {
                    workspace_root: self.workspace_root.clone(),
                    cwd: self.cwd.clone(),
                    output_limit_bytes: self.output_limit_bytes,
                },
                self.turn_execution_lease.as_ref(),
            )
            .await
        {
            Ok(value) => ToolResult::success(name, call_id, value, registry_metadata(started)),
            Err(error) => {
                let message = error.to_string();
                let code = skill_error_code(&message);
                let mut metadata = registry_metadata(started);
                if code == "output_limit_exceeded" {
                    metadata.output_truncated = true;
                }
                registry_failure(name, call_id, code, message, false, metadata)
            }
        };
        let attributable = result.ok
            || result.error.as_ref().is_some_and(|error| {
                error.message.contains("skill command failed")
                    || error
                        .message
                        .contains("tool output exceeded runtime output limit")
            });
        ToolDispatchOutcome {
            attribution: attributable.then_some(ToolExecutionAttribution {
                source,
                success: result.ok,
            }),
            result,
        }
    }

    async fn observe_execution(&self, source: &ToolSource, success: bool) {
        let Some(observer) = &self.execution_observer else {
            return;
        };
        if matches!(
            tokio::time::timeout(TOOL_OBSERVER_TIMEOUT, observer.finished(source, success)).await,
            Ok(Ok(()))
        ) {
            return;
        }
        self.push_diagnostic(ToolObserverDiagnostic {
            operation: "tool_execution_observer",
            message: "tool execution observer failed".into(),
        });
    }

    fn push_diagnostic(&self, diagnostic: ToolObserverDiagnostic) {
        let mut diagnostics = self
            .observer_diagnostics
            .lock()
            .expect("tool observer diagnostic lock poisoned");
        if diagnostics.len() == 32 {
            diagnostics.pop_front();
        }
        diagnostics.push_back(diagnostic);
    }

    fn push_alias_deprecation_diagnostic(&self) {
        self.push_diagnostic(ToolObserverDiagnostic {
            operation: "runtime_tool_alias_deprecation",
            message: "unqualified runtime tool aliases are deprecated".into(),
        });
    }

    fn external_tool(&self, name: &str) -> Option<&ExternalToolConfig> {
        self.external_tools
            .iter()
            .find(|tool| matches!(tool.flattened_name(), Ok(flattened) if flattened == name))
    }

    fn execute_external_tool(
        &self,
        tool: &ExternalToolConfig,
        name: &str,
        call_id: &str,
        started: Instant,
    ) -> ToolResult {
        if matches!(
            tool.visibility,
            discovery::ExternalToolVisibility::Deferred { .. }
        ) {
            return registry_failure(
                name,
                call_id,
                "tool_disabled",
                "Deferred external tool schema is not loaded.",
                false,
                registry_metadata(started),
            );
        }

        match &tool.execution {
            ExternalToolExecution::Static { result } => {
                ToolResult::success(name, call_id, result.clone(), registry_metadata(started))
            }
            ExternalToolExecution::Unavailable => registry_failure(
                name,
                call_id,
                "tool_disabled",
                "External tool execution is not implemented in this phase.",
                false,
                registry_metadata(started),
            ),
        }
    }

    fn apply_output_limit(&self, result: ToolResult) -> ToolResult {
        if !result.ok {
            return result;
        }

        let data_exceeds_limit = result
            .data
            .as_ref()
            .map(|data| serialized_len(data) > self.output_limit_bytes)
            .unwrap_or(false);
        let result_exceeds_limit = serialized_len(&result) > self.output_limit_bytes;
        if data_exceeds_limit || result_exceeds_limit {
            let mut metadata = result.metadata;
            metadata.output_truncated = true;
            return registry_failure(
                &result.tool,
                &result.call_id,
                "output_limit_exceeded",
                "tool output exceeded runtime output limit",
                false,
                metadata,
            );
        }

        result
    }

    fn validate(self) -> anyhow::Result<Self> {
        for definition in self.non_management_definitions() {
            if SkillManagementTools::is_reserved_name(&definition.name) {
                anyhow::bail!(
                    "duplicate tool name: {} (reserved skill management tool name)",
                    definition.name
                );
            }
        }
        let mut names = HashSet::new();
        for definition in self.definitions() {
            if !names.insert(definition.name.clone()) {
                anyhow::bail!("duplicate tool name: {}", definition.name);
            }
        }

        Ok(self)
    }
}

fn registry_metadata(started: Instant) -> ToolResultMetadata {
    ToolResultMetadata {
        duration_ms: started.elapsed().as_millis() as u64,
        ..ToolResultMetadata::default()
    }
}

fn registry_failure(
    tool: &str,
    call_id: &str,
    code: &str,
    message: impl Into<String>,
    retryable: bool,
    metadata: ToolResultMetadata,
) -> ToolResult {
    ToolResult::failure(
        tool,
        call_id,
        ToolError {
            code: code.to_string(),
            message: message.into(),
            retryable,
        },
        metadata,
    )
}

fn skill_error_code(message: &str) -> &'static str {
    if message.contains("unknown tool") {
        "unknown_tool"
    } else if message.contains("Permission denied") {
        "permission_denied"
    } else if message.contains("output limit") {
        "output_limit_exceeded"
    } else {
        "internal_error"
    }
}

#[cfg(test)]
mod registry_tests;

#[cfg(test)]
mod app_policy_command_tests;

#[cfg(test)]
mod execution_observer_tests;

#[cfg(test)]
mod management_registry_tests;

#[cfg(test)]
mod management_permission_tests {
    use super::*;

    #[test]
    fn skill_management_permission_is_never_enabled_by_runtime_modes() {
        for mode in [RuntimeMode::ReadOnly, RuntimeMode::WorkspaceWrite] {
            for command_mode in [CommandMode::Disabled, CommandMode::Allowed] {
                assert!(!permission_allowed(
                    mode,
                    command_mode,
                    ToolPermission::ManageSkills
                ));
            }
        }
    }

    #[test]
    fn skill_management_permission_has_stable_metadata_name() {
        assert_eq!(
            serde_json::to_value(ToolPermission::ManageSkills).unwrap(),
            serde_json::json!("manage_skills")
        );
    }
}

#[cfg(test)]
#[path = "persistence_policy_tests.rs"]
mod persistence_policy_tests;
