use super::*;
use crate::storage::Storage;

#[tokio::test]
async fn automation_tools_inject_scope_and_preserve_idempotency() {
    let storage = Storage::connect("sqlite::memory:").await.unwrap();
    let runtime = AutomationToolRuntime::from_storage(
        &storage,
        AutomationScope::new("app", "tenant", "user").unwrap(),
    )
    .await
    .unwrap();
    let at = Utc::now() + chrono::Duration::hours(1);
    let arguments = json!({
        "name":"Follow up",
        "schedule":{"kind":"one_shot","at":at},
        "misfire":{"kind":"fire_once"},
        "payload":{"kind":"reminder"},
        "idempotencyKey":"schedule-1"
    });
    let first = runtime
        .execute("schedule_create", arguments.clone())
        .await
        .unwrap();
    let repeated = runtime.execute("schedule_create", arguments).await.unwrap();
    assert_eq!(first["id"], repeated["id"]);
    assert_eq!(first["request"]["app_id"], "app");
    assert!(
        runtime
            .execute("schedule_list", json!({"appId":"other"}))
            .await
            .is_err()
    );
}

#[tokio::test]
async fn notifications_are_scoped_deduplicated_and_cancellable() {
    let storage = Storage::connect("sqlite::memory:").await.unwrap();
    let runtime = AutomationToolRuntime::from_storage(
        &storage,
        AutomationScope::new("app", "tenant", "user").unwrap(),
    )
    .await
    .unwrap();
    let arguments = json!({
        "channel":"desktop",
        "title":"Reminder",
        "body":"Prepare the brief",
        "dedupeKey":"notification-1",
        "notBefore":Utc::now(),
        "data":{}
    });
    let first = runtime
        .execute("notification_enqueue", arguments.clone())
        .await
        .unwrap();
    let repeated = runtime
        .execute("notification_enqueue", arguments)
        .await
        .unwrap();
    assert_eq!(first["notification_id"], repeated["notification_id"]);
    let cancelled = runtime
        .execute(
            "notification_cancel",
            json!({"id":first["notification_id"]}),
        )
        .await
        .unwrap();
    assert_eq!(cancelled["status"], "cancelled");
}

#[test]
fn definitions_are_concrete_and_host_scoped() {
    let names = definitions()
        .into_iter()
        .map(|definition| definition.name)
        .collect::<Vec<_>>();
    assert_eq!(names, AUTOMATION_TOOL_NAMES);
}
