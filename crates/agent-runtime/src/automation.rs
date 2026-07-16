use crate::scheduler::{ScheduledClaim, SchedulerStore};
use crate::storage::Storage;
use async_trait::async_trait;
use chrono::{DateTime, Datelike, Duration, TimeZone, Timelike, Utc};
use chrono_tz::Tz;
use serde::{Deserialize, Serialize};
use serde_json::Value;
use sha2::{Digest, Sha256};
use sqlx::{Row, SqlitePool};
use std::time::Duration as StdDuration;
use tokio_util::sync::CancellationToken;
use uuid::Uuid;

#[derive(Clone, Debug, Deserialize, Serialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct QuietHours {
    pub timezone: String,
    pub start_minute: u16,
    pub end_minute: u16,
}

impl QuietHours {
    pub fn validate(&self) -> anyhow::Result<()> {
        anyhow::ensure!(self.start_minute < 1440, "quiet-hours start is invalid");
        anyhow::ensure!(self.end_minute < 1440, "quiet-hours end is invalid");
        anyhow::ensure!(
            self.start_minute != self.end_minute,
            "quiet hours cannot cover the entire day"
        );
        self.timezone
            .parse::<Tz>()
            .map(|_| ())
            .map_err(|_| anyhow::anyhow!("quiet-hours timezone is invalid"))
    }

    pub fn next_allowed(&self, now: DateTime<Utc>) -> anyhow::Result<DateTime<Utc>> {
        self.validate()?;
        let timezone = self.timezone.parse::<Tz>()?;
        let local = now.with_timezone(&timezone);
        let minute = local.hour() as u16 * 60 + local.minute() as u16;
        let inside = if self.start_minute < self.end_minute {
            minute >= self.start_minute && minute < self.end_minute
        } else {
            minute >= self.start_minute || minute < self.end_minute
        };
        if !inside {
            return Ok(now);
        }
        let end_today = minute < self.end_minute;
        let date = if end_today {
            local.date_naive()
        } else {
            local.date_naive() + Duration::days(1)
        };
        let hour = u32::from(self.end_minute / 60);
        let minute = u32::from(self.end_minute % 60);
        timezone
            .with_ymd_and_hms(date.year(), date.month(), date.day(), hour, minute, 0)
            .earliest()
            .map(|value| value.with_timezone(&Utc))
            .ok_or_else(|| anyhow::anyhow!("quiet-hours boundary is invalid for timezone"))
    }
}

#[derive(Clone, Debug, Deserialize, Serialize, PartialEq)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct NotificationRequest {
    pub app_id: String,
    pub tenant_id: String,
    pub user_id: String,
    pub channel: String,
    pub title: String,
    pub body: String,
    pub dedupe_key: String,
    pub not_before: DateTime<Utc>,
    pub quiet_hours: Option<QuietHours>,
    pub data: Value,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct NotificationScope<'a> {
    pub app_id: &'a str,
    pub tenant_id: &'a str,
    pub user_id: &'a str,
}

#[derive(Clone, Copy, Debug, Deserialize, Serialize, PartialEq, Eq)]
#[serde(rename_all = "snake_case")]
pub enum NotificationStatus {
    Pending,
    Delivering,
    Delivered,
    Failed,
    Uncertain,
    Cancelled,
}

impl NotificationStatus {
    fn as_str(self) -> &'static str {
        match self {
            Self::Pending => "pending",
            Self::Delivering => "delivering",
            Self::Delivered => "delivered",
            Self::Failed => "failed",
            Self::Uncertain => "uncertain",
            Self::Cancelled => "cancelled",
        }
    }
}

#[derive(Clone, Debug, Deserialize, Serialize, PartialEq)]
pub struct NotificationRecord {
    pub notification_id: String,
    pub request: NotificationRequest,
    pub status: NotificationStatus,
    pub attempt_count: u32,
    pub delivery_id: Option<String>,
    pub last_error: Option<String>,
}

#[derive(Clone)]
pub struct NotificationStore {
    pool: SqlitePool,
}

impl NotificationStore {
    pub async fn from_storage(storage: &Storage) -> anyhow::Result<Self> {
        let store = Self {
            pool: storage.pool().clone(),
        };
        store.migrate().await?;
        Ok(store)
    }

    async fn migrate(&self) -> anyhow::Result<()> {
        sqlx::query(
            r#"CREATE TABLE IF NOT EXISTS notification_outbox (
                notification_id TEXT PRIMARY KEY,
                app_id TEXT NOT NULL,
                tenant_id TEXT NOT NULL,
                user_id TEXT NOT NULL,
                channel TEXT NOT NULL,
                title TEXT NOT NULL,
                body TEXT NOT NULL,
                dedupe_key TEXT NOT NULL,
                not_before TEXT NOT NULL,
                quiet_hours_json TEXT,
                data_json TEXT NOT NULL,
                status TEXT NOT NULL,
                attempt_count INTEGER NOT NULL,
                claim_owner TEXT,
                claim_until TEXT,
                delivery_id TEXT,
                last_error TEXT,
                created_at TEXT NOT NULL,
                updated_at TEXT NOT NULL,
                UNIQUE(app_id, tenant_id, user_id, channel, dedupe_key)
            )"#,
        )
        .execute(&self.pool)
        .await?;
        sqlx::query(
            "CREATE INDEX IF NOT EXISTS notification_due_idx ON notification_outbox(status, not_before)",
        )
        .execute(&self.pool)
        .await?;
        Ok(())
    }

    pub async fn enqueue(
        &self,
        mut request: NotificationRequest,
        now: DateTime<Utc>,
    ) -> anyhow::Result<NotificationRecord> {
        validate_notification(&request)?;
        if let Some(quiet_hours) = &request.quiet_hours {
            request.not_before = request.not_before.max(quiet_hours.next_allowed(now)?);
        }
        let notification_id = Uuid::new_v4().to_string();
        sqlx::query(
            "INSERT OR IGNORE INTO notification_outbox(notification_id, app_id, tenant_id, user_id, channel, title, body, dedupe_key, not_before, quiet_hours_json, data_json, status, attempt_count, claim_owner, claim_until, delivery_id, last_error, created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 'pending', 0, NULL, NULL, NULL, NULL, ?, ?)",
        )
        .bind(&notification_id)
        .bind(&request.app_id)
        .bind(&request.tenant_id)
        .bind(&request.user_id)
        .bind(&request.channel)
        .bind(&request.title)
        .bind(&request.body)
        .bind(&request.dedupe_key)
        .bind(request.not_before.to_rfc3339())
        .bind(request.quiet_hours.as_ref().map(serde_json::to_string).transpose()?)
        .bind(serde_json::to_string(&request.data)?)
        .bind(now.to_rfc3339())
        .bind(now.to_rfc3339())
        .execute(&self.pool)
        .await?;
        let record = self
            .get_by_key(&request)
            .await?
            .ok_or_else(|| anyhow::anyhow!("notification record was not persisted"))?;
        anyhow::ensure!(
            same_deduplicated_request(&record.request, &request),
            "notification deduplication conflict"
        );
        Ok(record)
    }

    pub async fn list_for_scope(
        &self,
        scope: NotificationScope<'_>,
        status: Option<NotificationStatus>,
        limit: usize,
    ) -> anyhow::Result<Vec<NotificationRecord>> {
        validate_notification_scope(scope.app_id, scope.tenant_id, scope.user_id)?;
        anyhow::ensure!(
            (1..=100).contains(&limit),
            "notification list limit is invalid"
        );
        let rows = if let Some(status) = status {
            sqlx::query(
                "SELECT * FROM notification_outbox WHERE app_id = ? AND tenant_id = ? AND user_id = ? AND status = ? ORDER BY not_before DESC, notification_id LIMIT ?",
            )
            .bind(scope.app_id)
            .bind(scope.tenant_id)
            .bind(scope.user_id)
            .bind(status.as_str())
            .bind(limit as i64)
            .fetch_all(&self.pool)
            .await?
        } else {
            sqlx::query(
                "SELECT * FROM notification_outbox WHERE app_id = ? AND tenant_id = ? AND user_id = ? ORDER BY not_before DESC, notification_id LIMIT ?",
            )
            .bind(scope.app_id)
            .bind(scope.tenant_id)
            .bind(scope.user_id)
            .bind(limit as i64)
            .fetch_all(&self.pool)
            .await?
        };
        rows.into_iter().map(notification_from_row).collect()
    }

    pub async fn get_for_scope(
        &self,
        scope: NotificationScope<'_>,
        notification_id: &str,
    ) -> anyhow::Result<Option<NotificationRecord>> {
        validate_notification_scope(scope.app_id, scope.tenant_id, scope.user_id)?;
        validate_uuid(notification_id, "notification ID")?;
        let row = sqlx::query(
            "SELECT * FROM notification_outbox WHERE app_id = ? AND tenant_id = ? AND user_id = ? AND notification_id = ?",
        )
        .bind(scope.app_id)
        .bind(scope.tenant_id)
        .bind(scope.user_id)
        .bind(notification_id)
        .fetch_optional(&self.pool)
        .await?;
        row.map(notification_from_row).transpose()
    }

    pub async fn cancel_for_scope(
        &self,
        scope: NotificationScope<'_>,
        notification_id: &str,
        now: DateTime<Utc>,
    ) -> anyhow::Result<Option<NotificationRecord>> {
        let Some(current) = self.get_for_scope(scope, notification_id).await? else {
            return Ok(None);
        };
        if current.status == NotificationStatus::Cancelled {
            return Ok(Some(current));
        }
        anyhow::ensure!(
            matches!(
                current.status,
                NotificationStatus::Pending | NotificationStatus::Failed
            ),
            "notification cannot be cancelled after delivery begins"
        );
        sqlx::query(
            "UPDATE notification_outbox SET status = 'cancelled', updated_at = ? WHERE app_id = ? AND tenant_id = ? AND user_id = ? AND notification_id = ? AND status IN ('pending', 'failed')",
        )
        .bind(now.to_rfc3339())
        .bind(scope.app_id)
        .bind(scope.tenant_id)
        .bind(scope.user_id)
        .bind(notification_id)
        .execute(&self.pool)
        .await?;
        self.get_for_scope(scope, notification_id).await
    }

    pub async fn claim_due(
        &self,
        worker: &str,
        now: DateTime<Utc>,
        lease: Duration,
        limit: usize,
    ) -> anyhow::Result<Vec<NotificationRecord>> {
        self.claim_due_matching(worker, None, None, now, lease, limit)
            .await
    }

    pub async fn claim_due_for_channel(
        &self,
        worker: &str,
        channel: Option<&str>,
        now: DateTime<Utc>,
        lease: Duration,
        limit: usize,
    ) -> anyhow::Result<Vec<NotificationRecord>> {
        self.claim_due_matching(worker, None, channel, now, lease, limit)
            .await
    }

    pub async fn claim_due_for_scope_and_channel(
        &self,
        worker: &str,
        scope: NotificationScope<'_>,
        channel: &str,
        now: DateTime<Utc>,
        lease: Duration,
        limit: usize,
    ) -> anyhow::Result<Vec<NotificationRecord>> {
        validate_notification_scope(scope.app_id, scope.tenant_id, scope.user_id)?;
        self.claim_due_matching(
            worker,
            Some((scope.app_id, scope.tenant_id, scope.user_id)),
            Some(channel),
            now,
            lease,
            limit,
        )
        .await
    }

    async fn claim_due_matching(
        &self,
        worker: &str,
        scope: Option<(&str, &str, &str)>,
        channel: Option<&str>,
        now: DateTime<Utc>,
        lease: Duration,
        limit: usize,
    ) -> anyhow::Result<Vec<NotificationRecord>> {
        anyhow::ensure!(!worker.trim().is_empty(), "notification worker is required");
        if let Some(channel) = channel {
            anyhow::ensure!(
                !channel.trim().is_empty(),
                "notification channel is required"
            );
            anyhow::ensure!(channel.len() <= 255, "notification channel is too long");
        }
        anyhow::ensure!(lease > Duration::zero(), "notification lease is invalid");
        anyhow::ensure!(
            (1..=100).contains(&limit),
            "notification claim limit is invalid"
        );
        let mut tx = self.pool.begin().await?;
        sqlx::query(
            "UPDATE notification_outbox SET status = 'uncertain', last_error = 'delivery lease expired; reconciliation required', claim_owner = NULL, claim_until = NULL, updated_at = ? WHERE status = 'delivering' AND claim_until <= ?",
        )
        .bind(now.to_rfc3339())
        .bind(now.to_rfc3339())
        .execute(&mut *tx)
        .await?;
        let ids: Vec<String> = match (scope, channel) {
            (Some((app_id, tenant_id, user_id)), Some(channel)) => sqlx::query_scalar(
                "SELECT notification_id FROM notification_outbox WHERE status IN ('pending', 'failed') AND app_id = ? AND tenant_id = ? AND user_id = ? AND channel = ? AND not_before <= ? ORDER BY not_before, notification_id LIMIT ?",
            )
            .bind(app_id)
            .bind(tenant_id)
            .bind(user_id)
            .bind(channel)
            .bind(now.to_rfc3339())
            .bind(limit as i64)
            .fetch_all(&mut *tx)
            .await?,
            (Some((app_id, tenant_id, user_id)), None) => sqlx::query_scalar(
                "SELECT notification_id FROM notification_outbox WHERE status IN ('pending', 'failed') AND app_id = ? AND tenant_id = ? AND user_id = ? AND not_before <= ? ORDER BY not_before, notification_id LIMIT ?",
            )
            .bind(app_id)
            .bind(tenant_id)
            .bind(user_id)
            .bind(now.to_rfc3339())
            .bind(limit as i64)
            .fetch_all(&mut *tx)
            .await?,
            (None, Some(channel)) => sqlx::query_scalar(
                "SELECT notification_id FROM notification_outbox WHERE status IN ('pending', 'failed') AND channel = ? AND not_before <= ? ORDER BY not_before, notification_id LIMIT ?",
            )
            .bind(channel)
            .bind(now.to_rfc3339())
            .bind(limit as i64)
            .fetch_all(&mut *tx)
            .await?,
            (None, None) => sqlx::query_scalar(
                "SELECT notification_id FROM notification_outbox WHERE status IN ('pending', 'failed') AND not_before <= ? ORDER BY not_before, notification_id LIMIT ?",
            )
            .bind(now.to_rfc3339())
            .bind(limit as i64)
            .fetch_all(&mut *tx)
            .await?,
        };
        let mut claimed = Vec::new();
        for id in ids {
            let updated = sqlx::query(
                "UPDATE notification_outbox SET status = 'delivering', attempt_count = attempt_count + 1, claim_owner = ?, claim_until = ?, updated_at = ? WHERE notification_id = ? AND status IN ('pending', 'failed')",
            )
            .bind(worker)
            .bind((now + lease).to_rfc3339())
            .bind(now.to_rfc3339())
            .bind(&id)
            .execute(&mut *tx)
            .await?;
            if updated.rows_affected() == 1 {
                let row =
                    sqlx::query("SELECT * FROM notification_outbox WHERE notification_id = ?")
                        .bind(id)
                        .fetch_one(&mut *tx)
                        .await?;
                claimed.push(notification_from_row(row)?);
            }
        }
        tx.commit().await?;
        Ok(claimed)
    }

    pub async fn finish(
        &self,
        notification_id: &str,
        worker: &str,
        outcome: NotificationDeliveryOutcome,
        now: DateTime<Utc>,
    ) -> anyhow::Result<bool> {
        self.finish_matching(notification_id, worker, None, outcome, now)
            .await
    }

    pub async fn finish_for_scope(
        &self,
        notification_id: &str,
        worker: &str,
        scope: NotificationScope<'_>,
        outcome: NotificationDeliveryOutcome,
        now: DateTime<Utc>,
    ) -> anyhow::Result<bool> {
        validate_notification_scope(scope.app_id, scope.tenant_id, scope.user_id)?;
        self.finish_matching(
            notification_id,
            worker,
            Some((scope.app_id, scope.tenant_id, scope.user_id)),
            outcome,
            now,
        )
        .await
    }

    async fn finish_matching(
        &self,
        notification_id: &str,
        worker: &str,
        scope: Option<(&str, &str, &str)>,
        outcome: NotificationDeliveryOutcome,
        now: DateTime<Utc>,
    ) -> anyhow::Result<bool> {
        let (status, delivery_id, error, retry_at) = match outcome {
            NotificationDeliveryOutcome::Delivered { delivery_id } => {
                (NotificationStatus::Delivered, Some(delivery_id), None, None)
            }
            NotificationDeliveryOutcome::RetryableFailure { message, retry_at } => (
                NotificationStatus::Failed,
                None,
                Some(message),
                Some(retry_at),
            ),
            NotificationDeliveryOutcome::PermanentFailure { message } => {
                (NotificationStatus::Cancelled, None, Some(message), None)
            }
            NotificationDeliveryOutcome::Uncertain { message } => {
                (NotificationStatus::Uncertain, None, Some(message), None)
            }
        };
        let retry_at = retry_at.map(|value| value.to_rfc3339());
        let updated = if let Some((app_id, tenant_id, user_id)) = scope {
            sqlx::query(
                "UPDATE notification_outbox SET status = ?, delivery_id = ?, last_error = ?, not_before = COALESCE(?, not_before), claim_owner = NULL, claim_until = NULL, updated_at = ? WHERE notification_id = ? AND app_id = ? AND tenant_id = ? AND user_id = ? AND status = 'delivering' AND claim_owner = ?",
            )
            .bind(status.as_str())
            .bind(delivery_id)
            .bind(error)
            .bind(retry_at)
            .bind(now.to_rfc3339())
            .bind(notification_id)
            .bind(app_id)
            .bind(tenant_id)
            .bind(user_id)
            .bind(worker)
            .execute(&self.pool)
            .await?
        } else {
            sqlx::query(
                "UPDATE notification_outbox SET status = ?, delivery_id = ?, last_error = ?, not_before = COALESCE(?, not_before), claim_owner = NULL, claim_until = NULL, updated_at = ? WHERE notification_id = ? AND status = 'delivering' AND claim_owner = ?",
            )
            .bind(status.as_str())
            .bind(delivery_id)
            .bind(error)
            .bind(retry_at)
            .bind(now.to_rfc3339())
            .bind(notification_id)
            .bind(worker)
            .execute(&self.pool)
            .await?
        };
        Ok(updated.rows_affected() == 1)
    }

    async fn get_by_key(
        &self,
        request: &NotificationRequest,
    ) -> anyhow::Result<Option<NotificationRecord>> {
        let row = sqlx::query(
            "SELECT * FROM notification_outbox WHERE app_id = ? AND tenant_id = ? AND user_id = ? AND channel = ? AND dedupe_key = ?",
        )
        .bind(&request.app_id)
        .bind(&request.tenant_id)
        .bind(&request.user_id)
        .bind(&request.channel)
        .bind(&request.dedupe_key)
        .fetch_optional(&self.pool)
        .await?;
        row.map(notification_from_row).transpose()
    }
}

#[derive(Clone, Debug, Deserialize, Serialize, PartialEq)]
#[serde(tag = "kind", rename_all = "snake_case", deny_unknown_fields)]
pub enum NotificationDeliveryOutcome {
    Delivered {
        delivery_id: String,
    },
    RetryableFailure {
        message: String,
        retry_at: DateTime<Utc>,
    },
    PermanentFailure {
        message: String,
    },
    Uncertain {
        message: String,
    },
}

#[async_trait]
pub trait NotificationHost: Send + Sync {
    async fn deliver(
        &self,
        record: &NotificationRecord,
    ) -> anyhow::Result<NotificationDeliveryOutcome>;
}

#[derive(Clone, Debug, PartialEq)]
pub struct ScheduledExecution {
    pub succeeded: bool,
    pub result: Value,
    pub notifications: Vec<NotificationRequest>,
}

#[async_trait]
pub trait ScheduledRunExecutor: Send + Sync {
    async fn execute(&self, claim: &ScheduledClaim) -> anyhow::Result<ScheduledExecution>;
}

#[derive(Clone, Default)]
pub struct DeclarativeScheduledRunExecutor;

#[derive(Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
struct DeclarativeScheduledPayload {
    #[serde(default)]
    result: Value,
    #[serde(default)]
    notifications: Vec<ScheduledNotificationRequest>,
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
struct ScheduledNotificationRequest {
    channel: String,
    title: String,
    body: String,
    dedupe_key: String,
    not_before: DateTime<Utc>,
    quiet_hours: Option<QuietHours>,
    #[serde(default)]
    data: Value,
}

#[async_trait]
impl ScheduledRunExecutor for DeclarativeScheduledRunExecutor {
    async fn execute(&self, claim: &ScheduledClaim) -> anyhow::Result<ScheduledExecution> {
        let payload: DeclarativeScheduledPayload = serde_json::from_value(claim.payload.clone())?;
        Ok(ScheduledExecution {
            succeeded: true,
            result: serde_json::json!({
                "runId": claim.run_id,
                "dueAt": claim.due_at,
                "output": payload.result,
            }),
            notifications: payload
                .notifications
                .into_iter()
                .map(|notification| NotificationRequest {
                    app_id: claim.app_id.clone(),
                    tenant_id: claim.tenant_id.clone(),
                    user_id: claim.user_id.clone(),
                    channel: notification.channel,
                    title: notification.title,
                    body: notification.body,
                    dedupe_key: scheduled_notification_dedupe_key(
                        &notification.dedupe_key,
                        &claim.run_id,
                    ),
                    not_before: notification.not_before,
                    quiet_hours: notification.quiet_hours,
                    data: notification.data,
                })
                .collect(),
        })
    }
}

fn scheduled_notification_dedupe_key(seed: &str, run_id: &str) -> String {
    let mut digest = Sha256::new();
    digest.update(seed.as_bytes());
    digest.update([0]);
    digest.update(run_id.as_bytes());
    format!("scheduled:{:x}", digest.finalize())
}

pub struct SchedulerRunner<E> {
    scheduler: SchedulerStore,
    notifications: NotificationStore,
    executor: E,
    worker: String,
    lease: Duration,
}

impl<E> SchedulerRunner<E>
where
    E: ScheduledRunExecutor,
{
    pub fn new(
        scheduler: SchedulerStore,
        notifications: NotificationStore,
        executor: E,
        worker: impl Into<String>,
        lease: Duration,
    ) -> anyhow::Result<Self> {
        let worker = worker.into();
        anyhow::ensure!(!worker.trim().is_empty(), "scheduler worker is required");
        anyhow::ensure!(lease > Duration::zero(), "scheduler lease is invalid");
        Ok(Self {
            scheduler,
            notifications,
            executor,
            worker,
            lease,
        })
    }

    pub async fn tick(&self, now: DateTime<Utc>, limit: usize) -> anyhow::Result<usize> {
        let claims = self
            .scheduler
            .claim_due(now, &self.worker, self.lease, limit)
            .await?;
        let count = claims.len();
        for claim in claims {
            match self.executor.execute(&claim).await {
                Ok(execution) => {
                    let mut persisted = true;
                    for notification in execution.notifications {
                        if self
                            .notifications
                            .enqueue(notification, Utc::now())
                            .await
                            .is_err()
                        {
                            persisted = false;
                            break;
                        }
                    }
                    self.scheduler
                        .finish_claim_for_worker(
                            &claim.claim_id,
                            &self.worker,
                            execution.succeeded && persisted,
                            execution.result,
                            Utc::now(),
                        )
                        .await?;
                }
                Err(error) => {
                    tracing::warn!(?error, claim_id = %claim.claim_id, "scheduled execution failed");
                    self.scheduler
                        .finish_claim_for_worker(
                            &claim.claim_id,
                            &self.worker,
                            false,
                            serde_json::json!({"error": "scheduled execution failed"}),
                            Utc::now(),
                        )
                        .await?;
                }
            }
        }
        Ok(count)
    }

    pub async fn run_until_cancelled(
        &self,
        interval: StdDuration,
        limit: usize,
        cancellation: CancellationToken,
    ) -> anyhow::Result<()> {
        anyhow::ensure!(!interval.is_zero(), "scheduler interval is invalid");
        loop {
            tokio::select! {
                _ = cancellation.cancelled() => return Ok(()),
                _ = tokio::time::sleep(interval) => { self.tick(Utc::now(), limit).await?; }
            }
        }
    }
}

pub struct NotificationWorker<H> {
    store: NotificationStore,
    host: H,
    worker: String,
    lease: Duration,
}

impl<H> NotificationWorker<H>
where
    H: NotificationHost,
{
    pub fn new(
        store: NotificationStore,
        host: H,
        worker: impl Into<String>,
        lease: Duration,
    ) -> anyhow::Result<Self> {
        let worker = worker.into();
        anyhow::ensure!(!worker.trim().is_empty(), "notification worker is required");
        anyhow::ensure!(lease > Duration::zero(), "notification lease is invalid");
        Ok(Self {
            store,
            host,
            worker,
            lease,
        })
    }

    pub async fn tick(&self, now: DateTime<Utc>, limit: usize) -> anyhow::Result<usize> {
        let records = self
            .store
            .claim_due(&self.worker, now, self.lease, limit)
            .await?;
        let count = records.len();
        for record in records {
            let outcome = self.host.deliver(&record).await.unwrap_or_else(|error| {
                NotificationDeliveryOutcome::Uncertain {
                    message: format!("notification host failed: {error}"),
                }
            });
            self.store
                .finish(&record.notification_id, &self.worker, outcome, Utc::now())
                .await?;
        }
        Ok(count)
    }
}

fn validate_notification(request: &NotificationRequest) -> anyhow::Result<()> {
    validate_notification_scope(&request.app_id, &request.tenant_id, &request.user_id)?;
    for value in [&request.channel, &request.title, &request.dedupe_key] {
        anyhow::ensure!(!value.trim().is_empty(), "notification field is required");
        anyhow::ensure!(value.len() <= 512, "notification field is too long");
    }
    anyhow::ensure!(
        request.body.len() <= 16 * 1024,
        "notification body is too long"
    );
    anyhow::ensure!(
        serde_json::to_vec(&request.data)?.len() <= 64 * 1024,
        "notification data is too large"
    );
    if let Some(quiet_hours) = &request.quiet_hours {
        quiet_hours.validate()?;
    }
    Ok(())
}

fn validate_notification_scope(app_id: &str, tenant_id: &str, user_id: &str) -> anyhow::Result<()> {
    for value in [app_id, tenant_id, user_id] {
        anyhow::ensure!(!value.trim().is_empty(), "notification scope is required");
        anyhow::ensure!(value.len() <= 512, "notification scope is too long");
    }
    Ok(())
}

fn validate_uuid(value: &str, label: &str) -> anyhow::Result<()> {
    anyhow::ensure!(Uuid::parse_str(value).is_ok(), "{label} is invalid");
    Ok(())
}

fn same_deduplicated_request(
    existing: &NotificationRequest,
    requested: &NotificationRequest,
) -> bool {
    existing.app_id == requested.app_id
        && existing.tenant_id == requested.tenant_id
        && existing.user_id == requested.user_id
        && existing.channel == requested.channel
        && existing.title == requested.title
        && existing.body == requested.body
        && existing.dedupe_key == requested.dedupe_key
        && existing.quiet_hours == requested.quiet_hours
        && existing.data == requested.data
}

fn notification_from_row(row: sqlx::sqlite::SqliteRow) -> anyhow::Result<NotificationRecord> {
    let status: String = row.try_get("status")?;
    Ok(NotificationRecord {
        notification_id: row.try_get("notification_id")?,
        request: NotificationRequest {
            app_id: row.try_get("app_id")?,
            tenant_id: row.try_get("tenant_id")?,
            user_id: row.try_get("user_id")?,
            channel: row.try_get("channel")?,
            title: row.try_get("title")?,
            body: row.try_get("body")?,
            dedupe_key: row.try_get("dedupe_key")?,
            not_before: parse_time(row.try_get("not_before")?)?,
            quiet_hours: row
                .try_get::<Option<String>, _>("quiet_hours_json")?
                .map(|value| serde_json::from_str(&value))
                .transpose()?,
            data: serde_json::from_str(row.try_get("data_json")?)?,
        },
        status: match status.as_str() {
            "pending" => NotificationStatus::Pending,
            "delivering" => NotificationStatus::Delivering,
            "delivered" => NotificationStatus::Delivered,
            "failed" => NotificationStatus::Failed,
            "uncertain" => NotificationStatus::Uncertain,
            "cancelled" => NotificationStatus::Cancelled,
            _ => anyhow::bail!("invalid notification status"),
        },
        attempt_count: u32::try_from(row.try_get::<i64, _>("attempt_count")?)?,
        delivery_id: row.try_get("delivery_id")?,
        last_error: row.try_get("last_error")?,
    })
}

fn parse_time(value: String) -> anyhow::Result<DateTime<Utc>> {
    Ok(DateTime::parse_from_rfc3339(&value)?.with_timezone(&Utc))
}

#[cfg(test)]
#[path = "automation_tests.rs"]
mod tests;
