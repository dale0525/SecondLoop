use super::*;
use crate::scheduler::{MisfirePolicy, ScheduleSpec, ScheduledJobRequest};
use serde_json::json;
use std::sync::Arc;
use std::sync::atomic::{AtomicUsize, Ordering};

struct FakeExecutor {
    calls: Arc<AtomicUsize>,
    now: DateTime<Utc>,
}

#[async_trait]
impl ScheduledRunExecutor for FakeExecutor {
    async fn execute(&self, claim: &ScheduledClaim) -> anyhow::Result<ScheduledExecution> {
        self.calls.fetch_add(1, Ordering::SeqCst);
        Ok(ScheduledExecution {
            succeeded: true,
            result: json!({"runId": claim.run_id}),
            notifications: vec![NotificationRequest {
                app_id: "app".into(),
                tenant_id: "tenant".into(),
                user_id: "user".into(),
                channel: "local".into(),
                title: "Scheduled result".into(),
                body: "The scheduled run completed.".into(),
                dedupe_key: claim.run_id.clone(),
                not_before: self.now,
                quiet_hours: None,
                data: json!({"runId": claim.run_id}),
            }],
        })
    }
}

struct FakeNotificationHost {
    calls: Arc<AtomicUsize>,
}

#[async_trait]
impl NotificationHost for FakeNotificationHost {
    async fn deliver(
        &self,
        record: &NotificationRecord,
    ) -> anyhow::Result<NotificationDeliveryOutcome> {
        self.calls.fetch_add(1, Ordering::SeqCst);
        Ok(NotificationDeliveryOutcome::Delivered {
            delivery_id: format!("delivered:{}", record.request.dedupe_key),
        })
    }
}

#[tokio::test]
async fn scheduled_execution_and_notification_delivery_are_independent_and_exactly_once() {
    let storage = Storage::connect("sqlite::memory:").await.unwrap();
    let scheduler = SchedulerStore::from_storage(&storage).await.unwrap();
    let notifications = NotificationStore::from_storage(&storage).await.unwrap();
    let now = Utc::now();
    scheduler
        .create_job(
            ScheduledJobRequest {
                app_id: "app".into(),
                tenant_id: "tenant".into(),
                user_id: "user".into(),
                name: "Morning brief".into(),
                schedule: ScheduleSpec::OneShot { at: now },
                misfire: MisfirePolicy::FireOnce,
                payload: json!({"task": "brief"}),
            },
            now,
        )
        .await
        .unwrap();
    let execution_calls = Arc::new(AtomicUsize::new(0));
    let runner = SchedulerRunner::new(
        scheduler.clone(),
        notifications.clone(),
        FakeExecutor {
            calls: execution_calls.clone(),
            now,
        },
        "scheduler-1",
        Duration::seconds(30),
    )
    .unwrap();
    assert_eq!(runner.tick(now, 10).await.unwrap(), 1);
    assert_eq!(
        runner.tick(now + Duration::seconds(1), 10).await.unwrap(),
        0
    );
    assert_eq!(execution_calls.load(Ordering::SeqCst), 1);

    let delivery_calls = Arc::new(AtomicUsize::new(0));
    let worker = NotificationWorker::new(
        NotificationStore::from_storage(&storage).await.unwrap(),
        FakeNotificationHost {
            calls: delivery_calls.clone(),
        },
        "notifications-1",
        Duration::seconds(30),
    )
    .unwrap();
    assert_eq!(worker.tick(Utc::now(), 10).await.unwrap(), 1);
    assert_eq!(worker.tick(Utc::now(), 10).await.unwrap(), 0);
    assert_eq!(delivery_calls.load(Ordering::SeqCst), 1);
}

#[tokio::test]
async fn declarative_recurring_notifications_are_idempotent_per_run_not_per_schedule() {
    let now = Utc::now();
    let claim = |run_id: &str| ScheduledClaim {
        claim_id: format!("claim-{run_id}"),
        job_id: "job-1".into(),
        run_id: run_id.into(),
        app_id: "app".into(),
        tenant_id: "tenant".into(),
        user_id: "user".into(),
        due_at: now,
        claimed_by: "worker".into(),
        claim_until: now + Duration::minutes(1),
        payload: json!({
            "notifications":[{
                "channel":"desktop",
                "title":"Daily reminder",
                "body":"Review priorities",
                "dedupeKey":"daily-reminder",
                "notBefore":now,
                "quietHours":null,
                "data":{}
            }]
        }),
    };
    let executor = DeclarativeScheduledRunExecutor;
    let first = executor.execute(&claim("run-1")).await.unwrap();
    let retry = executor.execute(&claim("run-1")).await.unwrap();
    let second = executor.execute(&claim("run-2")).await.unwrap();

    assert_eq!(
        first.notifications[0].dedupe_key,
        retry.notifications[0].dedupe_key
    );
    assert_ne!(
        first.notifications[0].dedupe_key,
        second.notifications[0].dedupe_key
    );
    assert!(first.notifications[0].dedupe_key.starts_with("scheduled:"));
}

#[tokio::test]
async fn expired_scheduler_claim_is_recovered_with_the_same_run_identity() {
    let storage = Storage::connect("sqlite::memory:").await.unwrap();
    let scheduler = SchedulerStore::from_storage(&storage).await.unwrap();
    let now = Utc::now();
    scheduler
        .create_job(
            ScheduledJobRequest {
                app_id: "app".into(),
                tenant_id: "tenant".into(),
                user_id: "user".into(),
                name: "Recover me".into(),
                schedule: ScheduleSpec::OneShot { at: now },
                misfire: MisfirePolicy::FireOnce,
                payload: json!({}),
            },
            now,
        )
        .await
        .unwrap();
    let first = scheduler
        .claim_due(now, "worker-a", Duration::seconds(1), 10)
        .await
        .unwrap();
    let recovered = scheduler
        .claim_due(
            now + Duration::seconds(2),
            "worker-b",
            Duration::seconds(30),
            10,
        )
        .await
        .unwrap();
    assert_eq!(first.len(), 1);
    assert_eq!(recovered.len(), 1);
    assert_eq!(first[0].claim_id, recovered[0].claim_id);
    assert_eq!(first[0].run_id, recovered[0].run_id);
    assert_eq!(recovered[0].claimed_by, "worker-b");
    assert!(
        !scheduler
            .finish_claim_for_worker(&first[0].claim_id, "worker-a", true, json!({}), Utc::now(),)
            .await
            .unwrap()
    );
}

#[test]
fn quiet_hours_defer_until_the_local_end_boundary() {
    let quiet = QuietHours {
        timezone: "UTC".into(),
        start_minute: 22 * 60,
        end_minute: 7 * 60,
    };
    let now = Utc.with_ymd_and_hms(2026, 7, 14, 23, 30, 0).unwrap();
    assert_eq!(
        quiet.next_allowed(now).unwrap(),
        Utc.with_ymd_and_hms(2026, 7, 15, 7, 0, 0).unwrap()
    );
}
