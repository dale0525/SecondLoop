use crate::secret::SecretValue;
use async_trait::async_trait;
use chrono::{DateTime, Utc};
use std::{
    collections::{BTreeSet, HashMap},
    fmt,
    sync::atomic::{AtomicU64, Ordering},
};
use tokio::sync::Mutex;

#[derive(Clone, Debug, PartialEq, Eq, Hash)]
pub struct SessionBinding {
    provider_id: String,
    app_id: String,
    tenant_id: String,
    audience: String,
}

impl SessionBinding {
    pub fn new(
        provider_id: impl Into<String>,
        app_id: impl Into<String>,
        tenant_id: impl Into<String>,
        audience: impl Into<String>,
    ) -> Self {
        Self {
            provider_id: provider_id.into(),
            app_id: app_id.into(),
            tenant_id: tenant_id.into(),
            audience: audience.into(),
        }
    }

    pub fn provider_id(&self) -> &str {
        &self.provider_id
    }

    pub fn app_id(&self) -> &str {
        &self.app_id
    }

    pub fn tenant_id(&self) -> &str {
        &self.tenant_id
    }

    pub fn audience(&self) -> &str {
        &self.audience
    }
}

#[derive(Clone, Copy, PartialEq, Eq, Hash)]
pub struct StateDigest([u8; 32]);

impl StateDigest {
    pub fn new(bytes: [u8; 32]) -> Self {
        Self(bytes)
    }

    pub fn as_bytes(&self) -> &[u8; 32] {
        &self.0
    }
}

impl fmt::Debug for StateDigest {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter.write_str("StateDigest([REDACTED])")
    }
}

/// Secret authorization state. Store implementations must persist it only in
/// a host secure store and must make `take_authorization` atomic.
#[derive(Clone)]
pub struct AuthorizationTransaction {
    pub(crate) binding: SessionBinding,
    pub(crate) code_verifier: SecretValue,
    pub(crate) nonce: SecretValue,
    pub(crate) requested_scopes: BTreeSet<String>,
    pub(crate) expires_at: DateTime<Utc>,
}

impl AuthorizationTransaction {
    pub fn binding(&self) -> &SessionBinding {
        &self.binding
    }

    pub fn code_verifier(&self) -> &SecretValue {
        &self.code_verifier
    }

    pub fn nonce(&self) -> &SecretValue {
        &self.nonce
    }

    pub fn requested_scopes(&self) -> &BTreeSet<String> {
        &self.requested_scopes
    }

    pub fn expires_at(&self) -> DateTime<Utc> {
        self.expires_at
    }
}

impl fmt::Debug for AuthorizationTransaction {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter
            .debug_struct("AuthorizationTransaction")
            .field("binding", &self.binding)
            .field("code_verifier", &"[REDACTED]")
            .field("nonce", &"[REDACTED]")
            .field("requested_scopes", &self.requested_scopes)
            .field("expires_at", &self.expires_at)
            .finish()
    }
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct SessionMetadata {
    pub issuer: String,
    pub subject: String,
    pub granted_scopes: BTreeSet<String>,
    pub authenticated_at: DateTime<Utc>,
    pub expires_at: DateTime<Utc>,
}

#[derive(Clone)]
pub struct SessionSecrets {
    access_token: SecretValue,
    refresh_token: Option<SecretValue>,
    id_token: SecretValue,
    nonce: SecretValue,
}

impl SessionSecrets {
    pub fn new(
        access_token: SecretValue,
        refresh_token: Option<SecretValue>,
        id_token: SecretValue,
        nonce: SecretValue,
    ) -> Self {
        Self {
            access_token,
            refresh_token,
            id_token,
            nonce,
        }
    }

    pub fn access_token(&self) -> &SecretValue {
        &self.access_token
    }

    pub fn refresh_token(&self) -> Option<&SecretValue> {
        self.refresh_token.as_ref()
    }

    pub fn id_token(&self) -> &SecretValue {
        &self.id_token
    }

    pub fn nonce(&self) -> &SecretValue {
        &self.nonce
    }
}

impl fmt::Debug for SessionSecrets {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter
            .debug_struct("SessionSecrets")
            .field("access_token", &"[REDACTED]")
            .field(
                "refresh_token",
                &self.refresh_token.as_ref().map(|_| "[REDACTED]"),
            )
            .field("id_token", &"[REDACTED]")
            .field("nonce", &"[REDACTED]")
            .finish()
    }
}

#[derive(Clone)]
pub struct StoredSession {
    pub(crate) metadata: SessionMetadata,
    pub(crate) secrets: SessionSecrets,
}

impl StoredSession {
    pub fn new(metadata: SessionMetadata, secrets: SessionSecrets) -> Self {
        Self { metadata, secrets }
    }

    pub fn metadata(&self) -> &SessionMetadata {
        &self.metadata
    }

    pub fn secrets(&self) -> &SessionSecrets {
        &self.secrets
    }
}

impl fmt::Debug for StoredSession {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter
            .debug_struct("StoredSession")
            .field("metadata", &self.metadata)
            .field("secrets", &self.secrets)
            .finish()
    }
}

#[derive(Clone, Copy, PartialEq, Eq)]
pub(crate) struct LeaseToken(pub(crate) u64);

pub struct SessionLease {
    pub(crate) binding: SessionBinding,
    pub(crate) token: LeaseToken,
    pub(crate) session: StoredSession,
}

impl SessionLease {
    pub fn binding(&self) -> &SessionBinding {
        &self.binding
    }

    pub fn session(&self) -> &StoredSession {
        &self.session
    }
}

impl fmt::Debug for SessionLease {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter
            .debug_struct("SessionLease")
            .field("binding", &self.binding)
            .field("token", &"[REDACTED]")
            .field("session", &self.session)
            .finish()
    }
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum SecretStoreError {
    Conflict,
    NotFound,
    Busy,
    Failure,
}

#[async_trait]
pub trait OidcSecretStore: Send + Sync {
    /// Must atomically reject an existing digest.
    async fn insert_authorization(
        &self,
        state: StateDigest,
        transaction: AuthorizationTransaction,
    ) -> Result<(), SecretStoreError>;

    /// Must atomically remove before returning. Expired records must also be
    /// removed and returned as `None`, preventing replay and concurrent use.
    async fn take_authorization(
        &self,
        state: &StateDigest,
        now: DateTime<Utc>,
    ) -> Result<Option<AuthorizationTransaction>, SecretStoreError>;

    async fn put_session(
        &self,
        binding: SessionBinding,
        session: StoredSession,
    ) -> Result<(), SecretStoreError>;

    async fn session_metadata(
        &self,
        binding: &SessionBinding,
    ) -> Result<Option<SessionMetadata>, SecretStoreError>;

    /// Must atomically grant at most one update lease per binding.
    async fn lease_session(
        &self,
        binding: &SessionBinding,
    ) -> Result<Option<SessionLease>, SecretStoreError>;

    async fn commit_session(
        &self,
        lease: SessionLease,
        replacement: StoredSession,
    ) -> Result<(), SecretStoreError>;

    async fn release_session(&self, lease: SessionLease) -> Result<(), SecretStoreError>;

    async fn delete_leased_session(&self, lease: SessionLease) -> Result<(), SecretStoreError>;
}

#[derive(Default)]
pub struct InMemoryOidcSecretStore {
    authorizations: Mutex<HashMap<StateDigest, AuthorizationTransaction>>,
    sessions: Mutex<HashMap<SessionBinding, SessionSlot>>,
    next_lease: AtomicU64,
}

struct SessionSlot {
    session: StoredSession,
    lease: Option<LeaseToken>,
}

#[async_trait]
impl OidcSecretStore for InMemoryOidcSecretStore {
    async fn insert_authorization(
        &self,
        state: StateDigest,
        transaction: AuthorizationTransaction,
    ) -> Result<(), SecretStoreError> {
        let mut records = self.authorizations.lock().await;
        if records.contains_key(&state) {
            return Err(SecretStoreError::Conflict);
        }
        records.insert(state, transaction);
        Ok(())
    }

    async fn take_authorization(
        &self,
        state: &StateDigest,
        now: DateTime<Utc>,
    ) -> Result<Option<AuthorizationTransaction>, SecretStoreError> {
        let record = self.authorizations.lock().await.remove(state);
        Ok(record.filter(|transaction| transaction.expires_at > now))
    }

    async fn put_session(
        &self,
        binding: SessionBinding,
        session: StoredSession,
    ) -> Result<(), SecretStoreError> {
        let mut sessions = self.sessions.lock().await;
        if sessions
            .get(&binding)
            .is_some_and(|slot| slot.lease.is_some())
        {
            return Err(SecretStoreError::Busy);
        }
        sessions.insert(
            binding,
            SessionSlot {
                session,
                lease: None,
            },
        );
        Ok(())
    }

    async fn session_metadata(
        &self,
        binding: &SessionBinding,
    ) -> Result<Option<SessionMetadata>, SecretStoreError> {
        Ok(self
            .sessions
            .lock()
            .await
            .get(binding)
            .map(|slot| slot.session.metadata.clone()))
    }

    async fn lease_session(
        &self,
        binding: &SessionBinding,
    ) -> Result<Option<SessionLease>, SecretStoreError> {
        let mut sessions = self.sessions.lock().await;
        let Some(slot) = sessions.get_mut(binding) else {
            return Ok(None);
        };
        if slot.lease.is_some() {
            return Err(SecretStoreError::Busy);
        }
        let id = self
            .next_lease
            .fetch_update(Ordering::Relaxed, Ordering::Relaxed, |value| {
                value.checked_add(1)
            })
            .map_err(|_| SecretStoreError::Failure)?;
        let token = LeaseToken(id);
        slot.lease = Some(token);
        Ok(Some(SessionLease {
            binding: binding.clone(),
            token,
            session: slot.session.clone(),
        }))
    }

    async fn commit_session(
        &self,
        lease: SessionLease,
        replacement: StoredSession,
    ) -> Result<(), SecretStoreError> {
        let mut sessions = self.sessions.lock().await;
        let slot = sessions
            .get_mut(&lease.binding)
            .ok_or(SecretStoreError::NotFound)?;
        if slot.lease != Some(lease.token) {
            return Err(SecretStoreError::Conflict);
        }
        slot.session = replacement;
        slot.lease = None;
        Ok(())
    }

    async fn release_session(&self, lease: SessionLease) -> Result<(), SecretStoreError> {
        let mut sessions = self.sessions.lock().await;
        let slot = sessions
            .get_mut(&lease.binding)
            .ok_or(SecretStoreError::NotFound)?;
        if slot.lease != Some(lease.token) {
            return Err(SecretStoreError::Conflict);
        }
        slot.lease = None;
        Ok(())
    }

    async fn delete_leased_session(&self, lease: SessionLease) -> Result<(), SecretStoreError> {
        let mut sessions = self.sessions.lock().await;
        let slot = sessions
            .get(&lease.binding)
            .ok_or(SecretStoreError::NotFound)?;
        if slot.lease != Some(lease.token) {
            return Err(SecretStoreError::Conflict);
        }
        sessions.remove(&lease.binding);
        Ok(())
    }
}
