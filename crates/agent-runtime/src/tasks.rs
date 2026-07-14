use async_trait::async_trait;
use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};
use std::collections::{BTreeMap, HashMap};
use std::sync::{Arc, Mutex};
use thiserror::Error;
use uuid::Uuid;

pub type TaskResult<T> = Result<T, TaskError>;

#[derive(Clone, Debug, Error, PartialEq, Eq)]
pub enum TaskError {
    #[error("task request is invalid: {0}")]
    InvalidRequest(String),
    #[error("task not found")]
    NotFound,
    #[error("task version conflict")]
    VersionConflict,
    #[error("task idempotency key conflicts with another request")]
    IdempotencyConflict,
    #[error("task provider is unavailable")]
    Unavailable,
}

#[derive(Clone, Debug, Deserialize, Serialize, PartialEq, Eq, PartialOrd, Ord, Hash)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct TaskScope {
    pub app_id: String,
    pub tenant_id: String,
    pub user_id: String,
}

impl TaskScope {
    pub fn new(app_id: &str, tenant_id: &str, user_id: &str) -> TaskResult<Self> {
        let scope = Self {
            app_id: app_id.into(),
            tenant_id: tenant_id.into(),
            user_id: user_id.into(),
        };
        scope.validate()?;
        Ok(scope)
    }

    pub fn validate(&self) -> TaskResult<()> {
        for (label, value) in [
            ("app ID", &self.app_id),
            ("tenant ID", &self.tenant_id),
            ("user ID", &self.user_id),
        ] {
            ensure_valid(!value.trim().is_empty(), format!("{label} is required"))?;
            ensure_valid(value.len() <= 256, format!("{label} is too long"))?;
        }
        Ok(())
    }
}

#[derive(Clone, Copy, Debug, Deserialize, Serialize, PartialEq, Eq)]
#[serde(rename_all = "snake_case")]
pub enum TaskStatus {
    Open,
    Completed,
    Cancelled,
}

#[derive(Clone, Copy, Debug, Deserialize, Serialize, PartialEq, Eq)]
#[serde(rename_all = "snake_case")]
pub enum TaskPriority {
    Low,
    Normal,
    High,
    Urgent,
}

#[derive(Clone, Debug, Deserialize, Serialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct TaskContent {
    pub title: String,
    pub notes: Option<String>,
    pub due_at: Option<DateTime<Utc>>,
    pub timezone: Option<String>,
    pub recurrence: Option<String>,
    pub priority: TaskPriority,
    pub tags: Vec<String>,
}

impl TaskContent {
    pub fn validate(&self) -> TaskResult<()> {
        ensure_valid(!self.title.trim().is_empty(), "task title is required")?;
        ensure_valid(self.title.len() <= 1024, "task title is too long")?;
        ensure_valid(
            self.notes
                .as_ref()
                .is_none_or(|value| value.len() <= 64 * 1024),
            "task notes are too long",
        )?;
        ensure_valid(self.tags.len() <= 100, "task has too many tags")?;
        ensure_valid(
            self.tags
                .iter()
                .all(|tag| !tag.trim().is_empty() && tag.len() <= 128),
            "task tag is invalid",
        )?;
        if let Some(timezone) = &self.timezone {
            ensure_valid(timezone.len() <= 128, "task timezone is too long")?;
            timezone
                .parse::<chrono_tz::Tz>()
                .map_err(|_| invalid("task timezone is invalid"))?;
        }
        if let Some(recurrence) = &self.recurrence {
            ensure_valid(recurrence.len() <= 4096, "task recurrence is too long")?;
            ensure_valid(self.due_at.is_some(), "recurring task requires a due time")?;
        }
        Ok(())
    }
}

#[derive(Clone, Debug, Deserialize, Serialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct TaskRecord {
    pub id: String,
    pub content: TaskContent,
    pub status: TaskStatus,
    pub version: u64,
    pub created_at: DateTime<Utc>,
    pub updated_at: DateTime<Utc>,
    pub completed_at: Option<DateTime<Utc>>,
}

#[derive(Clone, Debug, Deserialize, Serialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct TaskQuery {
    pub status: Option<TaskStatus>,
    pub due_after: Option<DateTime<Utc>>,
    pub due_before: Option<DateTime<Utc>>,
    pub tag: Option<String>,
    pub text: Option<String>,
    pub cursor: Option<String>,
    pub limit: usize,
}

#[derive(Clone, Debug, Deserialize, Serialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct TaskPage {
    pub tasks: Vec<TaskRecord>,
    pub next_cursor: Option<String>,
}

#[async_trait]
pub trait TaskProvider: Send + Sync {
    async fn initialize(&self) -> TaskResult<()>;
    async fn list(&self, scope: &TaskScope, query: TaskQuery) -> TaskResult<TaskPage>;
    async fn get(&self, scope: &TaskScope, task_id: &str) -> TaskResult<Option<TaskRecord>>;
    async fn create(
        &self,
        scope: &TaskScope,
        content: TaskContent,
        idempotency_key: &str,
    ) -> TaskResult<TaskRecord>;
    async fn update(
        &self,
        scope: &TaskScope,
        task_id: &str,
        expected_version: u64,
        content: TaskContent,
    ) -> TaskResult<TaskRecord>;
    async fn set_status(
        &self,
        scope: &TaskScope,
        task_id: &str,
        expected_version: u64,
        status: TaskStatus,
    ) -> TaskResult<TaskRecord>;
    async fn delete(
        &self,
        scope: &TaskScope,
        task_id: &str,
        expected_version: u64,
    ) -> TaskResult<bool>;
}

#[derive(Clone, Default)]
pub struct FakeTaskProvider {
    state: Arc<Mutex<FakeTaskState>>,
}

#[derive(Default)]
struct FakeTaskState {
    tasks: BTreeMap<(TaskScope, String), TaskRecord>,
    idempotency: HashMap<(TaskScope, String), (String, String)>,
}

#[async_trait]
impl TaskProvider for FakeTaskProvider {
    async fn initialize(&self) -> TaskResult<()> {
        Ok(())
    }

    async fn list(&self, scope: &TaskScope, query: TaskQuery) -> TaskResult<TaskPage> {
        scope.validate()?;
        let values = self
            .state
            .lock()
            .expect("task lock poisoned")
            .tasks
            .iter()
            .filter(|((task_scope, _), _)| task_scope == scope)
            .map(|(_, task)| task.clone())
            .collect::<Vec<_>>();
        filter_and_page(values, query)
    }

    async fn get(&self, scope: &TaskScope, task_id: &str) -> TaskResult<Option<TaskRecord>> {
        scope.validate()?;
        validate_task_id(task_id)?;
        Ok(self
            .state
            .lock()
            .expect("task lock poisoned")
            .tasks
            .get(&(scope.clone(), task_id.into()))
            .cloned())
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
        let request_hash = content_fingerprint(&content)?;
        let mut state = self.state.lock().expect("task lock poisoned");
        if let Some((id, existing_hash)) = state
            .idempotency
            .get(&(scope.clone(), idempotency_key.into()))
        {
            if existing_hash != &request_hash {
                return Err(TaskError::IdempotencyConflict);
            }
            return Ok(state.tasks[&(scope.clone(), id.clone())].clone());
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
        state.idempotency.insert(
            (scope.clone(), idempotency_key.into()),
            (task.id.clone(), request_hash),
        );
        state
            .tasks
            .insert((scope.clone(), task.id.clone()), task.clone());
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
        validate_task_id(task_id)?;
        content.validate()?;
        mutate_task(&self.state, scope, task_id, expected_version, |task| {
            task.content = content
        })
    }

    async fn set_status(
        &self,
        scope: &TaskScope,
        task_id: &str,
        expected_version: u64,
        status: TaskStatus,
    ) -> TaskResult<TaskRecord> {
        scope.validate()?;
        validate_task_id(task_id)?;
        mutate_task(&self.state, scope, task_id, expected_version, |task| {
            task.status = status;
            task.completed_at = (status == TaskStatus::Completed).then(Utc::now);
        })
    }

    async fn delete(
        &self,
        scope: &TaskScope,
        task_id: &str,
        expected_version: u64,
    ) -> TaskResult<bool> {
        scope.validate()?;
        validate_task_id(task_id)?;
        let mut state = self.state.lock().expect("task lock poisoned");
        let key = (scope.clone(), task_id.into());
        let task = state.tasks.get(&key).ok_or(TaskError::NotFound)?;
        if task.version != expected_version {
            return Err(TaskError::VersionConflict);
        }
        state.tasks.remove(&key);
        state.idempotency.retain(|_, (id, _)| id != task_id);
        Ok(true)
    }
}

fn mutate_task(
    state: &Arc<Mutex<FakeTaskState>>,
    scope: &TaskScope,
    task_id: &str,
    expected_version: u64,
    mutation: impl FnOnce(&mut TaskRecord),
) -> TaskResult<TaskRecord> {
    let mut state = state.lock().expect("task lock poisoned");
    let task = state
        .tasks
        .get_mut(&(scope.clone(), task_id.into()))
        .ok_or(TaskError::NotFound)?;
    if task.version != expected_version {
        return Err(TaskError::VersionConflict);
    }
    mutation(task);
    task.version += 1;
    task.updated_at = Utc::now();
    Ok(task.clone())
}

pub(crate) fn filter_and_page(
    mut values: Vec<TaskRecord>,
    query: TaskQuery,
) -> TaskResult<TaskPage> {
    validate_query(&query)?;
    let text = query.text.as_deref().map(str::to_lowercase);
    values.retain(|task| {
        query.status.is_none_or(|status| task.status == status)
            && query
                .due_after
                .is_none_or(|due| task.content.due_at.is_some_and(|value| value >= due))
            && query
                .due_before
                .is_none_or(|due| task.content.due_at.is_some_and(|value| value <= due))
            && query
                .tag
                .as_ref()
                .is_none_or(|tag| task.content.tags.contains(tag))
            && text.as_ref().is_none_or(|text| {
                task.content.title.to_lowercase().contains(text)
                    || task
                        .content
                        .notes
                        .as_ref()
                        .is_some_and(|notes| notes.to_lowercase().contains(text))
            })
    });
    values.sort_by(|left, right| {
        left.content
            .due_at
            .cmp(&right.content.due_at)
            .then_with(|| left.id.cmp(&right.id))
    });
    if let Some(cursor) = query.cursor.as_deref() {
        let (due_at, id) = decode_cursor(cursor)?;
        values.retain(|task| (task.content.due_at, task.id.as_str()) > (due_at, id.as_str()));
    }
    let has_more = values.len() > query.limit;
    values.truncate(query.limit);
    let next_cursor = has_more
        .then(|| values.last().map(encode_cursor))
        .flatten()
        .transpose()?;
    Ok(TaskPage {
        tasks: values,
        next_cursor,
    })
}

fn validate_query(query: &TaskQuery) -> TaskResult<()> {
    ensure_valid((1..=100).contains(&query.limit), "task limit is invalid")?;
    ensure_valid(
        query.tag.as_ref().is_none_or(|value| value.len() <= 128),
        "task tag filter is too long",
    )?;
    ensure_valid(
        query.text.as_ref().is_none_or(|value| value.len() <= 4096),
        "task text filter is too long",
    )?;
    ensure_valid(
        query
            .due_after
            .zip(query.due_before)
            .is_none_or(|(after, before)| after <= before),
        "task due range is invalid",
    )
}

pub(crate) fn content_fingerprint(content: &TaskContent) -> TaskResult<String> {
    let bytes = serde_json::to_vec(content).map_err(|_| TaskError::Unavailable)?;
    Ok(hex::encode(Sha256::digest(bytes)))
}

fn encode_cursor(task: &TaskRecord) -> TaskResult<String> {
    let value = (
        task.content.due_at.map(|value| value.to_rfc3339()),
        &task.id,
    );
    serde_json::to_vec(&value)
        .map(hex::encode)
        .map_err(|_| TaskError::Unavailable)
}

fn decode_cursor(cursor: &str) -> TaskResult<(Option<DateTime<Utc>>, String)> {
    let bytes = hex::decode(cursor).map_err(|_| invalid("task cursor is invalid"))?;
    let (due_at, id): (Option<String>, String) =
        serde_json::from_slice(&bytes).map_err(|_| invalid("task cursor is invalid"))?;
    validate_task_id(&id)?;
    let due_at = due_at
        .map(|value| value.parse::<DateTime<Utc>>())
        .transpose()
        .map_err(|_| invalid("task cursor is invalid"))?;
    Ok((due_at, id))
}

fn validate_task_id(task_id: &str) -> TaskResult<()> {
    ensure_valid(Uuid::parse_str(task_id).is_ok(), "task ID is invalid")
}

fn validate_idempotency_key(key: &str) -> TaskResult<()> {
    ensure_valid(!key.trim().is_empty(), "task idempotency key is required")?;
    ensure_valid(key.len() <= 512, "task idempotency key is too long")
}

fn invalid(message: impl Into<String>) -> TaskError {
    TaskError::InvalidRequest(message.into())
}

fn ensure_valid(condition: bool, message: impl Into<String>) -> TaskResult<()> {
    condition.then_some(()).ok_or_else(|| invalid(message))
}

#[cfg(test)]
#[path = "tasks_tests.rs"]
mod tests;
