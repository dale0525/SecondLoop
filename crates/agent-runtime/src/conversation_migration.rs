use sqlx::{Row, Sqlite, SqlitePool, Transaction};

const COMPONENT: &str = "conversation";
const CURRENT_VERSION: i64 = 4;

pub(crate) async fn migrate(pool: &SqlitePool) -> anyhow::Result<()> {
    let mut tx = pool.begin().await?;
    sqlx::query(
        r#"CREATE TABLE IF NOT EXISTS runtime_schema_migrations (
            component TEXT NOT NULL,
            version INTEGER NOT NULL,
            applied_at TEXT NOT NULL,
            PRIMARY KEY(component, version)
        )"#,
    )
    .execute(&mut *tx)
    .await?;
    let versions = sqlx::query(
        "SELECT version FROM runtime_schema_migrations WHERE component = ? ORDER BY version",
    )
    .bind(COMPONENT)
    .fetch_all(&mut *tx)
    .await?;
    if versions
        .iter()
        .any(|row| row.get::<i64, _>("version") > CURRENT_VERSION)
    {
        anyhow::bail!("conversation schema is newer than this runtime");
    }

    ensure_scope_column(&mut tx, "app_id", "dev.agentweave.default").await?;
    ensure_scope_column(&mut tx, "agent_id", "default").await?;
    ensure_scope_column(&mut tx, "tenant_id", "local").await?;
    ensure_scope_column(&mut tx, "user_id", "local-user").await?;
    ensure_scope_column(&mut tx, "device_id", "local-device").await?;
    sqlx::query(
        r#"CREATE TABLE IF NOT EXISTS conversation_events (
            id TEXT PRIMARY KEY,
            session_id TEXT NOT NULL,
            event_index INTEGER NOT NULL,
            kind TEXT NOT NULL,
            payload_json TEXT NOT NULL,
            created_at TEXT NOT NULL,
            FOREIGN KEY(session_id) REFERENCES sessions(id) ON DELETE CASCADE,
            UNIQUE(session_id, event_index)
        )"#,
    )
    .execute(&mut *tx)
    .await?;
    ensure_column(&mut tx, "conversation_events", "turn_id", "TEXT").await?;
    sqlx::query(
        r#"CREATE TABLE IF NOT EXISTS conversation_turns (
            id TEXT PRIMARY KEY,
            session_id TEXT NOT NULL,
            request_id TEXT NOT NULL,
            status TEXT NOT NULL,
            user_message_id TEXT NOT NULL,
            assistant_message_id TEXT,
            failure_message TEXT,
            started_at TEXT NOT NULL,
            updated_at TEXT NOT NULL,
            finished_at TEXT,
            FOREIGN KEY(session_id) REFERENCES sessions(id) ON DELETE CASCADE,
            UNIQUE(session_id, request_id)
        )"#,
    )
    .execute(&mut *tx)
    .await?;
    sqlx::query(
        "CREATE INDEX IF NOT EXISTS sessions_scope_updated_idx ON sessions(app_id, agent_id, tenant_id, user_id, device_id, updated_at)",
    )
    .execute(&mut *tx)
    .await?;
    sqlx::query(
        "CREATE INDEX IF NOT EXISTS messages_session_created_idx ON messages(session_id, created_at)",
    )
    .execute(&mut *tx)
    .await?;
    sqlx::query(
        "CREATE INDEX IF NOT EXISTS conversation_events_turn_idx ON conversation_events(turn_id, event_index)",
    )
    .execute(&mut *tx)
    .await?;
    sqlx::query(
        "CREATE INDEX IF NOT EXISTS conversation_turns_session_status_idx ON conversation_turns(session_id, status, started_at)",
    )
    .execute(&mut *tx)
    .await?;
    sqlx::query(
        r#"CREATE TABLE IF NOT EXISTS structured_content_state (
            session_id TEXT NOT NULL,
            content_id TEXT NOT NULL,
            owner TEXT NOT NULL,
            revision INTEGER NOT NULL,
            deleted INTEGER NOT NULL DEFAULT 0 CHECK(deleted IN (0, 1)),
            content_json TEXT,
            updated_at TEXT NOT NULL,
            PRIMARY KEY(session_id, content_id),
            FOREIGN KEY(session_id) REFERENCES sessions(id) ON DELETE CASCADE,
            CHECK(revision > 0),
            CHECK((deleted = 0 AND content_json IS NOT NULL) OR (deleted = 1 AND content_json IS NULL))
        )"#,
    )
    .execute(&mut *tx)
    .await?;
    sqlx::query(
        r#"CREATE TABLE IF NOT EXISTS structured_action_bindings (
            binding_id TEXT PRIMARY KEY,
            session_id TEXT NOT NULL,
            content_id TEXT NOT NULL,
            content_revision INTEGER NOT NULL,
            action_id TEXT NOT NULL,
            intent TEXT NOT NULL,
            parameters_json TEXT NOT NULL,
            parameters_sha256 TEXT NOT NULL,
            input_schema_json TEXT NOT NULL,
            constraints_json TEXT NOT NULL,
            expires_at TEXT NOT NULL,
            idempotency_key TEXT NOT NULL,
            state TEXT NOT NULL CHECK(state IN ('pending', 'executing', 'completed', 'cancelled', 'superseded')),
            lease_expires_at TEXT,
            claim_token TEXT,
            claim_epoch INTEGER NOT NULL DEFAULT 0,
            created_at TEXT NOT NULL,
            updated_at TEXT NOT NULL,
            FOREIGN KEY(session_id, content_id) REFERENCES structured_content_state(session_id, content_id) ON DELETE CASCADE,
            UNIQUE(session_id, idempotency_key)
        )"#,
    )
    .execute(&mut *tx)
    .await?;
    ensure_column(&mut tx, "structured_action_bindings", "claim_token", "TEXT").await?;
    ensure_column(
        &mut tx,
        "structured_action_bindings",
        "claim_epoch",
        "INTEGER NOT NULL DEFAULT 0",
    )
    .await?;
    sqlx::query(
        r#"CREATE TABLE IF NOT EXISTS structured_action_receipts (
            binding_id TEXT PRIMARY KEY,
            result_json TEXT NOT NULL,
            completed_at TEXT NOT NULL,
            FOREIGN KEY(binding_id) REFERENCES structured_action_bindings(binding_id) ON DELETE CASCADE
        )"#,
    )
    .execute(&mut *tx)
    .await?;
    sqlx::query(
        "CREATE INDEX IF NOT EXISTS structured_content_session_updated_idx ON structured_content_state(session_id, updated_at)",
    )
    .execute(&mut *tx)
    .await?;
    sqlx::query(
        "CREATE INDEX IF NOT EXISTS structured_action_scope_state_idx ON structured_action_bindings(session_id, state, expires_at)",
    )
    .execute(&mut *tx)
    .await?;
    sqlx::query(
        "CREATE UNIQUE INDEX IF NOT EXISTS structured_action_content_execution_idx ON structured_action_bindings(session_id, content_id) WHERE state = 'executing'",
    )
    .execute(&mut *tx)
    .await?;
    sqlx::query(
        "INSERT OR IGNORE INTO runtime_schema_migrations(component, version, applied_at) VALUES (?, ?, ?)",
    )
    .bind(COMPONENT)
    .bind(CURRENT_VERSION)
    .bind(chrono::Utc::now().to_rfc3339())
    .execute(&mut *tx)
    .await?;
    tx.commit().await?;
    Ok(())
}

async fn ensure_scope_column(
    tx: &mut Transaction<'_, Sqlite>,
    column: &str,
    default_value: &str,
) -> anyhow::Result<()> {
    ensure_column(
        tx,
        "sessions",
        column,
        &format!("TEXT NOT NULL DEFAULT '{default_value}'"),
    )
    .await
}

async fn ensure_column(
    tx: &mut Transaction<'_, Sqlite>,
    table: &str,
    column: &str,
    definition: &str,
) -> anyhow::Result<()> {
    anyhow::ensure!(
        matches!(
            table,
            "sessions" | "conversation_events" | "structured_action_bindings"
        ),
        "conversation migration table is invalid"
    );
    let columns = sqlx::query(&format!("PRAGMA table_info({table})"))
        .fetch_all(&mut **tx)
        .await?;
    if columns
        .iter()
        .any(|row| row.get::<String, _>("name") == column)
    {
        return Ok(());
    }
    let statement = format!("ALTER TABLE {table} ADD COLUMN {column} {definition}");
    sqlx::query(&statement).execute(&mut **tx).await?;
    Ok(())
}
