use crate::automation::{
    NotificationRequest, NotificationScope, NotificationStatus, NotificationStore, QuietHours,
};
use crate::scheduler::{
    MisfirePolicy, ScheduleScope, ScheduleSpec, ScheduledJobRequest, ScheduledJobStatus,
    SchedulerStore,
};
use crate::storage::Storage;
use crate::tools::{ToolDefinition, ToolPermission, ToolSource};
use chrono::{DateTime, Utc};
use serde::Deserialize;
use serde_json::{Value, json};

pub const AUTOMATION_TOOL_NAMES: [&str; 8] = [
    "schedule_list",
    "schedule_get",
    "schedule_create",
    "schedule_set_status",
    "notification_list",
    "notification_get",
    "notification_enqueue",
    "notification_cancel",
];

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct AutomationScope {
    pub app_id: String,
    pub tenant_id: String,
    pub user_id: String,
}

impl AutomationScope {
    pub fn new(app_id: &str, tenant_id: &str, user_id: &str) -> anyhow::Result<Self> {
        for value in [app_id, tenant_id, user_id] {
            anyhow::ensure!(!value.trim().is_empty(), "automation scope is required");
            anyhow::ensure!(value.len() <= 255, "automation scope is too long");
        }
        Ok(Self {
            app_id: app_id.into(),
            tenant_id: tenant_id.into(),
            user_id: user_id.into(),
        })
    }

    fn notification(&self) -> NotificationScope<'_> {
        NotificationScope {
            app_id: &self.app_id,
            tenant_id: &self.tenant_id,
            user_id: &self.user_id,
        }
    }
}

#[derive(Clone)]
pub struct AutomationToolRuntime {
    scheduler: SchedulerStore,
    notifications: NotificationStore,
    scope: AutomationScope,
}

impl AutomationToolRuntime {
    pub async fn from_storage(storage: &Storage, scope: AutomationScope) -> anyhow::Result<Self> {
        Ok(Self {
            scheduler: SchedulerStore::from_storage(storage).await?,
            notifications: NotificationStore::from_storage(storage).await?,
            scope,
        })
    }

    pub fn definitions(&self) -> Vec<ToolDefinition> {
        definitions()
    }

    pub fn handles(&self, name: &str) -> bool {
        AUTOMATION_TOOL_NAMES.contains(&name)
    }

    pub fn parallel_safe(&self, name: &str) -> bool {
        matches!(
            name,
            "schedule_list" | "schedule_get" | "notification_list" | "notification_get"
        )
    }

    pub async fn execute(&self, name: &str, arguments: Value) -> anyhow::Result<Value> {
        match name {
            "schedule_list" => self.schedule_list(arguments).await,
            "schedule_get" => self.schedule_get(arguments).await,
            "schedule_create" => self.schedule_create(arguments).await,
            "schedule_set_status" => self.schedule_set_status(arguments).await,
            "notification_list" => self.notification_list(arguments).await,
            "notification_get" => self.notification_get(arguments).await,
            "notification_enqueue" => self.notification_enqueue(arguments).await,
            "notification_cancel" => self.notification_cancel(arguments).await,
            _ => anyhow::bail!("unknown automation tool: {name}"),
        }
    }

    async fn schedule_list(&self, arguments: Value) -> anyhow::Result<Value> {
        let arguments: ListArguments = serde_json::from_value(arguments)?;
        serde_json::to_value(
            self.scheduler
                .list_jobs(
                    &self.scope.app_id,
                    &self.scope.tenant_id,
                    &self.scope.user_id,
                    arguments.limit,
                )
                .await?,
        )
        .map_err(Into::into)
    }

    async fn schedule_get(&self, arguments: Value) -> anyhow::Result<Value> {
        let arguments: IdArguments = serde_json::from_value(arguments)?;
        serde_json::to_value(
            self.scheduler
                .get_job_for_scope(
                    &self.scope.app_id,
                    &self.scope.tenant_id,
                    &self.scope.user_id,
                    &arguments.id,
                )
                .await?,
        )
        .map_err(Into::into)
    }

    async fn schedule_create(&self, arguments: Value) -> anyhow::Result<Value> {
        let arguments: CreateScheduleArguments = serde_json::from_value(arguments)?;
        serde_json::to_value(
            self.scheduler
                .create_job_idempotent(
                    ScheduledJobRequest {
                        app_id: self.scope.app_id.clone(),
                        tenant_id: self.scope.tenant_id.clone(),
                        user_id: self.scope.user_id.clone(),
                        name: arguments.name,
                        schedule: arguments.schedule,
                        misfire: arguments.misfire,
                        payload: arguments.payload,
                    },
                    &arguments.idempotency_key,
                    Utc::now(),
                )
                .await?,
        )
        .map_err(Into::into)
    }

    async fn schedule_set_status(&self, arguments: Value) -> anyhow::Result<Value> {
        let arguments: SetScheduleStatusArguments = serde_json::from_value(arguments)?;
        serde_json::to_value(
            self.scheduler
                .set_status_for_scope(
                    ScheduleScope {
                        app_id: &self.scope.app_id,
                        tenant_id: &self.scope.tenant_id,
                        user_id: &self.scope.user_id,
                    },
                    &arguments.id,
                    arguments.expected_version,
                    arguments.status,
                    Utc::now(),
                )
                .await?,
        )
        .map_err(Into::into)
    }

    async fn notification_list(&self, arguments: Value) -> anyhow::Result<Value> {
        let arguments: NotificationListArguments = serde_json::from_value(arguments)?;
        serde_json::to_value(
            self.notifications
                .list_for_scope(self.scope.notification(), arguments.status, arguments.limit)
                .await?,
        )
        .map_err(Into::into)
    }

    async fn notification_get(&self, arguments: Value) -> anyhow::Result<Value> {
        let arguments: IdArguments = serde_json::from_value(arguments)?;
        serde_json::to_value(
            self.notifications
                .get_for_scope(self.scope.notification(), &arguments.id)
                .await?,
        )
        .map_err(Into::into)
    }

    async fn notification_enqueue(&self, arguments: Value) -> anyhow::Result<Value> {
        let arguments: EnqueueNotificationArguments = serde_json::from_value(arguments)?;
        serde_json::to_value(
            self.notifications
                .enqueue(
                    NotificationRequest {
                        app_id: self.scope.app_id.clone(),
                        tenant_id: self.scope.tenant_id.clone(),
                        user_id: self.scope.user_id.clone(),
                        channel: arguments.channel,
                        title: arguments.title,
                        body: arguments.body,
                        dedupe_key: arguments.dedupe_key,
                        not_before: arguments.not_before,
                        quiet_hours: arguments.quiet_hours,
                        data: arguments.data,
                    },
                    Utc::now(),
                )
                .await?,
        )
        .map_err(Into::into)
    }

    async fn notification_cancel(&self, arguments: Value) -> anyhow::Result<Value> {
        let arguments: IdArguments = serde_json::from_value(arguments)?;
        serde_json::to_value(
            self.notifications
                .cancel_for_scope(self.scope.notification(), &arguments.id, Utc::now())
                .await?,
        )
        .map_err(Into::into)
    }
}

#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
struct IdArguments {
    id: String,
}

#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
struct ListArguments {
    #[serde(default = "default_limit")]
    limit: usize,
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
struct CreateScheduleArguments {
    name: String,
    schedule: ScheduleSpec,
    misfire: MisfirePolicy,
    #[serde(default)]
    payload: Value,
    idempotency_key: String,
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
struct SetScheduleStatusArguments {
    id: String,
    expected_version: i64,
    status: ScheduledJobStatus,
}

#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
struct NotificationListArguments {
    #[serde(default)]
    status: Option<NotificationStatus>,
    #[serde(default = "default_limit")]
    limit: usize,
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
struct EnqueueNotificationArguments {
    channel: String,
    title: String,
    body: String,
    dedupe_key: String,
    not_before: DateTime<Utc>,
    #[serde(default)]
    quiet_hours: Option<QuietHours>,
    #[serde(default)]
    data: Value,
}

fn default_limit() -> usize {
    25
}

fn definitions() -> Vec<ToolDefinition> {
    vec![
        definition(
            "schedule_list",
            "List durable schedules in the trusted App/user scope.",
            json!({"type":"object","properties":{"limit":{"type":"integer","minimum":1,"maximum":100}},"additionalProperties":false}),
            ToolPermission::ReadSensitive,
        ),
        definition(
            "schedule_get",
            "Read one durable schedule by stable ID.",
            id_schema(),
            ToolPermission::ReadSensitive,
        ),
        definition(
            "schedule_create",
            "Create one durable schedule with an idempotency key.",
            schedule_create_schema(),
            ToolPermission::PersistData,
        ),
        definition(
            "schedule_set_status",
            "Pause, resume, complete, or cancel a schedule with its current version.",
            json!({"type":"object","properties":{"id":{"type":"string","format":"uuid"},"expectedVersion":{"type":"integer","minimum":1},"status":{"type":"string","enum":["active","paused","completed","cancelled"]}},"required":["id","expectedVersion","status"],"additionalProperties":false}),
            ToolPermission::PersistData,
        ),
        definition(
            "notification_list",
            "List queued and delivered notifications in the trusted App/user scope.",
            json!({"type":"object","properties":{"status":{"type":"string","enum":["pending","delivering","delivered","failed","uncertain","cancelled"]},"limit":{"type":"integer","minimum":1,"maximum":100}},"additionalProperties":false}),
            ToolPermission::ReadSensitive,
        ),
        definition(
            "notification_get",
            "Read one notification delivery record by stable ID.",
            id_schema(),
            ToolPermission::ReadSensitive,
        ),
        definition(
            "notification_enqueue",
            "Queue one host notification using a stable deduplication key.",
            notification_enqueue_schema(),
            ToolPermission::ExternalWrite,
        ),
        definition(
            "notification_cancel",
            "Cancel a notification before delivery begins.",
            id_schema(),
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
        namespace: Some("automation".into()),
        description: description.into(),
        input_schema,
        output_schema: None,
        permission,
        source: ToolSource::HostCapability {
            capability: "agentweave.host.automation/v1".into(),
        },
    }
}

fn id_schema() -> Value {
    json!({"type":"object","properties":{"id":{"type":"string","format":"uuid"}},"required":["id"],"additionalProperties":false})
}

fn schedule_create_schema() -> Value {
    json!({
        "type":"object",
        "properties":{
            "name":{"type":"string","minLength":1,"maxLength":255},
            "schedule":{"type":"object"},
            "misfire":{"type":"object"},
            "payload":{},
            "idempotencyKey":{"type":"string","minLength":1,"maxLength":512}
        },
        "required":["name","schedule","misfire","idempotencyKey"],
        "additionalProperties":false
    })
}

fn notification_enqueue_schema() -> Value {
    json!({
        "type":"object",
        "properties":{
            "channel":{"type":"string","minLength":1,"maxLength":512},
            "title":{"type":"string","minLength":1,"maxLength":512},
            "body":{"type":"string","maxLength":65536},
            "dedupeKey":{"type":"string","minLength":1,"maxLength":512},
            "notBefore":{"type":"string","format":"date-time"},
            "quietHours":{"type":["object","null"]},
            "data":{}
        },
        "required":["channel","title","body","dedupeKey","notBefore"],
        "additionalProperties":false
    })
}

#[cfg(test)]
#[path = "automation_tools_tests.rs"]
mod tests;
