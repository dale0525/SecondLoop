use super::*;
use crate::http::ProviderHttpResponse;
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
        _: &BTreeSet<String>,
    ) -> anyhow::Result<SecretMaterial> {
        assert_eq!(connector_id, CALENDAR_CONNECTOR_ID);
        assert_eq!(account_id, "primary");
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
        description: None,
        start,
        end: start + chrono::Duration::hours(1),
        timezone: "Asia/Shanghai".into(),
        location: None,
        attendees: Vec::new(),
        recurrence: None,
    }
}

fn event_json(start: DateTime<Utc>) -> Vec<u8> {
    serde_json::to_vec(&json!({
        "id": "event-1",
        "etag": "etag-1",
        "status": "confirmed",
        "summary": "Planning",
        "start": {"dateTime": start, "timeZone": "Asia/Shanghai"},
        "end": {"dateTime": start + chrono::Duration::hours(1), "timeZone": "Asia/Shanghai"},
        "attendees": [],
        "updated": Utc::now()
    }))
    .unwrap()
}

#[tokio::test]
async fn approved_create_checks_conflicts_then_posts_exact_event() {
    let start = Utc::now() + chrono::Duration::hours(1);
    let http = Arc::new(FakeHttp::default());
    http.responses.lock().unwrap().extend([
        ProviderHttpResponse {
            status: 200,
            body: serde_json::to_vec(&json!({"calendars": {"primary": {"busy": []}}})).unwrap(),
        },
        ProviderHttpResponse {
            status: 200,
            body: event_json(start),
        },
    ]);
    let connector = GoogleCalendarConnector::new(http.clone(), Arc::new(FakeCredentials));
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
    let requests = http.requests.lock().unwrap();
    assert_eq!(requests.len(), 2);
    assert_eq!(requests[0].path, "/calendar/v3/freeBusy");
    assert_eq!(requests[1].method, Method::POST);
    assert_eq!(requests[1].json.as_ref().unwrap()["summary"], "Planning");
}

#[test]
fn all_day_events_fail_instead_of_flattening_time_semantics() {
    let event: GoogleEvent = serde_json::from_value(json!({
        "id": "event-1",
        "etag": "etag-1",
        "summary": "Holiday",
        "start": {"date": "2026-07-16"},
        "end": {"date": "2026-07-17"},
        "updated": Utc::now()
    }))
    .unwrap();
    assert!(normalize_event("primary", event).is_err());
}

#[tokio::test]
async fn untitled_events_keep_the_calendar_listing_representable() {
    let start = Utc::now();
    let http = Arc::new(FakeHttp::default());
    http.responses.lock().unwrap().push_back(ProviderHttpResponse {
        status: 200,
        body: serde_json::to_vec(&json!({
            "items": [{
                "id": "event-1",
                "etag": "etag-1",
                "start": {"dateTime": start, "timeZone": "Asia/Shanghai"},
                "end": {"dateTime": start + chrono::Duration::hours(1), "timeZone": "Asia/Shanghai"},
                "updated": start
            }]
        }))
        .unwrap(),
    });
    let connector = GoogleCalendarConnector::new(http, Arc::new(FakeCredentials));

    let events = connector
        .list_events(&scope(), start, start + chrono::Duration::hours(2))
        .await
        .unwrap();
    assert_eq!(
        events[0].content.title,
        crate::calendar_support::UNTITLED_EVENT_TITLE
    );
}
