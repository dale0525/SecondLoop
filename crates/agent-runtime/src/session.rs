use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Deserialize, Serialize, PartialEq, Eq, Hash)]
#[serde(deny_unknown_fields)]
pub struct ConversationScope {
    pub app_id: String,
    pub agent_id: String,
    pub tenant_id: String,
    pub user_id: String,
    pub device_id: String,
}

impl ConversationScope {
    pub fn local(app_id: impl Into<String>) -> Self {
        Self {
            app_id: app_id.into(),
            agent_id: "default".into(),
            tenant_id: "local".into(),
            user_id: "local-user".into(),
            device_id: "local-device".into(),
        }
    }

    pub fn validate(&self) -> anyhow::Result<()> {
        for (name, value) in [
            ("app_id", &self.app_id),
            ("agent_id", &self.agent_id),
            ("tenant_id", &self.tenant_id),
            ("user_id", &self.user_id),
            ("device_id", &self.device_id),
        ] {
            anyhow::ensure!(!value.trim().is_empty(), "conversation {name} is required");
            anyhow::ensure!(value.len() <= 255, "conversation {name} is too long");
            anyhow::ensure!(
                !value.chars().any(char::is_control),
                "conversation {name} contains control characters"
            );
        }
        Ok(())
    }
}

impl Default for ConversationScope {
    fn default() -> Self {
        Self::local("dev.agentweave.default")
    }
}

#[derive(Debug, Clone, Deserialize, Serialize, PartialEq, Eq)]
pub struct Session {
    pub id: String,
    pub title: String,
    pub created_at: DateTime<Utc>,
    pub updated_at: DateTime<Utc>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct SessionPageCursor {
    pub snapshot_at: DateTime<Utc>,
    pub updated_at: DateTime<Utc>,
    pub created_at: DateTime<Utc>,
    pub id: String,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct SessionPage {
    pub items: Vec<Session>,
    pub next_cursor: Option<SessionPageCursor>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum SessionMutation {
    Applied(Session),
    Conflict(Session),
    NotFound,
}

#[derive(Debug, Clone, Deserialize, Serialize, PartialEq, Eq)]
pub struct Message {
    pub id: String,
    pub session_id: String,
    pub role: String,
    pub content: String,
    pub created_at: DateTime<Utc>,
}

#[derive(Debug, Clone, Deserialize, Serialize, PartialEq)]
pub struct ConversationEventRecord {
    pub id: String,
    pub session_id: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub turn_id: Option<String>,
    pub event_index: i64,
    pub kind: String,
    pub payload: serde_json::Value,
    pub created_at: DateTime<Utc>,
}

#[derive(Debug, Clone, Copy, Deserialize, Serialize, PartialEq, Eq)]
#[serde(rename_all = "snake_case")]
pub enum ConversationTurnStatus {
    Running,
    Completed,
    Failed,
    Cancelled,
    Interrupted,
}

impl ConversationTurnStatus {
    pub fn is_terminal(self) -> bool {
        self != Self::Running
    }

    pub fn as_str(self) -> &'static str {
        match self {
            Self::Running => "running",
            Self::Completed => "completed",
            Self::Failed => "failed",
            Self::Cancelled => "cancelled",
            Self::Interrupted => "interrupted",
        }
    }
}

impl std::str::FromStr for ConversationTurnStatus {
    type Err = anyhow::Error;

    fn from_str(value: &str) -> Result<Self, Self::Err> {
        match value {
            "running" => Ok(Self::Running),
            "completed" => Ok(Self::Completed),
            "failed" => Ok(Self::Failed),
            "cancelled" => Ok(Self::Cancelled),
            "interrupted" => Ok(Self::Interrupted),
            _ => anyhow::bail!("unknown conversation turn status"),
        }
    }
}

#[derive(Debug, Clone, Deserialize, Serialize, PartialEq, Eq)]
pub struct ConversationTurn {
    pub id: String,
    pub session_id: String,
    pub request_id: String,
    pub status: ConversationTurnStatus,
    pub user_message_id: String,
    pub assistant_message_id: Option<String>,
    pub failure_message: Option<String>,
    pub started_at: DateTime<Utc>,
    pub updated_at: DateTime<Utc>,
    pub finished_at: Option<DateTime<Utc>>,
}

#[derive(Debug, Clone, PartialEq)]
pub struct ConversationTurnEventPage {
    pub turn: ConversationTurn,
    pub events: Vec<ConversationEventRecord>,
    pub next_cursor: i64,
    pub has_more: bool,
}

pub fn messages_to_model_history(messages: &[Message]) -> anyhow::Result<Vec<serde_json::Value>> {
    messages
        .iter()
        .map(|message| {
            anyhow::ensure!(
                matches!(message.role.as_str(), "user" | "assistant"),
                "unsupported persisted conversation role: {}",
                message.role
            );
            Ok(serde_json::json!({
                "role": message.role,
                "content": message.content,
            }))
        })
        .collect()
}
