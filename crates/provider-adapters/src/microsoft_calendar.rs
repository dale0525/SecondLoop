use crate::calendar_support::normalize_provider_event_title;
use crate::credential_source::ProviderCredentialSource;
use crate::http::{ProviderHttpClient, ProviderHttpRequest, ProviderHttpResponse};
use agent_runtime::calendar::{
    ApprovedCalendarMutation, BusyInterval, CalendarAttendee, CalendarConnector, CalendarEvent,
    CalendarEventContent, CalendarEventStatus, CalendarMutationKind, CalendarMutationPreview,
    CalendarScope,
};
use agent_runtime::calendar_connector_transport::CALENDAR_CONNECTOR_ID;
use async_trait::async_trait;
use chrono::{DateTime, LocalResult, NaiveDateTime, TimeZone, Utc};
use percent_encoding::{NON_ALPHANUMERIC, utf8_percent_encode};
use reqwest::Method;
use serde::Deserialize;
use serde_json::{Value, json};
use sha2::{Digest, Sha256};
use std::collections::{BTreeMap, BTreeSet};
use std::sync::{Arc, Mutex};
use uuid::Uuid;

const CALENDAR_SCOPE: &str = "Calendars.ReadWrite";
const UTC_PREFERENCE: &str = "outlook.timezone=\"UTC\"";

pub struct MicrosoftCalendarConnector {
    http: Arc<dyn ProviderHttpClient>,
    credentials: Arc<dyn ProviderCredentialSource>,
    schedule_address: String,
    state: Mutex<MicrosoftCalendarState>,
}

#[derive(Default)]
struct MicrosoftCalendarState {
    previews: BTreeMap<String, (CalendarScope, CalendarMutationPreview)>,
    results: BTreeMap<(CalendarScope, String), CalendarEvent>,
}

impl MicrosoftCalendarConnector {
    pub fn new(
        http: Arc<dyn ProviderHttpClient>,
        credentials: Arc<dyn ProviderCredentialSource>,
        schedule_address: impl Into<String>,
    ) -> anyhow::Result<Self> {
        let schedule_address = schedule_address.into();
        anyhow::ensure!(
            !schedule_address.trim().is_empty() && schedule_address.len() <= 512,
            "Microsoft schedule address is invalid"
        );
        Ok(Self {
            http,
            credentials,
            schedule_address,
            state: Mutex::new(MicrosoftCalendarState::default()),
        })
    }

    async fn execute(
        &self,
        scope: &CalendarScope,
        request: ProviderHttpRequest,
    ) -> anyhow::Result<ProviderHttpResponse> {
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

    async fn graph_event(
        &self,
        scope: &CalendarScope,
        event_id: &str,
    ) -> anyhow::Result<Option<GraphEvent>> {
        let mut request =
            ProviderHttpRequest::get(format!("/v1.0/me/events/{}", segment(event_id)));
        prefer_utc(&mut request);
        let response = self.execute(scope, request).await?;
        if response.status == 404 {
            return Ok(None);
        }
        response.json().map(Some)
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
            anyhow::ensure!(
                content.calendar_id == "primary",
                "Microsoft Calendar v1 only supports the primary calendar"
            );
            validate_recurrence(content.recurrence.as_deref())?;
        }
        if let (Some(event_id), Some(expected_version)) = (&event_id, expected_version) {
            let current = self
                .get_event(scope, event_id)
                .await?
                .ok_or_else(|| anyhow::anyhow!("Microsoft Calendar event not found"))?;
            anyhow::ensure!(
                current.version == expected_version,
                "Microsoft Calendar event version conflict"
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
        let mut state = self
            .state
            .lock()
            .expect("Microsoft Calendar state poisoned");
        if let Some((_, existing)) = state.previews.values().find(|(existing_scope, existing)| {
            existing_scope == scope && existing.idempotency_key == idempotency_key
        }) {
            anyhow::ensure!(
                existing.preview_hash == preview_hash,
                "Microsoft Calendar idempotency conflict"
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
impl CalendarConnector for MicrosoftCalendarConnector {
    async fn get_event(
        &self,
        scope: &CalendarScope,
        event_id: &str,
    ) -> anyhow::Result<Option<CalendarEvent>> {
        self.graph_event(scope, event_id)
            .await?
            .map(normalize_event)
            .transpose()
    }

    async fn list_events(
        &self,
        scope: &CalendarScope,
        start: DateTime<Utc>,
        end: DateTime<Utc>,
    ) -> anyhow::Result<Vec<CalendarEvent>> {
        validate_range(start, end)?;
        let mut request = ProviderHttpRequest::get("/v1.0/me/calendarView");
        request.query = vec![
            ("startDateTime".into(), start.to_rfc3339()),
            ("endDateTime".into(), end.to_rfc3339()),
            ("$top".into(), "1000".into()),
        ];
        prefer_utc(&mut request);
        let page: GraphEventPage = self.execute(scope, request).await?.json()?;
        anyhow::ensure!(
            page.next_link.is_none(),
            "Microsoft Calendar result is truncated"
        );
        page.value.into_iter().map(normalize_event).collect()
    }

    async fn free_busy(
        &self,
        scope: &CalendarScope,
        start: DateTime<Utc>,
        end: DateTime<Utc>,
    ) -> anyhow::Result<Vec<BusyInterval>> {
        validate_range(start, end)?;
        let mut request = ProviderHttpRequest::json(
            Method::POST,
            "/v1.0/me/calendar/getSchedule",
            json!({
                "schedules": [self.schedule_address],
                "startTime": graph_utc_time(start),
                "endTime": graph_utc_time(end),
                "availabilityViewInterval": 30
            }),
        );
        prefer_utc(&mut request);
        let response: GraphScheduleResponse = self.execute(scope, request).await?.json()?;
        anyhow::ensure!(
            response.value.len() == 1,
            "Microsoft Calendar schedule result is ambiguous"
        );
        response
            .value
            .into_iter()
            .next()
            .expect("checked schedule result")
            .schedule_items
            .into_iter()
            .filter(|item| item.status != "free")
            .map(|item| {
                let start = parse_graph_time(&item.start)?;
                let end = parse_graph_time(&item.end)?;
                anyhow::ensure!(end > start, "Microsoft busy interval is invalid");
                Ok(BusyInterval {
                    start,
                    end,
                    event_id: None,
                })
            })
            .collect()
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
            let state = self
                .state
                .lock()
                .expect("Microsoft Calendar state poisoned");
            let (preview_scope, preview) = state
                .previews
                .get(&approval.preview_id)
                .ok_or_else(|| anyhow::anyhow!("Microsoft Calendar preview not found"))?;
            anyhow::ensure!(
                preview_scope == scope && preview.preview_hash == approval.preview_hash,
                "Microsoft Calendar approval does not match preview"
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
                let request = ProviderHttpRequest::json(
                    Method::POST,
                    "/v1.0/me/events",
                    graph_event_body(content, Some(&preview.idempotency_key))?,
                );
                normalize_event(self.execute(scope, request).await?.json()?)?
            }
            CalendarMutationKind::Update => {
                let event_id = preview.event_id.as_deref().expect("validated event id");
                let current = self
                    .graph_event(scope, event_id)
                    .await?
                    .ok_or_else(|| anyhow::anyhow!("Microsoft Calendar event not found"))?;
                anyhow::ensure!(
                    event_version(&current)?
                        == preview.expected_version.expect("validated version"),
                    "Microsoft Calendar event version conflict"
                );
                let mut request = ProviderHttpRequest::json(
                    Method::PATCH,
                    format!("/v1.0/me/events/{}", segment(event_id)),
                    graph_event_body(preview.content.as_ref().expect("validated content"), None)?,
                );
                request
                    .headers
                    .insert("If-Match".into(), event_etag(&current)?.into());
                normalize_event(self.execute(scope, request).await?.json()?)?
            }
            CalendarMutationKind::Cancel => {
                let event_id = preview.event_id.as_deref().expect("validated event id");
                let current = self
                    .graph_event(scope, event_id)
                    .await?
                    .ok_or_else(|| anyhow::anyhow!("Microsoft Calendar event not found"))?;
                anyhow::ensure!(
                    event_version(&current)?
                        == preview.expected_version.expect("validated version"),
                    "Microsoft Calendar event version conflict"
                );
                let etag = event_etag(&current)?.to_string();
                let mut event = normalize_event(current)?;
                let mut request = ProviderHttpRequest::json(
                    Method::DELETE,
                    format!("/v1.0/me/events/{}", segment(event_id)),
                    Value::Null,
                );
                request.headers.insert("If-Match".into(), etag);
                let response = self.execute(scope, request).await?;
                anyhow::ensure!(
                    (200..300).contains(&response.status),
                    "Microsoft Calendar cancel failed"
                );
                event.status = CalendarEventStatus::Cancelled;
                event.version = event.version.saturating_add(1);
                event.updated_at = Utc::now();
                event
            }
        };
        self.state
            .lock()
            .expect("Microsoft Calendar state poisoned")
            .results
            .insert((scope.clone(), preview.idempotency_key), event.clone());
        Ok(event)
    }
}

#[derive(Deserialize)]
struct GraphEventPage {
    #[serde(default)]
    value: Vec<GraphEvent>,
    #[serde(rename = "@odata.nextLink")]
    next_link: Option<String>,
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct GraphEvent {
    id: String,
    #[serde(rename = "@odata.etag")]
    etag: Option<String>,
    #[serde(default)]
    subject: String,
    body: Option<GraphBody>,
    start: GraphDateTime,
    end: GraphDateTime,
    location: Option<GraphLocation>,
    #[serde(default)]
    attendees: Vec<GraphAttendee>,
    recurrence: Option<Value>,
    #[serde(default)]
    is_cancelled: bool,
    original_start_time_zone: Option<String>,
    last_modified_date_time: DateTime<Utc>,
}

#[derive(Deserialize)]
struct GraphBody {
    content: String,
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct GraphDateTime {
    date_time: String,
    time_zone: String,
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct GraphLocation {
    display_name: Option<String>,
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct GraphAttendee {
    email_address: GraphEmailAddress,
    status: Option<GraphResponseStatus>,
}

#[derive(Deserialize)]
struct GraphEmailAddress {
    address: String,
    name: Option<String>,
}

#[derive(Deserialize)]
struct GraphResponseStatus {
    response: String,
}

#[derive(Deserialize)]
struct GraphScheduleResponse {
    value: Vec<GraphSchedule>,
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct GraphSchedule {
    #[serde(default)]
    schedule_items: Vec<GraphScheduleItem>,
}

#[derive(Deserialize)]
struct GraphScheduleItem {
    status: String,
    start: GraphDateTime,
    end: GraphDateTime,
}

fn normalize_event(event: GraphEvent) -> anyhow::Result<CalendarEvent> {
    let version = event_version(&event)?;
    let start = parse_graph_time(&event.start)?;
    let end = parse_graph_time(&event.end)?;
    let timezone = event
        .original_start_time_zone
        .unwrap_or_else(|| event.start.time_zone.clone());
    timezone
        .parse::<chrono_tz::Tz>()
        .map_err(|_| anyhow::anyhow!("Microsoft Calendar event timezone is not IANA-compatible"))?;
    let recurrence = event
        .recurrence
        .map(|value| serde_json::to_string(&value))
        .transpose()?;
    let content = CalendarEventContent {
        calendar_id: "primary".into(),
        title: normalize_provider_event_title(event.subject),
        description: event.body.map(|body| body.content),
        start,
        end,
        timezone,
        location: event.location.and_then(|value| value.display_name),
        attendees: event
            .attendees
            .into_iter()
            .map(|attendee| CalendarAttendee {
                address: attendee.email_address.address,
                display_name: attendee.email_address.name,
                response: attendee
                    .status
                    .map(|status| status.response)
                    .unwrap_or_else(|| "none".into()),
            })
            .collect(),
        recurrence,
    };
    content.validate()?;
    Ok(CalendarEvent {
        id: event.id.clone(),
        content,
        status: if event.is_cancelled {
            CalendarEventStatus::Cancelled
        } else {
            CalendarEventStatus::Confirmed
        },
        version,
        provider_id: Some(event.id),
        updated_at: event.last_modified_date_time,
    })
}

fn graph_event_body(
    content: &CalendarEventContent,
    idempotency_key: Option<&str>,
) -> anyhow::Result<Value> {
    content.validate()?;
    let recurrence = content
        .recurrence
        .as_deref()
        .map(serde_json::from_str::<Value>)
        .transpose()?;
    if let Some(value) = &recurrence {
        anyhow::ensure!(
            value.is_object(),
            "Microsoft recurrence must be a JSON object"
        );
    }
    let mut body = json!({
        "subject": content.title,
        "body": {"contentType": "text", "content": content.description.as_deref().unwrap_or_default()},
        "start": graph_local_time(content.start, &content.timezone)?,
        "end": graph_local_time(content.end, &content.timezone)?,
        "location": {"displayName": content.location.as_deref().unwrap_or_default()},
        "attendees": content.attendees.iter().map(|attendee| json!({
            "emailAddress": {
                "address": attendee.address,
                "name": attendee.display_name,
            },
            "type": "required",
        })).collect::<Vec<_>>(),
        "recurrence": recurrence,
    });
    if let Some(key) = idempotency_key {
        body.as_object_mut()
            .expect("event body is an object")
            .insert("transactionId".into(), json!(transaction_id(key)));
    }
    Ok(body)
}

fn graph_local_time(value: DateTime<Utc>, timezone: &str) -> anyhow::Result<Value> {
    let timezone = timezone.parse::<chrono_tz::Tz>()?;
    Ok(json!({
        "dateTime": value.with_timezone(&timezone).format("%Y-%m-%dT%H:%M:%S%.3f").to_string(),
        "timeZone": timezone.name(),
    }))
}

fn graph_utc_time(value: DateTime<Utc>) -> Value {
    json!({
        "dateTime": value.format("%Y-%m-%dT%H:%M:%S%.3f").to_string(),
        "timeZone": "UTC",
    })
}

fn parse_graph_time(value: &GraphDateTime) -> anyhow::Result<DateTime<Utc>> {
    if let Ok(parsed) = DateTime::parse_from_rfc3339(&value.date_time) {
        return Ok(parsed.with_timezone(&Utc));
    }
    let local = NaiveDateTime::parse_from_str(&value.date_time, "%Y-%m-%dT%H:%M:%S%.f")?;
    let timezone = value.time_zone.parse::<chrono_tz::Tz>()?;
    match timezone.from_local_datetime(&local) {
        LocalResult::Single(value) => Ok(value.with_timezone(&Utc)),
        LocalResult::Ambiguous(_, _) => {
            anyhow::bail!("Microsoft Calendar local time is ambiguous")
        }
        LocalResult::None => anyhow::bail!("Microsoft Calendar local time does not exist"),
    }
}

fn validate_recurrence(value: Option<&str>) -> anyhow::Result<()> {
    if let Some(value) = value {
        let recurrence: Value = serde_json::from_str(value)?;
        anyhow::ensure!(
            recurrence.is_object(),
            "Microsoft recurrence must be a JSON object"
        );
    }
    Ok(())
}

fn event_version(event: &GraphEvent) -> anyhow::Result<u64> {
    Ok(etag_version(event_etag(event)?))
}

fn event_etag(event: &GraphEvent) -> anyhow::Result<&str> {
    event
        .etag
        .as_deref()
        .filter(|value| !value.is_empty())
        .ok_or_else(|| anyhow::anyhow!("Microsoft Calendar event etag is missing"))
}

fn etag_version(etag: &str) -> u64 {
    let digest = Sha256::digest(etag.as_bytes());
    u64::from_be_bytes(digest[..8].try_into().expect("SHA-256 prefix")) | 1
}

fn transaction_id(value: &str) -> String {
    let mut bytes: [u8; 16] = Sha256::digest(value.as_bytes())[..16]
        .try_into()
        .expect("SHA-256 prefix");
    bytes[6] = (bytes[6] & 0x0f) | 0x50;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    let encoded = hex::encode(bytes);
    format!(
        "{}-{}-{}-{}-{}",
        &encoded[0..8],
        &encoded[8..12],
        &encoded[12..16],
        &encoded[16..20],
        &encoded[20..32]
    )
}

fn prefer_utc(request: &mut ProviderHttpRequest) {
    request
        .headers
        .insert("Prefer".into(), UTC_PREFERENCE.into());
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

#[cfg(test)]
#[path = "microsoft_calendar_tests.rs"]
mod tests;
