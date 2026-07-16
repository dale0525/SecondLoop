use crate::credential::{
    ConnectorAccount, CredentialScope, OAuthAuthorizationState, ProviderCredential, SecretId,
};
use crate::storage::Storage;
use chrono::{DateTime, Utc};
use sqlx::{Row, SqliteConnection, SqlitePool};
use std::collections::BTreeSet;

#[path = "credential_cleanup_sqlite.rs"]
mod cleanup;

const CREATE_CREDENTIAL_RECORDS: &str = r#"CREATE TABLE IF NOT EXISTS credential_records (
    app_id TEXT NOT NULL,
    tenant_id TEXT NOT NULL,
    user_id TEXT NOT NULL,
    credential_id TEXT NOT NULL,
    provider_id TEXT NOT NULL,
    provider_subject TEXT NOT NULL,
    access_secret_id TEXT NOT NULL,
    refresh_secret_id TEXT,
    granted_scopes_json TEXT NOT NULL,
    expires_at TEXT,
    revoked_at TEXT,
    updated_at TEXT NOT NULL,
    PRIMARY KEY(app_id, tenant_id, user_id, credential_id)
)"#;

const CREATE_CONNECTOR_ACCOUNTS: &str = r#"CREATE TABLE IF NOT EXISTS connector_accounts (
    app_id TEXT NOT NULL,
    tenant_id TEXT NOT NULL,
    user_id TEXT NOT NULL,
    connector_id TEXT NOT NULL,
    account_id TEXT NOT NULL,
    credential_id TEXT NOT NULL,
    allowed_scopes_json TEXT NOT NULL,
    updated_at TEXT NOT NULL,
    PRIMARY KEY(app_id, tenant_id, user_id, connector_id, account_id),
    FOREIGN KEY(app_id, tenant_id, user_id, credential_id)
        REFERENCES credential_records(app_id, tenant_id, user_id, credential_id)
        ON DELETE RESTRICT
)"#;

const CREATE_OAUTH_STATES: &str = r#"CREATE TABLE IF NOT EXISTS oauth_authorization_states (
    app_id TEXT NOT NULL,
    tenant_id TEXT NOT NULL,
    user_id TEXT NOT NULL,
    state_id TEXT NOT NULL,
    connector_id TEXT NOT NULL,
    account_id TEXT NOT NULL,
    pkce_secret_id TEXT NOT NULL,
    redirect_uri TEXT NOT NULL,
    requested_scopes_json TEXT NOT NULL,
    expires_at TEXT NOT NULL,
    created_at TEXT NOT NULL,
    PRIMARY KEY(app_id, tenant_id, user_id, state_id)
)"#;

const CREATE_SECRET_CLEANUP: &str = r#"CREATE TABLE IF NOT EXISTS credential_secret_cleanup (
    app_id TEXT NOT NULL,
    tenant_id TEXT NOT NULL,
    user_id TEXT NOT NULL,
    secret_id TEXT NOT NULL,
    created_at TEXT NOT NULL,
    not_before TEXT NOT NULL,
    phase TEXT NOT NULL DEFAULT 'cleanup',
    operation_id TEXT,
    lease_expires_at TEXT,
    cleaned_at TEXT,
    PRIMARY KEY(app_id, tenant_id, user_id, secret_id),
    CHECK (
        (phase = 'staging' AND operation_id IS NOT NULL
            AND lease_expires_at IS NOT NULL AND cleaned_at IS NULL)
        OR
        (phase = 'cleanup' AND operation_id IS NULL AND lease_expires_at IS NULL)
    )
)"#;

#[derive(Clone)]
pub struct SqliteCredentialMetadataStore {
    pool: SqlitePool,
}

impl SqliteCredentialMetadataStore {
    pub async fn from_storage(storage: &Storage) -> anyhow::Result<Self> {
        let store = Self {
            pool: storage.pool().clone(),
        };
        store.migrate().await?;
        Ok(store)
    }

    async fn migrate(&self) -> anyhow::Result<()> {
        let mut tx = self.pool.begin().await?;
        sqlx::query(CREATE_CREDENTIAL_RECORDS)
            .execute(&mut *tx)
            .await?;
        sqlx::query(CREATE_OAUTH_STATES).execute(&mut *tx).await?;
        sqlx::query(CREATE_SECRET_CLEANUP).execute(&mut *tx).await?;
        let cleanup_columns = table_columns(&mut tx, "credential_secret_cleanup").await?;
        for (column, definition) in [
            ("not_before", "TEXT NOT NULL DEFAULT ''"),
            ("phase", "TEXT NOT NULL DEFAULT 'cleanup'"),
            ("operation_id", "TEXT"),
            ("lease_expires_at", "TEXT"),
            ("cleaned_at", "TEXT"),
        ] {
            if !cleanup_columns.contains(column) {
                sqlx::query(&format!(
                    "ALTER TABLE credential_secret_cleanup ADD COLUMN {column} {definition}"
                ))
                .execute(&mut *tx)
                .await?;
            }
        }
        sqlx::query(
            "UPDATE credential_secret_cleanup SET not_before = created_at WHERE not_before = ''",
        )
        .execute(&mut *tx)
        .await?;

        let connector_columns = table_columns(&mut tx, "connector_accounts").await?;
        if !connector_columns.is_empty() && !connector_columns.contains("credential_id") {
            sqlx::query(
                r#"INSERT OR IGNORE INTO credential_records(
                    app_id, tenant_id, user_id, credential_id, provider_id, provider_subject,
                    access_secret_id, refresh_secret_id, granted_scopes_json, expires_at,
                    revoked_at, updated_at
                )
                SELECT app_id, tenant_id, user_id, secret_id, provider_id, account_id,
                    secret_id, NULL, granted_scopes_json, expires_at, NULL, updated_at
                FROM connector_accounts"#,
            )
            .execute(&mut *tx)
            .await?;
            sqlx::query("ALTER TABLE connector_accounts RENAME TO connector_accounts_legacy")
                .execute(&mut *tx)
                .await?;
            sqlx::query(CREATE_CONNECTOR_ACCOUNTS)
                .execute(&mut *tx)
                .await?;
            sqlx::query(
                r#"INSERT INTO connector_accounts(
                    app_id, tenant_id, user_id, connector_id, account_id, credential_id,
                    allowed_scopes_json, updated_at
                )
                SELECT app_id, tenant_id, user_id, connector_id, account_id, secret_id,
                    granted_scopes_json, updated_at
                FROM connector_accounts_legacy"#,
            )
            .execute(&mut *tx)
            .await?;
            sqlx::query("DROP TABLE connector_accounts_legacy")
                .execute(&mut *tx)
                .await?;
        } else {
            sqlx::query(CREATE_CONNECTOR_ACCOUNTS)
                .execute(&mut *tx)
                .await?;
        }

        if !table_columns(&mut tx, "oauth_token_records")
            .await?
            .is_empty()
        {
            sqlx::query(
                r#"INSERT OR IGNORE INTO credential_records(
                    app_id, tenant_id, user_id, credential_id, provider_id, provider_subject,
                    access_secret_id, refresh_secret_id, granted_scopes_json, expires_at,
                    revoked_at, updated_at
                )
                SELECT app_id, tenant_id, user_id, access_secret_id, provider_id, account_id,
                    access_secret_id, refresh_secret_id, granted_scopes_json, expires_at,
                    revoked_at, updated_at
                FROM oauth_token_records"#,
            )
            .execute(&mut *tx)
            .await?;
            sqlx::query(
                r#"INSERT OR IGNORE INTO connector_accounts(
                    app_id, tenant_id, user_id, connector_id, account_id, credential_id,
                    allowed_scopes_json, updated_at
                )
                SELECT app_id, tenant_id, user_id, connector_id, account_id, access_secret_id,
                    granted_scopes_json, updated_at
                FROM oauth_token_records"#,
            )
            .execute(&mut *tx)
            .await?;
        }
        tx.commit().await?;
        Ok(())
    }

    pub async fn upsert_credential(
        &self,
        scope: &CredentialScope,
        credential: &ProviderCredential,
    ) -> anyhow::Result<()> {
        validate_credential(scope, credential)?;
        sqlx::query(
            r#"INSERT INTO credential_records(
                app_id, tenant_id, user_id, credential_id, provider_id, provider_subject,
                access_secret_id, refresh_secret_id, granted_scopes_json, expires_at,
                revoked_at, updated_at
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(app_id, tenant_id, user_id, credential_id) DO UPDATE SET
                provider_id = excluded.provider_id,
                provider_subject = excluded.provider_subject,
                access_secret_id = excluded.access_secret_id,
                refresh_secret_id = excluded.refresh_secret_id,
                granted_scopes_json = excluded.granted_scopes_json,
                expires_at = excluded.expires_at,
                revoked_at = excluded.revoked_at,
                updated_at = excluded.updated_at"#,
        )
        .bind(&scope.app_id)
        .bind(&scope.tenant_id)
        .bind(&scope.user_id)
        .bind(&credential.credential_id)
        .bind(&credential.provider_id)
        .bind(&credential.provider_subject)
        .bind(credential.access_secret_id.as_str())
        .bind(credential.refresh_secret_id.as_ref().map(SecretId::as_str))
        .bind(serde_json::to_string(&credential.granted_scopes)?)
        .bind(credential.expires_at.map(|value| value.to_rfc3339()))
        .bind(credential.revoked_at.map(|value| value.to_rfc3339()))
        .bind(Utc::now().to_rfc3339())
        .execute(&self.pool)
        .await?;
        Ok(())
    }

    pub async fn get_credential(
        &self,
        scope: &CredentialScope,
        credential_id: &str,
    ) -> anyhow::Result<Option<ProviderCredential>> {
        scope.validate()?;
        let row = sqlx::query(
            r#"SELECT credential_id, provider_id, provider_subject, access_secret_id,
                refresh_secret_id, granted_scopes_json, expires_at, revoked_at
            FROM credential_records
            WHERE app_id = ? AND tenant_id = ? AND user_id = ? AND credential_id = ?"#,
        )
        .bind(&scope.app_id)
        .bind(&scope.tenant_id)
        .bind(&scope.user_id)
        .bind(credential_id)
        .fetch_optional(&self.pool)
        .await?;
        row.map(credential_from_row).transpose()
    }

    pub async fn revoke_credential_if_unbound(
        &self,
        scope: &CredentialScope,
        credential_id: &str,
        now: DateTime<Utc>,
    ) -> anyhow::Result<Option<ProviderCredential>> {
        scope.validate()?;
        let mut tx = self.pool.begin().await?;
        let credential = sqlx::query(
            r#"SELECT credential_id, provider_id, provider_subject, access_secret_id,
                refresh_secret_id, granted_scopes_json, expires_at, revoked_at
            FROM credential_records
            WHERE app_id = ? AND tenant_id = ? AND user_id = ? AND credential_id = ?"#,
        )
        .bind(&scope.app_id)
        .bind(&scope.tenant_id)
        .bind(&scope.user_id)
        .bind(credential_id)
        .fetch_optional(&mut *tx)
        .await?
        .map(credential_from_row)
        .transpose()?;
        let Some(credential) = credential else {
            return Ok(None);
        };
        let bindings: i64 = sqlx::query_scalar(
            r#"SELECT COUNT(*) FROM connector_accounts
            WHERE app_id = ? AND tenant_id = ? AND user_id = ? AND credential_id = ?"#,
        )
        .bind(&scope.app_id)
        .bind(&scope.tenant_id)
        .bind(&scope.user_id)
        .bind(credential_id)
        .fetch_one(&mut *tx)
        .await?;
        anyhow::ensure!(
            bindings == 0,
            "provider credential is still bound to a connector"
        );
        cleanup::enqueue_cleanup_tombstone(&mut tx, scope, &credential.access_secret_id).await?;
        if let Some(secret_id) = &credential.refresh_secret_id {
            cleanup::enqueue_cleanup_tombstone(&mut tx, scope, secret_id).await?;
        }
        if credential.revoked_at.is_some() {
            tx.commit().await?;
            return Ok(Some(credential));
        }
        let result = sqlx::query(
            r#"UPDATE credential_records SET revoked_at = ?, updated_at = ?
            WHERE app_id = ? AND tenant_id = ? AND user_id = ? AND credential_id = ?
                AND revoked_at IS NULL"#,
        )
        .bind(now.to_rfc3339())
        .bind(now.to_rfc3339())
        .bind(&scope.app_id)
        .bind(&scope.tenant_id)
        .bind(&scope.user_id)
        .bind(credential_id)
        .execute(&mut *tx)
        .await?;
        anyhow::ensure!(
            result.rows_affected() == 1,
            "provider credential changed concurrently"
        );
        tx.commit().await?;
        Ok(Some(credential))
    }

    pub async fn upsert_account(&self, account: &ConnectorAccount) -> anyhow::Result<()> {
        self.write_account(account, true, None).await
    }

    pub async fn insert_account(&self, account: &ConnectorAccount) -> anyhow::Result<()> {
        self.write_account(account, false, None).await
    }

    pub async fn insert_account_fenced(
        &self,
        account: &ConnectorAccount,
        authorization_id: &str,
        owner_id: &str,
        now: DateTime<Utc>,
    ) -> anyhow::Result<()> {
        self.write_account(account, false, Some((authorization_id, owner_id, now)))
            .await
    }

    async fn write_account(
        &self,
        account: &ConnectorAccount,
        overwrite: bool,
        fence: Option<(&str, &str, DateTime<Utc>)>,
    ) -> anyhow::Result<()> {
        validate_account(account)?;
        let mut tx = self.pool.begin().await?;
        if let Some((authorization_id, owner_id, now)) = fence {
            validate_oauth_fence(&mut tx, &account.scope, authorization_id, owner_id, now).await?;
        }
        let credential = sqlx::query(
            r#"SELECT credential_id, provider_id, provider_subject, access_secret_id,
                refresh_secret_id, granted_scopes_json, expires_at, revoked_at
            FROM credential_records
            WHERE app_id = ? AND tenant_id = ? AND user_id = ? AND credential_id = ?"#,
        )
        .bind(&account.scope.app_id)
        .bind(&account.scope.tenant_id)
        .bind(&account.scope.user_id)
        .bind(&account.credential_id)
        .fetch_optional(&mut *tx)
        .await?
        .map(credential_from_row)
        .transpose()?
        .ok_or_else(|| anyhow::anyhow!("connector account credential is unavailable"))?;
        anyhow::ensure!(
            account.allowed_scopes.is_subset(&credential.granted_scopes),
            "connector account scopes exceed provider credential grant"
        );
        anyhow::ensure!(
            credential.revoked_at.is_none(),
            "connector account credential is revoked"
        );
        let statement = if overwrite {
            r#"INSERT INTO connector_accounts(
                app_id, tenant_id, user_id, connector_id, account_id, credential_id,
                allowed_scopes_json, updated_at
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(app_id, tenant_id, user_id, connector_id, account_id) DO UPDATE SET
                credential_id = excluded.credential_id,
                allowed_scopes_json = excluded.allowed_scopes_json,
                updated_at = excluded.updated_at"#
        } else {
            r#"INSERT INTO connector_accounts(
                app_id, tenant_id, user_id, connector_id, account_id, credential_id,
                allowed_scopes_json, updated_at
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?)"#
        };
        sqlx::query(statement)
            .bind(&account.scope.app_id)
            .bind(&account.scope.tenant_id)
            .bind(&account.scope.user_id)
            .bind(&account.connector_id)
            .bind(&account.account_id)
            .bind(&account.credential_id)
            .bind(serde_json::to_string(&account.allowed_scopes)?)
            .bind(Utc::now().to_rfc3339())
            .execute(&mut *tx)
            .await?;
        tx.commit().await?;
        Ok(())
    }

    pub async fn get_account(
        &self,
        scope: &CredentialScope,
        connector_id: &str,
        account_id: &str,
    ) -> anyhow::Result<Option<ConnectorAccount>> {
        scope.validate()?;
        let row = sqlx::query(
            r#"SELECT connector_id, account_id, credential_id, allowed_scopes_json
            FROM connector_accounts
            WHERE app_id = ? AND tenant_id = ? AND user_id = ?
                AND connector_id = ? AND account_id = ?"#,
        )
        .bind(&scope.app_id)
        .bind(&scope.tenant_id)
        .bind(&scope.user_id)
        .bind(connector_id)
        .bind(account_id)
        .fetch_optional(&self.pool)
        .await?;
        row.map(|row| account_from_row(scope, row)).transpose()
    }

    pub async fn list_accounts(
        &self,
        scope: &CredentialScope,
        connector_id: Option<&str>,
    ) -> anyhow::Result<Vec<ConnectorAccount>> {
        scope.validate()?;
        let rows = match connector_id {
            Some(connector_id) => {
                sqlx::query(
                    r#"SELECT connector_id, account_id, credential_id, allowed_scopes_json
                    FROM connector_accounts
                    WHERE app_id = ? AND tenant_id = ? AND user_id = ? AND connector_id = ?
                    ORDER BY account_id"#,
                )
                .bind(&scope.app_id)
                .bind(&scope.tenant_id)
                .bind(&scope.user_id)
                .bind(connector_id)
                .fetch_all(&self.pool)
                .await?
            }
            None => {
                sqlx::query(
                    r#"SELECT connector_id, account_id, credential_id, allowed_scopes_json
                    FROM connector_accounts
                    WHERE app_id = ? AND tenant_id = ? AND user_id = ?
                    ORDER BY connector_id, account_id"#,
                )
                .bind(&scope.app_id)
                .bind(&scope.tenant_id)
                .bind(&scope.user_id)
                .fetch_all(&self.pool)
                .await?
            }
        };
        rows.into_iter()
            .map(|row| account_from_row(scope, row))
            .collect()
    }

    pub async fn delete_account(
        &self,
        scope: &CredentialScope,
        connector_id: &str,
        account_id: &str,
    ) -> anyhow::Result<Option<ConnectorAccount>> {
        scope.validate()?;
        let mut tx = self.pool.begin().await?;
        let account = sqlx::query(
            r#"SELECT connector_id, account_id, credential_id, allowed_scopes_json
            FROM connector_accounts
            WHERE app_id = ? AND tenant_id = ? AND user_id = ?
                AND connector_id = ? AND account_id = ?"#,
        )
        .bind(&scope.app_id)
        .bind(&scope.tenant_id)
        .bind(&scope.user_id)
        .bind(connector_id)
        .bind(account_id)
        .fetch_optional(&mut *tx)
        .await?
        .map(|row| account_from_row(scope, row))
        .transpose()?;
        let Some(account) = account else {
            return Ok(None);
        };
        let result = sqlx::query(
            r#"DELETE FROM connector_accounts
            WHERE app_id = ? AND tenant_id = ? AND user_id = ?
                AND connector_id = ? AND account_id = ?"#,
        )
        .bind(&scope.app_id)
        .bind(&scope.tenant_id)
        .bind(&scope.user_id)
        .bind(connector_id)
        .bind(account_id)
        .execute(&mut *tx)
        .await?;
        anyhow::ensure!(
            result.rows_affected() == 1,
            "connector account changed concurrently"
        );
        tx.commit().await?;
        Ok(Some(account))
    }

    pub async fn count_credential_bindings(
        &self,
        scope: &CredentialScope,
        credential_id: &str,
    ) -> anyhow::Result<u64> {
        scope.validate()?;
        let count: i64 = sqlx::query_scalar(
            r#"SELECT COUNT(*) FROM connector_accounts
            WHERE app_id = ? AND tenant_id = ? AND user_id = ? AND credential_id = ?"#,
        )
        .bind(&scope.app_id)
        .bind(&scope.tenant_id)
        .bind(&scope.user_id)
        .bind(credential_id)
        .fetch_one(&self.pool)
        .await?;
        Ok(u64::try_from(count)?)
    }

    pub async fn save_oauth_state(
        &self,
        scope: &CredentialScope,
        state: &OAuthAuthorizationState,
    ) -> anyhow::Result<()> {
        validate_oauth_state(scope, state)?;
        sqlx::query(
            r#"INSERT INTO oauth_authorization_states(
                app_id, tenant_id, user_id, state_id, connector_id, account_id,
                pkce_secret_id, redirect_uri, requested_scopes_json, expires_at, created_at
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)"#,
        )
        .bind(&scope.app_id)
        .bind(&scope.tenant_id)
        .bind(&scope.user_id)
        .bind(&state.state_id)
        .bind(&state.connector_id)
        .bind(&state.account_id)
        .bind(state.pkce_verifier_secret_id.as_str())
        .bind(&state.redirect_uri)
        .bind(serde_json::to_string(&state.requested_scopes)?)
        .bind(state.expires_at.to_rfc3339())
        .bind(Utc::now().to_rfc3339())
        .execute(&self.pool)
        .await?;
        Ok(())
    }

    pub async fn consume_oauth_state(
        &self,
        scope: &CredentialScope,
        state_id: &str,
        now: DateTime<Utc>,
    ) -> anyhow::Result<OAuthAuthorizationState> {
        scope.validate()?;
        let mut tx = self.pool.begin().await?;
        let row = sqlx::query(
            r#"SELECT state_id, connector_id, account_id, pkce_secret_id, redirect_uri,
                requested_scopes_json, expires_at
            FROM oauth_authorization_states
            WHERE app_id = ? AND tenant_id = ? AND user_id = ? AND state_id = ?"#,
        )
        .bind(&scope.app_id)
        .bind(&scope.tenant_id)
        .bind(&scope.user_id)
        .bind(state_id)
        .fetch_optional(&mut *tx)
        .await?
        .ok_or_else(|| anyhow::anyhow!("OAuth authorization state is unavailable"))?;
        let state = oauth_state_from_row(row)?;
        anyhow::ensure!(state.expires_at > now, "OAuth authorization state expired");
        let deleted = sqlx::query(
            r#"DELETE FROM oauth_authorization_states
            WHERE app_id = ? AND tenant_id = ? AND user_id = ? AND state_id = ?"#,
        )
        .bind(&scope.app_id)
        .bind(&scope.tenant_id)
        .bind(&scope.user_id)
        .bind(state_id)
        .execute(&mut *tx)
        .await?;
        anyhow::ensure!(
            deleted.rows_affected() == 1,
            "OAuth state was consumed elsewhere"
        );
        tx.commit().await?;
        Ok(state)
    }
}

async fn validate_oauth_fence(
    tx: &mut sqlx::Transaction<'_, sqlx::Sqlite>,
    scope: &CredentialScope,
    authorization_id: &str,
    owner_id: &str,
    now: DateTime<Utc>,
) -> anyhow::Result<()> {
    let owned: i64 = sqlx::query_scalar(
        r#"SELECT COUNT(*) FROM oauth_broker_sessions
        WHERE app_id = ? AND tenant_id = ? AND user_id = ?
            AND authorization_id = ? AND status = 'exchanging'
            AND exchange_owner_id = ? AND exchange_lease_expires_at > ?"#,
    )
    .bind(&scope.app_id)
    .bind(&scope.tenant_id)
    .bind(&scope.user_id)
    .bind(authorization_id)
    .bind(owner_id)
    .bind(now.to_rfc3339())
    .fetch_one(&mut **tx)
    .await?;
    anyhow::ensure!(owned == 1, "OAuth credential write ownership changed");
    Ok(())
}

async fn table_columns(
    connection: &mut SqliteConnection,
    table: &str,
) -> anyhow::Result<BTreeSet<String>> {
    let rows = sqlx::query("SELECT name FROM pragma_table_info(?)")
        .bind(table)
        .fetch_all(connection)
        .await?;
    rows.into_iter()
        .map(|row| row.try_get("name").map_err(Into::into))
        .collect()
}

fn validate_account(account: &ConnectorAccount) -> anyhow::Result<()> {
    account.scope.validate()?;
    for value in [
        &account.account_id,
        &account.connector_id,
        &account.credential_id,
    ] {
        anyhow::ensure!(
            !value.trim().is_empty(),
            "connector account field is required"
        );
        anyhow::ensure!(value.len() <= 255, "connector account field is too long");
    }
    Ok(())
}

fn validate_credential(
    scope: &CredentialScope,
    credential: &ProviderCredential,
) -> anyhow::Result<()> {
    scope.validate()?;
    for value in [
        &credential.credential_id,
        &credential.provider_id,
        &credential.provider_subject,
    ] {
        anyhow::ensure!(
            !value.trim().is_empty(),
            "provider credential field is required"
        );
        anyhow::ensure!(value.len() <= 255, "provider credential field is too long");
    }
    anyhow::ensure!(
        credential.refresh_secret_id.as_ref() != Some(&credential.access_secret_id),
        "access and refresh secret IDs must differ"
    );
    Ok(())
}

fn validate_oauth_state(
    scope: &CredentialScope,
    state: &OAuthAuthorizationState,
) -> anyhow::Result<()> {
    scope.validate()?;
    for value in [
        &state.state_id,
        &state.connector_id,
        &state.account_id,
        &state.redirect_uri,
    ] {
        anyhow::ensure!(!value.trim().is_empty(), "OAuth state field is required");
        anyhow::ensure!(value.len() <= 2048, "OAuth state field is too long");
    }
    Ok(())
}

fn account_from_row(
    scope: &CredentialScope,
    row: sqlx::sqlite::SqliteRow,
) -> anyhow::Result<ConnectorAccount> {
    Ok(ConnectorAccount {
        account_id: row.try_get("account_id")?,
        allowed_scopes: serde_json::from_str(row.try_get("allowed_scopes_json")?)?,
        connector_id: row.try_get("connector_id")?,
        credential_id: row.try_get("credential_id")?,
        scope: scope.clone(),
    })
}

fn credential_from_row(row: sqlx::sqlite::SqliteRow) -> anyhow::Result<ProviderCredential> {
    Ok(ProviderCredential {
        access_secret_id: SecretId::parse(row.try_get("access_secret_id")?)?,
        credential_id: row.try_get("credential_id")?,
        expires_at: parse_time(row.try_get("expires_at")?)?,
        granted_scopes: serde_json::from_str(row.try_get("granted_scopes_json")?)?,
        provider_id: row.try_get("provider_id")?,
        provider_subject: row.try_get("provider_subject")?,
        refresh_secret_id: row
            .try_get::<Option<String>, _>("refresh_secret_id")?
            .map(|value| SecretId::parse(&value))
            .transpose()?,
        revoked_at: parse_time(row.try_get("revoked_at")?)?,
    })
}

fn oauth_state_from_row(row: sqlx::sqlite::SqliteRow) -> anyhow::Result<OAuthAuthorizationState> {
    Ok(OAuthAuthorizationState {
        state_id: row.try_get("state_id")?,
        connector_id: row.try_get("connector_id")?,
        account_id: row.try_get("account_id")?,
        pkce_verifier_secret_id: SecretId::parse(row.try_get("pkce_secret_id")?)?,
        redirect_uri: row.try_get("redirect_uri")?,
        requested_scopes: serde_json::from_str(row.try_get("requested_scopes_json")?)?,
        expires_at: parse_required_time(row.try_get("expires_at")?)?,
    })
}

fn parse_time(value: Option<String>) -> anyhow::Result<Option<DateTime<Utc>>> {
    value.map(|value| parse_required_time(&value)).transpose()
}

fn parse_required_time(value: &str) -> anyhow::Result<DateTime<Utc>> {
    Ok(DateTime::parse_from_rfc3339(value)?.with_timezone(&Utc))
}

#[cfg(test)]
#[path = "credential_sqlite_tests.rs"]
mod tests;

#[cfg(test)]
#[path = "credential_cleanup_sqlite_tests.rs"]
mod cleanup_tests;
