use agent_runtime::credential::SecretMaterial;
use agent_runtime::data_protection::{
    BackupMetadata, DataProtectionError, EncryptedBackup, EncryptedBackupCodec,
};
use agent_runtime::storage::Storage;
use serde::Serialize;
use sqlx::sqlite::{SqliteConnectOptions, SqlitePoolOptions};
use std::ffi::OsString;
use std::path::{Path, PathBuf};
use std::sync::Arc;
use tokio::io::AsyncWriteExt;
use uuid::Uuid;

const MAX_DATABASE_BYTES: usize = 256 * 1024 * 1024;
pub const MAX_BACKUP_BYTES: usize = MAX_DATABASE_BYTES + 1024;

#[derive(Clone)]
pub(crate) struct DataProtectionService {
    inner: Arc<DataProtectionInner>,
}

struct DataProtectionInner {
    app_id: String,
    codec: EncryptedBackupCodec,
    database_path: PathBuf,
    storage: Storage,
}

#[derive(Clone, Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub(crate) struct DataProtectionStatus {
    pub enabled: bool,
    pub at_rest_encryption: &'static str,
    pub backup_encryption: &'static str,
    pub backup_format: &'static str,
    pub pending_restart: bool,
    pub restore_rollback_available: bool,
}

#[derive(Clone, Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub(crate) struct RestoreReceipt {
    pub accepted: bool,
    pub restart_required: bool,
    pub backup: BackupMetadata,
}

impl DataProtectionService {
    pub(crate) fn new(
        storage: Storage,
        database_path: impl Into<PathBuf>,
        app_id: impl Into<String>,
        key: SecretMaterial,
    ) -> Result<Self, DataProtectionError> {
        Ok(Self {
            inner: Arc::new(DataProtectionInner {
                app_id: app_id.into(),
                codec: EncryptedBackupCodec::new(key)?,
                database_path: database_path.into(),
                storage,
            }),
        })
    }

    pub(crate) fn status(&self) -> DataProtectionStatus {
        DataProtectionStatus {
            enabled: true,
            at_rest_encryption: "not_provided",
            backup_encryption: "aes-256-gcm",
            backup_format: "agentweave-backup-v1",
            pending_restart: pending_path(&self.inner.database_path).exists(),
            restore_rollback_available: rollback_path(&self.inner.database_path).exists(),
        }
    }

    pub(crate) async fn create_backup(&self) -> anyhow::Result<EncryptedBackup> {
        let snapshot = temporary_path(&self.inner.database_path, "backup-snapshot");
        let result = async {
            self.inner
                .storage
                .create_consistent_snapshot(&snapshot)
                .await?;
            let metadata = tokio::fs::metadata(&snapshot).await?;
            anyhow::ensure!(
                metadata.is_file() && metadata.len() <= MAX_DATABASE_BYTES as u64,
                "database snapshot exceeds backup size limit"
            );
            let bytes = tokio::fs::read(&snapshot).await?;
            self.inner
                .codec
                .encrypt(&self.inner.app_id, &bytes)
                .map_err(anyhow::Error::from)
        }
        .await;
        let _ = tokio::fs::remove_file(&snapshot).await;
        result
    }

    pub(crate) async fn stage_restore(&self, envelope: &[u8]) -> anyhow::Result<RestoreReceipt> {
        self.stage_restore_with_codec(&self.inner.codec, envelope)
            .await
    }

    pub(crate) async fn stage_restore_with_key(
        &self,
        envelope: &[u8],
        key: SecretMaterial,
    ) -> anyhow::Result<RestoreReceipt> {
        let codec = EncryptedBackupCodec::new(key)?;
        self.stage_restore_with_codec(&codec, envelope).await
    }

    async fn stage_restore_with_codec(
        &self,
        codec: &EncryptedBackupCodec,
        envelope: &[u8],
    ) -> anyhow::Result<RestoreReceipt> {
        anyhow::ensure!(
            envelope.len() <= MAX_BACKUP_BYTES,
            "encrypted backup exceeds size limit"
        );
        let decrypted = codec
            .decrypt(&self.inner.app_id, envelope)
            .map_err(anyhow::Error::from)?;
        anyhow::ensure!(
            decrypted.bytes.len() <= MAX_DATABASE_BYTES,
            "decrypted backup exceeds size limit"
        );
        let pending = pending_path(&self.inner.database_path);
        anyhow::ensure!(!pending.exists(), "a database restore is already pending");
        let candidate = temporary_path(&self.inner.database_path, "restore-candidate");
        write_private_file(&candidate, &decrypted.bytes).await?;
        if let Err(error) = validate_sqlite_snapshot(&candidate).await {
            let _ = tokio::fs::remove_file(&candidate).await;
            return Err(error);
        }
        if let Err(error) = tokio::fs::rename(&candidate, &pending).await {
            let _ = tokio::fs::remove_file(&candidate).await;
            return Err(error.into());
        }
        sync_parent(&pending)?;
        Ok(RestoreReceipt {
            accepted: true,
            restart_required: true,
            backup: decrypted.metadata,
        })
    }
}

pub(crate) fn disabled_status() -> DataProtectionStatus {
    DataProtectionStatus {
        enabled: false,
        at_rest_encryption: "not_provided",
        backup_encryption: "unavailable",
        backup_format: "agentweave-backup-v1",
        pending_restart: false,
        restore_rollback_available: false,
    }
}

pub async fn apply_pending_restore(database_path: &Path) -> anyhow::Result<bool> {
    let pending = pending_path(database_path);
    if !pending.exists() {
        return Ok(false);
    }
    validate_sqlite_snapshot(&pending).await?;
    let rollback = rollback_path(database_path);
    remove_database_family(&rollback).await?;

    let current_exists = database_path.exists();
    if current_exists {
        tokio::fs::rename(database_path, &rollback).await?;
        move_if_present(
            &sidecar_path(database_path, "-wal"),
            &sidecar_path(&rollback, "-wal"),
        )
        .await?;
        move_if_present(
            &sidecar_path(database_path, "-shm"),
            &sidecar_path(&rollback, "-shm"),
        )
        .await?;
    }
    if let Err(error) = tokio::fs::rename(&pending, database_path).await {
        if current_exists {
            let _ = tokio::fs::rename(&rollback, database_path).await;
            let _ = move_if_present(
                &sidecar_path(&rollback, "-wal"),
                &sidecar_path(database_path, "-wal"),
            )
            .await;
            let _ = move_if_present(
                &sidecar_path(&rollback, "-shm"),
                &sidecar_path(database_path, "-shm"),
            )
            .await;
        }
        return Err(error.into());
    }
    sync_parent(database_path)?;
    Ok(true)
}

async fn validate_sqlite_snapshot(path: &Path) -> anyhow::Result<()> {
    let options = SqliteConnectOptions::new()
        .filename(path)
        .read_only(true)
        .immutable(true);
    let pool = SqlitePoolOptions::new()
        .max_connections(1)
        .connect_with(options)
        .await?;
    let result = async {
        let integrity: String = sqlx::query_scalar("PRAGMA quick_check")
            .fetch_one(&pool)
            .await?;
        anyhow::ensure!(integrity == "ok", "backup database integrity check failed");
        let migrations: i64 = sqlx::query_scalar(
            "SELECT COUNT(*) FROM sqlite_master WHERE type = 'table' AND name = 'runtime_schema_migrations'",
        )
        .fetch_one(&pool)
        .await?;
        anyhow::ensure!(migrations == 1, "backup database schema is incompatible");
        Ok(())
    }
    .await;
    pool.close().await;
    result
}

async fn write_private_file(path: &Path, bytes: &[u8]) -> anyhow::Result<()> {
    let mut options = tokio::fs::OpenOptions::new();
    options.write(true).create_new(true);
    #[cfg(unix)]
    {
        options.mode(0o600);
    }
    let mut file = options.open(path).await?;
    file.write_all(bytes).await?;
    file.sync_all().await?;
    Ok(())
}

async fn remove_database_family(path: &Path) -> anyhow::Result<()> {
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

async fn move_if_present(source: &Path, destination: &Path) -> anyhow::Result<()> {
    match tokio::fs::rename(source, destination).await {
        Ok(()) => Ok(()),
        Err(error) if error.kind() == std::io::ErrorKind::NotFound => Ok(()),
        Err(error) => Err(error.into()),
    }
}

fn temporary_path(database_path: &Path, label: &str) -> PathBuf {
    database_path.with_file_name(format!(".{label}-{}.sqlite", Uuid::new_v4()))
}

fn pending_path(database_path: &Path) -> PathBuf {
    appended_path(database_path, ".restore-pending")
}

fn rollback_path(database_path: &Path) -> PathBuf {
    appended_path(database_path, ".restore-rollback")
}

fn sidecar_path(database_path: &Path, suffix: &str) -> PathBuf {
    appended_path(database_path, suffix)
}

fn appended_path(path: &Path, suffix: &str) -> PathBuf {
    let mut value: OsString = path.as_os_str().to_owned();
    value.push(suffix);
    PathBuf::from(value)
}

fn sync_parent(path: &Path) -> anyhow::Result<()> {
    if let Some(parent) = path.parent() {
        std::fs::File::open(parent)?.sync_all()?;
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[tokio::test]
    async fn encrypted_backup_stages_validates_and_restores_on_restart() {
        let root = tempfile::tempdir().unwrap();
        let database = root.path().join("agentweave.db");
        let url = format!("sqlite://{}?mode=rwc", database.display());
        let storage = Storage::connect(&url).await.unwrap();
        let original = storage.create_session("Original").await.unwrap();
        let service = DataProtectionService::new(
            storage.clone(),
            &database,
            "agentweave.default",
            SecretMaterial::new(vec![7; 32]).unwrap(),
        )
        .unwrap();
        let backup = service.create_backup().await.unwrap();
        storage.create_session("Later").await.unwrap();
        let restore_service = DataProtectionService::new(
            storage.clone(),
            &database,
            "agentweave.default",
            SecretMaterial::new(vec![8; 32]).unwrap(),
        )
        .unwrap();
        let receipt = restore_service
            .stage_restore_with_key(&backup.bytes, SecretMaterial::new(vec![7; 32]).unwrap())
            .await
            .unwrap();
        assert!(receipt.restart_required);
        storage.close().await;

        assert!(apply_pending_restore(&database).await.unwrap());
        let restored = Storage::connect(&url).await.unwrap();
        let sessions = restored.list_sessions().await.unwrap();
        assert_eq!(sessions.len(), 1);
        assert_eq!(sessions[0].id, original.id);
        assert!(rollback_path(&database).exists());
    }
}
