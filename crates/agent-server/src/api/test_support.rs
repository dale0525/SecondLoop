use super::*;

pub(super) fn default_runtime_config() -> RuntimeConfig {
    let cwd = std::env::current_dir().unwrap_or_else(|_| PathBuf::from("."));
    RuntimeConfig::workspace_write(cwd.clone(), cwd).without_builtin_tools()
}

pub(super) struct DeterministicAgent;

#[async_trait::async_trait]
impl AgentRunner for DeterministicAgent {
    async fn run(&self, user_text: &str) -> anyhow::Result<Vec<RuntimeEvent>> {
        let turn_id = uuid::Uuid::new_v4().to_string();
        let assistant_text = format!("MVP agent received: {user_text}");

        Ok(vec![
            RuntimeEvent::TurnStarted {
                turn_id: turn_id.clone(),
            },
            RuntimeEvent::AssistantTextDelta {
                text: assistant_text.clone(),
            },
            RuntimeEvent::AssistantMessageFinished {
                text: assistant_text,
            },
            RuntimeEvent::TurnFinished { turn_id },
        ])
    }
}
