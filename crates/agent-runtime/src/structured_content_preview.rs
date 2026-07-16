use crate::automation::QuietHours;
use crate::oauth::OAuthAuthorizationRequest;
use crate::scheduler::{MisfirePolicy, ScheduleSpec, ScheduledJobStatus};
use crate::structured_content::{StructuredActionBindingRequest, StructuredActionIntent};
use chrono::{DateTime, Utc};
use serde::Deserialize;
use serde_json::{Map, Value, json};

const AGENTWEAVE_CARD_MIME: &str = "application/vnd.agentweave.card+json";
const VERIFIED_SUMMARY: &str =
    "Host-verified preview of the exact action parameters. Review these fields before continuing.";

pub(crate) fn apply_authoritative_action_preview(
    mime_type: &str,
    payload: Value,
    bindings: &[StructuredActionBindingRequest],
    now: DateTime<Utc>,
) -> anyhow::Result<Value> {
    if bindings.is_empty() {
        return Ok(payload);
    }
    let mut payload = payload
        .as_object()
        .cloned()
        .ok_or_else(|| anyhow::anyhow!("structured content payload must be an object"))?;
    let previews = bindings
        .iter()
        .map(|binding| preview_binding(binding, now))
        .collect::<anyhow::Result<Vec<_>>>()?;
    replace_actions(&mut payload, &previews)?;
    let fields = preview_fields(&previews)?;
    if mime_type == AGENTWEAVE_CARD_MIME {
        payload.insert("title".into(), Value::String("Confirm action".into()));
        payload.insert("summary".into(), Value::String(VERIFIED_SUMMARY.into()));
        payload.insert(
            "status".into(),
            json!({"label":"Host verified — confirmation required","tone":"warning"}),
        );
        payload.insert("fields".into(), Value::Array(fields));
    } else if mime_type.starts_with("application/vnd.a2ui.") {
        let mut components = vec![
            json!({"type":"text","style":"heading","text":"Confirm action"}),
            json!({"type":"text","style":"body","text":VERIFIED_SUMMARY}),
            json!({"type":"status","label":"Host verified — confirmation required","tone":"warning"}),
        ];
        components.extend(fields.into_iter().map(|field| {
            json!({
                "type":"field",
                "label":field["label"].clone(),
                "value":field["value"].clone()
            })
        }));
        anyhow::ensure!(
            components.len() <= 64,
            "authoritative action preview is too large"
        );
        payload.insert("components".into(), Value::Array(components));
    }
    Ok(Value::Object(payload))
}

struct ActionPreview {
    action_id: String,
    fields: Vec<(String, String)>,
    label: String,
    style: &'static str,
}

fn preview_binding(
    binding: &StructuredActionBindingRequest,
    now: DateTime<Utc>,
) -> anyhow::Result<ActionPreview> {
    match binding.intent {
        StructuredActionIntent::OauthStart => oauth_start_preview(binding),
        StructuredActionIntent::OauthStatus => oauth_resource_preview(binding, false),
        StructuredActionIntent::OauthCancel => oauth_resource_preview(binding, true),
        StructuredActionIntent::ScheduleCreate => schedule_create_preview(binding, now),
        StructuredActionIntent::ScheduleStatus => schedule_status_preview(binding),
    }
}

fn oauth_start_preview(binding: &StructuredActionBindingRequest) -> anyhow::Result<ActionPreview> {
    let request: OAuthAuthorizationRequest = serde_json::from_value(binding.parameters.clone())?;
    let providers = binding
        .constraints
        .provider_ids
        .iter()
        .cloned()
        .collect::<std::collections::BTreeSet<_>>();
    anyhow::ensure!(
        providers == std::collections::BTreeSet::from([request.provider_id.clone()])
            && binding
                .constraints
                .connector_ids
                .iter()
                .cloned()
                .collect::<std::collections::BTreeSet<_>>()
                == request.connector_ids
            && binding
                .constraints
                .capabilities
                .iter()
                .cloned()
                .collect::<std::collections::BTreeSet<_>>()
                == request.requested_capabilities,
        "OAuth action constraints do not match the requested authorization"
    );
    Ok(ActionPreview {
        action_id: binding.action_id.clone(),
        fields: vec![
            ("Provider".into(), request.provider_id),
            ("Connectors".into(), join_set(request.connector_ids)?),
            (
                "Capabilities".into(),
                join_set(request.requested_capabilities)?,
            ),
        ],
        label: "Continue to sign in".into(),
        style: "primary",
    })
}

fn oauth_resource_preview(
    binding: &StructuredActionBindingRequest,
    cancel: bool,
) -> anyhow::Result<ActionPreview> {
    let parameters: OAuthResourceArguments = serde_json::from_value(binding.parameters.clone())?;
    Ok(ActionPreview {
        action_id: binding.action_id.clone(),
        fields: vec![("Authorization".into(), parameters.authorization_id)],
        label: if cancel {
            "Cancel authorization".into()
        } else {
            "Refresh authorization status".into()
        },
        style: if cancel { "danger" } else { "secondary" },
    })
}

fn schedule_create_preview(
    binding: &StructuredActionBindingRequest,
    now: DateTime<Utc>,
) -> anyhow::Result<ActionPreview> {
    let parameters: CreateScheduleArguments = serde_json::from_value(binding.parameters.clone())?;
    parameters.schedule.validate()?;
    anyhow::ensure!(
        !parameters.notifications.notifications.is_empty()
            && parameters.notifications.notifications.len() <= 5,
        "structured schedule confirmation requires one to five notifications"
    );
    let first_occurrence = parameters
        .schedule
        .next_after(now)?
        .ok_or_else(|| anyhow::anyhow!("schedule has no future occurrence"))?;
    let mut fields = vec![
        ("Schedule name".into(), bounded(parameters.name, 255)?),
        ("Schedule".into(), schedule_label(&parameters.schedule)),
        ("First occurrence".into(), first_occurrence.to_rfc3339()),
        ("Misfire policy".into(), misfire_label(&parameters.misfire)),
    ];
    for (index, notification) in parameters
        .notifications
        .notifications
        .into_iter()
        .enumerate()
    {
        notification.validate()?;
        let prefix = if index == 0 {
            "Notification".to_string()
        } else {
            format!("Notification {}", index + 1)
        };
        fields.extend([
            (format!("{prefix} channel"), notification.channel),
            (format!("{prefix} title"), notification.title),
            (format!("{prefix} body"), notification.body),
            (
                format!("{prefix} not before"),
                notification.not_before.to_rfc3339(),
            ),
        ]);
        if let Some(quiet_hours) = notification.quiet_hours {
            fields.push((
                format!("{prefix} quiet hours"),
                format!(
                    "{} {:02}:{:02}–{:02}:{:02}",
                    quiet_hours.timezone,
                    quiet_hours.start_minute / 60,
                    quiet_hours.start_minute % 60,
                    quiet_hours.end_minute / 60,
                    quiet_hours.end_minute % 60,
                ),
            ));
        }
    }
    Ok(ActionPreview {
        action_id: binding.action_id.clone(),
        fields,
        label: "Create schedule".into(),
        style: "primary",
    })
}

fn schedule_status_preview(
    binding: &StructuredActionBindingRequest,
) -> anyhow::Result<ActionPreview> {
    let parameters: SetScheduleStatusArguments =
        serde_json::from_value(binding.parameters.clone())?;
    let (label, style) = match parameters.status {
        ScheduledJobStatus::Active => ("Resume schedule", "primary"),
        ScheduledJobStatus::Paused => ("Pause schedule", "secondary"),
        ScheduledJobStatus::Completed => ("Complete schedule", "secondary"),
        ScheduledJobStatus::Cancelled => ("Cancel schedule", "danger"),
    };
    Ok(ActionPreview {
        action_id: binding.action_id.clone(),
        fields: vec![
            ("Schedule ID".into(), parameters.id),
            (
                "Expected version".into(),
                parameters.expected_version.to_string(),
            ),
            (
                "New status".into(),
                serde_json::to_value(parameters.status)?
                    .as_str()
                    .unwrap_or("unknown")
                    .to_string(),
            ),
        ],
        label: label.into(),
        style,
    })
}

fn replace_actions(
    payload: &mut Map<String, Value>,
    previews: &[ActionPreview],
) -> anyhow::Result<()> {
    let actions = payload
        .get_mut("actions")
        .and_then(Value::as_array_mut)
        .ok_or_else(|| anyhow::anyhow!("interactive structured content requires actions"))?;
    for action in actions {
        let action_id = action
            .get("id")
            .and_then(Value::as_str)
            .ok_or_else(|| anyhow::anyhow!("structured content action id is invalid"))?;
        let preview = previews
            .iter()
            .find(|preview| preview.action_id == action_id)
            .ok_or_else(|| anyhow::anyhow!("structured content action has no trusted preview"))?;
        *action = json!({
            "id":preview.action_id,
            "label":preview.label,
            "style":preview.style
        });
    }
    Ok(())
}

fn preview_fields(previews: &[ActionPreview]) -> anyhow::Result<Vec<Value>> {
    let multiple = previews.len() > 1;
    let mut fields = Vec::new();
    for preview in previews {
        for (label, value) in &preview.fields {
            fields.push(json!({
                "label":if multiple { format!("{} · {label}", preview.label) } else { label.clone() },
                "value":bounded(value.clone(), 4_096)?
            }));
        }
    }
    anyhow::ensure!(
        fields.len() <= 32,
        "authoritative action preview has too many fields"
    );
    Ok(fields)
}

fn schedule_label(schedule: &ScheduleSpec) -> String {
    match schedule {
        ScheduleSpec::OneShot { at } => format!("One shot at {}", at.to_rfc3339()),
        ScheduleSpec::Interval {
            anchor,
            every_seconds,
        } => format!("Every {every_seconds} seconds from {}", anchor.to_rfc3339()),
        ScheduleSpec::Cron {
            expression,
            timezone,
        } => format!("Cron {expression} ({timezone})"),
        ScheduleSpec::RRule {
            rule,
            timezone,
            start,
        } => format!("RRule {rule} from {} ({timezone})", start.to_rfc3339()),
    }
}

fn misfire_label(policy: &MisfirePolicy) -> String {
    match policy {
        MisfirePolicy::Skip { grace_seconds } => {
            format!("Skip after {grace_seconds} seconds")
        }
        MisfirePolicy::FireOnce => "Fire once".into(),
        MisfirePolicy::CatchUp { max_runs } => format!("Catch up at most {max_runs} runs"),
    }
}

fn join_set(values: std::collections::BTreeSet<String>) -> anyhow::Result<String> {
    bounded(values.into_iter().collect::<Vec<_>>().join(", "), 4_096)
}

fn bounded(value: String, maximum: usize) -> anyhow::Result<String> {
    anyhow::ensure!(
        !value.trim().is_empty() && value.len() <= maximum,
        "authoritative action preview value is invalid"
    );
    Ok(value)
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
struct OAuthResourceArguments {
    authorization_id: String,
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
struct CreateScheduleArguments {
    name: String,
    schedule: ScheduleSpec,
    misfire: MisfirePolicy,
    #[serde(rename = "payload")]
    notifications: DeclarativeScheduledPayload,
    #[serde(rename = "idempotencyKey")]
    _idempotency_key: String,
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
struct DeclarativeScheduledPayload {
    #[serde(rename = "result", default)]
    _result: Value,
    #[serde(default)]
    notifications: Vec<ScheduledNotification>,
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
struct ScheduledNotification {
    channel: String,
    title: String,
    body: String,
    dedupe_key: String,
    not_before: DateTime<Utc>,
    quiet_hours: Option<QuietHours>,
    #[serde(default)]
    data: Value,
}

impl ScheduledNotification {
    fn validate(&self) -> anyhow::Result<()> {
        bounded(self.channel.clone(), 512)?;
        bounded(self.title.clone(), 512)?;
        bounded(self.body.clone(), 4_096)?;
        bounded(self.dedupe_key.clone(), 512)?;
        if let Some(quiet_hours) = &self.quiet_hours {
            quiet_hours.validate()?;
        }
        anyhow::ensure!(
            self.data.as_object().is_some_and(Map::is_empty),
            "structured schedule notification data must be empty"
        );
        Ok(())
    }
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
struct SetScheduleStatusArguments {
    id: String,
    expected_version: i64,
    status: ScheduledJobStatus,
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::structured_content::{StructuredActionConstraints, empty_input_schema};
    use chrono::Duration;

    #[test]
    fn schedule_preview_replaces_model_claims_with_host_parameters() {
        let now = Utc::now();
        let binding = StructuredActionBindingRequest {
            action_id: "confirm".into(),
            intent: StructuredActionIntent::ScheduleCreate,
            idempotency_key: "binding-key".into(),
            expires_at: now + Duration::minutes(10),
            parameters: json!({
                "name":"Actual reminder",
                "schedule":{"kind":"cron","expression":"0 0 9 * * *","timezone":"Asia/Shanghai"},
                "misfire":{"kind":"fire_once"},
                "payload":{"notifications":[{
                    "channel":"desktop","title":"Actual title","body":"Actual body",
                    "dedupeKey":"seed","notBefore":now,"quietHours":null,"data":{}
                }]},
                "idempotencyKey":"job-key"
            }),
            input_schema: empty_input_schema(),
            constraints: StructuredActionConstraints::default(),
        };
        let payload = apply_authoritative_action_preview(
            AGENTWEAVE_CARD_MIME,
            json!({
                "title":"Misleading title",
                "summary":"Runs yearly",
                "fields":[{"label":"Time","value":"Never"}],
                "actions":[{"id":"confirm","label":"Harmless","style":"secondary"}]
            }),
            &[binding],
            now,
        )
        .unwrap();

        assert_eq!(payload["actions"][0]["label"], "Create schedule");
        assert_eq!(payload["fields"][0]["value"], "Actual reminder");
        assert_eq!(payload["fields"][5]["value"], "Actual title");
        assert_eq!(payload["status"]["tone"], "warning");
        assert!(!payload.to_string().contains("Runs yearly"));
        assert!(!payload.to_string().contains("Never"));
    }

    #[test]
    fn oauth_preview_requires_constraints_to_match_parameters() {
        let now = Utc::now();
        let mut binding = StructuredActionBindingRequest {
            action_id: "connect".into(),
            intent: StructuredActionIntent::OauthStart,
            idempotency_key: "oauth-key".into(),
            expires_at: now + Duration::minutes(10),
            parameters: json!({
                "providerId":"workspace",
                "connectorIds":["calendar"],
                "requestedCapabilities":["read"]
            }),
            input_schema: empty_input_schema(),
            constraints: StructuredActionConstraints {
                provider_ids: vec!["other".into()],
                connector_ids: vec!["calendar".into()],
                capabilities: vec!["read".into()],
            },
        };
        let payload = json!({
            "title":"Connect",
            "actions":[{"id":"connect","label":"Connect","style":"primary"}]
        });
        assert!(
            apply_authoritative_action_preview(
                AGENTWEAVE_CARD_MIME,
                payload.clone(),
                &[binding.clone()],
                now,
            )
            .is_err()
        );
        binding.constraints.provider_ids = vec!["workspace".into()];
        let preview =
            apply_authoritative_action_preview(AGENTWEAVE_CARD_MIME, payload, &[binding], now)
                .unwrap();
        assert_eq!(preview["fields"][0]["value"], "workspace");
    }
}
