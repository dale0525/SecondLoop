use crate::api::AppState;
use agent_runtime::{
    app_manifest::AgentAppProviderBinding,
    attachments::AttachmentScope,
    automation_tools::AutomationScope,
    credential::{CredentialScope, SecretStore},
    identity::{
        IdentityProvider, IdentityProviderError, IdentityProviderErrorCode, SecurityContext,
        SecurityContextRequest,
    },
    memory::MemoryScope,
    session::ConversationScope,
    tasks::TaskScope,
};
use axum::{
    Json, Router,
    extract::{Request, State},
    http::StatusCode,
    middleware::Next,
    response::{IntoResponse, Response},
    routing::{get, post},
};
use identity_firebase::{
    FIREBASE_IDENTITY_PROVIDER_ID, FirebaseError, FirebaseIdentityProvider, FirebasePublicConfig,
    FirebaseSecret, FirebaseSessionStore, ReqwestFirebaseHttpClient,
};
use identity_oidc::{
    GenericOidcProvider, OIDC_IDENTITY_PROVIDER_ID, OidcError, OidcHttpClient,
    OidcPluginPublicConfig, OidcSecretStore, PersistentOidcSecretStore, RemoteRevocation,
    ReqwestOidcHttpClient, SessionBinding,
};
use model_gateway::credentials::{
    GatewayBearerToken, GatewayCredentialError, GatewayCredentialProvider,
};
use serde::{Deserialize, Serialize};
use std::sync::Arc;
use tokio::sync::{Mutex, RwLock};
use url::Url;
use zeroize::Zeroizing;

const MAX_CALLBACK_URL_BYTES: usize = 16 * 1024;

#[derive(Clone)]
pub struct IdentityRuntime {
    inner: Arc<IdentityRuntimeInner>,
}

struct IdentityRuntimeInner {
    request: SecurityContextRequest,
    kind: IdentityRuntimeKind,
    session_gate: RwLock<()>,
}

enum IdentityRuntimeKind {
    Oidc(Box<OidcRuntime>),
    Firebase(Arc<FirebaseIdentityProvider>),
}

struct OidcRuntime {
    provider_id: String,
    config: OidcPluginPublicConfig,
    store: Arc<dyn OidcSecretStore>,
    http: Arc<dyn OidcHttpClient>,
    provider: RwLock<Option<Arc<GenericOidcProvider>>>,
    initialize: Mutex<()>,
}

impl std::fmt::Debug for IdentityRuntime {
    fn fmt(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        formatter
            .debug_struct("IdentityRuntime")
            .field("provider_id", &self.provider_id())
            .field("app_id", &self.inner.request.app_id)
            .field("tenant_id", &self.inner.request.tenant_id)
            .finish_non_exhaustive()
    }
}

impl IdentityRuntime {
    pub async fn oidc(
        binding: &AgentAppProviderBinding,
        app_id: impl Into<String>,
        tenant_id: impl Into<String>,
        pool: sqlx::SqlitePool,
        secrets: Arc<dyn SecretStore>,
    ) -> anyhow::Result<Self> {
        anyhow::ensure!(
            binding.id.as_str() == OIDC_IDENTITY_PROVIDER_ID,
            "required identity provider is not supported by this Host"
        );
        let config: OidcPluginPublicConfig = serde_json::from_value(binding.public_config.clone())
            .map_err(|_| anyhow::anyhow!("OIDC public configuration is invalid"))?;
        config
            .validate()
            .map_err(|_| anyhow::anyhow!("OIDC public configuration is invalid"))?;
        let app_id = app_id.into();
        let tenant_id = tenant_id.into();
        let scope = agent_runtime::credential::CredentialScope {
            app_id: app_id.clone(),
            tenant_id: tenant_id.clone(),
            user_id: "identity-session".into(),
        };
        let store = Arc::new(
            PersistentOidcSecretStore::new(pool, secrets, scope)
                .await
                .map_err(|_| anyhow::anyhow!("OIDC secure storage is unavailable"))?,
        );
        let http = Arc::new(
            ReqwestOidcHttpClient::new()
                .map_err(|_| anyhow::anyhow!("OIDC HTTP client is unavailable"))?,
        );
        Self::with_dependencies(
            binding.id.as_str().to_owned(),
            config,
            app_id,
            tenant_id,
            store,
            http,
        )
    }

    fn with_dependencies(
        provider_id: String,
        config: OidcPluginPublicConfig,
        app_id: String,
        tenant_id: String,
        store: Arc<dyn OidcSecretStore>,
        http: Arc<dyn OidcHttpClient>,
    ) -> anyhow::Result<Self> {
        let request = SecurityContextRequest {
            app_id,
            tenant_id,
            audience: config.audience.clone(),
            required_scopes: config.scopes.clone(),
        };
        request.validate()?;
        Ok(Self {
            inner: Arc::new(IdentityRuntimeInner {
                request,
                kind: IdentityRuntimeKind::Oidc(Box::new(OidcRuntime {
                    provider_id,
                    config,
                    store,
                    http,
                    provider: RwLock::new(None),
                    initialize: Mutex::new(()),
                })),
                session_gate: RwLock::new(()),
            }),
        })
    }

    pub fn firebase(
        binding: &AgentAppProviderBinding,
        app_id: impl Into<String>,
        tenant_id: impl Into<String>,
        store: Arc<dyn FirebaseSessionStore>,
    ) -> anyhow::Result<Self> {
        anyhow::ensure!(
            binding.id.as_str() == FIREBASE_IDENTITY_PROVIDER_ID,
            "required identity provider is not supported by this Host"
        );
        let config: FirebasePublicConfig = serde_json::from_value(binding.public_config.clone())
            .map_err(|_| anyhow::anyhow!("Firebase public configuration is invalid"))?;
        config
            .validate()
            .map_err(|_| anyhow::anyhow!("Firebase public configuration is invalid"))?;
        let request = SecurityContextRequest {
            app_id: app_id.into(),
            tenant_id: tenant_id.into(),
            audience: config.audience().into(),
            required_scopes: Default::default(),
        };
        request.validate()?;
        let http = Arc::new(
            ReqwestFirebaseHttpClient::new()
                .map_err(|_| anyhow::anyhow!("Firebase HTTP client is unavailable"))?,
        );
        let provider = Arc::new(
            FirebaseIdentityProvider::new(config, store, http)
                .map_err(|_| anyhow::anyhow!("Firebase identity provider is unavailable"))?,
        );
        Ok(Self {
            inner: Arc::new(IdentityRuntimeInner {
                request,
                kind: IdentityRuntimeKind::Firebase(provider),
                session_gate: RwLock::new(()),
            }),
        })
    }

    pub fn provider_id(&self) -> &str {
        match &self.inner.kind {
            IdentityRuntimeKind::Oidc(runtime) => &runtime.provider_id,
            IdentityRuntimeKind::Firebase(_) => FIREBASE_IDENTITY_PROVIDER_ID,
        }
    }

    pub fn redirect_uri(&self) -> Option<&Url> {
        match &self.inner.kind {
            IdentityRuntimeKind::Oidc(runtime) => Some(&runtime.config.redirect_uri),
            IdentityRuntimeKind::Firebase(_) => None,
        }
    }

    async fn security_context(&self) -> Result<SecurityContext, IdentityProviderError> {
        match &self.inner.kind {
            IdentityRuntimeKind::Oidc(runtime) => {
                runtime
                    .provider()
                    .await
                    .map_err(IdentityProviderError::from)?
                    .security_context(&self.inner.request)
                    .await
            }
            IdentityRuntimeKind::Firebase(provider) => {
                provider.security_context(&self.inner.request).await
            }
        }
    }

    pub(crate) async fn gateway_test_assertion(
        &self,
    ) -> Result<IdentityAssertion, IdentityProviderError> {
        let value = match &self.inner.kind {
            IdentityRuntimeKind::Oidc(runtime) => runtime
                .provider()
                .await
                .map_err(IdentityProviderError::from)?
                .access_assertion(&self.inner.request)
                .await
                .map_err(IdentityProviderError::from)?
                .expose_secret()
                .to_owned(),
            IdentityRuntimeKind::Firebase(provider) => provider
                .gateway_assertion(&self.inner.request)
                .await
                .map_err(IdentityProviderError::from)?
                .expose_secret()
                .to_owned(),
        };
        Ok(IdentityAssertion(Zeroizing::new(value)))
    }

    async fn session_status(&self) -> IdentitySessionStatus {
        if let IdentityRuntimeKind::Oidc(runtime) = &self.inner.kind {
            match runtime.store.session_metadata(&self.binding()).await {
                Ok(None) => return IdentitySessionStatus::signed_out(),
                Err(_) => {
                    return IdentitySessionStatus {
                        state: IdentitySessionState::Unavailable,
                        account: None,
                    };
                }
                Ok(Some(_)) => {}
            }
        }
        match self.security_context().await {
            Ok(context) => IdentitySessionStatus {
                state: IdentitySessionState::SignedIn,
                account: Some(project_account(&self.inner.request, &context)),
            },
            Err(error) if error.code == IdentityProviderErrorCode::AuthenticationRequired => {
                IdentitySessionStatus::signed_out()
            }
            Err(_) => IdentitySessionStatus {
                state: IdentitySessionState::Unavailable,
                account: None,
            },
        }
    }

    async fn clear_local_session(&self) -> Result<(), IdentityProviderError> {
        match &self.inner.kind {
            IdentityRuntimeKind::Oidc(runtime) => {
                let lease = runtime
                    .store
                    .lease_session(&self.binding())
                    .await
                    .map_err(map_store_error)
                    .map_err(IdentityProviderError::from)?;
                if let Some(lease) = lease {
                    runtime
                        .store
                        .delete_leased_session(lease)
                        .await
                        .map_err(map_store_error)
                        .map_err(IdentityProviderError::from)?;
                }
                Ok(())
            }
            IdentityRuntimeKind::Firebase(provider) => provider
                .sign_out()
                .await
                .map_err(IdentityProviderError::from),
        }
    }

    fn binding(&self) -> SessionBinding {
        SessionBinding::new(
            self.provider_id(),
            &self.inner.request.app_id,
            &self.inner.request.tenant_id,
            &self.inner.request.audience,
        )
    }
}

impl OidcRuntime {
    async fn provider(&self) -> Result<Arc<GenericOidcProvider>, OidcError> {
        if let Some(provider) = self.provider.read().await.clone() {
            return Ok(provider);
        }
        let _guard = self.initialize.lock().await;
        if let Some(provider) = self.provider.read().await.clone() {
            return Ok(provider);
        }
        let provider = Arc::new(
            GenericOidcProvider::discover(
                self.provider_id.clone(),
                self.config.connection(),
                self.config.preset,
                self.http.clone(),
                self.store.clone(),
            )
            .await?,
        );
        *self.provider.write().await = Some(provider.clone());
        Ok(provider)
    }
}

pub(crate) struct IdentityAssertion(Zeroizing<String>);

impl IdentityAssertion {
    pub(crate) fn expose_secret(&self) -> &str {
        self.0.as_str()
    }
}

/// Trusted, request-local identity projection inserted only by the Host middleware.
///
/// The raw issuer and subject remain inside the non-serializable security context. Persistence
/// layers receive only the deterministic App-scoped user identifier.
#[derive(Clone, Debug)]
pub(crate) struct RequestSecurityContext {
    security_context: Option<SecurityContext>,
    conversation_scope: ConversationScope,
}

impl RequestSecurityContext {
    pub(crate) fn local(scope: &ConversationScope) -> Self {
        Self {
            security_context: None,
            conversation_scope: scope.clone(),
        }
    }

    fn authenticated(context: SecurityContext, base: &ConversationScope) -> Self {
        let user_id = scoped_user_id(&context.app_id, &context.tenant_id, &context);
        Self {
            conversation_scope: ConversationScope {
                app_id: context.app_id.clone(),
                agent_id: base.agent_id.clone(),
                tenant_id: context.tenant_id.clone(),
                user_id,
                device_id: base.device_id.clone(),
            },
            security_context: Some(context),
        }
    }

    pub(crate) fn conversation_scope(&self) -> &ConversationScope {
        &self.conversation_scope
    }

    pub(crate) fn memory_scope(&self) -> anyhow::Result<MemoryScope> {
        MemoryScope::new(
            &self.conversation_scope.app_id,
            &self.conversation_scope.tenant_id,
            &self.conversation_scope.user_id,
        )
        .map_err(Into::into)
    }

    pub(crate) fn task_scope(&self) -> anyhow::Result<TaskScope> {
        TaskScope::new(
            &self.conversation_scope.app_id,
            &self.conversation_scope.tenant_id,
            &self.conversation_scope.user_id,
        )
        .map_err(Into::into)
    }

    pub(crate) fn attachment_scope(&self) -> anyhow::Result<AttachmentScope> {
        AttachmentScope::new(
            &self.conversation_scope.app_id,
            &self.conversation_scope.tenant_id,
            &self.conversation_scope.user_id,
        )
        .map_err(Into::into)
    }

    pub(crate) fn automation_scope(&self) -> anyhow::Result<AutomationScope> {
        AutomationScope::new(
            &self.conversation_scope.app_id,
            &self.conversation_scope.tenant_id,
            &self.conversation_scope.user_id,
        )
    }

    pub(crate) fn credential_scope(&self) -> CredentialScope {
        CredentialScope {
            app_id: self.conversation_scope.app_id.clone(),
            tenant_id: self.conversation_scope.tenant_id.clone(),
            user_id: self.conversation_scope.user_id.clone(),
        }
    }

    pub(crate) fn is_authenticated(&self) -> bool {
        self.security_context.is_some()
    }
}

#[async_trait::async_trait]
impl GatewayCredentialProvider for IdentityRuntime {
    async fn bearer_token(&self) -> Result<GatewayBearerToken, GatewayCredentialError> {
        let assertion = self
            .gateway_test_assertion()
            .await
            .map_err(|_| GatewayCredentialError)?;
        GatewayBearerToken::new(assertion.expose_secret().to_owned())
    }
}

#[derive(Clone, Copy, Debug, Serialize, PartialEq, Eq)]
#[serde(rename_all = "snake_case")]
pub enum IdentitySessionState {
    SignedOut,
    SignedIn,
    Unavailable,
}

#[derive(Clone, Debug, Serialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub struct IdentityAccount {
    pub id: String,
    pub authenticated_at: chrono::DateTime<chrono::Utc>,
    pub expires_at: chrono::DateTime<chrono::Utc>,
}

#[derive(Clone, Debug, Serialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub struct IdentitySessionStatus {
    pub state: IdentitySessionState,
    pub account: Option<IdentityAccount>,
}

impl IdentitySessionStatus {
    fn signed_out() -> Self {
        Self {
            state: IdentitySessionState::SignedOut,
            account: None,
        }
    }
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
struct AuthorizationStartResponse {
    authorization_url: String,
    expires_at: chrono::DateTime<chrono::Utc>,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
struct AuthorizationCallbackRequest {
    callback_url: String,
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
struct PasswordSignInRequest {
    email: FirebaseSecret,
    password: FirebaseSecret,
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
struct LogoutResponse {
    status: IdentitySessionStatus,
    end_session_url: Option<String>,
    remote_revocation: LogoutRevocationStatus,
}

#[derive(Clone, Copy, Debug, Serialize)]
#[serde(rename_all = "snake_case")]
enum LogoutRevocationStatus {
    NotSupported,
    Succeeded,
    Failed,
}

pub(crate) fn routes() -> Router<Arc<AppState>> {
    Router::new()
        .route("/identity/status", get(status))
        .route("/identity/authorization", post(begin_authorization))
        .route("/identity/callback", post(complete_authorization))
        .route("/identity/password", post(sign_in_with_password))
        .route("/identity/logout", post(logout))
}

pub(crate) async fn require_identity(
    State(state): State<Arc<AppState>>,
    mut request: Request,
    next: Next,
) -> Response {
    let Some(runtime) = state.identity_runtime() else {
        request
            .extensions_mut()
            .insert(RequestSecurityContext::local(state.conversation_scope()));
        return next.run(request).await;
    };
    let _session_guard = runtime.inner.session_gate.read().await;
    match runtime.security_context().await {
        Ok(context) => {
            request
                .extensions_mut()
                .insert(RequestSecurityContext::authenticated(
                    context,
                    state.conversation_scope(),
                ));
            next.run(request).await
        }
        Err(error) if error.code == IdentityProviderErrorCode::AuthenticationRequired => (
            StatusCode::UNAUTHORIZED,
            Json(serde_json::json!({ "error": "identity_authorization_required" })),
        )
            .into_response(),
        Err(_) => (
            StatusCode::SERVICE_UNAVAILABLE,
            Json(serde_json::json!({ "error": "identity_unavailable" })),
        )
            .into_response(),
    }
}

async fn status(
    State(state): State<Arc<AppState>>,
) -> Result<Json<IdentitySessionStatus>, ApiError> {
    Ok(Json(runtime(&state)?.session_status().await))
}

async fn begin_authorization(
    State(state): State<Arc<AppState>>,
) -> Result<Json<AuthorizationStartResponse>, ApiError> {
    let runtime = runtime(&state)?;
    let IdentityRuntimeKind::Oidc(oidc) = &runtime.inner.kind else {
        return Err(ApiError::InvalidRequest);
    };
    let provider = oidc.provider().await.map_err(ApiError::from)?;
    let start = provider
        .begin_authorization(&runtime.inner.request)
        .await
        .map_err(ApiError::from)?;
    Ok(Json(AuthorizationStartResponse {
        authorization_url: start.url().as_str().to_owned(),
        expires_at: start.expires_at(),
    }))
}

async fn complete_authorization(
    State(state): State<Arc<AppState>>,
    Json(request): Json<AuthorizationCallbackRequest>,
) -> Result<Json<IdentitySessionStatus>, ApiError> {
    if request.callback_url.len() > MAX_CALLBACK_URL_BYTES {
        return Err(ApiError::InvalidRequest);
    }
    let runtime = runtime(&state)?;
    let _session_guard = runtime.inner.session_gate.write().await;
    let redirect_uri = runtime.redirect_uri().ok_or(ApiError::InvalidRequest)?;
    let callback = Url::parse(&request.callback_url).map_err(|_| ApiError::InvalidRequest)?;
    if callback.scheme() != redirect_uri.scheme()
        || callback.host_str() != redirect_uri.host_str()
        || callback.port_or_known_default() != redirect_uri.port_or_known_default()
        || callback.path() != redirect_uri.path()
    {
        return Err(ApiError::InvalidRequest);
    }
    let IdentityRuntimeKind::Oidc(oidc) = &runtime.inner.kind else {
        return Err(ApiError::InvalidRequest);
    };
    let provider = oidc.provider().await.map_err(ApiError::from)?;
    state.turn_coordinator().cancel_all().await;
    provider
        .complete_authorization_url(&callback)
        .await
        .map_err(ApiError::from)?;
    Ok(Json(runtime.session_status().await))
}

async fn sign_in_with_password(
    State(state): State<Arc<AppState>>,
    Json(request): Json<PasswordSignInRequest>,
) -> Result<Json<IdentitySessionStatus>, ApiError> {
    let runtime = runtime(&state)?;
    let _session_guard = runtime.inner.session_gate.write().await;
    let IdentityRuntimeKind::Firebase(provider) = &runtime.inner.kind else {
        return Err(ApiError::InvalidRequest);
    };
    state.turn_coordinator().cancel_all().await;
    provider
        .sign_in_with_password(&runtime.inner.request, request.email, request.password)
        .await
        .map_err(ApiError::from)?;
    Ok(Json(runtime.session_status().await))
}

async fn logout(State(state): State<Arc<AppState>>) -> Result<Json<LogoutResponse>, ApiError> {
    let runtime = runtime(&state)?;
    let _session_guard = runtime.inner.session_gate.write().await;
    state.turn_coordinator().cancel_all().await;
    let outcome = match &runtime.inner.kind {
        IdentityRuntimeKind::Oidc(oidc) => match oidc.provider().await {
            Ok(provider) => Some(
                provider
                    .logout(&runtime.inner.request)
                    .await
                    .map_err(ApiError::from)?,
            ),
            Err(_) => {
                runtime
                    .clear_local_session()
                    .await
                    .map_err(ApiError::from)?;
                None
            }
        },
        IdentityRuntimeKind::Firebase(provider) => {
            provider.sign_out().await.map_err(ApiError::from)?;
            None
        }
    };
    let end_session_url = outcome
        .as_ref()
        .and_then(|value| value.end_session_url.as_ref())
        .map(ToString::to_string);
    let remote_revocation = match outcome.map(|value| value.remote_revocation) {
        None | Some(RemoteRevocation::NotSupported) => LogoutRevocationStatus::NotSupported,
        Some(RemoteRevocation::Succeeded) => LogoutRevocationStatus::Succeeded,
        Some(RemoteRevocation::Failed) => LogoutRevocationStatus::Failed,
    };
    Ok(Json(LogoutResponse {
        status: IdentitySessionStatus::signed_out(),
        end_session_url,
        remote_revocation,
    }))
}

fn runtime(state: &AppState) -> Result<&IdentityRuntime, ApiError> {
    state.identity_runtime().ok_or(ApiError::NotConfigured)
}

fn project_account(request: &SecurityContextRequest, context: &SecurityContext) -> IdentityAccount {
    IdentityAccount {
        id: scoped_user_id(&request.app_id, &request.tenant_id, context),
        authenticated_at: context.authenticated_at,
        expires_at: context.expires_at,
    }
}

fn scoped_user_id(app_id: &str, tenant_id: &str, context: &SecurityContext) -> String {
    agent_runtime::identity::derive_scoped_user_id(
        app_id,
        tenant_id,
        &context.provider_id,
        &context.principal,
    )
    .expect("validated identity contexts must project to a scoped user identifier")
}

fn map_store_error(error: identity_oidc::SecretStoreError) -> OidcError {
    match error {
        identity_oidc::SecretStoreError::Busy => OidcError::SessionBusy,
        identity_oidc::SecretStoreError::Conflict
        | identity_oidc::SecretStoreError::NotFound
        | identity_oidc::SecretStoreError::Failure => OidcError::SecureStorage,
    }
}

#[derive(Clone, Copy, Debug)]
enum ApiError {
    NotConfigured,
    InvalidRequest,
    AccessDenied,
    Unavailable,
}

impl From<OidcError> for ApiError {
    fn from(error: OidcError) -> Self {
        match error {
            OidcError::InvalidConfiguration | OidcError::InvalidAuthorization => {
                Self::InvalidRequest
            }
            OidcError::AccessDenied => Self::AccessDenied,
            OidcError::AuthenticationRequired => Self::AccessDenied,
            OidcError::InvalidProviderResponse
            | OidcError::Unavailable
            | OidcError::SessionBusy
            | OidcError::SecureStorage => Self::Unavailable,
        }
    }
}

impl From<FirebaseError> for ApiError {
    fn from(error: FirebaseError) -> Self {
        match error {
            FirebaseError::InvalidConfiguration | FirebaseError::InvalidRequest => {
                Self::InvalidRequest
            }
            FirebaseError::AccessDenied | FirebaseError::AuthenticationRequired => {
                Self::AccessDenied
            }
            FirebaseError::InvalidResponse
            | FirebaseError::Unavailable
            | FirebaseError::SecureStorage => Self::Unavailable,
        }
    }
}

impl From<IdentityProviderError> for ApiError {
    fn from(error: IdentityProviderError) -> Self {
        match error.code {
            IdentityProviderErrorCode::InvalidRequest => Self::InvalidRequest,
            IdentityProviderErrorCode::AccessDenied
            | IdentityProviderErrorCode::AuthenticationRequired => Self::AccessDenied,
            IdentityProviderErrorCode::InvalidResponse | IdentityProviderErrorCode::Unavailable => {
                Self::Unavailable
            }
        }
    }
}

impl IntoResponse for ApiError {
    fn into_response(self) -> Response {
        let (status, code) = match self {
            Self::NotConfigured => (StatusCode::NOT_FOUND, "identity_not_configured"),
            Self::InvalidRequest => (StatusCode::BAD_REQUEST, "identity_request_invalid"),
            Self::AccessDenied => (StatusCode::UNAUTHORIZED, "identity_authorization_denied"),
            Self::Unavailable => (StatusCode::SERVICE_UNAVAILABLE, "identity_unavailable"),
        };
        (status, Json(serde_json::json!({ "error": code }))).into_response()
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use chrono::{Duration, Utc};
    use std::collections::BTreeSet;

    #[test]
    fn account_projection_is_stable_app_scoped_and_opaque() {
        let context = SecurityContext {
            schema_version: 1,
            provider_id: OIDC_IDENTITY_PROVIDER_ID.into(),
            app_id: "com.example.one".into(),
            tenant_id: "local".into(),
            audience: "https://gateway.example".into(),
            principal: agent_runtime::identity::PrincipalIdentity {
                issuer: "https://identity.example".into(),
                subject: "raw-subject".into(),
            },
            granted_scopes: BTreeSet::from(["openid".into()]),
            authenticated_at: Utc::now(),
            expires_at: Utc::now() + Duration::hours(1),
        };
        let first = SecurityContextRequest {
            app_id: "com.example.one".into(),
            tenant_id: "local".into(),
            audience: context.audience.clone(),
            required_scopes: BTreeSet::new(),
        };
        let second = SecurityContextRequest {
            app_id: "com.example.two".into(),
            ..first.clone()
        };

        let projected = project_account(&first, &context);
        assert_eq!(projected, project_account(&first, &context));
        assert_ne!(projected, project_account(&second, &context));
        assert!(!projected.id.contains("raw-subject"));
        assert!(!projected.id.contains("identity.example"));
    }

    #[tokio::test]
    async fn authenticated_request_scopes_isolate_sequential_accounts_from_legacy_data() {
        let base = ConversationScope::local("com.example.one");
        let first_context = SecurityContext {
            schema_version: 1,
            provider_id: OIDC_IDENTITY_PROVIDER_ID.into(),
            app_id: "com.example.one".into(),
            tenant_id: "local".into(),
            audience: "https://gateway.example".into(),
            principal: agent_runtime::identity::PrincipalIdentity {
                issuer: "https://identity.example".into(),
                subject: "account-a".into(),
            },
            granted_scopes: BTreeSet::from(["openid".into()]),
            authenticated_at: Utc::now(),
            expires_at: Utc::now() + Duration::hours(1),
        };
        let mut second_context = first_context.clone();
        second_context.principal.subject = "account-b".into();
        let first = RequestSecurityContext::authenticated(first_context, &base);
        let second = RequestSecurityContext::authenticated(second_context, &base);

        assert_ne!(first.conversation_scope(), second.conversation_scope());
        assert_ne!(first.conversation_scope(), &base);
        assert!(first.conversation_scope().user_id.starts_with("usr_"));
        assert!(second.conversation_scope().user_id.starts_with("usr_"));

        let storage = agent_runtime::storage::Storage::connect("sqlite::memory:")
            .await
            .unwrap();
        storage
            .create_scoped_session(&base, "Legacy")
            .await
            .unwrap();
        storage
            .create_scoped_session(first.conversation_scope(), "Account A")
            .await
            .unwrap();
        storage
            .create_scoped_session(second.conversation_scope(), "Account B")
            .await
            .unwrap();

        let first_sessions = storage
            .list_scoped_sessions(first.conversation_scope())
            .await
            .unwrap();
        let second_sessions = storage
            .list_scoped_sessions(second.conversation_scope())
            .await
            .unwrap();
        assert_eq!(first_sessions.len(), 1);
        assert_eq!(first_sessions[0].title, "Account A");
        assert_eq!(second_sessions.len(), 1);
        assert_eq!(second_sessions[0].title, "Account B");
    }
}
