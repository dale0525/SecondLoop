use crate::storage::Storage;
use chrono::{DateTime, Datelike, Duration, TimeZone, Timelike, Utc};
use chrono_tz::Tz;
use cron::Schedule;
use serde::{Deserialize, Serialize};
use serde_json::Value;
use sha2::{Digest, Sha256};
use sqlx::sqlite::{SqliteConnectOptions, SqlitePoolOptions};
use sqlx::{Row, SqlitePool};
use std::str::FromStr;
use std::time::Duration as StdDuration;
use uuid::Uuid;

const SCHEDULER_SCHEMA_VERSION: i64 = 1;

#[derive(Clone, Debug, Deserialize, Serialize, PartialEq, Eq)]
#[serde(tag = "kind", rename_all = "snake_case", deny_unknown_fields)]
pub enum ScheduleSpec {
    OneShot {
        at: DateTime<Utc>,
    },
    Interval {
        anchor: DateTime<Utc>,
        every_seconds: u64,
    },
    Cron {
        expression: String,
        timezone: String,
    },
    RRule {
        rule: String,
        timezone: String,
        start: DateTime<Utc>,
    },
}

impl ScheduleSpec {
    pub fn validate(&self) -> anyhow::Result<()> {
        match self {
            Self::OneShot { .. } => Ok(()),
            Self::Interval { every_seconds, .. } => {
                anyhow::ensure!(*every_seconds > 0, "schedule interval must be positive");
                anyhow::ensure!(
                    *every_seconds <= 366 * 24 * 60 * 60,
                    "schedule interval is too large"
                );
                Ok(())
            }
            Self::Cron {
                expression,
                timezone,
            } => {
                parse_timezone(timezone)?;
                Schedule::from_str(expression)
                    .map(|_| ())
                    .map_err(|error| anyhow::anyhow!("invalid cron expression: {error}"))
            }
            Self::RRule { rule, timezone, .. } => {
                parse_timezone(timezone)?;
                parse_rrule(rule).map(|_| ())
            }
        }
    }

    pub fn next_after(&self, after: DateTime<Utc>) -> anyhow::Result<Option<DateTime<Utc>>> {
        self.validate()?;
        match self {
            Self::OneShot { at } => Ok((*at > after).then_some(*at)),
            Self::Interval {
                anchor,
                every_seconds,
            } => {
                if *anchor > after {
                    return Ok(Some(*anchor));
                }
                let every = i64::try_from(*every_seconds)?;
                let elapsed = after.signed_duration_since(*anchor).num_seconds();
                let steps = elapsed.div_euclid(every) + 1;
                Ok(Some(
                    *anchor + Duration::seconds(steps.saturating_mul(every)),
                ))
            }
            Self::Cron {
                expression,
                timezone,
            } => {
                let timezone = parse_timezone(timezone)?;
                let schedule = Schedule::from_str(expression)?;
                Ok(schedule
                    .after(&after.with_timezone(&timezone))
                    .next()
                    .map(|next| next.with_timezone(&Utc)))
            }
            Self::RRule {
                rule,
                timezone,
                start,
            } => next_rrule_after(rule, parse_timezone(timezone)?, *start, after),
        }
    }
}

#[derive(Clone, Debug, Deserialize, Serialize, PartialEq, Eq)]
#[serde(tag = "kind", rename_all = "snake_case", deny_unknown_fields)]
pub enum MisfirePolicy {
    Skip { grace_seconds: u64 },
    FireOnce,
    CatchUp { max_runs: u32 },
}

#[derive(Clone, Debug, Deserialize, Serialize, PartialEq)]
#[serde(deny_unknown_fields)]
pub struct ScheduledJobRequest {
    pub app_id: String,
    pub tenant_id: String,
    pub user_id: String,
    pub name: String,
    pub schedule: ScheduleSpec,
    pub misfire: MisfirePolicy,
    pub payload: Value,
}

#[derive(Clone, Debug, Deserialize, Serialize, PartialEq, Eq)]
#[serde(rename_all = "snake_case")]
pub enum ScheduledJobStatus {
    Active,
    Paused,
    Completed,
    Cancelled,
}

impl ScheduledJobStatus {
    fn as_str(&self) -> &'static str {
        match self {
            Self::Active => "active",
            Self::Paused => "paused",
            Self::Completed => "completed",
            Self::Cancelled => "cancelled",
        }
    }
}

#[derive(Clone, Debug, Deserialize, Serialize, PartialEq)]
pub struct ScheduledJob {
    pub id: String,
    pub request: ScheduledJobRequest,
    pub status: ScheduledJobStatus,
    pub next_run_at: Option<DateTime<Utc>>,
    pub version: i64,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct ScheduleScope<'a> {
    pub app_id: &'a str,
    pub tenant_id: &'a str,
    pub user_id: &'a str,
}

#[derive(Clone, Debug, Deserialize, Serialize, PartialEq)]
pub struct ScheduledClaim {
    pub claim_id: String,
    pub job_id: String,
    pub run_id: String,
    pub app_id: String,
    pub tenant_id: String,
    pub user_id: String,
    pub due_at: DateTime<Utc>,
    pub claimed_by: String,
    pub claim_until: DateTime<Utc>,
    pub payload: Value,
}

#[derive(Clone)]
pub struct SchedulerStore {
    pool: SqlitePool,
}

impl SchedulerStore {
    pub async fn connect(url: &str) -> anyhow::Result<Self> {
        let options = SqliteConnectOptions::from_str(url)?
            .foreign_keys(true)
            .busy_timeout(StdDuration::from_secs(5));
        let pool = SqlitePoolOptions::new().connect_with(options).await?;
        let store = Self { pool };
        store.migrate().await?;
        Ok(store)
    }

    pub async fn from_storage(storage: &Storage) -> anyhow::Result<Self> {
        let store = Self {
            pool: storage.pool().clone(),
        };
        store.migrate().await?;
        Ok(store)
    }

    async fn migrate(&self) -> anyhow::Result<()> {
        let mut tx = self.pool.begin().await?;
        sqlx::query(
            r#"CREATE TABLE IF NOT EXISTS scheduler_schema (
                version INTEGER PRIMARY KEY,
                applied_at TEXT NOT NULL
            )"#,
        )
        .execute(&mut *tx)
        .await?;
        let future: Option<i64> =
            sqlx::query_scalar("SELECT MAX(version) FROM scheduler_schema WHERE version > ?")
                .bind(SCHEDULER_SCHEMA_VERSION)
                .fetch_one(&mut *tx)
                .await?;
        anyhow::ensure!(
            future.is_none(),
            "scheduler schema is newer than this runtime"
        );
        sqlx::query(
            r#"CREATE TABLE IF NOT EXISTS scheduled_jobs (
                id TEXT PRIMARY KEY,
                app_id TEXT NOT NULL,
                tenant_id TEXT NOT NULL,
                user_id TEXT NOT NULL,
                name TEXT NOT NULL,
                schedule_json TEXT NOT NULL,
                misfire_json TEXT NOT NULL,
                payload_json TEXT NOT NULL,
                status TEXT NOT NULL,
                next_run_at TEXT,
                version INTEGER NOT NULL,
                created_at TEXT NOT NULL,
                updated_at TEXT NOT NULL
            )"#,
        )
        .execute(&mut *tx)
        .await?;
        sqlx::query(
            r#"CREATE TABLE IF NOT EXISTS schedule_claims (
                claim_id TEXT PRIMARY KEY,
                job_id TEXT NOT NULL,
                run_id TEXT NOT NULL UNIQUE,
                due_at TEXT NOT NULL,
                claimed_by TEXT NOT NULL,
                claim_until TEXT NOT NULL,
                status TEXT NOT NULL,
                result_json TEXT,
                created_at TEXT NOT NULL,
                updated_at TEXT NOT NULL,
                FOREIGN KEY(job_id) REFERENCES scheduled_jobs(id),
                UNIQUE(job_id, due_at)
            )"#,
        )
        .execute(&mut *tx)
        .await?;
        sqlx::query(
            r#"CREATE TABLE IF NOT EXISTS schedule_idempotency (
                app_id TEXT NOT NULL,
                tenant_id TEXT NOT NULL,
                user_id TEXT NOT NULL,
                idempotency_key TEXT NOT NULL,
                request_sha256 TEXT NOT NULL,
                job_id TEXT NOT NULL,
                created_at TEXT NOT NULL,
                PRIMARY KEY(app_id, tenant_id, user_id, idempotency_key),
                FOREIGN KEY(job_id) REFERENCES scheduled_jobs(id)
            )"#,
        )
        .execute(&mut *tx)
        .await?;
        sqlx::query(
            "CREATE INDEX IF NOT EXISTS scheduled_jobs_due_idx ON scheduled_jobs(status, next_run_at)",
        )
        .execute(&mut *tx)
        .await?;
        sqlx::query("INSERT OR IGNORE INTO scheduler_schema(version, applied_at) VALUES (?, ?)")
            .bind(SCHEDULER_SCHEMA_VERSION)
            .bind(Utc::now().to_rfc3339())
            .execute(&mut *tx)
            .await?;
        tx.commit().await?;
        Ok(())
    }

    pub async fn create_job(
        &self,
        request: ScheduledJobRequest,
        now: DateTime<Utc>,
    ) -> anyhow::Result<ScheduledJob> {
        validate_request(&request)?;
        let next_run_at = request
            .schedule
            .next_after(now - Duration::nanoseconds(1))?;
        anyhow::ensure!(next_run_at.is_some(), "schedule has no future occurrence");
        let now_text = now.to_rfc3339();
        let job = ScheduledJob {
            id: Uuid::new_v4().to_string(),
            request,
            status: ScheduledJobStatus::Active,
            next_run_at,
            version: 1,
        };
        sqlx::query(
            "INSERT INTO scheduled_jobs(id, app_id, tenant_id, user_id, name, schedule_json, misfire_json, payload_json, status, next_run_at, version, created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
        )
        .bind(&job.id)
        .bind(&job.request.app_id)
        .bind(&job.request.tenant_id)
        .bind(&job.request.user_id)
        .bind(&job.request.name)
        .bind(serde_json::to_string(&job.request.schedule)?)
        .bind(serde_json::to_string(&job.request.misfire)?)
        .bind(serde_json::to_string(&job.request.payload)?)
        .bind(job.status.as_str())
        .bind(job.next_run_at.map(|value| value.to_rfc3339()))
        .bind(job.version)
        .bind(&now_text)
        .bind(&now_text)
        .execute(&self.pool)
        .await?;
        Ok(job)
    }

    pub async fn create_job_idempotent(
        &self,
        request: ScheduledJobRequest,
        idempotency_key: &str,
        now: DateTime<Utc>,
    ) -> anyhow::Result<ScheduledJob> {
        validate_request(&request)?;
        validate_idempotency_key(idempotency_key)?;
        let request_sha256 = hex::encode(Sha256::digest(serde_json::to_vec(&request)?));
        if let Some(row) = sqlx::query(
            "SELECT request_sha256, job_id FROM schedule_idempotency WHERE app_id = ? AND tenant_id = ? AND user_id = ? AND idempotency_key = ?",
        )
        .bind(&request.app_id)
        .bind(&request.tenant_id)
        .bind(&request.user_id)
        .bind(idempotency_key)
        .fetch_optional(&self.pool)
        .await?
        {
            let existing_hash: String = row.try_get("request_sha256")?;
            anyhow::ensure!(
                existing_hash == request_sha256,
                "schedule idempotency conflict"
            );
            let job_id: String = row.try_get("job_id")?;
            return self
                .get_job(&job_id)
                .await?
                .ok_or_else(|| anyhow::anyhow!("idempotent schedule is unavailable"));
        }

        let job = self.create_job(request, now).await?;
        let inserted = sqlx::query(
            "INSERT OR IGNORE INTO schedule_idempotency(app_id, tenant_id, user_id, idempotency_key, request_sha256, job_id, created_at) VALUES (?, ?, ?, ?, ?, ?, ?)",
        )
        .bind(&job.request.app_id)
        .bind(&job.request.tenant_id)
        .bind(&job.request.user_id)
        .bind(idempotency_key)
        .bind(&request_sha256)
        .bind(&job.id)
        .bind(now.to_rfc3339())
        .execute(&self.pool)
        .await?;
        if inserted.rows_affected() == 1 {
            return Ok(job);
        }
        sqlx::query("DELETE FROM scheduled_jobs WHERE id = ?")
            .bind(&job.id)
            .execute(&self.pool)
            .await?;
        let row = sqlx::query(
            "SELECT request_sha256, job_id FROM schedule_idempotency WHERE app_id = ? AND tenant_id = ? AND user_id = ? AND idempotency_key = ?",
        )
        .bind(&job.request.app_id)
        .bind(&job.request.tenant_id)
        .bind(&job.request.user_id)
        .bind(idempotency_key)
        .fetch_one(&self.pool)
        .await?;
        let existing_hash: String = row.try_get("request_sha256")?;
        anyhow::ensure!(
            existing_hash == request_sha256,
            "schedule idempotency conflict"
        );
        let job_id: String = row.try_get("job_id")?;
        self.get_job(&job_id)
            .await?
            .ok_or_else(|| anyhow::anyhow!("idempotent schedule is unavailable"))
    }

    pub async fn set_status(
        &self,
        job_id: &str,
        expected_version: i64,
        status: ScheduledJobStatus,
        now: DateTime<Utc>,
    ) -> anyhow::Result<bool> {
        let updated = sqlx::query(
            "UPDATE scheduled_jobs SET status = ?, version = version + 1, updated_at = ? WHERE id = ? AND version = ?",
        )
        .bind(status.as_str())
        .bind(now.to_rfc3339())
        .bind(job_id)
        .bind(expected_version)
        .execute(&self.pool)
        .await?;
        Ok(updated.rows_affected() == 1)
    }

    pub async fn list_jobs(
        &self,
        app_id: &str,
        tenant_id: &str,
        user_id: &str,
        limit: usize,
    ) -> anyhow::Result<Vec<ScheduledJob>> {
        anyhow::ensure!((1..=100).contains(&limit), "schedule list limit is invalid");
        let rows = sqlx::query(
            "SELECT * FROM scheduled_jobs WHERE app_id = ? AND tenant_id = ? AND user_id = ? ORDER BY created_at DESC, id LIMIT ?",
        )
        .bind(app_id)
        .bind(tenant_id)
        .bind(user_id)
        .bind(limit as i64)
        .fetch_all(&self.pool)
        .await?;
        rows.into_iter().map(scheduled_job_from_row).collect()
    }

    pub async fn get_job(&self, job_id: &str) -> anyhow::Result<Option<ScheduledJob>> {
        let row = sqlx::query("SELECT * FROM scheduled_jobs WHERE id = ?")
            .bind(job_id)
            .fetch_optional(&self.pool)
            .await?;
        row.map(scheduled_job_from_row).transpose()
    }

    pub async fn get_job_for_scope(
        &self,
        app_id: &str,
        tenant_id: &str,
        user_id: &str,
        job_id: &str,
    ) -> anyhow::Result<Option<ScheduledJob>> {
        validate_scope(app_id, tenant_id, user_id)?;
        validate_uuid(job_id, "schedule ID")?;
        let row = sqlx::query(
            "SELECT * FROM scheduled_jobs WHERE app_id = ? AND tenant_id = ? AND user_id = ? AND id = ?",
        )
        .bind(app_id)
        .bind(tenant_id)
        .bind(user_id)
        .bind(job_id)
        .fetch_optional(&self.pool)
        .await?;
        row.map(scheduled_job_from_row).transpose()
    }

    pub async fn set_status_for_scope(
        &self,
        scope: ScheduleScope<'_>,
        job_id: &str,
        expected_version: i64,
        status: ScheduledJobStatus,
        now: DateTime<Utc>,
    ) -> anyhow::Result<Option<ScheduledJob>> {
        if self
            .get_job_for_scope(scope.app_id, scope.tenant_id, scope.user_id, job_id)
            .await?
            .is_none()
        {
            return Ok(None);
        }
        anyhow::ensure!(
            self.set_status(job_id, expected_version, status, now)
                .await?,
            "scheduled job version conflict"
        );
        self.get_job_for_scope(scope.app_id, scope.tenant_id, scope.user_id, job_id)
            .await
    }

    pub async fn claim_due(
        &self,
        now: DateTime<Utc>,
        worker: &str,
        lease: Duration,
        limit: usize,
    ) -> anyhow::Result<Vec<ScheduledClaim>> {
        anyhow::ensure!(!worker.trim().is_empty(), "scheduler worker is required");
        anyhow::ensure!(
            (1..=100).contains(&limit),
            "scheduler claim limit is invalid"
        );
        anyhow::ensure!(
            lease > Duration::zero(),
            "scheduler claim lease must be positive"
        );
        let mut tx = self.pool.begin().await?;
        let expired = sqlx::query(
            "SELECT c.claim_id, c.job_id, c.run_id, c.due_at, c.claim_until, j.app_id, j.tenant_id, j.user_id, j.payload_json FROM schedule_claims c JOIN scheduled_jobs j ON j.id = c.job_id WHERE c.status = 'claimed' AND c.claim_until <= ? ORDER BY c.due_at, c.claim_id LIMIT ?",
        )
        .bind(now.to_rfc3339())
        .bind(limit as i64)
        .fetch_all(&mut *tx)
        .await?;
        let mut claims = Vec::new();
        for row in expired {
            let claim_id: String = row.try_get("claim_id")?;
            let previous_until: String = row.try_get("claim_until")?;
            let updated = sqlx::query(
                "UPDATE schedule_claims SET claimed_by = ?, claim_until = ?, updated_at = ? WHERE claim_id = ? AND status = 'claimed' AND claim_until = ?",
            )
            .bind(worker)
            .bind((now + lease).to_rfc3339())
            .bind(now.to_rfc3339())
            .bind(&claim_id)
            .bind(previous_until)
            .execute(&mut *tx)
            .await?;
            if updated.rows_affected() == 1 {
                claims.push(ScheduledClaim {
                    claim_id,
                    job_id: row.try_get("job_id")?,
                    run_id: row.try_get("run_id")?,
                    app_id: row.try_get("app_id")?,
                    tenant_id: row.try_get("tenant_id")?,
                    user_id: row.try_get("user_id")?,
                    due_at: DateTime::parse_from_rfc3339(row.try_get("due_at")?)?
                        .with_timezone(&Utc),
                    claimed_by: worker.to_string(),
                    claim_until: now + lease,
                    payload: serde_json::from_str(row.try_get("payload_json")?)?,
                });
            }
        }
        if claims.len() >= limit {
            tx.commit().await?;
            return Ok(claims);
        }
        let rows = sqlx::query(
            "SELECT id, app_id, tenant_id, user_id, schedule_json, misfire_json, payload_json, next_run_at FROM scheduled_jobs WHERE status = 'active' AND next_run_at <= ? ORDER BY next_run_at, id LIMIT ?",
        )
        .bind(now.to_rfc3339())
        .bind((limit - claims.len()) as i64)
        .fetch_all(&mut *tx)
        .await?;
        for row in rows {
            let job_id: String = row.try_get("id")?;
            let schedule: ScheduleSpec = serde_json::from_str(row.try_get("schedule_json")?)?;
            let misfire: MisfirePolicy = serde_json::from_str(row.try_get("misfire_json")?)?;
            let payload: Value = serde_json::from_str(row.try_get("payload_json")?)?;
            let next_run_at: String = row.try_get("next_run_at")?;
            let due = DateTime::parse_from_rfc3339(&next_run_at)?.with_timezone(&Utc);
            let due_occurrences = due_occurrences(&schedule, &misfire, due, now)?;
            for due_at in due_occurrences {
                let claim = ScheduledClaim {
                    claim_id: Uuid::new_v4().to_string(),
                    job_id: job_id.clone(),
                    run_id: format!("scheduled:{job_id}:{}", due_at.timestamp_micros()),
                    app_id: row.try_get("app_id")?,
                    tenant_id: row.try_get("tenant_id")?,
                    user_id: row.try_get("user_id")?,
                    due_at,
                    claimed_by: worker.to_string(),
                    claim_until: now + lease,
                    payload: payload.clone(),
                };
                let inserted = sqlx::query(
                    "INSERT OR IGNORE INTO schedule_claims(claim_id, job_id, run_id, due_at, claimed_by, claim_until, status, created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?, 'claimed', ?, ?)",
                )
                .bind(&claim.claim_id)
                .bind(&claim.job_id)
                .bind(&claim.run_id)
                .bind(claim.due_at.to_rfc3339())
                .bind(&claim.claimed_by)
                .bind(claim.claim_until.to_rfc3339())
                .bind(now.to_rfc3339())
                .bind(now.to_rfc3339())
                .execute(&mut *tx)
                .await?;
                if inserted.rows_affected() == 1 {
                    claims.push(claim);
                }
            }
            let future = advance_past(&schedule, due, now)?;
            let status = if future.is_some() {
                "active"
            } else {
                "completed"
            };
            sqlx::query(
                "UPDATE scheduled_jobs SET next_run_at = ?, status = ?, version = version + 1, updated_at = ? WHERE id = ? AND next_run_at = ?",
            )
            .bind(future.map(|value| value.to_rfc3339()))
            .bind(status)
            .bind(now.to_rfc3339())
            .bind(&job_id)
            .bind(next_run_at)
            .execute(&mut *tx)
            .await?;
        }
        tx.commit().await?;
        Ok(claims)
    }

    pub async fn finish_claim(
        &self,
        claim_id: &str,
        succeeded: bool,
        result: Value,
        now: DateTime<Utc>,
    ) -> anyhow::Result<bool> {
        self.finish_claim_inner(claim_id, None, succeeded, result, now)
            .await
    }

    pub async fn finish_claim_for_worker(
        &self,
        claim_id: &str,
        worker: &str,
        succeeded: bool,
        result: Value,
        now: DateTime<Utc>,
    ) -> anyhow::Result<bool> {
        anyhow::ensure!(!worker.trim().is_empty(), "scheduler worker is required");
        self.finish_claim_inner(claim_id, Some(worker), succeeded, result, now)
            .await
    }

    async fn finish_claim_inner(
        &self,
        claim_id: &str,
        worker: Option<&str>,
        succeeded: bool,
        result: Value,
        now: DateTime<Utc>,
    ) -> anyhow::Result<bool> {
        let status = if succeeded { "succeeded" } else { "failed" };
        let updated = if let Some(worker) = worker {
            sqlx::query(
                "UPDATE schedule_claims SET status = ?, result_json = ?, updated_at = ? WHERE claim_id = ? AND status = 'claimed' AND claimed_by = ?",
            )
            .bind(status)
            .bind(serde_json::to_string(&result)?)
            .bind(now.to_rfc3339())
            .bind(claim_id)
            .bind(worker)
            .execute(&self.pool)
            .await?
        } else {
            sqlx::query(
                "UPDATE schedule_claims SET status = ?, result_json = ?, updated_at = ? WHERE claim_id = ? AND status = 'claimed'",
            )
            .bind(status)
            .bind(serde_json::to_string(&result)?)
            .bind(now.to_rfc3339())
            .bind(claim_id)
            .execute(&self.pool)
            .await?
        };
        Ok(updated.rows_affected() == 1)
    }

    pub async fn close(&self) {
        self.pool.close().await;
    }
}

fn validate_request(request: &ScheduledJobRequest) -> anyhow::Result<()> {
    for value in [
        &request.app_id,
        &request.tenant_id,
        &request.user_id,
        &request.name,
    ] {
        anyhow::ensure!(
            !value.trim().is_empty(),
            "scheduled job identity is required"
        );
        anyhow::ensure!(value.len() <= 255, "scheduled job identity is too long");
    }
    anyhow::ensure!(
        serde_json::to_vec(&request.payload)?.len() <= 64 * 1024,
        "scheduled job payload exceeds limit"
    );
    if let MisfirePolicy::CatchUp { max_runs } = request.misfire {
        anyhow::ensure!(
            (1..=100).contains(&max_runs),
            "catch-up run limit is invalid"
        );
    }
    request.schedule.validate()
}

fn validate_scope(app_id: &str, tenant_id: &str, user_id: &str) -> anyhow::Result<()> {
    for value in [app_id, tenant_id, user_id] {
        anyhow::ensure!(!value.trim().is_empty(), "schedule scope is required");
        anyhow::ensure!(value.len() <= 255, "schedule scope is too long");
    }
    Ok(())
}

fn validate_uuid(value: &str, label: &str) -> anyhow::Result<()> {
    anyhow::ensure!(Uuid::parse_str(value).is_ok(), "{label} is invalid");
    Ok(())
}

fn validate_idempotency_key(value: &str) -> anyhow::Result<()> {
    anyhow::ensure!(
        !value.trim().is_empty(),
        "schedule idempotency key is required"
    );
    anyhow::ensure!(value.len() <= 512, "schedule idempotency key is too long");
    Ok(())
}

fn scheduled_job_from_row(row: sqlx::sqlite::SqliteRow) -> anyhow::Result<ScheduledJob> {
    let status: String = row.try_get("status")?;
    let next_run_at: Option<String> = row.try_get("next_run_at")?;
    Ok(ScheduledJob {
        id: row.try_get("id")?,
        request: ScheduledJobRequest {
            app_id: row.try_get("app_id")?,
            tenant_id: row.try_get("tenant_id")?,
            user_id: row.try_get("user_id")?,
            name: row.try_get("name")?,
            schedule: serde_json::from_str(row.try_get("schedule_json")?)?,
            misfire: serde_json::from_str(row.try_get("misfire_json")?)?,
            payload: serde_json::from_str(row.try_get("payload_json")?)?,
        },
        status: match status.as_str() {
            "active" => ScheduledJobStatus::Active,
            "paused" => ScheduledJobStatus::Paused,
            "completed" => ScheduledJobStatus::Completed,
            "cancelled" => ScheduledJobStatus::Cancelled,
            _ => anyhow::bail!("invalid scheduled job status"),
        },
        next_run_at: next_run_at
            .map(|value| DateTime::parse_from_rfc3339(&value).map(|time| time.with_timezone(&Utc)))
            .transpose()?,
        version: row.try_get("version")?,
    })
}

fn due_occurrences(
    schedule: &ScheduleSpec,
    misfire: &MisfirePolicy,
    first_due: DateTime<Utc>,
    now: DateTime<Utc>,
) -> anyhow::Result<Vec<DateTime<Utc>>> {
    match misfire {
        MisfirePolicy::Skip { grace_seconds } => {
            let late = now.signed_duration_since(first_due).num_seconds().max(0) as u64;
            Ok((late <= *grace_seconds)
                .then_some(first_due)
                .into_iter()
                .collect())
        }
        MisfirePolicy::FireOnce => Ok(vec![first_due]),
        MisfirePolicy::CatchUp { max_runs } => {
            let mut occurrences = Vec::new();
            let mut due = Some(first_due);
            while let Some(value) = due
                && value <= now
                && occurrences.len() < *max_runs as usize
            {
                occurrences.push(value);
                due = schedule.next_after(value)?;
            }
            Ok(occurrences)
        }
    }
}

fn advance_past(
    schedule: &ScheduleSpec,
    first_due: DateTime<Utc>,
    now: DateTime<Utc>,
) -> anyhow::Result<Option<DateTime<Utc>>> {
    let mut next = schedule.next_after(first_due)?;
    let mut guard = 0usize;
    while next.is_some_and(|value| value <= now) {
        next = schedule.next_after(next.expect("checked above"))?;
        guard += 1;
        anyhow::ensure!(
            guard <= 100_000,
            "schedule produced too many missed occurrences"
        );
    }
    Ok(next)
}

fn parse_timezone(value: &str) -> anyhow::Result<Tz> {
    value
        .parse()
        .map_err(|_| anyhow::anyhow!("invalid schedule timezone: {value}"))
}

#[derive(Clone, Copy)]
enum RRuleFrequency {
    Daily,
    Weekly,
}

struct ParsedRRule {
    frequency: RRuleFrequency,
    interval: i64,
    hour: Option<u32>,
    minute: Option<u32>,
    second: Option<u32>,
}

fn parse_rrule(rule: &str) -> anyhow::Result<ParsedRRule> {
    let mut values = std::collections::BTreeMap::new();
    for item in rule.trim().trim_start_matches("RRULE:").split(';') {
        let (key, value) = item
            .split_once('=')
            .ok_or_else(|| anyhow::anyhow!("invalid RRULE field"))?;
        values.insert(key.to_ascii_uppercase(), value.to_ascii_uppercase());
    }
    let frequency = match values.get("FREQ").map(String::as_str) {
        Some("DAILY") => RRuleFrequency::Daily,
        Some("WEEKLY") => RRuleFrequency::Weekly,
        _ => anyhow::bail!("only DAILY and WEEKLY RRULE frequencies are supported"),
    };
    let interval = values
        .get("INTERVAL")
        .map(|value| value.parse::<i64>())
        .transpose()?
        .unwrap_or(1);
    anyhow::ensure!((1..=366).contains(&interval), "RRULE interval is invalid");
    let parse_component = |name: &str, maximum: u32| -> anyhow::Result<Option<u32>> {
        let value = values
            .get(name)
            .map(|value| value.parse::<u32>())
            .transpose()?;
        anyhow::ensure!(
            value.is_none_or(|value| value <= maximum),
            "RRULE {name} is invalid"
        );
        Ok(value)
    };
    Ok(ParsedRRule {
        frequency,
        interval,
        hour: parse_component("BYHOUR", 23)?,
        minute: parse_component("BYMINUTE", 59)?,
        second: parse_component("BYSECOND", 59)?,
    })
}

fn next_rrule_after(
    rule: &str,
    timezone: Tz,
    start: DateTime<Utc>,
    after: DateTime<Utc>,
) -> anyhow::Result<Option<DateTime<Utc>>> {
    let parsed = parse_rrule(rule)?;
    let start_local = start.with_timezone(&timezone);
    let step_days = match parsed.frequency {
        RRuleFrequency::Daily => parsed.interval,
        RRuleFrequency::Weekly => parsed.interval * 7,
    };
    for step in 0..100_000i64 {
        let date = start_local.date_naive() + Duration::days(step.saturating_mul(step_days));
        let hour = parsed.hour.unwrap_or(start_local.hour());
        let minute = parsed.minute.unwrap_or(start_local.minute());
        let second = parsed.second.unwrap_or(start_local.second());
        let candidate = timezone
            .with_ymd_and_hms(date.year(), date.month(), date.day(), hour, minute, second)
            .earliest();
        if let Some(candidate) = candidate {
            let candidate = candidate.with_timezone(&Utc);
            if candidate >= start && candidate > after {
                return Ok(Some(candidate));
            }
        }
    }
    Ok(None)
}

#[cfg(test)]
#[path = "scheduler_tests.rs"]
mod tests;
