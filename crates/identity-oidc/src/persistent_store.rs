use crate::{
    AuthorizationTransaction, OidcSecretStore, SecretStoreError, SecretValue, SessionBinding,
    SessionLease, SessionMetadata, SessionSecrets, StateDigest, StoredSession, store::LeaseToken,
};
use agent_runtime::credential::{CredentialScope, SecretId, SecretMaterial, SecretStore};
use async_trait::async_trait;
use base64::{Engine as _, engine::general_purpose::URL_SAFE_NO_PAD};
use chrono::{DateTime, Duration, Utc};
use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};
use sqlx::{Row, SqlitePool};
use std::{collections::BTreeSet, sync::Arc};
use uuid::Uuid;
use zeroize::{Zeroize, Zeroizing};

const STORE_SCHEMA_VERSION: i64 = 1;
const UPDATE_LEASE_SECONDS: i64 = 60;

#[derive(Clone)]
pub struct PersistentOidcSecretStore {
    pool: SqlitePool,
    secrets: Arc<dyn SecretStore>,
    scope: CredentialScope,
}

impl std::fmt::Debug for PersistentOidcSecretStore {
    fn fmt(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        formatter
            .debug_struct("PersistentOidcSecretStore")
            .field("scope", &"[SCOPED]")
            .finish_non_exhaustive()
    }
}

impl PersistentOidcSecretStore {
    pub async fn new(
        pool: SqlitePool,
        secrets: Arc<dyn SecretStore>,
        scope: CredentialScope,
    ) -> Result<Self, SecretStoreError> {
        scope.validate().map_err(|_| SecretStoreError::Failure)?;
        migrate(&pool).await?;
        Ok(Self {
            pool,
            secrets,
            scope,
        })
    }

    async fn save_blob(
        &self,
        kind: &str,
        bytes: Zeroizing<Vec<u8>>,
    ) -> Result<SecretId, SecretStoreError> {
        let id = SecretId::parse(&format!("oidc-{kind}-{}", Uuid::new_v4()))
            .map_err(|_| SecretStoreError::Failure)?;
        self.secrets
            .save(
                &self.scope,
                &id,
                SecretMaterial::new(bytes.as_slice()).map_err(|_| SecretStoreError::Failure)?,
            )
            .await
            .map_err(|_| SecretStoreError::Failure)?;
        Ok(id)
    }

    async fn load_blob(&self, id: &SecretId) -> Result<Zeroizing<Vec<u8>>, SecretStoreError> {
        let material = self
            .secrets
            .load(&self.scope, id)
            .await
            .map_err(|_| SecretStoreError::Failure)?
            .ok_or(SecretStoreError::NotFound)?;
        Ok(material.with_exposed_bytes(|bytes| Zeroizing::new(bytes.to_vec())))
    }

    async fn delete_blob(&self, id: &SecretId) -> Result<(), SecretStoreError> {
        self.secrets
            .delete(&self.scope, id)
            .await
            .map(|_| ())
            .map_err(|_| SecretStoreError::Failure)
    }
}

#[derive(Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
struct AuthorizationWire {
    binding: BindingWire,
    code_verifier: String,
    nonce: String,
    requested_scopes: BTreeSet<String>,
    expires_at: DateTime<Utc>,
}

#[derive(Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
struct SessionWire {
    binding: BindingWire,
    metadata: SessionMetadataWire,
    access_token: String,
    refresh_token: Option<String>,
    id_token: String,
    nonce: String,
}

#[derive(Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
struct BindingWire {
    provider_id: String,
    app_id: String,
    tenant_id: String,
    audience: String,
}

#[derive(Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
struct SessionMetadataWire {
    issuer: String,
    subject: String,
    granted_scopes: BTreeSet<String>,
    authenticated_at: DateTime<Utc>,
    expires_at: DateTime<Utc>,
}

#[async_trait]
impl OidcSecretStore for PersistentOidcSecretStore {
    async fn insert_authorization(
        &self,
        state: StateDigest,
        transaction: AuthorizationTransaction,
    ) -> Result<(), SecretStoreError> {
        let bytes = encode_authorization(&transaction)?;
        let secret_id = self.save_blob("authorization", bytes).await?;
        let result = sqlx::query(
            "INSERT INTO oidc_authorizations (state_digest, secret_id, expires_at) VALUES (?, ?, ?)",
        )
        .bind(&state.as_bytes()[..])
        .bind(secret_id.as_str())
        .bind(transaction.expires_at)
        .execute(&self.pool)
        .await;
        match result {
            Ok(_) => Ok(()),
            Err(error) => {
                let _ = self.delete_blob(&secret_id).await;
                if database_conflict(&error) {
                    Err(SecretStoreError::Conflict)
                } else {
                    Err(SecretStoreError::Failure)
                }
            }
        }
    }

    async fn take_authorization(
        &self,
        state: &StateDigest,
        now: DateTime<Utc>,
    ) -> Result<Option<AuthorizationTransaction>, SecretStoreError> {
        let mut transaction = self
            .pool
            .begin()
            .await
            .map_err(|_| SecretStoreError::Failure)?;
        let row = sqlx::query(
            "DELETE FROM oidc_authorizations WHERE state_digest = ? RETURNING secret_id, expires_at",
        )
        .bind(&state.as_bytes()[..])
        .fetch_optional(&mut *transaction)
        .await
        .map_err(|_| SecretStoreError::Failure)?;
        transaction
            .commit()
            .await
            .map_err(|_| SecretStoreError::Failure)?;
        let Some(row) = row else { return Ok(None) };
        let secret_id = parse_secret_id(row.try_get("secret_id"))?;
        let expires_at: DateTime<Utc> = row
            .try_get("expires_at")
            .map_err(|_| SecretStoreError::Failure)?;
        let bytes = self.load_blob(&secret_id).await;
        let _ = self.delete_blob(&secret_id).await;
        if expires_at <= now {
            return Ok(None);
        }
        decode_authorization(bytes?).map(Some)
    }

    async fn put_session(
        &self,
        binding: SessionBinding,
        session: StoredSession,
    ) -> Result<(), SecretStoreError> {
        let binding_key = binding_key(&binding);
        let bytes = encode_session(&binding, &session)?;
        let new_secret = self.save_blob("session", bytes).await?;
        let now = Utc::now();
        let mut transaction = self
            .pool
            .begin()
            .await
            .map_err(|_| SecretStoreError::Failure)?;
        let existing = sqlx::query(
            "SELECT secret_id, lease_expires_at FROM oidc_sessions WHERE binding_key = ?",
        )
        .bind(&binding_key)
        .fetch_optional(&mut *transaction)
        .await
        .map_err(|_| SecretStoreError::Failure)?;
        if existing.as_ref().is_some_and(|row| {
            row.try_get::<Option<DateTime<Utc>>, _>("lease_expires_at")
                .ok()
                .flatten()
                .is_some_and(|expires| expires > now)
        }) {
            let _ = transaction.rollback().await;
            let _ = self.delete_blob(&new_secret).await;
            return Err(SecretStoreError::Busy);
        }
        let old_secret = existing
            .as_ref()
            .and_then(|row| row.try_get::<String, _>("secret_id").ok())
            .and_then(|value| SecretId::parse(&value).ok());
        sqlx::query(
            "INSERT INTO oidc_sessions (binding_key, secret_id, lease_token, lease_expires_at, updated_at) VALUES (?, ?, NULL, NULL, ?) ON CONFLICT(binding_key) DO UPDATE SET secret_id = excluded.secret_id, lease_token = NULL, lease_expires_at = NULL, updated_at = excluded.updated_at",
        )
        .bind(&binding_key)
        .bind(new_secret.as_str())
        .bind(now)
        .execute(&mut *transaction)
        .await
        .map_err(|_| SecretStoreError::Failure)?;
        transaction
            .commit()
            .await
            .map_err(|_| SecretStoreError::Failure)?;
        if let Some(old) = old_secret {
            let _ = self.delete_blob(&old).await;
        }
        Ok(())
    }

    async fn session_metadata(
        &self,
        binding: &SessionBinding,
    ) -> Result<Option<SessionMetadata>, SecretStoreError> {
        let row = sqlx::query("SELECT secret_id FROM oidc_sessions WHERE binding_key = ?")
            .bind(binding_key(binding))
            .fetch_optional(&self.pool)
            .await
            .map_err(|_| SecretStoreError::Failure)?;
        let Some(row) = row else { return Ok(None) };
        let id = parse_secret_id(row.try_get("secret_id"))?;
        let (_, session) = decode_session(self.load_blob(&id).await?)?;
        Ok(Some(session.metadata))
    }

    async fn lease_session(
        &self,
        binding: &SessionBinding,
    ) -> Result<Option<SessionLease>, SecretStoreError> {
        let key = binding_key(binding);
        let now = Utc::now();
        let token = lease_token();
        let expires = now + Duration::seconds(UPDATE_LEASE_SECONDS);
        let row = sqlx::query(
            "UPDATE oidc_sessions SET lease_token = ?, lease_expires_at = ?, updated_at = ? WHERE binding_key = ? AND (lease_token IS NULL OR lease_expires_at <= ?) RETURNING secret_id",
        )
        .bind(token.to_string())
        .bind(expires)
        .bind(now)
        .bind(&key)
        .bind(now)
        .fetch_optional(&self.pool)
        .await
        .map_err(|_| SecretStoreError::Failure)?;
        let Some(row) = row else {
            let exists = sqlx::query("SELECT 1 FROM oidc_sessions WHERE binding_key = ?")
                .bind(&key)
                .fetch_optional(&self.pool)
                .await
                .map_err(|_| SecretStoreError::Failure)?
                .is_some();
            return if exists {
                Err(SecretStoreError::Busy)
            } else {
                Ok(None)
            };
        };
        let id = parse_secret_id(row.try_get("secret_id"))?;
        match self.load_blob(&id).await.and_then(decode_session) {
            Ok((stored_binding, session)) if stored_binding == *binding => Ok(Some(SessionLease {
                binding: binding.clone(),
                token: LeaseToken(token),
                session,
            })),
            _ => {
                let _ = release_lease(&self.pool, &key, token).await;
                Err(SecretStoreError::Failure)
            }
        }
    }

    async fn commit_session(
        &self,
        lease: SessionLease,
        replacement: StoredSession,
    ) -> Result<(), SecretStoreError> {
        let key = binding_key(&lease.binding);
        let new_secret = self
            .save_blob("session", encode_session(&lease.binding, &replacement)?)
            .await?;
        let mut transaction = self
            .pool
            .begin()
            .await
            .map_err(|_| SecretStoreError::Failure)?;
        let old_secret = sqlx::query(
            "SELECT secret_id FROM oidc_sessions WHERE binding_key = ? AND lease_token = ?",
        )
        .bind(&key)
        .bind(lease.token.0.to_string())
        .fetch_optional(&mut *transaction)
        .await
        .map_err(|_| SecretStoreError::Failure)?
        .map(|row| parse_secret_id(row.try_get("secret_id")))
        .transpose()?;
        let Some(old_secret) = old_secret else {
            let _ = transaction.rollback().await;
            let _ = self.delete_blob(&new_secret).await;
            return Err(SecretStoreError::Conflict);
        };
        let updated = sqlx::query(
            "UPDATE oidc_sessions SET secret_id = ?, lease_token = NULL, lease_expires_at = NULL, updated_at = ? WHERE binding_key = ? AND lease_token = ?",
        )
        .bind(new_secret.as_str())
        .bind(Utc::now())
        .bind(&key)
        .bind(lease.token.0.to_string())
        .execute(&mut *transaction)
        .await
        .map_err(|_| SecretStoreError::Failure)?;
        if updated.rows_affected() != 1 {
            let _ = transaction.rollback().await;
            let _ = self.delete_blob(&new_secret).await;
            return Err(SecretStoreError::Conflict);
        }
        transaction
            .commit()
            .await
            .map_err(|_| SecretStoreError::Failure)?;
        let _ = self.delete_blob(&old_secret).await;
        Ok(())
    }

    async fn release_session(&self, lease: SessionLease) -> Result<(), SecretStoreError> {
        let changed =
            release_lease(&self.pool, &binding_key(&lease.binding), lease.token.0).await?;
        if changed {
            Ok(())
        } else {
            Err(SecretStoreError::Conflict)
        }
    }

    async fn delete_leased_session(&self, lease: SessionLease) -> Result<(), SecretStoreError> {
        let row = sqlx::query(
            "DELETE FROM oidc_sessions WHERE binding_key = ? AND lease_token = ? RETURNING secret_id",
        )
        .bind(binding_key(&lease.binding))
        .bind(lease.token.0.to_string())
        .fetch_optional(&self.pool)
        .await
        .map_err(|_| SecretStoreError::Failure)?
        .ok_or(SecretStoreError::Conflict)?;
        let id = parse_secret_id(row.try_get("secret_id"))?;
        self.delete_blob(&id).await
    }
}

async fn migrate(pool: &SqlitePool) -> Result<(), SecretStoreError> {
    sqlx::query(
        "CREATE TABLE IF NOT EXISTS oidc_store_metadata (singleton INTEGER PRIMARY KEY CHECK(singleton = 1), schema_version INTEGER NOT NULL);",
    )
    .execute(pool)
    .await
    .map_err(|_| SecretStoreError::Failure)?;
    sqlx::query(
        "INSERT INTO oidc_store_metadata (singleton, schema_version) VALUES (1, ?) ON CONFLICT(singleton) DO NOTHING",
    )
    .bind(STORE_SCHEMA_VERSION)
    .execute(pool)
    .await
    .map_err(|_| SecretStoreError::Failure)?;
    let version = sqlx::query("SELECT schema_version FROM oidc_store_metadata WHERE singleton = 1")
        .fetch_one(pool)
        .await
        .map_err(|_| SecretStoreError::Failure)?;
    let version: i64 = version
        .try_get("schema_version")
        .map_err(|_| SecretStoreError::Failure)?;
    if version != STORE_SCHEMA_VERSION {
        return Err(SecretStoreError::Failure);
    }
    sqlx::query(
        "CREATE TABLE IF NOT EXISTS oidc_authorizations (state_digest BLOB PRIMARY KEY, secret_id TEXT NOT NULL UNIQUE, expires_at TEXT NOT NULL);",
    )
    .execute(pool)
    .await
    .map_err(|_| SecretStoreError::Failure)?;
    sqlx::query(
        "CREATE TABLE IF NOT EXISTS oidc_sessions (binding_key TEXT PRIMARY KEY, secret_id TEXT NOT NULL UNIQUE, lease_token TEXT, lease_expires_at TEXT, updated_at TEXT NOT NULL);",
    )
    .execute(pool)
    .await
    .map_err(|_| SecretStoreError::Failure)?;
    Ok(())
}

fn encode_authorization(
    value: &AuthorizationTransaction,
) -> Result<Zeroizing<Vec<u8>>, SecretStoreError> {
    encode(&AuthorizationWire {
        binding: binding_wire(&value.binding),
        code_verifier: value.code_verifier.expose_secret().into(),
        nonce: value.nonce.expose_secret().into(),
        requested_scopes: value.requested_scopes.clone(),
        expires_at: value.expires_at,
    })
}

fn decode_authorization(
    mut bytes: Zeroizing<Vec<u8>>,
) -> Result<AuthorizationTransaction, SecretStoreError> {
    let wire: AuthorizationWire =
        serde_json::from_slice(&bytes).map_err(|_| SecretStoreError::Failure)?;
    bytes.zeroize();
    Ok(AuthorizationTransaction {
        binding: binding_from_wire(wire.binding),
        code_verifier: SecretValue::new(wire.code_verifier),
        nonce: SecretValue::new(wire.nonce),
        requested_scopes: wire.requested_scopes,
        expires_at: wire.expires_at,
    })
}

fn encode_session(
    binding: &SessionBinding,
    session: &StoredSession,
) -> Result<Zeroizing<Vec<u8>>, SecretStoreError> {
    encode(&SessionWire {
        binding: binding_wire(binding),
        metadata: SessionMetadataWire {
            issuer: session.metadata.issuer.clone(),
            subject: session.metadata.subject.clone(),
            granted_scopes: session.metadata.granted_scopes.clone(),
            authenticated_at: session.metadata.authenticated_at,
            expires_at: session.metadata.expires_at,
        },
        access_token: session.secrets.access_token().expose_secret().into(),
        refresh_token: session
            .secrets
            .refresh_token()
            .map(|value| value.expose_secret().into()),
        id_token: session.secrets.id_token().expose_secret().into(),
        nonce: session.secrets.nonce().expose_secret().into(),
    })
}

fn decode_session(
    mut bytes: Zeroizing<Vec<u8>>,
) -> Result<(SessionBinding, StoredSession), SecretStoreError> {
    let wire: SessionWire =
        serde_json::from_slice(&bytes).map_err(|_| SecretStoreError::Failure)?;
    bytes.zeroize();
    let binding = binding_from_wire(wire.binding);
    let metadata = SessionMetadata {
        issuer: wire.metadata.issuer,
        subject: wire.metadata.subject,
        granted_scopes: wire.metadata.granted_scopes,
        authenticated_at: wire.metadata.authenticated_at,
        expires_at: wire.metadata.expires_at,
    };
    let secrets = SessionSecrets::new(
        SecretValue::new(wire.access_token),
        wire.refresh_token.map(SecretValue::new),
        SecretValue::new(wire.id_token),
        SecretValue::new(wire.nonce),
    );
    Ok((binding, StoredSession::new(metadata, secrets)))
}

fn encode(value: &impl Serialize) -> Result<Zeroizing<Vec<u8>>, SecretStoreError> {
    serde_json::to_vec(value)
        .map(Zeroizing::new)
        .map_err(|_| SecretStoreError::Failure)
}

fn binding_wire(binding: &SessionBinding) -> BindingWire {
    BindingWire {
        provider_id: binding.provider_id().into(),
        app_id: binding.app_id().into(),
        tenant_id: binding.tenant_id().into(),
        audience: binding.audience().into(),
    }
}

fn binding_from_wire(wire: BindingWire) -> SessionBinding {
    SessionBinding::new(wire.provider_id, wire.app_id, wire.tenant_id, wire.audience)
}

fn binding_key(binding: &SessionBinding) -> String {
    let mut digest = Sha256::new();
    digest.update(b"agentweave.identity.oidc.binding.v1\0");
    for value in [
        binding.provider_id(),
        binding.app_id(),
        binding.tenant_id(),
        binding.audience(),
    ] {
        digest.update((value.len() as u64).to_be_bytes());
        digest.update(value.as_bytes());
    }
    URL_SAFE_NO_PAD.encode(digest.finalize())
}

fn lease_token() -> u64 {
    let bytes = *Uuid::new_v4().as_bytes();
    u64::from_be_bytes(bytes[..8].try_into().expect("UUID prefix has eight bytes"))
}

async fn release_lease(pool: &SqlitePool, key: &str, token: u64) -> Result<bool, SecretStoreError> {
    let result = sqlx::query(
        "UPDATE oidc_sessions SET lease_token = NULL, lease_expires_at = NULL, updated_at = ? WHERE binding_key = ? AND lease_token = ?",
    )
    .bind(Utc::now())
    .bind(key)
    .bind(token.to_string())
    .execute(pool)
    .await
    .map_err(|_| SecretStoreError::Failure)?;
    Ok(result.rows_affected() == 1)
}

fn parse_secret_id(value: Result<String, sqlx::Error>) -> Result<SecretId, SecretStoreError> {
    SecretId::parse(&value.map_err(|_| SecretStoreError::Failure)?)
        .map_err(|_| SecretStoreError::Failure)
}

fn database_conflict(error: &sqlx::Error) -> bool {
    error
        .as_database_error()
        .is_some_and(|database| database.is_unique_violation())
}

#[cfg(test)]
mod tests {
    use super::*;
    use agent_runtime::{credential::InMemorySecretStore, storage::Storage};

    #[tokio::test]
    async fn authorization_is_single_use_across_store_reconstruction() {
        let storage = Storage::connect("sqlite::memory:").await.unwrap();
        let secrets = Arc::new(InMemorySecretStore::default());
        let scope = test_scope();
        let store =
            PersistentOidcSecretStore::new(storage.sqlite_pool(), secrets.clone(), scope.clone())
                .await
                .unwrap();
        let state = StateDigest::new([7; 32]);
        store
            .insert_authorization(state, authorization())
            .await
            .unwrap();
        let rebuilt = PersistentOidcSecretStore::new(storage.sqlite_pool(), secrets, scope)
            .await
            .unwrap();

        assert!(
            rebuilt
                .take_authorization(&state, Utc::now())
                .await
                .unwrap()
                .is_some()
        );
        assert!(
            rebuilt
                .take_authorization(&state, Utc::now())
                .await
                .unwrap()
                .is_none()
        );
    }

    #[tokio::test]
    async fn session_leases_are_atomic_and_persist_metadata() {
        let storage = Storage::connect("sqlite::memory:").await.unwrap();
        let store = PersistentOidcSecretStore::new(
            storage.sqlite_pool(),
            Arc::new(InMemorySecretStore::default()),
            test_scope(),
        )
        .await
        .unwrap();
        let binding = binding();
        store.put_session(binding.clone(), session()).await.unwrap();

        let lease = store.lease_session(&binding).await.unwrap().unwrap();
        assert!(matches!(
            store.lease_session(&binding).await,
            Err(SecretStoreError::Busy)
        ));
        store.release_session(lease).await.unwrap();
        assert_eq!(
            store
                .session_metadata(&binding)
                .await
                .unwrap()
                .unwrap()
                .subject,
            "user-1"
        );
    }

    fn test_scope() -> CredentialScope {
        CredentialScope {
            app_id: "com.example.app".into(),
            tenant_id: "local".into(),
            user_id: "identity-oidc".into(),
        }
    }

    fn binding() -> SessionBinding {
        SessionBinding::new(
            "agentweave.identity.oidc",
            "com.example.app",
            "local",
            "https://gateway.example",
        )
    }

    fn authorization() -> AuthorizationTransaction {
        AuthorizationTransaction {
            binding: binding(),
            code_verifier: SecretValue::new("verifier"),
            nonce: SecretValue::new("nonce"),
            requested_scopes: BTreeSet::from(["openid".into()]),
            expires_at: Utc::now() + Duration::minutes(5),
        }
    }

    fn session() -> StoredSession {
        StoredSession::new(
            SessionMetadata {
                issuer: "https://identity.example".into(),
                subject: "user-1".into(),
                granted_scopes: BTreeSet::from(["model.invoke".into()]),
                authenticated_at: Utc::now(),
                expires_at: Utc::now() + Duration::hours(1),
            },
            SessionSecrets::new(
                SecretValue::new("access"),
                Some(SecretValue::new("refresh")),
                SecretValue::new("id-token"),
                SecretValue::new("nonce"),
            ),
        )
    }
}
