use super::*;
use agent_runtime::credential::SecretMaterial;
use std::collections::VecDeque;

#[derive(Default)]
struct FakeHttp {
    requests: Mutex<Vec<ProviderHttpRequest>>,
    responses: Mutex<VecDeque<ProviderHttpResponse>>,
}

#[async_trait]
impl ProviderHttpClient for FakeHttp {
    async fn execute(
        &self,
        request: ProviderHttpRequest,
        _: &SecretMaterial,
    ) -> anyhow::Result<ProviderHttpResponse> {
        self.requests.lock().unwrap().push(request);
        self.responses
            .lock()
            .unwrap()
            .pop_front()
            .ok_or_else(|| anyhow::anyhow!("missing fake response"))
    }
}

struct FakeCredentials;

#[async_trait]
impl ProviderCredentialSource for FakeCredentials {
    async fn access_token(
        &self,
        connector_id: &str,
        account_id: &str,
        scopes: &BTreeSet<String>,
    ) -> anyhow::Result<SecretMaterial> {
        assert_eq!(connector_id, CALENDAR_CONNECTOR_ID);
        assert_eq!(account_id, "primary");
        assert_eq!(scopes, &BTreeSet::from([CALENDAR_SCOPE.into()]));
        SecretMaterial::new("token")
    }
}

fn scope() -> CalendarScope {
    CalendarScope {
        app_id: "com.example.app".into(),
        tenant_id: "local".into(),
        user_id: "user".into(),
        account_id: "primary".into(),
    }
}

fn content(start: DateTime<Utc>) -> CalendarEventContent {
    CalendarEventContent {
        calendar_id: "primary".into(),
        title: "Planning".into(),
        description: Some("Agenda".into()),
        start,
        end: start + chrono::Duration::hours(1),
        timezone: "Asia/Shanghai".into(),
        location: Some("Room 1".into()),
        attendees: Vec::new(),
        recurrence: Some(
            json!({
                "pattern": {"type": "weekly", "interval": 1, "daysOfWeek": ["thursday"]},
                "range": {"type": "noEnd", "startDate": "2026-07-16"}
            })
            .to_string(),
        ),
    }
}

fn event_json(start: DateTime<Utc>, etag: &str) -> Vec<u8> {
    serde_json::to_vec(&json!({
        "@odata.etag": etag,
        "id": "event-1",
        "subject": "Planning",
        "body": {"content": "Agenda"},
        "start": {"dateTime": start.format("%Y-%m-%dT%H:%M:%S%.3f").to_string(), "timeZone": "UTC"},
        "end": {"dateTime": (start + chrono::Duration::hours(1)).format("%Y-%m-%dT%H:%M:%S%.3f").to_string(), "timeZone": "UTC"},
        "location": {"displayName": "Room 1"},
        "attendees": [],
        "recurrence": {
            "pattern": {"type": "weekly", "interval": 1, "daysOfWeek": ["thursday"]},
            "range": {"type": "noEnd", "startDate": "2026-07-16"}
        },
        "isCancelled": false,
        "originalStartTimeZone": "Asia/Shanghai",
        "lastModifiedDateTime": Utc::now()
    }))
    .unwrap()
}

#[tokio::test]
async fn approved_create_checks_schedule_and_preserves_graph_recurrence() {
    let start = Utc::now() + chrono::Duration::hours(1);
    let http = Arc::new(FakeHttp::default());
    http.responses.lock().unwrap().extend([
        ProviderHttpResponse {
            status: 200,
            body: serde_json::to_vec(&json!({"value": [{"scheduleItems": []}]})).unwrap(),
        },
        ProviderHttpResponse {
            status: 200,
            body: event_json(start, "etag-1"),
        },
    ]);
    let connector = MicrosoftCalendarConnector::new(
        http.clone(),
        Arc::new(FakeCredentials),
        "person@example.test",
    )
    .unwrap();
    let preview = connector
        .preview_create(&scope(), content(start), "create-1".into())
        .await
        .unwrap();
    let event = connector
        .apply(
            &scope(),
            ApprovedCalendarMutation {
                preview_id: preview.preview_id,
                preview_hash: preview.preview_hash,
                approval_id: "approval-1".into(),
            },
        )
        .await
        .unwrap();
    assert_eq!(event.id, "event-1");
    assert!(event.content.recurrence.unwrap().contains("daysOfWeek"));
    let requests = http.requests.lock().unwrap();
    assert_eq!(requests[0].path, "/v1.0/me/calendar/getSchedule");
    assert_eq!(requests[1].path, "/v1.0/me/events");
    assert_eq!(requests[1].method, Method::POST);
    assert!(requests[1].json.as_ref().unwrap()["recurrence"].is_object());
    assert!(requests[1].json.as_ref().unwrap()["transactionId"].is_string());
}

#[tokio::test]
async fn approved_update_rechecks_etag_and_uses_if_match() {
    let start = Utc::now() + chrono::Duration::hours(1);
    let http = Arc::new(FakeHttp::default());
    http.responses.lock().unwrap().extend([
        ProviderHttpResponse {
            status: 200,
            body: event_json(start, "etag-1"),
        },
        ProviderHttpResponse {
            status: 200,
            body: serde_json::to_vec(&json!({"value": [{"scheduleItems": []}]})).unwrap(),
        },
        ProviderHttpResponse {
            status: 200,
            body: event_json(start, "etag-1"),
        },
        ProviderHttpResponse {
            status: 200,
            body: event_json(start, "etag-2"),
        },
    ]);
    let connector = MicrosoftCalendarConnector::new(
        http.clone(),
        Arc::new(FakeCredentials),
        "person@example.test",
    )
    .unwrap();
    let expected_version = etag_version("etag-1");
    let preview = connector
        .preview_update(
            &scope(),
            "event-1",
            expected_version,
            content(start),
            "update-1".into(),
        )
        .await
        .unwrap();
    connector
        .apply(
            &scope(),
            ApprovedCalendarMutation {
                preview_id: preview.preview_id,
                preview_hash: preview.preview_hash,
                approval_id: "approval-1".into(),
            },
        )
        .await
        .unwrap();
    let requests = http.requests.lock().unwrap();
    let patch = requests.last().unwrap();
    assert_eq!(patch.method, Method::PATCH);
    assert_eq!(
        patch.headers.get("If-Match").map(String::as_str),
        Some("etag-1")
    );
}

#[test]
fn ambiguous_or_nonexistent_local_times_fail_closed() {
    let ambiguous = GraphDateTime {
        date_time: "2026-11-01T01:30:00.000".into(),
        time_zone: "America/New_York".into(),
    };
    let nonexistent = GraphDateTime {
        date_time: "2026-03-08T02:30:00.000".into(),
        time_zone: "America/New_York".into(),
    };
    assert!(parse_graph_time(&ambiguous).is_err());
    assert!(parse_graph_time(&nonexistent).is_err());
}

#[tokio::test]
async fn untitled_events_keep_the_calendar_listing_representable() {
    let start = Utc::now();
    let http = Arc::new(FakeHttp::default());
    http.responses.lock().unwrap().push_back(ProviderHttpResponse {
        status: 200,
        body: serde_json::to_vec(&json!({
            "value": [{
                "@odata.etag": "etag-1",
                "id": "event-1",
                "start": {"dateTime": start.format("%Y-%m-%dT%H:%M:%S%.3f").to_string(), "timeZone": "UTC"},
                "end": {"dateTime": (start + chrono::Duration::hours(1)).format("%Y-%m-%dT%H:%M:%S%.3f").to_string(), "timeZone": "UTC"},
                "isCancelled": false,
                "originalStartTimeZone": "UTC",
                "lastModifiedDateTime": start
            }]
        }))
        .unwrap(),
    });
    let connector =
        MicrosoftCalendarConnector::new(http, Arc::new(FakeCredentials), "person@example.test")
            .unwrap();

    let events = connector
        .list_events(&scope(), start, start + chrono::Duration::hours(2))
        .await
        .unwrap();
    assert_eq!(
        events[0].content.title,
        crate::calendar_support::UNTITLED_EVENT_TITLE
    );
}
