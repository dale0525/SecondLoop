use crate::approval::immutable_arguments_hash;
use crate::calendar::{CalendarMutationKind, CalendarMutationPreview};
use crate::calendar_connector_transport::CALENDAR_CONNECTOR_ID;
use crate::foundation_action_envelope::{
    FoundationActionEffect, FoundationActionEnvelope, FoundationActionPreview,
    FoundationActionResource,
};
use serde::{Deserialize, Serialize};
use serde_json::{Value, json};

pub const CALENDAR_ACTION_ENVELOPE_VERSION: u32 = 1;
pub const CALENDAR_CREATE_ACTION_KIND: &str = "calendar.event.create";
pub const CALENDAR_UPDATE_ACTION_KIND: &str = "calendar.event.update";
pub const CALENDAR_CANCEL_ACTION_KIND: &str = "calendar.event.cancel";
pub const CALENDAR_APPLY_OPERATION: &str = "calendar_event_apply";

#[derive(Clone, Debug, Deserialize, Serialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct CanonicalCalendarActionEnvelope {
    pub schema_version: u32,
    pub preview: CalendarMutationPreview,
    pub preview_sha256: String,
}

impl CanonicalCalendarActionEnvelope {
    pub fn from_preview(preview: CalendarMutationPreview) -> anyhow::Result<Self> {
        let preview_sha256 = immutable_arguments_hash(&serde_json::to_value(&preview)?)?;
        let envelope = Self {
            schema_version: CALENDAR_ACTION_ENVELOPE_VERSION,
            preview,
            preview_sha256,
        };
        envelope.validate()?;
        Ok(envelope)
    }

    pub fn validate(&self) -> anyhow::Result<()> {
        anyhow::ensure!(
            self.schema_version == CALENDAR_ACTION_ENVELOPE_VERSION,
            "unsupported canonical Calendar action version"
        );
        self.preview.validate()?;
        anyhow::ensure!(
            self.preview_sha256 == immutable_arguments_hash(&serde_json::to_value(&self.preview)?)?,
            "Calendar preview hash does not match preview"
        );
        Ok(())
    }

    pub fn into_foundation_action(self) -> anyhow::Result<FoundationActionEnvelope> {
        self.validate()?;
        let kind = action_kind(self.preview.kind);
        let (resource_type, resource_id, expected_revision) = match self.preview.kind {
            CalendarMutationKind::Create => (
                "calendar",
                self.preview
                    .content
                    .as_ref()
                    .expect("validated create content")
                    .calendar_id
                    .clone(),
                None,
            ),
            CalendarMutationKind::Update | CalendarMutationKind::Cancel => (
                "event",
                self.preview.event_id.clone().expect("validated event id"),
                self.preview
                    .expected_version
                    .map(|version| version.to_string()),
            ),
        };
        let effect = if self.preview.kind == CalendarMutationKind::Cancel {
            FoundationActionEffect::DestructiveWrite
        } else {
            FoundationActionEffect::ExternalWrite
        };
        let approval_preview = FoundationActionPreview::new(
            calendar_risk_summary(&self.preview),
            calendar_preview_details(&self.preview),
        )?;
        FoundationActionEnvelope::new(
            kind,
            CALENDAR_CONNECTOR_ID,
            CALENDAR_APPLY_OPERATION,
            self.preview.account_id.clone(),
            FoundationActionResource::new(resource_type, resource_id, expected_revision)?,
            effect,
            self.preview.idempotency_key.clone(),
            serde_json::to_value(self)?,
            approval_preview,
        )
    }

    pub fn from_foundation_action(envelope: &FoundationActionEnvelope) -> anyhow::Result<Self> {
        envelope.validate()?;
        anyhow::ensure!(
            is_calendar_action_kind(&envelope.kind)
                && envelope.connector_id == CALENDAR_CONNECTOR_ID
                && envelope.operation == CALENDAR_APPLY_OPERATION,
            "Foundation Action is not a canonical Calendar mutation"
        );
        let action: Self = serde_json::from_value(envelope.payload.clone())?;
        action.validate()?;
        let expected = action.clone().into_foundation_action()?;
        anyhow::ensure!(
            envelope.kind == expected.kind
                && envelope.account_id == expected.account_id
                && envelope.resource == expected.resource
                && envelope.effect == expected.effect
                && envelope.idempotency_key == expected.idempotency_key
                && envelope.preview == expected.preview,
            "canonical Calendar action binding is invalid"
        );
        Ok(action)
    }
}

pub fn is_calendar_action_kind(kind: &str) -> bool {
    matches!(
        kind,
        CALENDAR_CREATE_ACTION_KIND | CALENDAR_UPDATE_ACTION_KIND | CALENDAR_CANCEL_ACTION_KIND
    )
}

fn action_kind(kind: CalendarMutationKind) -> &'static str {
    match kind {
        CalendarMutationKind::Create => CALENDAR_CREATE_ACTION_KIND,
        CalendarMutationKind::Update => CALENDAR_UPDATE_ACTION_KIND,
        CalendarMutationKind::Cancel => CALENDAR_CANCEL_ACTION_KIND,
    }
}

fn calendar_risk_summary(preview: &CalendarMutationPreview) -> String {
    let operation = match preview.kind {
        CalendarMutationKind::Create => "Create",
        CalendarMutationKind::Update => "Update",
        CalendarMutationKind::Cancel => "Cancel",
    };
    let target = preview
        .content
        .as_ref()
        .map(|content| content.title.as_str())
        .or(preview.event_id.as_deref())
        .unwrap_or("calendar event");
    format!(
        "{operation} Calendar event {target:?} in account {}",
        preview.account_id
    )
    .chars()
    .take(1024)
    .collect()
}

fn calendar_preview_details(preview: &CalendarMutationPreview) -> Value {
    json!({
        "kind": preview.kind,
        "eventId": preview.event_id,
        "expectedVersion": preview.expected_version,
        "content": preview.content,
        "conflicts": preview.conflicts,
        "attendeeVisible": preview.attendee_visible,
        "previewHash": preview.preview_hash,
    })
}

#[cfg(test)]
#[path = "calendar_action_envelope_tests.rs"]
mod tests;
