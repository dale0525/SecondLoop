use super::{ToolDefinition, ToolPermission, ToolPersistence, ToolSource};
use serde::{Deserialize, Serialize};
use serde_json::Value;

#[derive(Debug, Clone, Deserialize, Serialize, PartialEq, Eq)]
#[serde(rename_all = "snake_case")]
pub enum ConnectorAuthState {
    NotRequired,
    Connected,
    Missing,
}

#[derive(Debug, Clone, Deserialize, Serialize, PartialEq, Eq)]
pub struct ConnectorMetadata {
    pub id: String,
    pub name: String,
    pub description: String,
    pub version: String,
    pub permissions: Vec<ToolPermission>,
    pub auth_state: ConnectorAuthState,
    pub tool_count: usize,
}

#[derive(Debug, Clone, Deserialize, Serialize, PartialEq)]
pub enum ExternalToolVisibility {
    Immediate,
    Deferred { summary: String },
}

#[derive(Debug, Clone, Deserialize, Serialize, PartialEq)]
pub enum ExternalToolExecution {
    Unavailable,
    Static { result: Value },
}

#[derive(Debug, Clone, Deserialize, Serialize, PartialEq)]
pub enum ExternalToolKind {
    Mcp { server: String },
    AppConnector { connector: String },
}

#[derive(Debug, Clone, Deserialize, Serialize, PartialEq)]
pub struct ExternalToolConfig {
    pub kind: ExternalToolKind,
    pub name: String,
    pub description: String,
    pub input_schema: Value,
    pub permission: ToolPermission,
    pub visibility: ExternalToolVisibility,
    pub execution: ExternalToolExecution,
}

#[derive(Debug, Clone, Deserialize, Serialize, PartialEq)]
pub struct ToolDiscoveryItem {
    pub name: String,
    pub namespace: Option<String>,
    pub description: String,
    pub summary: String,
    pub permission: ToolPermission,
    pub source: ToolSource,
    pub schema_loaded: bool,
    pub deferred: bool,
}

impl ExternalToolConfig {
    pub fn mcp(
        server: impl Into<String>,
        name: impl Into<String>,
        description: impl Into<String>,
        input_schema: Value,
        visibility: ExternalToolVisibility,
    ) -> Self {
        Self {
            kind: ExternalToolKind::Mcp {
                server: server.into(),
            },
            name: name.into(),
            description: description.into(),
            input_schema,
            permission: ToolPermission::ReadWorkspace,
            visibility,
            execution: ExternalToolExecution::Unavailable,
        }
    }

    pub fn with_static_result(mut self, result: Value) -> Self {
        self.execution = ExternalToolExecution::Static { result };
        self
    }

    pub fn namespace(&self) -> anyhow::Result<String> {
        let (prefix, id) = self.namespace_parts();
        ensure_model_safe_part(id, "external tool namespace")?;
        Ok(format!("{prefix}__{id}"))
    }

    pub fn flattened_name(&self) -> anyhow::Result<String> {
        ensure_model_safe_part(&self.name, "external tool name")?;
        Ok(format!("{}__{}", self.namespace()?, self.name))
    }

    pub fn tool_definition(&self) -> anyhow::Result<Option<ToolDefinition>> {
        if matches!(self.visibility, ExternalToolVisibility::Deferred { .. }) {
            return Ok(None);
        }

        Ok(Some(ToolDefinition {
            name: self.flattened_name()?,
            namespace: Some(self.namespace()?),
            description: self.description.clone(),
            input_schema: self.input_schema.clone(),
            output_schema: None,
            permission: self.permission,
            persistence: ToolPersistence::for_permission(self.permission),
            source: self.source(),
        }))
    }

    pub fn discovery_summary(&self) -> anyhow::Result<ToolDiscoveryItem> {
        let deferred_summary = match &self.visibility {
            ExternalToolVisibility::Immediate => None,
            ExternalToolVisibility::Deferred { summary } => Some(summary.clone()),
        };
        Ok(ToolDiscoveryItem {
            name: self.flattened_name()?,
            namespace: Some(self.namespace()?),
            description: self.description.clone(),
            summary: deferred_summary.unwrap_or_else(|| self.description.clone()),
            permission: self.permission,
            source: self.source(),
            schema_loaded: matches!(self.visibility, ExternalToolVisibility::Immediate),
            deferred: matches!(self.visibility, ExternalToolVisibility::Deferred { .. }),
        })
    }

    pub fn source(&self) -> ToolSource {
        match &self.kind {
            ExternalToolKind::Mcp { server } => ToolSource::Mcp {
                server: server.clone(),
            },
            ExternalToolKind::AppConnector { connector } => ToolSource::AppConnector {
                connector: connector.clone(),
            },
        }
    }

    fn namespace_parts(&self) -> (&'static str, &str) {
        match &self.kind {
            ExternalToolKind::Mcp { server } => ("mcp", server.as_str()),
            ExternalToolKind::AppConnector { connector } => ("connector", connector.as_str()),
        }
    }
}

fn ensure_model_safe_part(value: &str, label: &str) -> anyhow::Result<()> {
    if is_model_safe_part(value) {
        return Ok(());
    }

    anyhow::bail!("{label} must be model-safe");
}

fn is_model_safe_part(value: &str) -> bool {
    !value.is_empty()
        && value.len() <= 64
        && value
            .chars()
            .all(|ch| ch.is_ascii_alphanumeric() || ch == '_' || ch == '-')
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn mcp_tool_names_are_flattened_with_model_safe_namespace() {
        let tool = ExternalToolConfig::mcp(
            "filesystem",
            "read_file",
            "Read a file through MCP.",
            serde_json::json!({ "type": "object" }),
            ExternalToolVisibility::Immediate,
        );

        assert_eq!(tool.flattened_name().unwrap(), "mcp__filesystem__read_file");
        assert_eq!(tool.namespace().unwrap(), "mcp__filesystem");
    }

    #[test]
    fn external_tool_names_reject_invalid_namespace_parts() {
        let tool = ExternalToolConfig::mcp(
            "bad/server",
            "read_file",
            "Read a file through MCP.",
            serde_json::json!({ "type": "object" }),
            ExternalToolVisibility::Immediate,
        );

        let error = tool.flattened_name().unwrap_err().to_string();

        assert!(error.contains("external tool namespace must be model-safe"));
    }

    #[test]
    fn deferred_external_tool_summaries_do_not_require_full_schema() {
        let tool = ExternalToolConfig::mcp(
            "search",
            "expensive_lookup",
            "Search a remote corpus.",
            serde_json::json!({
                "type": "object",
                "properties": {
                    "query": { "type": "string" }
                }
            }),
            ExternalToolVisibility::Deferred {
                summary: "Remote corpus lookup.".into(),
            },
        );

        let summary = tool.discovery_summary().unwrap();

        assert_eq!(summary.name, "mcp__search__expensive_lookup");
        assert_eq!(summary.namespace.as_deref(), Some("mcp__search"));
        assert!(!summary.schema_loaded);
        assert_eq!(summary.summary, "Remote corpus lookup.");
    }
}
