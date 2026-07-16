use super::*;
use crate::tools::discovery::{ExternalToolConfig, ExternalToolExecution, ExternalToolVisibility};
use crate::tools::{ToolPermission, ToolPersistence};
use futures::stream;
use std::sync::atomic::{AtomicUsize, Ordering};

struct SensitiveToolModel {
    calls: AtomicUsize,
}

#[async_trait]
impl ModelClient for SensitiveToolModel {
    async fn stream(&self, _request: GatewayRequest) -> anyhow::Result<ModelEventStream> {
        let call = self.calls.fetch_add(1, Ordering::SeqCst);
        let events = if call == 0 {
            vec![
                Ok(GatewayEvent::ToolCall {
                    call_id: "call-sensitive".into(),
                    name: "mcp__vault__read".into(),
                    legacy_alias_selected: false,
                    arguments: serde_json::json!({"key": "live-argument-secret"}),
                }),
                Ok(GatewayEvent::Completed),
            ]
        } else {
            vec![Ok(GatewayEvent::Completed)]
        };
        Ok(Box::pin(stream::iter(events)))
    }
}

#[tokio::test]
async fn sensitive_tool_live_events_keep_full_values_with_metadata_only_policy() {
    let mut tool = ExternalToolConfig::mcp(
        "vault",
        "read",
        "Read one sensitive value.",
        serde_json::json!({"type": "object"}),
        ExternalToolVisibility::Immediate,
    );
    tool.permission = ToolPermission::ReadSensitive;
    tool.execution = ExternalToolExecution::Static {
        result: serde_json::json!({"value": "live-result-secret"}),
    };
    let root = tempfile::tempdir().unwrap();
    let config = RuntimeConfig {
        external_tools: vec![tool],
        ..RuntimeConfig::workspace_write(root.path(), root.path())
    };
    let runner = TurnRunner::new_with_config(
        SensitiveToolModel {
            calls: AtomicUsize::new(0),
        },
        SkillRegistry::empty(),
        config,
    );

    let events = runner.run("read a sensitive value").await.unwrap();

    assert!(events.iter().any(|event| matches!(
        event,
        RuntimeEvent::ToolCallStarted {
            arguments,
            persistence: ToolPersistence::MetadataOnly,
            ..
        } if arguments["key"] == "live-argument-secret"
    )));
    assert!(events.iter().any(|event| matches!(
        event,
        RuntimeEvent::ToolCallFinished {
            result,
            persistence: ToolPersistence::MetadataOnly,
            ..
        } if result["data"]["value"] == "live-result-secret"
    )));
}
