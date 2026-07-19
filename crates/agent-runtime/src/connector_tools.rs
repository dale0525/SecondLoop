use crate::connector::{
    ConnectorApprovalMode, ConnectorCallContext, ConnectorDescriptor, ConnectorRuntime,
    ConnectorToolRisk, ConnectorToolSpec, connector_action_hash,
};
use crate::credential::CredentialScope;
use crate::tools::{ToolDefinition, ToolPermission, ToolPersistence, ToolSource};
use async_trait::async_trait;
use serde_json::Value;
use std::collections::BTreeMap;
use std::sync::{Arc, Mutex};
use std::time::Duration;
use tokio_util::sync::CancellationToken;

#[derive(Clone, Debug)]
pub struct ConnectorToolAuthorizationRequest {
    pub connector: ConnectorDescriptor,
    pub tool: ConnectorToolSpec,
    pub call_id: String,
    pub action_hash: String,
    pub trusted_host_action: bool,
}

#[async_trait]
pub trait ConnectorCallContextProvider: Send + Sync {
    async fn context_for(
        &self,
        request: ConnectorToolAuthorizationRequest,
    ) -> anyhow::Result<ConnectorCallContext>;
}

#[derive(Debug, thiserror::Error)]
pub enum ConnectorToolAuthorizationError {
    #[error("connector action requires approval for immutable action hash {action_hash}")]
    ApprovalRequired { action_hash: String },
}

#[derive(Clone, Debug)]
struct ActionGrant {
    approved_action_hash: String,
    idempotency_key: String,
}

pub struct EphemeralConnectorContextProvider {
    scope: CredentialScope,
    accounts: BTreeMap<String, String>,
    grants: Mutex<BTreeMap<String, ActionGrant>>,
    timeout: Duration,
}

impl EphemeralConnectorContextProvider {
    pub fn fail_closed(scope: CredentialScope, timeout: Duration) -> anyhow::Result<Self> {
        scope.validate()?;
        anyhow::ensure!(!timeout.is_zero(), "connector timeout must be positive");
        Ok(Self {
            scope,
            accounts: BTreeMap::new(),
            grants: Mutex::new(BTreeMap::new()),
            timeout,
        })
    }

    pub fn with_account(
        mut self,
        connector_id: impl Into<String>,
        account_id: impl Into<String>,
    ) -> Self {
        self.accounts.insert(connector_id.into(), account_id.into());
        self
    }

    pub fn grant_once(
        &self,
        action_hash: &str,
        idempotency_key: impl Into<String>,
    ) -> anyhow::Result<()> {
        anyhow::ensure!(
            action_hash.len() == 64 && action_hash.bytes().all(|byte| byte.is_ascii_hexdigit()),
            "connector action hash is invalid"
        );
        let idempotency_key = idempotency_key.into();
        anyhow::ensure!(
            !idempotency_key.trim().is_empty(),
            "connector idempotency key is required"
        );
        self.grants
            .lock()
            .expect("connector grant lock poisoned")
            .insert(
                action_hash.to_string(),
                ActionGrant {
                    approved_action_hash: action_hash.to_string(),
                    idempotency_key,
                },
            );
        Ok(())
    }
}

#[async_trait]
impl ConnectorCallContextProvider for EphemeralConnectorContextProvider {
    async fn context_for(
        &self,
        request: ConnectorToolAuthorizationRequest,
    ) -> anyhow::Result<ConnectorCallContext> {
        let approval_required = approval_required(&request.connector, &request.tool);
        let mut grant = self
            .grants
            .lock()
            .expect("connector grant lock poisoned")
            .remove(&request.action_hash);
        if request.trusted_host_action && grant.is_none() {
            grant = Some(ActionGrant {
                approved_action_hash: request.action_hash.clone(),
                idempotency_key: format!("trusted-host-action:{}", request.call_id),
            });
        }
        if approval_required && grant.is_none() {
            return Err(ConnectorToolAuthorizationError::ApprovalRequired {
                action_hash: request.action_hash,
            }
            .into());
        }
        let idempotency_key = if request.tool.risk.is_write() {
            Some(
                grant
                    .as_ref()
                    .map(|grant| grant.idempotency_key.clone())
                    .unwrap_or_else(|| format!("connector-action:{}", request.action_hash)),
            )
        } else {
            None
        };
        Ok(ConnectorCallContext {
            call_id: request.call_id,
            credential_scope: self.scope.clone(),
            account_id: self.accounts.get(&request.connector.id).cloned(),
            approved_action_hash: grant.map(|grant| grant.approved_action_hash),
            idempotency_key,
            timeout: self.timeout,
            cancellation: CancellationToken::new(),
        })
    }
}

#[derive(Clone)]
struct ConnectorToolBinding {
    descriptor: ConnectorDescriptor,
    spec: ConnectorToolSpec,
    canonical_name: String,
    local_alias: bool,
}

#[derive(Clone)]
pub struct ConnectorToolRuntime {
    runtime: Arc<ConnectorRuntime>,
    context_provider: Arc<dyn ConnectorCallContextProvider>,
    bindings: Arc<Vec<ConnectorToolBinding>>,
}

impl ConnectorToolRuntime {
    pub fn load(
        runtime: Arc<ConnectorRuntime>,
        context_provider: Arc<dyn ConnectorCallContextProvider>,
    ) -> anyhow::Result<Self> {
        let discovered = runtime.discover();
        let mut counts = BTreeMap::<String, usize>::new();
        for (_, tools) in &discovered {
            for tool in tools {
                *counts.entry(tool.name.clone()).or_default() += 1;
            }
        }
        let mut bindings = Vec::new();
        for (descriptor, tools) in discovered {
            for spec in tools {
                let canonical_name = connector_tool_name(&descriptor.id, &spec.name)?;
                bindings.push(ConnectorToolBinding {
                    local_alias: counts.get(&spec.name) == Some(&1),
                    descriptor: descriptor.clone(),
                    spec,
                    canonical_name,
                });
            }
        }
        bindings.sort_by(|left, right| left.canonical_name.cmp(&right.canonical_name));
        Ok(Self {
            runtime,
            context_provider,
            bindings: Arc::new(bindings),
        })
    }

    pub fn with_context_provider(
        &self,
        context_provider: Arc<dyn ConnectorCallContextProvider>,
    ) -> Self {
        Self {
            runtime: self.runtime.clone(),
            context_provider,
            bindings: self.bindings.clone(),
        }
    }

    pub fn definitions(&self) -> Vec<ToolDefinition> {
        let mut definitions = Vec::new();
        for binding in self.bindings.iter() {
            definitions.push(tool_definition(binding, binding.canonical_name.clone()));
            if binding.local_alias {
                definitions.push(tool_definition(binding, binding.spec.name.clone()));
            }
        }
        definitions
    }

    pub fn handles(&self, name: &str) -> bool {
        self.resolve(name).is_some()
    }

    pub fn parallel_safe(&self, name: &str) -> bool {
        self.resolve(name)
            .is_some_and(|binding| binding.spec.parallel_safe)
    }

    pub async fn execute(
        &self,
        name: &str,
        call_id: &str,
        arguments: Value,
    ) -> anyhow::Result<Value> {
        self.execute_inner(name, call_id, arguments, false).await
    }

    pub async fn execute_trusted_host_action(
        &self,
        name: &str,
        call_id: &str,
        arguments: Value,
    ) -> anyhow::Result<Value> {
        self.execute_inner(name, call_id, arguments, true).await
    }

    async fn execute_inner(
        &self,
        name: &str,
        call_id: &str,
        arguments: Value,
        trusted_host_action: bool,
    ) -> anyhow::Result<Value> {
        let binding = self
            .resolve(name)
            .ok_or_else(|| anyhow::anyhow!("unknown connector tool"))?;
        let action_hash =
            connector_action_hash(&binding.descriptor.id, &binding.spec.name, &arguments)?;
        let context = self
            .context_provider
            .context_for(ConnectorToolAuthorizationRequest {
                connector: binding.descriptor.clone(),
                tool: binding.spec.clone(),
                call_id: call_id.to_string(),
                action_hash,
                trusted_host_action,
            })
            .await?;
        let result = self
            .runtime
            .execute(
                &binding.descriptor.id,
                &binding.spec.name,
                arguments,
                context,
            )
            .await?;
        serde_json::to_value(result).map_err(Into::into)
    }

    fn resolve(&self, name: &str) -> Option<&ConnectorToolBinding> {
        self.bindings.iter().find(|binding| {
            binding.canonical_name == name || (binding.local_alias && binding.spec.name == name)
        })
    }
}

fn approval_required(descriptor: &ConnectorDescriptor, tool: &ConnectorToolSpec) -> bool {
    match descriptor.approval_mode {
        ConnectorApprovalMode::Auto => false,
        ConnectorApprovalMode::Prompt | ConnectorApprovalMode::Explicit => true,
        ConnectorApprovalMode::Writes => tool.risk.requires_external_approval(),
    }
}

fn connector_tool_name(connector_id: &str, tool_name: &str) -> anyhow::Result<String> {
    validate_model_part(connector_id, "connector id")?;
    validate_model_part(tool_name, "connector tool name")?;
    Ok(format!("connector__{connector_id}__{tool_name}"))
}

fn validate_model_part(value: &str, label: &str) -> anyhow::Result<()> {
    anyhow::ensure!(
        !value.is_empty()
            && value.len() <= 64
            && value.chars().all(
                |character| character.is_ascii_alphanumeric() || matches!(character, '-' | '_')
            ),
        "{label} must be model-safe"
    );
    Ok(())
}

fn tool_definition(binding: &ConnectorToolBinding, name: String) -> ToolDefinition {
    ToolDefinition {
        name,
        namespace: Some(format!("connector__{}", binding.descriptor.id)),
        description: binding.spec.description.clone(),
        input_schema: binding.spec.input_schema.clone(),
        output_schema: binding.spec.output_schema.clone(),
        permission: permission_for_risk(binding.spec.risk),
        persistence: persistence_for_risk(binding.spec.risk),
        source: ToolSource::AppConnector {
            connector: binding.descriptor.id.clone(),
        },
    }
}

fn persistence_for_risk(risk: ConnectorToolRisk) -> ToolPersistence {
    match risk {
        ConnectorToolRisk::Read | ConnectorToolRisk::SensitiveRead => ToolPersistence::MetadataOnly,
        ConnectorToolRisk::PersistentWrite
        | ConnectorToolRisk::Write
        | ConnectorToolRisk::DestructiveWrite => ToolPersistence::Full,
    }
}

fn permission_for_risk(risk: ConnectorToolRisk) -> ToolPermission {
    match risk {
        ConnectorToolRisk::Read => ToolPermission::ReadWorkspace,
        ConnectorToolRisk::SensitiveRead => ToolPermission::ReadSensitive,
        ConnectorToolRisk::PersistentWrite => ToolPermission::PersistData,
        ConnectorToolRisk::Write => ToolPermission::ExternalWrite,
        ConnectorToolRisk::DestructiveWrite => ToolPermission::DestructiveWrite,
    }
}

pub fn connector_authorization_error_code(error: &anyhow::Error) -> &'static str {
    if error
        .downcast_ref::<ConnectorToolAuthorizationError>()
        .is_some()
    {
        "approval_required"
    } else if error.to_string().contains("timed out") {
        "timeout"
    } else {
        "connector_error"
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::connector::{
        ConnectorHealth, ConnectorTransport, ConnectorTransportCall, ConnectorTransportKind,
    };
    use async_trait::async_trait;
    use serde_json::json;

    #[test]
    fn connector_reads_are_always_metadata_only() {
        assert_eq!(
            persistence_for_risk(ConnectorToolRisk::Read),
            ToolPersistence::MetadataOnly
        );
        assert_eq!(
            persistence_for_risk(ConnectorToolRisk::SensitiveRead),
            ToolPersistence::MetadataOnly
        );
        for risk in [
            ConnectorToolRisk::PersistentWrite,
            ConnectorToolRisk::Write,
            ConnectorToolRisk::DestructiveWrite,
        ] {
            assert_eq!(persistence_for_risk(risk), ToolPersistence::Full);
        }
    }

    struct EchoTransport;

    #[async_trait]
    impl ConnectorTransport for EchoTransport {
        async fn start(&self) -> anyhow::Result<()> {
            Ok(())
        }

        async fn list_tools(&self) -> anyhow::Result<Vec<ConnectorToolSpec>> {
            Ok(vec![
                connector_spec("read", ConnectorToolRisk::Read),
                connector_spec("sensitive", ConnectorToolRisk::SensitiveRead),
                connector_spec("write", ConnectorToolRisk::Write),
            ])
        }

        async fn call(&self, request: ConnectorTransportCall) -> anyhow::Result<Value> {
            Ok(request.arguments)
        }

        async fn health(&self) -> anyhow::Result<ConnectorHealth> {
            Ok(ConnectorHealth::Ready)
        }

        async fn stop(&self) -> anyhow::Result<()> {
            Ok(())
        }
    }

    fn connector_spec(name: &str, risk: ConnectorToolRisk) -> ConnectorToolSpec {
        ConnectorToolSpec {
            name: name.into(),
            description: format!("Run {name}."),
            input_schema: json!({"type": "object"}),
            output_schema: None,
            risk,
            required_scopes: Default::default(),
            parallel_safe: !risk.is_write(),
            supports_idempotency: risk.is_write(),
        }
    }

    async fn runtime() -> (ConnectorToolRuntime, Arc<EphemeralConnectorContextProvider>) {
        let connector = Arc::new(ConnectorRuntime::new(None, 4096).unwrap());
        connector
            .register(
                ConnectorDescriptor {
                    id: "example".into(),
                    name: "Example".into(),
                    version: "1.0.0".into(),
                    instructions: None,
                    transport: ConnectorTransportKind::LocalHost,
                    required_startup: true,
                    account_required: false,
                    approval_mode: ConnectorApprovalMode::Writes,
                    allowed_tools: Default::default(),
                    denied_tools: Default::default(),
                },
                Arc::new(EchoTransport),
            )
            .await
            .unwrap();
        let provider = Arc::new(
            EphemeralConnectorContextProvider::fail_closed(
                CredentialScope {
                    app_id: "app".into(),
                    tenant_id: "tenant".into(),
                    user_id: "user".into(),
                },
                Duration::from_secs(1),
            )
            .unwrap(),
        );
        (
            ConnectorToolRuntime::load(connector, provider.clone()).unwrap(),
            provider,
        )
    }

    #[tokio::test]
    async fn write_is_fail_closed_until_exact_hash_is_granted_once() {
        let (runtime, provider) = runtime().await;
        let arguments = json!({"value": "one"});
        let denied = runtime
            .execute("write", "call-1", arguments.clone())
            .await
            .unwrap_err();
        assert_eq!(
            connector_authorization_error_code(&denied),
            "approval_required"
        );
        let hash = connector_action_hash("example", "write", &arguments).unwrap();
        provider.grant_once(&hash, "action-1").unwrap();
        let result = runtime
            .execute("write", "call-2", arguments.clone())
            .await
            .unwrap();
        assert_eq!(result["output"], arguments);
        assert!(
            runtime
                .execute("write", "call-3", json!({"value": "two"}))
                .await
                .is_err()
        );
    }

    #[tokio::test]
    async fn unique_local_alias_and_canonical_name_are_both_discoverable() {
        let (runtime, _) = runtime().await;
        let names = runtime
            .definitions()
            .into_iter()
            .map(|definition| definition.name)
            .collect::<Vec<_>>();
        assert!(names.contains(&"write".to_string()));
        assert!(names.contains(&"connector__example__write".to_string()));
    }

    #[tokio::test]
    async fn discovered_connector_read_definitions_are_metadata_only() {
        let (runtime, _) = runtime().await;
        let definitions = runtime.definitions();

        for name in ["read", "sensitive"] {
            let definition = definitions
                .iter()
                .find(|definition| definition.name == name)
                .unwrap();
            assert_eq!(definition.persistence, ToolPersistence::MetadataOnly);
            assert_eq!(
                definition.effective_persistence(),
                ToolPersistence::MetadataOnly
            );
        }
        assert_eq!(
            definitions
                .iter()
                .find(|definition| definition.name == "write")
                .unwrap()
                .persistence,
            ToolPersistence::Full
        );
    }
}
