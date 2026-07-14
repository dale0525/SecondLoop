use crate::storage::Storage;
use base64::{Engine as _, engine::general_purpose::STANDARD};
use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};
use sqlx::{Row, SqlitePool};
use thiserror::Error;
use uuid::Uuid;

pub const MAX_ATTACHMENT_BYTES: usize = 16 * 1024 * 1024;
pub const MAX_ATTACHMENT_CHUNK_BYTES: usize = 256 * 1024;

#[derive(Clone, Debug, Error, PartialEq, Eq)]
pub enum AttachmentError {
    #[error("attachment request is invalid: {0}")]
    InvalidRequest(String),
    #[error("attachment not found")]
    NotFound,
    #[error("attachment idempotency conflict")]
    IdempotencyConflict,
    #[error("attachment exceeds size limit")]
    TooLarge,
    #[error("attachment store is unavailable")]
    Unavailable,
}

pub type AttachmentResult<T> = Result<T, AttachmentError>;

#[derive(Clone, Debug, Deserialize, Serialize, PartialEq, Eq, PartialOrd, Ord, Hash)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct AttachmentScope {
    pub app_id: String,
    pub tenant_id: String,
    pub user_id: String,
}

impl AttachmentScope {
    pub fn new(app_id: &str, tenant_id: &str, user_id: &str) -> AttachmentResult<Self> {
        let scope = Self {
            app_id: app_id.into(),
            tenant_id: tenant_id.into(),
            user_id: user_id.into(),
        };
        scope.validate()?;
        Ok(scope)
    }

    fn validate(&self) -> AttachmentResult<()> {
        for value in [&self.app_id, &self.tenant_id, &self.user_id] {
            valid(!value.trim().is_empty(), "attachment scope is required")?;
            valid(value.len() <= 255, "attachment scope is too long")?;
        }
        Ok(())
    }
}

#[derive(Clone, Debug, Deserialize, Serialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct AttachmentMetadata {
    pub id: String,
    pub file_name: String,
    pub mime_type: String,
    pub size_bytes: u64,
    pub sha256: String,
    pub created_at: DateTime<Utc>,
}

#[derive(Clone, Debug, Deserialize, Serialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct AttachmentChunk {
    pub attachment_id: String,
    pub offset: u64,
    pub data_base64: String,
    pub next_offset: u64,
    pub truncated: bool,
}

#[derive(Clone)]
pub struct SqliteAttachmentStore {
    pool: SqlitePool,
}

impl SqliteAttachmentStore {
    pub async fn from_storage(storage: &Storage) -> AttachmentResult<Self> {
        let store = Self {
            pool: storage.pool().clone(),
        };
        store.initialize().await?;
        Ok(store)
    }

    async fn initialize(&self) -> AttachmentResult<()> {
        sqlx::query(
            r#"
            CREATE TABLE IF NOT EXISTS attachment_blobs (
              id TEXT PRIMARY KEY,
              app_id TEXT NOT NULL,
              tenant_id TEXT NOT NULL,
              user_id TEXT NOT NULL,
              file_name TEXT NOT NULL,
              mime_type TEXT NOT NULL,
              size_bytes INTEGER NOT NULL,
              sha256 TEXT NOT NULL,
              data BLOB NOT NULL,
              created_at TEXT NOT NULL
            );
            CREATE INDEX IF NOT EXISTS attachment_scope_created
              ON attachment_blobs(app_id, tenant_id, user_id, created_at, id);
            CREATE TABLE IF NOT EXISTS attachment_idempotency (
              app_id TEXT NOT NULL,
              tenant_id TEXT NOT NULL,
              user_id TEXT NOT NULL,
              idempotency_key TEXT NOT NULL,
              request_sha256 TEXT NOT NULL,
              attachment_id TEXT NOT NULL,
              PRIMARY KEY(app_id, tenant_id, user_id, idempotency_key),
              FOREIGN KEY(attachment_id) REFERENCES attachment_blobs(id) ON DELETE CASCADE
            );
            "#,
        )
        .execute(&self.pool)
        .await
        .map_err(unavailable)?;
        Ok(())
    }

    pub async fn import(
        &self,
        scope: &AttachmentScope,
        file_name: &str,
        mime_type: &str,
        data: &[u8],
        idempotency_key: &str,
    ) -> AttachmentResult<AttachmentMetadata> {
        scope.validate()?;
        validate_import(file_name, mime_type, data, idempotency_key)?;
        let data_sha256 = hex::encode(Sha256::digest(data));
        let request_sha256 = request_fingerprint(file_name, mime_type, &data_sha256);
        let mut tx = self.pool.begin().await.map_err(unavailable)?;
        if let Some(row) = sqlx::query(
            "SELECT request_sha256, attachment_id FROM attachment_idempotency WHERE app_id = ? AND tenant_id = ? AND user_id = ? AND idempotency_key = ?",
        )
        .bind(&scope.app_id)
        .bind(&scope.tenant_id)
        .bind(&scope.user_id)
        .bind(idempotency_key)
        .fetch_optional(&mut *tx)
        .await
        .map_err(unavailable)?
        {
            let existing_hash: String = row.get("request_sha256");
            if existing_hash != request_sha256 {
                return Err(AttachmentError::IdempotencyConflict);
            }
            let attachment_id: String = row.get("attachment_id");
            return load_metadata(&mut tx, scope, &attachment_id)
                .await?
                .ok_or(AttachmentError::Unavailable);
        }

        let created_at = Utc::now();
        let metadata = AttachmentMetadata {
            id: Uuid::new_v4().to_string(),
            file_name: file_name.into(),
            mime_type: mime_type.into(),
            size_bytes: data.len() as u64,
            sha256: data_sha256,
            created_at,
        };
        sqlx::query(
            "INSERT INTO attachment_blobs(id, app_id, tenant_id, user_id, file_name, mime_type, size_bytes, sha256, data, created_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
        )
        .bind(&metadata.id)
        .bind(&scope.app_id)
        .bind(&scope.tenant_id)
        .bind(&scope.user_id)
        .bind(&metadata.file_name)
        .bind(&metadata.mime_type)
        .bind(metadata.size_bytes as i64)
        .bind(&metadata.sha256)
        .bind(data)
        .bind(metadata.created_at.to_rfc3339())
        .execute(&mut *tx)
        .await
        .map_err(unavailable)?;
        sqlx::query(
            "INSERT INTO attachment_idempotency(app_id, tenant_id, user_id, idempotency_key, request_sha256, attachment_id) VALUES (?, ?, ?, ?, ?, ?)",
        )
        .bind(&scope.app_id)
        .bind(&scope.tenant_id)
        .bind(&scope.user_id)
        .bind(idempotency_key)
        .bind(request_sha256)
        .bind(&metadata.id)
        .execute(&mut *tx)
        .await
        .map_err(unavailable)?;
        tx.commit().await.map_err(unavailable)?;
        Ok(metadata)
    }

    pub async fn list(
        &self,
        scope: &AttachmentScope,
        limit: usize,
    ) -> AttachmentResult<Vec<AttachmentMetadata>> {
        scope.validate()?;
        valid(
            (1..=100).contains(&limit),
            "attachment list limit is invalid",
        )?;
        let rows = sqlx::query(
            "SELECT id, file_name, mime_type, size_bytes, sha256, created_at FROM attachment_blobs WHERE app_id = ? AND tenant_id = ? AND user_id = ? ORDER BY created_at DESC, id LIMIT ?",
        )
        .bind(&scope.app_id)
        .bind(&scope.tenant_id)
        .bind(&scope.user_id)
        .bind(limit as i64)
        .fetch_all(&self.pool)
        .await
        .map_err(unavailable)?;
        rows.iter().map(decode_metadata).collect()
    }

    pub async fn get(
        &self,
        scope: &AttachmentScope,
        attachment_id: &str,
    ) -> AttachmentResult<Option<AttachmentMetadata>> {
        scope.validate()?;
        validate_id(attachment_id)?;
        let mut tx = self.pool.begin().await.map_err(unavailable)?;
        load_metadata(&mut tx, scope, attachment_id).await
    }

    pub async fn read(
        &self,
        scope: &AttachmentScope,
        attachment_id: &str,
        offset: u64,
        max_bytes: usize,
    ) -> AttachmentResult<AttachmentChunk> {
        scope.validate()?;
        validate_id(attachment_id)?;
        valid(
            (1..=MAX_ATTACHMENT_CHUNK_BYTES).contains(&max_bytes),
            "attachment chunk limit is invalid",
        )?;
        let start = i64::try_from(offset).map_err(|_| invalid("attachment offset is invalid"))?;
        let row = sqlx::query(
            "SELECT length(data) AS size_bytes, substr(data, ?, ?) AS data FROM attachment_blobs WHERE app_id = ? AND tenant_id = ? AND user_id = ? AND id = ?",
        )
        .bind(start.saturating_add(1))
        .bind(max_bytes as i64)
        .bind(&scope.app_id)
        .bind(&scope.tenant_id)
        .bind(&scope.user_id)
        .bind(attachment_id)
        .fetch_optional(&self.pool)
        .await
        .map_err(unavailable)?
        .ok_or(AttachmentError::NotFound)?;
        let size_bytes: i64 = row.get("size_bytes");
        valid(start <= size_bytes, "attachment offset exceeds content")?;
        let data: Vec<u8> = row.get("data");
        let next_offset = offset.saturating_add(data.len() as u64);
        Ok(AttachmentChunk {
            attachment_id: attachment_id.into(),
            offset,
            data_base64: STANDARD.encode(data),
            next_offset,
            truncated: next_offset < size_bytes as u64,
        })
    }

    pub async fn content(
        &self,
        scope: &AttachmentScope,
        attachment_id: &str,
    ) -> AttachmentResult<Vec<u8>> {
        scope.validate()?;
        validate_id(attachment_id)?;
        sqlx::query_scalar(
            "SELECT data FROM attachment_blobs WHERE app_id = ? AND tenant_id = ? AND user_id = ? AND id = ?",
        )
        .bind(&scope.app_id)
        .bind(&scope.tenant_id)
        .bind(&scope.user_id)
        .bind(attachment_id)
        .fetch_optional(&self.pool)
        .await
        .map_err(unavailable)?
        .ok_or(AttachmentError::NotFound)
    }

    pub async fn delete(
        &self,
        scope: &AttachmentScope,
        attachment_id: &str,
    ) -> AttachmentResult<bool> {
        scope.validate()?;
        validate_id(attachment_id)?;
        let mut tx = self.pool.begin().await.map_err(unavailable)?;
        sqlx::query(
            "DELETE FROM attachment_idempotency WHERE app_id = ? AND tenant_id = ? AND user_id = ? AND attachment_id = ?",
        )
        .bind(&scope.app_id)
        .bind(&scope.tenant_id)
        .bind(&scope.user_id)
        .bind(attachment_id)
        .execute(&mut *tx)
        .await
        .map_err(unavailable)?;
        let deleted = sqlx::query(
            "DELETE FROM attachment_blobs WHERE app_id = ? AND tenant_id = ? AND user_id = ? AND id = ?",
        )
        .bind(&scope.app_id)
        .bind(&scope.tenant_id)
        .bind(&scope.user_id)
        .bind(attachment_id)
        .execute(&mut *tx)
        .await
        .map_err(unavailable)?
        .rows_affected();
        tx.commit().await.map_err(unavailable)?;
        Ok(deleted == 1)
    }
}

async fn load_metadata(
    tx: &mut sqlx::Transaction<'_, sqlx::Sqlite>,
    scope: &AttachmentScope,
    attachment_id: &str,
) -> AttachmentResult<Option<AttachmentMetadata>> {
    let row = sqlx::query(
        "SELECT id, file_name, mime_type, size_bytes, sha256, created_at FROM attachment_blobs WHERE app_id = ? AND tenant_id = ? AND user_id = ? AND id = ?",
    )
    .bind(&scope.app_id)
    .bind(&scope.tenant_id)
    .bind(&scope.user_id)
    .bind(attachment_id)
    .fetch_optional(&mut **tx)
    .await
    .map_err(unavailable)?;
    row.as_ref().map(decode_metadata).transpose()
}

fn decode_metadata(row: &sqlx::sqlite::SqliteRow) -> AttachmentResult<AttachmentMetadata> {
    let size_bytes: i64 = row.get("size_bytes");
    valid(size_bytes >= 0, "attachment size is invalid")?;
    Ok(AttachmentMetadata {
        id: row.get("id"),
        file_name: row.get("file_name"),
        mime_type: row.get("mime_type"),
        size_bytes: size_bytes as u64,
        sha256: row.get("sha256"),
        created_at: row
            .get::<String, _>("created_at")
            .parse()
            .map_err(|_| AttachmentError::Unavailable)?,
    })
}

fn validate_import(
    file_name: &str,
    mime_type: &str,
    data: &[u8],
    idempotency_key: &str,
) -> AttachmentResult<()> {
    valid(
        !file_name.trim().is_empty()
            && file_name.len() <= 255
            && !file_name.chars().any(|value| value.is_control())
            && !file_name.contains(['/', '\\']),
        "attachment file name is invalid",
    )?;
    valid(
        !mime_type.trim().is_empty()
            && mime_type.len() <= 255
            && mime_type.is_ascii()
            && !mime_type.chars().any(char::is_whitespace),
        "attachment MIME type is invalid",
    )?;
    if data.len() > MAX_ATTACHMENT_BYTES {
        return Err(AttachmentError::TooLarge);
    }
    valid(
        !idempotency_key.trim().is_empty() && idempotency_key.len() <= 512,
        "attachment idempotency key is invalid",
    )
}

fn validate_id(value: &str) -> AttachmentResult<()> {
    valid(Uuid::parse_str(value).is_ok(), "attachment ID is invalid")
}

fn request_fingerprint(file_name: &str, mime_type: &str, data_sha256: &str) -> String {
    let mut hash = Sha256::new();
    for value in [file_name, mime_type, data_sha256] {
        hash.update(value.as_bytes());
        hash.update([0]);
    }
    hex::encode(hash.finalize())
}

fn invalid(message: impl Into<String>) -> AttachmentError {
    AttachmentError::InvalidRequest(message.into())
}

fn valid(condition: bool, message: impl Into<String>) -> AttachmentResult<()> {
    condition.then_some(()).ok_or_else(|| invalid(message))
}

fn unavailable(_: sqlx::Error) -> AttachmentError {
    AttachmentError::Unavailable
}

#[cfg(test)]
#[path = "attachments_tests.rs"]
mod tests;
