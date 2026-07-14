use crate::tasks::{
    TaskContent, TaskError, TaskPage, TaskProvider, TaskQuery, TaskRecord, TaskResult, TaskScope,
    TaskStatus, content_fingerprint, filter_and_page,
};
use async_trait::async_trait;
use chrono::{DateTime, Utc};
use sqlx::{Row, Sqlite, SqlitePool, Transaction};
use uuid::Uuid;

#[derive(Clone)]
pub struct SqliteTaskProvider {
    pool: SqlitePool,
}

impl SqliteTaskProvider {
    pub fn from_pool(pool: SqlitePool) -> Self {
        Self { pool }
    }

    pub fn pool(&self) -> &SqlitePool {
        &self.pool
    }
}

#[async_trait]
impl TaskProvider for SqliteTaskProvider {
    async fn initialize(&self) -> TaskResult<()> {
        sqlx::query(
            r#"
            CREATE TABLE IF NOT EXISTS foundation_tasks (
              id TEXT PRIMARY KEY,
              app_id TEXT NOT NULL,
              tenant_id TEXT NOT NULL,
              user_id TEXT NOT NULL,
              content_json TEXT NOT NULL,
              status TEXT NOT NULL,
              version INTEGER NOT NULL,
              created_at TEXT NOT NULL,
              updated_at TEXT NOT NULL,
              completed_at TEXT,
              UNIQUE(app_id, tenant_id, user_id, id)
            );
            CREATE INDEX IF NOT EXISTS foundation_tasks_scope_due
              ON foundation_tasks(app_id, tenant_id, user_id, status, updated_at, id);
            CREATE TABLE IF NOT EXISTS foundation_task_idempotency (
              app_id TEXT NOT NULL,
              tenant_id TEXT NOT NULL,
              user_id TEXT NOT NULL,
              idempotency_key TEXT NOT NULL,
              request_sha256 TEXT NOT NULL,
              task_id TEXT NOT NULL,
              created_at TEXT NOT NULL,
              PRIMARY KEY(app_id, tenant_id, user_id, idempotency_key),
              FOREIGN KEY(task_id) REFERENCES foundation_tasks(id) ON DELETE CASCADE
            );
            "#,
        )
        .execute(&self.pool)
        .await
        .map_err(unavailable)?;
        Ok(())
    }

    async fn list(&self, scope: &TaskScope, query: TaskQuery) -> TaskResult<TaskPage> {
        scope.validate()?;
        let rows = sqlx::query(
            r#"
            SELECT id, content_json, status, version, created_at, updated_at, completed_at
            FROM foundation_tasks
            WHERE app_id = ? AND tenant_id = ? AND user_id = ?
            "#,
        )
        .bind(&scope.app_id)
        .bind(&scope.tenant_id)
        .bind(&scope.user_id)
        .fetch_all(&self.pool)
        .await
        .map_err(unavailable)?;
        let tasks = rows
            .iter()
            .map(decode_task)
            .collect::<TaskResult<Vec<_>>>()?;
        filter_and_page(tasks, query)
    }

    async fn get(&self, scope: &TaskScope, task_id: &str) -> TaskResult<Option<TaskRecord>> {
        scope.validate()?;
        validate_uuid(task_id)?;
        let row = sqlx::query(
            r#"
            SELECT id, content_json, status, version, created_at, updated_at, completed_at
            FROM foundation_tasks
            WHERE app_id = ? AND tenant_id = ? AND user_id = ? AND id = ?
            "#,
        )
        .bind(&scope.app_id)
        .bind(&scope.tenant_id)
        .bind(&scope.user_id)
        .bind(task_id)
        .fetch_optional(&self.pool)
        .await
        .map_err(unavailable)?;
        row.as_ref().map(decode_task).transpose()
    }

    async fn create(
        &self,
        scope: &TaskScope,
        content: TaskContent,
        idempotency_key: &str,
    ) -> TaskResult<TaskRecord> {
        scope.validate()?;
        content.validate()?;
        validate_idempotency_key(idempotency_key)?;
        let request_sha256 = content_fingerprint(&content)?;
        let mut tx = self.pool.begin().await.map_err(unavailable)?;
        if let Some(row) = sqlx::query(
            r#"
            SELECT task_id, request_sha256
            FROM foundation_task_idempotency
            WHERE app_id = ? AND tenant_id = ? AND user_id = ? AND idempotency_key = ?
            "#,
        )
        .bind(&scope.app_id)
        .bind(&scope.tenant_id)
        .bind(&scope.user_id)
        .bind(idempotency_key)
        .fetch_optional(&mut *tx)
        .await
        .map_err(unavailable)?
        {
            let existing_hash: String = row.get("request_sha256");
            if existing_hash != request_sha256 {
                return Err(TaskError::IdempotencyConflict);
            }
            let task_id: String = row.get("task_id");
            return load_task(&mut tx, scope, &task_id)
                .await?
                .ok_or(TaskError::Unavailable);
        }

        let now = Utc::now();
        let task = TaskRecord {
            id: Uuid::new_v4().to_string(),
            content,
            status: TaskStatus::Open,
            version: 1,
            created_at: now,
            updated_at: now,
            completed_at: None,
        };
        insert_task(&mut tx, scope, &task).await?;
        sqlx::query(
            r#"
            INSERT INTO foundation_task_idempotency (
              app_id, tenant_id, user_id, idempotency_key, request_sha256, task_id, created_at
            ) VALUES (?, ?, ?, ?, ?, ?, ?)
            "#,
        )
        .bind(&scope.app_id)
        .bind(&scope.tenant_id)
        .bind(&scope.user_id)
        .bind(idempotency_key)
        .bind(request_sha256)
        .bind(&task.id)
        .bind(now.to_rfc3339())
        .execute(&mut *tx)
        .await
        .map_err(unavailable)?;
        tx.commit().await.map_err(unavailable)?;
        Ok(task)
    }

    async fn update(
        &self,
        scope: &TaskScope,
        task_id: &str,
        expected_version: u64,
        content: TaskContent,
    ) -> TaskResult<TaskRecord> {
        scope.validate()?;
        validate_uuid(task_id)?;
        content.validate()?;
        let mut tx = self.pool.begin().await.map_err(unavailable)?;
        let mut task = task_for_mutation(&mut tx, scope, task_id, expected_version).await?;
        task.content = content;
        task.version += 1;
        task.updated_at = Utc::now();
        persist_task(&mut tx, scope, &task).await?;
        tx.commit().await.map_err(unavailable)?;
        Ok(task)
    }

    async fn set_status(
        &self,
        scope: &TaskScope,
        task_id: &str,
        expected_version: u64,
        status: TaskStatus,
    ) -> TaskResult<TaskRecord> {
        scope.validate()?;
        validate_uuid(task_id)?;
        let mut tx = self.pool.begin().await.map_err(unavailable)?;
        let mut task = task_for_mutation(&mut tx, scope, task_id, expected_version).await?;
        let now = Utc::now();
        task.status = status;
        task.completed_at = (status == TaskStatus::Completed).then_some(now);
        task.version += 1;
        task.updated_at = now;
        persist_task(&mut tx, scope, &task).await?;
        tx.commit().await.map_err(unavailable)?;
        Ok(task)
    }

    async fn delete(
        &self,
        scope: &TaskScope,
        task_id: &str,
        expected_version: u64,
    ) -> TaskResult<bool> {
        scope.validate()?;
        validate_uuid(task_id)?;
        let mut tx = self.pool.begin().await.map_err(unavailable)?;
        task_for_mutation(&mut tx, scope, task_id, expected_version).await?;
        let deleted = sqlx::query(
            "DELETE FROM foundation_tasks WHERE app_id = ? AND tenant_id = ? AND user_id = ? AND id = ?",
        )
        .bind(&scope.app_id)
        .bind(&scope.tenant_id)
        .bind(&scope.user_id)
        .bind(task_id)
        .execute(&mut *tx)
        .await
        .map_err(unavailable)?
        .rows_affected();
        sqlx::query(
            "DELETE FROM foundation_task_idempotency WHERE app_id = ? AND tenant_id = ? AND user_id = ? AND task_id = ?",
        )
        .bind(&scope.app_id)
        .bind(&scope.tenant_id)
        .bind(&scope.user_id)
        .bind(task_id)
        .execute(&mut *tx)
        .await
        .map_err(unavailable)?;
        tx.commit().await.map_err(unavailable)?;
        Ok(deleted == 1)
    }
}

async fn insert_task(
    tx: &mut Transaction<'_, Sqlite>,
    scope: &TaskScope,
    task: &TaskRecord,
) -> TaskResult<()> {
    sqlx::query(
        r#"
        INSERT INTO foundation_tasks (
          id, app_id, tenant_id, user_id, content_json, status, version,
          created_at, updated_at, completed_at
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        "#,
    )
    .bind(&task.id)
    .bind(&scope.app_id)
    .bind(&scope.tenant_id)
    .bind(&scope.user_id)
    .bind(encode_content(&task.content)?)
    .bind(status_name(task.status))
    .bind(task.version as i64)
    .bind(task.created_at.to_rfc3339())
    .bind(task.updated_at.to_rfc3339())
    .bind(task.completed_at.map(|value| value.to_rfc3339()))
    .execute(&mut **tx)
    .await
    .map_err(unavailable)?;
    Ok(())
}

async fn persist_task(
    tx: &mut Transaction<'_, Sqlite>,
    scope: &TaskScope,
    task: &TaskRecord,
) -> TaskResult<()> {
    let updated = sqlx::query(
        r#"
        UPDATE foundation_tasks
        SET content_json = ?, status = ?, version = ?, updated_at = ?, completed_at = ?
        WHERE app_id = ? AND tenant_id = ? AND user_id = ? AND id = ?
        "#,
    )
    .bind(encode_content(&task.content)?)
    .bind(status_name(task.status))
    .bind(task.version as i64)
    .bind(task.updated_at.to_rfc3339())
    .bind(task.completed_at.map(|value| value.to_rfc3339()))
    .bind(&scope.app_id)
    .bind(&scope.tenant_id)
    .bind(&scope.user_id)
    .bind(&task.id)
    .execute(&mut **tx)
    .await
    .map_err(unavailable)?
    .rows_affected();
    if updated != 1 {
        return Err(TaskError::Unavailable);
    }
    Ok(())
}

async fn task_for_mutation(
    tx: &mut Transaction<'_, Sqlite>,
    scope: &TaskScope,
    task_id: &str,
    expected_version: u64,
) -> TaskResult<TaskRecord> {
    let task = load_task(tx, scope, task_id)
        .await?
        .ok_or(TaskError::NotFound)?;
    if task.version != expected_version {
        return Err(TaskError::VersionConflict);
    }
    Ok(task)
}

async fn load_task(
    tx: &mut Transaction<'_, Sqlite>,
    scope: &TaskScope,
    task_id: &str,
) -> TaskResult<Option<TaskRecord>> {
    let row = sqlx::query(
        r#"
        SELECT id, content_json, status, version, created_at, updated_at, completed_at
        FROM foundation_tasks
        WHERE app_id = ? AND tenant_id = ? AND user_id = ? AND id = ?
        "#,
    )
    .bind(&scope.app_id)
    .bind(&scope.tenant_id)
    .bind(&scope.user_id)
    .bind(task_id)
    .fetch_optional(&mut **tx)
    .await
    .map_err(unavailable)?;
    row.as_ref().map(decode_task).transpose()
}

fn decode_task(row: &sqlx::sqlite::SqliteRow) -> TaskResult<TaskRecord> {
    let version: i64 = row.get("version");
    if version < 1 {
        return Err(TaskError::Unavailable);
    }
    Ok(TaskRecord {
        id: row.get("id"),
        content: serde_json::from_str(row.get("content_json"))
            .map_err(|_| TaskError::Unavailable)?,
        status: parse_status(row.get("status"))?,
        version: version as u64,
        created_at: parse_time(row.get("created_at"))?,
        updated_at: parse_time(row.get("updated_at"))?,
        completed_at: row
            .get::<Option<String>, _>("completed_at")
            .map(|value| parse_time(&value))
            .transpose()?,
    })
}

fn encode_content(content: &TaskContent) -> TaskResult<String> {
    serde_json::to_string(content).map_err(|_| TaskError::Unavailable)
}

fn parse_time(value: &str) -> TaskResult<DateTime<Utc>> {
    value.parse().map_err(|_| TaskError::Unavailable)
}

fn status_name(status: TaskStatus) -> &'static str {
    match status {
        TaskStatus::Open => "open",
        TaskStatus::Completed => "completed",
        TaskStatus::Cancelled => "cancelled",
    }
}

fn parse_status(value: &str) -> TaskResult<TaskStatus> {
    match value {
        "open" => Ok(TaskStatus::Open),
        "completed" => Ok(TaskStatus::Completed),
        "cancelled" => Ok(TaskStatus::Cancelled),
        _ => Err(TaskError::Unavailable),
    }
}

fn validate_uuid(value: &str) -> TaskResult<()> {
    if Uuid::parse_str(value).is_err() {
        return Err(TaskError::InvalidRequest("task ID is invalid".into()));
    }
    Ok(())
}

fn validate_idempotency_key(value: &str) -> TaskResult<()> {
    if value.trim().is_empty() || value.len() > 512 {
        return Err(TaskError::InvalidRequest(
            "task idempotency key is invalid".into(),
        ));
    }
    Ok(())
}

fn unavailable(_: sqlx::Error) -> TaskError {
    TaskError::Unavailable
}

#[cfg(test)]
#[path = "task_sqlite_tests.rs"]
mod tests;
