use crate::tasks::{TaskContent, TaskProvider, TaskQuery, TaskScope, TaskStatus};
use crate::tools::{ToolDefinition, ToolPermission, ToolPersistence, ToolSource};
use chrono::{DateTime, Utc};
use serde::Deserialize;
use serde_json::{Value, json};
use std::sync::Arc;

pub const TASK_TOOL_NAMES: [&str; 6] = [
    "task_list",
    "task_get",
    "task_create",
    "task_update",
    "task_set_status",
    "task_delete",
];

#[derive(Clone)]
pub struct TaskToolRuntime {
    provider: Arc<dyn TaskProvider>,
    scope: TaskScope,
}

impl TaskToolRuntime {
    pub fn new(provider: Arc<dyn TaskProvider>, scope: TaskScope) -> anyhow::Result<Self> {
        scope.validate()?;
        Ok(Self { provider, scope })
    }

    pub fn definitions(&self) -> Vec<ToolDefinition> {
        definitions()
    }

    pub fn handles(&self, name: &str) -> bool {
        TASK_TOOL_NAMES.contains(&name)
    }

    pub fn parallel_safe(&self, name: &str) -> bool {
        matches!(name, "task_list" | "task_get")
    }

    pub async fn execute(&self, name: &str, arguments: Value) -> anyhow::Result<Value> {
        let value = match name {
            "task_list" => {
                let arguments: ListArguments = serde_json::from_value(arguments)?;
                serde_json::to_value(
                    self.provider
                        .list(
                            &self.scope,
                            TaskQuery {
                                status: arguments.status,
                                due_after: arguments.due_after,
                                due_before: arguments.due_before,
                                tag: arguments.tag,
                                text: arguments.text,
                                cursor: arguments.cursor,
                                limit: arguments.limit,
                            },
                        )
                        .await?,
                )?
            }
            "task_get" => {
                let arguments: IdArguments = serde_json::from_value(arguments)?;
                serde_json::to_value(self.provider.get(&self.scope, &arguments.id).await?)?
            }
            "task_create" => {
                let arguments: CreateArguments = serde_json::from_value(arguments)?;
                serde_json::to_value(
                    self.provider
                        .create(&self.scope, arguments.content, &arguments.idempotency_key)
                        .await?,
                )?
            }
            "task_update" => {
                let arguments: UpdateArguments = serde_json::from_value(arguments)?;
                serde_json::to_value(
                    self.provider
                        .update(
                            &self.scope,
                            &arguments.id,
                            arguments.expected_version,
                            arguments.content,
                        )
                        .await?,
                )?
            }
            "task_set_status" => {
                let arguments: StatusArguments = serde_json::from_value(arguments)?;
                serde_json::to_value(
                    self.provider
                        .set_status(
                            &self.scope,
                            &arguments.id,
                            arguments.expected_version,
                            arguments.status,
                        )
                        .await?,
                )?
            }
            "task_delete" => {
                let arguments: VersionArguments = serde_json::from_value(arguments)?;
                json!({
                    "deleted": self.provider.delete(
                        &self.scope,
                        &arguments.id,
                        arguments.expected_version,
                    ).await?
                })
            }
            _ => anyhow::bail!("unknown task tool: {name}"),
        };
        Ok(value)
    }
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
struct ListArguments {
    #[serde(default)]
    status: Option<TaskStatus>,
    #[serde(default)]
    due_after: Option<DateTime<Utc>>,
    #[serde(default)]
    due_before: Option<DateTime<Utc>>,
    #[serde(default)]
    tag: Option<String>,
    #[serde(default)]
    text: Option<String>,
    #[serde(default)]
    cursor: Option<String>,
    #[serde(default = "default_limit")]
    limit: usize,
}

#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
struct IdArguments {
    id: String,
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
struct CreateArguments {
    content: TaskContent,
    idempotency_key: String,
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
struct UpdateArguments {
    id: String,
    expected_version: u64,
    content: TaskContent,
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
struct StatusArguments {
    id: String,
    expected_version: u64,
    status: TaskStatus,
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
struct VersionArguments {
    id: String,
    expected_version: u64,
}

fn default_limit() -> usize {
    20
}

fn definitions() -> Vec<ToolDefinition> {
    vec![
        definition(
            "task_list",
            "List confirmed durable tasks inside the trusted App/user scope.",
            list_schema(),
            ToolPermission::ReadSensitive,
        ),
        definition(
            "task_get",
            "Read one confirmed durable task by stable ID.",
            object_schema(json!({ "id": id_schema() }), &["id"]),
            ToolPermission::ReadSensitive,
        ),
        definition(
            "task_create",
            "Create one confirmed durable task with an idempotency key.",
            object_schema(
                json!({
                    "content": content_schema(),
                    "idempotencyKey": {"type": "string", "minLength": 1, "maxLength": 512}
                }),
                &["content", "idempotencyKey"],
            ),
            ToolPermission::PersistData,
        ),
        definition(
            "task_update",
            "Update task content using its current optimistic version.",
            object_schema(
                json!({
                    "id": id_schema(),
                    "expectedVersion": version_schema(),
                    "content": content_schema()
                }),
                &["id", "expectedVersion", "content"],
            ),
            ToolPermission::PersistData,
        ),
        definition(
            "task_set_status",
            "Complete, cancel, or reopen a task using its current optimistic version.",
            object_schema(
                json!({
                    "id": id_schema(),
                    "expectedVersion": version_schema(),
                    "status": {"type": "string", "enum": ["open", "completed", "cancelled"]}
                }),
                &["id", "expectedVersion", "status"],
            ),
            ToolPermission::PersistData,
        ),
        definition(
            "task_delete",
            "Delete one exact task using its current optimistic version.",
            object_schema(
                json!({"id": id_schema(), "expectedVersion": version_schema()}),
                &["id", "expectedVersion"],
            ),
            ToolPermission::DestructiveWrite,
        ),
    ]
}

fn definition(
    name: &str,
    description: &str,
    input_schema: Value,
    permission: ToolPermission,
) -> ToolDefinition {
    ToolDefinition {
        name: name.into(),
        namespace: Some("tasks".into()),
        description: description.into(),
        input_schema,
        output_schema: None,
        permission,
        persistence: ToolPersistence::for_permission(permission),
        source: ToolSource::HostCapability {
            capability: "agentweave.host.tasks/v1".into(),
        },
    }
}

fn list_schema() -> Value {
    object_schema(
        json!({
            "status": {"type": "string", "enum": ["open", "completed", "cancelled"]},
            "dueAfter": {"type": "string", "format": "date-time"},
            "dueBefore": {"type": "string", "format": "date-time"},
            "tag": {"type": "string", "maxLength": 128},
            "text": {"type": "string", "maxLength": 4096},
            "cursor": {"type": "string", "minLength": 1},
            "limit": {"type": "integer", "minimum": 1, "maximum": 100}
        }),
        &[],
    )
}

fn content_schema() -> Value {
    object_schema(
        json!({
            "title": {"type": "string", "minLength": 1, "maxLength": 1024},
            "notes": {"type": ["string", "null"], "maxLength": 65536},
            "dueAt": {"type": ["string", "null"], "format": "date-time"},
            "timezone": {"type": ["string", "null"], "maxLength": 128},
            "recurrence": {"type": ["string", "null"], "maxLength": 4096},
            "priority": {"type": "string", "enum": ["low", "normal", "high", "urgent"]},
            "tags": {
                "type": "array",
                "maxItems": 100,
                "items": {"type": "string", "minLength": 1, "maxLength": 128}
            }
        }),
        &[
            "title",
            "notes",
            "dueAt",
            "timezone",
            "recurrence",
            "priority",
            "tags",
        ],
    )
}

fn object_schema(properties: Value, required: &[&str]) -> Value {
    json!({
        "type": "object",
        "properties": properties,
        "required": required,
        "additionalProperties": false
    })
}

fn id_schema() -> Value {
    json!({"type": "string", "format": "uuid"})
}

fn version_schema() -> Value {
    json!({"type": "integer", "minimum": 1})
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::tasks::FakeTaskProvider;

    #[tokio::test]
    async fn scope_is_host_injected_and_unknown_fields_are_rejected() {
        let runtime = TaskToolRuntime::new(
            Arc::new(FakeTaskProvider::default()),
            TaskScope::new("app", "tenant", "user").unwrap(),
        )
        .unwrap();
        assert!(
            runtime
                .execute("task_list", json!({"scope": {"appId": "other"}}),)
                .await
                .is_err()
        );
    }

    #[test]
    fn definitions_are_stable_and_domain_scoped() {
        let runtime = TaskToolRuntime::new(
            Arc::new(FakeTaskProvider::default()),
            TaskScope::new("app", "tenant", "user").unwrap(),
        )
        .unwrap();
        assert_eq!(runtime.definitions().len(), TASK_TOOL_NAMES.len());
        assert!(runtime.definitions().iter().all(|tool| matches!(
            tool.source,
            ToolSource::HostCapability { ref capability }
            if capability == "agentweave.host.tasks/v1"
        )));
    }
}
