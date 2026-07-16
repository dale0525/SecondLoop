use crate::event_persistence::project_runtime_event_for_persistence;
use crate::events::RuntimeEvent;
use crate::session::{
    ConversationEventRecord, ConversationScope, ConversationSessionEventPage, ConversationTurn,
    ConversationTurnEventPage, ConversationTurnStatus, Message,
};
use crate::storage::Storage;
use chrono::{DateTime, Duration, Utc};
use sqlx::{Row, Sqlite, Transaction};
use std::str::FromStr;
use uuid::Uuid;

const RECOVERY_MESSAGE: &str = "turn interrupted by runtime restart";
pub const TURN_REQUEST_CONFLICT_MESSAGE: &str =
    "turn request identifier is already bound to different content";

#[derive(Debug, Clone, PartialEq)]
pub struct ConversationTurnStart {
    pub turn: ConversationTurn,
    pub user_message: Message,
    pub created: bool,
}

pub struct ConversationTurnCompletion<'a> {
    pub status: ConversationTurnStatus,
    pub terminal_event: &'a RuntimeEvent,
    pub assistant_content: Option<&'a str>,
    pub failure_message: Option<&'a str>,
}

impl Storage {
    pub async fn begin_scoped_turn(
        &self,
        scope: &ConversationScope,
        session_id: &str,
        request_id: &str,
        user_content: &str,
    ) -> anyhow::Result<ConversationTurnStart> {
        scope.validate()?;
        validate_request_id(request_id)?;
        anyhow::ensure!(!user_content.trim().is_empty(), "turn content is required");
        let mut tx = self.pool().begin_with("BEGIN IMMEDIATE").await?;
        ensure_scoped_session(&mut tx, scope, session_id).await?;
        if let Some(turn) = get_turn_by_request(&mut tx, scope, session_id, request_id).await? {
            let user_message = get_message(&mut tx, &turn.user_message_id).await?;
            anyhow::ensure!(
                user_message.content == user_content,
                TURN_REQUEST_CONFLICT_MESSAGE
            );
            tx.commit().await?;
            return Ok(ConversationTurnStart {
                turn,
                user_message,
                created: false,
            });
        }
        let running: i64 = sqlx::query_scalar(
            "SELECT EXISTS(SELECT 1 FROM conversation_turns WHERE session_id = ? AND status = 'running')",
        )
        .bind(session_id)
        .fetch_one(&mut *tx)
        .await?;
        anyhow::ensure!(running == 0, "session already has a running turn");

        let now = Utc::now();
        let user_message = Message {
            id: Uuid::new_v4().to_string(),
            session_id: session_id.to_string(),
            role: "user".into(),
            content: user_content.to_string(),
            created_at: now,
        };
        sqlx::query(
            "INSERT INTO messages (id, session_id, role, content, created_at) VALUES (?, ?, 'user', ?, ?)",
        )
        .bind(&user_message.id)
        .bind(session_id)
        .bind(user_content)
        .bind(now.to_rfc3339())
        .execute(&mut *tx)
        .await?;
        let turn = ConversationTurn {
            id: Uuid::new_v4().to_string(),
            session_id: session_id.to_string(),
            request_id: request_id.to_string(),
            status: ConversationTurnStatus::Running,
            user_message_id: user_message.id.clone(),
            assistant_message_id: None,
            failure_message: None,
            started_at: now,
            updated_at: now,
            finished_at: None,
        };
        sqlx::query(
            "INSERT INTO conversation_turns (id, session_id, request_id, status, user_message_id, assistant_message_id, failure_message, started_at, updated_at, finished_at) VALUES (?, ?, ?, 'running', ?, NULL, NULL, ?, ?, NULL)",
        )
        .bind(&turn.id)
        .bind(session_id)
        .bind(request_id)
        .bind(&user_message.id)
        .bind(now.to_rfc3339())
        .bind(now.to_rfc3339())
        .execute(&mut *tx)
        .await?;
        sqlx::query("UPDATE sessions SET updated_at = ? WHERE id = ?")
            .bind(now.to_rfc3339())
            .bind(session_id)
            .execute(&mut *tx)
            .await?;
        tx.commit().await?;
        Ok(ConversationTurnStart {
            turn,
            user_message,
            created: true,
        })
    }

    pub async fn get_scoped_turn(
        &self,
        scope: &ConversationScope,
        session_id: &str,
        turn_id: &str,
    ) -> anyhow::Result<Option<ConversationTurn>> {
        scope.validate()?;
        let row = sqlx::query(
            "SELECT t.* FROM conversation_turns t INNER JOIN sessions s ON s.id = t.session_id WHERE t.id = ? AND t.session_id = ? AND s.app_id = ? AND s.agent_id = ? AND s.tenant_id = ? AND s.user_id = ? AND s.device_id = ?",
        )
        .bind(turn_id)
        .bind(session_id)
        .bind(&scope.app_id)
        .bind(&scope.agent_id)
        .bind(&scope.tenant_id)
        .bind(&scope.user_id)
        .bind(&scope.device_id)
        .fetch_optional(self.pool())
        .await?;
        row.map(turn_from_row).transpose()
    }

    pub async fn list_scoped_turns(
        &self,
        scope: &ConversationScope,
        session_id: &str,
    ) -> anyhow::Result<Vec<ConversationTurn>> {
        scope.validate()?;
        let rows = sqlx::query(
            "SELECT t.* FROM conversation_turns t INNER JOIN sessions s ON s.id = t.session_id WHERE t.session_id = ? AND s.app_id = ? AND s.agent_id = ? AND s.tenant_id = ? AND s.user_id = ? AND s.device_id = ? ORDER BY t.started_at, t.id",
        )
        .bind(session_id)
        .bind(&scope.app_id)
        .bind(&scope.agent_id)
        .bind(&scope.tenant_id)
        .bind(&scope.user_id)
        .bind(&scope.device_id)
        .fetch_all(self.pool())
        .await?;
        rows.into_iter().map(turn_from_row).collect()
    }

    pub async fn append_scoped_turn_event(
        &self,
        scope: &ConversationScope,
        session_id: &str,
        turn_id: &str,
        event: &RuntimeEvent,
    ) -> anyhow::Result<Option<ConversationEventRecord>> {
        scope.validate()?;
        let mut tx = self.pool().begin_with("BEGIN IMMEDIATE").await?;
        let Some(turn) = get_turn(&mut tx, scope, session_id, turn_id).await? else {
            tx.rollback().await?;
            return Ok(None);
        };
        if turn.status.is_terminal() {
            tx.rollback().await?;
            return Ok(None);
        }
        let record = insert_turn_event(&mut tx, session_id, turn_id, event, Utc::now()).await?;
        sqlx::query("UPDATE conversation_turns SET updated_at = ? WHERE id = ?")
            .bind(record.created_at.to_rfc3339())
            .bind(turn_id)
            .execute(&mut *tx)
            .await?;
        tx.commit().await?;
        Ok(Some(record))
    }

    pub async fn finish_scoped_turn(
        &self,
        scope: &ConversationScope,
        session_id: &str,
        turn_id: &str,
        completion: ConversationTurnCompletion<'_>,
    ) -> anyhow::Result<ConversationTurn> {
        scope.validate()?;
        let ConversationTurnCompletion {
            status,
            terminal_event,
            assistant_content,
            failure_message,
        } = completion;
        anyhow::ensure!(status.is_terminal(), "turn terminal status is required");
        let mut tx = self.pool().begin_with("BEGIN IMMEDIATE").await?;
        let turn = get_turn(&mut tx, scope, session_id, turn_id)
            .await?
            .ok_or_else(|| anyhow::anyhow!("turn not found in conversation scope"))?;
        if turn.status.is_terminal() {
            tx.commit().await?;
            return Ok(turn);
        }
        let now = Utc::now();
        insert_turn_event(&mut tx, session_id, turn_id, terminal_event, now).await?;
        let assistant_message_id = match assistant_content.filter(|value| !value.is_empty()) {
            Some(content) => {
                let id = Uuid::new_v4().to_string();
                sqlx::query(
                    "INSERT INTO messages (id, session_id, role, content, created_at) VALUES (?, ?, 'assistant', ?, ?)",
                )
                .bind(&id)
                .bind(session_id)
                .bind(content)
                .bind((now + Duration::microseconds(1)).to_rfc3339())
                .execute(&mut *tx)
                .await?;
                Some(id)
            }
            None => None,
        };
        sqlx::query(
            "UPDATE conversation_turns SET status = ?, assistant_message_id = ?, failure_message = ?, updated_at = ?, finished_at = ? WHERE id = ? AND status = 'running'",
        )
        .bind(status.as_str())
        .bind(&assistant_message_id)
        .bind(failure_message)
        .bind(now.to_rfc3339())
        .bind(now.to_rfc3339())
        .bind(turn_id)
        .execute(&mut *tx)
        .await?;
        sqlx::query("UPDATE sessions SET updated_at = ? WHERE id = ?")
            .bind(now.to_rfc3339())
            .bind(session_id)
            .execute(&mut *tx)
            .await?;
        let result = get_turn(&mut tx, scope, session_id, turn_id)
            .await?
            .ok_or_else(|| anyhow::anyhow!("turn disappeared during finalization"))?;
        tx.commit().await?;
        Ok(result)
    }

    pub async fn list_scoped_turn_events_page(
        &self,
        scope: &ConversationScope,
        session_id: &str,
        turn_id: &str,
        after: i64,
        limit: usize,
    ) -> anyhow::Result<Option<ConversationTurnEventPage>> {
        scope.validate()?;
        anyhow::ensure!(after >= -1, "turn event cursor is invalid");
        anyhow::ensure!((1..=100).contains(&limit), "turn event limit is invalid");
        let Some(turn) = self.get_scoped_turn(scope, session_id, turn_id).await? else {
            return Ok(None);
        };
        let rows = sqlx::query(
            "SELECT e.id, e.session_id, e.turn_id, e.event_index, e.kind, e.payload_json, e.created_at FROM conversation_events e WHERE e.session_id = ? AND e.turn_id = ? AND e.event_index > ? ORDER BY e.event_index LIMIT ?",
        )
        .bind(session_id)
        .bind(turn_id)
        .bind(after)
        .bind(i64::try_from(limit + 1)?)
        .fetch_all(self.pool())
        .await?;
        let mut events = rows
            .into_iter()
            .map(event_from_row)
            .collect::<anyhow::Result<Vec<_>>>()?;
        let has_more = events.len() > limit;
        events.truncate(limit);
        let next_cursor = events.last().map_or(after, |event| event.event_index);
        Ok(Some(ConversationTurnEventPage {
            turn,
            events,
            next_cursor,
            has_more,
        }))
    }

    pub async fn list_scoped_session_events_page(
        &self,
        scope: &ConversationScope,
        session_id: &str,
        after: i64,
        limit: usize,
    ) -> anyhow::Result<Option<ConversationSessionEventPage>> {
        scope.validate()?;
        anyhow::ensure!(after >= -1, "session event cursor is invalid");
        anyhow::ensure!((1..=100).contains(&limit), "session event limit is invalid");
        if self.get_scoped_session(scope, session_id).await?.is_none() {
            return Ok(None);
        }
        let rows = sqlx::query(
            "SELECT e.id, e.session_id, e.turn_id, e.event_index, e.kind, e.payload_json, e.created_at FROM conversation_events e WHERE e.session_id = ? AND e.event_index > ? ORDER BY e.event_index LIMIT ?",
        )
        .bind(session_id)
        .bind(after)
        .bind(i64::try_from(limit + 1)?)
        .fetch_all(self.pool())
        .await?;
        let mut events = rows
            .into_iter()
            .map(event_from_row)
            .collect::<anyhow::Result<Vec<_>>>()?;
        let has_more = events.len() > limit;
        events.truncate(limit);
        let next_cursor = events.last().map_or(after, |event| event.event_index);
        Ok(Some(ConversationSessionEventPage {
            events,
            next_cursor,
            has_more,
        }))
    }

    pub(crate) async fn recover_interrupted_turns(&self) -> anyhow::Result<usize> {
        let rows =
            sqlx::query("SELECT id, session_id FROM conversation_turns WHERE status = 'running'")
                .fetch_all(self.pool())
                .await?;
        let mut recovered = 0usize;
        for row in rows {
            let turn_id: String = row.try_get("id")?;
            let session_id: String = row.try_get("session_id")?;
            let mut tx = self.pool().begin_with("BEGIN IMMEDIATE").await?;
            let status: Option<String> =
                sqlx::query_scalar("SELECT status FROM conversation_turns WHERE id = ?")
                    .bind(&turn_id)
                    .fetch_optional(&mut *tx)
                    .await?;
            if status.as_deref() != Some("running") {
                tx.rollback().await?;
                continue;
            }
            let event = RuntimeEvent::TurnFailed {
                turn_id: turn_id.clone(),
                message: RECOVERY_MESSAGE.into(),
            };
            let now = Utc::now();
            insert_turn_event(&mut tx, &session_id, &turn_id, &event, now).await?;
            sqlx::query(
                "UPDATE conversation_turns SET status = 'interrupted', failure_message = ?, updated_at = ?, finished_at = ? WHERE id = ? AND status = 'running'",
            )
            .bind(RECOVERY_MESSAGE)
            .bind(now.to_rfc3339())
            .bind(now.to_rfc3339())
            .bind(&turn_id)
            .execute(&mut *tx)
            .await?;
            sqlx::query("UPDATE sessions SET updated_at = ? WHERE id = ?")
                .bind(now.to_rfc3339())
                .bind(&session_id)
                .execute(&mut *tx)
                .await?;
            tx.commit().await?;
            recovered += 1;
        }
        Ok(recovered)
    }
}

async fn ensure_scoped_session(
    tx: &mut Transaction<'_, Sqlite>,
    scope: &ConversationScope,
    session_id: &str,
) -> anyhow::Result<()> {
    let exists: i64 = sqlx::query_scalar(
        "SELECT EXISTS(SELECT 1 FROM sessions WHERE id = ? AND app_id = ? AND agent_id = ? AND tenant_id = ? AND user_id = ? AND device_id = ?)",
    )
    .bind(session_id)
    .bind(&scope.app_id)
    .bind(&scope.agent_id)
    .bind(&scope.tenant_id)
    .bind(&scope.user_id)
    .bind(&scope.device_id)
    .fetch_one(&mut **tx)
    .await?;
    anyhow::ensure!(exists != 0, "session not found in conversation scope");
    Ok(())
}

async fn get_turn(
    tx: &mut Transaction<'_, Sqlite>,
    scope: &ConversationScope,
    session_id: &str,
    turn_id: &str,
) -> anyhow::Result<Option<ConversationTurn>> {
    let row = sqlx::query(
        "SELECT t.* FROM conversation_turns t INNER JOIN sessions s ON s.id = t.session_id WHERE t.id = ? AND t.session_id = ? AND s.app_id = ? AND s.agent_id = ? AND s.tenant_id = ? AND s.user_id = ? AND s.device_id = ?",
    )
    .bind(turn_id)
    .bind(session_id)
    .bind(&scope.app_id)
    .bind(&scope.agent_id)
    .bind(&scope.tenant_id)
    .bind(&scope.user_id)
    .bind(&scope.device_id)
    .fetch_optional(&mut **tx)
    .await?;
    row.map(turn_from_row).transpose()
}

async fn get_turn_by_request(
    tx: &mut Transaction<'_, Sqlite>,
    scope: &ConversationScope,
    session_id: &str,
    request_id: &str,
) -> anyhow::Result<Option<ConversationTurn>> {
    let row = sqlx::query(
        "SELECT t.* FROM conversation_turns t INNER JOIN sessions s ON s.id = t.session_id WHERE t.session_id = ? AND t.request_id = ? AND s.app_id = ? AND s.agent_id = ? AND s.tenant_id = ? AND s.user_id = ? AND s.device_id = ?",
    )
    .bind(session_id)
    .bind(request_id)
    .bind(&scope.app_id)
    .bind(&scope.agent_id)
    .bind(&scope.tenant_id)
    .bind(&scope.user_id)
    .bind(&scope.device_id)
    .fetch_optional(&mut **tx)
    .await?;
    row.map(turn_from_row).transpose()
}

async fn get_message(
    tx: &mut Transaction<'_, Sqlite>,
    message_id: &str,
) -> anyhow::Result<Message> {
    let row =
        sqlx::query("SELECT id, session_id, role, content, created_at FROM messages WHERE id = ?")
            .bind(message_id)
            .fetch_one(&mut **tx)
            .await?;
    let created_at: String = row.try_get("created_at")?;
    Ok(Message {
        id: row.try_get("id")?,
        session_id: row.try_get("session_id")?,
        role: row.try_get("role")?,
        content: row.try_get("content")?,
        created_at: parse_time(&created_at)?,
    })
}

async fn insert_turn_event(
    tx: &mut Transaction<'_, Sqlite>,
    session_id: &str,
    turn_id: &str,
    event: &RuntimeEvent,
    created_at: DateTime<Utc>,
) -> anyhow::Result<ConversationEventRecord> {
    let event_index: i64 = sqlx::query_scalar(
        "SELECT COALESCE(MAX(event_index) + 1, 0) FROM conversation_events WHERE session_id = ?",
    )
    .bind(session_id)
    .fetch_one(&mut **tx)
    .await?;
    let payload = project_runtime_event_for_persistence(event)?;
    let kind = payload
        .get("type")
        .and_then(serde_json::Value::as_str)
        .ok_or_else(|| anyhow::anyhow!("runtime event is missing a type"))?
        .to_string();
    let record = ConversationEventRecord {
        id: Uuid::new_v4().to_string(),
        session_id: session_id.to_string(),
        turn_id: Some(turn_id.to_string()),
        event_index,
        kind,
        payload,
        created_at,
    };
    sqlx::query(
        "INSERT INTO conversation_events (id, session_id, turn_id, event_index, kind, payload_json, created_at) VALUES (?, ?, ?, ?, ?, ?, ?)",
    )
    .bind(&record.id)
    .bind(session_id)
    .bind(turn_id)
    .bind(record.event_index)
    .bind(&record.kind)
    .bind(serde_json::to_string(&record.payload)?)
    .bind(created_at.to_rfc3339())
    .execute(&mut **tx)
    .await?;
    Ok(record)
}

fn turn_from_row(row: sqlx::sqlite::SqliteRow) -> anyhow::Result<ConversationTurn> {
    let started_at: String = row.try_get("started_at")?;
    let updated_at: String = row.try_get("updated_at")?;
    let finished_at: Option<String> = row.try_get("finished_at")?;
    Ok(ConversationTurn {
        id: row.try_get("id")?,
        session_id: row.try_get("session_id")?,
        request_id: row.try_get("request_id")?,
        status: ConversationTurnStatus::from_str(&row.try_get::<String, _>("status")?)?,
        user_message_id: row.try_get("user_message_id")?,
        assistant_message_id: row.try_get("assistant_message_id")?,
        failure_message: row.try_get("failure_message")?,
        started_at: parse_time(&started_at)?,
        updated_at: parse_time(&updated_at)?,
        finished_at: finished_at.as_deref().map(parse_time).transpose()?,
    })
}

fn event_from_row(row: sqlx::sqlite::SqliteRow) -> anyhow::Result<ConversationEventRecord> {
    let created_at: String = row.try_get("created_at")?;
    let payload_json: String = row.try_get("payload_json")?;
    Ok(ConversationEventRecord {
        id: row.try_get("id")?,
        session_id: row.try_get("session_id")?,
        turn_id: row.try_get("turn_id")?,
        event_index: row.try_get("event_index")?,
        kind: row.try_get("kind")?,
        payload: serde_json::from_str(&payload_json)?,
        created_at: parse_time(&created_at)?,
    })
}

fn parse_time(value: &str) -> anyhow::Result<DateTime<Utc>> {
    Ok(DateTime::parse_from_rfc3339(value)?.with_timezone(&Utc))
}

fn validate_request_id(value: &str) -> anyhow::Result<()> {
    anyhow::ensure!(!value.is_empty(), "turn request identifier is required");
    anyhow::ensure!(value.len() <= 128, "turn request identifier is too long");
    anyhow::ensure!(
        value
            .bytes()
            .all(|byte| byte.is_ascii_alphanumeric() || matches!(byte, b'-' | b'_' | b'.')),
        "turn request identifier is invalid"
    );
    Ok(())
}

#[cfg(test)]
#[path = "turn_storage_tests.rs"]
mod tests;
