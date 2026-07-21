use async_trait::async_trait;
use chrono::{DateTime, Duration, Utc};
use serde::{Deserialize, Serialize};
use std::collections::{BTreeMap, BTreeSet};
use std::fmt;
use std::sync::{Arc, Mutex};
use uuid::Uuid;

const SECRET_STAGING_LEASE_MINUTES: i64 = 10;

#[path = "credential_persistence.rs"]
mod persistence;
#[path = "credential_provider_leases.rs"]
mod provider_leases;
#[path = "credential_status.rs"]
mod status;
#[path = "credential_validation.rs"]
mod validation;
use validation::{validate_connector_account, validate_provider_credential};

#[derive(Clone, Debug, Deserialize, Serialize, PartialEq, Eq, PartialOrd, Ord, Hash)]
#[serde(transparent)]
pub struct SecretId(String);

impl SecretId {
    pub fn parse(value: &str) -> anyhow::Result<Self> {
        anyhow::ensure!(
            !value.is_empty()
                && value.len() <= 255
                && value
                    .chars()
                    .all(|character| character.is_ascii_alphanumeric() || ".-_".contains(character)),
            "invalid opaque secret id"
        );
        Ok(Self(value.to_string()))
    }

    pub fn as_str(&self) -> &str {
        &self.0
    }
}

#[derive(Clone, Debug, Deserialize, Serialize, PartialEq, Eq, PartialOrd, Ord, Hash)]
#[serde(deny_unknown_fields)]
pub struct CredentialScope {
    pub app_id: String,
    pub tenant_id: String,
    pub user_id: String,
}

impl CredentialScope {
    pub fn validate(&self) -> anyhow::Result<()> {
        for value in [&self.app_id, &self.tenant_id, &self.user_id] {
            anyhow::ensure!(
                !value.trim().is_empty(),
                "credential scope values are required"
            );
            anyhow::ensure!(value.len() <= 255, "credential scope value is too long");
        }
        Ok(())
    }
}

pub struct SecretMaterial(Vec<u8>);

impl SecretMaterial {
    pub fn new(value: impl Into<Vec<u8>>) -> anyhow::Result<Self> {
        let value = value.into();
        anyhow::ensure!(!value.is_empty(), "secret material cannot be empty");
        anyhow::ensure!(value.len() <= 64 * 1024, "secret material is too large");
        Ok(Self(value))
    }

    pub(crate) fn expose_bytes(&self) -> &[u8] {
        &self.0
    }

    pub fn with_exposed_bytes<T>(&self, operation: impl FnOnce(&[u8]) -> T) -> T {
        operation(&self.0)
    }
}

impl fmt::Debug for SecretMaterial {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter.write_str("SecretMaterial([REDACTED])")
    }
}

impl Drop for SecretMaterial {
    fn drop(&mut self) {
        self.0.fill(0);
    }
}

#[async_trait]
pub trait SecretStore: Send + Sync {
    async fn save(
        &self,
        scope: &CredentialScope,
        secret_id: &SecretId,
        value: SecretMaterial,
    ) -> anyhow::Result<()>;
    async fn load(
        &self,
        scope: &CredentialScope,
        secret_id: &SecretId,
    ) -> anyhow::Result<Option<SecretMaterial>>;
    async fn delete(&self, scope: &CredentialScope, secret_id: &SecretId) -> anyhow::Result<bool>;
    async fn rotate(
        &self,
        scope: &CredentialScope,
        secret_id: &SecretId,
        value: SecretMaterial,
    ) -> anyhow::Result<()>;
}

#[derive(Default)]
pub struct InMemorySecretStore {
    values: Mutex<BTreeMap<(CredentialScope, SecretId), Vec<u8>>>,
}

#[async_trait]
impl SecretStore for InMemorySecretStore {
    async fn save(
        &self,
        scope: &CredentialScope,
        secret_id: &SecretId,
        value: SecretMaterial,
    ) -> anyhow::Result<()> {
        scope.validate()?;
        let mut values = self.values.lock().expect("secret store lock poisoned");
        anyhow::ensure!(
            !values.contains_key(&(scope.clone(), secret_id.clone())),
            "secret already exists"
        );
        values.insert(
            (scope.clone(), secret_id.clone()),
            value.expose_bytes().to_vec(),
        );
        Ok(())
    }

    async fn load(
        &self,
        scope: &CredentialScope,
        secret_id: &SecretId,
    ) -> anyhow::Result<Option<SecretMaterial>> {
        scope.validate()?;
        self.values
            .lock()
            .expect("secret store lock poisoned")
            .get(&(scope.clone(), secret_id.clone()))
            .cloned()
            .map(SecretMaterial::new)
            .transpose()
    }

    async fn delete(&self, scope: &CredentialScope, secret_id: &SecretId) -> anyhow::Result<bool> {
        scope.validate()?;
        let removed = self
            .values
            .lock()
            .expect("secret store lock poisoned")
            .remove(&(scope.clone(), secret_id.clone()));
        if let Some(mut value) = removed {
            value.fill(0);
            Ok(true)
        } else {
            Ok(false)
        }
    }

    async fn rotate(
        &self,
        scope: &CredentialScope,
        secret_id: &SecretId,
        value: SecretMaterial,
    ) -> anyhow::Result<()> {
        scope.validate()?;
        let mut values = self.values.lock().expect("secret store lock poisoned");
        let stored = values
            .get_mut(&(scope.clone(), secret_id.clone()))
            .ok_or_else(|| anyhow::anyhow!("secret does not exist"))?;
        stored.fill(0);
        *stored = value.expose_bytes().to_vec();
        Ok(())
    }
}

impl Drop for InMemorySecretStore {
    fn drop(&mut self) {
        if let Ok(values) = self.values.get_mut() {
            for value in values.values_mut() {
                value.fill(0);
            }
        }
    }
}

#[derive(Clone, Debug, Deserialize, Serialize, PartialEq, Eq)]
#[serde(deny_unknown_fields)]
pub struct ConnectorAccount {
    pub account_id: String,
    pub connector_id: String,
    pub credential_id: String,
    pub scope: CredentialScope,
    pub allowed_scopes: BTreeSet<String>,
}

#[derive(Clone, Debug, Deserialize, Serialize, PartialEq, Eq)]
#[serde(deny_unknown_fields)]
pub struct ProviderCredential {
    pub credential_id: String,
    pub provider_id: String,
    pub provider_subject: String,
    pub access_secret_id: SecretId,
    pub refresh_secret_id: Option<SecretId>,
    pub granted_scopes: BTreeSet<String>,
    pub expires_at: Option<DateTime<Utc>>,
    pub revoked_at: Option<DateTime<Utc>>,
}

#[derive(Clone, Debug, Deserialize, Serialize, PartialEq, Eq)]
#[serde(deny_unknown_fields)]
pub struct OAuthAuthorizationState {
    pub state_id: String,
    pub connector_id: String,
    pub account_id: String,
    pub pkce_verifier_secret_id: SecretId,
    pub redirect_uri: String,
    pub requested_scopes: BTreeSet<String>,
    pub expires_at: DateTime<Utc>,
}

type ConnectorAccountKey = (CredentialScope, String, String);
type ConnectorAccountMap = BTreeMap<ConnectorAccountKey, ConnectorAccount>;
type ProviderCredentialKey = (CredentialScope, String);
type ProviderCredentialMap = BTreeMap<ProviderCredentialKey, ProviderCredential>;

#[derive(Default)]
struct CredentialVaultState {
    accounts: ConnectorAccountMap,
    credentials: ProviderCredentialMap,
}

#[derive(Clone)]
pub struct CredentialVault {
    store: Arc<dyn SecretStore>,
    state: Arc<Mutex<CredentialVaultState>>,
    metadata: Option<crate::credential_sqlite::SqliteCredentialMetadataStore>,
}

impl CredentialVault {
    pub fn new(store: Arc<dyn SecretStore>) -> Self {
        Self {
            store,
            state: Arc::new(Mutex::new(CredentialVaultState::default())),
            metadata: None,
        }
    }

    pub fn new_persistent(
        store: Arc<dyn SecretStore>,
        metadata: crate::credential_sqlite::SqliteCredentialMetadataStore,
    ) -> Self {
        Self {
            store,
            state: Arc::new(Mutex::new(CredentialVaultState::default())),
            metadata: Some(metadata),
        }
    }

    pub fn register_provider_credential(
        &self,
        scope: &CredentialScope,
        credential: ProviderCredential,
    ) -> anyhow::Result<()> {
        scope.validate()?;
        validate_provider_credential(&credential)?;
        self.state
            .lock()
            .expect("credential vault state lock poisoned")
            .credentials
            .insert(
                (scope.clone(), credential.credential_id.clone()),
                credential,
            );
        Ok(())
    }

    pub async fn register_provider_credential_persistent(
        &self,
        scope: &CredentialScope,
        credential: ProviderCredential,
    ) -> anyhow::Result<()> {
        validate_provider_credential(&credential)?;
        scope.validate()?;
        if let Some(metadata) = &self.metadata {
            metadata.upsert_credential(scope, &credential).await?;
        }
        self.state
            .lock()
            .expect("credential vault state lock poisoned")
            .credentials
            .insert(
                (scope.clone(), credential.credential_id.clone()),
                credential,
            );
        Ok(())
    }

    pub fn register_account(&self, account: ConnectorAccount) -> anyhow::Result<()> {
        validate_connector_account(&account)?;
        let mut state = self
            .state
            .lock()
            .expect("credential vault state lock poisoned");
        let credential = state
            .credentials
            .get(&(account.scope.clone(), account.credential_id.clone()))
            .ok_or_else(|| anyhow::anyhow!("connector account credential is unavailable"))?;
        anyhow::ensure!(
            account.allowed_scopes.is_subset(&credential.granted_scopes),
            "connector account scopes exceed provider credential grant"
        );
        anyhow::ensure!(
            credential.revoked_at.is_none(),
            "connector account credential is revoked"
        );
        state.accounts.insert(
            (
                account.scope.clone(),
                account.connector_id.clone(),
                account.account_id.clone(),
            ),
            account,
        );
        Ok(())
    }

    pub async fn register_account_persistent(
        &self,
        account: ConnectorAccount,
    ) -> anyhow::Result<()> {
        validate_connector_account(&account)?;
        if let Some(metadata) = &self.metadata {
            metadata.upsert_account(&account).await?;
            self.cache_account(account);
            Ok(())
        } else {
            self.register_account(account)
        }
    }

    pub async fn register_account_persistent_exclusive(
        &self,
        account: ConnectorAccount,
    ) -> anyhow::Result<()> {
        validate_connector_account(&account)?;
        let metadata = self
            .metadata
            .as_ref()
            .ok_or_else(|| anyhow::anyhow!("persistent credential metadata is unavailable"))?;
        metadata.insert_account(&account).await?;
        self.cache_account(account);
        Ok(())
    }

    pub(crate) async fn register_account_persistent_exclusive_fenced(
        &self,
        account: ConnectorAccount,
        authorization_id: &str,
        owner_id: &str,
        now: DateTime<Utc>,
    ) -> anyhow::Result<()> {
        validate_connector_account(&account)?;
        let metadata = self
            .metadata
            .as_ref()
            .ok_or_else(|| anyhow::anyhow!("persistent credential metadata is unavailable"))?;
        metadata
            .insert_account_fenced(&account, authorization_id, owner_id, now)
            .await?;
        self.cache_account(account);
        Ok(())
    }

    fn cache_account(&self, account: ConnectorAccount) {
        self.state
            .lock()
            .expect("credential vault state lock poisoned")
            .accounts
            .insert(
                (
                    account.scope.clone(),
                    account.connector_id.clone(),
                    account.account_id.clone(),
                ),
                account,
            );
    }

    pub async fn list_connector_accounts(
        &self,
        scope: &CredentialScope,
        connector_id: Option<&str>,
    ) -> anyhow::Result<Vec<ConnectorAccount>> {
        scope.validate()?;
        if let Some(metadata) = &self.metadata {
            return metadata.list_accounts(scope, connector_id).await;
        }
        let mut accounts = self
            .state
            .lock()
            .expect("credential vault state lock poisoned")
            .accounts
            .values()
            .filter(|account| {
                account.scope == *scope
                    && connector_id.is_none_or(|expected| account.connector_id == expected)
            })
            .cloned()
            .collect::<Vec<_>>();
        accounts.sort_by(|left, right| {
            (&left.connector_id, &left.account_id).cmp(&(&right.connector_id, &right.account_id))
        });
        Ok(accounts)
    }

    pub async fn begin_oauth_authorization(
        &self,
        scope: &CredentialScope,
        state: OAuthAuthorizationState,
        pkce_verifier: SecretMaterial,
    ) -> anyhow::Result<()> {
        scope.validate()?;
        anyhow::ensure!(
            state.expires_at > Utc::now(),
            "OAuth state is already expired"
        );
        let metadata = self
            .metadata
            .as_ref()
            .ok_or_else(|| anyhow::anyhow!("persistent credential metadata is unavailable"))?;
        self.store
            .save(scope, &state.pkce_verifier_secret_id, pkce_verifier)
            .await?;
        if let Err(error) = metadata.save_oauth_state(scope, &state).await {
            let _ = self
                .store
                .delete(scope, &state.pkce_verifier_secret_id)
                .await;
            return Err(error);
        }
        Ok(())
    }

    pub async fn consume_oauth_authorization(
        &self,
        scope: &CredentialScope,
        state_id: &str,
        now: DateTime<Utc>,
    ) -> anyhow::Result<(OAuthAuthorizationState, SecretMaterial)> {
        let metadata = self
            .metadata
            .as_ref()
            .ok_or_else(|| anyhow::anyhow!("persistent credential metadata is unavailable"))?;
        let state = metadata.consume_oauth_state(scope, state_id, now).await?;
        let verifier = self
            .store
            .load(scope, &state.pkce_verifier_secret_id)
            .await?
            .ok_or_else(|| anyhow::anyhow!("OAuth PKCE verifier is unavailable"))?;
        self.store
            .delete(scope, &state.pkce_verifier_secret_id)
            .await?;
        Ok((state, verifier))
    }

    pub async fn save_oauth_pkce_verifier(
        &self,
        scope: &CredentialScope,
        secret_id: &SecretId,
        verifier: SecretMaterial,
    ) -> anyhow::Result<()> {
        scope.validate()?;
        self.store.save(scope, secret_id, verifier).await
    }

    pub async fn consume_oauth_pkce_verifier(
        &self,
        scope: &CredentialScope,
        secret_id: &SecretId,
    ) -> anyhow::Result<SecretMaterial> {
        scope.validate()?;
        let verifier = self
            .store
            .load(scope, secret_id)
            .await?
            .ok_or_else(|| anyhow::anyhow!("OAuth PKCE verifier is unavailable"))?;
        self.store.delete(scope, secret_id).await?;
        Ok(verifier)
    }

    pub async fn delete_oauth_pkce_verifier(
        &self,
        scope: &CredentialScope,
        secret_id: &SecretId,
    ) -> anyhow::Result<bool> {
        scope.validate()?;
        self.store.delete(scope, secret_id).await
    }

    pub(crate) async fn delete_secret_material(
        &self,
        scope: &CredentialScope,
        secret_id: &SecretId,
    ) -> anyhow::Result<bool> {
        scope.validate()?;
        self.store.delete(scope, secret_id).await
    }

    pub(crate) async fn cleanup_pending_secret_material(
        &self,
        scope: &CredentialScope,
    ) -> anyhow::Result<()> {
        scope.validate()?;
        let metadata = self
            .metadata
            .as_ref()
            .ok_or_else(|| anyhow::anyhow!("persistent credential metadata is unavailable"))?;
        for secret_id in metadata.pending_secret_cleanup(scope).await? {
            self.store.delete(scope, &secret_id).await?;
            metadata.complete_secret_cleanup(scope, &secret_id).await?;
        }
        Ok(())
    }

    pub async fn save_provider_credential(
        &self,
        scope: &CredentialScope,
        credential: ProviderCredential,
        access_secret: SecretMaterial,
        refresh_secret: Option<SecretMaterial>,
    ) -> anyhow::Result<()> {
        self.save_provider_credential_inner(scope, credential, access_secret, refresh_secret, None)
            .await
    }

    #[allow(clippy::too_many_arguments)]
    pub(crate) async fn save_provider_credential_fenced(
        &self,
        scope: &CredentialScope,
        credential: ProviderCredential,
        access_secret: SecretMaterial,
        refresh_secret: Option<SecretMaterial>,
        authorization_id: &str,
        owner_id: &str,
        now: DateTime<Utc>,
    ) -> anyhow::Result<()> {
        self.save_provider_credential_inner(
            scope,
            credential,
            access_secret,
            refresh_secret,
            Some((authorization_id, owner_id, now)),
        )
        .await
    }

    async fn save_provider_credential_inner(
        &self,
        scope: &CredentialScope,
        credential: ProviderCredential,
        access_secret: SecretMaterial,
        refresh_secret: Option<SecretMaterial>,
        fence: Option<(&str, &str, DateTime<Utc>)>,
    ) -> anyhow::Result<()> {
        scope.validate()?;
        validate_provider_credential(&credential)?;
        anyhow::ensure!(
            credential.refresh_secret_id.is_some() == refresh_secret.is_some(),
            "refresh secret metadata and material must be provided together"
        );
        let metadata = self
            .metadata
            .as_ref()
            .ok_or_else(|| anyhow::anyhow!("persistent credential metadata is unavailable"))?;
        let mut staged = vec![credential.access_secret_id.clone()];
        if let Some(secret_id) = &credential.refresh_secret_id {
            staged.push(secret_id.clone());
        }
        let operation_id = format!("credential-save-{}", Uuid::new_v4());
        metadata
            .stage_secret_cleanup(
                scope,
                &staged,
                &operation_id,
                Utc::now() + Duration::minutes(SECRET_STAGING_LEASE_MINUTES),
            )
            .await?;
        if let Err(error) = self
            .save_provider_secret(scope, &credential.access_secret_id, access_secret)
            .await
        {
            self.abandon_provider_secret_staging(scope, metadata, &staged, &operation_id)
                .await;
            return Err(error);
        }
        if let (Some(secret_id), Some(secret)) = (&credential.refresh_secret_id, refresh_secret)
            && let Err(error) = self.save_provider_secret(scope, secret_id, secret).await
        {
            self.abandon_provider_secret_staging(scope, metadata, &staged, &operation_id)
                .await;
            return Err(error);
        }
        let activation = match fence {
            Some((authorization_id, owner_id, now)) => {
                metadata
                    .activate_credential_fenced(
                        scope,
                        &credential,
                        &operation_id,
                        authorization_id,
                        owner_id,
                        std::cmp::max(Utc::now(), now),
                    )
                    .await
            }
            None => {
                metadata
                    .activate_credential(scope, &credential, &operation_id, Utc::now())
                    .await
            }
        };
        if let Err(error) = activation {
            self.abandon_provider_secret_staging(scope, metadata, &staged, &operation_id)
                .await;
            return Err(error);
        }
        self.state
            .lock()
            .expect("credential vault state lock poisoned")
            .credentials
            .insert(
                (scope.clone(), credential.credential_id.clone()),
                credential,
            );
        Ok(())
    }

    pub async fn replace_provider_credential(
        &self,
        scope: &CredentialScope,
        credential: ProviderCredential,
        access_secret: SecretMaterial,
        refresh_secret: Option<SecretMaterial>,
    ) -> anyhow::Result<()> {
        scope.validate()?;
        validate_provider_credential(&credential)?;
        anyhow::ensure!(
            credential.refresh_secret_id.is_some() == refresh_secret.is_some(),
            "refresh secret metadata and material must be provided together"
        );
        let current = self
            .get_provider_credential(scope, &credential.credential_id)
            .await?
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
        for account in self.list_connector_accounts(scope, None).await? {
            if account.credential_id == credential.credential_id {
                anyhow::ensure!(
                    account.allowed_scopes.is_subset(&credential.granted_scopes),
                    "rotated provider grant no longer covers a Connector binding"
                );
            }
        }
        let metadata = self
            .metadata
            .as_ref()
            .ok_or_else(|| anyhow::anyhow!("persistent credential metadata is unavailable"))?;
        let mut staged = vec![credential.access_secret_id.clone()];
        if let Some(secret_id) = &credential.refresh_secret_id {
            staged.push(secret_id.clone());
        }
        let operation_id = format!("credential-rotate-{}", Uuid::new_v4());
        metadata
            .stage_secret_cleanup(
                scope,
                &staged,
                &operation_id,
                Utc::now() + Duration::minutes(SECRET_STAGING_LEASE_MINUTES),
            )
            .await?;
        if let Err(error) = self
            .save_provider_secret(scope, &credential.access_secret_id, access_secret)
            .await
        {
            self.abandon_provider_secret_staging(scope, metadata, &staged, &operation_id)
                .await;
            return Err(error);
        }
        if let (Some(secret_id), Some(secret)) = (&credential.refresh_secret_id, refresh_secret)
            && let Err(error) = self.save_provider_secret(scope, secret_id, secret).await
        {
            self.abandon_provider_secret_staging(scope, metadata, &staged, &operation_id)
                .await;
            return Err(error);
        }
        if let Err(error) = metadata
            .replace_credential_transactional(scope, &credential, &operation_id, Utc::now())
            .await
        {
            self.abandon_provider_secret_staging(scope, metadata, &staged, &operation_id)
                .await;
            return Err(error);
        }
        self.state
            .lock()
            .expect("credential vault state lock poisoned")
            .credentials
            .insert(
                (scope.clone(), credential.credential_id.clone()),
                credential,
            );
        if let Err(error) = self.cleanup_pending_secret_material(scope).await {
            tracing::warn!(error = %error, "credential secret cleanup remains pending");
        }
        Ok(())
    }

    pub async fn remove_connector_account(
        &self,
        scope: &CredentialScope,
        connector_id: &str,
        account_id: &str,
    ) -> anyhow::Result<Option<(String, u64)>> {
        scope.validate()?;
        if let Some(metadata) = &self.metadata {
            let removed = metadata
                .delete_account(scope, connector_id, account_id)
                .await?;
            let Some(account) = removed else {
                return Ok(None);
            };
            self.state
                .lock()
                .expect("credential vault state lock poisoned")
                .accounts
                .remove(&(
                    scope.clone(),
                    connector_id.to_string(),
                    account_id.to_string(),
                ));
            let remaining = metadata
                .count_credential_bindings(scope, &account.credential_id)
                .await?;
            Ok(Some((account.credential_id, remaining)))
        } else {
            let mut state = self
                .state
                .lock()
                .expect("credential vault state lock poisoned");
            let removed = state.accounts.remove(&(
                scope.clone(),
                connector_id.to_string(),
                account_id.to_string(),
            ));
            let Some(account) = removed else {
                return Ok(None);
            };
            let remaining = state
                .accounts
                .values()
                .filter(|candidate| {
                    candidate.scope == *scope && candidate.credential_id == account.credential_id
                })
                .count() as u64;
            Ok(Some((account.credential_id, remaining)))
        }
    }

    pub async fn revoke_provider_credential(
        &self,
        scope: &CredentialScope,
        credential_id: &str,
        now: DateTime<Utc>,
    ) -> anyhow::Result<bool> {
        scope.validate()?;
        if let Some(metadata) = &self.metadata {
            let Some(_credential) = metadata
                .revoke_credential_if_unbound(scope, credential_id, now)
                .await?
            else {
                return Ok(false);
            };
            self.state
                .lock()
                .expect("credential vault state lock poisoned")
                .credentials
                .remove(&(scope.clone(), credential_id.to_string()));
            self.cleanup_pending_secret_material(scope).await?;
            return Ok(true);
        }
        let credential = {
            let state = self
                .state
                .lock()
                .expect("credential vault state lock poisoned");
            anyhow::ensure!(
                !state.accounts.values().any(|account| {
                    account.scope == *scope && account.credential_id == credential_id
                }),
                "provider credential is still bound to a connector"
            );
            let Some(credential) = state
                .credentials
                .get(&(scope.clone(), credential_id.to_string()))
                .cloned()
            else {
                return Ok(false);
            };
            if credential.revoked_at.is_some() {
                return Ok(false);
            }
            credential
        };
        self.store
            .delete(scope, &credential.access_secret_id)
            .await?;
        if let Some(secret_id) = &credential.refresh_secret_id {
            self.store.delete(scope, secret_id).await?;
        }
        self.state
            .lock()
            .expect("credential vault state lock poisoned")
            .credentials
            .remove(&(scope.clone(), credential_id.to_string()));
        Ok(true)
    }

    pub async fn lease_for_connector(
        &self,
        scope: &CredentialScope,
        connector_id: &str,
        account_id: &str,
        required_scopes: &BTreeSet<String>,
    ) -> anyhow::Result<SecretMaterial> {
        let (account, cached_credential) = {
            let state = self
                .state
                .lock()
                .expect("credential vault state lock poisoned");
            let account = state
                .accounts
                .get(&(
                    scope.clone(),
                    connector_id.to_string(),
                    account_id.to_string(),
                ))
                .cloned();
            let credential = account.as_ref().and_then(|account| {
                state
                    .credentials
                    .get(&(scope.clone(), account.credential_id.clone()))
                    .cloned()
            });
            (account, credential)
        };
        let account = match account {
            Some(account) => account,
            None => self
                .metadata
                .as_ref()
                .ok_or_else(|| anyhow::anyhow!("connector account is unavailable"))?
                .get_account(scope, connector_id, account_id)
                .await?
                .ok_or_else(|| anyhow::anyhow!("connector account is unavailable"))?,
        };
        anyhow::ensure!(
            required_scopes.is_subset(&account.allowed_scopes),
            "connector account lacks required scopes"
        );
        let credential = match cached_credential {
            Some(credential) => credential,
            None => self
                .get_provider_credential(scope, &account.credential_id)
                .await?
                .ok_or_else(|| anyhow::anyhow!("provider credential is unavailable"))?,
        };
        anyhow::ensure!(
            required_scopes.is_subset(&credential.granted_scopes),
            "provider credential lacks required scopes"
        );
        anyhow::ensure!(
            credential.revoked_at.is_none(),
            "provider credential is revoked"
        );
        anyhow::ensure!(
            credential
                .expires_at
                .is_none_or(|expiry| expiry > Utc::now()),
            "provider credential authorization expired"
        );
        self.store
            .load(scope, &credential.access_secret_id)
            .await?
            .ok_or_else(|| anyhow::anyhow!("connector credential is unavailable"))
    }

    pub async fn get_connector_account(
        &self,
        scope: &CredentialScope,
        connector_id: &str,
        account_id: &str,
    ) -> anyhow::Result<Option<ConnectorAccount>> {
        scope.validate()?;
        if let Some(account) = self
            .state
            .lock()
            .expect("credential vault state lock poisoned")
            .accounts
            .get(&(
                scope.clone(),
                connector_id.to_string(),
                account_id.to_string(),
            ))
            .cloned()
        {
            return Ok(Some(account));
        }
        match &self.metadata {
            Some(metadata) => metadata.get_account(scope, connector_id, account_id).await,
            None => Ok(None),
        }
    }

    pub async fn get_provider_credential(
        &self,
        scope: &CredentialScope,
        credential_id: &str,
    ) -> anyhow::Result<Option<ProviderCredential>> {
        if let Some(credential) = self
            .state
            .lock()
            .expect("credential vault state lock poisoned")
            .credentials
            .get(&(scope.clone(), credential_id.to_string()))
            .cloned()
        {
            return Ok(Some(credential));
        }
        match &self.metadata {
            Some(metadata) => metadata.get_credential(scope, credential_id).await,
            None => Ok(None),
        }
    }
}

#[cfg(test)]
#[path = "credential_tests.rs"]
mod tests;
