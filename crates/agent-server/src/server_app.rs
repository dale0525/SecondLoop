use agent_provider_adapters::credential_source::VaultCredentialSource;
use agent_provider_adapters::google_calendar::GoogleCalendarConnector;
use agent_provider_adapters::google_contacts::GoogleContactsConnector;
use agent_provider_adapters::http::ReqwestProviderHttpClient;
use agent_provider_adapters::microsoft_calendar::MicrosoftCalendarConnector;
use agent_provider_adapters::microsoft_contacts::MicrosoftContactsConnector;
use agent_provider_adapters::oauth_provider::{WorkspaceOAuthProvider, microsoft_mail_scopes};
use agent_runtime::app_definition::{
    AgentAppHostDiscovery, AgentAppRuntimeInventory, AgentAppRuntimePolicy, ResolvedAgentApp,
};
use agent_runtime::app_manifest::AppNetworkPolicy;
use agent_runtime::attachment_tools::AttachmentToolRuntime;
use agent_runtime::attachments::{AttachmentScope, SqliteAttachmentStore};
use agent_runtime::automation_tools::{AutomationScope, AutomationToolRuntime};
use agent_runtime::calendar::FakeCalendarConnector;
use agent_runtime::calendar_connector_transport::{
    CALENDAR_CONNECTOR_ID, CALENDAR_TOOL_NAMES, CalendarConnectorTransport,
};
use agent_runtime::connector::ConnectorRuntime;
use agent_runtime::connector_tools::{ConnectorToolRuntime, EphemeralConnectorContextProvider};
use agent_runtime::contacts::FakeContactsConnector;
use agent_runtime::contacts_connector_transport::{
    CONTACTS_CONNECTOR_ID, CONTACTS_TOOL_NAMES, ContactsConnectorTransport,
};
use agent_runtime::credential::{
    ConnectorAccount, CredentialScope, CredentialVault, ProviderCredential, SecretId,
    SecretMaterial,
};
use agent_runtime::mail::{MailAccount, MailAddress, MailConnector};
use agent_runtime::mail_attachments::{MailAttachmentSource, StoredMailAttachmentSource};
use agent_runtime::mail_connector_transport::{
    MAIL_CONNECTOR_ID, MAIL_TOOL_NAMES, MailConnectorTransport,
};
use agent_runtime::mail_fake::FakeMailConnector;
use agent_runtime::mail_imap_smtp::{ImapSmtpMailConfig, ImapSmtpMailConnector};
use agent_runtime::mail_imap_smtp_accounts::{
    ImapSmtpMailAccountManager, ManagedImapSmtpMailConnector, SqliteImapSmtpMailAccountStore,
};
use agent_runtime::memory::{MemoryProvider, MemoryScope};
use agent_runtime::memory_tools::MemoryToolRuntime;
use agent_runtime::platform::PlatformId;
use agent_runtime::prompt_composer::AppPromptConfig;
use agent_runtime::skill_manager::SkillManager;
use agent_runtime::storage::Storage;
use agent_runtime::task_tools::TaskToolRuntime;
use agent_runtime::tasks::{TaskProvider, TaskScope};
use agent_runtime::tools::RuntimeConfig;
use std::collections::BTreeSet;
use std::path::{Path, PathBuf};
use std::sync::Arc;
use std::time::Duration;

pub(super) struct ResolvedConnectorFoundation {
    pub(super) tools: ConnectorToolRuntime,
    pub(super) mail_actions: Option<agent_runtime::foundation_actions::MailActionService>,
    pub(super) calendar_actions: Option<agent_runtime::calendar_actions::CalendarActionService>,
    pub(super) contacts_actions: Option<agent_runtime::contacts_actions::ContactsActionService>,
    pub(super) oauth_broker: Option<agent_runtime::oauth::OAuthBroker>,
    pub(super) account_manager: Option<Arc<ImapSmtpMailAccountManager>>,
}

pub(super) struct ResolvedServerApp {
    pub(super) prompt: AppPromptConfig,
    pub(super) host_discovery: Option<AgentAppHostDiscovery>,
    pub(super) runtime_policy: Option<AgentAppRuntimePolicy>,
}

impl ResolvedServerApp {
    pub(super) fn enforce_runtime_policy(&self, runtime_config: RuntimeConfig) -> RuntimeConfig {
        match &self.runtime_policy {
            Some(policy) => runtime_config.with_agent_app_policy(policy.clone()),
            None => runtime_config,
        }
    }
}

pub(super) fn credential_root_for_database(database_path: Option<&Path>) -> Option<PathBuf> {
    database_path
        .and_then(Path::parent)
        .map(|parent| parent.join("credentials"))
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
enum MailConnectorMode {
    Unconfigured,
    Fake,
    ImapSmtp,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
enum WorkspaceProviderMode {
    Fake,
    Google,
    Microsoft,
}

pub(super) async fn resolve_app(
    manager: &SkillManager,
    runtime_config: &RuntimeConfig,
) -> anyhow::Result<ResolvedServerApp> {
    let Ok(root) = std::env::var("AGENTWEAVE_APP_ROOT") else {
        return Ok(ResolvedServerApp {
            prompt: AppPromptConfig::default(),
            host_discovery: None,
            runtime_policy: None,
        });
    };
    let snapshot = manager.current_snapshot();
    let capabilities = manager
        .runtime_context()
        .map(|context| {
            context
                .capabilities()
                .names()
                .iter()
                .cloned()
                .collect::<BTreeSet<_>>()
        })
        .unwrap_or_default()
        .into_iter()
        .chain(first_party_capabilities())
        .collect();
    let inventory = AgentAppRuntimeInventory {
        runtime_version: env!("CARGO_PKG_VERSION").parse()?,
        platform: manager
            .runtime_context()
            .map_or(PlatformId::Desktop, |context| context.platform()),
        packages: snapshot
            .packages()
            .iter()
            .map(|resolved| {
                (
                    resolved.package.descriptor.id.as_str().to_string(),
                    resolved.package.descriptor.version.clone(),
                )
            })
            .collect(),
        capabilities,
        runtime_tools: snapshot
            .registry()
            .tools()
            .iter()
            .map(|tool| tool.name.clone())
            .chain(crate::server_app::first_party_tool_names())
            .collect(),
        connectors: runtime_config
            .connectors
            .iter()
            .map(|connector| connector.id.clone())
            .chain([
                MAIL_CONNECTOR_ID.to_string(),
                CALENDAR_CONNECTOR_ID.to_string(),
                CONTACTS_CONNECTOR_ID.to_string(),
            ])
            .collect(),
    };
    let resolved =
        ResolvedAgentApp::load(PathBuf::from(root).as_path(), &inventory, 64 * 1024).await?;
    let host_discovery = resolved.host_discovery().clone();
    let runtime_policy = resolved.runtime_policy().clone();
    Ok(ResolvedServerApp {
        prompt: resolved.prompt,
        host_discovery: Some(host_discovery),
        runtime_policy: Some(runtime_policy),
    })
}

fn first_party_capabilities() -> impl Iterator<Item = String> {
    [
        "memory-provider",
        "provenance",
        "retention-policy",
        "reversible-history",
        "durable-actions",
        "approval-engine",
        "credential-vault",
        "mail-connector",
        "calendar-connector",
        "contacts-connector",
        "host-tools",
        "task-provider",
        "scheduler",
        "attachments",
        "data-protection",
    ]
    .into_iter()
    .map(str::to_string)
}

fn first_party_tool_names() -> impl Iterator<Item = String> {
    agent_runtime::memory_tools::MEMORY_TOOL_NAMES
        .into_iter()
        .chain(agent_runtime::task_tools::TASK_TOOL_NAMES)
        .chain(agent_runtime::automation_tools::AUTOMATION_TOOL_NAMES)
        .chain(agent_runtime::attachment_tools::ATTACHMENT_TOOL_NAMES)
        .chain(MAIL_TOOL_NAMES)
        .chain(CALENDAR_TOOL_NAMES)
        .chain(CONTACTS_TOOL_NAMES)
        .map(str::to_string)
}

pub(super) async fn resolve_memory_tools(
    storage: &Storage,
    app_prompt: &AppPromptConfig,
) -> anyhow::Result<Option<MemoryToolRuntime>> {
    let enabled = app_prompt
        .identity
        .enabled_capabilities
        .iter()
        .any(|capability| capability == "memory-provider")
        || std::env::var("AGENTWEAVE_MEMORY").as_deref() == Ok("enabled");
    if !enabled {
        return Ok(None);
    }
    let provider = Arc::new(storage.local_memory_provider());
    provider.initialize().await?;
    Ok(Some(MemoryToolRuntime::new(
        provider,
        MemoryScope::new(&app_prompt.identity.app_id, "local", "local-user")?,
    )?))
}

pub(super) async fn resolve_task_tools(
    storage: &Storage,
    app_prompt: &AppPromptConfig,
) -> anyhow::Result<Option<TaskToolRuntime>> {
    let enabled = app_prompt
        .identity
        .enabled_capabilities
        .iter()
        .any(|capability| capability == "task-provider")
        || std::env::var("AGENTWEAVE_TASKS").as_deref() == Ok("enabled");
    if !enabled {
        return Ok(None);
    }
    let provider = Arc::new(storage.local_task_provider());
    provider.initialize().await?;
    Ok(Some(TaskToolRuntime::new(
        provider,
        TaskScope::new(&app_prompt.identity.app_id, "local", "local-user")?,
    )?))
}

pub(super) async fn resolve_automation_tools(
    storage: &Storage,
    app_prompt: &AppPromptConfig,
    runtime_config: &RuntimeConfig,
) -> anyhow::Result<Option<AutomationToolRuntime>> {
    let declared = app_prompt
        .identity
        .enabled_capabilities
        .iter()
        .any(|capability| capability == "scheduler");
    let enabled_by_host = std::env::var("AGENTWEAVE_AUTOMATION").as_deref() == Ok("enabled");
    if !background_execution_allowed(runtime_config, declared, enabled_by_host) {
        return Ok(None);
    }
    AutomationToolRuntime::from_storage(
        storage,
        AutomationScope::new(&app_prompt.identity.app_id, "local", "local-user")?,
    )
    .await
    .map(Some)
}

pub(super) async fn resolve_attachment_tools(
    storage: &Storage,
    app_prompt: &AppPromptConfig,
) -> anyhow::Result<Option<AttachmentToolRuntime>> {
    let enabled = app_prompt
        .identity
        .enabled_capabilities
        .iter()
        .any(|capability| capability == "attachments")
        || std::env::var("AGENTWEAVE_ATTACHMENTS").as_deref() == Ok("enabled");
    if !enabled {
        return Ok(None);
    }
    Ok(Some(AttachmentToolRuntime::new(
        SqliteAttachmentStore::from_storage(storage).await?,
        AttachmentScope::new(&app_prompt.identity.app_id, "local", "local-user")?,
    )))
}

pub(super) async fn resolve_connector_tools(
    storage: &Storage,
    app_prompt: &AppPromptConfig,
    runtime_config: &RuntimeConfig,
    credential_vault_key: Option<Arc<SecretMaterial>>,
    credential_root: Option<&Path>,
) -> anyhow::Result<Option<ResolvedConnectorFoundation>> {
    let mail_declared = app_prompt
        .identity
        .enabled_capabilities
        .iter()
        .any(|capability| capability == "mail-connector");
    let mail_enabled_by_host = std::env::var("AGENTWEAVE_FAKE_MAIL").as_deref() == Ok("enabled");
    let mail_enabled = mail_foundation_allowed(runtime_config, mail_declared, mail_enabled_by_host);
    let calendar_declared = app_prompt
        .identity
        .enabled_capabilities
        .iter()
        .any(|capability| capability == "calendar-connector");
    let calendar_enabled_by_host =
        std::env::var("AGENTWEAVE_FAKE_CALENDAR").as_deref() == Ok("enabled");
    let calendar_enabled =
        calendar_foundation_allowed(runtime_config, calendar_declared, calendar_enabled_by_host);
    let contacts_declared = app_prompt
        .identity
        .enabled_capabilities
        .iter()
        .any(|capability| capability == "contacts-connector");
    let contacts_enabled_by_host =
        std::env::var("AGENTWEAVE_FAKE_CONTACTS").as_deref() == Ok("enabled");
    let contacts_enabled =
        contacts_foundation_allowed(runtime_config, contacts_declared, contacts_enabled_by_host);
    let workspace_provider = workspace_provider_mode_from_lookup(|name| std::env::var_os(name))?;
    if !mail_enabled && !calendar_enabled && !contacts_enabled {
        return Ok(None);
    }

    let ledger = Arc::new(
        agent_runtime::connector_ledger::SqliteConnectorActionLedger::from_storage(storage).await?,
    );
    let vault =
        resolve_credential_vault(storage, credential_vault_key.as_deref(), credential_root).await?;
    let runtime = Arc::new(ConnectorRuntime::new_with_ledger(
        vault.as_deref().cloned(),
        ledger,
        256 * 1024,
    )?);
    let scope = CredentialScope {
        app_id: app_prompt.identity.app_id.clone(),
        tenant_id: "local".into(),
        user_id: "local-user".into(),
    };
    let oauth_broker = if workspace_provider != WorkspaceProviderMode::Fake {
        let configured_vault = vault.as_ref().ok_or_else(|| {
            anyhow::anyhow!("workspace providers require the persistent Credential Vault")
        })?;
        let provider = match workspace_provider {
            WorkspaceProviderMode::Google => {
                let client_id = std::env::var("AGENTWEAVE_GOOGLE_CLIENT_ID")
                    .map_err(|_| anyhow::anyhow!("AGENTWEAVE_GOOGLE_CLIENT_ID is required"))?;
                let client_secret = std::env::var("AGENTWEAVE_GOOGLE_CLIENT_SECRET")
                    .ok()
                    .map(agent_runtime::credential::SecretMaterial::new)
                    .transpose()?;
                Arc::new(WorkspaceOAuthProvider::google(client_id, client_secret)?)
            }
            WorkspaceProviderMode::Microsoft => {
                let client_id = std::env::var("AGENTWEAVE_MICROSOFT_CLIENT_ID")
                    .map_err(|_| anyhow::anyhow!("AGENTWEAVE_MICROSOFT_CLIENT_ID is required"))?;
                let client_secret = std::env::var("AGENTWEAVE_MICROSOFT_CLIENT_SECRET")
                    .ok()
                    .map(agent_runtime::credential::SecretMaterial::new)
                    .transpose()?;
                Arc::new(WorkspaceOAuthProvider::microsoft(client_id, client_secret)?)
            }
            WorkspaceProviderMode::Fake => unreachable!("filtered above"),
        };
        Some(
            agent_runtime::oauth::OAuthBroker::new(
                storage,
                scope.clone(),
                std::env::var("AGENTWEAVE_OAUTH_CALLBACK_URL")
                    .unwrap_or_else(|_| "http://127.0.0.1:43121/oauth/callback".into()),
                configured_vault.clone(),
                vec![provider],
            )
            .await?,
        )
    } else {
        None
    };
    let workspace_credentials = if workspace_provider != WorkspaceProviderMode::Fake {
        Some(Arc::new(VaultCredentialSource::new(
            vault.as_ref().expect("checked above").clone(),
            oauth_broker.clone(),
            scope.clone(),
        )?)
            as Arc<
                dyn agent_provider_adapters::credential_source::ProviderCredentialSource,
            >)
    } else {
        None
    };
    let mut resolved_account_manager = None;
    if mail_enabled {
        let attachments_enabled = app_prompt
            .identity
            .enabled_capabilities
            .iter()
            .any(|capability| capability == "attachments")
            || std::env::var("AGENTWEAVE_ATTACHMENTS").as_deref() == Ok("enabled");
        let attachment_source: Option<Arc<dyn MailAttachmentSource>> = if attachments_enabled {
            Some(Arc::new(StoredMailAttachmentSource::new(
                SqliteAttachmentStore::from_storage(storage).await?,
                AttachmentScope::new(&app_prompt.identity.app_id, "local", "local-user")?,
            )) as Arc<dyn MailAttachmentSource>)
        } else {
            None
        };
        let (mail, display_name, deterministic, account_manager): (
            Arc<dyn MailConnector>,
            &str,
            bool,
            Option<Arc<ImapSmtpMailAccountManager>>,
        ) = match workspace_provider {
            WorkspaceProviderMode::Google => {
                let configured_vault = vault.as_ref().expect("checked above");
                let config = google_imap_smtp_config(scope.clone())?;
                let mut connector = ImapSmtpMailConnector::new(config, configured_vault.clone())?
                    .with_xoauth2_authentication(
                    MAIL_CONNECTOR_ID,
                    BTreeSet::from([
                        "https://www.googleapis.com/auth/gmail.modify".into(),
                        "https://www.googleapis.com/auth/gmail.compose".into(),
                        "https://www.googleapis.com/auth/gmail.send".into(),
                    ]),
                )?;
                if let Some(source) = &attachment_source {
                    connector = connector.with_attachment_source(source.clone());
                }
                (Arc::new(connector), "Gmail IMAP/SMTP", false, None)
            }
            WorkspaceProviderMode::Microsoft => {
                let configured_vault = vault.as_ref().expect("checked above");
                let config = microsoft_imap_smtp_config(scope.clone())?;
                let mut connector =
                    ImapSmtpMailConnector::new(config, configured_vault.clone())?
                        .with_xoauth2_authentication(MAIL_CONNECTOR_ID, microsoft_mail_scopes())?;
                if let Some(source) = &attachment_source {
                    connector = connector.with_attachment_source(source.clone());
                }
                (Arc::new(connector), "Outlook IMAP/SMTP", false, None)
            }
            WorkspaceProviderMode::Fake => {
                match mail_connector_mode_from_lookup(|name| std::env::var_os(name))? {
                    MailConnectorMode::ImapSmtp => {
                        let config = load_imap_smtp_config().await?;
                        anyhow::ensure!(
                            config.credential_scope.app_id == app_prompt.identity.app_id,
                            "IMAP/SMTP credential scope App does not match the active Agent App"
                        );
                        let configured_vault = vault.as_ref().ok_or_else(|| {
                            anyhow::anyhow!("IMAP/SMTP requires the persistent Credential Vault")
                        })?;
                        let granted_scopes = BTreeSet::from([
                            "mail.message.read".into(),
                            "mail.message.organize".into(),
                            "mail.message.send".into(),
                        ]);
                        let credential_id = config.credential_secret_id.as_str().to_string();
                        configured_vault
                            .register_provider_credential_persistent(
                                &config.credential_scope,
                                ProviderCredential {
                                    access_secret_id: config.credential_secret_id.clone(),
                                    credential_id: credential_id.clone(),
                                    expires_at: None,
                                    granted_scopes: granted_scopes.clone(),
                                    provider_id: "imap-smtp".into(),
                                    provider_subject: config.username.clone(),
                                    refresh_secret_id: None,
                                    revoked_at: None,
                                },
                            )
                            .await?;
                        configured_vault
                            .register_account_persistent(ConnectorAccount {
                                account_id: config.account.id.clone(),
                                allowed_scopes: granted_scopes,
                                connector_id: "agentweave.connector.mail.imap-smtp".into(),
                                credential_id,
                                scope: config.credential_scope.clone(),
                            })
                            .await?;
                        let mut connector =
                            ImapSmtpMailConnector::new(config, configured_vault.clone())?;
                        if let Some(source) = &attachment_source {
                            connector = connector.with_attachment_source(source.clone());
                        }
                        (Arc::new(connector), "IMAP/SMTP Mail", false, None)
                    }
                    MailConnectorMode::Fake => {
                        let fake = Arc::new(FakeMailConnector::new());
                        fake.add_account(MailAccount {
                            id: "primary".into(),
                            display_name: "Example Mail".into(),
                            primary_address: MailAddress {
                                name: Some("Local User".into()),
                                address: "local@example.test".into(),
                            },
                            addresses: Vec::new(),
                            provider_reference: None,
                        })?;
                        (fake, "Fake Mail", true, None)
                    }
                    MailConnectorMode::Unconfigured => match &vault {
                        Some(vault) => {
                            let mail = Arc::new(ManagedImapSmtpMailConnector::new());
                            let store =
                                SqliteImapSmtpMailAccountStore::from_storage(storage).await?;
                            let mut manager =
                                ImapSmtpMailAccountManager::new(store, vault.clone(), mail.clone());
                            if let Some(source) = &attachment_source {
                                manager = manager.with_attachment_source(source.clone());
                            }
                            let manager = Arc::new(manager);
                            manager.load_accounts(&scope).await?;
                            (mail, "Managed IMAP/SMTP Mail", false, Some(manager))
                        }
                        None => (
                            Arc::new(FakeMailConnector::new()),
                            "Unconfigured Mail",
                            true,
                            None,
                        ),
                    },
                }
            }
        };
        runtime
            .register(
                MailConnectorTransport::descriptor(display_name, deterministic),
                Arc::new(MailConnectorTransport::new(mail)),
            )
            .await?;
        resolved_account_manager = account_manager;
    }
    if calendar_enabled {
        let calendar: Arc<dyn agent_runtime::calendar::CalendarConnector> = match workspace_provider
        {
            WorkspaceProviderMode::Google => Arc::new(GoogleCalendarConnector::new(
                Arc::new(ReqwestProviderHttpClient::new(
                    "https://www.googleapis.com/",
                    false,
                )?),
                workspace_credentials
                    .as_ref()
                    .expect("configured above")
                    .clone(),
            )),
            WorkspaceProviderMode::Microsoft => Arc::new(MicrosoftCalendarConnector::new(
                Arc::new(ReqwestProviderHttpClient::new(
                    "https://graph.microsoft.com/",
                    false,
                )?),
                workspace_credentials
                    .as_ref()
                    .expect("configured above")
                    .clone(),
                microsoft_email_from_env()?,
            )?),
            WorkspaceProviderMode::Fake => Arc::new(FakeCalendarConnector::default()),
        };
        runtime
            .register(
                CalendarConnectorTransport::descriptor(
                    match workspace_provider {
                        WorkspaceProviderMode::Google => "Google Calendar",
                        WorkspaceProviderMode::Microsoft => "Microsoft Outlook Calendar",
                        WorkspaceProviderMode::Fake => "Fake Calendar",
                    },
                    true,
                ),
                Arc::new(CalendarConnectorTransport::new(calendar, scope.clone())?),
            )
            .await?;
    }
    if contacts_enabled {
        let contacts: Arc<dyn agent_runtime::contacts::ContactsConnector> = match workspace_provider
        {
            WorkspaceProviderMode::Google => Arc::new(GoogleContactsConnector::new(
                Arc::new(ReqwestProviderHttpClient::new(
                    "https://people.googleapis.com/",
                    false,
                )?),
                workspace_credentials
                    .as_ref()
                    .expect("configured above")
                    .clone(),
            )),
            WorkspaceProviderMode::Microsoft => Arc::new(MicrosoftContactsConnector::new(
                Arc::new(ReqwestProviderHttpClient::new(
                    "https://graph.microsoft.com/",
                    false,
                )?),
                workspace_credentials
                    .as_ref()
                    .expect("configured above")
                    .clone(),
            )),
            WorkspaceProviderMode::Fake => Arc::new(FakeContactsConnector::default()),
        };
        runtime
            .register(
                ContactsConnectorTransport::descriptor(
                    match workspace_provider {
                        WorkspaceProviderMode::Google => "Google Contacts",
                        WorkspaceProviderMode::Microsoft => "Microsoft Outlook Contacts",
                        WorkspaceProviderMode::Fake => "Fake Contacts",
                    },
                    true,
                ),
                Arc::new(ContactsConnectorTransport::new(contacts, scope.clone())?),
            )
            .await?;
    }
    let context = Arc::new(EphemeralConnectorContextProvider::fail_closed(
        scope.clone(),
        Duration::from_secs(30),
    )?);
    let tools = ConnectorToolRuntime::load(runtime, context.clone())?;
    let mail_actions = if mail_enabled {
        Some(
            agent_runtime::foundation_actions::MailActionService::new(
                storage,
                tools.clone(),
                context.clone(),
                scope.clone(),
                "agentweave.foundation-actions.v1",
            )
            .await?,
        )
    } else {
        None
    };
    let calendar_actions = if calendar_enabled {
        Some(
            agent_runtime::calendar_actions::CalendarActionService::new(
                storage,
                tools.clone(),
                context.clone(),
                scope.clone(),
                "agentweave.foundation-actions.v1",
            )
            .await?,
        )
    } else {
        None
    };
    let contacts_actions = if contacts_enabled {
        Some(
            agent_runtime::contacts_actions::ContactsActionService::new(
                storage,
                tools.clone(),
                context,
                scope,
                "agentweave.foundation-actions.v1",
            )
            .await?,
        )
    } else {
        None
    };
    Ok(Some(ResolvedConnectorFoundation {
        tools,
        mail_actions,
        calendar_actions,
        contacts_actions,
        oauth_broker,
        account_manager: resolved_account_manager,
    }))
}

pub(super) fn background_execution_allowed(
    runtime_config: &RuntimeConfig,
    declared_by_app: bool,
    enabled_by_host: bool,
) -> bool {
    runtime_config
        .agent_app_policy
        .as_ref()
        .map_or(declared_by_app || enabled_by_host, |policy| {
            policy.allows_background_execution(declared_by_app, enabled_by_host)
        })
}

fn mail_foundation_allowed(
    runtime_config: &RuntimeConfig,
    declared_by_app: bool,
    enabled_by_host: bool,
) -> bool {
    runtime_config
        .agent_app_policy
        .as_ref()
        .map_or(declared_by_app || enabled_by_host, |policy| {
            policy.network() != AppNetworkPolicy::Deny
                && policy.declares_connector(MAIL_CONNECTOR_ID)
                && declared_by_app
        })
}

fn calendar_foundation_allowed(
    runtime_config: &RuntimeConfig,
    declared_by_app: bool,
    enabled_by_host: bool,
) -> bool {
    runtime_config
        .agent_app_policy
        .as_ref()
        .map_or(declared_by_app || enabled_by_host, |policy| {
            policy.network() != AppNetworkPolicy::Deny
                && policy.declares_connector(CALENDAR_CONNECTOR_ID)
                && declared_by_app
        })
}

fn contacts_foundation_allowed(
    runtime_config: &RuntimeConfig,
    declared_by_app: bool,
    enabled_by_host: bool,
) -> bool {
    runtime_config
        .agent_app_policy
        .as_ref()
        .map_or(declared_by_app || enabled_by_host, |policy| {
            policy.network() != AppNetworkPolicy::Deny
                && policy.declares_connector(CONTACTS_CONNECTOR_ID)
                && declared_by_app
        })
}

fn workspace_provider_mode_from_lookup<F>(lookup: F) -> anyhow::Result<WorkspaceProviderMode>
where
    F: Fn(&str) -> Option<std::ffi::OsString>,
{
    match lookup("AGENTWEAVE_WORKSPACE_PROVIDER")
        .map(|value| value.into_string())
        .transpose()
        .map_err(|_| anyhow::anyhow!("AGENTWEAVE_WORKSPACE_PROVIDER must be valid UTF-8"))?
        .as_deref()
    {
        Some("google") => Ok(WorkspaceProviderMode::Google),
        Some("microsoft") => Ok(WorkspaceProviderMode::Microsoft),
        Some(value) => anyhow::bail!("unsupported AGENTWEAVE_WORKSPACE_PROVIDER '{value}'"),
        None => Ok(WorkspaceProviderMode::Fake),
    }
}

fn google_imap_smtp_config(scope: CredentialScope) -> anyhow::Result<ImapSmtpMailConfig> {
    let account_id = std::env::var("AGENTWEAVE_GOOGLE_ACCOUNT_ID")
        .map_err(|_| anyhow::anyhow!("AGENTWEAVE_GOOGLE_ACCOUNT_ID is required for Gmail"))?;
    let email = std::env::var("AGENTWEAVE_GOOGLE_EMAIL")
        .map_err(|_| anyhow::anyhow!("AGENTWEAVE_GOOGLE_EMAIL is required for Gmail"))?;
    Ok(ImapSmtpMailConfig {
        account: MailAccount {
            id: account_id,
            display_name: "Google Workspace".into(),
            primary_address: MailAddress {
                name: None,
                address: email.clone(),
            },
            addresses: Vec::new(),
            provider_reference: Some(agent_runtime::mail::ProviderReference {
                provider: "google-workspace".into(),
                id: email.clone(),
            }),
        },
        credential_scope: scope,
        credential_secret_id: SecretId::parse("oauth.managed.google")?,
        imap_host: "imap.gmail.com".into(),
        imap_port: 993,
        imap_tls: agent_runtime::mail_imap_smtp::MailTlsMode::Implicit,
        smtp_host: "smtp.gmail.com".into(),
        smtp_port: 465,
        smtp_tls: agent_runtime::mail_imap_smtp::MailTlsMode::Implicit,
        username: email,
        archive_mailbox: Some("[Gmail]/All Mail".into()),
        sent_mailbox: Some("[Gmail]/Sent Mail".into()),
        drafts_mailbox: Some("[Gmail]/Drafts".into()),
        trash_mailbox: Some("[Gmail]/Trash".into()),
        allow_insecure_localhost: false,
        connect_timeout_seconds: 30,
        operation_timeout_seconds: 60,
    })
}

fn microsoft_imap_smtp_config(scope: CredentialScope) -> anyhow::Result<ImapSmtpMailConfig> {
    let account_id = std::env::var("AGENTWEAVE_MICROSOFT_ACCOUNT_ID").map_err(|_| {
        anyhow::anyhow!("AGENTWEAVE_MICROSOFT_ACCOUNT_ID is required for Outlook Mail")
    })?;
    let email = microsoft_email_from_env()?;
    Ok(ImapSmtpMailConfig {
        account: MailAccount {
            id: account_id,
            display_name: "Microsoft 365".into(),
            primary_address: MailAddress {
                name: None,
                address: email.clone(),
            },
            addresses: Vec::new(),
            provider_reference: Some(agent_runtime::mail::ProviderReference {
                provider: "microsoft-graph".into(),
                id: email.clone(),
            }),
        },
        credential_scope: scope,
        credential_secret_id: SecretId::parse("oauth.managed.microsoft")?,
        imap_host: "outlook.office365.com".into(),
        imap_port: 993,
        imap_tls: agent_runtime::mail_imap_smtp::MailTlsMode::Implicit,
        smtp_host: "smtp.office365.com".into(),
        smtp_port: 587,
        smtp_tls: agent_runtime::mail_imap_smtp::MailTlsMode::StartTls,
        username: email,
        archive_mailbox: Some("Archive".into()),
        sent_mailbox: Some("Sent Items".into()),
        drafts_mailbox: Some("Drafts".into()),
        trash_mailbox: Some("Deleted Items".into()),
        allow_insecure_localhost: false,
        connect_timeout_seconds: 30,
        operation_timeout_seconds: 60,
    })
}

fn microsoft_email_from_env() -> anyhow::Result<String> {
    std::env::var("AGENTWEAVE_MICROSOFT_EMAIL")
        .map_err(|_| anyhow::anyhow!("AGENTWEAVE_MICROSOFT_EMAIL is required"))
}

fn mail_connector_mode_from_lookup<F>(lookup: F) -> anyhow::Result<MailConnectorMode>
where
    F: Fn(&str) -> Option<std::ffi::OsString>,
{
    let connector = lookup("AGENTWEAVE_MAIL_CONNECTOR")
        .map(|value| {
            value
                .into_string()
                .map_err(|_| anyhow::anyhow!("AGENTWEAVE_MAIL_CONNECTOR must be valid UTF-8"))
        })
        .transpose()?;
    match connector.as_deref() {
        Some("imap-smtp") => Ok(MailConnectorMode::ImapSmtp),
        Some(value) => anyhow::bail!("unsupported AGENTWEAVE_MAIL_CONNECTOR '{value}'"),
        None if lookup("AGENTWEAVE_FAKE_MAIL").as_deref()
            == Some(std::ffi::OsStr::new("enabled")) =>
        {
            Ok(MailConnectorMode::Fake)
        }
        None => Ok(MailConnectorMode::Unconfigured),
    }
}

async fn load_imap_smtp_config() -> anyhow::Result<ImapSmtpMailConfig> {
    let path = PathBuf::from(
        std::env::var("AGENTWEAVE_MAIL_ACCOUNT_CONFIG").map_err(|_| {
            anyhow::anyhow!("AGENTWEAVE_MAIL_ACCOUNT_CONFIG is required for IMAP/SMTP")
        })?,
    );
    let metadata = tokio::fs::symlink_metadata(&path).await?;
    anyhow::ensure!(
        metadata.is_file() && !metadata.file_type().is_symlink(),
        "IMAP/SMTP account config must be a real file"
    );
    anyhow::ensure!(
        metadata.len() <= 64 * 1024,
        "IMAP/SMTP account config is too large"
    );
    let config: ImapSmtpMailConfig = serde_json::from_slice(&tokio::fs::read(path).await?)?;
    config.validate()?;
    Ok(config)
}

async fn resolve_credential_vault(
    storage: &Storage,
    trusted_key: Option<&SecretMaterial>,
    trusted_root: Option<&Path>,
) -> anyhow::Result<Option<Arc<CredentialVault>>> {
    if let Some(key) = trusted_key {
        let root = trusted_root
            .ok_or_else(|| anyhow::anyhow!("trusted Credential Vault root is unavailable"))?;
        let store = Arc::new(
            agent_runtime::credential_file::EncryptedFileSecretStore::new_borrowed(root, key)?,
        );
        let metadata =
            agent_runtime::credential_sqlite::SqliteCredentialMetadataStore::from_storage(storage)
                .await?;
        return Ok(Some(Arc::new(CredentialVault::new_persistent(
            store, metadata,
        ))));
    }
    let configured = match (
        std::env::var("AGENTWEAVE_SECRET_ROOT").ok(),
        std::env::var("AGENTWEAVE_SECRET_MASTER_KEY_HEX").ok(),
    ) {
        (None, None) => return Ok(None),
        (Some(root), Some(key)) => (root, key),
        _ => anyhow::bail!(
            "AGENTWEAVE_SECRET_ROOT and AGENTWEAVE_SECRET_MASTER_KEY_HEX must be configured together"
        ),
    };
    let key = hex::decode(configured.1)?;
    anyhow::ensure!(key.len() == 32, "secret master key must decode to 32 bytes");
    let store = Arc::new(
        agent_runtime::credential_file::EncryptedFileSecretStore::new(
            configured.0,
            agent_runtime::credential::SecretMaterial::new(key)?,
        )?,
    );
    let metadata =
        agent_runtime::credential_sqlite::SqliteCredentialMetadataStore::from_storage(storage)
            .await?;
    Ok(Some(Arc::new(CredentialVault::new_persistent(
        store, metadata,
    ))))
}

#[cfg(test)]
#[path = "server_app_tests.rs"]
mod tests;

#[cfg(test)]
#[path = "server_app_workspace_tests.rs"]
mod workspace_tests;
