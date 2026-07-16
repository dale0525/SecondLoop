use async_trait::async_trait;
use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};
use std::collections::{BTreeMap, HashMap};
use std::sync::{Arc, Mutex};
use uuid::Uuid;

#[derive(Clone, Debug, Deserialize, Serialize, PartialEq, Eq, PartialOrd, Ord)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct CalendarScope {
    pub app_id: String,
    pub tenant_id: String,
    pub user_id: String,
    pub account_id: String,
}

#[derive(Clone, Debug, Deserialize, Serialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct CalendarAttendee {
    pub address: String,
    pub display_name: Option<String>,
    pub response: String,
}

#[derive(Clone, Debug, Deserialize, Serialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct CalendarEventContent {
    pub calendar_id: String,
    pub title: String,
    pub description: Option<String>,
    pub start: DateTime<Utc>,
    pub end: DateTime<Utc>,
    pub timezone: String,
    pub location: Option<String>,
    pub attendees: Vec<CalendarAttendee>,
    pub recurrence: Option<String>,
}

impl CalendarEventContent {
    pub fn validate(&self) -> anyhow::Result<()> {
        validate_text(&self.calendar_id, 512, "calendar id")?;
        validate_text(&self.title, 1024, "event title")?;
        anyhow::ensure!(self.end > self.start, "event end must be after start");
        anyhow::ensure!(self.attendees.len() <= 500, "event has too many attendees");
        if let Some(description) = &self.description {
            anyhow::ensure!(
                description.len() <= 64 * 1024,
                "event description is too long"
            );
        }
        validate_text(&self.timezone, 255, "event timezone")?;
        self.timezone.parse::<chrono_tz::Tz>()?;
        if let Some(location) = &self.location {
            validate_text(location, 2048, "event location")?;
        }
        if let Some(recurrence) = &self.recurrence {
            validate_text(recurrence, 16 * 1024, "event recurrence")?;
        }
        for attendee in &self.attendees {
            validate_text(&attendee.address, 512, "attendee address")?;
            validate_text(&attendee.response, 64, "attendee response")?;
            if let Some(display_name) = &attendee.display_name {
                validate_text(display_name, 1024, "attendee display name")?;
            }
        }
        Ok(())
    }
}

#[derive(Clone, Debug, Deserialize, Serialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct CalendarEvent {
    pub id: String,
    pub content: CalendarEventContent,
    pub status: CalendarEventStatus,
    pub version: u64,
    pub provider_id: Option<String>,
    pub updated_at: DateTime<Utc>,
}

#[derive(Clone, Copy, Debug, Deserialize, Serialize, PartialEq, Eq)]
#[serde(rename_all = "snake_case")]
pub enum CalendarEventStatus {
    Confirmed,
    Cancelled,
}

#[derive(Clone, Debug, Deserialize, Serialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct BusyInterval {
    pub start: DateTime<Utc>,
    pub end: DateTime<Utc>,
    pub event_id: Option<String>,
}

#[derive(Clone, Copy, Debug, Deserialize, Serialize, PartialEq, Eq)]
#[serde(rename_all = "snake_case")]
pub enum CalendarMutationKind {
    Create,
    Update,
    Cancel,
}

#[derive(Clone, Debug, Deserialize, Serialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct CalendarMutationPreview {
    pub preview_id: String,
    pub account_id: String,
    pub kind: CalendarMutationKind,
    pub event_id: Option<String>,
    pub expected_version: Option<u64>,
    pub content: Option<CalendarEventContent>,
    pub conflicts: Vec<BusyInterval>,
    pub attendee_visible: bool,
    pub preview_hash: String,
    pub idempotency_key: String,
}

impl CalendarMutationPreview {
    pub fn validate(&self) -> anyhow::Result<()> {
        validate_text(&self.preview_id, 512, "calendar preview id")?;
        validate_text(&self.account_id, 255, "calendar account id")?;
        validate_text(&self.idempotency_key, 512, "calendar idempotency key")?;
        validate_sha256(&self.preview_hash, "calendar preview hash")?;
        anyhow::ensure!(
            self.conflicts.len() <= 500,
            "calendar preview has too many conflicts"
        );
        for conflict in &self.conflicts {
            anyhow::ensure!(
                conflict.end > conflict.start,
                "calendar conflict interval is invalid"
            );
            if let Some(event_id) = &conflict.event_id {
                validate_text(event_id, 512, "calendar conflict event id")?;
            }
        }
        match self.kind {
            CalendarMutationKind::Create => {
                anyhow::ensure!(
                    self.event_id.is_none() && self.expected_version.is_none(),
                    "calendar create preview has an existing event binding"
                );
                self.content
                    .as_ref()
                    .ok_or_else(|| anyhow::anyhow!("calendar create content is required"))?
                    .validate()?;
            }
            CalendarMutationKind::Update => {
                validate_text(
                    self.event_id
                        .as_deref()
                        .ok_or_else(|| anyhow::anyhow!("calendar event id is required"))?,
                    512,
                    "calendar event id",
                )?;
                anyhow::ensure!(
                    self.expected_version.is_some_and(|version| version > 0),
                    "calendar expected version is invalid"
                );
                self.content
                    .as_ref()
                    .ok_or_else(|| anyhow::anyhow!("calendar update content is required"))?
                    .validate()?;
            }
            CalendarMutationKind::Cancel => {
                validate_text(
                    self.event_id
                        .as_deref()
                        .ok_or_else(|| anyhow::anyhow!("calendar event id is required"))?,
                    512,
                    "calendar event id",
                )?;
                anyhow::ensure!(
                    self.expected_version.is_some_and(|version| version > 0),
                    "calendar expected version is invalid"
                );
                anyhow::ensure!(
                    self.content.is_none(),
                    "calendar cancel preview cannot replace event content"
                );
            }
        }
        let expected_attendee_visible = self
            .content
            .as_ref()
            .is_some_and(|content| !content.attendees.is_empty());
        anyhow::ensure!(
            self.attendee_visible == expected_attendee_visible,
            "calendar attendee visibility binding is invalid"
        );
        Ok(())
    }
}

#[derive(Clone, Debug, Deserialize, Serialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct ApprovedCalendarMutation {
    pub preview_id: String,
    pub preview_hash: String,
    pub approval_id: String,
}

#[async_trait]
pub trait CalendarConnector: Send + Sync {
    async fn get_event(
        &self,
        scope: &CalendarScope,
        event_id: &str,
    ) -> anyhow::Result<Option<CalendarEvent>>;
    async fn list_events(
        &self,
        scope: &CalendarScope,
        start: DateTime<Utc>,
        end: DateTime<Utc>,
    ) -> anyhow::Result<Vec<CalendarEvent>>;
    async fn free_busy(
        &self,
        scope: &CalendarScope,
        start: DateTime<Utc>,
        end: DateTime<Utc>,
    ) -> anyhow::Result<Vec<BusyInterval>>;
    async fn preview_create(
        &self,
        scope: &CalendarScope,
        content: CalendarEventContent,
        idempotency_key: String,
    ) -> anyhow::Result<CalendarMutationPreview>;
    async fn preview_update(
        &self,
        scope: &CalendarScope,
        event_id: &str,
        expected_version: u64,
        content: CalendarEventContent,
        idempotency_key: String,
    ) -> anyhow::Result<CalendarMutationPreview>;
    async fn preview_cancel(
        &self,
        scope: &CalendarScope,
        event_id: &str,
        expected_version: u64,
        idempotency_key: String,
    ) -> anyhow::Result<CalendarMutationPreview>;
    async fn apply(
        &self,
        scope: &CalendarScope,
        approval: ApprovedCalendarMutation,
    ) -> anyhow::Result<CalendarEvent>;
}

#[derive(Clone, Default)]
pub struct FakeCalendarConnector {
    state: Arc<Mutex<FakeCalendarState>>,
}

#[derive(Default)]
struct FakeCalendarState {
    events: BTreeMap<(CalendarScope, String), CalendarEvent>,
    previews: HashMap<String, (CalendarScope, CalendarMutationPreview)>,
    results: BTreeMap<(CalendarScope, String), CalendarEvent>,
}

impl FakeCalendarConnector {
    pub fn seed(&self, scope: CalendarScope, event: CalendarEvent) {
        self.state
            .lock()
            .expect("calendar lock poisoned")
            .events
            .insert((scope, event.id.clone()), event);
    }

    fn preview(
        &self,
        scope: &CalendarScope,
        kind: CalendarMutationKind,
        event_id: Option<String>,
        expected_version: Option<u64>,
        content: Option<CalendarEventContent>,
        idempotency_key: String,
    ) -> anyhow::Result<CalendarMutationPreview> {
        anyhow::ensure!(
            !idempotency_key.trim().is_empty(),
            "calendar idempotency key is required"
        );
        if let Some(content) = &content {
            content.validate()?;
        }
        let state = self.state.lock().expect("calendar lock poisoned");
        if let (Some(id), Some(version)) = (&event_id, expected_version) {
            let event = state
                .events
                .get(&(scope.clone(), id.clone()))
                .ok_or_else(|| anyhow::anyhow!("calendar event not found"))?;
            anyhow::ensure!(event.version == version, "calendar event version conflict");
        }
        let conflicts = content
            .as_ref()
            .map(|candidate| {
                state
                    .events
                    .iter()
                    .filter(|((event_scope, _), event)| {
                        event_scope == scope
                            && event.status == CalendarEventStatus::Confirmed
                            && event.content.start < candidate.end
                            && event.content.end > candidate.start
                            && Some(event.id.as_str()) != event_id.as_deref()
                    })
                    .map(|(_, event)| BusyInterval {
                        start: event.content.start,
                        end: event.content.end,
                        event_id: Some(event.id.clone()),
                    })
                    .collect()
            })
            .unwrap_or_default();
        drop(state);
        let preview_id = Uuid::new_v4().to_string();
        let hash_input = serde_json::to_vec(&(
            scope,
            kind,
            &event_id,
            expected_version,
            &content,
            &conflicts,
            &idempotency_key,
        ))?;
        let preview = CalendarMutationPreview {
            preview_id: preview_id.clone(),
            account_id: scope.account_id.clone(),
            kind,
            event_id,
            expected_version,
            attendee_visible: content
                .as_ref()
                .is_some_and(|value| !value.attendees.is_empty()),
            content,
            conflicts,
            preview_hash: hex::encode(Sha256::digest(hash_input)),
            idempotency_key,
        };
        preview.validate()?;
        let mut state = self.state.lock().expect("calendar lock poisoned");
        if let Some((_, existing)) = state.previews.values().find(|(existing_scope, existing)| {
            existing_scope == scope && existing.idempotency_key == preview.idempotency_key
        }) {
            anyhow::ensure!(
                existing.preview_hash == preview.preview_hash,
                "calendar idempotency key conflicts with another preview"
            );
            return Ok(existing.clone());
        }
        state
            .previews
            .insert(preview_id, (scope.clone(), preview.clone()));
        Ok(preview)
    }
}

#[async_trait]
impl CalendarConnector for FakeCalendarConnector {
    async fn get_event(
        &self,
        scope: &CalendarScope,
        event_id: &str,
    ) -> anyhow::Result<Option<CalendarEvent>> {
        validate_text(event_id, 512, "calendar event id")?;
        Ok(self
            .state
            .lock()
            .expect("calendar lock poisoned")
            .events
            .get(&(scope.clone(), event_id.to_string()))
            .cloned())
    }

    async fn list_events(
        &self,
        scope: &CalendarScope,
        start: DateTime<Utc>,
        end: DateTime<Utc>,
    ) -> anyhow::Result<Vec<CalendarEvent>> {
        anyhow::ensure!(end > start, "calendar range is invalid");
        Ok(self
            .state
            .lock()
            .expect("calendar lock poisoned")
            .events
            .iter()
            .filter(|((event_scope, _), event)| {
                event_scope == scope && event.content.start < end && event.content.end > start
            })
            .map(|(_, event)| event.clone())
            .collect::<Vec<_>>())
    }

    async fn free_busy(
        &self,
        scope: &CalendarScope,
        start: DateTime<Utc>,
        end: DateTime<Utc>,
    ) -> anyhow::Result<Vec<BusyInterval>> {
        Ok(self
            .list_events(scope, start, end)
            .await?
            .into_iter()
            .filter(|event| event.status == CalendarEventStatus::Confirmed)
            .map(|event| BusyInterval {
                start: event.content.start,
                end: event.content.end,
                event_id: Some(event.id),
            })
            .collect())
    }

    async fn preview_create(
        &self,
        scope: &CalendarScope,
        content: CalendarEventContent,
        idempotency_key: String,
    ) -> anyhow::Result<CalendarMutationPreview> {
        self.preview(
            scope,
            CalendarMutationKind::Create,
            None,
            None,
            Some(content),
            idempotency_key,
        )
    }

    async fn preview_update(
        &self,
        scope: &CalendarScope,
        event_id: &str,
        expected_version: u64,
        content: CalendarEventContent,
        idempotency_key: String,
    ) -> anyhow::Result<CalendarMutationPreview> {
        self.preview(
            scope,
            CalendarMutationKind::Update,
            Some(event_id.into()),
            Some(expected_version),
            Some(content),
            idempotency_key,
        )
    }

    async fn preview_cancel(
        &self,
        scope: &CalendarScope,
        event_id: &str,
        expected_version: u64,
        idempotency_key: String,
    ) -> anyhow::Result<CalendarMutationPreview> {
        self.preview(
            scope,
            CalendarMutationKind::Cancel,
            Some(event_id.into()),
            Some(expected_version),
            None,
            idempotency_key,
        )
    }

    async fn apply(
        &self,
        scope: &CalendarScope,
        approval: ApprovedCalendarMutation,
    ) -> anyhow::Result<CalendarEvent> {
        anyhow::ensure!(
            !approval.approval_id.trim().is_empty(),
            "calendar approval is required"
        );
        let mut state = self.state.lock().expect("calendar lock poisoned");
        let (preview_scope, preview) = state
            .previews
            .get(&approval.preview_id)
            .cloned()
            .ok_or_else(|| anyhow::anyhow!("calendar preview not found"))?;
        anyhow::ensure!(
            &preview_scope == scope && approval.preview_hash == preview.preview_hash,
            "calendar approval does not match preview"
        );
        let result_key = (scope.clone(), preview.idempotency_key.clone());
        if let Some(existing) = state.results.get(&result_key) {
            return Ok(existing.clone());
        }
        let event = match preview.kind {
            CalendarMutationKind::Create => CalendarEvent {
                id: Uuid::new_v4().to_string(),
                content: preview.content.unwrap(),
                status: CalendarEventStatus::Confirmed,
                version: 1,
                provider_id: None,
                updated_at: Utc::now(),
            },
            CalendarMutationKind::Update => {
                let id = preview.event_id.unwrap();
                let stored = state
                    .events
                    .get_mut(&(scope.clone(), id))
                    .ok_or_else(|| anyhow::anyhow!("calendar event not found"))?;
                anyhow::ensure!(
                    stored.version == preview.expected_version.unwrap(),
                    "calendar event version conflict"
                );
                stored.content = preview.content.unwrap();
                stored.version += 1;
                stored.updated_at = Utc::now();
                stored.clone()
            }
            CalendarMutationKind::Cancel => {
                let id = preview.event_id.unwrap();
                let stored = state
                    .events
                    .get_mut(&(scope.clone(), id))
                    .ok_or_else(|| anyhow::anyhow!("calendar event not found"))?;
                anyhow::ensure!(
                    stored.version == preview.expected_version.unwrap(),
                    "calendar event version conflict"
                );
                stored.status = CalendarEventStatus::Cancelled;
                stored.version += 1;
                stored.updated_at = Utc::now();
                stored.clone()
            }
        };
        state
            .events
            .insert((scope.clone(), event.id.clone()), event.clone());
        state.results.insert(result_key, event.clone());
        Ok(event)
    }
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

fn validate_sha256(value: &str, name: &str) -> anyhow::Result<()> {
    anyhow::ensure!(
        value.len() == 64 && value.bytes().all(|byte| byte.is_ascii_hexdigit()),
        "{name} is invalid"
    );
    Ok(())
}

#[cfg(test)]
#[path = "calendar_tests.rs"]
mod tests;
