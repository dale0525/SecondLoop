use crate::credential::SecretMaterial;
use async_trait::async_trait;
use serde::Serialize;
use sqlx::SqlitePool;
use std::fmt;
use std::sync::Arc;

/// The runtime's verified view of active-database protection.
///
/// `Configured` deliberately does not imply that database bytes are encrypted.
/// Only a trusted provider may return `Active` after it has opened and verified
/// the database with the supplied key.
#[derive(Clone, Copy, Debug, Default, Eq, PartialEq, Serialize)]
#[serde(rename_all = "snake_case")]
pub enum StorageProtectionState {
    #[default]
    NotProvided,
    Configured,
    Active,
    Error,
}

impl StorageProtectionState {
    pub const fn as_str(self) -> &'static str {
        match self {
            Self::NotProvided => "not_provided",
            Self::Configured => "configured",
            Self::Active => "active",
            Self::Error => "error",
        }
    }
}

#[derive(Clone, Debug, Default, Eq, PartialEq)]
pub struct StorageProtectionStatus {
    state: StorageProtectionState,
    provider_id: Option<Arc<str>>,
}

impl StorageProtectionStatus {
    pub fn state(&self) -> StorageProtectionState {
        self.state
    }

    pub fn provider_id(&self) -> Option<&str> {
        self.provider_id.as_deref()
    }

    fn new(state: StorageProtectionState, provider_id: Option<Arc<str>>) -> Self {
        Self { state, provider_id }
    }
}

/// Policy handed to a provider before it inspects or opens an existing file.
///
/// Providers must reject plaintext SQLite by default. A provider may migrate
/// plaintext only when `MigrateWithVerifiedRollback` is selected, and must
/// verify a rollback copy before replacing the source database.
#[derive(Clone, Copy, Debug, Default, Eq, PartialEq)]
pub enum PlaintextStoragePolicy {
    #[default]
    Reject,
    MigrateWithVerifiedRollback,
}

/// A short-lived, borrowed key view available only while a provider opens the
/// database. Providers must not log, serialize, or include these bytes in an
/// error, and should avoid copying them unless their backend requires it.
#[derive(Clone, Copy)]
pub struct StorageProtectionKey<'a>(&'a [u8]);

impl<'a> StorageProtectionKey<'a> {
    pub fn expose_bytes(self) -> &'a [u8] {
        self.0
    }
}

impl fmt::Debug for StorageProtectionKey<'_> {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter.write_str("StorageProtectionKey([REDACTED])")
    }
}

pub struct StorageProtectionOpenRequest<'a> {
    database_url: &'a str,
    key: StorageProtectionKey<'a>,
    plaintext_policy: PlaintextStoragePolicy,
}

impl<'a> StorageProtectionOpenRequest<'a> {
    pub fn database_url(&self) -> &'a str {
        self.database_url
    }

    pub fn key(&self) -> StorageProtectionKey<'a> {
        self.key
    }

    pub fn plaintext_policy(&self) -> PlaintextStoragePolicy {
        self.plaintext_policy
    }
}

impl fmt::Debug for StorageProtectionOpenRequest<'_> {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter
            .debug_struct("StorageProtectionOpenRequest")
            .field("database_url", &self.database_url)
            .field("key", &self.key)
            .field("plaintext_policy", &self.plaintext_policy)
            .finish()
    }
}

/// A pool that a trusted provider has opened and verified as protected.
pub struct ProtectedStoragePool {
    pool: SqlitePool,
}

impl ProtectedStoragePool {
    pub fn verified(pool: SqlitePool) -> Self {
        Self { pool }
    }

    fn into_pool(self) -> SqlitePool {
        self.pool
    }
}

#[async_trait]
pub trait StorageProtectionProvider: Send + Sync {
    /// Stable, non-secret identifier used only for diagnostics.
    fn provider_id(&self) -> &'static str;

    /// Perform plaintext preflight, any explicitly authorized migration, open
    /// the pool with the borrowed key, and verify protection before returning.
    async fn open(
        &self,
        request: StorageProtectionOpenRequest<'_>,
    ) -> anyhow::Result<ProtectedStoragePool>;
}

#[derive(Clone, Default)]
pub struct StorageOpenOptions {
    key: Option<Arc<SecretMaterial>>,
    provider: Option<Arc<dyn StorageProtectionProvider>>,
    plaintext_policy: PlaintextStoragePolicy,
}

impl StorageOpenOptions {
    pub fn with_key(mut self, key: Arc<SecretMaterial>) -> Self {
        self.key = Some(key);
        self
    }

    pub fn with_provider(mut self, provider: Arc<dyn StorageProtectionProvider>) -> Self {
        self.provider = Some(provider);
        self
    }

    pub fn with_plaintext_policy(mut self, policy: PlaintextStoragePolicy) -> Self {
        self.plaintext_policy = policy;
        self
    }
}

impl fmt::Debug for StorageOpenOptions {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter
            .debug_struct("StorageOpenOptions")
            .field("key", &self.key.as_ref().map(|_| "[REDACTED]"))
            .field(
                "provider_id",
                &self
                    .provider
                    .as_ref()
                    .map(|provider| provider.provider_id()),
            )
            .field("plaintext_policy", &self.plaintext_policy)
            .finish()
    }
}

#[derive(Debug, thiserror::Error)]
#[error("storage protection provider failed")]
pub struct StorageProtectionOpenError {
    status: StorageProtectionStatus,
    #[source]
    source: anyhow::Error,
}

impl StorageProtectionOpenError {
    pub fn status(&self) -> &StorageProtectionStatus {
        &self.status
    }
}

pub(crate) async fn open_storage_pool(
    database_url: &str,
    options: StorageOpenOptions,
) -> anyhow::Result<(SqlitePool, StorageProtectionStatus)> {
    let StorageOpenOptions {
        key,
        provider,
        plaintext_policy,
    } = options;
    let provider_id = provider
        .as_ref()
        .map(|provider| Arc::<str>::from(provider.provider_id()));

    match (key, provider) {
        (Some(key), Some(provider)) => {
            let request = StorageProtectionOpenRequest {
                database_url,
                key: StorageProtectionKey(key.expose_bytes()),
                plaintext_policy,
            };
            let protected =
                provider
                    .open(request)
                    .await
                    .map_err(|source| StorageProtectionOpenError {
                        status: StorageProtectionStatus::new(
                            StorageProtectionState::Error,
                            provider_id.clone(),
                        ),
                        source,
                    })?;
            Ok((
                protected.into_pool(),
                StorageProtectionStatus::new(StorageProtectionState::Active, provider_id),
            ))
        }
        (Some(_), None) => Ok((
            open_plaintext_pool(database_url).await?,
            StorageProtectionStatus::new(StorageProtectionState::Configured, None),
        )),
        (None, Some(_)) => Err(StorageProtectionOpenError {
            status: StorageProtectionStatus::new(StorageProtectionState::Error, provider_id),
            source: anyhow::anyhow!("storage protection key is not provided"),
        }
        .into()),
        (None, None) => Ok((
            open_plaintext_pool(database_url).await?,
            StorageProtectionStatus::new(StorageProtectionState::NotProvided, None),
        )),
    }
}

async fn open_plaintext_pool(database_url: &str) -> anyhow::Result<SqlitePool> {
    use sqlx::sqlite::{SqliteConnectOptions, SqlitePoolOptions};
    use std::str::FromStr;
    use std::time::Duration;

    let options = SqliteConnectOptions::from_str(database_url)?
        .foreign_keys(true)
        .busy_timeout(Duration::from_secs(5));
    Ok(SqlitePoolOptions::new().connect_with(options).await?)
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::path::Path;
    use std::sync::atomic::{AtomicBool, Ordering};

    struct FakeProvider {
        observed_before_create: Arc<AtomicBool>,
        expected_key: Vec<u8>,
        fail: bool,
    }

    #[async_trait]
    impl StorageProtectionProvider for FakeProvider {
        fn provider_id(&self) -> &'static str {
            "test.fake"
        }

        async fn open(
            &self,
            request: StorageProtectionOpenRequest<'_>,
        ) -> anyhow::Result<ProtectedStoragePool> {
            let path = sqlite_path(request.database_url());
            self.observed_before_create
                .store(!path.exists(), Ordering::Release);
            anyhow::ensure!(request.key().expose_bytes() == self.expected_key);
            anyhow::ensure!(request.plaintext_policy() == PlaintextStoragePolicy::Reject);
            if self.fail {
                anyhow::bail!("injected provider failure");
            }
            Ok(ProtectedStoragePool::verified(
                open_plaintext_pool(request.database_url()).await?,
            ))
        }
    }

    fn sqlite_path(url: &str) -> &Path {
        Path::new(
            url.strip_prefix("sqlite://")
                .unwrap()
                .split('?')
                .next()
                .unwrap(),
        )
    }

    fn key(bytes: &[u8]) -> Arc<SecretMaterial> {
        Arc::new(SecretMaterial::new(bytes.to_vec()).unwrap())
    }

    #[tokio::test]
    async fn reports_missing_and_configured_keys_without_claiming_active_protection() {
        let root = tempfile::tempdir().unwrap();
        let missing_path = root.path().join("missing.db");
        let missing_url = format!("sqlite://{}?mode=rwc", missing_path.display());
        let (missing_pool, missing) =
            open_storage_pool(&missing_url, StorageOpenOptions::default())
                .await
                .unwrap();
        assert_eq!(missing.state(), StorageProtectionState::NotProvided);
        missing_pool.close().await;

        let configured_path = root.path().join("configured.db");
        let configured_url = format!("sqlite://{}?mode=rwc", configured_path.display());
        let (pool, configured) = open_storage_pool(
            &configured_url,
            StorageOpenOptions::default().with_key(key(&[7; 32])),
        )
        .await
        .unwrap();
        assert_eq!(configured.state(), StorageProtectionState::Configured);
        sqlx::query("CREATE TABLE configured_probe (id INTEGER PRIMARY KEY)")
            .execute(&pool)
            .await
            .unwrap();
        pool.close().await;
        assert_eq!(
            &std::fs::read(configured_path).unwrap()[..16],
            b"SQLite format 3\0"
        );
    }

    #[tokio::test]
    async fn provider_receives_borrowed_key_before_create_and_must_verify_active() {
        let root = tempfile::tempdir().unwrap();
        let path = root.path().join("active.db");
        let url = format!("sqlite://{}?mode=rwc", path.display());
        let observed = Arc::new(AtomicBool::new(false));
        let provider = Arc::new(FakeProvider {
            observed_before_create: observed.clone(),
            expected_key: vec![9; 32],
            fail: false,
        });
        let (pool, status) = open_storage_pool(
            &url,
            StorageOpenOptions::default()
                .with_key(key(&[9; 32]))
                .with_provider(provider),
        )
        .await
        .unwrap();
        assert!(observed.load(Ordering::Acquire));
        assert_eq!(status.state(), StorageProtectionState::Active);
        assert_eq!(status.provider_id(), Some("test.fake"));
        pool.close().await;
    }

    #[tokio::test]
    async fn provider_failure_is_downcastable_and_does_not_create_database() {
        let root = tempfile::tempdir().unwrap();
        let path = root.path().join("failed.db");
        let url = format!("sqlite://{}?mode=rwc", path.display());
        let provider = Arc::new(FakeProvider {
            observed_before_create: Arc::new(AtomicBool::new(false)),
            expected_key: vec![3; 32],
            fail: true,
        });
        let error = open_storage_pool(
            &url,
            StorageOpenOptions::default()
                .with_key(key(&[3; 32]))
                .with_provider(provider),
        )
        .await
        .unwrap_err();
        let error = error.downcast_ref::<StorageProtectionOpenError>().unwrap();
        assert_eq!(error.status().state(), StorageProtectionState::Error);
        assert_eq!(error.status().provider_id(), Some("test.fake"));
        assert!(!path.exists());
    }

    #[tokio::test]
    async fn configured_provider_without_key_fails_closed_before_create() {
        let root = tempfile::tempdir().unwrap();
        let path = root.path().join("missing-key.db");
        let url = format!("sqlite://{}?mode=rwc", path.display());
        let provider = Arc::new(FakeProvider {
            observed_before_create: Arc::new(AtomicBool::new(false)),
            expected_key: vec![3; 32],
            fail: false,
        });
        let error = open_storage_pool(&url, StorageOpenOptions::default().with_provider(provider))
            .await
            .unwrap_err();
        let error = error.downcast_ref::<StorageProtectionOpenError>().unwrap();
        assert_eq!(error.status().state(), StorageProtectionState::Error);
        assert_eq!(error.status().provider_id(), Some("test.fake"));
        assert!(!path.exists());
    }

    #[test]
    fn debug_output_redacts_storage_key() {
        let secret = b"never-print-this-key";
        let options = StorageOpenOptions::default().with_key(key(secret));
        let output = format!("{options:?}");
        assert!(output.contains("[REDACTED]"));
        assert!(!output.contains(std::str::from_utf8(secret).unwrap()));
    }
}
