use super::*;
use crate::connector::ConnectorRuntime;
use crate::connector_tools::{ConnectorToolRuntime, EphemeralConnectorContextProvider};
use crate::credential::CredentialScope;
use crate::foundation_actions::MailActionService;
use crate::mail::{CreateDraftRequest, DraftContent, MailAccount, MailAddress, OutgoingBody};
use crate::mail_connector_transport::MailConnectorTransport;
use crate::mail_fake::FakeMailConnector;
use crate::model_config::StoredModelConfig;
use crate::platform::{CapabilitySet, PlatformId};
use crate::skill::SkillRegistry;
use crate::skill_catalog::SkillCatalog;
use crate::skill_manager::{SkillManager, SkillManagerConfig};
use crate::skill_source::{DirectorySkillSource, SkillLayer};
use crate::storage::Storage;
use crate::tools::RuntimeConfig;
use crate::tools::discovery::{
    ConnectorAuthState, ConnectorMetadata, ExternalToolConfig, ExternalToolVisibility,
};
use futures::stream;
use model_gateway::provider::EndpointType;
use model_gateway::responses::GatewayEvent;
use serde_json::{Value, json};
use std::collections::BTreeMap;
use std::path::Path;
use std::sync::atomic::{AtomicUsize, Ordering};
use std::sync::{Arc, Mutex};
use std::time::Duration;
use tempfile::tempdir;

struct FakeModel;

#[async_trait::async_trait]
impl crate::turn::ModelClient for FakeModel {
    async fn stream(
        &self,
        _request: model_gateway::responses::GatewayRequest,
    ) -> anyhow::Result<crate::turn::ModelEventStream> {
        Ok(Box::pin(stream::iter(vec![Ok(GatewayEvent::TextDelta {
            text: "hello from android".into(),
        })])))
    }
}

struct MobileMailPreviewModel {
    calls: AtomicUsize,
    draft_id: String,
}

#[async_trait::async_trait]
impl crate::turn::ModelClient for MobileMailPreviewModel {
    async fn stream(
        &self,
        request: model_gateway::responses::GatewayRequest,
    ) -> anyhow::Result<crate::turn::ModelEventStream> {
        let call = self.calls.fetch_add(1, Ordering::SeqCst);
        let events = if call == 0 {
            assert!(
                request
                    .tools
                    .iter()
                    .any(|tool| tool.advertised_name() == "mail_send_preview")
            );
            assert!(
                request
                    .tools
                    .iter()
                    .all(|tool| tool.advertised_name() != "mail_send")
            );
            vec![
                GatewayEvent::ToolCall {
                    call_id: "mobile-mail-preview".into(),
                    name: "mail_send_preview".into(),
                    legacy_alias_selected: false,
                    arguments: json!({
                        "accountId": "primary",
                        "draftId": self.draft_id,
                        "expectedRevision": 1
                    }),
                },
                GatewayEvent::Completed,
            ]
        } else {
            vec![
                GatewayEvent::TextDelta {
                    text: "Waiting for approval.".into(),
                },
                GatewayEvent::Completed,
            ]
        };
        Ok(Box::pin(stream::iter(events.into_iter().map(Ok))))
    }
}

struct InstructionCapturingModel {
    developer_inputs: Arc<Mutex<Vec<String>>>,
}

#[async_trait::async_trait]
impl crate::turn::ModelClient for InstructionCapturingModel {
    async fn stream(
        &self,
        request: model_gateway::responses::GatewayRequest,
    ) -> anyhow::Result<crate::turn::ModelEventStream> {
        let developer = request
            .input
            .iter()
            .find(|item| item["role"] == "developer")
            .and_then(|item| item["content"].as_str())
            .unwrap_or_default()
            .to_string();
        self.developer_inputs.lock().unwrap().push(developer);
        Ok(Box::pin(stream::iter(vec![Ok(GatewayEvent::TextDelta {
            text: "done".into(),
        })])))
    }
}

struct StaticSecretResolver;

#[async_trait::async_trait]
impl SecretResolver for StaticSecretResolver {
    async fn resolve_secret(&self, secret_id: &str) -> anyhow::Result<Option<String>> {
        assert_eq!(secret_id, "model.openai.default");
        Ok(Some("sk-runtime".into()))
    }
}

#[tokio::test]
async fn mobile_host_persists_turn_messages() {
    let dir = tempdir().unwrap();
    let db_url = format!("sqlite://{}?mode=rwc", dir.path().join("ga.db").display());
    let storage = Storage::connect(&db_url).await.unwrap();
    let runtime_config =
        RuntimeConfig::workspace_write(dir.path(), dir.path()).without_builtin_tools();
    let host = MobileRuntimeHost::new_for_test(
        storage,
        FakeModel,
        SkillRegistry::empty(),
        SkillCatalog::empty(),
        runtime_config,
        MobileRuntimeInit {
            platform: PlatformId::Android,
            capabilities: CapabilitySet::android_mvp(),
        },
    );

    let session = host.create_session("Mobile").await.unwrap();
    let result = host.send_message(&session.id, "Hi").await.unwrap();
    let messages = host.get_messages(&session.id).await.unwrap();

    assert_eq!(result.assistant_text, "hello from android");
    assert_eq!(messages.len(), 2);
    assert_eq!(messages[0].role, "user");
    assert_eq!(messages[1].content, "hello from android");
}

#[tokio::test]
async fn mobile_host_persists_agent_mail_preview_as_session_bound_action() {
    let dir = tempdir().unwrap();
    let db_url = format!("sqlite://{}?mode=rwc", dir.path().join("ga.db").display());
    let storage = Storage::connect(&db_url).await.unwrap();
    let mail = Arc::new(FakeMailConnector::new());
    mail.add_account(MailAccount {
        id: "primary".into(),
        display_name: "Work Mail".into(),
        primary_address: MailAddress {
            name: Some("Local User".into()),
            address: "local@example.test".into(),
        },
        addresses: Vec::new(),
        provider_reference: None,
    })
    .unwrap();
    let connector_runtime = Arc::new(ConnectorRuntime::new(None, 256 * 1024).unwrap());
    connector_runtime
        .register(
            MailConnectorTransport::descriptor("Fake Mail", true),
            Arc::new(MailConnectorTransport::new(mail.clone())),
        )
        .await
        .unwrap();
    let scope = CredentialScope {
        app_id: "agentweave.default".into(),
        tenant_id: "local".into(),
        user_id: "local-user".into(),
    };
    let context = Arc::new(
        EphemeralConnectorContextProvider::fail_closed(scope.clone(), Duration::from_secs(2))
            .unwrap(),
    );
    let connector_tools = ConnectorToolRuntime::load(connector_runtime, context.clone()).unwrap();
    let draft = connector_tools
        .execute_trusted_host_action(
            "mail_draft_create",
            "mobile-draft",
            serde_json::to_value(CreateDraftRequest {
                account_id: "primary".into(),
                content: DraftContent {
                    to: vec![MailAddress {
                        name: Some("Recipient".into()),
                        address: "recipient@example.test".into(),
                    }],
                    cc: Vec::new(),
                    bcc: Vec::new(),
                    subject: "Mobile approval".into(),
                    body: OutgoingBody {
                        plain_text: "Please review".into(),
                        html: None,
                    },
                    attachments: Vec::new(),
                    reply_context: None,
                    forward_context: None,
                },
            })
            .unwrap(),
        )
        .await
        .unwrap();
    let actions = MailActionService::new(
        &storage,
        connector_tools.clone(),
        context,
        scope,
        "mobile-agent-test-v1",
    )
    .await
    .unwrap();
    let host = MobileRuntimeHost::new_for_test(
        storage,
        MobileMailPreviewModel {
            calls: AtomicUsize::new(0),
            draft_id: draft["output"]["id"].as_str().unwrap().to_string(),
        },
        SkillRegistry::empty(),
        SkillCatalog::empty(),
        RuntimeConfig::workspace_write(dir.path(), dir.path()).without_builtin_tools(),
        MobileRuntimeInit {
            platform: PlatformId::Android,
            capabilities: CapabilitySet::android_mvp(),
        },
    )
    .with_foundations(None, Some(connector_tools))
    .with_mail_actions(Some(actions.clone()));
    let session = host.create_session("Mail approval").await.unwrap();

    let result = host
        .send_message(&session.id, "Send the reviewed draft")
        .await
        .unwrap();

    assert_eq!(result.assistant_text, "Waiting for approval.");
    let pending = actions.list_actions().await.unwrap();
    assert_eq!(pending.len(), 1);
    assert_eq!(
        pending[0].approval.binding.session_id.as_deref(),
        Some(session.id.as_str())
    );
    assert_eq!(mail.provider_submission_count(), 0);
}

#[tokio::test]
async fn android_host_disables_builtin_tools_even_for_workspace_write_config() {
    let dir = tempdir().unwrap();
    let db_url = format!("sqlite://{}?mode=rwc", dir.path().join("ga.db").display());
    let storage = Storage::connect(&db_url).await.unwrap();
    let runtime_config = RuntimeConfig::workspace_write(dir.path(), dir.path());

    let host = MobileRuntimeHost::new_for_test(
        storage,
        FakeModel,
        SkillRegistry::empty(),
        SkillCatalog::empty(),
        runtime_config,
        MobileRuntimeInit {
            platform: PlatformId::Android,
            capabilities: CapabilitySet::android_mvp(),
        },
    );

    assert!(!host.diagnostics().built_in_tools_enabled);
}

#[tokio::test]
async fn android_host_strips_external_tools_and_connectors_from_runtime_config() {
    let dir = tempdir().unwrap();
    let db_url = format!("sqlite://{}?mode=rwc", dir.path().join("ga.db").display());
    let storage = Storage::connect(&db_url).await.unwrap();
    let runtime_config = RuntimeConfig {
        external_tools: vec![ExternalToolConfig::mcp(
            "filesystem",
            "read_file",
            "Read a file through MCP.",
            json!({ "type": "object" }),
            ExternalToolVisibility::Immediate,
        )],
        connectors: vec![ConnectorMetadata {
            id: "desktop-drive".into(),
            name: "Desktop Drive".into(),
            description: "Desktop-only connector".into(),
            version: "1.0.0".into(),
            permissions: vec![],
            auth_state: ConnectorAuthState::Connected,
            tool_count: 1,
        }],
        ..RuntimeConfig::workspace_write(dir.path(), dir.path())
    };

    let host = MobileRuntimeHost::new_for_test(
        storage,
        FakeModel,
        SkillRegistry::empty(),
        SkillCatalog::empty(),
        runtime_config,
        MobileRuntimeInit {
            platform: PlatformId::Android,
            capabilities: CapabilitySet::android_mvp(),
        },
    );

    let diagnostics = host.diagnostics();

    assert!(host.runtime_config.external_tools.is_empty());
    assert!(host.runtime_config.connectors.is_empty());
    assert_eq!(diagnostics.configured_external_tool_count, 0);
    assert_eq!(diagnostics.configured_connector_count, 0);
}

#[tokio::test]
async fn android_host_hides_runtime_skill_tools_without_android_capability_support() {
    let dir = tempdir().unwrap();
    let skills_root = dir.path().join("skills");
    write_skill_manifest(
        &skills_root,
        "desktop-only",
        json!({
            "name": "desktop-only",
            "description": "Requires desktop automation.",
            "version": "0.1.0",
            "capabilities": {
                "requires": ["browser.headless"]
            },
            "entry": { "type": "command", "command": "node", "args": ["index.js"] },
            "tools": [
                {
                    "name": "desktop_only_tool",
                    "description": "Desktop only tool.",
                    "input_schema": { "type": "object" }
                }
            ]
        }),
    )
    .await;
    tokio::fs::write(
        skills_root.join("desktop-only").join("index.js"),
        "process.stdin.resume();\n",
    )
    .await
    .unwrap();

    let db_url = format!("sqlite://{}?mode=rwc", dir.path().join("ga.db").display());
    let storage = Storage::connect(&db_url).await.unwrap();
    let skills = SkillRegistry::load_development(&skills_root).await.unwrap();
    let host = MobileRuntimeHost::new_for_test(
        storage,
        FakeModel,
        skills,
        SkillCatalog::empty(),
        RuntimeConfig::workspace_write(dir.path(), dir.path()),
        MobileRuntimeInit {
            platform: PlatformId::Android,
            capabilities: CapabilitySet::android_mvp(),
        },
    );

    assert_eq!(host.diagnostics().registered_skill_tool_count, 0);
}

#[tokio::test]
async fn mobile_manager_constructor_rejects_desktop_runtime_context() {
    let dir = tempdir().unwrap();
    let skills_root = dir.path().join("skills");
    let package_root = skills_root.join("dynamic");
    write_dynamic_mobile_skill(&package_root, "first_tool").await;
    let manager = SkillManager::new(SkillManagerConfig {
        sources: vec![Arc::new(DirectorySkillSource::new(
            SkillLayer::Builtin,
            &skills_root,
        ))],
        platform: PlatformId::Desktop,
        capabilities: CapabilitySet::desktop_runtime(),
        protected_packages: Vec::new(),
        allowed_overrides: Vec::new(),
        runtime_version: "0.1.0".parse().unwrap(),
    })
    .await
    .unwrap();
    let db_url = format!("sqlite://{}?mode=rwc", dir.path().join("ga.db").display());
    let storage = Storage::connect(&db_url).await.unwrap();
    let error = MobileRuntimeHost::new_for_test_with_manager(
        storage,
        FakeModel,
        manager.clone(),
        RuntimeConfig::workspace_write(dir.path(), dir.path()),
        MobileRuntimeInit {
            platform: PlatformId::Android,
            capabilities: CapabilitySet::android_mvp(),
        },
    )
    .err()
    .expect("desktop manager must be rejected by Android host");

    assert_eq!(manager.current_snapshot().registry().tools().len(), 1);
    assert!(error.to_string().contains("runtime context"));
}

#[tokio::test]
async fn mobile_manager_constructor_rejects_missing_or_mismatched_context() {
    let dir = tempdir().unwrap();
    let init = MobileRuntimeInit {
        platform: PlatformId::Android,
        capabilities: CapabilitySet::android_mvp(),
    };
    let contextless =
        SkillManager::from_registry_and_catalog(SkillRegistry::empty(), SkillCatalog::empty());
    let storage = Storage::connect("sqlite::memory:").await.unwrap();
    let missing = MobileRuntimeHost::new_for_test_with_manager(
        storage,
        FakeModel,
        contextless,
        RuntimeConfig::workspace_write(dir.path(), dir.path()),
        init.clone(),
    )
    .err()
    .expect("contextless manager must be rejected");
    assert!(missing.to_string().contains("context is required"));

    let skills_root = dir.path().join("skills");
    tokio::fs::create_dir_all(&skills_root).await.unwrap();
    let manager = SkillManager::new(SkillManagerConfig {
        sources: vec![Arc::new(DirectorySkillSource::new(
            SkillLayer::Builtin,
            skills_root,
        ))],
        platform: PlatformId::Android,
        capabilities: CapabilitySet::from_names(["network.http"]),
        protected_packages: Vec::new(),
        allowed_overrides: Vec::new(),
        runtime_version: "0.1.0".parse().unwrap(),
    })
    .await
    .unwrap();
    let storage = Storage::connect("sqlite::memory:").await.unwrap();
    let mismatch = MobileRuntimeHost::new_for_test_with_manager(
        storage,
        FakeModel,
        manager,
        RuntimeConfig::workspace_write(dir.path(), dir.path()),
        init,
    )
    .err()
    .expect("capability mismatch must be rejected");
    assert!(mismatch.to_string().contains("does not match"));
}

#[tokio::test]
async fn mobile_instruction_view_updates_after_manager_reload() {
    let dir = tempdir().unwrap();
    let skills_root = dir.path().join("skills");
    let package_root = skills_root.join("instructions");
    write_mobile_instruction_package(&package_root, "First mobile body").await;
    let manager = SkillManager::new(SkillManagerConfig {
        sources: vec![Arc::new(DirectorySkillSource::new(
            SkillLayer::Builtin,
            &skills_root,
        ))],
        platform: PlatformId::Android,
        capabilities: CapabilitySet::android_mvp(),
        protected_packages: Vec::new(),
        allowed_overrides: Vec::new(),
        runtime_version: "0.1.0".parse().unwrap(),
    })
    .await
    .unwrap();
    let db_url = format!("sqlite://{}?mode=rwc", dir.path().join("ga.db").display());
    let storage = Storage::connect(&db_url).await.unwrap();
    let developer_inputs = Arc::new(Mutex::new(Vec::new()));
    let host = MobileRuntimeHost::new_for_test_with_manager(
        storage,
        InstructionCapturingModel {
            developer_inputs: developer_inputs.clone(),
        },
        manager.clone(),
        RuntimeConfig::workspace_write(dir.path(), dir.path()),
        MobileRuntimeInit {
            platform: PlatformId::Android,
            capabilities: CapabilitySet::android_mvp(),
        },
    )
    .unwrap();
    let session = host.create_session("Instructions").await.unwrap();

    host.send_message(&session.id, "use $mobile-instructions")
        .await
        .unwrap();
    write_mobile_instruction_package(&package_root, "Second mobile body").await;
    manager.reload().await.unwrap();
    host.send_message(&session.id, "use $mobile-instructions")
        .await
        .unwrap();

    let inputs = developer_inputs.lock().unwrap();
    assert!(inputs[0].contains("First mobile body"));
    assert!(!inputs[0].contains("Second mobile body"));
    assert!(inputs[1].contains("Second mobile body"));
    assert!(!inputs[1].contains("First mobile body"));
}

#[tokio::test]
async fn resolves_model_secret_for_provider_profile() {
    let model_config = StoredModelConfig {
        provider_id: "openai".into(),
        provider_name: "OpenAI".into(),
        endpoint_type: EndpointType::Responses,
        base_url: "https://api.openai.com/v1".into(),
        model_name: "gpt-5.4".into(),
        secret_id: Some("model.openai.default".into()),
        headers: BTreeMap::new(),
    };

    let api_key = resolve_model_api_key(&model_config, &StaticSecretResolver)
        .await
        .unwrap();

    assert_eq!(api_key.as_deref(), Some("sk-runtime"));
}

#[tokio::test]
async fn http_mobile_host_applies_android_runtime_sanitization() {
    let dir = tempdir().unwrap();
    let skills_root = dir.path().join("skills");
    write_skill_manifest(
        &skills_root,
        "desktop-only",
        json!({
            "name": "desktop-only",
            "description": "Requires desktop automation.",
            "version": "0.1.0",
            "capabilities": {
                "requires": ["browser.headless"]
            },
            "entry": { "type": "command", "command": "node", "args": ["index.js"] },
            "tools": [
                {
                    "name": "desktop_only_tool",
                    "description": "Desktop only tool.",
                    "input_schema": { "type": "object" }
                }
            ]
        }),
    )
    .await;
    tokio::fs::write(
        skills_root.join("desktop-only").join("index.js"),
        "process.stdin.resume();\n",
    )
    .await
    .unwrap();

    let db_url = format!("sqlite://{}?mode=rwc", dir.path().join("ga.db").display());
    let storage = Storage::connect(&db_url).await.unwrap();
    let skills = SkillRegistry::load_development(&skills_root).await.unwrap();
    let runtime_config = RuntimeConfig {
        external_tools: vec![ExternalToolConfig::mcp(
            "filesystem",
            "read_file",
            "Read a file through MCP.",
            json!({ "type": "object" }),
            ExternalToolVisibility::Immediate,
        )],
        connectors: vec![ConnectorMetadata {
            id: "desktop-drive".into(),
            name: "Desktop Drive".into(),
            description: "Desktop-only connector".into(),
            version: "1.0.0".into(),
            permissions: vec![],
            auth_state: ConnectorAuthState::Connected,
            tool_count: 1,
        }],
        ..RuntimeConfig::workspace_write(dir.path(), dir.path())
    };
    let model_config = StoredModelConfig {
        provider_id: "openai".into(),
        provider_name: "OpenAI".into(),
        endpoint_type: EndpointType::Responses,
        base_url: "https://api.openai.com/v1".into(),
        model_name: "gpt-5.4".into(),
        secret_id: Some("model.openai.default".into()),
        headers: BTreeMap::new(),
    };

    let host = HttpMobileRuntimeHost::new(
        storage,
        skills,
        SkillCatalog::empty(),
        runtime_config,
        MobileRuntimeInit {
            platform: PlatformId::Android,
            capabilities: CapabilitySet::android_mvp(),
        },
        model_config,
        StaticSecretResolver,
    );

    let diagnostics = host.diagnostics();

    assert!(!diagnostics.built_in_tools_enabled);
    assert_eq!(diagnostics.registered_skill_tool_count, 0);
    assert_eq!(diagnostics.configured_external_tool_count, 0);
    assert_eq!(diagnostics.configured_connector_count, 0);
}

#[tokio::test]
async fn http_mobile_manager_constructor_rejects_desktop_runtime_context() {
    let dir = tempdir().unwrap();
    let skills_root = dir.path().join("skills");
    write_dynamic_mobile_skill(&skills_root.join("dynamic"), "desktop_tool").await;
    let manager = SkillManager::new(SkillManagerConfig {
        sources: vec![Arc::new(DirectorySkillSource::new(
            SkillLayer::Builtin,
            &skills_root,
        ))],
        platform: PlatformId::Desktop,
        capabilities: CapabilitySet::desktop_runtime(),
        protected_packages: Vec::new(),
        allowed_overrides: Vec::new(),
        runtime_version: "0.1.0".parse().unwrap(),
    })
    .await
    .unwrap();
    let db_url = format!("sqlite://{}?mode=rwc", dir.path().join("ga.db").display());
    let storage = Storage::connect(&db_url).await.unwrap();
    let error = HttpMobileRuntimeHost::new_with_manager(
        storage,
        manager.clone(),
        RuntimeConfig::workspace_write(dir.path(), dir.path()),
        MobileRuntimeInit {
            platform: PlatformId::Android,
            capabilities: CapabilitySet::android_mvp(),
        },
        StoredModelConfig {
            provider_id: "openai".into(),
            provider_name: "OpenAI".into(),
            endpoint_type: EndpointType::Responses,
            base_url: "https://api.openai.com/v1".into(),
            model_name: "gpt-5.4".into(),
            secret_id: None,
            headers: BTreeMap::new(),
        },
        StaticSecretResolver,
    )
    .err()
    .expect("desktop manager must be rejected by Android HTTP host");

    assert_eq!(manager.current_snapshot().registry().tools().len(), 1);
    assert!(error.to_string().contains("runtime context"));
}

async fn write_skill_manifest(root: &Path, folder: &str, manifest: Value) {
    let skill_dir = root.join(folder);
    tokio::fs::create_dir_all(&skill_dir).await.unwrap();
    tokio::fs::write(skill_dir.join("skill.json"), manifest.to_string())
        .await
        .unwrap();
}

async fn write_dynamic_mobile_skill(package_root: &Path, tool_name: &str) {
    tokio::fs::create_dir_all(package_root).await.unwrap();
    tokio::fs::write(
        package_root.join("agentweave.json"),
        json!({
            "schemaVersion": 1,
            "id": "com.example.mobile-dynamic",
            "version": "1.0.0",
            "displayName": "Mobile dynamic",
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
    write_skill_manifest(
        package_root.parent().unwrap(),
        package_root.file_name().unwrap().to_str().unwrap(),
        json!({
            "name": "mobile-dynamic",
            "description": "Dynamic mobile skill.",
            "version": "1.0.0",
            "entry": { "type": "command", "command": "node", "args": ["index.js"] },
            "tools": [{
                "name": tool_name,
                "description": "Dynamic mobile tool.",
                "input_schema": { "type": "object" }
            }]
        }),
    )
    .await;
    tokio::fs::write(package_root.join("index.js"), "process.stdin.resume();\n")
        .await
        .unwrap();
}

async fn write_mobile_instruction_package(package_root: &Path, body: &str) {
    tokio::fs::create_dir_all(package_root).await.unwrap();
    tokio::fs::write(
        package_root.join("agentweave.json"),
        json!({
            "schemaVersion": 1,
            "id": "com.example.mobile-instructions",
            "version": "1.0.0",
            "displayName": "Mobile instructions",
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
            format!(
                "---\nname: mobile-instructions\ndescription: Mobile instructions.\n---\n\n# Mobile instructions\n{body}\n"
            ),
        )
        .await
        .unwrap();
}
