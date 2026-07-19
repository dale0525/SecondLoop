use crate::developer_control_plane::{DeveloperControlPlane, PendingAuthorization, now_unix_ms};
use agent_devkit::cloudflare::{
    CAPABILITY_D1_WRITE, CAPABILITY_WORKERS_SCRIPTS_READ, CAPABILITY_WORKERS_SCRIPTS_WRITE,
    CLOUDFLARE_PROVIDER_ID,
};
use agent_devkit::{
    BeginProviderAuthorizationRequest, CompleteProviderAuthorizationRequest, DeveloperAccount,
    DeveloperAuthorization, DevkitError, DevkitErrorCode, DevkitResult, ProviderConfiguration,
    SensitiveInputResolver, SensitiveInputStore, SensitiveValue,
};
use base64::{Engine, engine::general_purpose::URL_SAFE_NO_PAD};
use serde::{Deserialize, Serialize};
use serde_json::json;
use sha2::{Digest, Sha256};
use std::collections::{BTreeMap, BTreeSet};
use url::Url;
use uuid::Uuid;

const AUTHORIZATION_LIFETIME_MS: u64 = 10 * 60 * 1_000;
const MAX_CALLBACK_BYTES: usize = 16 * 1024;

#[derive(Clone, Debug, Deserialize)]
#[serde(
    tag = "mode",
    rename_all = "snake_case",
    rename_all_fields = "camelCase",
    deny_unknown_fields
)]
pub enum CloudflareOAuthClientSelection {
    AgentWeavePublic,
    Custom {
        client_id: String,
        scope_catalog: BTreeMap<String, String>,
    },
}

#[derive(Clone, Debug, Eq, PartialEq, Serialize)]
#[serde(rename_all = "snake_case")]
pub enum DeveloperAuthorizationPhase {
    Disconnected,
    AwaitingCallback,
    SelectAccount,
    Ready,
    Expired,
}

#[derive(Clone, Debug, Eq, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct DeveloperAuthorizationStatus {
    pub provider_id: String,
    pub phase: DeveloperAuthorizationPhase,
    pub account_id: Option<String>,
    pub expires_at_unix_ms: Option<u64>,
    pub public_oauth_client_available: bool,
}

#[derive(Clone, Debug, Eq, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct DeveloperAuthorizationStart {
    pub authorization_url: String,
    pub expires_at_unix_ms: u64,
}

#[derive(Clone, Debug, Eq, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct DeveloperAuthorizationCallbackReceipt {
    pub status: DeveloperAuthorizationStatus,
    pub accounts: Vec<DeveloperAccount>,
}

impl DeveloperControlPlane {
    pub async fn authorization_status(&self) -> DevkitResult<DeveloperAuthorizationStatus> {
        let now = now_unix_ms();
        let authorization = self.load_authorization().await?;
        let pending = self.pending_authorization.lock().await;
        let phase = match authorization.as_ref() {
            Some(authorization)
                if authorization
                    .expires_at_unix_ms()
                    .is_some_and(|expires| expires <= now) =>
            {
                DeveloperAuthorizationPhase::Expired
            }
            Some(authorization) if authorization.account_id().is_some() => {
                DeveloperAuthorizationPhase::Ready
            }
            Some(_) => DeveloperAuthorizationPhase::SelectAccount,
            None if pending
                .as_ref()
                .is_some_and(|transaction| transaction.expires_at_unix_ms > now) =>
            {
                DeveloperAuthorizationPhase::AwaitingCallback
            }
            None => DeveloperAuthorizationPhase::Disconnected,
        };
        Ok(DeveloperAuthorizationStatus {
            provider_id: CLOUDFLARE_PROVIDER_ID.into(),
            phase,
            account_id: authorization
                .as_ref()
                .and_then(DeveloperAuthorization::account_id)
                .map(str::to_owned),
            expires_at_unix_ms: authorization
                .as_ref()
                .and_then(DeveloperAuthorization::expires_at_unix_ms),
            public_oauth_client_available: self.public_oauth_client_available(),
        })
    }

    pub async fn start_authorization(
        &self,
        selection: CloudflareOAuthClientSelection,
        redirect_uri: Url,
    ) -> DevkitResult<DeveloperAuthorizationStart> {
        let _mutation = self.mutation.lock().await;
        self.clear_pending_authorization().await?;
        let configuration = self.oauth_configuration(selection, &redirect_uri)?;
        let state = random_oauth_value();
        let verifier = random_oauth_value();
        let challenge = URL_SAFE_NO_PAD.encode(Sha256::digest(verifier.as_bytes()));
        let state_handle = self
            .sensitive
            .store(
                "cloudflare/oauth/state",
                SensitiveValue::new(state.into_bytes())?,
            )
            .await?;
        let verifier_handle = match self
            .sensitive
            .store(
                "cloudflare/oauth/pkce-verifier",
                SensitiveValue::new(verifier.into_bytes())?,
            )
            .await
        {
            Ok(handle) => handle,
            Err(error) => {
                let _ = self.sensitive.delete_handle(&state_handle).await;
                return Err(error);
            }
        };
        let expires_at_unix_ms = now_unix_ms().saturating_add(AUTHORIZATION_LIFETIME_MS);
        let request = BeginProviderAuthorizationRequest {
            configuration: configuration.clone(),
            redirect_uri: redirect_uri.clone(),
            pkce_s256_challenge: challenge,
            state_handle: state_handle.clone(),
            requested_capabilities: all_deployment_capabilities(),
            expires_at_unix_ms,
        };
        let plan = match self.provider.begin_provider_authorization(request).await {
            Ok(plan) => plan,
            Err(error) => {
                let _ = self
                    .sensitive
                    .delete_handles([state_handle, verifier_handle])
                    .await;
                return Err(error);
            }
        };
        *self.pending_authorization.lock().await = Some(PendingAuthorization {
            configuration,
            redirect_uri,
            state_handle,
            verifier_handle,
            expected_catalog_revision: plan.catalog_revision,
            expected_scope_ids: plan.requested_scope_ids,
            expires_at_unix_ms,
        });
        Ok(DeveloperAuthorizationStart {
            authorization_url: plan.authorization_url.to_string(),
            expires_at_unix_ms,
        })
    }

    pub async fn complete_authorization_callback(
        &self,
        callback_url: &str,
    ) -> DevkitResult<DeveloperAuthorizationCallbackReceipt> {
        let _mutation = self.mutation.lock().await;
        let pending = self
            .pending_authorization
            .lock()
            .await
            .take()
            .ok_or_else(|| {
                DevkitError::new(
                    DevkitErrorCode::InvalidAuthorization,
                    "no Cloudflare authorization is awaiting a callback",
                )
            })?;
        let result = self
            .complete_authorization_callback_inner(callback_url, &pending)
            .await;
        let _ = self
            .sensitive
            .delete_handles([
                pending.state_handle.clone(),
                pending.verifier_handle.clone(),
            ])
            .await;
        result
    }

    async fn complete_authorization_callback_inner(
        &self,
        callback_url: &str,
        pending: &PendingAuthorization,
    ) -> DevkitResult<DeveloperAuthorizationCallbackReceipt> {
        if callback_url.is_empty() || callback_url.len() > MAX_CALLBACK_BYTES {
            return Err(invalid_callback());
        }
        if pending.expires_at_unix_ms <= now_unix_ms() {
            return Err(DevkitError::new(
                DevkitErrorCode::InvalidAuthorization,
                "Cloudflare authorization callback expired",
            ));
        }
        let callback = Url::parse(callback_url).map_err(|_| invalid_callback())?;
        if callback.scheme() != pending.redirect_uri.scheme()
            || callback.host_str() != pending.redirect_uri.host_str()
            || callback.port_or_known_default() != pending.redirect_uri.port_or_known_default()
            || callback.path() != pending.redirect_uri.path()
            || callback.fragment().is_some()
        {
            return Err(invalid_callback());
        }
        let query = unique_query(&callback)?;
        let provided_state = query.get("state").ok_or_else(invalid_callback)?;
        let expected_state = self.sensitive.resolve(&pending.state_handle).await?;
        let matches = expected_state.expose(|expected| {
            Ok(Sha256::digest(expected).as_slice()
                == Sha256::digest(provided_state.as_bytes()).as_slice())
        })?;
        if !matches {
            return Err(DevkitError::new(
                DevkitErrorCode::InvalidAuthorization,
                "Cloudflare authorization state did not match",
            ));
        }
        if query.contains_key("error") {
            return Err(DevkitError::new(
                DevkitErrorCode::InvalidAuthorization,
                "Cloudflare authorization was denied",
            ));
        }
        let code = query.get("code").ok_or_else(invalid_callback)?;
        if code.is_empty() || code.len() > 8 * 1024 || code.chars().any(char::is_control) {
            return Err(invalid_callback());
        }
        let code_handle = self
            .sensitive
            .store(
                "cloudflare/oauth/code",
                SensitiveValue::new(code.as_bytes().to_vec())?,
            )
            .await?;
        self.sensitive.begin_capture()?;
        let request = CompleteProviderAuthorizationRequest {
            configuration: pending.configuration.clone(),
            redirect_uri: pending.redirect_uri.clone(),
            code_handle: code_handle.clone(),
            pkce_verifier_handle: pending.verifier_handle.clone(),
            expected_catalog_revision: pending.expected_catalog_revision.clone(),
            expected_scope_ids: pending.expected_scope_ids.clone(),
            actor_id: "local-developer-host".into(),
            now_unix_ms: now_unix_ms(),
        };
        let completed = self.provider.complete_provider_authorization(request).await;
        let captured = self.sensitive.finish_capture()?;
        let _ = self.sensitive.delete_handle(&code_handle).await;
        let authorization = match completed {
            Ok(authorization) => authorization,
            Err(error) => {
                let _ = self.sensitive.delete_handles(captured).await;
                return Err(error);
            }
        };
        let accounts = match self
            .provider
            .list_authorization_accounts(&authorization, now_unix_ms())
            .await
        {
            Ok(accounts) => accounts,
            Err(error) => {
                let _ = self.sensitive.delete_handles(captured).await;
                return Err(error);
            }
        };
        let previous = self.load_authorization().await?;
        if let Err(error) = self.save_authorization(&authorization).await {
            let _ = self.sensitive.delete_handles(captured).await;
            return Err(error);
        }
        if let Some(previous) = previous {
            let active = authorization_handles(&authorization);
            let stale = authorization_handles(&previous)
                .into_iter()
                .filter(|handle| !active.contains(handle));
            let _ = self.sensitive.delete_handles(stale).await;
        }
        Ok(DeveloperAuthorizationCallbackReceipt {
            status: self.authorization_status().await?,
            accounts,
        })
    }

    pub async fn list_authorization_accounts(&self) -> DevkitResult<Vec<DeveloperAccount>> {
        let authorization = self.require_authorization(false).await?;
        self.provider
            .list_authorization_accounts(&authorization, now_unix_ms())
            .await
    }

    pub async fn select_authorization_account(
        &self,
        account_id: &str,
    ) -> DevkitResult<DeveloperAuthorizationStatus> {
        let _mutation = self.mutation.lock().await;
        let authorization = self.require_authorization(false).await?;
        let authorization = self
            .provider
            .bind_authorization_account(&authorization, account_id, now_unix_ms())
            .await?;
        self.save_authorization(&authorization).await?;
        self.authorization_status().await
    }

    pub async fn disconnect_authorization(&self) -> DevkitResult<DeveloperAuthorizationStatus> {
        let _mutation = self.mutation.lock().await;
        self.clear_pending_authorization().await?;
        if let Some(authorization) = self.load_authorization().await? {
            self.delete_authorization_record().await?;
            let mut handles = vec![authorization.token_handle().clone()];
            handles.extend(authorization.refresh_token_handle().cloned());
            let _ = self.sensitive.delete_handles(handles).await;
        }
        self.cached_plans.lock().await.clear();
        self.authorization_status().await
    }

    pub async fn cancel_pending_authorization(&self) -> DevkitResult<DeveloperAuthorizationStatus> {
        let _mutation = self.mutation.lock().await;
        self.clear_pending_authorization().await?;
        self.authorization_status().await
    }

    pub(super) async fn require_authorization(
        &self,
        account_required: bool,
    ) -> DevkitResult<DeveloperAuthorization> {
        let authorization = self.load_authorization().await?.ok_or_else(|| {
            DevkitError::new(
                DevkitErrorCode::InvalidAuthorization,
                "Cloudflare developer authorization is required",
            )
        })?;
        authorization.ensure_provider_usable(
            CLOUDFLARE_PROVIDER_ID,
            &all_deployment_capabilities(),
            now_unix_ms(),
        )?;
        if account_required && authorization.account_id().is_none() {
            return Err(DevkitError::new(
                DevkitErrorCode::InvalidAuthorization,
                "select a Cloudflare account before deployment",
            ));
        }
        Ok(authorization)
    }

    async fn clear_pending_authorization(&self) -> DevkitResult<()> {
        let pending = self.pending_authorization.lock().await.take();
        if let Some(pending) = pending {
            self.sensitive
                .delete_handles([pending.state_handle, pending.verifier_handle])
                .await?;
        }
        Ok(())
    }

    fn oauth_configuration(
        &self,
        selection: CloudflareOAuthClientSelection,
        redirect_uri: &Url,
    ) -> DevkitResult<ProviderConfiguration> {
        let (client_id, scope_catalog) = match selection {
            CloudflareOAuthClientSelection::AgentWeavePublic => (
                self.oauth_defaults.client_id.clone().ok_or_else(|| {
                    DevkitError::new(
                        DevkitErrorCode::Unavailable,
                        "AgentWeave public Cloudflare OAuth client is not configured",
                    )
                })?,
                self.oauth_defaults.scope_catalog.clone().ok_or_else(|| {
                    DevkitError::new(
                        DevkitErrorCode::Unavailable,
                        "AgentWeave public Cloudflare OAuth scope catalog is not configured",
                    )
                })?,
            ),
            CloudflareOAuthClientSelection::Custom {
                client_id,
                scope_catalog,
            } => (client_id, scope_catalog),
        };
        Ok(ProviderConfiguration {
            schema_version: 1,
            public: BTreeMap::from([
                ("client-id".into(), json!(client_id)),
                ("callback-uri".into(), json!(redirect_uri.as_str())),
                ("scope-catalog".into(), json!(scope_catalog)),
            ]),
            sensitive: BTreeMap::new(),
        })
    }
}

fn all_deployment_capabilities() -> BTreeSet<String> {
    BTreeSet::from([
        CAPABILITY_WORKERS_SCRIPTS_READ.into(),
        CAPABILITY_WORKERS_SCRIPTS_WRITE.into(),
        CAPABILITY_D1_WRITE.into(),
    ])
}

fn random_oauth_value() -> String {
    format!("{}{}", Uuid::new_v4().simple(), Uuid::new_v4().simple())
}

fn unique_query(url: &Url) -> DevkitResult<BTreeMap<String, String>> {
    let mut values = BTreeMap::new();
    for (name, value) in url.query_pairs() {
        if !matches!(
            name.as_ref(),
            "code" | "state" | "error" | "error_description"
        ) || values
            .insert(name.into_owned(), value.into_owned())
            .is_some()
        {
            return Err(invalid_callback());
        }
    }
    Ok(values)
}

fn invalid_callback() -> DevkitError {
    DevkitError::new(
        DevkitErrorCode::InvalidAuthorization,
        "Cloudflare authorization callback is invalid",
    )
}

fn authorization_handles(
    authorization: &DeveloperAuthorization,
) -> BTreeSet<agent_devkit::SensitiveInputHandle> {
    let mut handles = BTreeSet::from([authorization.token_handle().clone()]);
    handles.extend(authorization.refresh_token_handle().cloned());
    handles
}
