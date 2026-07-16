use super::*;
use crate::connector::ConnectorRuntime;
use crate::connector_tools::{ConnectorToolRuntime, EphemeralConnectorContextProvider};
use crate::credential::CredentialScope;
use crate::foundation_actions::{FoundationActionTurnContext, MailActionService};
use crate::mail_connector_transport::MailConnectorTransport;
use crate::mail_fake::FakeMailConnector;
use crate::skill::SkillRegistry;
use crate::storage::Storage;
use std::sync::Arc;
use std::time::Duration;

#[tokio::test]
async fn registry_exposes_only_the_runtime_managed_preview_contract() {
    let registry = registry_with_mail_actions(Some(trusted_context())).await;
    let definitions = registry.definitions();
    let preview = definitions
        .iter()
        .find(|definition| definition.name == MAIL_SEND_PREVIEW)
        .expect("Runtime-managed Mail preview must be model-visible");

    assert_eq!(
        definitions
            .iter()
            .filter(|definition| definition.name == MAIL_SEND_PREVIEW)
            .count(),
        1
    );
    for hidden in [MAIL_SEND, CANONICAL_MAIL_SEND, CANONICAL_MAIL_SEND_PREVIEW] {
        assert!(
            definitions
                .iter()
                .all(|definition| definition.name != hidden),
            "{hidden} must not be model-visible"
        );
    }
    assert_eq!(
        preview.input_schema["required"],
        serde_json::json!(["accountId", "draftId", "expectedRevision"])
    );
    assert_eq!(preview.permission, ToolPermission::ReadSensitive);
    let properties = preview.input_schema["properties"].as_object().unwrap();
    for runtime_owned in ["sessionId", "turnId", "idempotencyKey", "approvalId"] {
        assert!(!properties.contains_key(runtime_owned));
    }
}

#[tokio::test]
async fn registry_rejects_direct_or_canonical_mail_delivery_dispatch() {
    let registry = registry_with_mail_actions(Some(trusted_context())).await;

    for disabled in [MAIL_SEND, CANONICAL_MAIL_SEND, CANONICAL_MAIL_SEND_PREVIEW] {
        let result = registry
            .execute(disabled, "call-disabled", serde_json::json!({}))
            .await;
        assert!(!result.ok);
        assert_eq!(result.error.unwrap().code, "tool_disabled");
    }
}

#[tokio::test]
async fn registry_fails_closed_without_host_session_context() {
    let registry = registry_with_mail_actions(None).await;
    let result = registry
        .execute(
            MAIL_SEND_PREVIEW,
            "call-preview",
            serde_json::json!({
                "accountId": "primary",
                "draftId": "draft-1",
                "expectedRevision": 1
            }),
        )
        .await;

    assert!(!result.ok);
    assert_eq!(result.error.unwrap().code, "trusted_context_missing");
}

fn trusted_context() -> FoundationActionTurnContext {
    FoundationActionTurnContext::new("session-1", "turn-1").unwrap()
}

async fn registry_with_mail_actions(context: Option<FoundationActionTurnContext>) -> ToolRegistry {
    let storage = Storage::connect("sqlite::memory:").await.unwrap();
    let runtime = Arc::new(ConnectorRuntime::new(None, 256 * 1024).unwrap());
    runtime
        .register(
            MailConnectorTransport::descriptor("Fake Mail", true),
            Arc::new(MailConnectorTransport::new(Arc::new(
                FakeMailConnector::new(),
            ))),
        )
        .await
        .unwrap();
    let scope = CredentialScope {
        app_id: "com.example.agent".into(),
        tenant_id: "tenant-1".into(),
        user_id: "user-1".into(),
    };
    let provider = Arc::new(
        EphemeralConnectorContextProvider::fail_closed(scope.clone(), Duration::from_secs(2))
            .unwrap(),
    );
    let connector_tools = ConnectorToolRuntime::load(runtime, provider.clone()).unwrap();
    let actions = MailActionService::new(
        &storage,
        connector_tools.clone(),
        provider,
        scope,
        "registry-test-v1",
    )
    .await
    .unwrap();
    let root = std::env::temp_dir();
    let config = RuntimeConfig::workspace_write(root.clone(), root).without_builtin_tools();

    ToolRegistry::new(SkillRegistry::empty_for_tests(), &config)
        .try_with_connector_tools(connector_tools)
        .unwrap()
        .try_with_mail_actions(actions, context)
        .unwrap()
}
