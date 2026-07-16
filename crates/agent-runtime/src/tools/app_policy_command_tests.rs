use super::*;
use crate::app_definition::AgentAppRuntimePolicy;
use crate::app_manifest::AgentAppManifest;
use crate::skill::SkillRegistry;

fn app_policy(network: &str, runtime_tools: &[&str]) -> AgentAppRuntimePolicy {
    let manifest = serde_json::json!({
        "schemaVersion": 1,
        "appId": "com.example.command-policy",
        "package": {"id": "com.example.command-policy.app", "version": "0.1.0"},
        "requires": {
            "packages": [],
            "capabilities": [],
            "runtimeTools": runtime_tools,
            "connectors": []
        },
        "features": [],
        "policy": {
            "externalSideEffects": "allow_by_policy",
            "network": network,
            "backgroundExecution": "disabled",
            "memoryPersistence": "disabled",
            "skillManagement": "disabled"
        },
        "branding": {"displayName": "Command Policy"},
        "instructions": {"system": "prompts/system.md"}
    });
    let manifest = AgentAppManifest::parse_json(&serde_json::to_vec(&manifest).unwrap()).unwrap();
    AgentAppRuntimePolicy::compile(&manifest)
}

fn deny_network_policy() -> AgentAppRuntimePolicy {
    app_policy("deny", &["host_lookup"])
}

#[tokio::test]
async fn restricted_network_policy_disables_host_enabled_command_execution() {
    let root = std::env::temp_dir().join(format!(
        "agentweave-app-policy-command-{}",
        uuid::Uuid::new_v4()
    ));
    std::fs::create_dir_all(&root).unwrap();
    let config = RuntimeConfig {
        agent_app_policy: Some(deny_network_policy()),
        ..RuntimeConfig::workspace_write(root.clone(), root.clone())
            .with_command_mode(CommandMode::Allowed)
    };
    let registry = ToolRegistry::new(SkillRegistry::empty_for_tests(), &config);

    assert!(
        registry
            .definitions()
            .iter()
            .all(|tool| tool.name != "exec_command")
    );
    let result = registry
        .execute(
            "exec_command",
            "call-command",
            serde_json::json!({"cmd":"printf blocked"}),
        )
        .await;
    assert_eq!(result.error.unwrap().code, "permission_denied");
    tokio::fs::remove_dir_all(root).await.unwrap();
}

#[test]
fn restricted_network_policy_fails_closed_for_unknown_host_capabilities() {
    let definition = ToolDefinition {
        name: "host_lookup".into(),
        namespace: Some("host".into()),
        description: "Unknown host lookup".into(),
        input_schema: serde_json::json!({"type":"object"}),
        output_schema: None,
        permission: ToolPermission::ReadSensitive,
        persistence: ToolPersistence::for_permission(ToolPermission::ReadSensitive),
        source: ToolSource::HostCapability {
            capability: "example.host.network/v1".into(),
        },
    };

    assert!(!app_policy_allows_tool(&deny_network_policy(), &definition));
}

#[test]
fn declared_network_policy_allows_declared_foundation_mail_host_tool() {
    let definition = foundation_actions::mail_send_preview_definition();

    assert!(app_policy_allows_tool(
        &app_policy("declared_only", &["mail_send_preview"]),
        &definition,
    ));
    assert!(!app_policy_allows_tool(
        &app_policy("declared_only", &[]),
        &definition,
    ));
}
