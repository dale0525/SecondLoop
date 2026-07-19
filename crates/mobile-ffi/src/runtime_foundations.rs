use agent_runtime::app_manifest::AppNetworkPolicy;
use agent_runtime::connector::ConnectorRuntime;
use agent_runtime::connector_ledger::SqliteConnectorActionLedger;
use agent_runtime::connector_tools::{ConnectorToolRuntime, EphemeralConnectorContextProvider};
use agent_runtime::credential::{CredentialScope, CredentialVault, InMemorySecretStore};
use agent_runtime::foundation_actions::MailActionService;
use agent_runtime::mail::{MailAccount, MailAddress};
use agent_runtime::mail_connector_transport::MailConnectorTransport;
use agent_runtime::mail_fake::FakeMailConnector;
use agent_runtime::memory::{MemoryProvider, MemoryScope};
use agent_runtime::memory_tools::MemoryToolRuntime;
use agent_runtime::prompt_composer::AppPromptConfig;
use agent_runtime::session::ConversationScope;
use agent_runtime::storage::Storage;
use agent_runtime::tools::RuntimeConfig;
use anyhow::Result;
use std::sync::Arc;
use std::time::Duration;

pub(super) async fn resolve_mobile_memory(
    storage: &Storage,
    app_prompt: &AppPromptConfig,
    conversation_scope: &ConversationScope,
) -> Result<Option<MemoryToolRuntime>> {
    if !app_prompt
        .identity
        .enabled_capabilities
        .iter()
        .any(|capability| capability == "memory-provider")
    {
        return Ok(None);
    }
    let provider = Arc::new(storage.local_memory_provider());
    provider.initialize().await?;
    Ok(Some(MemoryToolRuntime::new(
        provider,
        MemoryScope::new(
            &conversation_scope.app_id,
            &conversation_scope.tenant_id,
            &conversation_scope.user_id,
        )?,
    )?))
}

pub(super) async fn resolve_mobile_mail(
    storage: &Storage,
    app_prompt: &AppPromptConfig,
    runtime_config: &RuntimeConfig,
    conversation_scope: &ConversationScope,
) -> Result<Option<(ConnectorToolRuntime, MailActionService)>> {
    if !app_prompt
        .identity
        .enabled_capabilities
        .iter()
        .any(|capability| capability == "mail-connector")
    {
        return Ok(None);
    }
    if runtime_config
        .agent_app_policy
        .as_ref()
        .is_some_and(|policy| {
            policy.network() == AppNetworkPolicy::Deny
                || !policy
                    .declares_connector(agent_runtime::mail_connector_transport::MAIL_CONNECTOR_ID)
        })
    {
        return Ok(None);
    }
    let mail = Arc::new(FakeMailConnector::new());
    mail.add_account(MailAccount {
        id: "primary".into(),
        display_name: "Example Mail".into(),
        primary_address: MailAddress {
            name: Some("Local User".into()),
            address: "local@example.test".into(),
        },
        addresses: Vec::new(),
        provider_reference: None,
    })?;
    let ledger = Arc::new(SqliteConnectorActionLedger::from_storage(storage).await?);
    let vault = CredentialVault::new(Arc::new(InMemorySecretStore::default()));
    let runtime = Arc::new(ConnectorRuntime::new_with_ledger(
        Some(vault),
        ledger,
        256 * 1024,
    )?);
    runtime
        .register(
            MailConnectorTransport::descriptor("Fake Mail", true),
            Arc::new(MailConnectorTransport::new(mail)),
        )
        .await?;
    let scope = CredentialScope {
        app_id: conversation_scope.app_id.clone(),
        tenant_id: conversation_scope.tenant_id.clone(),
        user_id: conversation_scope.user_id.clone(),
    };
    let context = Arc::new(EphemeralConnectorContextProvider::fail_closed(
        scope.clone(),
        Duration::from_secs(30),
    )?);
    let tools = ConnectorToolRuntime::load(runtime, context.clone())?;
    let actions = MailActionService::new(
        storage,
        tools.clone(),
        context,
        scope,
        "agentweave.mobile.foundation-actions.v1",
    )
    .await?;
    Ok(Some((tools, actions)))
}
