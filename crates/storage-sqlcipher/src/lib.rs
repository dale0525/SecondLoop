use agent_runtime::storage_protection::{
    PlaintextStoragePolicy, ProtectedStoragePool, StorageProtectionOpenRequest,
    StorageProtectionProvider,
};
use anyhow::Context;
use async_trait::async_trait;
use fs2::FileExt;
use libsqlite3_sys::{SQLITE_OK, sqlite3_key_v2};
use sqlx::sqlite::{SqliteConnectOptions, SqlitePoolOptions};
use sqlx::{ConnectOptions, Connection, Row, SqliteConnection, SqlitePool};
use std::ffi::CString;
use std::fs::{File, OpenOptions};
use std::path::{Path, PathBuf};
use std::str::FromStr;
use std::sync::Arc;
use std::time::Duration;
use zeroize::{Zeroize, Zeroizing};

const SQLITE_HEADER: &[u8; 16] = b"SQLite format 3\0";
const REQUIRED_KEY_BYTES: usize = 32;

#[derive(Clone, Debug)]
/// SQLCipher-backed implementation of AgentWeave's active-storage protection contract.
pub struct SqlCipherStorageProvider {
    max_connections: u32,
}

impl Default for SqlCipherStorageProvider {
    fn default() -> Self {
        Self { max_connections: 5 }
    }
}

impl SqlCipherStorageProvider {
    /// Creates a provider with a five-connection SQLite pool.
    pub fn new() -> Self {
        Self::default()
    }

    /// Sets the maximum number of protected SQLite connections.
    pub fn with_max_connections(mut self, max_connections: u32) -> anyhow::Result<Self> {
        anyhow::ensure!(max_connections > 0, "SQLCipher pool size must be positive");
        self.max_connections = max_connections;
        Ok(self)
    }
}

#[async_trait]
impl StorageProtectionProvider for SqlCipherStorageProvider {
    fn provider_id(&self) -> &'static str {
        "agentweave.sqlcipher.v1"
    }

    async fn open(
        &self,
        request: StorageProtectionOpenRequest<'_>,
    ) -> anyhow::Result<ProtectedStoragePool> {
        anyhow::ensure!(
            request.key().expose_bytes().len() == REQUIRED_KEY_BYTES,
            "SQLCipher storage key must be exactly 32 bytes"
        );
        let path = database_path(request.database_url())?;
        let lock = DatabaseLock::acquire(&path)?;
        recover_interrupted_migration(&path)
            .await
            .context("interrupted SQLCipher migration recovery failed")?;
        let key = Arc::new(RetainedKey::new(request.key().expose_bytes()));
        let database_kind = inspect_database(&path)?;
        match database_kind {
            DatabaseKind::Plaintext => match request.plaintext_policy() {
                PlaintextStoragePolicy::Reject => {
                    anyhow::bail!("plaintext SQLite storage is rejected by SQLCipher policy")
                }
                PlaintextStoragePolicy::MigrateWithVerifiedRollback => {
                    migrate_plaintext_database(request.database_url(), &path, key.clone()).await?;
                }
            },
            DatabaseKind::MissingOrEmpty | DatabaseKind::ProtectedOrInvalid => {}
        }
        let pool = open_protected_pool(
            request.database_url(),
            key,
            self.max_connections,
            matches!(database_kind, DatabaseKind::MissingOrEmpty),
        )
        .await
        .context("SQLCipher pool initialization failed")?;
        verify_protected_pool(&pool, &path)
            .await
            .context("SQLCipher pool verification failed")?;
        make_private(&path)?;
        lock.release()?;
        Ok(ProtectedStoragePool::verified(pool))
    }
}

struct RetainedKey(Vec<u8>);

impl RetainedKey {
    fn new(bytes: &[u8]) -> Self {
        Self(bytes.to_vec())
    }

    fn expose_bytes(&self) -> &[u8] {
        &self.0
    }
}

impl Drop for RetainedKey {
    fn drop(&mut self) {
        self.0.zeroize();
    }
}

struct DatabaseLock {
    file: File,
}

impl DatabaseLock {
    fn acquire(database: &Path) -> anyhow::Result<Self> {
        let lock_path = migration_path(database, "lock");
        let mut options = OpenOptions::new();
        options.read(true).write(true).create(true);
        #[cfg(unix)]
        {
            use std::os::unix::fs::OpenOptionsExt;
            options.mode(0o600);
        }
        let file = options.open(lock_path)?;
        file.try_lock_exclusive()
            .map_err(|_| anyhow::anyhow!("SQLCipher database migration lock is unavailable"))?;
        Ok(Self { file })
    }

    fn release(self) -> anyhow::Result<()> {
        FileExt::unlock(&self.file)?;
        Ok(())
    }
}

#[derive(Clone, Copy)]
enum DatabaseKind {
    MissingOrEmpty,
    Plaintext,
    ProtectedOrInvalid,
}

fn database_path(database_url: &str) -> anyhow::Result<PathBuf> {
    anyhow::ensure!(
        !is_memory_database_url(database_url),
        "SQLCipher provider requires file-backed SQLite storage"
    );
    let options = SqliteConnectOptions::from_str(database_url)?;
    let path = options.get_filename();
    anyhow::ensure!(
        path != Path::new(":memory:")
            && !path.as_os_str().is_empty()
            && !path.to_string_lossy().starts_with("file:sqlx-in-memory-"),
        "SQLCipher provider requires file-backed SQLite storage"
    );
    let path = if path.is_absolute() {
        path.to_path_buf()
    } else {
        std::env::current_dir()?.join(path)
    };
    if let Ok(metadata) = std::fs::symlink_metadata(&path) {
        anyhow::ensure!(
            !metadata.file_type().is_symlink(),
            "database path is a symlink"
        );
        anyhow::ensure!(metadata.is_file(), "database path is not a regular file");
    }
    let parent = path
        .parent()
        .ok_or_else(|| anyhow::anyhow!("database path has no parent"))?;
    anyhow::ensure!(parent.is_dir(), "database parent directory is unavailable");
    Ok(path)
}

fn is_memory_database_url(database_url: &str) -> bool {
    let (location, query) = database_url
        .split_once('?')
        .map_or((database_url, ""), |(location, query)| (location, query));
    matches!(location, "sqlite::memory:" | "sqlite://:memory:")
        || query.split('&').any(|parameter| parameter == "mode=memory")
}

fn inspect_database(path: &Path) -> anyhow::Result<DatabaseKind> {
    let mut file = match File::open(path) {
        Ok(file) => file,
        Err(error) if error.kind() == std::io::ErrorKind::NotFound => {
            return Ok(DatabaseKind::MissingOrEmpty);
        }
        Err(error) => return Err(error.into()),
    };
    if file.metadata()?.len() == 0 {
        return Ok(DatabaseKind::MissingOrEmpty);
    }
    let mut header = [0_u8; SQLITE_HEADER.len()];
    use std::io::Read;
    let bytes_read = file.read(&mut header)?;
    if bytes_read < SQLITE_HEADER.len() {
        return Ok(DatabaseKind::ProtectedOrInvalid);
    }
    if &header == SQLITE_HEADER {
        Ok(DatabaseKind::Plaintext)
    } else {
        Ok(DatabaseKind::ProtectedOrInvalid)
    }
}

async fn open_protected_pool(
    database_url: &str,
    key: Arc<RetainedKey>,
    max_connections: u32,
    initialize_empty: bool,
) -> anyhow::Result<SqlitePool> {
    let options = SqliteConnectOptions::from_str(database_url)?
        .pragma("key", sqlcipher_key_pragma(&key))
        .foreign_keys(true)
        .busy_timeout(Duration::from_secs(5))
        .disable_statement_logging();
    let mut probe = SqliteConnection::connect_with(&options).await?;
    if initialize_empty {
        sqlx::query("PRAGMA user_version = 0")
            .execute(&mut probe)
            .await?;
    }
    sqlx::query("SELECT COUNT(*) FROM sqlite_schema")
        .execute(&mut probe)
        .await?;
    probe.close().await?;
    let pool = SqlitePoolOptions::new()
        .max_connections(max_connections)
        .after_connect(|connection, _| {
            Box::pin(async move {
                sqlx::query("SELECT COUNT(*) FROM sqlite_schema")
                    .execute(connection)
                    .await?;
                Ok(())
            })
        })
        .connect_with(options)
        .await?;
    Ok(pool)
}

fn sqlcipher_key_pragma(key: &RetainedKey) -> String {
    format!("\"{}\"", sqlcipher_raw_key(key))
}

fn sqlcipher_raw_key(key: &RetainedKey) -> String {
    format!("x'{}'", hex::encode(key.expose_bytes()))
}

async fn apply_attached_key(
    connection: &mut SqliteConnection,
    database: &str,
    key: &RetainedKey,
) -> Result<(), sqlx::Error> {
    let mut handle = connection.lock_handle().await?;
    let database = CString::new(database)
        .map_err(|_| sqlx::Error::Protocol("invalid SQLite database name".into()))?;
    let encoded_key = Zeroizing::new(sqlcipher_raw_key(key));
    // SAFETY: the SQLx handle is exclusively locked, the key bytes remain
    // alive for the call, and the database name is NUL-terminated.
    let status = unsafe {
        sqlite3_key_v2(
            handle.as_raw_handle().as_ptr(),
            database.as_ptr(),
            encoded_key.as_bytes().as_ptr().cast(),
            encoded_key.len() as i32,
        )
    };
    if status != SQLITE_OK {
        return Err(sqlx::Error::Protocol(format!(
            "SQLCipher key initialization failed with status {status}"
        )));
    }
    Ok(())
}

async fn verify_protected_pool(pool: &SqlitePool, path: &Path) -> anyhow::Result<()> {
    let version: String = sqlx::query_scalar("PRAGMA cipher_version")
        .fetch_one(pool)
        .await?;
    anyhow::ensure!(
        !version.trim().is_empty(),
        "SQLCipher backend is unavailable"
    );
    let quick_check: String = sqlx::query_scalar("PRAGMA quick_check")
        .fetch_one(pool)
        .await?;
    anyhow::ensure!(
        quick_check == "ok",
        "SQLCipher database integrity check failed"
    );
    let cipher_rows = sqlx::query("PRAGMA cipher_integrity_check")
        .fetch_all(pool)
        .await?;
    for row in cipher_rows {
        let result: String = row.try_get(0)?;
        anyhow::ensure!(result == "ok", "SQLCipher page integrity check failed");
    }
    use tokio::io::AsyncReadExt;
    let mut file = tokio::fs::File::open(path).await?;
    let mut header = [0_u8; SQLITE_HEADER.len()];
    file.read_exact(&mut header).await?;
    anyhow::ensure!(
        &header != SQLITE_HEADER,
        "SQLCipher verification found a plaintext database header"
    );
    Ok(())
}

async fn migrate_plaintext_database(
    database_url: &str,
    database_path: &Path,
    key: Arc<RetainedKey>,
) -> anyhow::Result<()> {
    let rollback_path = migration_path(database_path, "plaintext-rollback");
    let candidate_path = migration_path(database_path, "protected-candidate");
    let original_path = migration_path(database_path, "plaintext-original");
    let result = migrate_plaintext_database_inner(
        database_url,
        database_path,
        &rollback_path,
        &candidate_path,
        &original_path,
        key,
    )
    .await;
    match result {
        Ok(()) => {
            remove_database_family_checked(&rollback_path)
                .await
                .context("verified plaintext rollback cleanup failed")?;
            remove_database_family_checked(&original_path)
                .await
                .context("original plaintext database cleanup failed")?;
            remove_database_family_checked(&candidate_path).await?;
            Ok(())
        }
        Err(error) => {
            if let Err(recovery_error) = recover_interrupted_migration(database_path).await {
                return Err(error.context(format!(
                    "plaintext rollback was retained after recovery failed: {recovery_error}"
                )));
            }
            let _ = remove_database_family_checked(&candidate_path).await;
            Err(error)
        }
    }
}

async fn migrate_plaintext_database_inner(
    database_url: &str,
    database_path: &Path,
    rollback_path: &Path,
    candidate_path: &Path,
    original_path: &Path,
    key: Arc<RetainedKey>,
) -> anyhow::Result<()> {
    let options = SqliteConnectOptions::from_str(database_url)?
        .foreign_keys(true)
        .busy_timeout(Duration::from_secs(5))
        .disable_statement_logging();
    let mut source = SqliteConnection::connect_with(&options).await?;
    sqlx::query("PRAGMA locking_mode = EXCLUSIVE")
        .execute(&mut source)
        .await?;
    sqlx::query("BEGIN EXCLUSIVE").execute(&mut source).await?;
    sqlx::query("COMMIT").execute(&mut source).await?;
    verify_plaintext_connection(&mut source).await?;
    sqlx::query("VACUUM INTO ?")
        .bind(rollback_path.to_string_lossy().as_ref())
        .execute(&mut source)
        .await?;
    make_private(rollback_path)?;
    verify_plaintext_file(rollback_path).await?;

    sqlx::query("ATTACH DATABASE ? AS protected")
        .bind(candidate_path.to_string_lossy().as_ref())
        .execute(&mut source)
        .await?;
    apply_attached_key(&mut source, "protected", &key).await?;
    let export_result = sqlx::query("SELECT sqlcipher_export('protected')")
        .execute(&mut source)
        .await;
    let detach_result = sqlx::query("DETACH DATABASE protected")
        .execute(&mut source)
        .await;
    export_result?;
    detach_result?;
    make_private(candidate_path)?;
    let candidate_url = file_url(candidate_path);
    let candidate_pool = open_protected_pool(&candidate_url, key.clone(), 1, false)
        .await
        .context("migrated SQLCipher candidate could not be opened")?;
    let candidate_verification = verify_protected_pool(&candidate_pool, candidate_path).await;
    candidate_pool.close().await;
    candidate_verification?;
    source.close().await?;

    move_database_family(database_path, original_path).await?;
    if let Err(error) = tokio::fs::rename(candidate_path, database_path).await {
        move_database_family(original_path, database_path).await?;
        return Err(error.into());
    }
    sync_parent(database_path)?;
    let final_pool = open_protected_pool(database_url, key, 1, false)
        .await
        .context("installed SQLCipher database could not be opened")?;
    let final_verification = verify_protected_pool(&final_pool, database_path).await;
    final_pool.close().await;
    final_verification?;
    Ok(())
}

async fn verify_plaintext_connection(connection: &mut SqliteConnection) -> anyhow::Result<()> {
    let result: String = sqlx::query_scalar("PRAGMA quick_check")
        .fetch_one(connection)
        .await?;
    anyhow::ensure!(result == "ok", "plaintext database integrity check failed");
    Ok(())
}

async fn verify_plaintext_file(path: &Path) -> anyhow::Result<()> {
    let options = SqliteConnectOptions::new()
        .filename(path)
        .read_only(true)
        .immutable(true)
        .disable_statement_logging();
    let mut connection = SqliteConnection::connect_with(&options).await?;
    let result = verify_plaintext_connection(&mut connection).await;
    connection.close().await?;
    result
}

async fn recover_interrupted_migration(database: &Path) -> anyhow::Result<()> {
    let rollback = migration_path(database, "plaintext-rollback");
    let candidate = migration_path(database, "protected-candidate");
    let original = migration_path(database, "plaintext-original");
    if original.exists() {
        remove_database_family_checked(database).await?;
        move_database_family(&original, database).await?;
        remove_database_family_checked(&rollback).await?;
        remove_database_family_checked(&candidate).await?;
        sync_parent(database)?;
    } else if rollback.exists() {
        remove_database_family_checked(database).await?;
        tokio::fs::rename(&rollback, database).await?;
        remove_database_family_checked(&candidate).await?;
        sync_parent(database)?;
    } else {
        remove_database_family_checked(&candidate).await?;
    }
    Ok(())
}

async fn move_database_family(source: &Path, destination: &Path) -> anyhow::Result<()> {
    tokio::fs::rename(source, destination).await?;
    for suffix in ["-wal", "-shm"] {
        let source_sidecar = sidecar_path(source, suffix);
        if source_sidecar.exists() {
            tokio::fs::rename(source_sidecar, sidecar_path(destination, suffix)).await?;
        }
    }
    Ok(())
}

async fn remove_database_family_checked(path: &Path) -> anyhow::Result<()> {
    for candidate in [
        path.to_path_buf(),
        sidecar_path(path, "-wal"),
        sidecar_path(path, "-shm"),
    ] {
        match tokio::fs::remove_file(candidate).await {
            Ok(()) => {}
            Err(error) if error.kind() == std::io::ErrorKind::NotFound => {}
            Err(error) => return Err(error.into()),
        }
    }
    Ok(())
}

fn make_private(path: &Path) -> anyhow::Result<()> {
    #[cfg(unix)]
    {
        use std::os::unix::fs::PermissionsExt;
        std::fs::set_permissions(path, std::fs::Permissions::from_mode(0o600))?;
    }
    Ok(())
}

fn file_url(path: &Path) -> String {
    format!("sqlite://{}?mode=rw", path.display())
}

fn migration_path(database: &Path, label: &str) -> PathBuf {
    let mut name = database.file_name().unwrap_or_default().to_os_string();
    name.push(format!(".agentweave-sqlcipher-{label}"));
    database.with_file_name(name)
}

fn sidecar_path(path: &Path, suffix: &str) -> PathBuf {
    let mut value = path.as_os_str().to_os_string();
    value.push(suffix);
    PathBuf::from(value)
}

fn sync_parent(path: &Path) -> anyhow::Result<()> {
    if let Some(parent) = path.parent() {
        #[cfg(unix)]
        File::open(parent)?.sync_all()?;
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    use agent_runtime::credential::SecretMaterial;
    use agent_runtime::storage::Storage;
    use agent_runtime::storage_protection::{
        PlaintextStoragePolicy, StorageOpenOptions, StorageProtectionState,
    };

    fn key(value: u8) -> Arc<SecretMaterial> {
        Arc::new(SecretMaterial::new(vec![value; REQUIRED_KEY_BYTES]).unwrap())
    }

    fn options(value: u8) -> StorageOpenOptions {
        StorageOpenOptions::default()
            .with_key(key(value))
            .with_provider(Arc::new(SqlCipherStorageProvider::new()))
    }

    #[tokio::test]
    async fn creates_reopens_and_verifies_an_encrypted_database() {
        let root = tempfile::tempdir().unwrap();
        let path = root.path().join("protected.db");
        let url = format!("sqlite://{}?mode=rwc", path.display());
        let storage = Storage::connect_with_options(&url, options(7))
            .await
            .unwrap();
        assert_eq!(
            storage.protection_status().state(),
            StorageProtectionState::Active
        );
        storage.create_session("retained").await.unwrap();
        storage.close().await;

        assert_ne!(
            &std::fs::read(&path).unwrap()[..SQLITE_HEADER.len()],
            SQLITE_HEADER
        );
        assert!(Storage::connect(&url).await.is_err());
        assert!(
            Storage::connect_with_options(&url, options(8))
                .await
                .is_err()
        );
        let reopened = Storage::connect_with_options(&url, options(7))
            .await
            .unwrap();
        let sessions = reopened.list_sessions().await.unwrap();
        assert_eq!(sessions.len(), 1);
        assert_eq!(sessions[0].title, "retained");
    }

    #[tokio::test]
    async fn rejects_plaintext_without_mutating_it() {
        let root = tempfile::tempdir().unwrap();
        let path = root.path().join("plaintext.db");
        let url = format!("sqlite://{}?mode=rwc", path.display());
        let storage = Storage::connect(&url).await.unwrap();
        storage.close().await;
        let before = std::fs::read(&path).unwrap();

        let error = Storage::connect_with_options(&url, options(4))
            .await
            .err()
            .expect("plaintext database must be rejected");
        assert!(error.to_string().contains("provider failed"));
        assert_eq!(std::fs::read(&path).unwrap(), before);
    }

    #[tokio::test]
    async fn explicitly_migrates_plaintext_with_verified_rollback() {
        let root = tempfile::tempdir().unwrap();
        let path = root.path().join("migrate.db");
        let url = format!("sqlite://{}?mode=rwc", path.display());
        let plaintext = Storage::connect(&url).await.unwrap();
        plaintext.create_session("preserved").await.unwrap();
        plaintext.close().await;

        let migrated = Storage::connect_with_options(
            &url,
            options(5).with_plaintext_policy(PlaintextStoragePolicy::MigrateWithVerifiedRollback),
        )
        .await
        .unwrap();
        let sessions = migrated.list_sessions().await.unwrap();
        assert_eq!(sessions.len(), 1);
        assert_eq!(sessions[0].title, "preserved");
        migrated.close().await;
        assert_ne!(
            &std::fs::read(&path).unwrap()[..SQLITE_HEADER.len()],
            SQLITE_HEADER
        );
        let residue = std::fs::read_dir(root.path())
            .unwrap()
            .filter_map(Result::ok)
            .map(|entry| entry.file_name().to_string_lossy().into_owned())
            .filter(|name| name.contains("plaintext-") || name.contains("protected-candidate"))
            .collect::<Vec<_>>();
        assert!(
            residue.is_empty(),
            "unexpected migration residue: {residue:?}"
        );
    }

    #[tokio::test]
    async fn interrupted_replacement_rolls_back_before_retrying_migration() {
        let root = tempfile::tempdir().unwrap();
        let path = root.path().join("interrupted.db");
        let url = format!("sqlite://{}?mode=rwc", path.display());
        let plaintext = Storage::connect(&url).await.unwrap();
        plaintext.create_session("recover-me").await.unwrap();
        plaintext.close().await;

        let original = migration_path(&path, "plaintext-original");
        let rollback = migration_path(&path, "plaintext-rollback");
        let candidate = migration_path(&path, "protected-candidate");
        std::fs::copy(&path, &rollback).unwrap();
        std::fs::rename(&path, &original).unwrap();
        std::fs::write(&path, b"incomplete protected replacement").unwrap();
        std::fs::write(&candidate, b"incomplete candidate").unwrap();

        let migrated = Storage::connect_with_options(
            &url,
            options(6).with_plaintext_policy(PlaintextStoragePolicy::MigrateWithVerifiedRollback),
        )
        .await
        .unwrap();
        let sessions = migrated.list_sessions().await.unwrap();
        assert_eq!(sessions.len(), 1);
        assert_eq!(sessions[0].title, "recover-me");
        migrated.close().await;
        assert!(!original.exists());
        assert!(!rollback.exists());
        assert!(!candidate.exists());
    }

    #[tokio::test]
    async fn migration_lock_fails_closed_without_creating_a_database() {
        let root = tempfile::tempdir().unwrap();
        let path = root.path().join("locked.db");
        let url = format!("sqlite://{}?mode=rwc", path.display());
        let lock = DatabaseLock::acquire(&path).unwrap();

        assert!(
            Storage::connect_with_options(&url, options(2))
                .await
                .is_err()
        );
        assert!(!path.exists());
        lock.release().unwrap();
    }

    #[tokio::test]
    async fn rejects_non_file_storage_and_invalid_key_lengths() {
        let root = tempfile::tempdir().unwrap();
        let memory_error = Storage::connect_with_options("sqlite::memory:", options(3))
            .await
            .err()
            .expect("memory storage must be rejected");
        assert!(memory_error.to_string().contains("provider failed"));

        let path = root.path().join("invalid-key.db");
        let url = format!("sqlite://{}?mode=rwc", path.display());
        let invalid = StorageOpenOptions::default()
            .with_key(Arc::new(SecretMaterial::new(vec![1; 31]).unwrap()))
            .with_provider(Arc::new(SqlCipherStorageProvider::new()));
        assert!(Storage::connect_with_options(&url, invalid).await.is_err());
        assert!(!path.exists());
    }
}
