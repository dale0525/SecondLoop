use crate::calendar_support::normalize_provider_event_title;
use crate::credential_source::ProviderCredentialSource;
use crate::http::{ProviderHttpClient, ProviderHttpRequest};
use agent_runtime::calendar::{
    ApprovedCalendarMutation, BusyInterval, CalendarAttendee, CalendarConnector, CalendarEvent,
    CalendarEventContent, CalendarEventStatus, CalendarMutationKind, CalendarMutationPreview,
    CalendarScope,
};
use agent_runtime::calendar_connector_transport::CALENDAR_CONNECTOR_ID;
use async_trait::async_trait;
use chrono::{DateTime, Utc};
use percent_encoding::{NON_ALPHANUMERIC, utf8_percent_encode};
use reqwest::Method;
use serde::Deserialize;
use serde_json::{Value, json};
use sha2::{Digest, Sha256};
use std::collections::{BTreeMap, BTreeSet};
use std::sync::{Arc, Mutex};
use uuid::Uuid;

const CALENDAR_SCOPE: &str = "https://www.googleapis.com/auth/calendar.events";

pub struct GoogleCalendarConnector {
    http: Arc<dyn ProviderHttpClient>,
    credentials: Arc<dyn ProviderCredentialSource>,
    state: Mutex<GoogleCalendarState>,
}

#[derive(Default)]
struct GoogleCalendarState {
    previews: BTreeMap<String, (CalendarScope, CalendarMutationPreview)>,
    results: BTreeMap<(CalendarScope, String), CalendarEvent>,
}

impl GoogleCalendarConnector {
    pub fn new(
        http: Arc<dyn ProviderHttpClient>,
        credentials: Arc<dyn ProviderCredentialSource>,
    ) -> Self {
        Self {
            http,
            credentials,
            state: Mutex::new(GoogleCalendarState::default()),
        }
    }

    async fn execute(
        &self,
        scope: &CalendarScope,
        request: ProviderHttpRequest,
    ) -> anyhow::Result<crate::http::ProviderHttpResponse> {
        let token = self
            .credentials
            .access_token(
                CALENDAR_CONNECTOR_ID,
                &scope.account_id,
                &BTreeSet::from([CALENDAR_SCOPE.into()]),
            )
            .await?;
        self.http.execute(request, &token).await
    }

    async fn preview(
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
            "idempotency key is required"
        );
        if let Some(content) = &content {
            content.validate()?;
        }
        if let (Some(event_id), Some(expected_version)) = (&event_id, expected_version) {
            let current = self
                .get_event(scope, event_id)
                .await?
                .ok_or_else(|| anyhow::anyhow!("Google Calendar event not found"))?;
            anyhow::ensure!(
                current.version == expected_version,
                "Google Calendar event version conflict"
            );
        }
        let conflicts = match &content {
            Some(content) => self.free_busy(scope, content.start, content.end).await?,
            None => Vec::new(),
        };
        let preview_hash = hex::encode(Sha256::digest(serde_json::to_vec(&(
            scope,
            kind,
            &event_id,
            expected_version,
            &content,
            &conflicts,
            &idempotency_key,
        ))?));
        let mut state = self.state.lock().expect("Google Calendar state poisoned");
        if let Some((_, existing)) = state.previews.values().find(|(existing_scope, existing)| {
            existing_scope == scope && existing.idempotency_key == idempotency_key
        }) {
            anyhow::ensure!(
                existing.preview_hash == preview_hash,
                "Google Calendar idempotency conflict"
            );
            return Ok(existing.clone());
        }
        let preview = CalendarMutationPreview {
            preview_id: Uuid::new_v4().to_string(),
            account_id: scope.account_id.clone(),
            kind,
            event_id,
            expected_version,
            attendee_visible: content
                .as_ref()
                .is_some_and(|value| !value.attendees.is_empty()),
            content,
            conflicts,
            preview_hash,
            idempotency_key,
        };
        preview.validate()?;
        state
            .previews
            .insert(preview.preview_id.clone(), (scope.clone(), preview.clone()));
        Ok(preview)
    }
}

#[async_trait]
impl CalendarConnector for GoogleCalendarConnector {
    async fn get_event(
        &self,
        scope: &CalendarScope,
        event_id: &str,
    ) -> anyhow::Result<Option<CalendarEvent>> {
        let path = format!(
            "/calendar/v3/calendars/primary/events/{}",
            segment(event_id)
        );
        let response = self.execute(scope, ProviderHttpRequest::get(path)).await?;
        if response.status == 404 {
            return Ok(None);
        }
        let event: GoogleEvent = response.json()?;
        Ok(Some(normalize_event("primary", event)?))
    }

    async fn list_events(
        &self,
        scope: &CalendarScope,
        start: DateTime<Utc>,
        end: DateTime<Utc>,
    ) -> anyhow::Result<Vec<CalendarEvent>> {
        validate_range(start, end)?;
        let mut request = ProviderHttpRequest::get("/calendar/v3/calendars/primary/events");
        request.query = vec![
            ("timeMin".into(), start.to_rfc3339()),
            ("timeMax".into(), end.to_rfc3339()),
            ("maxResults".into(), "2500".into()),
            ("singleEvents".into(), "false".into()),
        ];
        let page: GoogleEventPage = self.execute(scope, request).await?.json()?;
        anyhow::ensure!(
            page.next_page_token.is_none(),
            "Google Calendar result is truncated"
        );
        page.items
            .into_iter()
            .map(|event| normalize_event("primary", event))
            .collect()
    }

    async fn free_busy(
        &self,
        scope: &CalendarScope,
        start: DateTime<Utc>,
        end: DateTime<Utc>,
    ) -> anyhow::Result<Vec<BusyInterval>> {
        validate_range(start, end)?;
        let request = ProviderHttpRequest::json(
            Method::POST,
            "/calendar/v3/freeBusy",
            json!({
                "timeMin": start,
                "timeMax": end,
                "items": [{"id": "primary"}]
            }),
        );
        let response: GoogleFreeBusy = self.execute(scope, request).await?.json()?;
        let calendar = response
            .calendars
            .get("primary")
            .ok_or_else(|| anyhow::anyhow!("Google Calendar free-busy result is missing"))?;
        Ok(calendar
            .busy
            .iter()
            .map(|busy| BusyInterval {
                start: busy.start,
                end: busy.end,
                event_id: None,
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
        .await
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
        .await
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
        .await
    }

    async fn apply(
        &self,
        scope: &CalendarScope,
        approval: ApprovedCalendarMutation,
    ) -> anyhow::Result<CalendarEvent> {
        anyhow::ensure!(
            !approval.approval_id.trim().is_empty(),
            "approval is required"
        );
        let preview = {
            let state = self.state.lock().expect("Google Calendar state poisoned");
            let (preview_scope, preview) = state
                .previews
                .get(&approval.preview_id)
                .ok_or_else(|| anyhow::anyhow!("Google Calendar preview not found"))?;
            anyhow::ensure!(
                preview_scope == scope && preview.preview_hash == approval.preview_hash,
                "Google Calendar approval does not match preview"
            );
            if let Some(result) = state
                .results
                .get(&(scope.clone(), preview.idempotency_key.clone()))
            {
                return Ok(result.clone());
            }
            preview.clone()
        };
        let event = match preview.kind {
            CalendarMutationKind::Create => {
                let content = preview.content.as_ref().expect("validated content");
                let path = format!(
                    "/calendar/v3/calendars/{}/events",
                    segment(&content.calendar_id)
                );
                let request =
                    ProviderHttpRequest::json(Method::POST, path, google_event_body(content));
                normalize_event(
                    &content.calendar_id,
                    self.execute(scope, request).await?.json()?,
                )?
            }
            CalendarMutationKind::Update => {
                let content = preview.content.as_ref().expect("validated content");
                let path = format!(
                    "/calendar/v3/calendars/{}/events/{}",
                    segment(&content.calendar_id),
                    segment(preview.event_id.as_deref().expect("validated event id"))
                );
                let request =
                    ProviderHttpRequest::json(Method::PUT, path, google_event_body(content));
                normalize_event(
                    &content.calendar_id,
                    self.execute(scope, request).await?.json()?,
                )?
            }
            CalendarMutationKind::Cancel => {
                let event_id = preview.event_id.as_deref().expect("validated event id");
                let mut event = self
                    .get_event(scope, event_id)
                    .await?
                    .ok_or_else(|| anyhow::anyhow!("Google Calendar event not found"))?;
                let request = ProviderHttpRequest::json(
                    Method::DELETE,
                    format!(
                        "/calendar/v3/calendars/primary/events/{}",
                        segment(event_id)
                    ),
                    Value::Null,
                );
                let response = self.execute(scope, request).await?;
                anyhow::ensure!(
                    (200..300).contains(&response.status),
                    "Google Calendar cancel failed"
                );
                event.status = CalendarEventStatus::Cancelled;
                event.version = event.version.saturating_add(1);
                event.updated_at = Utc::now();
                event
            }
        };
        self.state
            .lock()
            .expect("Google Calendar state poisoned")
            .results
            .insert((scope.clone(), preview.idempotency_key), event.clone());
        Ok(event)
    }
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct GoogleEventPage {
    #[serde(default)]
    items: Vec<GoogleEvent>,
    next_page_token: Option<String>,
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct GoogleEvent {
    id: String,
    etag: String,
    #[serde(default)]
    status: String,
    #[serde(default)]
    summary: String,
    description: Option<String>,
    location: Option<String>,
    start: GoogleEventTime,
    end: GoogleEventTime,
    #[serde(default)]
    attendees: Vec<GoogleAttendee>,
    recurrence: Option<Vec<String>>,
    updated: DateTime<Utc>,
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct GoogleEventTime {
    date_time: Option<DateTime<Utc>>,
    time_zone: Option<String>,
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct GoogleAttendee {
    email: String,
    display_name: Option<String>,
    #[serde(default = "needs_action")]
    response_status: String,
}

#[derive(Deserialize)]
struct GoogleFreeBusy {
    calendars: BTreeMap<String, GoogleBusyCalendar>,
}

#[derive(Deserialize)]
struct GoogleBusyCalendar {
    #[serde(default)]
    busy: Vec<GoogleBusy>,
}

#[derive(Deserialize)]
struct GoogleBusy {
    start: DateTime<Utc>,
    end: DateTime<Utc>,
}

fn normalize_event(calendar_id: &str, event: GoogleEvent) -> anyhow::Result<CalendarEvent> {
    let start = event
        .start
        .date_time
        .ok_or_else(|| anyhow::anyhow!("all-day Google events are unsupported"))?;
    let end = event
        .end
        .date_time
        .ok_or_else(|| anyhow::anyhow!("all-day Google events are unsupported"))?;
    let timezone = event
        .start
        .time_zone
        .or(event.end.time_zone)
        .unwrap_or_else(|| "UTC".into());
    let content = CalendarEventContent {
        calendar_id: calendar_id.into(),
        title: normalize_provider_event_title(event.summary),
        description: event.description,
        start,
        end,
        timezone,
        location: event.location,
        attendees: event
            .attendees
            .into_iter()
            .map(|attendee| CalendarAttendee {
                address: attendee.email,
                display_name: attendee.display_name,
                response: attendee.response_status,
            })
            .collect(),
        recurrence: event.recurrence.map(|values| values.join("\n")),
    };
    content.validate()?;
    Ok(CalendarEvent {
        id: event.id.clone(),
        content,
        status: if event.status == "cancelled" {
            CalendarEventStatus::Cancelled
        } else {
            CalendarEventStatus::Confirmed
        },
        version: etag_version(&event.etag),
        provider_id: Some(event.id),
        updated_at: event.updated,
    })
}

fn google_event_body(content: &CalendarEventContent) -> Value {
    json!({
        "summary": content.title,
        "description": content.description,
        "location": content.location,
        "start": {"dateTime": content.start, "timeZone": content.timezone},
        "end": {"dateTime": content.end, "timeZone": content.timezone},
        "attendees": content.attendees.iter().map(|attendee| json!({
            "email": attendee.address,
            "displayName": attendee.display_name,
            "responseStatus": attendee.response,
        })).collect::<Vec<_>>(),
        "recurrence": content.recurrence.as_ref().map(|value| value.lines().collect::<Vec<_>>()),
    })
}

fn etag_version(etag: &str) -> u64 {
    let digest = Sha256::digest(etag.as_bytes());
    u64::from_be_bytes(digest[..8].try_into().expect("SHA-256 prefix")) | 1
}

fn validate_range(start: DateTime<Utc>, end: DateTime<Utc>) -> anyhow::Result<()> {
    anyhow::ensure!(end > start, "calendar range is invalid");
    anyhow::ensure!(
        end - start <= chrono::Duration::days(366),
        "calendar range exceeds limit"
    );
    Ok(())
}

fn segment(value: &str) -> String {
    utf8_percent_encode(value, NON_ALPHANUMERIC).to_string()
}

fn needs_action() -> String {
    "needsAction".into()
}

#[cfg(test)]
#[path = "google_calendar_tests.rs"]
mod tests;
