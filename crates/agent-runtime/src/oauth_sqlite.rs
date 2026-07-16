use crate::{
    credential::{CredentialScope, SecretId},
    oauth::{OAuthAuthorizationBinding, OAuthAuthorizationSession, OAuthAuthorizationStatus},
    storage::Storage,
};
use chrono::{DateTime, Utc};
use sqlx::{Row, SqlitePool};

const CREATE_SESSIONS: &str = r#"CREATE TABLE IF NOT EXISTS oauth_broker_sessions (
    app_id TEXT NOT NULL,
    tenant_id TEXT NOT NULL,
    user_id TEXT NOT NULL,
    authorization_id TEXT NOT NULL,
    provider_id TEXT NOT NULL,
    connector_ids_json TEXT NOT NULL,
    requested_capabilities_json TEXT NOT NULL,
    requested_scopes_json TEXT NOT NULL,
    connector_scopes_json TEXT NOT NULL,
    status TEXT NOT NULL,
    exchange_owner_id TEXT,
    exchange_lease_expires_at TEXT,
    credential_id TEXT,
    bindings_json TEXT NOT NULL,
    error_code TEXT,
    expires_at TEXT NOT NULL,
    created_at TEXT NOT NULL,
    updated_at TEXT NOT NULL,
    PRIMARY KEY(app_id, tenant_id, user_id, authorization_id)
)"#;

const CREATE_STATES: &str = r#"CREATE TABLE IF NOT EXISTS oauth_broker_states (
    app_id TEXT NOT NULL,
    tenant_id TEXT NOT NULL,
    user_id TEXT NOT NULL,
    state_id TEXT NOT NULL,
    authorization_id TEXT NOT NULL,
    pkce_secret_id TEXT NOT NULL,
    expires_at TEXT NOT NULL,
    created_at TEXT NOT NULL,
    PRIMARY KEY(app_id, tenant_id, user_id, state_id),
    UNIQUE(app_id, tenant_id, user_id, authorization_id),
    FOREIGN KEY(app_id, tenant_id, user_id, authorization_id)
        REFERENCES oauth_broker_sessions(app_id, tenant_id, user_id, authorization_id)
        ON DELETE CASCADE
)"#;

#[derive(Clone)]
pub(crate) struct SqliteOAuthStore {
    pool: SqlitePool,
}

pub(crate) enum OAuthStateConsumption {
    Ready {
        session: Box<OAuthAuthorizationSession>,
        pkce_secret_id: SecretId,
    },
    Expired {
        authorization_id: String,
        pkce_secret_id: SecretId,
    },
}

impl SqliteOAuthStore {
    pub(crate) async fn from_storage(storage: &Storage) -> anyhow::Result<Self> {
        let store = Self {
            pool: storage.pool().clone(),
        };
        let mut tx = store.pool.begin().await?;
        sqlx::query(CREATE_SESSIONS).execute(&mut *tx).await?;
        ensure_column(
            &mut tx,
            "oauth_broker_sessions",
            "exchange_owner_id",
            "TEXT",
        )
        .await?;
        ensure_column(
            &mut tx,
            "oauth_broker_sessions",
            "exchange_lease_expires_at",
            "TEXT",
        )
        .await?;
        sqlx::query(CREATE_STATES).execute(&mut *tx).await?;
        tx.commit().await?;
        Ok(store)
    }

    pub(crate) async fn create(
        &self,
        scope: &CredentialScope,
        session: &OAuthAuthorizationSession,
        state_id: &str,
        pkce_secret_id: &SecretId,
        owner_id: &str,
        lease_expires_at: DateTime<Utc>,
    ) -> anyhow::Result<()> {
        validate_session(scope, session)?;
        validate_opaque_id("OAuth state", state_id)?;
        validate_opaque_id("OAuth preparation owner", owner_id)?;
        anyhow::ensure!(
            lease_expires_at > session.updated_at,
            "OAuth preparation lease is invalid"
        );
        let mut tx = self.pool.begin().await?;
        sqlx::query(
            r#"INSERT INTO oauth_broker_sessions(
                app_id, tenant_id, user_id, authorization_id, provider_id,
                connector_ids_json, requested_capabilities_json, requested_scopes_json,
                connector_scopes_json, status, exchange_owner_id,
                exchange_lease_expires_at, credential_id, bindings_json, error_code,
                expires_at, created_at, updated_at
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, '[]', NULL, ?, ?, ?)"#,
        )
        .bind(&scope.app_id)
        .bind(&scope.tenant_id)
        .bind(&scope.user_id)
        .bind(&session.authorization_id)
        .bind(&session.provider_id)
        .bind(serde_json::to_string(&session.connector_ids)?)
        .bind(serde_json::to_string(&session.requested_capabilities)?)
        .bind(serde_json::to_string(&session.requested_scopes)?)
        .bind(serde_json::to_string(&session.connector_scopes)?)
        .bind(status_name(session.status))
        .bind(owner_id)
        .bind(lease_expires_at.to_rfc3339())
        .bind(&session.credential_id)
        .bind(session.expires_at.to_rfc3339())
        .bind(session.created_at.to_rfc3339())
        .bind(session.updated_at.to_rfc3339())
        .execute(&mut *tx)
        .await?;
        sqlx::query(
            r#"INSERT INTO oauth_broker_states(
                app_id, tenant_id, user_id, state_id, authorization_id,
                pkce_secret_id, expires_at, created_at
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?)"#,
        )
        .bind(&scope.app_id)
        .bind(&scope.tenant_id)
        .bind(&scope.user_id)
        .bind(state_id)
        .bind(&session.authorization_id)
        .bind(pkce_secret_id.as_str())
        .bind(session.expires_at.to_rfc3339())
        .bind(session.created_at.to_rfc3339())
        .execute(&mut *tx)
        .await?;
        tx.commit().await?;
        Ok(())
    }

    pub(crate) async fn activate_pending(
        &self,
        scope: &CredentialScope,
        authorization_id: &str,
        owner_id: &str,
        now: DateTime<Utc>,
    ) -> anyhow::Result<()> {
        scope.validate()?;
        let result = sqlx::query(
            r#"UPDATE oauth_broker_sessions SET status = 'pending',
                exchange_owner_id = NULL, exchange_lease_expires_at = NULL, updated_at = ?
            WHERE app_id = ? AND tenant_id = ? AND user_id = ?
                AND authorization_id = ? AND status = 'preparing'
                AND exchange_owner_id = ? AND exchange_lease_expires_at > ?"#,
        )
        .bind(now.to_rfc3339())
        .bind(&scope.app_id)
        .bind(&scope.tenant_id)
        .bind(&scope.user_id)
        .bind(authorization_id)
        .bind(owner_id)
        .bind(now.to_rfc3339())
        .execute(&self.pool)
        .await?;
        anyhow::ensure!(
            result.rows_affected() == 1,
            "OAuth preparation ownership changed"
        );
        Ok(())
    }

    pub(crate) async fn get(
        &self,
        scope: &CredentialScope,
        authorization_id: &str,
    ) -> anyhow::Result<Option<OAuthAuthorizationSession>> {
        scope.validate()?;
        validate_opaque_id("OAuth authorization", authorization_id)?;
        let row = sqlx::query(
            r#"SELECT authorization_id, provider_id, connector_ids_json,
                requested_capabilities_json, requested_scopes_json, connector_scopes_json,
                status, exchange_owner_id, exchange_lease_expires_at, credential_id,
                bindings_json, error_code, expires_at,
                created_at, updated_at
            FROM oauth_broker_sessions
            WHERE app_id = ? AND tenant_id = ? AND user_id = ? AND authorization_id = ?"#,
        )
        .bind(&scope.app_id)
        .bind(&scope.tenant_id)
        .bind(&scope.user_id)
        .bind(authorization_id)
        .fetch_optional(&self.pool)
        .await?;
        row.map(session_from_row).transpose()
    }

    pub(crate) async fn recovery_candidates(
        &self,
        scope: &CredentialScope,
        now: DateTime<Utc>,
    ) -> anyhow::Result<Vec<OAuthAuthorizationSession>> {
        scope.validate()?;
        let rows = sqlx::query(
            r#"SELECT authorization_id, provider_id, connector_ids_json,
                requested_capabilities_json, requested_scopes_json, connector_scopes_json,
                status, exchange_owner_id, exchange_lease_expires_at, credential_id,
                bindings_json, error_code, expires_at,
                created_at, updated_at
            FROM oauth_broker_sessions
            WHERE app_id = ? AND tenant_id = ? AND user_id = ?
                AND status IN ('preparing', 'exchanging', 'failed')
                AND credential_id IS NOT NULL
                AND (exchange_lease_expires_at IS NULL OR exchange_lease_expires_at <= ?)"#,
        )
        .bind(&scope.app_id)
        .bind(&scope.tenant_id)
        .bind(&scope.user_id)
        .bind(now.to_rfc3339())
        .fetch_all(&self.pool)
        .await?;
        rows.into_iter().map(session_from_row).collect()
    }

    pub(crate) async fn claim_recovery(
        &self,
        scope: &CredentialScope,
        authorization_id: &str,
        owner_id: &str,
        lease_expires_at: DateTime<Utc>,
        now: DateTime<Utc>,
    ) -> anyhow::Result<Option<OAuthAuthorizationSession>> {
        scope.validate()?;
        validate_opaque_id("OAuth authorization", authorization_id)?;
        validate_opaque_id("OAuth recovery owner", owner_id)?;
        anyhow::ensure!(lease_expires_at > now, "OAuth recovery lease is invalid");
        let result = sqlx::query(
            r#"UPDATE oauth_broker_sessions SET
                status = 'failed',
                error_code = CASE WHEN status IN ('preparing', 'exchanging')
                    THEN 'authorization_interrupted' ELSE error_code END,
                exchange_owner_id = ?, exchange_lease_expires_at = ?, updated_at = ?
            WHERE app_id = ? AND tenant_id = ? AND user_id = ?
                AND authorization_id = ? AND status IN ('preparing', 'exchanging', 'failed')
                AND credential_id IS NOT NULL
                AND (exchange_lease_expires_at IS NULL OR exchange_lease_expires_at <= ?)"#,
        )
        .bind(owner_id)
        .bind(lease_expires_at.to_rfc3339())
        .bind(now.to_rfc3339())
        .bind(&scope.app_id)
        .bind(&scope.tenant_id)
        .bind(&scope.user_id)
        .bind(authorization_id)
        .bind(now.to_rfc3339())
        .execute(&self.pool)
        .await?;
        if result.rows_affected() == 0 {
            return Ok(None);
        }
        anyhow::ensure!(
            result.rows_affected() == 1,
            "OAuth recovery claim is ambiguous"
        );
        self.get(scope, authorization_id).await
    }

    pub(crate) async fn renew_exchange(
        &self,
        scope: &CredentialScope,
        authorization_id: &str,
        owner_id: &str,
        lease_expires_at: DateTime<Utc>,
        now: DateTime<Utc>,
    ) -> anyhow::Result<bool> {
        let result = sqlx::query(
            r#"UPDATE oauth_broker_sessions SET exchange_lease_expires_at = ?, updated_at = ?
            WHERE app_id = ? AND tenant_id = ? AND user_id = ?
                AND authorization_id = ? AND status = 'exchanging'
                AND exchange_owner_id = ? AND exchange_lease_expires_at > ?"#,
        )
        .bind(lease_expires_at.to_rfc3339())
        .bind(now.to_rfc3339())
        .bind(&scope.app_id)
        .bind(&scope.tenant_id)
        .bind(&scope.user_id)
        .bind(authorization_id)
        .bind(owner_id)
        .bind(now.to_rfc3339())
        .execute(&self.pool)
        .await?;
        Ok(result.rows_affected() == 1)
    }

    pub(crate) async fn finalize_recovery(
        &self,
        scope: &CredentialScope,
        authorization_id: &str,
        owner_id: &str,
        now: DateTime<Utc>,
    ) -> anyhow::Result<OAuthAuthorizationSession> {
        let result = sqlx::query(
            r#"UPDATE oauth_broker_sessions SET credential_id = NULL, bindings_json = '[]',
                exchange_owner_id = NULL, exchange_lease_expires_at = NULL, updated_at = ?
            WHERE app_id = ? AND tenant_id = ? AND user_id = ?
                AND authorization_id = ? AND status = 'failed' AND exchange_owner_id = ?
                AND exchange_lease_expires_at > ?"#,
        )
        .bind(now.to_rfc3339())
        .bind(&scope.app_id)
        .bind(&scope.tenant_id)
        .bind(&scope.user_id)
        .bind(authorization_id)
        .bind(owner_id)
        .bind(now.to_rfc3339())
        .execute(&self.pool)
        .await?;
        anyhow::ensure!(
            result.rows_affected() == 1,
            "OAuth recovery ownership changed"
        );
        self.get(scope, authorization_id)
            .await?
            .ok_or_else(|| anyhow::anyhow!("OAuth authorization is unavailable"))
    }

    pub(crate) async fn consume_state(
        &self,
        scope: &CredentialScope,
        state_id: &str,
        owner_id: &str,
        lease_expires_at: DateTime<Utc>,
        now: DateTime<Utc>,
    ) -> anyhow::Result<OAuthStateConsumption> {
        scope.validate()?;
        validate_opaque_id("OAuth state", state_id)?;
        validate_opaque_id("OAuth exchange owner", owner_id)?;
        anyhow::ensure!(lease_expires_at > now, "OAuth exchange lease is invalid");
        let mut tx = self.pool.begin().await?;
        let row = sqlx::query(
            r#"SELECT state_id, authorization_id, pkce_secret_id, expires_at
            FROM oauth_broker_states
            WHERE app_id = ? AND tenant_id = ? AND user_id = ? AND state_id = ?"#,
        )
        .bind(&scope.app_id)
        .bind(&scope.tenant_id)
        .bind(&scope.user_id)
        .bind(state_id)
        .fetch_optional(&mut *tx)
        .await?
        .ok_or_else(|| anyhow::anyhow!("OAuth callback state is unavailable"))?;
        let authorization_id: String = row.try_get("authorization_id")?;
        let pkce_secret_id = SecretId::parse(row.try_get("pkce_secret_id")?)?;
        let expires_at = parse_time(row.try_get("expires_at")?)?;
        let session_row = session_row_in_transaction(&mut tx, scope, &authorization_id)
            .await?
            .ok_or_else(|| anyhow::anyhow!("OAuth authorization is unavailable"))?;
        let session = session_from_row(session_row)?;
        anyhow::ensure!(
            session.status == OAuthAuthorizationStatus::Pending,
            "OAuth authorization is not pending"
        );
        if expires_at <= now {
            transition(
                &mut tx,
                scope,
                &authorization_id,
                OAuthAuthorizationStatus::Pending,
                OAuthAuthorizationStatus::Expired,
                Some("authorization_expired"),
                None,
                &[],
                now,
            )
            .await?;
            tx.commit().await?;
            return Ok(OAuthStateConsumption::Expired {
                authorization_id,
                pkce_secret_id,
            });
        }
        sqlx::query(
            r#"DELETE FROM oauth_broker_states
            WHERE app_id = ? AND tenant_id = ? AND user_id = ? AND state_id = ?"#,
        )
        .bind(&scope.app_id)
        .bind(&scope.tenant_id)
        .bind(&scope.user_id)
        .bind(state_id)
        .execute(&mut *tx)
        .await?;
        let result = sqlx::query(
            r#"UPDATE oauth_broker_sessions SET
                status = 'exchanging', error_code = NULL, bindings_json = '[]',
                exchange_owner_id = ?, exchange_lease_expires_at = ?, updated_at = ?
            WHERE app_id = ? AND tenant_id = ? AND user_id = ?
                AND authorization_id = ? AND status = 'pending'"#,
        )
        .bind(owner_id)
        .bind(lease_expires_at.to_rfc3339())
        .bind(now.to_rfc3339())
        .bind(&scope.app_id)
        .bind(&scope.tenant_id)
        .bind(&scope.user_id)
        .bind(&authorization_id)
        .execute(&mut *tx)
        .await?;
        anyhow::ensure!(
            result.rows_affected() == 1,
            "OAuth authorization changed concurrently"
        );
        tx.commit().await?;
        Ok(OAuthStateConsumption::Ready {
            session: Box::new(OAuthAuthorizationSession {
                status: OAuthAuthorizationStatus::Exchanging,
                exchange_owner_id: Some(owner_id.to_string()),
                updated_at: now,
                ..session
            }),
            pkce_secret_id,
        })
    }

    pub(crate) async fn cancel(
        &self,
        scope: &CredentialScope,
        authorization_id: &str,
        now: DateTime<Utc>,
    ) -> anyhow::Result<Option<(OAuthAuthorizationSession, SecretId)>> {
        scope.validate()?;
        let mut tx = self.pool.begin().await?;
        let row = sqlx::query(
            r#"SELECT pkce_secret_id FROM oauth_broker_states
            WHERE app_id = ? AND tenant_id = ? AND user_id = ? AND authorization_id = ?"#,
        )
        .bind(&scope.app_id)
        .bind(&scope.tenant_id)
        .bind(&scope.user_id)
        .bind(authorization_id)
        .fetch_optional(&mut *tx)
        .await?;
        let Some(row) = row else {
            return Ok(None);
        };
        let pkce_secret_id = SecretId::parse(row.try_get("pkce_secret_id")?)?;
        transition(
            &mut tx,
            scope,
            authorization_id,
            OAuthAuthorizationStatus::Pending,
            OAuthAuthorizationStatus::Cancelled,
            Some("authorization_cancelled"),
            None,
            &[],
            now,
        )
        .await?;
        tx.commit().await?;
        let session = self
            .get(scope, authorization_id)
            .await?
            .ok_or_else(|| anyhow::anyhow!("OAuth authorization is unavailable"))?;
        Ok(Some((session, pkce_secret_id)))
    }

    pub(crate) async fn cleanup_candidates(
        &self,
        scope: &CredentialScope,
        now: DateTime<Utc>,
    ) -> anyhow::Result<Vec<(String, SecretId)>> {
        scope.validate()?;
        let mut tx = self.pool.begin().await?;
        let now = now.to_rfc3339();
        sqlx::query(
            r#"UPDATE oauth_broker_sessions SET
                status = 'expired', error_code = 'authorization_expired',
                credential_id = NULL, bindings_json = '[]', updated_at = ?
            WHERE app_id = ? AND tenant_id = ? AND user_id = ?
                AND status = 'pending' AND expires_at <= ?"#,
        )
        .bind(&now)
        .bind(&scope.app_id)
        .bind(&scope.tenant_id)
        .bind(&scope.user_id)
        .bind(&now)
        .execute(&mut *tx)
        .await?;
        let rows = sqlx::query(
            r#"SELECT states.authorization_id, states.pkce_secret_id
            FROM oauth_broker_states AS states
            INNER JOIN oauth_broker_sessions AS sessions
                ON sessions.app_id = states.app_id
                AND sessions.tenant_id = states.tenant_id
                AND sessions.user_id = states.user_id
                AND sessions.authorization_id = states.authorization_id
            WHERE states.app_id = ? AND states.tenant_id = ? AND states.user_id = ?
                AND sessions.status IN ('cancelled', 'denied', 'expired', 'failed')"#,
        )
        .bind(&scope.app_id)
        .bind(&scope.tenant_id)
        .bind(&scope.user_id)
        .fetch_all(&mut *tx)
        .await?;
        tx.commit().await?;
        rows.into_iter()
            .map(|row| {
                Ok((
                    row.try_get("authorization_id")?,
                    SecretId::parse(row.try_get("pkce_secret_id")?)?,
                ))
            })
            .collect()
    }

    pub(crate) async fn delete_state(
        &self,
        scope: &CredentialScope,
        authorization_id: &str,
    ) -> anyhow::Result<()> {
        scope.validate()?;
        validate_opaque_id("OAuth authorization", authorization_id)?;
        sqlx::query(
            r#"DELETE FROM oauth_broker_states
            WHERE app_id = ? AND tenant_id = ? AND user_id = ? AND authorization_id = ?"#,
        )
        .bind(&scope.app_id)
        .bind(&scope.tenant_id)
        .bind(&scope.user_id)
        .bind(authorization_id)
        .execute(&self.pool)
        .await?;
        Ok(())
    }

    pub(crate) async fn purge_terminal(
        &self,
        scope: &CredentialScope,
        updated_before: DateTime<Utc>,
    ) -> anyhow::Result<u64> {
        scope.validate()?;
        let result = sqlx::query(
            r#"DELETE FROM oauth_broker_sessions
            WHERE app_id = ? AND tenant_id = ? AND user_id = ? AND updated_at <= ?
                AND status IN ('completed', 'denied', 'failed', 'expired', 'cancelled')
                AND (status <> 'failed' OR credential_id IS NULL)"#,
        )
        .bind(&scope.app_id)
        .bind(&scope.tenant_id)
        .bind(&scope.user_id)
        .bind(updated_before.to_rfc3339())
        .execute(&self.pool)
        .await?;
        Ok(result.rows_affected())
    }

    pub(crate) async fn mark_denied(
        &self,
        scope: &CredentialScope,
        authorization_id: &str,
        owner_id: &str,
        error_code: &str,
        now: DateTime<Utc>,
    ) -> anyhow::Result<OAuthAuthorizationSession> {
        self.finish(
            scope,
            authorization_id,
            owner_id,
            OAuthAuthorizationStatus::Denied,
            Some(error_code),
            None,
            &[],
            now,
        )
        .await
    }

    pub(crate) async fn mark_failed(
        &self,
        scope: &CredentialScope,
        authorization_id: &str,
        owner_id: &str,
        error_code: &str,
        now: DateTime<Utc>,
    ) -> anyhow::Result<OAuthAuthorizationSession> {
        self.finish(
            scope,
            authorization_id,
            owner_id,
            OAuthAuthorizationStatus::Failed,
            Some(error_code),
            None,
            &[],
            now,
        )
        .await
    }

    pub(crate) async fn mark_failed_recoverable(
        &self,
        scope: &CredentialScope,
        authorization_id: &str,
        owner_id: &str,
        error_code: &str,
        now: DateTime<Utc>,
    ) -> anyhow::Result<OAuthAuthorizationSession> {
        scope.validate()?;
        let result = sqlx::query(
            r#"UPDATE oauth_broker_sessions SET
                status = 'failed', error_code = ?, bindings_json = '[]', updated_at = ?
            WHERE app_id = ? AND tenant_id = ? AND user_id = ?
                AND authorization_id = ? AND status IN ('preparing', 'exchanging')
                AND exchange_owner_id = ? AND exchange_lease_expires_at > ?"#,
        )
        .bind(error_code)
        .bind(now.to_rfc3339())
        .bind(&scope.app_id)
        .bind(&scope.tenant_id)
        .bind(&scope.user_id)
        .bind(authorization_id)
        .bind(owner_id)
        .bind(now.to_rfc3339())
        .execute(&self.pool)
        .await?;
        anyhow::ensure!(
            result.rows_affected() == 1,
            "OAuth authorization changed concurrently"
        );
        self.get(scope, authorization_id)
            .await?
            .ok_or_else(|| anyhow::anyhow!("OAuth authorization is unavailable"))
    }

    pub(crate) async fn complete(
        &self,
        scope: &CredentialScope,
        authorization_id: &str,
        owner_id: &str,
        credential_id: &str,
        bindings: &[OAuthAuthorizationBinding],
        now: DateTime<Utc>,
    ) -> anyhow::Result<OAuthAuthorizationSession> {
        self.finish(
            scope,
            authorization_id,
            owner_id,
            OAuthAuthorizationStatus::Completed,
            None,
            Some(credential_id),
            bindings,
            now,
        )
        .await
    }

    #[allow(clippy::too_many_arguments)]
    async fn finish(
        &self,
        scope: &CredentialScope,
        authorization_id: &str,
        owner_id: &str,
        status: OAuthAuthorizationStatus,
        error_code: Option<&str>,
        credential_id: Option<&str>,
        bindings: &[OAuthAuthorizationBinding],
        now: DateTime<Utc>,
    ) -> anyhow::Result<OAuthAuthorizationSession> {
        let result = sqlx::query(
            r#"UPDATE oauth_broker_sessions SET status = ?, error_code = ?, credential_id = ?,
                bindings_json = ?, exchange_owner_id = NULL,
                exchange_lease_expires_at = NULL, updated_at = ?
            WHERE app_id = ? AND tenant_id = ? AND user_id = ?
                AND authorization_id = ? AND status = 'exchanging'
                AND exchange_owner_id = ? AND exchange_lease_expires_at > ?"#,
        )
        .bind(status_name(status))
        .bind(error_code)
        .bind(credential_id)
        .bind(serde_json::to_string(bindings)?)
        .bind(now.to_rfc3339())
        .bind(&scope.app_id)
        .bind(&scope.tenant_id)
        .bind(&scope.user_id)
        .bind(authorization_id)
        .bind(owner_id)
        .bind(now.to_rfc3339())
        .execute(&self.pool)
        .await?;
        anyhow::ensure!(
            result.rows_affected() == 1,
            "OAuth authorization ownership changed"
        );
        self.get(scope, authorization_id)
            .await?
            .ok_or_else(|| anyhow::anyhow!("OAuth authorization is unavailable"))
    }
}

async fn session_row_in_transaction(
    tx: &mut sqlx::Transaction<'_, sqlx::Sqlite>,
    scope: &CredentialScope,
    authorization_id: &str,
) -> anyhow::Result<Option<sqlx::sqlite::SqliteRow>> {
    Ok(sqlx::query(
        r#"SELECT authorization_id, provider_id, connector_ids_json,
            requested_capabilities_json, requested_scopes_json, connector_scopes_json,
            status, exchange_owner_id, exchange_lease_expires_at, credential_id,
            bindings_json, error_code, expires_at,
            created_at, updated_at
        FROM oauth_broker_sessions
        WHERE app_id = ? AND tenant_id = ? AND user_id = ? AND authorization_id = ?"#,
    )
    .bind(&scope.app_id)
    .bind(&scope.tenant_id)
    .bind(&scope.user_id)
    .bind(authorization_id)
    .fetch_optional(&mut **tx)
    .await?)
}

#[allow(clippy::too_many_arguments)]
async fn transition(
    tx: &mut sqlx::Transaction<'_, sqlx::Sqlite>,
    scope: &CredentialScope,
    authorization_id: &str,
    expected: OAuthAuthorizationStatus,
    status: OAuthAuthorizationStatus,
    error_code: Option<&str>,
    credential_id: Option<&str>,
    bindings: &[OAuthAuthorizationBinding],
    now: DateTime<Utc>,
) -> anyhow::Result<()> {
    let result = sqlx::query(
        r#"UPDATE oauth_broker_sessions SET
            status = ?, error_code = ?, credential_id = ?, bindings_json = ?, updated_at = ?
        WHERE app_id = ? AND tenant_id = ? AND user_id = ?
            AND authorization_id = ? AND status = ?"#,
    )
    .bind(status_name(status))
    .bind(error_code)
    .bind(credential_id)
    .bind(serde_json::to_string(bindings)?)
    .bind(now.to_rfc3339())
    .bind(&scope.app_id)
    .bind(&scope.tenant_id)
    .bind(&scope.user_id)
    .bind(authorization_id)
    .bind(status_name(expected))
    .execute(&mut **tx)
    .await?;
    anyhow::ensure!(
        result.rows_affected() == 1,
        "OAuth authorization changed concurrently"
    );
    Ok(())
}

fn session_from_row(row: sqlx::sqlite::SqliteRow) -> anyhow::Result<OAuthAuthorizationSession> {
    Ok(OAuthAuthorizationSession {
        authorization_id: row.try_get("authorization_id")?,
        exchange_owner_id: row.try_get("exchange_owner_id")?,
        credential_id: row.try_get("credential_id")?,
        provider_id: row.try_get("provider_id")?,
        connector_ids: serde_json::from_str(row.try_get("connector_ids_json")?)?,
        requested_capabilities: serde_json::from_str(row.try_get("requested_capabilities_json")?)?,
        requested_scopes: serde_json::from_str(row.try_get("requested_scopes_json")?)?,
        connector_scopes: serde_json::from_str(row.try_get("connector_scopes_json")?)?,
        status: parse_status(row.try_get("status")?)?,
        bindings: serde_json::from_str(row.try_get("bindings_json")?)?,
        error_code: row.try_get("error_code")?,
        expires_at: parse_time(row.try_get("expires_at")?)?,
        created_at: parse_time(row.try_get("created_at")?)?,
        updated_at: parse_time(row.try_get("updated_at")?)?,
    })
}

fn validate_session(
    scope: &CredentialScope,
    session: &OAuthAuthorizationSession,
) -> anyhow::Result<()> {
    scope.validate()?;
    validate_opaque_id("OAuth authorization", &session.authorization_id)?;
    validate_opaque_id("OAuth provider", &session.provider_id)?;
    let credential_id = session
        .credential_id
        .as_deref()
        .ok_or_else(|| anyhow::anyhow!("OAuth recovery credential is required"))?;
    validate_opaque_id("OAuth credential", credential_id)?;
    anyhow::ensure!(
        session.status == OAuthAuthorizationStatus::Preparing,
        "new OAuth authorization must be preparing"
    );
    anyhow::ensure!(
        session.expires_at > session.created_at,
        "OAuth expiry is invalid"
    );
    Ok(())
}

fn validate_opaque_id(label: &str, value: &str) -> anyhow::Result<()> {
    anyhow::ensure!(
        !value.is_empty()
            && value.len() <= 255
            && value
                .bytes()
                .all(|byte| byte.is_ascii_alphanumeric() || b"._-".contains(&byte)),
        "{label} is invalid"
    );
    Ok(())
}

fn status_name(status: OAuthAuthorizationStatus) -> &'static str {
    match status {
        OAuthAuthorizationStatus::Preparing => "preparing",
        OAuthAuthorizationStatus::Pending => "pending",
        OAuthAuthorizationStatus::Exchanging => "exchanging",
        OAuthAuthorizationStatus::Completed => "completed",
        OAuthAuthorizationStatus::Denied => "denied",
        OAuthAuthorizationStatus::Failed => "failed",
        OAuthAuthorizationStatus::Expired => "expired",
        OAuthAuthorizationStatus::Cancelled => "cancelled",
    }
}

fn parse_status(value: &str) -> anyhow::Result<OAuthAuthorizationStatus> {
    match value {
        "preparing" => Ok(OAuthAuthorizationStatus::Preparing),
        "pending" => Ok(OAuthAuthorizationStatus::Pending),
        "exchanging" => Ok(OAuthAuthorizationStatus::Exchanging),
        "completed" => Ok(OAuthAuthorizationStatus::Completed),
        "denied" => Ok(OAuthAuthorizationStatus::Denied),
        "failed" => Ok(OAuthAuthorizationStatus::Failed),
        "expired" => Ok(OAuthAuthorizationStatus::Expired),
        "cancelled" => Ok(OAuthAuthorizationStatus::Cancelled),
        _ => anyhow::bail!("OAuth authorization status is invalid"),
    }
}

async fn ensure_column(
    tx: &mut sqlx::Transaction<'_, sqlx::Sqlite>,
    table: &str,
    column: &str,
    definition: &str,
) -> anyhow::Result<()> {
    let rows = sqlx::query(&format!("PRAGMA table_info({table})"))
        .fetch_all(&mut **tx)
        .await?;
    if !rows
        .iter()
        .any(|row| row.get::<String, _>("name") == column)
    {
        sqlx::query(&format!(
            "ALTER TABLE {table} ADD COLUMN {column} {definition}"
        ))
        .execute(&mut **tx)
        .await?;
    }
    Ok(())
}

fn parse_time(value: &str) -> anyhow::Result<DateTime<Utc>> {
    Ok(DateTime::parse_from_rfc3339(value)?.with_timezone(&Utc))
}
