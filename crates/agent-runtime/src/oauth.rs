use crate::{
    credential::{
        ConnectorAccount, CredentialScope, CredentialVault, ProviderCredential, SecretId,
        SecretMaterial,
    },
    oauth_sqlite::{OAuthStateConsumption, SqliteOAuthStore},
    storage::Storage,
};
use async_trait::async_trait;
use base64::{Engine as _, engine::general_purpose::URL_SAFE_NO_PAD};
use chrono::{DateTime, Duration as ChronoDuration, Utc};
use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};
use std::{
    collections::{BTreeMap, BTreeSet},
    fmt,
    sync::Arc,
    time::Duration,
};
use tokio::sync::Mutex as AsyncMutex;
use uuid::Uuid;
use zeroize::Zeroizing;

#[path = "oauth_recovery.rs"]
mod recovery;
#[path = "oauth_validation.rs"]
mod validation;
use validation::{
    callback_error_code, provider_account_id, random_hex, secret_utf8,
    secure_provider_authorization_url, validate_authorization_origin, validate_authorization_plan,
    validate_authorization_request, validate_callback_request, validate_callback_url,
    validate_identifier, validate_provider_subject, validate_token_grant,
};

const AUTHORIZATION_TTL_MINUTES: i64 = 10;
const MAX_SCOPES: usize = 128;
const MAX_SECRET_TEXT_BYTES: usize = 64 * 1024;
#[cfg(not(test))]
const PROVIDER_OPERATION_TIMEOUT: Duration = Duration::from_secs(30);
#[cfg(test)]
const PROVIDER_OPERATION_TIMEOUT: Duration = Duration::from_millis(50);
const EXCHANGE_LEASE_SECONDS: i64 = 120;
const TERMINAL_RETENTION_DAYS: i64 = 30;

#[derive(Clone, Copy, Debug, Deserialize, Serialize, PartialEq, Eq)]
#[serde(rename_all = "snake_case")]
pub enum OAuthAuthorizationStatus {
    Preparing,
    Pending,
    Exchanging,
    Completed,
    Denied,
    Failed,
    Expired,
    Cancelled,
}

#[derive(Clone, Debug, Deserialize, Serialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct OAuthAuthorizationBinding {
    pub connector_id: String,
    pub account_id: String,
}

#[derive(Clone, Debug, Deserialize, Serialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct OAuthAuthorizationView {
    pub authorization_id: String,
    pub provider_id: String,
    pub connector_ids: BTreeSet<String>,
    pub requested_capabilities: BTreeSet<String>,
    pub status: OAuthAuthorizationStatus,
    pub bindings: Vec<OAuthAuthorizationBinding>,
    pub error_code: Option<String>,
    pub expires_at: DateTime<Utc>,
    pub created_at: DateTime<Utc>,
    pub updated_at: DateTime<Utc>,
}

#[derive(Clone, Deserialize, Serialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct OAuthAuthorizationStart {
    pub authorization_id: String,
    pub provider_id: String,
    pub connector_ids: BTreeSet<String>,
    pub requested_capabilities: BTreeSet<String>,
    pub status: OAuthAuthorizationStatus,
    pub expires_at: DateTime<Utc>,
    pub authorization_url: String,
    pub authorization_origin: String,
}

impl fmt::Debug for OAuthAuthorizationStart {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter
            .debug_struct("OAuthAuthorizationStart")
            .field("authorization_id", &self.authorization_id)
            .field("provider_id", &self.provider_id)
            .field("connector_ids", &self.connector_ids)
            .field("requested_capabilities", &self.requested_capabilities)
            .field("status", &self.status)
            .field("expires_at", &self.expires_at)
            .field("authorization_url", &"[REDACTED]")
            .field("authorization_origin", &self.authorization_origin)
            .finish()
    }
}

#[derive(Clone, Debug, Deserialize, Serialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct OAuthAuthorizationRequest {
    pub provider_id: String,
    pub connector_ids: BTreeSet<String>,
    pub requested_capabilities: BTreeSet<String>,
}

pub struct OAuthCallbackRequest {
    pub state: String,
    pub code: Option<OAuthSecretString>,
    pub error: Option<String>,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct OAuthAuthorizationPlan {
    pub requested_scopes: BTreeSet<String>,
    pub connector_scopes: BTreeMap<String, BTreeSet<String>>,
}

#[derive(Clone, PartialEq, Eq)]
pub struct OAuthAuthorizationUrlRequest {
    pub authorization_id: String,
    pub redirect_uri: String,
    pub state: String,
    pub pkce_challenge: String,
    pub scopes: BTreeSet<String>,
}

impl fmt::Debug for OAuthAuthorizationUrlRequest {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter
            .debug_struct("OAuthAuthorizationUrlRequest")
            .field("authorization_id", &self.authorization_id)
            .field("redirect_uri", &self.redirect_uri)
            .field("state", &"[REDACTED]")
            .field("pkce_challenge", &"[REDACTED]")
            .field("scopes", &self.scopes)
            .finish()
    }
}

pub struct OAuthCodeExchangeRequest {
    pub authorization_id: String,
    pub redirect_uri: String,
    pub code: OAuthSecretString,
    pub pkce_verifier: OAuthSecretString,
    pub requested_scopes: BTreeSet<String>,
}

impl fmt::Debug for OAuthCodeExchangeRequest {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter
            .debug_struct("OAuthCodeExchangeRequest")
            .field("authorization_id", &self.authorization_id)
            .field("redirect_uri", &self.redirect_uri)
            .field("code", &"[REDACTED]")
            .field("pkce_verifier", &"[REDACTED]")
            .field("requested_scopes", &self.requested_scopes)
            .finish()
    }
}

pub struct OAuthRefreshRequest {
    pub credential_id: String,
    pub refresh_token: OAuthSecretString,
}

impl fmt::Debug for OAuthRefreshRequest {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter
            .debug_struct("OAuthRefreshRequest")
            .field("credential_id", &self.credential_id)
            .field("refresh_token", &"[REDACTED]")
            .finish()
    }
}

pub struct OAuthTokenGrant {
    pub provider_subject: String,
    pub access_token: SecretMaterial,
    pub refresh_token: Option<SecretMaterial>,
    pub granted_scopes: BTreeSet<String>,
    pub expires_at: Option<DateTime<Utc>>,
}

pub struct OAuthSecretString(Zeroizing<String>);

impl OAuthSecretString {
    pub fn new(value: String) -> anyhow::Result<Self> {
        anyhow::ensure!(
            !value.is_empty() && value.len() <= MAX_SECRET_TEXT_BYTES,
            "OAuth secret text is invalid"
        );
        Ok(Self(Zeroizing::new(value)))
    }

    pub fn expose(&self) -> &str {
        self.0.as_str()
    }
}

impl fmt::Debug for OAuthSecretString {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter.write_str("OAuthSecretString([REDACTED])")
    }
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum OAuthProviderErrorCode {
    AuthorizationDenied,
    ExchangeFailed,
    InvalidRequest,
    PermissionInsufficient,
    RefreshFailed,
    Unavailable,
}

impl OAuthProviderErrorCode {
    fn as_str(self) -> &'static str {
        match self {
            Self::AuthorizationDenied => "authorization_denied",
            Self::ExchangeFailed => "exchange_failed",
            Self::InvalidRequest => "provider_invalid_request",
            Self::PermissionInsufficient => "permission_insufficient",
            Self::RefreshFailed => "refresh_failed",
            Self::Unavailable => "provider_unavailable",
        }
    }
}

#[derive(Clone, Copy, Debug, thiserror::Error, PartialEq, Eq)]
#[error("OAuth provider operation failed: {code:?}")]
pub struct OAuthProviderError {
    pub code: OAuthProviderErrorCode,
}

impl OAuthProviderError {
    pub fn new(code: OAuthProviderErrorCode) -> Self {
        Self { code }
    }
}

#[async_trait]
pub trait OAuthProvider: Send + Sync {
    fn provider_id(&self) -> &str;
    fn authorization_origin(&self) -> &str;
    fn authorization_plan(
        &self,
        connector_ids: &BTreeSet<String>,
        capabilities: &BTreeSet<String>,
    ) -> Result<OAuthAuthorizationPlan, OAuthProviderError>;
    fn authorization_url(
        &self,
        request: OAuthAuthorizationUrlRequest,
    ) -> Result<String, OAuthProviderError>;
    async fn exchange_code(
        &self,
        request: OAuthCodeExchangeRequest,
    ) -> Result<OAuthTokenGrant, OAuthProviderError>;
    async fn refresh_token(
        &self,
        request: OAuthRefreshRequest,
    ) -> Result<OAuthTokenGrant, OAuthProviderError>;
}

#[derive(Clone)]
pub struct OAuthBroker {
    callback_url: String,
    owner_id: String,
    providers: Arc<BTreeMap<String, Arc<dyn OAuthProvider>>>,
    refresh_lock: Arc<AsyncMutex<()>>,
    scope: CredentialScope,
    store: SqliteOAuthStore,
    vault: Arc<CredentialVault>,
}

#[derive(Clone, Debug, Deserialize, Serialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct OAuthRefreshReceipt {
    pub credential_id: String,
    pub provider_id: String,
    pub expires_at: Option<DateTime<Utc>>,
    pub granted_scopes: BTreeSet<String>,
}

impl OAuthBroker {
    pub async fn new(
        storage: &Storage,
        scope: CredentialScope,
        callback_url: impl Into<String>,
        vault: Arc<CredentialVault>,
        providers: Vec<Arc<dyn OAuthProvider>>,
    ) -> anyhow::Result<Self> {
        scope.validate()?;
        let callback_url = validate_callback_url(&callback_url.into())?;
        anyhow::ensure!(
            !providers.is_empty(),
            "at least one OAuth provider is required"
        );
        let mut registry = BTreeMap::new();
        for provider in providers {
            validate_identifier("OAuth provider", provider.provider_id())?;
            validate_authorization_origin(provider.authorization_origin())?;
            anyhow::ensure!(
                registry
                    .insert(provider.provider_id().to_string(), provider)
                    .is_none(),
                "OAuth provider IDs must be unique"
            );
        }
        if let Err(error) = vault.cleanup_pending_secret_material(&scope).await {
            tracing::warn!(error = %error, "credential secret cleanup remains pending");
        }
        let broker = Self {
            callback_url,
            owner_id: Uuid::new_v4().to_string(),
            providers: Arc::new(registry),
            refresh_lock: Arc::new(AsyncMutex::new(())),
            scope,
            store: SqliteOAuthStore::from_storage(storage).await?,
            vault,
        };
        broker.recover_interrupted(Utc::now()).await?;
        Ok(broker)
    }

    /// Creates a Host-bound view for another authenticated user without sharing account bindings.
    /// Provider registrations and the encrypted vault are shared, while every persisted OAuth
    /// state, credential and connector binding remains isolated by `CredentialScope`.
    pub async fn for_scope(&self, scope: CredentialScope) -> anyhow::Result<Self> {
        scope.validate()?;
        if let Err(error) = self.vault.cleanup_pending_secret_material(&scope).await {
            tracing::warn!(error = %error, "credential secret cleanup remains pending");
        }
        let broker = Self {
            callback_url: self.callback_url.clone(),
            owner_id: Uuid::new_v4().to_string(),
            providers: self.providers.clone(),
            refresh_lock: Arc::new(AsyncMutex::new(())),
            scope,
            store: self.store.clone(),
            vault: self.vault.clone(),
        };
        broker.recover_interrupted(Utc::now()).await?;
        Ok(broker)
    }

    pub async fn start(
        &self,
        request: OAuthAuthorizationRequest,
        now: DateTime<Utc>,
    ) -> anyhow::Result<OAuthAuthorizationStart> {
        self.cleanup_stale(now).await?;
        validate_authorization_request(&request)?;
        let provider = self
            .providers
            .get(&request.provider_id)
            .ok_or_else(|| anyhow::anyhow!("OAuth provider is unavailable"))?;
        let plan = provider
            .authorization_plan(&request.connector_ids, &request.requested_capabilities)
            .map_err(|error| anyhow::anyhow!(error.code.as_str()))?;
        validate_authorization_plan(&request.connector_ids, &plan)?;
        let authorization_id = Uuid::new_v4().to_string();
        let state_id = random_hex()?.to_string();
        let verifier = random_hex()?;
        let pkce_challenge = URL_SAFE_NO_PAD.encode(Sha256::digest(verifier.as_bytes()));
        let pkce_secret_id = SecretId::parse(&format!("oauth.pkce.{authorization_id}"))?;
        let authorization_url_request = OAuthAuthorizationUrlRequest {
            authorization_id: authorization_id.clone(),
            redirect_uri: self.callback_url.clone(),
            state: state_id.clone(),
            pkce_challenge,
            scopes: plan.requested_scopes.clone(),
        };
        let provider_url = provider
            .authorization_url(authorization_url_request.clone())
            .map_err(|error| anyhow::anyhow!(error.code.as_str()))?;
        let (authorization_url, authorization_origin) = secure_provider_authorization_url(
            &provider_url,
            provider.authorization_origin(),
            &authorization_url_request,
        )?;
        let expires_at = now + ChronoDuration::minutes(AUTHORIZATION_TTL_MINUTES);
        let session = OAuthAuthorizationSession {
            authorization_id: authorization_id.clone(),
            exchange_owner_id: Some(self.owner_id.clone()),
            credential_id: Some(format!("oauth.{}", Uuid::new_v4())),
            provider_id: request.provider_id.clone(),
            connector_ids: request.connector_ids.clone(),
            requested_capabilities: request.requested_capabilities.clone(),
            requested_scopes: plan.requested_scopes,
            connector_scopes: plan.connector_scopes,
            status: OAuthAuthorizationStatus::Preparing,
            bindings: Vec::new(),
            error_code: None,
            expires_at,
            created_at: now,
            updated_at: now,
        };
        self.store
            .create(
                &self.scope,
                &session,
                &state_id,
                &pkce_secret_id,
                &self.owner_id,
                now + ChronoDuration::seconds(EXCHANGE_LEASE_SECONDS),
            )
            .await?;
        if let Err(error) = self
            .vault
            .save_oauth_pkce_verifier(
                &self.scope,
                &pkce_secret_id,
                SecretMaterial::new(verifier.as_bytes())?,
            )
            .await
        {
            let _ = self
                .fail_and_recover(&authorization_id, "pkce_verifier_persistence_failed", now)
                .await;
            return Err(error);
        }
        if let Err(error) = self
            .store
            .activate_pending(&self.scope, &authorization_id, &self.owner_id, now)
            .await
        {
            let _ = self
                .fail_and_recover(&authorization_id, "authorization_activation_failed", now)
                .await;
            return Err(error);
        }
        Ok(OAuthAuthorizationStart {
            authorization_id,
            provider_id: request.provider_id,
            connector_ids: request.connector_ids,
            requested_capabilities: request.requested_capabilities,
            status: OAuthAuthorizationStatus::Pending,
            expires_at,
            authorization_url,
            authorization_origin,
        })
    }

    pub async fn status(
        &self,
        authorization_id: &str,
    ) -> anyhow::Result<Option<OAuthAuthorizationView>> {
        validate_identifier("OAuth authorization", authorization_id)?;
        self.cleanup_stale(Utc::now()).await?;
        Ok(self
            .store
            .get(&self.scope, authorization_id)
            .await?
            .map(OAuthAuthorizationSession::view))
    }

    pub async fn cancel(
        &self,
        authorization_id: &str,
        now: DateTime<Utc>,
    ) -> anyhow::Result<Option<OAuthAuthorizationView>> {
        validate_identifier("OAuth authorization", authorization_id)?;
        let cancelled = self
            .store
            .cancel(&self.scope, authorization_id, now)
            .await?;
        let Some((session, pkce_secret_id)) = cancelled else {
            return self.status(authorization_id).await;
        };
        self.vault
            .delete_oauth_pkce_verifier(&self.scope, &pkce_secret_id)
            .await?;
        self.store
            .delete_state(&self.scope, &session.authorization_id)
            .await?;
        Ok(Some(session.view()))
    }

    pub async fn callback(
        &self,
        request: OAuthCallbackRequest,
        now: DateTime<Utc>,
    ) -> anyhow::Result<OAuthAuthorizationView> {
        validate_callback_request(&request)?;
        let consumed = self
            .store
            .consume_state(
                &self.scope,
                &request.state,
                &self.owner_id,
                now + ChronoDuration::seconds(EXCHANGE_LEASE_SECONDS),
                now,
            )
            .await?;
        let (session, pkce_secret_id) = match consumed {
            OAuthStateConsumption::Ready {
                session,
                pkce_secret_id,
            } => (*session, pkce_secret_id),
            OAuthStateConsumption::Expired {
                authorization_id,
                pkce_secret_id,
            } => {
                self.vault
                    .delete_oauth_pkce_verifier(&self.scope, &pkce_secret_id)
                    .await?;
                self.store
                    .delete_state(&self.scope, &authorization_id)
                    .await?;
                return self
                    .status(&authorization_id)
                    .await?
                    .ok_or_else(|| anyhow::anyhow!("OAuth authorization is unavailable"));
            }
        };
        let verifier = match self
            .vault
            .consume_oauth_pkce_verifier(&self.scope, &pkce_secret_id)
            .await
        {
            Ok(verifier) => verifier,
            Err(_) => {
                return self
                    .fail_and_recover(
                        &session.authorization_id,
                        "pkce_verifier_unavailable",
                        Utc::now(),
                    )
                    .await;
            }
        };
        if let Some(error) = request.error {
            let error_code = callback_error_code(&error);
            let session = if error == "access_denied" {
                self.store
                    .mark_denied(
                        &self.scope,
                        &session.authorization_id,
                        &self.owner_id,
                        error_code,
                        now,
                    )
                    .await?
            } else {
                self.store
                    .mark_failed(
                        &self.scope,
                        &session.authorization_id,
                        &self.owner_id,
                        error_code,
                        now,
                    )
                    .await?
            };
            return Ok(session.view());
        }
        let code = request.code.expect("validated OAuth callback code");
        let verifier = match secret_utf8(&verifier) {
            Ok(verifier) => verifier,
            Err(_) => {
                return Ok(self
                    .store
                    .mark_failed(
                        &self.scope,
                        &session.authorization_id,
                        &self.owner_id,
                        "pkce_verifier_invalid",
                        now,
                    )
                    .await?
                    .view());
            }
        };
        let Some(provider) = self.providers.get(&session.provider_id) else {
            return Ok(self
                .store
                .mark_failed(
                    &self.scope,
                    &session.authorization_id,
                    &self.owner_id,
                    OAuthProviderErrorCode::Unavailable.as_str(),
                    now,
                )
                .await?
                .view());
        };
        let grant = match tokio::time::timeout(
            PROVIDER_OPERATION_TIMEOUT,
            provider.exchange_code(OAuthCodeExchangeRequest {
                authorization_id: session.authorization_id.clone(),
                redirect_uri: self.callback_url.clone(),
                code,
                pkce_verifier: verifier,
                requested_scopes: session.requested_scopes.clone(),
            }),
        )
        .await
        {
            Ok(Ok(grant)) => grant,
            Ok(Err(error)) => {
                return Ok(self
                    .store
                    .mark_failed(
                        &self.scope,
                        &session.authorization_id,
                        &self.owner_id,
                        error.code.as_str(),
                        now,
                    )
                    .await?
                    .view());
            }
            Err(_) => {
                return Ok(self
                    .store
                    .mark_failed(
                        &self.scope,
                        &session.authorization_id,
                        &self.owner_id,
                        "provider_exchange_timeout",
                        now,
                    )
                    .await?
                    .view());
            }
        };
        self.finish_exchange(session, grant, now).await
    }

    async fn finish_exchange(
        &self,
        session: OAuthAuthorizationSession,
        grant: OAuthTokenGrant,
        now: DateTime<Utc>,
    ) -> anyhow::Result<OAuthAuthorizationView> {
        if validate_token_grant(&session, &grant, now).is_err() {
            return Ok(self
                .store
                .mark_failed(
                    &self.scope,
                    &session.authorization_id,
                    &self.owner_id,
                    "permission_insufficient",
                    now,
                )
                .await?
                .view());
        }
        let credential_id = session
            .credential_id
            .clone()
            .ok_or_else(|| anyhow::anyhow!("OAuth recovery credential is unavailable"))?;
        let operation_now = Utc::now();
        if !self
            .renew_exchange(&session.authorization_id, operation_now)
            .await?
        {
            return self
                .exchange_lease_lost(&session.authorization_id, None, operation_now)
                .await;
        }
        let access_secret_id = recovery_access_secret_id(&credential_id)?;
        let refresh_secret_id = grant
            .refresh_token
            .as_ref()
            .map(|_| recovery_refresh_secret_id(&credential_id))
            .transpose()?;
        let account_id = provider_account_id(&session.provider_id, &grant.provider_subject);
        let credential = ProviderCredential {
            credential_id: credential_id.clone(),
            provider_id: session.provider_id.clone(),
            provider_subject: grant.provider_subject,
            access_secret_id,
            refresh_secret_id,
            granted_scopes: grant.granted_scopes,
            expires_at: grant.expires_at,
            revoked_at: None,
        };
        let credential_write_now = Utc::now();
        if self
            .vault
            .save_provider_credential_fenced(
                &self.scope,
                credential,
                grant.access_token,
                grant.refresh_token,
                &session.authorization_id,
                &self.owner_id,
                credential_write_now,
            )
            .await
            .is_err()
        {
            return match self
                .fail_and_recover(
                    &session.authorization_id,
                    "credential_persistence_failed",
                    Utc::now(),
                )
                .await
            {
                Ok(view) => Ok(view),
                Err(_) => {
                    self.exchange_lease_lost(
                        &session.authorization_id,
                        Some(&credential_id),
                        Utc::now(),
                    )
                    .await
                }
            };
        }
        let mut bindings: Vec<OAuthAuthorizationBinding> = Vec::new();
        for connector_id in &session.connector_ids {
            let binding_now = Utc::now();
            if !self
                .renew_exchange(&session.authorization_id, binding_now)
                .await?
            {
                return self
                    .exchange_lease_lost(
                        &session.authorization_id,
                        Some(&credential_id),
                        binding_now,
                    )
                    .await;
            }
            let allowed_scopes = session
                .connector_scopes
                .get(connector_id)
                .cloned()
                .unwrap_or_default();
            if self
                .vault
                .register_account_persistent_exclusive_fenced(
                    ConnectorAccount {
                        account_id: account_id.clone(),
                        connector_id: connector_id.clone(),
                        credential_id: credential_id.clone(),
                        scope: self.scope.clone(),
                        allowed_scopes,
                    },
                    &session.authorization_id,
                    &self.owner_id,
                    Utc::now(),
                )
                .await
                .is_err()
            {
                return match self
                    .fail_and_recover(
                        &session.authorization_id,
                        "connector_binding_failed",
                        Utc::now(),
                    )
                    .await
                {
                    Ok(view) => Ok(view),
                    Err(_) => {
                        self.exchange_lease_lost(
                            &session.authorization_id,
                            Some(&credential_id),
                            Utc::now(),
                        )
                        .await
                    }
                };
            }
            bindings.push(OAuthAuthorizationBinding {
                connector_id: connector_id.clone(),
                account_id: account_id.clone(),
            });
        }
        let completion_now = Utc::now();
        if !self
            .renew_exchange(&session.authorization_id, completion_now)
            .await?
        {
            return self
                .exchange_lease_lost(
                    &session.authorization_id,
                    Some(&credential_id),
                    completion_now,
                )
                .await;
        }
        match self
            .store
            .complete(
                &self.scope,
                &session.authorization_id,
                &self.owner_id,
                &credential_id,
                &bindings,
                completion_now,
            )
            .await
        {
            Ok(completed) => Ok(completed.view()),
            Err(error) => {
                let persisted = self
                    .store
                    .get(&self.scope, &session.authorization_id)
                    .await?;
                match persisted {
                    Some(current) if current.status == OAuthAuthorizationStatus::Completed => {
                        Ok(current.view())
                    }
                    Some(current)
                        if current.status == OAuthAuthorizationStatus::Exchanging
                            && current.exchange_owner_id.as_deref()
                                == Some(self.owner_id.as_str()) =>
                    {
                        self.fail_and_recover(
                            &session.authorization_id,
                            "authorization_persistence_failed",
                            Utc::now(),
                        )
                        .await
                    }
                    _ => self
                        .exchange_lease_lost(
                            &session.authorization_id,
                            Some(&credential_id),
                            Utc::now(),
                        )
                        .await
                        .map_err(|cleanup| {
                            cleanup.context(format!(
                                "OAuth authorization outcome is uncertain: {error}"
                            ))
                        }),
                }
            }
        }
    }

    pub async fn refresh_credential(
        &self,
        credential_id: &str,
    ) -> anyhow::Result<OAuthRefreshReceipt> {
        let _guard = self.refresh_lock.lock().await;
        validate_identifier("OAuth credential", credential_id)?;
        let current = self
            .vault
            .get_provider_credential(&self.scope, credential_id)
            .await?
            .ok_or_else(|| anyhow::anyhow!("OAuth credential is unavailable"))?;
        anyhow::ensure!(current.revoked_at.is_none(), "OAuth credential is revoked");
        let provider = self
            .providers
            .get(&current.provider_id)
            .ok_or_else(|| anyhow::anyhow!("OAuth provider is unavailable"))?;
        let retained_refresh = self
            .vault
            .lease_provider_refresh_secret(&self.scope, &current.provider_id, credential_id)
            .await?;
        let refresh_text = secret_utf8(&retained_refresh)?;
        let grant = tokio::time::timeout(
            PROVIDER_OPERATION_TIMEOUT,
            provider.refresh_token(OAuthRefreshRequest {
                credential_id: credential_id.to_string(),
                refresh_token: refresh_text,
            }),
        )
        .await
        .map_err(|_| anyhow::anyhow!("provider_refresh_timeout"))?
        .map_err(|error| anyhow::anyhow!(error.code.as_str()))?;
        validate_provider_subject(&grant.provider_subject)?;
        anyhow::ensure!(
            !grant.granted_scopes.is_empty() && grant.granted_scopes.len() <= MAX_SCOPES,
            "OAuth refresh grant is invalid"
        );
        anyhow::ensure!(
            grant
                .expires_at
                .is_none_or(|expires_at| expires_at > Utc::now()),
            "OAuth refresh grant is already expired"
        );
        anyhow::ensure!(
            grant.provider_subject == current.provider_subject,
            "OAuth refresh changed provider identity"
        );
        let access_secret_id = SecretId::parse(&format!("oauth.access.{}", Uuid::new_v4()))?;
        let refresh_secret_id = SecretId::parse(&format!("oauth.refresh.{}", Uuid::new_v4()))?;
        let refresh_secret = grant.refresh_token.or(Some(retained_refresh));
        let credential = ProviderCredential {
            credential_id: current.credential_id.clone(),
            provider_id: current.provider_id.clone(),
            provider_subject: current.provider_subject,
            access_secret_id,
            refresh_secret_id: Some(refresh_secret_id),
            granted_scopes: grant.granted_scopes.clone(),
            expires_at: grant.expires_at,
            revoked_at: None,
        };
        self.vault
            .replace_provider_credential(
                &self.scope,
                credential,
                grant.access_token,
                refresh_secret,
            )
            .await?;
        Ok(OAuthRefreshReceipt {
            credential_id: current.credential_id,
            provider_id: current.provider_id,
            expires_at: grant.expires_at,
            granted_scopes: grant.granted_scopes,
        })
    }
}

fn recovery_access_secret_id(credential_id: &str) -> anyhow::Result<SecretId> {
    SecretId::parse(&format!("{credential_id}.access"))
}

fn recovery_refresh_secret_id(credential_id: &str) -> anyhow::Result<SecretId> {
    SecretId::parse(&format!("{credential_id}.refresh"))
}

#[derive(Clone, Debug)]
pub(crate) struct OAuthAuthorizationSession {
    pub authorization_id: String,
    pub exchange_owner_id: Option<String>,
    pub credential_id: Option<String>,
    pub provider_id: String,
    pub connector_ids: BTreeSet<String>,
    pub requested_capabilities: BTreeSet<String>,
    pub requested_scopes: BTreeSet<String>,
    pub connector_scopes: BTreeMap<String, BTreeSet<String>>,
    pub status: OAuthAuthorizationStatus,
    pub bindings: Vec<OAuthAuthorizationBinding>,
    pub error_code: Option<String>,
    pub expires_at: DateTime<Utc>,
    pub created_at: DateTime<Utc>,
    pub updated_at: DateTime<Utc>,
}

impl OAuthAuthorizationSession {
    fn view(self) -> OAuthAuthorizationView {
        OAuthAuthorizationView {
            authorization_id: self.authorization_id,
            provider_id: self.provider_id,
            connector_ids: self.connector_ids,
            requested_capabilities: self.requested_capabilities,
            status: self.status,
            bindings: self.bindings,
            error_code: self.error_code,
            expires_at: self.expires_at,
            created_at: self.created_at,
            updated_at: self.updated_at,
        }
    }
}

#[cfg(test)]
#[path = "oauth_tests.rs"]
mod tests;

#[cfg(test)]
#[path = "oauth_security_tests.rs"]
mod security_tests;
