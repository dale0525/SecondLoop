use super::*;
use crate::calendar::{CalendarAttendee, CalendarEventContent};
use chrono::{Duration, Utc};

fn preview(kind: CalendarMutationKind) -> CalendarMutationPreview {
    let start = Utc::now() + Duration::hours(1);
    let content = CalendarEventContent {
        calendar_id: "primary".into(),
        title: "Planning".into(),
        description: Some("Quarterly planning".into()),
        start,
        end: start + Duration::hours(1),
        timezone: "Asia/Shanghai".into(),
        location: Some("Room 1".into()),
        attendees: vec![CalendarAttendee {
            address: "guest@example.test".into(),
            display_name: Some("Guest".into()),
            response: "needs_action".into(),
        }],
        recurrence: None,
    };
    let (event_id, expected_version, content) = match kind {
        CalendarMutationKind::Create => (None, None, Some(content)),
        CalendarMutationKind::Update => (Some("event-1".into()), Some(2), Some(content)),
        CalendarMutationKind::Cancel => (Some("event-1".into()), Some(2), None),
    };
    CalendarMutationPreview {
        preview_id: "preview-1".into(),
        account_id: "primary".into(),
        kind,
        event_id,
        expected_version,
        content,
        conflicts: Vec::new(),
        attendee_visible: kind != CalendarMutationKind::Cancel,
        preview_hash: "a".repeat(64),
        idempotency_key: format!("calendar-{kind:?}"),
    }
}

#[test]
fn canonical_envelopes_bind_each_mutation_kind() {
    for kind in [
        CalendarMutationKind::Create,
        CalendarMutationKind::Update,
        CalendarMutationKind::Cancel,
    ] {
        let canonical = CanonicalCalendarActionEnvelope::from_preview(preview(kind)).unwrap();
        let foundation = canonical.clone().into_foundation_action().unwrap();
        assert_eq!(
            CanonicalCalendarActionEnvelope::from_foundation_action(&foundation).unwrap(),
            canonical
        );
    }
}

#[test]
fn canonical_envelope_rejects_binding_drift() {
    let mut foundation =
        CanonicalCalendarActionEnvelope::from_preview(preview(CalendarMutationKind::Update))
            .unwrap()
            .into_foundation_action()
            .unwrap();
    foundation.account_id = "other".into();
    assert!(CanonicalCalendarActionEnvelope::from_foundation_action(&foundation).is_err());
}
