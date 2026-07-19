use agent_runtime::{
    app_manifest::{AgentAppIdentityMode, AgentAppManifest},
    credential::{CredentialScope, SecretMaterial, SecretStore},
    credential_file::EncryptedFileSecretStore,
    identity::{
        IdentityProvider, IdentityProviderErrorCode, PrincipalIdentity,
        SECURITY_CONTEXT_SCHEMA_VERSION, SecurityContext, SecurityContextRequest,
    },
};
use chrono::Utc;
use identity_oidc::{
    AuthorizationPrompt, GenericOidcProvider, OIDC_IDENTITY_PROVIDER_ID, OidcError, OidcHttpClient,
    OidcPluginPublicConfig, OidcSecretStore, PersistentOidcSecretStore, RemoteRevocation,
    ReqwestOidcHttpClient, SessionBinding, SessionMetadata,
};
use serde::{Deserialize, Serialize};
use sqlx::{
    SqlitePool,
    sqlite::{SqliteConnectOptions, SqliteJournalMode, SqlitePoolOptions},
};
use std::{
    fs,
    path::{Path, PathBuf},
    sync::Arc,
    time::Duration,
};
use tokio::{
    runtime::Runtime,
    sync::{Mutex, RwLock},
};
use url::Url;

const MAX_CALLBACK_URL_BYTES: usize = 16 * 1024;

#[derive(Clone, Debug, Deserialize, PartialEq, Eq)]
#[serde(deny_unknown_fields)]
pub struct MobileIdentityInitConfig {
    pub app_data_dir: String,
    pub no_backup_dir: String,
    #[serde(default)]
    pub app_package_dir: Option<String>,
    pub metadata_database_path: String,
    pub secret_store_dir: String,
    pub tenant_id: String,
}

#[derive(Clone, Copy, Debug, Serialize, PartialEq, Eq)]
#[serde(rename_all = "snake_case")]
pub enum MobileIdentitySessionState {
    NotRequired,
    SignedOut,
    SignedIn,
    Expired,
    Unavailable,
}

#[derive(Clone, Debug, Serialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub struct MobileIdentityStatus {
    pub state: MobileIdentitySessionState,
    pub app_id: String,
    pub app_display_name: String,
    pub provider_id: Option<String>,
    pub account_id: Option<String>,
    pub security_context: Option<SecurityContext>,
}

#[derive(Clone, Debug, Serialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub struct MobileIdentityAuthorizationStart {
    pub authorization_url: String,
    pub expires_at: chrono::DateTime<Utc>,
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
pub struct MobileGatewayCredential {
    pub bearer_token: String,
    pub security_context: SecurityContext,
}

impl std::fmt::Debug for MobileGatewayCredential {
    fn fmt(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        formatter
            .debug_struct("MobileGatewayCredential")
            .field("bearer_token", &"[REDACTED]")
            .field("security_context", &self.security_context)
            .finish()
    }
}

#[derive(Clone, Copy, Debug, Serialize, PartialEq, Eq)]
#[serde(rename_all = "snake_case")]
pub enum MobileLogoutRevocation {
    NotSupported,
    Succeeded,
    Failed,
}

#[derive(Clone, Debug, Serialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub struct MobileIdentityLogout {
    pub end_session_url: Option<String>,
    pub remote_revocation: MobileLogoutRevocation,
    pub status: MobileIdentityStatus,
}

#[derive(Clone, Copy, Debug, thiserror::Error, PartialEq, Eq)]
pub enum MobileIdentityError {
    #[error("identity is not configured")]
    NotConfigured,
    #[error("identity request is invalid")]
    InvalidRequest,
    #[error("identity authorization is required")]
    AuthenticationRequired,
    #[error("identity authorization was denied")]
    AccessDenied,
    #[error("identity provider is unavailable")]
    Unavailable,
    #[error("identity secure storage is unavailable")]
    SecureStorage,
}

pub struct MobileIdentityRuntime {
    tokio: Runtime,
    app_id: String,
    app_display_name: String,
    required: Option<RequiredIdentity>,
}

struct RequiredIdentity {
    provider_id: String,
    config: OidcPluginPublicConfig,
    request: SecurityContextRequest,
    store: Arc<dyn OidcSecretStore>,
    http: Arc<dyn OidcHttpClient>,
    provider: RwLock<Option<Arc<GenericOidcProvider>>>,
    initialize: Mutex<()>,
    session_gate: RwLock<()>,
    pool: SqlitePool,
}

impl MobileIdentityRuntime {
    pub fn initialize(config: MobileIdentityInitConfig, master_key: &[u8]) -> anyhow::Result<Self> {
        let tokio = Runtime::new()?;
        let app_data = prepare_root(Path::new(&config.app_data_dir), "app data")?;
        let no_backup = prepare_root(Path::new(&config.no_backup_dir), "no-backup data")?;
        let package = config
            .app_package_dir
            .as_deref()
            .map(|value| confined_existing_directory(Path::new(value), &app_data, "App package"))
            .transpose()?;
        let Some(package) = package else {
            return Ok(Self {
                tokio,
                app_id: "dev.agentweave.default".into(),
                app_display_name: "AgentWeave".into(),
                required: None,
            });
        };
        let loaded = tokio.block_on(AgentAppManifest::load(&package))?;
        let manifest = loaded.manifest;
        let app_id = manifest.app_id.as_str().to_owned();
        let app_display_name = manifest.branding.display_name.clone();
        let identity = manifest.effective_identity();
        if identity.mode == AgentAppIdentityMode::LocalSingleUser {
            return Ok(Self {
                tokio,
                app_id,
                app_display_name,
                required: None,
            });
        }

        anyhow::ensure!(master_key.len() == 32, "identity master key is invalid");

        let binding = identity
            .provider
            .as_ref()
            .ok_or_else(|| anyhow::anyhow!("required identity provider is missing"))?;
        anyhow::ensure!(
            binding.id.as_str() == OIDC_IDENTITY_PROVIDER_ID,
            "required identity provider is unavailable"
        );
        let oidc: OidcPluginPublicConfig = serde_json::from_value(binding.public_config.clone())?;
        oidc.validate()
            .map_err(|_| anyhow::anyhow!("OIDC public configuration is invalid"))?;
        let request = SecurityContextRequest {
            app_id: app_id.clone(),
            tenant_id: config.tenant_id,
            audience: oidc.audience.clone(),
            required_scopes: oidc.scopes.clone(),
        };
        request.validate()?;
        let database_path = confined_file_path(
            Path::new(&config.metadata_database_path),
            &no_backup,
            "identity metadata database",
        )?;
        let secret_root = confined_directory_path(
            Path::new(&config.secret_store_dir),
            &no_backup,
            "identity secret store",
        )?;
        let options = SqliteConnectOptions::new()
            .filename(database_path)
            .create_if_missing(true)
            .foreign_keys(true)
            .journal_mode(SqliteJournalMode::Wal)
            .busy_timeout(Duration::from_secs(5));
        let pool = tokio.block_on(
            SqlitePoolOptions::new()
                .max_connections(1)
                .connect_with(options),
        )?;
        let key = SecretMaterial::new(master_key)?;
        let encrypted: Arc<dyn SecretStore> =
            Arc::new(EncryptedFileSecretStore::new(secret_root, key)?);
        let scope = CredentialScope {
            app_id: app_id.clone(),
            tenant_id: request.tenant_id.clone(),
            user_id: "identity-session".into(),
        };
        let store: Arc<dyn OidcSecretStore> = Arc::new(
            tokio
                .block_on(PersistentOidcSecretStore::new(
                    pool.clone(),
                    encrypted,
                    scope,
                ))
                .map_err(|_| anyhow::anyhow!("OIDC secure storage is unavailable"))?,
        );
        let http: Arc<dyn OidcHttpClient> = Arc::new(
            ReqwestOidcHttpClient::new()
                .map_err(|_| anyhow::anyhow!("OIDC HTTP client is unavailable"))?,
        );
        Ok(Self {
            tokio,
            app_id,
            app_display_name,
            required: Some(RequiredIdentity {
                provider_id: binding.id.as_str().to_owned(),
                config: oidc,
                request,
                store,
                http,
                provider: RwLock::new(None),
                initialize: Mutex::new(()),
                session_gate: RwLock::new(()),
                pool,
            }),
        })
    }

    pub fn status(&self) -> MobileIdentityStatus {
        let Some(required) = &self.required else {
            return self.local_status();
        };
        self.tokio
            .block_on(required.local_status(&self.app_id, &self.app_display_name))
    }

    pub fn begin_authorization(
        &self,
        force_account_selection: bool,
    ) -> Result<MobileIdentityAuthorizationStart, MobileIdentityError> {
        let required = self.required()?;
        self.tokio.block_on(async {
            let _session = required.session_gate.read().await;
            let provider = required.provider().await.map_err(map_oidc_error)?;
            let prompt = force_account_selection.then_some(AuthorizationPrompt::SelectAccount);
            let start = provider
                .begin_authorization_with_prompt(&required.request, prompt)
                .await
                .map_err(map_oidc_error)?;
            Ok(MobileIdentityAuthorizationStart {
                authorization_url: start.url().as_str().to_owned(),
                expires_at: start.expires_at(),
            })
        })
    }

    pub fn complete_authorization(
        &self,
        callback_url: &str,
    ) -> Result<MobileIdentityStatus, MobileIdentityError> {
        if callback_url.len() > MAX_CALLBACK_URL_BYTES {
            return Err(MobileIdentityError::InvalidRequest);
        }
        let required = self.required()?;
        let callback = Url::parse(callback_url).map_err(|_| MobileIdentityError::InvalidRequest)?;
        exact_callback(&required.config.redirect_uri, &callback)?;
        self.tokio.block_on(async {
            let _session = required.session_gate.write().await;
            let provider = required.provider().await.map_err(map_oidc_error)?;
            provider
                .complete_authorization_url(&callback)
                .await
                .map_err(map_oidc_error)?;
            Ok(required
                .local_status(&self.app_id, &self.app_display_name)
                .await)
        })
    }

    pub fn refresh(&self) -> Result<MobileIdentityStatus, MobileIdentityError> {
        let required = self.required()?;
        self.tokio.block_on(async {
            let _session = required.session_gate.write().await;
            let provider = required.provider().await.map_err(map_oidc_error)?;
            provider
                .security_context(&required.request)
                .await
                .map_err(map_provider_error)?;
            Ok(required
                .local_status(&self.app_id, &self.app_display_name)
                .await)
        })
    }

    pub fn gateway_credential(&self) -> Result<MobileGatewayCredential, MobileIdentityError> {
        let required = self.required()?;
        self.tokio.block_on(async {
            let _session = required.session_gate.read().await;
            let provider = required.provider().await.map_err(map_oidc_error)?;
            let context = provider
                .security_context(&required.request)
                .await
                .map_err(map_provider_error)?;
            let assertion = provider
                .access_assertion(&required.request)
                .await
                .map_err(map_oidc_error)?;
            Ok(MobileGatewayCredential {
                bearer_token: assertion.expose_secret().to_owned(),
                security_context: context,
            })
        })
    }

    pub fn logout(&self) -> Result<MobileIdentityLogout, MobileIdentityError> {
        let required = self.required()?;
        self.tokio.block_on(async {
            let _session = required.session_gate.write().await;
            let outcome = match required.provider().await {
                Ok(provider) => Some(
                    provider
                        .logout(&required.request)
                        .await
                        .map_err(map_oidc_error)?,
                ),
                Err(_) => {
                    required.clear_local_session().await?;
                    None
                }
            };
            Ok(MobileIdentityLogout {
                end_session_url: outcome
                    .as_ref()
                    .and_then(|value| value.end_session_url.as_ref())
                    .map(ToString::to_string),
                remote_revocation: match outcome.map(|value| value.remote_revocation) {
                    None | Some(RemoteRevocation::NotSupported) => {
                        MobileLogoutRevocation::NotSupported
                    }
                    Some(RemoteRevocation::Succeeded) => MobileLogoutRevocation::Succeeded,
                    Some(RemoteRevocation::Failed) => MobileLogoutRevocation::Failed,
                },
                status: self.signed_out_status(required),
            })
        })
    }

    pub fn close(&self) {
        if let Some(required) = &self.required {
            self.tokio.block_on(required.pool.close());
        }
    }

    fn required(&self) -> Result<&RequiredIdentity, MobileIdentityError> {
        self.required
            .as_ref()
            .ok_or(MobileIdentityError::NotConfigured)
    }

    fn local_status(&self) -> MobileIdentityStatus {
        MobileIdentityStatus {
            state: MobileIdentitySessionState::NotRequired,
            app_id: self.app_id.clone(),
            app_display_name: self.app_display_name.clone(),
            provider_id: None,
            account_id: None,
            security_context: None,
        }
    }

    fn signed_out_status(&self, required: &RequiredIdentity) -> MobileIdentityStatus {
        MobileIdentityStatus {
            state: MobileIdentitySessionState::SignedOut,
            app_id: self.app_id.clone(),
            app_display_name: self.app_display_name.clone(),
            provider_id: Some(required.provider_id.clone()),
            account_id: None,
            security_context: None,
        }
    }
}

impl RequiredIdentity {
    async fn provider(&self) -> Result<Arc<GenericOidcProvider>, OidcError> {
        if let Some(provider) = self.provider.read().await.clone() {
            return Ok(provider);
        }
        let _initializing = self.initialize.lock().await;
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

    async fn local_status(&self, app_id: &str, display_name: &str) -> MobileIdentityStatus {
        let base = || MobileIdentityStatus {
            state: MobileIdentitySessionState::SignedOut,
            app_id: app_id.to_owned(),
            app_display_name: display_name.to_owned(),
            provider_id: Some(self.provider_id.clone()),
            account_id: None,
            security_context: None,
        };
        let metadata = match self.store.session_metadata(&self.binding()).await {
            Ok(Some(metadata)) => metadata,
            Ok(None) => return base(),
            Err(_) => {
                return MobileIdentityStatus {
                    state: MobileIdentitySessionState::Unavailable,
                    ..base()
                };
            }
        };
        let context = match context_from_metadata(&self.provider_id, &self.request, metadata) {
            Ok(context) => context,
            Err(_) => {
                return MobileIdentityStatus {
                    state: MobileIdentitySessionState::Unavailable,
                    ..base()
                };
            }
        };
        let now = Utc::now();
        let state = if context.is_expired_at(now) {
            MobileIdentitySessionState::Expired
        } else if context
            .validate_for(&self.provider_id, &self.request, now)
            .is_ok()
        {
            MobileIdentitySessionState::SignedIn
        } else {
            MobileIdentitySessionState::Unavailable
        };
        if state == MobileIdentitySessionState::Unavailable {
            return MobileIdentityStatus { state, ..base() };
        }
        let account_id = context.scoped_user_id().ok();
        MobileIdentityStatus {
            state,
            account_id,
            security_context: Some(context),
            ..base()
        }
    }

    fn binding(&self) -> SessionBinding {
        SessionBinding::new(
            &self.provider_id,
            &self.request.app_id,
            &self.request.tenant_id,
            &self.request.audience,
        )
    }

    async fn clear_local_session(&self) -> Result<(), MobileIdentityError> {
        if let Some(lease) = self
            .store
            .lease_session(&self.binding())
            .await
            .map_err(|_| MobileIdentityError::SecureStorage)?
        {
            self.store
                .delete_leased_session(lease)
                .await
                .map_err(|_| MobileIdentityError::SecureStorage)?;
        }
        Ok(())
    }
}

fn context_from_metadata(
    provider_id: &str,
    request: &SecurityContextRequest,
    metadata: SessionMetadata,
) -> Result<SecurityContext, MobileIdentityError> {
    let context = SecurityContext {
        schema_version: SECURITY_CONTEXT_SCHEMA_VERSION,
        provider_id: provider_id.to_owned(),
        app_id: request.app_id.clone(),
        tenant_id: request.tenant_id.clone(),
        audience: request.audience.clone(),
        principal: PrincipalIdentity {
            issuer: metadata.issuer,
            subject: metadata.subject,
        },
        granted_scopes: metadata.granted_scopes,
        authenticated_at: metadata.authenticated_at,
        expires_at: metadata.expires_at,
    };
    context
        .validate()
        .map_err(|_| MobileIdentityError::SecureStorage)?;
    Ok(context)
}

fn exact_callback(expected: &Url, actual: &Url) -> Result<(), MobileIdentityError> {
    let mut base = actual.clone();
    base.set_query(None);
    base.set_fragment(None);
    if actual.fragment().is_some() || &base != expected {
        return Err(MobileIdentityError::InvalidRequest);
    }
    Ok(())
}

fn map_provider_error(
    error: agent_runtime::identity::IdentityProviderError,
) -> MobileIdentityError {
    match error.code {
        IdentityProviderErrorCode::AuthenticationRequired => {
            MobileIdentityError::AuthenticationRequired
        }
        IdentityProviderErrorCode::AccessDenied => MobileIdentityError::AccessDenied,
        IdentityProviderErrorCode::InvalidRequest => MobileIdentityError::InvalidRequest,
        IdentityProviderErrorCode::InvalidResponse | IdentityProviderErrorCode::Unavailable => {
            MobileIdentityError::Unavailable
        }
    }
}

fn map_oidc_error(error: OidcError) -> MobileIdentityError {
    match error {
        OidcError::InvalidConfiguration | OidcError::InvalidAuthorization => {
            MobileIdentityError::InvalidRequest
        }
        OidcError::AuthenticationRequired => MobileIdentityError::AuthenticationRequired,
        OidcError::AccessDenied => MobileIdentityError::AccessDenied,
        OidcError::SecureStorage | OidcError::SessionBusy => MobileIdentityError::SecureStorage,
        OidcError::InvalidProviderResponse | OidcError::Unavailable => {
            MobileIdentityError::Unavailable
        }
    }
}

fn prepare_root(path: &Path, label: &str) -> anyhow::Result<PathBuf> {
    if path.exists() {
        let metadata = fs::symlink_metadata(path)?;
        anyhow::ensure!(
            metadata.is_dir() && !metadata.file_type().is_symlink(),
            "{label} root is invalid"
        );
    } else {
        fs::create_dir_all(path)?;
    }
    path.canonicalize().map_err(Into::into)
}

fn confined_existing_directory(path: &Path, root: &Path, label: &str) -> anyhow::Result<PathBuf> {
    let metadata = fs::symlink_metadata(path)?;
    anyhow::ensure!(
        metadata.is_dir() && !metadata.file_type().is_symlink(),
        "{label} directory is invalid"
    );
    let canonical = path.canonicalize()?;
    anyhow::ensure!(canonical.starts_with(root), "{label} escapes app storage");
    Ok(canonical)
}

fn confined_file_path(path: &Path, root: &Path, label: &str) -> anyhow::Result<PathBuf> {
    let parent = path
        .parent()
        .ok_or_else(|| anyhow::anyhow!("{label} parent is missing"))?;
    fs::create_dir_all(parent)?;
    let parent = parent.canonicalize()?;
    anyhow::ensure!(parent.starts_with(root), "{label} escapes app storage");
    let name = path
        .file_name()
        .ok_or_else(|| anyhow::anyhow!("{label} name is missing"))?;
    let target = parent.join(name);
    if target.exists() {
        anyhow::ensure!(
            !fs::symlink_metadata(&target)?.file_type().is_symlink(),
            "{label} cannot be a symlink"
        );
    }
    Ok(target)
}

fn confined_directory_path(path: &Path, root: &Path, label: &str) -> anyhow::Result<PathBuf> {
    if path.exists() {
        let metadata = fs::symlink_metadata(path)?;
        anyhow::ensure!(
            metadata.is_dir() && !metadata.file_type().is_symlink(),
            "{label} is invalid"
        );
    } else {
        fs::create_dir_all(path)?;
    }
    let canonical = path.canonicalize()?;
    anyhow::ensure!(canonical.starts_with(root), "{label} escapes app storage");
    Ok(canonical)
}
