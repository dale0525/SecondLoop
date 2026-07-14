use super::*;

fn request(schedule: ScheduleSpec, misfire: MisfirePolicy) -> ScheduledJobRequest {
    ScheduledJobRequest {
        app_id: "com.example.secretary".into(),
        tenant_id: "local".into(),
        user_id: "user".into(),
        name: "Daily briefing".into(),
        schedule,
        misfire,
        payload: serde_json::json!({"task": "briefing"}),
    }
}

#[test]
fn interval_cron_and_rrule_calculations_are_deterministic() {
    let after = DateTime::parse_from_rfc3339("2026-07-14T00:00:00Z")
        .unwrap()
        .with_timezone(&Utc);
    let interval = ScheduleSpec::Interval {
        anchor: after,
        every_seconds: 3600,
    };
    assert_eq!(
        interval.next_after(after).unwrap().unwrap(),
        after + Duration::hours(1)
    );
    let cron = ScheduleSpec::Cron {
        expression: "0 30 9 * * *".into(),
        timezone: "Asia/Shanghai".into(),
    };
    assert_eq!(
        cron.next_after(after).unwrap().unwrap(),
        DateTime::parse_from_rfc3339("2026-07-14T01:30:00Z")
            .unwrap()
            .with_timezone(&Utc)
    );
    let rrule = ScheduleSpec::RRule {
        rule: "FREQ=DAILY;BYHOUR=9;BYMINUTE=0;BYSECOND=0".into(),
        timezone: "Asia/Shanghai".into(),
        start: after,
    };
    assert_eq!(
        rrule.next_after(after).unwrap().unwrap(),
        DateTime::parse_from_rfc3339("2026-07-14T01:00:00Z")
            .unwrap()
            .with_timezone(&Utc)
    );
}

#[tokio::test]
async fn one_shot_survives_restart_and_is_claimed_exactly_once() {
    let root = tempfile::tempdir().unwrap();
    let database = root.path().join("scheduler.db");
    let url = format!("sqlite://{}?mode=rwc", database.display());
    let now = Utc::now();
    let store = SchedulerStore::connect(&url).await.unwrap();
    store
        .create_job(
            request(ScheduleSpec::OneShot { at: now }, MisfirePolicy::FireOnce),
            now,
        )
        .await
        .unwrap();
    store.close().await;

    let restarted = SchedulerStore::connect(&url).await.unwrap();
    let claims = restarted
        .claim_due(now, "worker-1", Duration::minutes(5), 10)
        .await
        .unwrap();
    assert_eq!(claims.len(), 1);
    assert!(
        restarted
            .claim_due(now, "worker-2", Duration::minutes(5), 10)
            .await
            .unwrap()
            .is_empty()
    );
    assert!(
        restarted
            .finish_claim(
                &claims[0].claim_id,
                true,
                serde_json::json!({"ok": true}),
                now
            )
            .await
            .unwrap()
    );
}

#[tokio::test]
async fn schedule_creation_is_idempotent_and_scope_bound() {
    let store = SchedulerStore::connect("sqlite::memory:").await.unwrap();
    let now = Utc::now();
    let scheduled_request = request(
        ScheduleSpec::OneShot {
            at: now + Duration::hours(1),
        },
        MisfirePolicy::FireOnce,
    );
    let first = store
        .create_job_idempotent(scheduled_request.clone(), "schedule-1", now)
        .await
        .unwrap();
    let repeated = store
        .create_job_idempotent(scheduled_request, "schedule-1", now)
        .await
        .unwrap();
    assert_eq!(first.id, repeated.id);
    assert!(
        store
            .get_job_for_scope("other", "local", "user", &first.id)
            .await
            .unwrap()
            .is_none()
    );

    let conflicting = request(
        ScheduleSpec::OneShot {
            at: now + Duration::hours(2),
        },
        MisfirePolicy::FireOnce,
    );
    assert!(
        store
            .create_job_idempotent(conflicting, "schedule-1", now)
            .await
            .unwrap_err()
            .to_string()
            .contains("idempotency conflict")
    );
}

#[tokio::test]
async fn catch_up_is_bounded_and_run_ids_are_stable() {
    let store = SchedulerStore::connect("sqlite::memory:").await.unwrap();
    let now = Utc::now();
    store
        .create_job(
            request(
                ScheduleSpec::Interval {
                    anchor: now - Duration::hours(10),
                    every_seconds: 3600,
                },
                MisfirePolicy::CatchUp { max_runs: 3 },
            ),
            now - Duration::hours(10),
        )
        .await
        .unwrap();
    let claims = store
        .claim_due(now, "worker", Duration::minutes(1), 10)
        .await
        .unwrap();
    assert_eq!(claims.len(), 3);
    assert!(
        claims
            .iter()
            .all(|claim| claim.run_id.starts_with("scheduled:"))
    );
}

#[test]
fn nonexistent_dst_local_time_is_skipped_without_panicking() {
    let start = DateTime::parse_from_rfc3339("2026-03-07T07:30:00Z")
        .unwrap()
        .with_timezone(&Utc);
    let schedule = ScheduleSpec::RRule {
        rule: "FREQ=DAILY;BYHOUR=2;BYMINUTE=30".into(),
        timezone: "America/New_York".into(),
        start,
    };
    let next = schedule.next_after(start).unwrap().unwrap();
    assert!(next > start);
}
