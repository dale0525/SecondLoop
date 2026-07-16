use super::*;
use crate::credential::{CredentialVault, InMemorySecretStore, SecretMaterial, SecretStore};
use chrono::Duration;
use std::collections::BTreeSet;
use std::sync::{
    Arc,
    atomic::{AtomicUsize, Ordering},
};

#[derive(Default)]
struct FailSecondSaveStore {
    inner: InMemorySecretStore,
    save_count: AtomicUsize,
}

struct StalledSaveStore;

#[async_trait::async_trait]
impl SecretStore for StalledSaveStore {
    async fn save(
        &self,
        _scope: &CredentialScope,
        _secret_id: &SecretId,
        _value: SecretMaterial,
    ) -> anyhow::Result<()> {
        std::future::pending().await
    }

    async fn load(
        &self,
        _scope: &CredentialScope,
        _secret_id: &SecretId,
    ) -> anyhow::Result<Option<SecretMaterial>> {
        Ok(None)
    }

    async fn delete(
        &self,
        _scope: &CredentialScope,
        _secret_id: &SecretId,
    ) -> anyhow::Result<bool> {
        Ok(false)
    }

    async fn rotate(
        &self,
        _scope: &CredentialScope,
        _secret_id: &SecretId,
        _value: SecretMaterial,
    ) -> anyhow::Result<()> {
        anyhow::bail!("unused stalled-store rotation")
    }
}

#[async_trait::async_trait]
impl SecretStore for FailSecondSaveStore {
    async fn save(
        &self,
        scope: &CredentialScope,
        secret_id: &SecretId,
        value: SecretMaterial,
    ) -> anyhow::Result<()> {
        if self.save_count.fetch_add(1, Ordering::SeqCst) == 1 {
            anyhow::bail!("injected second secret save failure");
        }
        self.inner.save(scope, secret_id, value).await
    }

    async fn load(
        &self,
        scope: &CredentialScope,
        secret_id: &SecretId,
    ) -> anyhow::Result<Option<SecretMaterial>> {
        self.inner.load(scope, secret_id).await
    }

    async fn delete(&self, scope: &CredentialScope, secret_id: &SecretId) -> anyhow::Result<bool> {
        self.inner.delete(scope, secret_id).await
    }

    async fn rotate(
        &self,
        scope: &CredentialScope,
        secret_id: &SecretId,
        value: SecretMaterial,
    ) -> anyhow::Result<()> {
        self.inner.rotate(scope, secret_id, value).await
    }
}

fn scope() -> CredentialScope {
    CredentialScope {
        app_id: "app-a".into(),
        tenant_id: "tenant".into(),
        user_id: "user".into(),
    }
}

fn credential(secret_id: &SecretId) -> ProviderCredential {
    ProviderCredential {
        access_secret_id: secret_id.clone(),
        credential_id: "workspace-principal".into(),
        expires_at: Some(Utc::now() + Duration::minutes(10)),
        granted_scopes: BTreeSet::from(["calendar.read".into()]),
        provider_id: "workspace".into(),
        provider_subject: "provider-user-1".into(),
        refresh_secret_id: None,
        revoked_at: None,
    }
}

#[tokio::test]
async fn active_staging_is_owner_bound_and_hidden_from_cleanup() {
    let storage = Storage::connect("sqlite::memory:").await.unwrap();
    let metadata = SqliteCredentialMetadataStore::from_storage(&storage)
        .await
        .unwrap();
    let account_scope = scope();
    let secret_id = SecretId::parse("workspace.access.leased").unwrap();
    let provider_credential = credential(&secret_id);
    let now = Utc::now();
    metadata
        .stage_secret_cleanup(
            &account_scope,
            std::slice::from_ref(&secret_id),
            "operation-owner",
            now + Duration::minutes(5),
        )
        .await
        .unwrap();

    assert!(
        metadata
            .pending_secret_cleanup_at(&account_scope, now + Duration::minutes(1))
            .await
            .unwrap()
            .is_empty()
    );
    assert!(
        metadata
            .activate_credential(
                &account_scope,
                &provider_credential,
                "operation-stale",
                now + Duration::minutes(1),
            )
            .await
            .is_err()
    );
    assert!(
        metadata
            .get_credential(&account_scope, &provider_credential.credential_id)
            .await
            .unwrap()
            .is_none()
    );

    metadata
        .activate_credential(
            &account_scope,
            &provider_credential,
            "operation-owner",
            now + Duration::minutes(1),
        )
        .await
        .unwrap();
    assert!(
        metadata
            .get_credential(&account_scope, &provider_credential.credential_id)
            .await
            .unwrap()
            .is_some()
    );
}

#[tokio::test]
async fn expired_and_abandoned_staging_leave_non_reusable_tombstones() {
    let storage = Storage::connect("sqlite::memory:").await.unwrap();
    let metadata = SqliteCredentialMetadataStore::from_storage(&storage)
        .await
        .unwrap();
    let account_scope = scope();
    let expired = SecretId::parse("workspace.access.expired").unwrap();
    let abandoned = SecretId::parse("workspace.access.abandoned").unwrap();
    let now = Utc::now();
    for (secret_id, operation_id, minutes) in [
        (&expired, "operation-expired", 1),
        (&abandoned, "operation-abandoned", 5),
    ] {
        metadata
            .stage_secret_cleanup(
                &account_scope,
                std::slice::from_ref(secret_id),
                operation_id,
                now + Duration::minutes(minutes),
            )
            .await
            .unwrap();
    }
    metadata
        .abandon_secret_staging(
            &account_scope,
            std::slice::from_ref(&abandoned),
            "wrong-owner",
        )
        .await
        .unwrap();
    assert!(
        metadata
            .pending_secret_cleanup_at(&account_scope, now + Duration::seconds(30))
            .await
            .unwrap()
            .is_empty()
    );
    metadata
        .abandon_secret_staging(
            &account_scope,
            std::slice::from_ref(&abandoned),
            "operation-abandoned",
        )
        .await
        .unwrap();

    let pending = metadata
        .pending_secret_cleanup_at(&account_scope, now + Duration::minutes(2))
        .await
        .unwrap();
    assert_eq!(
        pending.iter().cloned().collect::<BTreeSet<_>>(),
        BTreeSet::from([abandoned.clone(), expired.clone()])
    );
    for secret_id in &pending {
        metadata
            .complete_secret_cleanup(&account_scope, secret_id)
            .await
            .unwrap();
    }
    assert!(
        metadata
            .pending_secret_cleanup_at(&account_scope, now + Duration::minutes(3))
            .await
            .unwrap()
            .is_empty()
    );

    metadata
        .abandon_secret_staging(
            &account_scope,
            std::slice::from_ref(&expired),
            "operation-expired",
        )
        .await
        .unwrap();
    assert_eq!(
        metadata
            .pending_secret_cleanup_at(&account_scope, now + Duration::minutes(3))
            .await
            .unwrap(),
        vec![expired.clone()]
    );
    metadata
        .complete_secret_cleanup(&account_scope, &expired)
        .await
        .unwrap();
    assert!(
        metadata
            .stage_secret_cleanup(
                &account_scope,
                std::slice::from_ref(&expired),
                "operation-reuse",
                now + Duration::minutes(5),
            )
            .await
            .is_err()
    );
}

#[tokio::test]
async fn schema_upgrade_preserves_legacy_not_before_fencing() {
    let storage = Storage::connect("sqlite::memory:").await.unwrap();
    sqlx::query(
        r#"CREATE TABLE credential_secret_cleanup (
            app_id TEXT NOT NULL, tenant_id TEXT NOT NULL, user_id TEXT NOT NULL,
            secret_id TEXT NOT NULL, created_at TEXT NOT NULL, not_before TEXT NOT NULL,
            PRIMARY KEY(app_id, tenant_id, user_id, secret_id)
        )"#,
    )
    .execute(storage.pool())
    .await
    .unwrap();
    let now = Utc::now();
    for (secret_id, not_before) in [
        ("legacy.cleanup.ready", now - Duration::minutes(1)),
        ("legacy.cleanup.fenced", now + Duration::minutes(5)),
    ] {
        sqlx::query(
            r#"INSERT INTO credential_secret_cleanup(
                app_id, tenant_id, user_id, secret_id, created_at, not_before
            ) VALUES ('app-a', 'tenant', 'user', ?, ?, ?)"#,
        )
        .bind(secret_id)
        .bind(now.to_rfc3339())
        .bind(not_before.to_rfc3339())
        .execute(storage.pool())
        .await
        .unwrap();
    }

    let metadata = SqliteCredentialMetadataStore::from_storage(&storage)
        .await
        .unwrap();
    assert_eq!(
        metadata
            .pending_secret_cleanup_at(&scope(), now)
            .await
            .unwrap(),
        vec![SecretId::parse("legacy.cleanup.ready").unwrap()]
    );
    metadata
        .complete_secret_cleanup(&scope(), &SecretId::parse("legacy.cleanup.ready").unwrap())
        .await
        .unwrap();
    sqlx::query(
        r#"INSERT INTO credential_secret_cleanup(
            app_id, tenant_id, user_id, secret_id, created_at, not_before
        ) VALUES ('app-a', 'tenant', 'user', 'legacy.cleanup.rolling', ?, ?)"#,
    )
    .bind(now.to_rfc3339())
    .bind((now + Duration::minutes(10)).to_rfc3339())
    .execute(storage.pool())
    .await
    .unwrap();
    assert_eq!(
        metadata
            .pending_secret_cleanup_at(&scope(), now + Duration::minutes(11))
            .await
            .unwrap(),
        vec![
            SecretId::parse("legacy.cleanup.fenced").unwrap(),
            SecretId::parse("legacy.cleanup.rolling").unwrap(),
        ]
    );
}

#[tokio::test]
async fn active_secret_id_cannot_be_overwritten_during_rotation() {
    let storage = Storage::connect("sqlite::memory:").await.unwrap();
    let metadata = SqliteCredentialMetadataStore::from_storage(&storage)
        .await
        .unwrap();
    let secrets = Arc::new(InMemorySecretStore::default());
    let vault = CredentialVault::new_persistent(secrets.clone(), metadata);
    let account_scope = scope();
    let secret_id = SecretId::parse("workspace.access.active").unwrap();
    let provider_credential = credential(&secret_id);
    vault
        .save_provider_credential(
            &account_scope,
            provider_credential.clone(),
            SecretMaterial::new("original-secret").unwrap(),
            None,
        )
        .await
        .unwrap();

    assert!(
        vault
            .replace_provider_credential(
                &account_scope,
                provider_credential,
                SecretMaterial::new("replacement-secret").unwrap(),
                None,
            )
            .await
            .is_err()
    );
    let retained = secrets
        .load(&account_scope, &secret_id)
        .await
        .unwrap()
        .unwrap();
    assert_eq!(retained.expose_bytes(), b"original-secret");
}

#[tokio::test]
async fn partial_secret_save_failure_abandons_and_cleans_the_whole_operation() {
    let storage = Storage::connect("sqlite::memory:").await.unwrap();
    let metadata = SqliteCredentialMetadataStore::from_storage(&storage)
        .await
        .unwrap();
    let secrets = Arc::new(FailSecondSaveStore::default());
    let vault = CredentialVault::new_persistent(secrets.clone(), metadata.clone());
    let account_scope = scope();
    let access_id = SecretId::parse("workspace.access.partial").unwrap();
    let refresh_id = SecretId::parse("workspace.refresh.partial").unwrap();
    let mut provider_credential = credential(&access_id);
    provider_credential.refresh_secret_id = Some(refresh_id.clone());

    assert!(
        vault
            .save_provider_credential(
                &account_scope,
                provider_credential.clone(),
                SecretMaterial::new("partial-access").unwrap(),
                Some(SecretMaterial::new("partial-refresh").unwrap()),
            )
            .await
            .is_err()
    );
    assert!(
        metadata
            .get_credential(&account_scope, &provider_credential.credential_id)
            .await
            .unwrap()
            .is_none()
    );
    for secret_id in [&access_id, &refresh_id] {
        assert!(
            secrets
                .load(&account_scope, secret_id)
                .await
                .unwrap()
                .is_none()
        );
    }
    assert!(
        metadata
            .pending_secret_cleanup(&account_scope)
            .await
            .unwrap()
            .is_empty()
    );
    let tombstones: i64 = sqlx::query_scalar(
        "SELECT COUNT(*) FROM credential_secret_cleanup WHERE cleaned_at IS NOT NULL",
    )
    .fetch_one(storage.pool())
    .await
    .unwrap();
    assert_eq!(tombstones, 2);
}

#[tokio::test]
async fn stalled_secret_save_times_out_and_leaves_only_a_cleaned_tombstone() {
    let storage = Storage::connect("sqlite::memory:").await.unwrap();
    let metadata = SqliteCredentialMetadataStore::from_storage(&storage)
        .await
        .unwrap();
    let vault = CredentialVault::new_persistent(Arc::new(StalledSaveStore), metadata.clone());
    let account_scope = scope();
    let secret_id = SecretId::parse("workspace.access.stalled").unwrap();

    let error = vault
        .save_provider_credential(
            &account_scope,
            credential(&secret_id),
            SecretMaterial::new("stalled-secret").unwrap(),
            None,
        )
        .await
        .unwrap_err();

    assert!(error.to_string().contains("timed out"));
    assert!(
        metadata
            .pending_secret_cleanup(&account_scope)
            .await
            .unwrap()
            .is_empty()
    );
    let tombstones: i64 = sqlx::query_scalar(
        "SELECT COUNT(*) FROM credential_secret_cleanup WHERE cleaned_at IS NOT NULL",
    )
    .fetch_one(storage.pool())
    .await
    .unwrap();
    assert_eq!(tombstones, 1);
}

#[tokio::test]
async fn malformed_cleanup_state_fails_closed_after_legacy_schema_upgrade() {
    let storage = Storage::connect("sqlite::memory:").await.unwrap();
    sqlx::query(
        r#"CREATE TABLE credential_secret_cleanup (
            app_id TEXT NOT NULL, tenant_id TEXT NOT NULL, user_id TEXT NOT NULL,
            secret_id TEXT NOT NULL, created_at TEXT NOT NULL, not_before TEXT NOT NULL,
            PRIMARY KEY(app_id, tenant_id, user_id, secret_id)
        )"#,
    )
    .execute(storage.pool())
    .await
    .unwrap();
    let now = Utc::now();
    sqlx::query(
        r#"INSERT INTO credential_secret_cleanup(
            app_id, tenant_id, user_id, secret_id, created_at, not_before
        ) VALUES ('app-a', 'tenant', 'user', 'legacy.invalid', ?, ?)"#,
    )
    .bind(now.to_rfc3339())
    .bind(now.to_rfc3339())
    .execute(storage.pool())
    .await
    .unwrap();
    let metadata = SqliteCredentialMetadataStore::from_storage(&storage)
        .await
        .unwrap();
    sqlx::query(
        "UPDATE credential_secret_cleanup SET phase = 'staging', operation_id = NULL WHERE secret_id = 'legacy.invalid'",
    )
    .execute(storage.pool())
    .await
    .unwrap();

    assert!(
        metadata
            .pending_secret_cleanup_at(&scope(), now)
            .await
            .is_err()
    );
}

#[tokio::test]
async fn staging_rejects_empty_duplicate_and_overlong_lease_requests() {
    let storage = Storage::connect("sqlite::memory:").await.unwrap();
    let metadata = SqliteCredentialMetadataStore::from_storage(&storage)
        .await
        .unwrap();
    let account_scope = scope();
    let secret_id = SecretId::parse("workspace.access.invalid-stage").unwrap();
    let now = Utc::now();

    assert!(
        metadata
            .stage_secret_cleanup(
                &account_scope,
                &[],
                "operation-empty",
                now + Duration::minutes(1),
            )
            .await
            .is_err()
    );
    assert!(
        metadata
            .stage_secret_cleanup(
                &account_scope,
                &[secret_id.clone(), secret_id.clone()],
                "operation-duplicate",
                now + Duration::minutes(1),
            )
            .await
            .is_err()
    );
    assert!(
        metadata
            .stage_secret_cleanup(
                &account_scope,
                std::slice::from_ref(&secret_id),
                "operation-overlong",
                now + Duration::minutes(cleanup::MAX_STAGING_LEASE_MINUTES + 1),
            )
            .await
            .is_err()
    );
}
