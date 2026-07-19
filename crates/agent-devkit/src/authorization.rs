use crate::{
    DevkitError, DevkitErrorCode, DevkitResult, ProviderConfiguration, SensitiveInputHandle,
};
use serde::{Deserialize, Serialize};
use std::collections::{BTreeMap, BTreeSet};
use std::fmt;
use url::Url;

/// Host-owned authorization for a developer control-plane account.
///
/// This identity is intentionally unrelated to an Agent App end-user identity.
#[derive(Clone, Deserialize, Eq, PartialEq, Serialize)]
pub struct DeveloperAuthorization {
    provider_id: String,
    actor_id: String,
    #[serde(default)]
    account_id: Option<String>,
    token_handle: SensitiveInputHandle,
    refresh_token_handle: Option<SensitiveInputHandle>,
    granted_scope_ids: BTreeSet<String>,
    logical_capabilities: BTreeSet<String>,
    authorization_revision: String,
    issued_at_unix_ms: u64,
    expires_at_unix_ms: Option<u64>,
}

impl DeveloperAuthorization {
    #[allow(clippy::too_many_arguments)]
    pub fn new(
        provider_id: impl Into<String>,
        actor_id: impl Into<String>,
        account_id: impl Into<String>,
        token_handle: SensitiveInputHandle,
        refresh_token_handle: Option<SensitiveInputHandle>,
        granted_scope_ids: BTreeSet<String>,
        logical_capabilities: BTreeSet<String>,
        authorization_revision: impl Into<String>,
        issued_at_unix_ms: u64,
        expires_at_unix_ms: Option<u64>,
    ) -> DevkitResult<Self> {
        Self::build(
            provider_id.into(),
            actor_id.into(),
            Some(account_id.into()),
            token_handle,
            refresh_token_handle,
            granted_scope_ids,
            logical_capabilities,
            authorization_revision.into(),
            issued_at_unix_ms,
            expires_at_unix_ms,
        )
    }

    #[allow(clippy::too_many_arguments)]
    pub fn new_unbound(
        provider_id: impl Into<String>,
        actor_id: impl Into<String>,
        token_handle: SensitiveInputHandle,
        refresh_token_handle: Option<SensitiveInputHandle>,
        granted_scope_ids: BTreeSet<String>,
        logical_capabilities: BTreeSet<String>,
        authorization_revision: impl Into<String>,
        issued_at_unix_ms: u64,
        expires_at_unix_ms: Option<u64>,
    ) -> DevkitResult<Self> {
        Self::build(
            provider_id.into(),
            actor_id.into(),
            None,
            token_handle,
            refresh_token_handle,
            granted_scope_ids,
            logical_capabilities,
            authorization_revision.into(),
            issued_at_unix_ms,
            expires_at_unix_ms,
        )
    }

    #[allow(clippy::too_many_arguments)]
    fn build(
        provider_id: String,
        actor_id: String,
        account_id: Option<String>,
        token_handle: SensitiveInputHandle,
        refresh_token_handle: Option<SensitiveInputHandle>,
        granted_scope_ids: BTreeSet<String>,
        logical_capabilities: BTreeSet<String>,
        authorization_revision: String,
        issued_at_unix_ms: u64,
        expires_at_unix_ms: Option<u64>,
    ) -> DevkitResult<Self> {
        let authorization = Self {
            provider_id,
            actor_id,
            account_id,
            token_handle,
            refresh_token_handle,
            granted_scope_ids,
            logical_capabilities,
            authorization_revision,
            issued_at_unix_ms,
            expires_at_unix_ms,
        };
        authorization.validate()?;
        Ok(authorization)
    }

    fn validate(&self) -> DevkitResult<()> {
        for (label, value, maximum) in [
            ("provider id", self.provider_id.as_str(), 128),
            ("actor id", self.actor_id.as_str(), 256),
            (
                "authorization revision",
                self.authorization_revision.as_str(),
                256,
            ),
        ] {
            if value.is_empty() || value.len() > maximum || value.chars().any(char::is_control) {
                return Err(DevkitError::new(
                    DevkitErrorCode::InvalidAuthorization,
                    format!("developer authorization {label} is invalid"),
                ));
            }
        }
        if self.account_id.as_deref().is_some_and(|value| {
            value.is_empty() || value.len() > 256 || value.chars().any(char::is_control)
        }) {
            return Err(DevkitError::new(
                DevkitErrorCode::InvalidAuthorization,
                "developer authorization account id is invalid",
            ));
        }
        if self.granted_scope_ids.is_empty() || self.logical_capabilities.is_empty() {
            return Err(DevkitError::new(
                DevkitErrorCode::InvalidAuthorization,
                "developer authorization contains no deployment capabilities",
            ));
        }
        if self
            .expires_at_unix_ms
            .is_some_and(|expires| expires <= self.issued_at_unix_ms)
        {
            return Err(DevkitError::new(
                DevkitErrorCode::InvalidAuthorization,
                "developer authorization expiry is invalid",
            ));
        }
        Ok(())
    }

    pub fn provider_id(&self) -> &str {
        &self.provider_id
    }

    pub fn actor_id(&self) -> &str {
        &self.actor_id
    }

    pub fn account_id(&self) -> Option<&str> {
        self.account_id.as_deref()
    }

    pub fn token_handle(&self) -> &SensitiveInputHandle {
        &self.token_handle
    }

    pub fn refresh_token_handle(&self) -> Option<&SensitiveInputHandle> {
        self.refresh_token_handle.as_ref()
    }

    pub fn granted_scope_ids(&self) -> &BTreeSet<String> {
        &self.granted_scope_ids
    }

    pub fn logical_capabilities(&self) -> &BTreeSet<String> {
        &self.logical_capabilities
    }

    pub fn authorization_revision(&self) -> &str {
        &self.authorization_revision
    }

    pub fn issued_at_unix_ms(&self) -> u64 {
        self.issued_at_unix_ms
    }

    pub fn expires_at_unix_ms(&self) -> Option<u64> {
        self.expires_at_unix_ms
    }

    pub fn ensure_usable(
        &self,
        provider_id: &str,
        account_id: &str,
        required_capabilities: &BTreeSet<String>,
        now_unix_ms: u64,
    ) -> DevkitResult<()> {
        self.ensure_provider_usable(provider_id, required_capabilities, now_unix_ms)?;
        if self.account_id.as_deref() != Some(account_id) {
            return Err(DevkitError::new(
                DevkitErrorCode::InvalidAuthorization,
                "developer authorization is bound to a different provider account",
            ));
        }
        Ok(())
    }

    pub fn ensure_provider_usable(
        &self,
        provider_id: &str,
        required_capabilities: &BTreeSet<String>,
        now_unix_ms: u64,
    ) -> DevkitResult<()> {
        if self.provider_id != provider_id {
            return Err(DevkitError::new(
                DevkitErrorCode::InvalidAuthorization,
                "developer authorization belongs to a different provider",
            ));
        }
        if self
            .expires_at_unix_ms
            .is_some_and(|expires| expires <= now_unix_ms)
        {
            return Err(DevkitError::new(
                DevkitErrorCode::InvalidAuthorization,
                "developer authorization has expired",
            ));
        }
        if self.issued_at_unix_ms > now_unix_ms.saturating_add(300_000) {
            return Err(DevkitError::new(
                DevkitErrorCode::InvalidAuthorization,
                "developer authorization issue time is in the future",
            ));
        }
        if !required_capabilities.is_subset(&self.logical_capabilities) {
            return Err(DevkitError::new(
                DevkitErrorCode::PermissionInsufficient,
                "developer authorization lacks a required deployment capability",
            ));
        }
        Ok(())
    }

    pub fn bind_account(&self, account_id: impl Into<String>) -> DevkitResult<Self> {
        let mut authorization = self.clone();
        authorization.account_id = Some(account_id.into());
        authorization.validate()?;
        Ok(authorization)
    }
}

impl fmt::Debug for DeveloperAuthorization {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter
            .debug_struct("DeveloperAuthorization")
            .field("provider_id", &self.provider_id)
            .field("actor_id", &self.actor_id)
            .field("account_id", &self.account_id)
            .field("token_handle", &"[REDACTED]")
            .field(
                "refresh_token_handle",
                &self.refresh_token_handle.as_ref().map(|_| "[REDACTED]"),
            )
            .field("granted_scope_ids", &self.granted_scope_ids)
            .field("logical_capabilities", &self.logical_capabilities)
            .field("authorization_revision", &self.authorization_revision)
            .field("issued_at_unix_ms", &self.issued_at_unix_ms)
            .field("expires_at_unix_ms", &self.expires_at_unix_ms)
            .finish()
    }
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
pub struct DeveloperAccount {
    pub provider_id: String,
    pub account_id: String,
    pub display_name: Option<String>,
}

impl DeveloperAccount {
    pub fn validate(&self) -> DevkitResult<()> {
        for (label, value, maximum) in [
            ("provider id", self.provider_id.as_str(), 128),
            ("account id", self.account_id.as_str(), 256),
        ] {
            if value.is_empty() || value.len() > maximum || value.chars().any(char::is_control) {
                return Err(DevkitError::new(
                    DevkitErrorCode::RemoteProtocol,
                    format!("developer account {label} is invalid"),
                ));
            }
        }
        if self.display_name.as_deref().is_some_and(|name| {
            name.is_empty() || name.len() > 512 || name.chars().any(char::is_control)
        }) {
            return Err(DevkitError::new(
                DevkitErrorCode::RemoteProtocol,
                "developer account display name is invalid",
            ));
        }
        Ok(())
    }
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
pub struct AuthorizationCapabilityRequirement {
    pub capability: String,
    /// Exact authoritative names accepted from the provider scope catalog.
    pub accepted_catalog_names: BTreeSet<String>,
    pub reason: String,
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
pub struct AuthorizationRequirements {
    pub provider_id: String,
    pub catalog_revision: String,
    pub scope_ids_by_capability: BTreeMap<String, BTreeSet<String>>,
    pub reasons_by_capability: BTreeMap<String, String>,
}

impl AuthorizationRequirements {
    pub fn all_scope_ids(&self) -> BTreeSet<String> {
        self.scope_ids_by_capability
            .values()
            .flat_map(|scopes| scopes.iter().cloned())
            .collect()
    }

    pub fn logical_capabilities(&self) -> BTreeSet<String> {
        self.scope_ids_by_capability.keys().cloned().collect()
    }
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
pub struct BeginProviderAuthorizationRequest {
    pub configuration: ProviderConfiguration,
    pub redirect_uri: Url,
    pub pkce_s256_challenge: String,
    pub state_handle: SensitiveInputHandle,
    pub requested_capabilities: BTreeSet<String>,
    pub expires_at_unix_ms: u64,
}

#[derive(Clone, Deserialize, Eq, PartialEq, Serialize)]
pub struct ProviderAuthorizationPlan {
    pub provider_id: String,
    pub authorization_url: Url,
    pub requested_scope_ids: BTreeSet<String>,
    pub catalog_revision: String,
    pub expires_at_unix_ms: u64,
}

impl fmt::Debug for ProviderAuthorizationPlan {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter
            .debug_struct("ProviderAuthorizationPlan")
            .field("provider_id", &self.provider_id)
            .field("authorization_origin", &self.authorization_url.origin())
            .field("requested_scope_ids", &self.requested_scope_ids)
            .field("catalog_revision", &self.catalog_revision)
            .field("expires_at_unix_ms", &self.expires_at_unix_ms)
            .finish()
    }
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
pub struct CompleteProviderAuthorizationRequest {
    pub configuration: ProviderConfiguration,
    pub redirect_uri: Url,
    pub code_handle: SensitiveInputHandle,
    pub pkce_verifier_handle: SensitiveInputHandle,
    pub expected_catalog_revision: String,
    pub expected_scope_ids: BTreeSet<String>,
    pub actor_id: String,
    pub now_unix_ms: u64,
}
