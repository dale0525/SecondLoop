use agent_runtime::automation::{DeclarativeScheduledRunExecutor, SchedulerRunner};
use agent_runtime::scheduler::SchedulerStore;
use agent_runtime::{automation::NotificationStore, storage::Storage};
use chrono::Duration;
use std::time::Duration as StdDuration;
use tokio::task::JoinHandle;
use tokio_util::sync::CancellationToken;

pub(super) async fn start_scheduler_worker(
    storage: &Storage,
    cancellation: CancellationToken,
) -> anyhow::Result<JoinHandle<anyhow::Result<()>>> {
    let scheduler = SchedulerStore::from_storage(storage).await?;
    let notifications = NotificationStore::from_storage(storage).await?;
    let runner = SchedulerRunner::new(
        scheduler,
        notifications,
        DeclarativeScheduledRunExecutor,
        format!("server:{}", std::process::id()),
        Duration::seconds(60),
    )?;
    Ok(tokio::spawn(async move {
        runner
            .run_until_cancelled(StdDuration::from_secs(5), 25, cancellation)
            .await
    }))
}

#[cfg(test)]
mod tests {
    use super::*;
    use agent_runtime::scheduler::{MisfirePolicy, ScheduleSpec, ScheduledJobRequest};
    use chrono::Utc;

    #[tokio::test]
    async fn declarative_worker_persists_one_claim_and_notification() {
        let storage = Storage::connect("sqlite::memory:").await.unwrap();
        let scheduler = SchedulerStore::from_storage(&storage).await.unwrap();
        let notifications = NotificationStore::from_storage(&storage).await.unwrap();
        let now = Utc::now();
        scheduler
            .create_job(
                ScheduledJobRequest {
                    app_id: "com.example.agent".into(),
                    tenant_id: "local".into(),
                    user_id: "user".into(),
                    name: "Reminder".into(),
                    schedule: ScheduleSpec::OneShot { at: now },
                    misfire: MisfirePolicy::FireOnce,
                    payload: serde_json::json!({
                        "result": {"kind": "reminder"},
                        "notifications": [{
                            "channel": "desktop",
                            "title": "Reminder",
                            "body": "Review the draft",
                            "dedupeKey": "reminder-1",
                            "notBefore": now,
                            "quietHours": null,
                            "data": {}
                        }]
                    }),
                },
                now,
            )
            .await
            .unwrap();
        let runner = SchedulerRunner::new(
            scheduler,
            notifications.clone(),
            DeclarativeScheduledRunExecutor,
            "test-worker",
            Duration::seconds(30),
        )
        .unwrap();

        assert_eq!(runner.tick(now, 10).await.unwrap(), 1);
        assert_eq!(runner.tick(now, 10).await.unwrap(), 0);
        let claimed = notifications
            .claim_due("host", now, Duration::seconds(30), 10)
            .await
            .unwrap();
        assert_eq!(claimed.len(), 1);
        assert_eq!(claimed[0].request.app_id, "com.example.agent");
        assert_eq!(claimed[0].request.tenant_id, "local");
        assert_eq!(claimed[0].request.user_id, "user");
    }

    #[tokio::test]
    async fn declarative_worker_rejects_notification_scope_in_payload() {
        let storage = Storage::connect("sqlite::memory:").await.unwrap();
        let scheduler = SchedulerStore::from_storage(&storage).await.unwrap();
        let notifications = NotificationStore::from_storage(&storage).await.unwrap();
        let now = Utc::now();
        scheduler
            .create_job(
                ScheduledJobRequest {
                    app_id: "trusted.app".into(),
                    tenant_id: "local".into(),
                    user_id: "user".into(),
                    name: "Untrusted payload".into(),
                    schedule: ScheduleSpec::OneShot { at: now },
                    misfire: MisfirePolicy::FireOnce,
                    payload: serde_json::json!({
                        "notifications": [{
                            "appId": "other.app",
                            "channel": "desktop",
                            "title": "Must not enqueue",
                            "body": "Untrusted scope",
                            "dedupeKey": "scope-injection",
                            "notBefore": now,
                            "quietHours": null,
                            "data": {}
                        }]
                    }),
                },
                now,
            )
            .await
            .unwrap();
        let runner = SchedulerRunner::new(
            scheduler,
            notifications.clone(),
            DeclarativeScheduledRunExecutor,
            "test-worker",
            Duration::seconds(30),
        )
        .unwrap();

        assert_eq!(runner.tick(now, 10).await.unwrap(), 1);
        assert!(
            notifications
                .claim_due("host", now, Duration::seconds(30), 10)
                .await
                .unwrap()
                .is_empty()
        );
    }
}
