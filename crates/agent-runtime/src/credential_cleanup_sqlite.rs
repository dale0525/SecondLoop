use super::*;

pub(super) const MAX_STAGING_LEASE_MINUTES: i64 = 10;

impl SqliteCredentialMetadataStore {
    pub async fn stage_secret_cleanup(
        &self,
        scope: &CredentialScope,
        secret_ids: &[SecretId],
        operation_id: &str,
        lease_expires_at: DateTime<Utc>,
    ) -> anyhow::Result<()> {
        scope.validate()?;
        validate_cleanup_operation(operation_id)?;
        let now = Utc::now();
        anyhow::ensure!(
            (1..=2).contains(&secret_ids.len())
                && secret_ids
                    .iter()
                    .map(SecretId::as_str)
                    .collect::<BTreeSet<_>>()
                    .len()
                    == secret_ids.len(),
            "credential secret staging set is invalid"
        );
        anyhow::ensure!(
            lease_expires_at > now
                && lease_expires_at <= now + chrono::Duration::minutes(MAX_STAGING_LEASE_MINUTES),
            "credential staging lease is invalid"
        );
        let mut tx = self.pool.begin().await?;
        for secret_id in secret_ids {
            let references: i64 = sqlx::query_scalar(
                r#"SELECT COUNT(*) FROM credential_records
                WHERE app_id = ? AND tenant_id = ? AND user_id = ?
                    AND (access_secret_id = ? OR refresh_secret_id = ?)"#,
            )
            .bind(&scope.app_id)
            .bind(&scope.tenant_id)
            .bind(&scope.user_id)
            .bind(secret_id.as_str())
            .bind(secret_id.as_str())
            .fetch_one(&mut *tx)
            .await?;
            anyhow::ensure!(references == 0, "credential secret ID is already in use");
            sqlx::query(
                r#"INSERT INTO credential_secret_cleanup(
                    app_id, tenant_id, user_id, secret_id, created_at, not_before,
                    phase, operation_id, lease_expires_at
                ) VALUES (?, ?, ?, ?, ?, ?, 'staging', ?, ?)"#,
            )
            .bind(&scope.app_id)
            .bind(&scope.tenant_id)
            .bind(&scope.user_id)
            .bind(secret_id.as_str())
            .bind(now.to_rfc3339())
            .bind(lease_expires_at.to_rfc3339())
            .bind(operation_id)
            .bind(lease_expires_at.to_rfc3339())
            .execute(&mut *tx)
            .await?;
        }
        tx.commit().await?;
        Ok(())
    }

    pub async fn activate_credential(
        &self,
        scope: &CredentialScope,
        credential: &ProviderCredential,
        operation_id: &str,
        now: DateTime<Utc>,
    ) -> anyhow::Result<()> {
        validate_credential(scope, credential)?;
        let mut tx = self.pool.begin().await?;
        validate_staged_credential(&mut tx, scope, credential, operation_id, now).await?;
        upsert_credential_in_transaction(&mut tx, scope, credential).await?;
        consume_staged_credential(&mut tx, scope, credential, operation_id, now).await?;
        tx.commit().await?;
        Ok(())
    }

    #[allow(clippy::too_many_arguments)]
    pub async fn activate_credential_fenced(
        &self,
        scope: &CredentialScope,
        credential: &ProviderCredential,
        operation_id: &str,
        authorization_id: &str,
        owner_id: &str,
        now: DateTime<Utc>,
    ) -> anyhow::Result<()> {
        validate_credential(scope, credential)?;
        let mut tx = self.pool.begin().await?;
        validate_oauth_fence(&mut tx, scope, authorization_id, owner_id, now).await?;
        validate_staged_credential(&mut tx, scope, credential, operation_id, now).await?;
        upsert_credential_in_transaction(&mut tx, scope, credential).await?;
        consume_staged_credential(&mut tx, scope, credential, operation_id, now).await?;
        tx.commit().await?;
        Ok(())
    }

    pub async fn replace_credential_transactional(
        &self,
        scope: &CredentialScope,
        credential: &ProviderCredential,
        operation_id: &str,
        now: DateTime<Utc>,
    ) -> anyhow::Result<ProviderCredential> {
        validate_credential(scope, credential)?;
        let mut tx = self.pool.begin().await?;
        let current = sqlx::query(
            r#"SELECT credential_id, provider_id, provider_subject, access_secret_id,
                refresh_secret_id, granted_scopes_json, expires_at, revoked_at
            FROM credential_records
            WHERE app_id = ? AND tenant_id = ? AND user_id = ? AND credential_id = ?"#,
        )
        .bind(&scope.app_id)
        .bind(&scope.tenant_id)
        .bind(&scope.user_id)
        .bind(&credential.credential_id)
        .fetch_optional(&mut *tx)
        .await?
        .map(credential_from_row)
        .transpose()?
        .ok_or_else(|| anyhow::anyhow!("provider credential is unavailable"))?;
        anyhow::ensure!(
            current.revoked_at.is_none(),
            "provider credential is revoked"
        );
        anyhow::ensure!(
            current.provider_id == credential.provider_id
                && current.provider_subject == credential.provider_subject,
            "provider credential identity cannot change during rotation"
        );
        let rows = sqlx::query(
            r#"SELECT allowed_scopes_json FROM connector_accounts
            WHERE app_id = ? AND tenant_id = ? AND user_id = ? AND credential_id = ?"#,
        )
        .bind(&scope.app_id)
        .bind(&scope.tenant_id)
        .bind(&scope.user_id)
        .bind(&credential.credential_id)
        .fetch_all(&mut *tx)
        .await?;
        for row in rows {
            let allowed: BTreeSet<String> =
                serde_json::from_str(row.try_get("allowed_scopes_json")?)?;
            anyhow::ensure!(
                allowed.is_subset(&credential.granted_scopes),
                "rotated provider grant no longer covers a Connector binding"
            );
        }
        validate_staged_credential(&mut tx, scope, credential, operation_id, now).await?;
        upsert_credential_in_transaction(&mut tx, scope, credential).await?;
        consume_staged_credential(&mut tx, scope, credential, operation_id, now).await?;
        if current.access_secret_id != credential.access_secret_id {
            enqueue_cleanup_tombstone(&mut tx, scope, &current.access_secret_id).await?;
        }
        if let Some(secret_id) = &current.refresh_secret_id
            && credential.refresh_secret_id.as_ref() != Some(secret_id)
        {
            enqueue_cleanup_tombstone(&mut tx, scope, secret_id).await?;
        }
        tx.commit().await?;
        Ok(current)
    }

    pub async fn abandon_secret_staging(
        &self,
        scope: &CredentialScope,
        secret_ids: &[SecretId],
        operation_id: &str,
    ) -> anyhow::Result<()> {
        scope.validate()?;
        validate_cleanup_operation(operation_id)?;
        let mut tx = self.pool.begin().await?;
        for secret_id in secret_ids {
            sqlx::query(
                r#"UPDATE credential_secret_cleanup SET phase = 'cleanup', operation_id = NULL,
                    lease_expires_at = NULL, cleaned_at = NULL, not_before = ?
                WHERE app_id = ? AND tenant_id = ? AND user_id = ? AND secret_id = ?
                    AND ((phase = 'staging' AND operation_id = ?)
                        OR (phase = 'cleanup' AND operation_id IS NULL))
                    AND NOT EXISTS (
                        SELECT 1 FROM credential_records
                        WHERE app_id = ? AND tenant_id = ? AND user_id = ?
                            AND (access_secret_id = ? OR refresh_secret_id = ?)
                    )"#,
            )
            .bind(Utc::now().to_rfc3339())
            .bind(&scope.app_id)
            .bind(&scope.tenant_id)
            .bind(&scope.user_id)
            .bind(secret_id.as_str())
            .bind(operation_id)
            .bind(&scope.app_id)
            .bind(&scope.tenant_id)
            .bind(&scope.user_id)
            .bind(secret_id.as_str())
            .bind(secret_id.as_str())
            .execute(&mut *tx)
            .await?;
        }
        tx.commit().await?;
        Ok(())
    }

    pub async fn pending_secret_cleanup(
        &self,
        scope: &CredentialScope,
    ) -> anyhow::Result<Vec<SecretId>> {
        self.pending_secret_cleanup_at(scope, Utc::now()).await
    }

    pub(crate) async fn pending_secret_cleanup_at(
        &self,
        scope: &CredentialScope,
        now: DateTime<Utc>,
    ) -> anyhow::Result<Vec<SecretId>> {
        scope.validate()?;
        let mut tx = self.pool.begin().await?;
        validate_cleanup_rows(&mut tx, scope).await?;
        sqlx::query(
            r#"UPDATE credential_secret_cleanup SET phase = 'cleanup', operation_id = NULL,
                lease_expires_at = NULL, cleaned_at = NULL, not_before = ?
            WHERE app_id = ? AND tenant_id = ? AND user_id = ? AND phase = 'staging'
                AND lease_expires_at <= ?"#,
        )
        .bind(now.to_rfc3339())
        .bind(&scope.app_id)
        .bind(&scope.tenant_id)
        .bind(&scope.user_id)
        .bind(now.to_rfc3339())
        .execute(&mut *tx)
        .await?;
        let rows = sqlx::query(
            r#"SELECT secret_id FROM credential_secret_cleanup
            WHERE app_id = ? AND tenant_id = ? AND user_id = ? AND phase = 'cleanup'
                AND not_before <= ? AND cleaned_at IS NULL
            ORDER BY created_at, secret_id"#,
        )
        .bind(&scope.app_id)
        .bind(&scope.tenant_id)
        .bind(&scope.user_id)
        .bind(now.to_rfc3339())
        .fetch_all(&mut *tx)
        .await?;
        tx.commit().await?;
        rows.into_iter()
            .map(|row| SecretId::parse(row.try_get("secret_id")?))
            .collect()
    }

    pub async fn complete_secret_cleanup(
        &self,
        scope: &CredentialScope,
        secret_id: &SecretId,
    ) -> anyhow::Result<()> {
        scope.validate()?;
        let result = sqlx::query(
            r#"UPDATE credential_secret_cleanup SET cleaned_at = ?
            WHERE app_id = ? AND tenant_id = ? AND user_id = ? AND secret_id = ?
                AND phase = 'cleanup'"#,
        )
        .bind(Utc::now().to_rfc3339())
        .bind(&scope.app_id)
        .bind(&scope.tenant_id)
        .bind(&scope.user_id)
        .bind(secret_id.as_str())
        .execute(&self.pool)
        .await?;
        anyhow::ensure!(
            result.rows_affected() == 1,
            "credential cleanup ownership changed"
        );
        Ok(())
    }
}

async fn validate_staged_credential(
    tx: &mut sqlx::Transaction<'_, sqlx::Sqlite>,
    scope: &CredentialScope,
    credential: &ProviderCredential,
    operation_id: &str,
    now: DateTime<Utc>,
) -> anyhow::Result<()> {
    for secret_id in
        std::iter::once(&credential.access_secret_id).chain(credential.refresh_secret_id.iter())
    {
        let staged: i64 = sqlx::query_scalar(
            r#"SELECT COUNT(*) FROM credential_secret_cleanup
            WHERE app_id = ? AND tenant_id = ? AND user_id = ? AND secret_id = ?
                AND phase = 'staging' AND operation_id = ? AND lease_expires_at > ?"#,
        )
        .bind(&scope.app_id)
        .bind(&scope.tenant_id)
        .bind(&scope.user_id)
        .bind(secret_id.as_str())
        .bind(operation_id)
        .bind(now.to_rfc3339())
        .fetch_one(&mut **tx)
        .await?;
        anyhow::ensure!(staged == 1, "credential secret staging ownership changed");
    }
    Ok(())
}

async fn consume_staged_credential(
    tx: &mut sqlx::Transaction<'_, sqlx::Sqlite>,
    scope: &CredentialScope,
    credential: &ProviderCredential,
    operation_id: &str,
    now: DateTime<Utc>,
) -> anyhow::Result<()> {
    for secret_id in
        std::iter::once(&credential.access_secret_id).chain(credential.refresh_secret_id.iter())
    {
        let result = sqlx::query(
            r#"DELETE FROM credential_secret_cleanup
            WHERE app_id = ? AND tenant_id = ? AND user_id = ? AND secret_id = ?
                AND phase = 'staging' AND operation_id = ? AND lease_expires_at > ?"#,
        )
        .bind(&scope.app_id)
        .bind(&scope.tenant_id)
        .bind(&scope.user_id)
        .bind(secret_id.as_str())
        .bind(operation_id)
        .bind(now.to_rfc3339())
        .execute(&mut **tx)
        .await?;
        anyhow::ensure!(
            result.rows_affected() == 1,
            "credential staging ownership changed"
        );
    }
    Ok(())
}

pub(super) async fn enqueue_cleanup_tombstone(
    tx: &mut sqlx::Transaction<'_, sqlx::Sqlite>,
    scope: &CredentialScope,
    secret_id: &SecretId,
) -> anyhow::Result<()> {
    let now = Utc::now();
    let result = sqlx::query(
        r#"INSERT INTO credential_secret_cleanup(
            app_id, tenant_id, user_id, secret_id, created_at, not_before,
            phase, operation_id, lease_expires_at, cleaned_at
        ) VALUES (?, ?, ?, ?, ?, ?, 'cleanup', NULL, NULL, NULL)
        ON CONFLICT(app_id, tenant_id, user_id, secret_id) DO UPDATE SET
            phase = 'cleanup', operation_id = NULL, lease_expires_at = NULL,
            cleaned_at = NULL, not_before = excluded.not_before
        WHERE credential_secret_cleanup.phase = 'cleanup'"#,
    )
    .bind(&scope.app_id)
    .bind(&scope.tenant_id)
    .bind(&scope.user_id)
    .bind(secret_id.as_str())
    .bind(now.to_rfc3339())
    .bind(now.to_rfc3339())
    .execute(&mut **tx)
    .await?;
    anyhow::ensure!(
        result.rows_affected() == 1,
        "credential cleanup ownership changed"
    );
    Ok(())
}

async fn upsert_credential_in_transaction(
    tx: &mut sqlx::Transaction<'_, sqlx::Sqlite>,
    scope: &CredentialScope,
    credential: &ProviderCredential,
) -> anyhow::Result<()> {
    sqlx::query(
        r#"INSERT INTO credential_records(
            app_id, tenant_id, user_id, credential_id, provider_id, provider_subject,
            access_secret_id, refresh_secret_id, granted_scopes_json, expires_at,
            revoked_at, updated_at
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ON CONFLICT(app_id, tenant_id, user_id, credential_id) DO UPDATE SET
            provider_id = excluded.provider_id, provider_subject = excluded.provider_subject,
            access_secret_id = excluded.access_secret_id,
            refresh_secret_id = excluded.refresh_secret_id,
            granted_scopes_json = excluded.granted_scopes_json,
            expires_at = excluded.expires_at, revoked_at = excluded.revoked_at,
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
    .execute(&mut **tx)
    .await?;
    Ok(())
}

fn validate_cleanup_operation(operation_id: &str) -> anyhow::Result<()> {
    anyhow::ensure!(
        !operation_id.is_empty()
            && operation_id.len() <= 255
            && operation_id
                .bytes()
                .all(|byte| byte.is_ascii_alphanumeric() || b"._-".contains(&byte)),
        "credential cleanup operation is invalid"
    );
    Ok(())
}

async fn validate_cleanup_rows(
    tx: &mut sqlx::Transaction<'_, sqlx::Sqlite>,
    scope: &CredentialScope,
) -> anyhow::Result<()> {
    let invalid: i64 = sqlx::query_scalar(
        r#"SELECT COUNT(*) FROM credential_secret_cleanup
        WHERE app_id = ? AND tenant_id = ? AND user_id = ? AND (
            phase NOT IN ('staging', 'cleanup')
            OR julianday(not_before) IS NULL
            OR (cleaned_at IS NOT NULL AND julianday(cleaned_at) IS NULL)
            OR (phase = 'staging' AND (
                operation_id IS NULL OR operation_id = ''
                OR lease_expires_at IS NULL OR lease_expires_at = ''
                OR julianday(lease_expires_at) IS NULL
                OR cleaned_at IS NOT NULL
            ))
            OR (phase = 'cleanup' AND (
                operation_id IS NOT NULL OR lease_expires_at IS NOT NULL
            ))
        )"#,
    )
    .bind(&scope.app_id)
    .bind(&scope.tenant_id)
    .bind(&scope.user_id)
    .fetch_one(&mut **tx)
    .await?;
    anyhow::ensure!(invalid == 0, "credential cleanup state is invalid");
    Ok(())
}
