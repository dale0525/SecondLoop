use crate::events::RuntimeEvent;
use crate::model_config::StoredModelConfig;
use crate::session::{
    ConversationEventRecord, ConversationScope, Message, Session, SessionMutation, SessionPage,
    SessionPageCursor,
};
use chrono::{DateTime, Duration, Utc};
use sqlx::sqlite::{SqliteConnectOptions, SqlitePoolOptions, SqliteRow};
use sqlx::{Executor, Row, Sqlite, SqlitePool};
use std::str::FromStr;
use std::time::Duration as StdDuration;
use uuid::Uuid;

#[derive(Clone)]
pub struct Storage {
    pool: SqlitePool,
}

impl Storage {
    pub async fn connect(url: &str) -> anyhow::Result<Self> {
        let storage = Self::connect_without_migrations(url).await?;
        if let Err(error) = storage.run_migrations().await {
            storage.close().await;
            return Err(error);
        }
        storage.recover_interrupted_turns().await?;
        Ok(storage)
    }

    pub async fn connect_without_migrations(url: &str) -> anyhow::Result<Self> {
        let options = SqliteConnectOptions::from_str(url)?
            .foreign_keys(true)
            .busy_timeout(StdDuration::from_secs(5));
        let pool = SqlitePoolOptions::new().connect_with(options).await?;
        Ok(Self { pool })
    }

    pub async fn run_migrations(&self) -> anyhow::Result<()> {
        sqlx::query(
            r#"
            CREATE TABLE IF NOT EXISTS sessions (
              id TEXT PRIMARY KEY,
              title TEXT NOT NULL,
              created_at TEXT NOT NULL,
              updated_at TEXT NOT NULL
            );
            "#,
        )
        .execute(&self.pool)
        .await?;

        sqlx::query(
            r#"
            CREATE TABLE IF NOT EXISTS runtime_settings (
              key TEXT PRIMARY KEY,
              value TEXT NOT NULL
            );
            "#,
        )
        .execute(&self.pool)
        .await?;

        sqlx::query(
            r#"
            CREATE TABLE IF NOT EXISTS messages (
              id TEXT PRIMARY KEY,
              session_id TEXT NOT NULL,
              role TEXT NOT NULL,
              content TEXT NOT NULL,
              created_at TEXT NOT NULL,
              FOREIGN KEY(session_id) REFERENCES sessions(id)
            );
            "#,
        )
        .execute(&self.pool)
        .await?;

        crate::skill_state::migrate(self.pool()).await?;
        crate::conversation_migration::migrate(self.pool()).await?;

        Ok(())
    }

    pub(crate) fn pool(&self) -> &SqlitePool {
        &self.pool
    }

    pub fn local_memory_provider(&self) -> crate::memory_sqlite::SqliteMemoryProvider {
        crate::memory_sqlite::SqliteMemoryProvider::from_pool(self.pool.clone())
    }

    pub fn local_task_provider(&self) -> crate::task_sqlite::SqliteTaskProvider {
        crate::task_sqlite::SqliteTaskProvider::from_pool(self.pool.clone())
    }

    pub async fn close(&self) {
        self.pool.close().await;
    }

    pub fn is_closed(&self) -> bool {
        self.pool.is_closed()
    }

    pub async fn create_session(&self, title: &str) -> anyhow::Result<Session> {
        self.create_scoped_session(&ConversationScope::default(), title)
            .await
    }

    pub async fn create_scoped_session(
        &self,
        scope: &ConversationScope,
        title: &str,
    ) -> anyhow::Result<Session> {
        scope.validate()?;
        let now = Utc::now();
        let session = Session {
            id: Uuid::new_v4().to_string(),
            title: title.to_string(),
            created_at: now,
            updated_at: now,
        };

        sqlx::query("INSERT INTO sessions (id, title, created_at, updated_at, app_id, agent_id, tenant_id, user_id, device_id) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)")
            .bind(&session.id)
            .bind(&session.title)
            .bind(session.created_at.to_rfc3339())
            .bind(session.updated_at.to_rfc3339())
            .bind(&scope.app_id)
            .bind(&scope.agent_id)
            .bind(&scope.tenant_id)
            .bind(&scope.user_id)
            .bind(&scope.device_id)
            .execute(&self.pool)
            .await?;

        Ok(session)
    }

    pub async fn append_message(
        &self,
        session_id: &str,
        role: &str,
        content: &str,
    ) -> anyhow::Result<Message> {
        self.append_scoped_message(&ConversationScope::default(), session_id, role, content)
            .await
    }

    pub async fn append_scoped_message(
        &self,
        scope: &ConversationScope,
        session_id: &str,
        role: &str,
        content: &str,
    ) -> anyhow::Result<Message> {
        scope.validate()?;
        anyhow::ensure!(
            self.session_exists_scoped(scope, session_id).await?,
            "session not found in conversation scope"
        );
        let created_at = Utc::now();
        let message = build_message(session_id, role, content, created_at);
        let mut tx = self.pool.begin().await?;
        insert_message(&mut *tx, &message).await?;
        touch_session(&mut *tx, session_id, created_at).await?;
        tx.commit().await?;

        Ok(message)
    }

    pub async fn append_turn(
        &self,
        session_id: &str,
        user_content: &str,
        assistant_content: &str,
    ) -> anyhow::Result<(Message, Message)> {
        self.append_scoped_turn(
            &ConversationScope::default(),
            session_id,
            user_content,
            assistant_content,
        )
        .await
    }

    pub async fn append_scoped_turn(
        &self,
        scope: &ConversationScope,
        session_id: &str,
        user_content: &str,
        assistant_content: &str,
    ) -> anyhow::Result<(Message, Message)> {
        self.append_scoped_turn_with_events(scope, session_id, user_content, assistant_content, &[])
            .await
    }

    pub async fn append_scoped_turn_with_events(
        &self,
        scope: &ConversationScope,
        session_id: &str,
        user_content: &str,
        assistant_content: &str,
        events: &[RuntimeEvent],
    ) -> anyhow::Result<(Message, Message)> {
        scope.validate()?;
        let user_created_at = Utc::now();
        let assistant_created_at = user_created_at + Duration::microseconds(1);
        let user_message = build_message(session_id, "user", user_content, user_created_at);
        let assistant_message = build_message(
            session_id,
            "assistant",
            assistant_content,
            assistant_created_at,
        );
        let mut tx = self.pool.begin().await?;

        anyhow::ensure!(
            scoped_session_exists(&mut *tx, scope, session_id).await?,
            "session not found in conversation scope"
        );

        insert_message(&mut *tx, &user_message).await?;
        insert_message(&mut *tx, &assistant_message).await?;
        insert_runtime_events(&mut tx, session_id, events, assistant_created_at).await?;
        touch_session(&mut *tx, session_id, assistant_created_at).await?;
        tx.commit().await?;

        Ok((user_message, assistant_message))
    }

    pub async fn append_scoped_assistant_with_events(
        &self,
        scope: &ConversationScope,
        session_id: &str,
        assistant_content: &str,
        events: &[RuntimeEvent],
    ) -> anyhow::Result<Message> {
        scope.validate()?;
        let created_at = Utc::now();
        let assistant_message =
            build_message(session_id, "assistant", assistant_content, created_at);
        let mut tx = self.pool.begin().await?;
        anyhow::ensure!(
            scoped_session_exists(&mut *tx, scope, session_id).await?,
            "session not found in conversation scope"
        );
        insert_message(&mut *tx, &assistant_message).await?;
        insert_runtime_events(&mut tx, session_id, events, created_at).await?;
        touch_session(&mut *tx, session_id, created_at).await?;
        tx.commit().await?;
        Ok(assistant_message)
    }

    pub async fn session_exists(&self, session_id: &str) -> anyhow::Result<bool> {
        self.session_exists_scoped(&ConversationScope::default(), session_id)
            .await
    }

    pub async fn session_exists_scoped(
        &self,
        scope: &ConversationScope,
        session_id: &str,
    ) -> anyhow::Result<bool> {
        scope.validate()?;
        let exists: i64 = sqlx::query_scalar("SELECT EXISTS(SELECT 1 FROM sessions WHERE id = ? AND app_id = ? AND agent_id = ? AND tenant_id = ? AND user_id = ? AND device_id = ?)")
            .bind(session_id)
            .bind(&scope.app_id)
            .bind(&scope.agent_id)
            .bind(&scope.tenant_id)
            .bind(&scope.user_id)
            .bind(&scope.device_id)
            .fetch_one(&self.pool)
            .await?;

        Ok(exists != 0)
    }

    pub async fn list_messages(&self, session_id: &str) -> anyhow::Result<Vec<Message>> {
        self.list_scoped_messages(&ConversationScope::default(), session_id)
            .await
    }

    pub async fn list_scoped_messages(
        &self,
        scope: &ConversationScope,
        session_id: &str,
    ) -> anyhow::Result<Vec<Message>> {
        scope.validate()?;
        let rows = sqlx::query(
            "SELECT m.id, m.session_id, m.role, m.content, m.created_at FROM messages m INNER JOIN sessions s ON s.id = m.session_id WHERE m.session_id = ? AND s.app_id = ? AND s.agent_id = ? AND s.tenant_id = ? AND s.user_id = ? AND s.device_id = ? ORDER BY m.created_at ASC, m.id ASC",
        )
        .bind(session_id)
        .bind(&scope.app_id)
        .bind(&scope.agent_id)
        .bind(&scope.tenant_id)
        .bind(&scope.user_id)
        .bind(&scope.device_id)
        .fetch_all(&self.pool)
        .await?;

        let mut messages = Vec::with_capacity(rows.len());
        for row in rows {
            let created_at: String = row.try_get("created_at")?;
            messages.push(Message {
                id: row.try_get("id")?,
                session_id: row.try_get("session_id")?,
                role: row.try_get("role")?,
                content: row.try_get("content")?,
                created_at: DateTime::parse_from_rfc3339(&created_at)?.with_timezone(&Utc),
            });
        }

        Ok(messages)
    }

    pub async fn list_sessions(&self) -> anyhow::Result<Vec<Session>> {
        self.list_scoped_sessions(&ConversationScope::default())
            .await
    }

    pub async fn list_scoped_sessions(
        &self,
        scope: &ConversationScope,
    ) -> anyhow::Result<Vec<Session>> {
        scope.validate()?;
        let rows = sqlx::query(
            "SELECT id, title, created_at, updated_at FROM sessions WHERE app_id = ? AND agent_id = ? AND tenant_id = ? AND user_id = ? AND device_id = ? ORDER BY updated_at DESC, created_at DESC, id ASC",
        )
        .bind(&scope.app_id)
        .bind(&scope.agent_id)
        .bind(&scope.tenant_id)
        .bind(&scope.user_id)
        .bind(&scope.device_id)
        .fetch_all(&self.pool)
        .await?;

        let mut sessions = Vec::with_capacity(rows.len());
        for row in rows {
            let created_at: String = row.try_get("created_at")?;
            let updated_at: String = row.try_get("updated_at")?;
            sessions.push(Session {
                id: row.try_get("id")?,
                title: row.try_get("title")?,
                created_at: DateTime::parse_from_rfc3339(&created_at)?.with_timezone(&Utc),
                updated_at: DateTime::parse_from_rfc3339(&updated_at)?.with_timezone(&Utc),
            });
        }
        Ok(sessions)
    }

    pub async fn get_scoped_session(
        &self,
        scope: &ConversationScope,
        session_id: &str,
    ) -> anyhow::Result<Option<Session>> {
        scope.validate()?;
        let row = sqlx::query(
            "SELECT id, title, created_at, updated_at FROM sessions WHERE id = ? AND app_id = ? AND agent_id = ? AND tenant_id = ? AND user_id = ? AND device_id = ?",
        )
        .bind(session_id)
        .bind(&scope.app_id)
        .bind(&scope.agent_id)
        .bind(&scope.tenant_id)
        .bind(&scope.user_id)
        .bind(&scope.device_id)
        .fetch_optional(&self.pool)
        .await?;
        row.map(session_from_row).transpose()
    }

    pub async fn list_scoped_sessions_page(
        &self,
        scope: &ConversationScope,
        cursor: Option<&SessionPageCursor>,
        limit: usize,
    ) -> anyhow::Result<SessionPage> {
        scope.validate()?;
        anyhow::ensure!((1..=100).contains(&limit), "session page limit is invalid");
        let snapshot_at = cursor.map_or_else(Utc::now, |value| value.snapshot_at);
        let mut query = String::from(
            "SELECT id, title, created_at, updated_at FROM sessions WHERE app_id = ? AND agent_id = ? AND tenant_id = ? AND user_id = ? AND device_id = ? AND julianday(updated_at) <= julianday(?)",
        );
        if cursor.is_some() {
            query.push_str(
                " AND (julianday(updated_at) < julianday(?) OR (julianday(updated_at) = julianday(?) AND julianday(created_at) < julianday(?)) OR (julianday(updated_at) = julianday(?) AND julianday(created_at) = julianday(?) AND id > ?))",
            );
        }
        query.push_str(
            " ORDER BY julianday(updated_at) DESC, julianday(created_at) DESC, id ASC LIMIT ?",
        );
        let mut query = sqlx::query(&query)
            .bind(&scope.app_id)
            .bind(&scope.agent_id)
            .bind(&scope.tenant_id)
            .bind(&scope.user_id)
            .bind(&scope.device_id)
            .bind(snapshot_at.to_rfc3339());
        if let Some(cursor) = cursor {
            query = query
                .bind(cursor.updated_at.to_rfc3339())
                .bind(cursor.updated_at.to_rfc3339())
                .bind(cursor.created_at.to_rfc3339())
                .bind(cursor.updated_at.to_rfc3339())
                .bind(cursor.created_at.to_rfc3339())
                .bind(&cursor.id);
        }
        let rows = query
            .bind(i64::try_from(limit + 1)?)
            .fetch_all(&self.pool)
            .await?;
        let mut items = rows
            .into_iter()
            .map(session_from_row)
            .collect::<anyhow::Result<Vec<_>>>()?;
        let has_more = items.len() > limit;
        items.truncate(limit);
        let next_cursor = has_more && !items.is_empty();
        Ok(SessionPage {
            next_cursor: next_cursor.then(|| {
                let last = items.last().expect("nonempty session page");
                SessionPageCursor {
                    snapshot_at,
                    updated_at: last.updated_at,
                    created_at: last.created_at,
                    id: last.id.clone(),
                }
            }),
            items,
        })
    }

    pub async fn update_scoped_session_title(
        &self,
        scope: &ConversationScope,
        session_id: &str,
        title: &str,
        expected_updated_at: DateTime<Utc>,
    ) -> anyhow::Result<SessionMutation> {
        scope.validate()?;
        let Some(current) = self.get_scoped_session(scope, session_id).await? else {
            return Ok(SessionMutation::NotFound);
        };
        if current.updated_at != expected_updated_at {
            return Ok(SessionMutation::Conflict(current));
        }
        let updated_at = std::cmp::max(Utc::now(), current.updated_at + Duration::microseconds(1));
        let result = sqlx::query(
            "UPDATE sessions SET title = ?, updated_at = ? WHERE id = ? AND app_id = ? AND agent_id = ? AND tenant_id = ? AND user_id = ? AND device_id = ? AND updated_at = ?",
        )
        .bind(title)
        .bind(updated_at.to_rfc3339())
        .bind(session_id)
        .bind(&scope.app_id)
        .bind(&scope.agent_id)
        .bind(&scope.tenant_id)
        .bind(&scope.user_id)
        .bind(&scope.device_id)
        .bind(expected_updated_at.to_rfc3339())
        .execute(&self.pool)
        .await?;
        if result.rows_affected() == 1 {
            return Ok(SessionMutation::Applied(Session {
                id: current.id,
                title: title.to_string(),
                created_at: current.created_at,
                updated_at,
            }));
        }
        Ok(match self.get_scoped_session(scope, session_id).await? {
            Some(authoritative) => SessionMutation::Conflict(authoritative),
            None => SessionMutation::NotFound,
        })
    }

    pub async fn delete_scoped_session_if_unchanged(
        &self,
        scope: &ConversationScope,
        session_id: &str,
        expected_updated_at: DateTime<Utc>,
    ) -> anyhow::Result<SessionMutation> {
        scope.validate()?;
        let mut tx = self.pool.begin().await?;
        let result = sqlx::query(
            "UPDATE sessions SET id = id WHERE id = ? AND app_id = ? AND agent_id = ? AND tenant_id = ? AND user_id = ? AND device_id = ? AND updated_at = ?",
        )
        .bind(session_id)
        .bind(&scope.app_id)
        .bind(&scope.agent_id)
        .bind(&scope.tenant_id)
        .bind(&scope.user_id)
        .bind(&scope.device_id)
        .bind(expected_updated_at.to_rfc3339())
        .execute(&mut *tx)
        .await?;
        if result.rows_affected() != 1 {
            tx.rollback().await?;
            return Ok(match self.get_scoped_session(scope, session_id).await? {
                Some(authoritative) => SessionMutation::Conflict(authoritative),
                None => SessionMutation::NotFound,
            });
        }
        let current = session_from_row(
            sqlx::query("SELECT id, title, created_at, updated_at FROM sessions WHERE id = ?")
                .bind(session_id)
                .fetch_one(&mut *tx)
                .await?,
        )?;
        delete_session_rows(&mut tx, session_id).await?;
        tx.commit().await?;
        Ok(SessionMutation::Applied(current))
    }

    pub async fn delete_session(&self, session_id: &str) -> anyhow::Result<()> {
        self.delete_scoped_session(&ConversationScope::default(), session_id)
            .await
    }

    pub async fn delete_scoped_session(
        &self,
        scope: &ConversationScope,
        session_id: &str,
    ) -> anyhow::Result<()> {
        scope.validate()?;
        let mut tx = self.pool.begin().await?;
        if !scoped_session_exists(&mut *tx, scope, session_id).await? {
            return Ok(());
        }
        delete_session_rows(&mut tx, session_id).await?;
        tx.commit().await?;
        Ok(())
    }

    pub async fn list_conversation_events(
        &self,
        scope: &ConversationScope,
        session_id: &str,
    ) -> anyhow::Result<Vec<ConversationEventRecord>> {
        scope.validate()?;
        let rows = sqlx::query(
            "SELECT e.id, e.session_id, e.turn_id, e.event_index, e.kind, e.payload_json, e.created_at FROM conversation_events e INNER JOIN sessions s ON s.id = e.session_id WHERE e.session_id = ? AND s.app_id = ? AND s.agent_id = ? AND s.tenant_id = ? AND s.user_id = ? AND s.device_id = ? ORDER BY e.event_index",
        )
        .bind(session_id)
        .bind(&scope.app_id)
        .bind(&scope.agent_id)
        .bind(&scope.tenant_id)
        .bind(&scope.user_id)
        .bind(&scope.device_id)
        .fetch_all(&self.pool)
        .await?;
        rows.into_iter()
            .map(|row| {
                let created_at: String = row.try_get("created_at")?;
                let payload_json: String = row.try_get("payload_json")?;
                Ok(ConversationEventRecord {
                    id: row.try_get("id")?,
                    session_id: row.try_get("session_id")?,
                    turn_id: row.try_get("turn_id")?,
                    event_index: row.try_get("event_index")?,
                    kind: row.try_get("kind")?,
                    payload: serde_json::from_str(&payload_json)?,
                    created_at: DateTime::parse_from_rfc3339(&created_at)?.with_timezone(&Utc),
                })
            })
            .collect()
    }

    pub async fn search_scoped_messages(
        &self,
        scope: &ConversationScope,
        query: &str,
        limit: usize,
    ) -> anyhow::Result<Vec<Message>> {
        scope.validate()?;
        anyhow::ensure!(
            !query.trim().is_empty(),
            "conversation search query is required"
        );
        anyhow::ensure!(
            (1..=100).contains(&limit),
            "conversation search limit is invalid"
        );
        let pattern = format!("%{}%", query.trim());
        let rows = sqlx::query(
            "SELECT m.id, m.session_id, m.role, m.content, m.created_at FROM messages m INNER JOIN sessions s ON s.id = m.session_id WHERE s.app_id = ? AND s.agent_id = ? AND s.tenant_id = ? AND s.user_id = ? AND s.device_id = ? AND m.content LIKE ? ORDER BY m.created_at DESC, m.id ASC LIMIT ?",
        )
        .bind(&scope.app_id)
        .bind(&scope.agent_id)
        .bind(&scope.tenant_id)
        .bind(&scope.user_id)
        .bind(&scope.device_id)
        .bind(pattern)
        .bind(limit as i64)
        .fetch_all(&self.pool)
        .await?;
        rows.into_iter().map(message_from_row).collect()
    }

    pub async fn save_model_config(&self, config: &StoredModelConfig) -> anyhow::Result<()> {
        config.validate().map_err(anyhow::Error::msg)?;
        let value = serde_json::to_string(config)?;
        sqlx::query(
            r#"
            INSERT INTO runtime_settings (key, value)
            VALUES ('model_config', ?)
            ON CONFLICT(key) DO UPDATE SET value = excluded.value
            "#,
        )
        .bind(value)
        .execute(&self.pool)
        .await?;
        Ok(())
    }

    pub async fn load_model_config(&self) -> anyhow::Result<Option<StoredModelConfig>> {
        let value: Option<String> =
            sqlx::query_scalar("SELECT value FROM runtime_settings WHERE key = 'model_config'")
                .fetch_optional(&self.pool)
                .await?;
        value
            .map(|value| serde_json::from_str(&value).map_err(Into::into))
            .transpose()
    }
}

fn build_message(
    session_id: &str,
    role: &str,
    content: &str,
    created_at: DateTime<Utc>,
) -> Message {
    Message {
        id: Uuid::new_v4().to_string(),
        session_id: session_id.to_string(),
        role: role.to_string(),
        content: content.to_string(),
        created_at,
    }
}

async fn insert_message<'a, E>(executor: E, message: &Message) -> anyhow::Result<()>
where
    E: Executor<'a, Database = Sqlite>,
{
    sqlx::query(
        "INSERT INTO messages (id, session_id, role, content, created_at) VALUES (?, ?, ?, ?, ?)",
    )
    .bind(&message.id)
    .bind(&message.session_id)
    .bind(&message.role)
    .bind(&message.content)
    .bind(message.created_at.to_rfc3339())
    .execute(executor)
    .await?;

    Ok(())
}

fn message_from_row(row: SqliteRow) -> anyhow::Result<Message> {
    let created_at: String = row.try_get("created_at")?;
    Ok(Message {
        id: row.try_get("id")?,
        session_id: row.try_get("session_id")?,
        role: row.try_get("role")?,
        content: row.try_get("content")?,
        created_at: DateTime::parse_from_rfc3339(&created_at)?.with_timezone(&Utc),
    })
}

fn session_from_row(row: SqliteRow) -> anyhow::Result<Session> {
    let created_at: String = row.try_get("created_at")?;
    let updated_at: String = row.try_get("updated_at")?;
    Ok(Session {
        id: row.try_get("id")?,
        title: row.try_get("title")?,
        created_at: DateTime::parse_from_rfc3339(&created_at)?.with_timezone(&Utc),
        updated_at: DateTime::parse_from_rfc3339(&updated_at)?.with_timezone(&Utc),
    })
}

async fn delete_session_rows(
    transaction: &mut sqlx::Transaction<'_, Sqlite>,
    session_id: &str,
) -> anyhow::Result<()> {
    sqlx::query("DELETE FROM conversation_events WHERE session_id = ?")
        .bind(session_id)
        .execute(&mut **transaction)
        .await?;
    sqlx::query("DELETE FROM messages WHERE session_id = ?")
        .bind(session_id)
        .execute(&mut **transaction)
        .await?;
    sqlx::query("DELETE FROM sessions WHERE id = ?")
        .bind(session_id)
        .execute(&mut **transaction)
        .await?;
    Ok(())
}

async fn scoped_session_exists<'a, E>(
    executor: E,
    scope: &ConversationScope,
    session_id: &str,
) -> anyhow::Result<bool>
where
    E: Executor<'a, Database = Sqlite>,
{
    let exists: i64 = sqlx::query_scalar(
        "SELECT EXISTS(SELECT 1 FROM sessions WHERE id = ? AND app_id = ? AND agent_id = ? AND tenant_id = ? AND user_id = ? AND device_id = ?)",
    )
    .bind(session_id)
    .bind(&scope.app_id)
    .bind(&scope.agent_id)
    .bind(&scope.tenant_id)
    .bind(&scope.user_id)
    .bind(&scope.device_id)
    .fetch_one(executor)
    .await?;
    Ok(exists != 0)
}

async fn insert_runtime_events(
    executor: &mut sqlx::SqliteConnection,
    session_id: &str,
    events: &[RuntimeEvent],
    created_at: DateTime<Utc>,
) -> anyhow::Result<()> {
    let turn_id = events.iter().find_map(runtime_event_turn_id);
    let first_index: i64 = sqlx::query_scalar(
        "SELECT COALESCE(MAX(event_index) + 1, 0) FROM conversation_events WHERE session_id = ?",
    )
    .bind(session_id)
    .fetch_one(&mut *executor)
    .await?;
    for (offset, event) in events.iter().enumerate() {
        let payload = serde_json::to_value(event)?;
        let kind = payload
            .get("type")
            .and_then(serde_json::Value::as_str)
            .ok_or_else(|| anyhow::anyhow!("runtime event is missing a type"))?;
        sqlx::query(
            "INSERT INTO conversation_events(id, session_id, turn_id, event_index, kind, payload_json, created_at) VALUES (?, ?, ?, ?, ?, ?, ?)",
        )
        .bind(Uuid::new_v4().to_string())
        .bind(session_id)
        .bind(turn_id)
        .bind(first_index + offset as i64)
        .bind(kind)
        .bind(serde_json::to_string(&payload)?)
        .bind((created_at + Duration::microseconds(offset as i64)).to_rfc3339())
        .execute(&mut *executor)
        .await?;
    }
    Ok(())
}

fn runtime_event_turn_id(event: &RuntimeEvent) -> Option<&str> {
    match event {
        RuntimeEvent::TurnStarted { turn_id }
        | RuntimeEvent::TurnFinished { turn_id }
        | RuntimeEvent::TurnCancelled { turn_id }
        | RuntimeEvent::TurnFailed { turn_id, .. } => Some(turn_id),
        _ => None,
    }
}

async fn touch_session<'a, E>(
    executor: E,
    session_id: &str,
    updated_at: DateTime<Utc>,
) -> anyhow::Result<()>
where
    E: Executor<'a, Database = Sqlite>,
{
    sqlx::query("UPDATE sessions SET updated_at = ? WHERE id = ?")
        .bind(updated_at.to_rfc3339())
        .bind(session_id)
        .execute(executor)
        .await?;

    Ok(())
}

#[cfg(test)]
#[path = "storage_conversation_tests.rs"]
mod conversation_tests;

#[cfg(test)]
mod tests {
    use super::*;
    use crate::model_config::StoredModelConfig;
    use model_gateway::provider::EndpointType;
    use std::collections::BTreeMap;

    #[tokio::test]
    async fn stores_and_lists_messages() {
        let storage = Storage::connect("sqlite::memory:").await.unwrap();
        let session = storage.create_session("Test").await.unwrap();

        storage
            .append_message(&session.id, "user", "hello")
            .await
            .unwrap();

        let messages = storage.list_messages(&session.id).await.unwrap();
        assert_eq!(messages.len(), 1);
        assert_eq!(messages[0].role, "user");
        assert_eq!(messages[0].content, "hello");
    }

    #[tokio::test]
    async fn rejects_messages_for_missing_sessions() {
        let storage = Storage::connect("sqlite::memory:").await.unwrap();

        let result = storage
            .append_message("missing-session", "user", "hello")
            .await;

        assert!(result.is_err());
    }

    #[tokio::test]
    async fn reports_session_existence() {
        let storage = Storage::connect("sqlite::memory:").await.unwrap();
        let session = storage.create_session("Test").await.unwrap();

        assert!(storage.session_exists(&session.id).await.unwrap());
        assert!(!storage.session_exists("missing-session").await.unwrap());
    }

    #[tokio::test]
    async fn appends_user_and_assistant_turn_messages() {
        let storage = Storage::connect("sqlite::memory:").await.unwrap();
        let session = storage.create_session("Test").await.unwrap();

        let (user_message, assistant_message) = storage
            .append_turn(&session.id, "hello", "MVP agent received: hello")
            .await
            .unwrap();

        assert_eq!(user_message.role, "user");
        assert_eq!(user_message.content, "hello");
        assert_eq!(assistant_message.role, "assistant");
        assert_eq!(assistant_message.content, "MVP agent received: hello");

        let messages = storage.list_messages(&session.id).await.unwrap();
        assert_eq!(messages.len(), 2);
        assert_eq!(messages[0].id, user_message.id);
        assert_eq!(messages[1].id, assistant_message.id);
    }

    #[tokio::test]
    async fn append_turn_rolls_back_when_assistant_insert_fails() {
        let storage = Storage::connect("sqlite::memory:").await.unwrap();
        let session = storage.create_session("Test").await.unwrap();
        sqlx::query(
            r#"
            CREATE TRIGGER fail_assistant_insert
            BEFORE INSERT ON messages
            WHEN NEW.role = 'assistant'
            BEGIN
                SELECT RAISE(ABORT, 'assistant insert failed');
            END;
            "#,
        )
        .execute(&storage.pool)
        .await
        .unwrap();

        let result = storage
            .append_turn(&session.id, "hello", "MVP agent received: hello")
            .await;

        assert!(result.is_err());
        let messages = storage.list_messages(&session.id).await.unwrap();
        assert!(messages.is_empty());
    }

    #[tokio::test]
    async fn list_sessions_returns_newest_updated_first() {
        let storage = Storage::connect("sqlite::memory:").await.unwrap();
        let first = storage.create_session("First").await.unwrap();
        let second = storage.create_session("Second").await.unwrap();
        storage
            .append_message(&first.id, "user", "hello")
            .await
            .unwrap();

        let sessions = storage.list_sessions().await.unwrap();

        assert_eq!(sessions[0].id, first.id);
        assert_eq!(sessions[1].id, second.id);
    }

    #[tokio::test]
    async fn delete_session_removes_messages() {
        let storage = Storage::connect("sqlite::memory:").await.unwrap();
        let session = storage.create_session("Delete me").await.unwrap();
        storage
            .append_turn(&session.id, "user", "assistant")
            .await
            .unwrap();

        storage.delete_session(&session.id).await.unwrap();

        assert!(!storage.session_exists(&session.id).await.unwrap());
        assert!(storage.list_messages(&session.id).await.unwrap().is_empty());
    }

    #[tokio::test]
    async fn persists_non_secret_model_config() {
        let storage = Storage::connect("sqlite::memory:").await.unwrap();
        let config = StoredModelConfig {
            provider_id: "openai".into(),
            provider_name: "OpenAI".into(),
            endpoint_type: EndpointType::Responses,
            base_url: "https://api.openai.com/v1".into(),
            model_name: "gpt-5.4".into(),
            secret_id: Some("model.openai.default".into()),
            headers: BTreeMap::from([("X-Client-Version".into(), "android-1".into())]),
        };

        storage.save_model_config(&config).await.unwrap();

        assert_eq!(storage.load_model_config().await.unwrap(), Some(config));
    }
}
