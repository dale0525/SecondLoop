use crate::{
    config::{
        DiscoveryDocument, OidcPreset, OidcPresetId, OidcPublicConfig, ResourceParameter,
        oidc_preset,
    },
    error::{OidcError, Result},
    jwt::validate_id_token,
    secret::SecretValue,
    store::{
        AuthorizationTransaction, OidcSecretStore, SecretStoreError, SessionBinding, SessionLease,
        SessionMetadata, SessionSecrets, StateDigest, StoredSession,
    },
    transport::{OidcHttpClient, OidcHttpRequest, OidcHttpResponse},
};
use agent_runtime::identity::{
    IdentityProvider, IdentityProviderError, PrincipalIdentity, SECURITY_CONTEXT_SCHEMA_VERSION,
    SecurityContext, SecurityContextRequest,
};
use async_trait::async_trait;
use base64::{Engine, engine::general_purpose::URL_SAFE_NO_PAD};
use chrono::{DateTime, Duration, Utc};
use serde::{Deserialize, Deserializer};
use sha2::{Digest, Sha256};
use std::{collections::BTreeSet, fmt, sync::Arc};
use url::Url;
use zeroize::Zeroizing;

const AUTHORIZATION_LIFETIME_MINUTES: i64 = 10;
const MAX_TOKEN_BYTES: usize = 64 * 1024;
const MAX_TOKEN_LIFETIME_SECONDS: u64 = 31 * 24 * 60 * 60;
const MAX_HTTP_BODY_BYTES: usize = 1024 * 1024;

pub trait OidcClock: Send + Sync {
    fn now(&self) -> DateTime<Utc>;
}

#[derive(Default)]
pub struct SystemOidcClock;

impl OidcClock for SystemOidcClock {
    fn now(&self) -> DateTime<Utc> {
        Utc::now()
    }
}

pub trait SecureRandom: Send + Sync {
    fn fill(&self, destination: &mut [u8]) -> Result<()>;
}

#[derive(Default)]
pub struct OsSecureRandom;

impl SecureRandom for OsSecureRandom {
    fn fill(&self, destination: &mut [u8]) -> Result<()> {
        getrandom::fill(destination).map_err(|_| OidcError::Unavailable)
    }
}

/// Browser request containing short-lived state and nonce values. Its debug
/// representation never prints the query string.
pub struct AuthorizationRequest {
    url: Url,
    expires_at: DateTime<Utc>,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum AuthorizationPrompt {
    SelectAccount,
}

impl AuthorizationPrompt {
    fn as_str(self) -> &'static str {
        match self {
            Self::SelectAccount => "select_account",
        }
    }
}

impl AuthorizationRequest {
    pub fn url(&self) -> &Url {
        &self.url
    }

    pub fn expires_at(&self) -> DateTime<Utc> {
        self.expires_at
    }
}

impl fmt::Debug for AuthorizationRequest {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter
            .debug_struct("AuthorizationRequest")
            .field("origin", &self.url.origin().ascii_serialization())
            .field("path", &self.url.path())
            .field("query", &"[REDACTED]")
            .field("expires_at", &self.expires_at)
            .finish()
    }
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum RemoteRevocation {
    NotSupported,
    Succeeded,
    Failed,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct LogoutOutcome {
    pub end_session_url: Option<Url>,
    pub remote_revocation: RemoteRevocation,
}

struct AuthorizationCallback {
    code: SecretValue,
    state: SecretValue,
}

#[derive(Deserialize)]
struct TokenEndpointResponse {
    #[serde(deserialize_with = "deserialize_secret")]
    access_token: SecretValue,
    token_type: String,
    expires_in: u64,
    #[serde(default, deserialize_with = "deserialize_optional_secret")]
    refresh_token: Option<SecretValue>,
    #[serde(default, deserialize_with = "deserialize_optional_secret")]
    id_token: Option<SecretValue>,
    #[serde(default)]
    scope: Option<String>,
}

pub struct GenericOidcProvider {
    provider_id: String,
    config: OidcPublicConfig,
    preset: &'static OidcPreset,
    discovery: DiscoveryDocument,
    http: Arc<dyn OidcHttpClient>,
    store: Arc<dyn OidcSecretStore>,
    clock: Arc<dyn OidcClock>,
    random: Arc<dyn SecureRandom>,
}

impl GenericOidcProvider {
    pub async fn discover(
        provider_id: impl Into<String>,
        config: OidcPublicConfig,
        preset_id: OidcPresetId,
        http: Arc<dyn OidcHttpClient>,
        store: Arc<dyn OidcSecretStore>,
    ) -> Result<Self> {
        Self::discover_with(
            provider_id,
            config,
            preset_id,
            http,
            store,
            Arc::new(SystemOidcClock),
            Arc::new(OsSecureRandom),
        )
        .await
    }

    pub async fn discover_with(
        provider_id: impl Into<String>,
        config: OidcPublicConfig,
        preset_id: OidcPresetId,
        http: Arc<dyn OidcHttpClient>,
        store: Arc<dyn OidcSecretStore>,
        clock: Arc<dyn OidcClock>,
        random: Arc<dyn SecureRandom>,
    ) -> Result<Self> {
        let provider_id = provider_id.into();
        validate_identifier(&provider_id)?;
        let preset = oidc_preset(preset_id);
        config.validate_for_preset(preset)?;
        let discovery_url = config.discovery_url()?;
        let response = send_pinned(&*http, OidcHttpRequest::get(discovery_url.clone())).await?;
        if response.status() != 200 {
            return Err(OidcError::Unavailable);
        }
        let discovery: DiscoveryDocument = serde_json::from_slice(response.body())
            .map_err(|_| OidcError::InvalidProviderResponse)?;
        discovery.validate(&config, preset)?;
        Ok(Self {
            provider_id,
            config,
            preset,
            discovery,
            http,
            store,
            clock,
            random,
        })
    }

    pub fn public_config(&self) -> &OidcPublicConfig {
        &self.config
    }

    pub fn preset(&self) -> &'static OidcPreset {
        self.preset
    }

    pub async fn begin_authorization(
        &self,
        request: &SecurityContextRequest,
    ) -> Result<AuthorizationRequest> {
        self.begin_authorization_with_prompt(request, None).await
    }

    pub async fn begin_authorization_with_prompt(
        &self,
        request: &SecurityContextRequest,
        prompt: Option<AuthorizationPrompt>,
    ) -> Result<AuthorizationRequest> {
        self.validate_request(request)?;
        let now = self.clock.now();
        let state = self.random_secret(32)?;
        let nonce = self.random_secret(32)?;
        let verifier = self.random_secret(64)?;
        let challenge = URL_SAFE_NO_PAD.encode(Sha256::digest(verifier.expose_secret().as_bytes()));
        let state_digest = digest_state(state.expose_secret());
        let expires_at = now + Duration::minutes(AUTHORIZATION_LIFETIME_MINUTES);
        let transaction = AuthorizationTransaction {
            binding: self.binding(request),
            code_verifier: verifier,
            nonce: nonce.clone(),
            requested_scopes: self.config.scopes.clone(),
            expires_at,
        };
        self.store
            .insert_authorization(state_digest, transaction)
            .await
            .map_err(map_store_error)?;

        let mut url = self.discovery.authorization_endpoint.clone();
        {
            let mut query = url.query_pairs_mut();
            query
                .append_pair("response_type", "code")
                .append_pair("client_id", &self.config.client_id)
                .append_pair("redirect_uri", self.config.redirect_uri.as_str())
                .append_pair(
                    "scope",
                    &self
                        .config
                        .scopes
                        .iter()
                        .cloned()
                        .collect::<Vec<_>>()
                        .join(" "),
                )
                .append_pair("state", state.expose_secret())
                .append_pair("nonce", nonce.expose_secret())
                .append_pair("code_challenge", &challenge)
                .append_pair("code_challenge_method", "S256");
            match self.preset.resource_parameter {
                ResourceParameter::AuthorizationAudience => {
                    query.append_pair("audience", &self.config.audience);
                }
                ResourceParameter::Rfc8707AuthorizationAndToken => {
                    query.append_pair("resource", &self.config.audience);
                }
                ResourceParameter::None => {}
            }
            if let Some(prompt) = prompt {
                query.append_pair("prompt", prompt.as_str());
            }
        }
        Ok(AuthorizationRequest { url, expires_at })
    }

    pub async fn complete_authorization_url(&self, callback_url: &Url) -> Result<SecurityContext> {
        let callback = self.parse_callback(callback_url)?;
        let state_digest = digest_state(callback.state.expose_secret());
        let transaction = self
            .store
            .take_authorization(&state_digest, self.clock.now())
            .await
            .map_err(map_store_error)?
            .ok_or(OidcError::InvalidAuthorization)?;
        let response = self
            .exchange_authorization_code(&callback.code, &transaction.code_verifier)
            .await?;
        let session = self
            .session_from_authorization_response(response, &transaction)
            .await?;
        let context = self.context(&transaction.binding, &session.metadata)?;
        self.store
            .put_session(transaction.binding, session)
            .await
            .map_err(map_store_error)?;
        Ok(context)
    }

    pub async fn refresh(&self, request: &SecurityContextRequest) -> Result<SecurityContext> {
        self.validate_request(request)?;
        let binding = self.binding(request);
        let lease = self
            .store
            .lease_session(&binding)
            .await
            .map_err(map_store_error)?
            .ok_or(OidcError::AuthenticationRequired)?;
        let replacement = self.refresh_replacement(&lease).await;
        match replacement {
            Ok(session) => {
                let context = self
                    .context(&binding, &session.metadata)
                    .and_then(|context| {
                        context
                            .validate_for(&self.provider_id, request, self.clock.now())
                            .map_err(|_| OidcError::InvalidProviderResponse)?;
                        Ok(context)
                    });
                let context = match context {
                    Ok(context) => context,
                    Err(error) => {
                        self.store
                            .release_session(lease)
                            .await
                            .map_err(map_store_error)?;
                        return Err(error);
                    }
                };
                self.store
                    .commit_session(lease, session)
                    .await
                    .map_err(map_store_error)?;
                Ok(context)
            }
            Err(error) => {
                if error == OidcError::AccessDenied {
                    self.store
                        .delete_leased_session(lease)
                        .await
                        .map_err(map_store_error)?;
                } else {
                    self.store
                        .release_session(lease)
                        .await
                        .map_err(map_store_error)?;
                }
                Err(error)
            }
        }
    }

    /// Returns a short-lived host-only assertion for the configured gateway audience.
    /// The value is zeroized on drop and has no serialization implementation.
    pub async fn access_assertion(&self, request: &SecurityContextRequest) -> Result<SecretValue> {
        <Self as IdentityProvider>::security_context(self, request)
            .await
            .map_err(OidcError::from)?;
        let lease = self
            .store
            .lease_session(&self.binding(request))
            .await
            .map_err(map_store_error)?
            .ok_or(OidcError::AuthenticationRequired)?;
        let assertion = lease.session.secrets.access_token().clone();
        self.store
            .release_session(lease)
            .await
            .map_err(map_store_error)?;
        Ok(assertion)
    }

    pub async fn revoke(&self, request: &SecurityContextRequest) -> Result<LogoutOutcome> {
        self.terminate(request, false).await
    }

    pub async fn logout(&self, request: &SecurityContextRequest) -> Result<LogoutOutcome> {
        self.terminate(request, true).await
    }

    async fn terminate(
        &self,
        request: &SecurityContextRequest,
        include_end_session: bool,
    ) -> Result<LogoutOutcome> {
        self.validate_request(request)?;
        let Some(lease) = self
            .store
            .lease_session(&self.binding(request))
            .await
            .map_err(map_store_error)?
        else {
            return Ok(LogoutOutcome {
                end_session_url: None,
                remote_revocation: RemoteRevocation::NotSupported,
            });
        };
        let remote_revocation = self.revoke_remote(&lease).await;
        let end_session_url = include_end_session
            .then(|| self.end_session_url())
            .flatten();
        self.store
            .delete_leased_session(lease)
            .await
            .map_err(map_store_error)?;
        Ok(LogoutOutcome {
            end_session_url,
            remote_revocation,
        })
    }

    fn parse_callback(&self, callback_url: &Url) -> Result<AuthorizationCallback> {
        if callback_url.fragment().is_some() {
            return Err(OidcError::InvalidAuthorization);
        }
        let mut base = callback_url.clone();
        base.set_query(None);
        if base != self.config.redirect_uri {
            return Err(OidcError::InvalidAuthorization);
        }
        let mut code = None;
        let mut state = None;
        let mut issuer = None;
        let mut denied = false;
        for (name, value) in callback_url.query_pairs() {
            match name.as_ref() {
                "code" if code.is_none() => code = Some(value.into_owned()),
                "state" if state.is_none() => state = Some(value.into_owned()),
                "iss" if issuer.is_none() => issuer = Some(value.into_owned()),
                "error" => denied = true,
                "session_state" | "error_description" | "error_uri" => {}
                _ => return Err(OidcError::InvalidAuthorization),
            }
        }
        if denied {
            return Err(OidcError::AccessDenied);
        }
        if issuer
            .as_deref()
            .is_some_and(|value| value != self.discovery.issuer.as_str())
        {
            return Err(OidcError::InvalidAuthorization);
        }
        let code = code.ok_or(OidcError::InvalidAuthorization)?;
        let state = state.ok_or(OidcError::InvalidAuthorization)?;
        if !valid_secret_text(&code) || !valid_secret_text(&state) {
            return Err(OidcError::InvalidAuthorization);
        }
        Ok(AuthorizationCallback {
            code: SecretValue::new(code),
            state: SecretValue::new(state),
        })
    }

    async fn exchange_authorization_code(
        &self,
        code: &SecretValue,
        verifier: &SecretValue,
    ) -> Result<TokenEndpointResponse> {
        let mut form = vec![
            ("grant_type", SecretValue::new("authorization_code")),
            ("code", code.clone()),
            ("client_id", SecretValue::new(&self.config.client_id)),
            (
                "redirect_uri",
                SecretValue::new(self.config.redirect_uri.as_str()),
            ),
            ("code_verifier", verifier.clone()),
        ];
        self.add_token_resource(&mut form);
        self.exchange_token(form).await
    }

    async fn refresh_replacement(&self, lease: &SessionLease) -> Result<StoredSession> {
        let refresh_token = lease
            .session
            .secrets
            .refresh_token()
            .ok_or(OidcError::AuthenticationRequired)?;
        let mut form = vec![
            ("grant_type", SecretValue::new("refresh_token")),
            ("refresh_token", refresh_token.clone()),
            ("client_id", SecretValue::new(&self.config.client_id)),
        ];
        self.add_token_resource(&mut form);
        let response = self.exchange_token(form).await?;
        self.session_from_refresh_response(response, &lease.session)
            .await
    }

    async fn exchange_token(
        &self,
        form: Vec<(&'static str, SecretValue)>,
    ) -> Result<TokenEndpointResponse> {
        let request = OidcHttpRequest::post_form(self.discovery.token_endpoint.clone(), form);
        let response = send_pinned(&*self.http, request).await?;
        if response.status() == 400 || response.status() == 401 || response.status() == 403 {
            return Err(OidcError::AccessDenied);
        }
        if response.status() != 200 {
            return Err(OidcError::Unavailable);
        }
        let token: TokenEndpointResponse = serde_json::from_slice(response.body())
            .map_err(|_| OidcError::InvalidProviderResponse)?;
        validate_token_response(&token)?;
        Ok(token)
    }

    async fn session_from_authorization_response(
        &self,
        response: TokenEndpointResponse,
        transaction: &AuthorizationTransaction,
    ) -> Result<StoredSession> {
        let TokenEndpointResponse {
            access_token,
            expires_in,
            refresh_token,
            id_token,
            scope,
            ..
        } = response;
        let id_token = id_token.ok_or(OidcError::InvalidProviderResponse)?;
        let verified = self.verify_id_token(&id_token, &transaction.nonce).await?;
        let scopes = self.response_scopes(scope, &transaction.requested_scopes)?;
        let expires_at = token_expiration(self.clock.now(), expires_in, verified.expires_at)?;
        let metadata = SessionMetadata {
            issuer: verified.issuer,
            subject: verified.subject,
            granted_scopes: scopes,
            authenticated_at: verified.authenticated_at,
            expires_at,
        };
        let secrets = SessionSecrets::new(
            access_token,
            refresh_token,
            id_token,
            transaction.nonce.clone(),
        );
        Ok(StoredSession::new(metadata, secrets))
    }

    async fn session_from_refresh_response(
        &self,
        response: TokenEndpointResponse,
        previous: &StoredSession,
    ) -> Result<StoredSession> {
        let TokenEndpointResponse {
            access_token,
            expires_in,
            refresh_token,
            id_token: refreshed_id_token,
            scope,
            ..
        } = response;
        let (metadata_identity, id_token, id_expiration) = if let Some(compact) = refreshed_id_token
        {
            let verified = self
                .verify_id_token(&compact, previous.secrets.nonce())
                .await?;
            if verified.issuer != previous.metadata.issuer
                || verified.subject != previous.metadata.subject
            {
                return Err(OidcError::InvalidProviderResponse);
            }
            (
                (verified.issuer, verified.subject, verified.authenticated_at),
                compact,
                verified.expires_at,
            )
        } else {
            (
                (
                    previous.metadata.issuer.clone(),
                    previous.metadata.subject.clone(),
                    previous.metadata.authenticated_at,
                ),
                previous.secrets.id_token().clone(),
                DateTime::<Utc>::MAX_UTC,
            )
        };
        let expires_at = token_expiration(self.clock.now(), expires_in, id_expiration)?;
        let scopes = self.response_scopes(scope, &previous.metadata.granted_scopes)?;
        let metadata = SessionMetadata {
            issuer: metadata_identity.0,
            subject: metadata_identity.1,
            granted_scopes: scopes,
            authenticated_at: metadata_identity.2,
            expires_at,
        };
        let secrets = SessionSecrets::new(
            access_token,
            refresh_token.or_else(|| previous.secrets.refresh_token().cloned()),
            id_token,
            previous.secrets.nonce().clone(),
        );
        Ok(StoredSession::new(metadata, secrets))
    }

    async fn verify_id_token(
        &self,
        id_token: &SecretValue,
        nonce: &SecretValue,
    ) -> Result<crate::jwt::ValidatedIdToken> {
        let response = send_pinned(
            &*self.http,
            OidcHttpRequest::get(self.discovery.jwks_uri.clone()),
        )
        .await?;
        if response.status() != 200 {
            return Err(OidcError::Unavailable);
        }
        validate_id_token(
            id_token,
            response.body(),
            nonce,
            &self.config,
            &self.discovery,
            self.preset,
            self.clock.now(),
        )
    }

    async fn revoke_remote(&self, lease: &SessionLease) -> RemoteRevocation {
        let Some(endpoint) = self.discovery.revocation_endpoint.clone() else {
            return RemoteRevocation::NotSupported;
        };
        let mut tokens = Vec::new();
        if let Some(refresh) = lease.session.secrets.refresh_token() {
            tokens.push((refresh.clone(), "refresh_token"));
        }
        tokens.push((lease.session.secrets.access_token().clone(), "access_token"));
        for (token, hint) in tokens {
            let request = OidcHttpRequest::post_form(
                endpoint.clone(),
                vec![
                    ("token", token),
                    ("token_type_hint", SecretValue::new(hint)),
                    ("client_id", SecretValue::new(&self.config.client_id)),
                ],
            );
            let Ok(response) = send_pinned(&*self.http, request).await else {
                return RemoteRevocation::Failed;
            };
            if response.status() != 200 && response.status() != 204 {
                return RemoteRevocation::Failed;
            }
        }
        RemoteRevocation::Succeeded
    }

    fn end_session_url(&self) -> Option<Url> {
        let mut url = self.discovery.end_session_endpoint.clone()?;
        url.query_pairs_mut()
            .append_pair("client_id", &self.config.client_id);
        Some(url)
    }

    fn response_scopes(
        &self,
        response_scope: Option<String>,
        fallback: &BTreeSet<String>,
    ) -> Result<BTreeSet<String>> {
        let scopes = match response_scope {
            Some(scope) => scope
                .split_ascii_whitespace()
                .map(str::to_owned)
                .collect::<BTreeSet<_>>(),
            None => fallback.clone(),
        };
        if scopes.is_empty()
            || scopes
                .iter()
                .any(|scope| !self.config.scopes.contains(scope))
            || fallback.iter().any(|scope| !scopes.contains(scope))
        {
            return Err(OidcError::InvalidProviderResponse);
        }
        Ok(scopes)
    }

    fn add_token_resource(&self, form: &mut Vec<(&'static str, SecretValue)>) {
        if self.preset.resource_parameter == ResourceParameter::Rfc8707AuthorizationAndToken {
            form.push(("resource", SecretValue::new(&self.config.audience)));
        }
    }

    fn binding(&self, request: &SecurityContextRequest) -> SessionBinding {
        SessionBinding::new(
            &self.provider_id,
            &request.app_id,
            &request.tenant_id,
            &request.audience,
        )
    }

    fn validate_request(&self, request: &SecurityContextRequest) -> Result<()> {
        request
            .validate()
            .map_err(|_| OidcError::InvalidAuthorization)?;
        if request.audience != self.config.audience
            || request
                .required_scopes
                .iter()
                .any(|scope| !self.config.scopes.contains(scope))
        {
            return Err(OidcError::InvalidAuthorization);
        }
        Ok(())
    }

    fn context(
        &self,
        binding: &SessionBinding,
        metadata: &SessionMetadata,
    ) -> Result<SecurityContext> {
        let context = SecurityContext {
            schema_version: SECURITY_CONTEXT_SCHEMA_VERSION,
            provider_id: self.provider_id.clone(),
            app_id: binding.app_id().to_owned(),
            tenant_id: binding.tenant_id().to_owned(),
            audience: binding.audience().to_owned(),
            principal: PrincipalIdentity {
                issuer: metadata.issuer.clone(),
                subject: metadata.subject.clone(),
            },
            granted_scopes: metadata.granted_scopes.clone(),
            authenticated_at: metadata.authenticated_at,
            expires_at: metadata.expires_at,
        };
        context
            .validate()
            .map_err(|_| OidcError::InvalidProviderResponse)?;
        Ok(context)
    }

    fn random_secret(&self, bytes: usize) -> Result<SecretValue> {
        let mut buffer = Zeroizing::new(vec![0_u8; bytes]);
        self.random.fill(&mut buffer)?;
        Ok(SecretValue::new(URL_SAFE_NO_PAD.encode(buffer.as_slice())))
    }
}

#[async_trait]
impl IdentityProvider for GenericOidcProvider {
    fn provider_id(&self) -> &str {
        &self.provider_id
    }

    async fn security_context(
        &self,
        request: &SecurityContextRequest,
    ) -> std::result::Result<SecurityContext, IdentityProviderError> {
        self.validate_request(request)
            .map_err(IdentityProviderError::from)?;
        let binding = self.binding(request);
        let metadata = self
            .store
            .session_metadata(&binding)
            .await
            .map_err(map_store_error)
            .map_err(IdentityProviderError::from)?
            .ok_or_else(|| IdentityProviderError::from(OidcError::AuthenticationRequired))?;
        if metadata.expires_at <= self.clock.now() {
            return self
                .refresh(request)
                .await
                .map_err(IdentityProviderError::from);
        }
        let context = self
            .context(&binding, &metadata)
            .map_err(IdentityProviderError::from)?;
        context
            .validate_for(&self.provider_id, request, self.clock.now())
            .map_err(|_| IdentityProviderError::from(OidcError::InvalidProviderResponse))?;
        Ok(context)
    }
}

/// Stable, delimiter-safe partition identifier derived only from verified
/// `(provider, issuer, subject)` identity metadata.
pub fn principal_scope_id(provider_id: &str, issuer: &str, subject: &str) -> Result<String> {
    validate_identifier(provider_id)?;
    PrincipalIdentity {
        issuer: issuer.to_owned(),
        subject: subject.to_owned(),
    }
    .validate()
    .map_err(|_| OidcError::InvalidAuthorization)?;
    let mut digest = Sha256::new();
    digest.update(b"agentweave.identity.oidc.principal.v1\0");
    for value in [provider_id, issuer, subject] {
        digest.update((value.len() as u64).to_be_bytes());
        digest.update(value.as_bytes());
    }
    Ok(URL_SAFE_NO_PAD.encode(digest.finalize()))
}

pub(crate) async fn send_pinned(
    http: &dyn OidcHttpClient,
    request: OidcHttpRequest,
) -> Result<OidcHttpResponse> {
    let expected_url = request.url().clone();
    let response = http
        .send(request)
        .await
        .map_err(|_| OidcError::Unavailable)?;
    if response.final_url() != &expected_url || response.body().len() > MAX_HTTP_BODY_BYTES {
        return Err(OidcError::InvalidProviderResponse);
    }
    Ok(response)
}

fn validate_token_response(response: &TokenEndpointResponse) -> Result<()> {
    let token_values = [
        Some(response.access_token.expose_secret()),
        response
            .refresh_token
            .as_ref()
            .map(SecretValue::expose_secret),
        response.id_token.as_ref().map(SecretValue::expose_secret),
    ];
    if !response.token_type.eq_ignore_ascii_case("bearer")
        || token_values
            .into_iter()
            .flatten()
            .any(|value| !valid_secret_text(value))
        || response.expires_in == 0
        || response.expires_in > MAX_TOKEN_LIFETIME_SECONDS
    {
        return Err(OidcError::InvalidProviderResponse);
    }
    Ok(())
}

fn deserialize_secret<'de, D>(deserializer: D) -> std::result::Result<SecretValue, D::Error>
where
    D: Deserializer<'de>,
{
    String::deserialize(deserializer).map(SecretValue::new)
}

fn deserialize_optional_secret<'de, D>(
    deserializer: D,
) -> std::result::Result<Option<SecretValue>, D::Error>
where
    D: Deserializer<'de>,
{
    Option::<String>::deserialize(deserializer).map(|value| value.map(SecretValue::new))
}

fn token_expiration(
    now: DateTime<Utc>,
    expires_in: u64,
    id_token_expiration: DateTime<Utc>,
) -> Result<DateTime<Utc>> {
    let access_expiration = i64::try_from(expires_in)
        .ok()
        .and_then(|seconds| now.checked_add_signed(Duration::seconds(seconds)))
        .ok_or(OidcError::InvalidProviderResponse)?;
    let expires_at = access_expiration.min(id_token_expiration);
    if expires_at <= now {
        Err(OidcError::InvalidProviderResponse)
    } else {
        Ok(expires_at)
    }
}

fn digest_state(state: &str) -> StateDigest {
    StateDigest::new(Sha256::digest(state.as_bytes()).into())
}

fn valid_secret_text(value: &str) -> bool {
    !value.is_empty()
        && value.len() <= MAX_TOKEN_BYTES
        && value == value.trim()
        && !value.chars().any(char::is_control)
}

fn validate_identifier(value: &str) -> Result<()> {
    if value.is_empty()
        || value.len() > 255
        || value != value.trim()
        || !value
            .bytes()
            .all(|byte| byte.is_ascii_alphanumeric() || matches!(byte, b'.' | b'-' | b'_'))
    {
        Err(OidcError::InvalidConfiguration)
    } else {
        Ok(())
    }
}

fn map_store_error(error: SecretStoreError) -> OidcError {
    match error {
        SecretStoreError::Busy => OidcError::SessionBusy,
        SecretStoreError::Conflict | SecretStoreError::NotFound | SecretStoreError::Failure => {
            OidcError::SecureStorage
        }
    }
}
