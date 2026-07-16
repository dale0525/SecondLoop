use crate::calendar::{
    ApprovedCalendarMutation, CalendarConnector, CalendarEventContent, CalendarScope,
};
use crate::connector::{
    ConnectorApprovalMode, ConnectorDescriptor, ConnectorHealth, ConnectorToolRisk,
    ConnectorToolSpec, ConnectorTransport, ConnectorTransportCall, ConnectorTransportKind,
};
use crate::credential::CredentialScope;
use async_trait::async_trait;
use chrono::{DateTime, Utc};
use serde::Deserialize;
use serde_json::{Value, json};
use std::collections::BTreeSet;
use std::sync::Arc;

pub const CALENDAR_CONNECTOR_ID: &str = "agentweave-calendar";
pub const CALENDAR_TOOL_NAMES: [&str; 7] = [
    "calendar_event_get",
    "calendar_events_list",
    "calendar_free_busy",
    "calendar_event_create_preview",
    "calendar_event_update_preview",
    "calendar_event_cancel_preview",
    "calendar_event_apply",
];

pub struct CalendarConnectorTransport {
    connector: Arc<dyn CalendarConnector>,
    scope: CredentialScope,
}

impl CalendarConnectorTransport {
    pub fn new(
        connector: Arc<dyn CalendarConnector>,
        scope: CredentialScope,
    ) -> anyhow::Result<Self> {
        scope.validate()?;
        Ok(Self { connector, scope })
    }

    pub fn descriptor(name: impl Into<String>, required_startup: bool) -> ConnectorDescriptor {
        ConnectorDescriptor {
            id: CALENDAR_CONNECTOR_ID.into(),
            name: name.into(),
            version: "0.1.0".into(),
            instructions: Some(
                "Provider-neutral Calendar v1. Preserve exact timezone, recurrence, attendee, conflict, and event-version facts; mutations require an approved immutable preview."
                    .into(),
            ),
            transport: ConnectorTransportKind::LocalHost,
            required_startup,
            account_required: false,
            approval_mode: ConnectorApprovalMode::Writes,
            allowed_tools: BTreeSet::new(),
            denied_tools: BTreeSet::new(),
        }
    }

    fn calendar_scope(
        &self,
        account_id: String,
        trusted_account_id: Option<&str>,
    ) -> anyhow::Result<CalendarScope> {
        validate_text(&account_id, 255, "calendar account id")?;
        if let Some(trusted) = trusted_account_id {
            anyhow::ensure!(
                trusted == account_id,
                "calendar account does not match the trusted connector account"
            );
        }
        Ok(CalendarScope {
            app_id: self.scope.app_id.clone(),
            tenant_id: self.scope.tenant_id.clone(),
            user_id: self.scope.user_id.clone(),
            account_id,
        })
    }
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
struct EventRequest {
    account_id: String,
    event_id: String,
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
struct RangeRequest {
    account_id: String,
    start: DateTime<Utc>,
    end: DateTime<Utc>,
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
struct CreatePreviewRequest {
    account_id: String,
    content: CalendarEventContent,
    idempotency_key: String,
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
struct UpdatePreviewRequest {
    account_id: String,
    event_id: String,
    expected_version: u64,
    content: CalendarEventContent,
    idempotency_key: String,
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
struct CancelPreviewRequest {
    account_id: String,
    event_id: String,
    expected_version: u64,
    idempotency_key: String,
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
struct ApplyRequest {
    account_id: String,
    approval: ApprovedCalendarMutation,
}

#[async_trait]
impl ConnectorTransport for CalendarConnectorTransport {
    async fn start(&self) -> anyhow::Result<()> {
        Ok(())
    }

    async fn list_tools(&self) -> anyhow::Result<Vec<ConnectorToolSpec>> {
        Ok(calendar_tool_specs())
    }

    async fn call(&self, request: ConnectorTransportCall) -> anyhow::Result<Value> {
        let trusted_account = request.account_id.as_deref();
        match request.tool_name.as_str() {
            "calendar_event_get" => {
                let input: EventRequest = serde_json::from_value(request.arguments)?;
                let scope = self.calendar_scope(input.account_id, trusted_account)?;
                serde_json::to_value(self.connector.get_event(&scope, &input.event_id).await?)
                    .map_err(Into::into)
            }
            "calendar_events_list" => {
                let input: RangeRequest = serde_json::from_value(request.arguments)?;
                let scope = self.calendar_scope(input.account_id, trusted_account)?;
                validate_range(input.start, input.end)?;
                serde_json::to_value(
                    self.connector
                        .list_events(&scope, input.start, input.end)
                        .await?,
                )
                .map_err(Into::into)
            }
            "calendar_free_busy" => {
                let input: RangeRequest = serde_json::from_value(request.arguments)?;
                let scope = self.calendar_scope(input.account_id, trusted_account)?;
                validate_range(input.start, input.end)?;
                serde_json::to_value(
                    self.connector
                        .free_busy(&scope, input.start, input.end)
                        .await?,
                )
                .map_err(Into::into)
            }
            "calendar_event_create_preview" => {
                let input: CreatePreviewRequest = serde_json::from_value(request.arguments)?;
                let scope = self.calendar_scope(input.account_id, trusted_account)?;
                serde_json::to_value(
                    self.connector
                        .preview_create(&scope, input.content, input.idempotency_key)
                        .await?,
                )
                .map_err(Into::into)
            }
            "calendar_event_update_preview" => {
                let input: UpdatePreviewRequest = serde_json::from_value(request.arguments)?;
                let scope = self.calendar_scope(input.account_id, trusted_account)?;
                serde_json::to_value(
                    self.connector
                        .preview_update(
                            &scope,
                            &input.event_id,
                            input.expected_version,
                            input.content,
                            input.idempotency_key,
                        )
                        .await?,
                )
                .map_err(Into::into)
            }
            "calendar_event_cancel_preview" => {
                let input: CancelPreviewRequest = serde_json::from_value(request.arguments)?;
                let scope = self.calendar_scope(input.account_id, trusted_account)?;
                serde_json::to_value(
                    self.connector
                        .preview_cancel(
                            &scope,
                            &input.event_id,
                            input.expected_version,
                            input.idempotency_key,
                        )
                        .await?,
                )
                .map_err(Into::into)
            }
            "calendar_event_apply" => {
                let input: ApplyRequest = serde_json::from_value(request.arguments)?;
                let scope = self.calendar_scope(input.account_id, trusted_account)?;
                anyhow::ensure!(
                    request.idempotency_key.is_some(),
                    "calendar mutation requires a trusted idempotency key"
                );
                serde_json::to_value(self.connector.apply(&scope, input.approval).await?)
                    .map_err(Into::into)
            }
            _ => anyhow::bail!("unknown Calendar connector tool"),
        }
    }

    async fn health(&self) -> anyhow::Result<ConnectorHealth> {
        Ok(ConnectorHealth::Ready)
    }

    async fn stop(&self) -> anyhow::Result<()> {
        Ok(())
    }
}

fn calendar_tool_specs() -> Vec<ConnectorToolSpec> {
    vec![
        spec(
            "calendar_event_get",
            "Inspect one authoritative provider event by stable ID.",
            schema(&["accountId", "eventId"]),
            ConnectorToolRisk::SensitiveRead,
            &["calendar.event.read"],
            true,
            false,
        ),
        spec(
            "calendar_events_list",
            "List authoritative events in a bounded UTC range.",
            schema(&["accountId", "start", "end"]),
            ConnectorToolRisk::SensitiveRead,
            &["calendar.event.read"],
            true,
            false,
        ),
        spec(
            "calendar_free_busy",
            "Read authoritative busy intervals in a bounded UTC range.",
            schema(&["accountId", "start", "end"]),
            ConnectorToolRisk::SensitiveRead,
            &["calendar.event.read"],
            true,
            false,
        ),
        spec(
            "calendar_event_create_preview",
            "Preview an exact event creation without mutating the provider calendar.",
            schema(&["accountId", "content", "idempotencyKey"]),
            ConnectorToolRisk::SensitiveRead,
            &["calendar.event.write"],
            false,
            false,
        ),
        spec(
            "calendar_event_update_preview",
            "Preview an exact version-checked event update without mutating the provider calendar.",
            schema(&[
                "accountId",
                "eventId",
                "expectedVersion",
                "content",
                "idempotencyKey",
            ]),
            ConnectorToolRisk::SensitiveRead,
            &["calendar.event.write"],
            false,
            false,
        ),
        spec(
            "calendar_event_cancel_preview",
            "Preview an exact version-checked event cancellation without mutating the provider calendar.",
            schema(&["accountId", "eventId", "expectedVersion", "idempotencyKey"]),
            ConnectorToolRisk::SensitiveRead,
            &["calendar.event.write"],
            false,
            false,
        ),
        spec(
            "calendar_event_apply",
            "Apply exactly one Runtime-approved immutable Calendar preview.",
            schema(&["accountId", "approval"]),
            ConnectorToolRisk::Write,
            &["calendar.event.write"],
            false,
            true,
        ),
    ]
}

fn spec(
    name: &str,
    description: &str,
    input_schema: Value,
    risk: ConnectorToolRisk,
    scopes: &[&str],
    parallel_safe: bool,
    supports_idempotency: bool,
) -> ConnectorToolSpec {
    ConnectorToolSpec {
        name: name.into(),
        description: description.into(),
        input_schema,
        output_schema: None,
        risk,
        required_scopes: scopes.iter().map(|scope| (*scope).into()).collect(),
        parallel_safe,
        supports_idempotency,
    }
}

fn schema(required: &[&str]) -> Value {
    let properties = required
        .iter()
        .map(|name| ((*name).to_string(), property_schema(name)))
        .collect::<serde_json::Map<_, _>>();
    json!({
        "type": "object",
        "properties": properties,
        "required": required,
        "additionalProperties": false
    })
}

fn property_schema(name: &str) -> Value {
    match name {
        "content" | "approval" => json!({"type": "object"}),
        "expectedVersion" => json!({"type": "integer", "minimum": 1}),
        "start" | "end" => json!({"type": "string", "format": "date-time"}),
        _ => json!({"type": "string", "minLength": 1}),
    }
}

fn validate_range(start: DateTime<Utc>, end: DateTime<Utc>) -> anyhow::Result<()> {
    anyhow::ensure!(end > start, "calendar range is invalid");
    anyhow::ensure!(
        end - start <= chrono::Duration::days(366),
        "calendar range exceeds 366 days"
    );
    Ok(())
}

fn validate_text(value: &str, max: usize, name: &str) -> anyhow::Result<()> {
    anyhow::ensure!(!value.trim().is_empty(), "{name} is required");
    anyhow::ensure!(value.len() <= max, "{name} is too long");
    anyhow::ensure!(
        !value.chars().any(char::is_control),
        "{name} contains control characters"
    );
    Ok(())
}

#[cfg(test)]
#[path = "calendar_connector_transport_tests.rs"]
mod tests;
