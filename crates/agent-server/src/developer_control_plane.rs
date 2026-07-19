use crate::developer_sensitive_store::DeveloperSensitiveStore;
use agent_devkit::cloudflare::{
    CLOUDFLARE_PROVIDER_ID, CloudflareGatewayProvider, ReqwestCloudflareTransport,
};
use agent_devkit::{
    DeploymentPlan, DestroyPlan, DeveloperAuthorization, DevkitError, DevkitErrorCode,
    DevkitResult, GatewayDeploymentProvider, MutationControl, OperationLease,
    ProviderConfiguration, SensitiveInputHandle, SensitiveInputResolver, SensitiveInputStore,
    SensitiveValue,
};
use agent_runtime::credential::SecretStore;
use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};
use sqlx::{Row, SqlitePool};
use std::collections::{BTreeMap, BTreeSet};
use std::path::PathBuf;
use std::sync::Arc;
use std::time::{Duration, SystemTime, UNIX_EPOCH};
use tokio::sync::Mutex;
use uuid::Uuid;

const LEASE_LIFETIME_MS: u64 = 15 * 60 * 1_000;
const PLAN_LIFETIME_MS: u64 = 10 * 60 * 1_000;
const MAX_CACHED_PLANS: usize = 8;

#[derive(Clone, Debug, Default)]
pub struct CloudflareOAuthDefaults {
    pub client_id: Option<String>,
    pub scope_catalog: Option<BTreeMap<String, String>>,
}

#[derive(Clone)]
pub struct GatewayTemplateArtifact {
    version: String,
    bytes: Arc<Vec<u8>>,
    sha256: String,
}

impl GatewayTemplateArtifact {
    pub async fn from_environment() -> anyhow::Result<Option<Self>> {
        let Some(path) = std::env::var_os("AGENTWEAVE_CLOUDFLARE_GATEWAY_ARTIFACT") else {
            return Ok(None);
        };
        let path = PathBuf::from(path);
        anyhow::ensure!(
            path.is_absolute(),
            "Cloudflare gateway artifact path must be absolute"
        );
        let metadata = tokio::fs::symlink_metadata(&path).await?;
        anyhow::ensure!(
            metadata.is_file() && !metadata.file_type().is_symlink(),
            "Cloudflare gateway artifact must be a regular file"
        );
        anyhow::ensure!(
            metadata.len() > 0 && metadata.len() <= 16 * 1024 * 1024,
            "Cloudflare gateway artifact size is invalid"
        );
        let bytes = tokio::fs::read(path).await?;
        let version = std::env::var("AGENTWEAVE_CLOUDFLARE_GATEWAY_TEMPLATE_VERSION")
            .unwrap_or_else(|_| "0.3.0".into());
        Self::new(version, bytes).map(Some)
    }

    pub fn new(version: String, bytes: Vec<u8>) -> anyhow::Result<Self> {
        anyhow::ensure!(
            !version.trim().is_empty()
                && version.len() <= 128
                && !version.chars().any(char::is_control),
            "Cloudflare gateway template version is invalid"
        );
        anyhow::ensure!(
            !bytes.is_empty() && bytes.len() <= 16 * 1024 * 1024,
            "Cloudflare gateway artifact size is invalid"
        );
        let sha256 = hex::encode(Sha256::digest(&bytes));
        Ok(Self {
            version,
            bytes: Arc::new(bytes),
            sha256,
        })
    }

    pub fn version(&self) -> &str {
        &self.version
    }

    pub fn bytes(&self) -> &[u8] {
        &self.bytes
    }

    pub fn sha256(&self) -> &str {
        &self.sha256
    }
}

impl CloudflareOAuthDefaults {
    pub fn from_environment() -> anyhow::Result<Self> {
        let client_id = std::env::var("AGENTWEAVE_CLOUDFLARE_OAUTH_CLIENT_ID")
            .ok()
            .filter(|value| !value.trim().is_empty());
        let scope_catalog = match std::env::var("AGENTWEAVE_CLOUDFLARE_OAUTH_SCOPE_CATALOG_JSON") {
            Ok(value) => {
                let catalog: BTreeMap<String, String> = serde_json::from_str(&value)?;
                anyhow::ensure!(
                    !catalog.is_empty()
                        && catalog.iter().all(|(name, id)| {
                            !name.trim().is_empty()
                                && !id.trim().is_empty()
                                && name.len() <= 256
                                && id.len() <= 256
                                && !name.chars().any(char::is_control)
                                && !id.chars().any(char::is_control)
                        }),
                    "Cloudflare OAuth scope catalog is invalid"
                );
                Some(catalog)
            }
            Err(_) => None,
        };
        anyhow::ensure!(
            client_id.is_some() == scope_catalog.is_some(),
            "Cloudflare public OAuth client ID and scope catalog must be configured together"
        );
        Ok(Self {
            client_id,
            scope_catalog,
        })
    }

    pub fn public_client_available(&self) -> bool {
        self.client_id.is_some() && self.scope_catalog.is_some()
    }
}

pub struct DeveloperControlPlane {
    pub(super) provider: Arc<dyn GatewayDeploymentProvider>,
    pub(super) sensitive: Arc<DeveloperSensitiveStore>,
    pub(super) pool: SqlitePool,
    pub(super) project_key: String,
    pub(super) app_id: String,
    pub(super) oauth_defaults: CloudflareOAuthDefaults,
    pub(super) gateway_template: Option<GatewayTemplateArtifact>,
    pub(super) pending_authorization: Mutex<Option<PendingAuthorization>>,
    pub(super) cached_plans: Mutex<BTreeMap<String, CachedPlan>>,
    pub(super) mutation: Mutex<()>,
    pub(super) owner_id: String,
}

pub(super) struct PendingAuthorization {
    pub configuration: ProviderConfiguration,
    pub redirect_uri: url::Url,
    pub state_handle: SensitiveInputHandle,
    pub verifier_handle: SensitiveInputHandle,
    pub expected_catalog_revision: String,
    pub expected_scope_ids: BTreeSet<String>,
    pub expires_at_unix_ms: u64,
}

#[derive(Clone)]
pub(super) enum CachedPlan {
    Deployment(Box<CachedDeploymentPlan>),
    Destroy(Box<CachedDestroyPlan>),
}

#[derive(Clone)]
pub(super) struct CachedDeploymentPlan {
    pub plan: DeploymentPlan,
    pub environment: Option<String>,
    pub expires_at_unix_ms: u64,
}

#[derive(Clone)]
pub(super) struct CachedDestroyPlan {
    pub plan: DestroyPlan,
    pub expires_at_unix_ms: u64,
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct StoredSensitiveBinding {
    pub binding_name: String,
    pub revision: String,
    pub handle: SensitiveInputHandle,
}

impl DeveloperControlPlane {
    pub async fn cloudflare(
        pool: SqlitePool,
        secrets: Arc<dyn SecretStore>,
        project_identity: &str,
        app_id: &str,
        oauth_defaults: CloudflareOAuthDefaults,
    ) -> anyhow::Result<Self> {
        let project_key = project_key(project_identity)?;
        let sensitive = Arc::new(DeveloperSensitiveStore::new(secrets, &project_key)?);
        let transport = Arc::new(
            ReqwestCloudflareTransport::new(Duration::from_secs(30))
                .map_err(|error| anyhow::anyhow!(error.safe_message))?,
        );
        let provider = Arc::new(CloudflareGatewayProvider::new(
            transport,
            Arc::clone(&sensitive),
        )?);
        let gateway_template = GatewayTemplateArtifact::from_environment().await?;
        Self::new(
            pool,
            sensitive,
            provider,
            project_key,
            app_id.to_owned(),
            oauth_defaults,
            gateway_template,
        )
        .await
    }

    pub(crate) async fn new(
        pool: SqlitePool,
        sensitive: Arc<DeveloperSensitiveStore>,
        provider: Arc<dyn GatewayDeploymentProvider>,
        project_key: String,
        app_id: String,
        oauth_defaults: CloudflareOAuthDefaults,
        gateway_template: Option<GatewayTemplateArtifact>,
    ) -> anyhow::Result<Self> {
        anyhow::ensure!(
            !app_id.trim().is_empty()
                && app_id.len() <= 255
                && !app_id.chars().any(char::is_control),
            "developer App ID is invalid"
        );
        migrate(&pool).await?;
        Ok(Self {
            provider,
            sensitive,
            pool,
            project_key,
            app_id,
            oauth_defaults,
            gateway_template,
            pending_authorization: Mutex::new(None),
            cached_plans: Mutex::new(BTreeMap::new()),
            mutation: Mutex::new(()),
            owner_id: format!("developer-host-{}", Uuid::new_v4()),
        })
    }

    pub fn public_oauth_client_available(&self) -> bool {
        self.oauth_defaults.public_client_available()
    }

    pub fn gateway_template(&self) -> Option<&GatewayTemplateArtifact> {
        self.gateway_template.as_ref()
    }

    pub(super) async fn load_authorization(&self) -> DevkitResult<Option<DeveloperAuthorization>> {
        let row = sqlx::query(
            "SELECT authorization_json FROM developer_provider_authorizations WHERE project_key = ?1 AND provider_id = ?2",
        )
        .bind(&self.project_key)
        .bind(CLOUDFLARE_PROVIDER_ID)
        .fetch_optional(&self.pool)
        .await
        .map_err(|_| internal_state_error())?;
        row.map(|row| {
            serde_json::from_str(row.get::<&str, _>("authorization_json"))
                .map_err(|_| internal_state_error())
        })
        .transpose()
    }

    pub(super) async fn save_authorization(
        &self,
        authorization: &DeveloperAuthorization,
    ) -> DevkitResult<()> {
        if authorization.provider_id() != CLOUDFLARE_PROVIDER_ID {
            return Err(DevkitError::new(
                DevkitErrorCode::InvalidAuthorization,
                "developer authorization belongs to an unsupported provider",
            ));
        }
        let document = serde_json::to_string(authorization).map_err(|_| internal_state_error())?;
        sqlx::query(
            "INSERT INTO developer_provider_authorizations (project_key, provider_id, authorization_json, updated_at_unix_ms) VALUES (?1, ?2, ?3, ?4) ON CONFLICT (project_key, provider_id) DO UPDATE SET authorization_json = excluded.authorization_json, updated_at_unix_ms = excluded.updated_at_unix_ms",
        )
        .bind(&self.project_key)
        .bind(CLOUDFLARE_PROVIDER_ID)
        .bind(document)
        .bind(now_unix_ms() as i64)
        .execute(&self.pool)
        .await
        .map_err(|_| internal_state_error())?;
        Ok(())
    }

    pub(super) async fn delete_authorization_record(&self) -> DevkitResult<()> {
        sqlx::query(
            "DELETE FROM developer_provider_authorizations WHERE project_key = ?1 AND provider_id = ?2",
        )
        .bind(&self.project_key)
        .bind(CLOUDFLARE_PROVIDER_ID)
        .execute(&self.pool)
        .await
        .map_err(|_| internal_state_error())?;
        Ok(())
    }

    pub(super) async fn resolve_sensitive_binding(
        &self,
        binding_name: &str,
        revision: &str,
        replacement: Option<Vec<u8>>,
    ) -> DevkitResult<StoredSensitiveBinding> {
        validate_binding_metadata(binding_name, revision)?;
        let current = self.load_sensitive_binding(binding_name).await?;
        if let Some(value) = replacement {
            let handle = self
                .sensitive
                .store(
                    &format!("cloudflare/deployment-secret/{binding_name}"),
                    SensitiveValue::new(value)?,
                )
                .await?;
            if let Err(error) = self
                .save_sensitive_binding(binding_name, revision, &handle)
                .await
            {
                let _ = self.sensitive.delete_handle(&handle).await;
                return Err(error);
            }
            if let Some(previous) = current
                && previous.handle != handle
            {
                let _ = self.sensitive.delete_handle(&previous.handle).await;
            }
            return Ok(StoredSensitiveBinding {
                binding_name: binding_name.into(),
                revision: revision.into(),
                handle,
            });
        }
        let current = current.ok_or_else(|| {
            DevkitError::new(
                DevkitErrorCode::SensitiveInputUnavailable,
                format!("sensitive binding requires a value: {binding_name}"),
            )
        })?;
        if current.revision != revision {
            return Err(DevkitError::new(
                DevkitErrorCode::ConcurrentModification,
                format!("sensitive binding revision changed: {binding_name}"),
            ));
        }
        self.sensitive.resolve(&current.handle).await?;
        Ok(current)
    }

    async fn load_sensitive_binding(
        &self,
        binding_name: &str,
    ) -> DevkitResult<Option<StoredSensitiveBinding>> {
        let row = sqlx::query(
            "SELECT revision, handle FROM developer_sensitive_bindings WHERE project_key = ?1 AND binding_name = ?2",
        )
        .bind(&self.project_key)
        .bind(binding_name)
        .fetch_optional(&self.pool)
        .await
        .map_err(|_| internal_state_error())?;
        row.map(|row| {
            Ok(StoredSensitiveBinding {
                binding_name: binding_name.into(),
                revision: row.get("revision"),
                handle: SensitiveInputHandle::from_opaque_reference(
                    row.get::<String, _>("handle"),
                )?,
            })
        })
        .transpose()
    }

    pub(crate) async fn sensitive_binding_revisions(
        &self,
    ) -> DevkitResult<BTreeMap<String, String>> {
        let rows = sqlx::query(
            "SELECT binding_name, revision FROM developer_sensitive_bindings WHERE project_key = ?1 ORDER BY binding_name",
        )
        .bind(&self.project_key)
        .fetch_all(&self.pool)
        .await
        .map_err(|_| internal_state_error())?;
        rows.into_iter()
            .map(|row| {
                let name: String = row.get("binding_name");
                let revision: String = row.get("revision");
                if name.is_empty()
                    || name.len() > 128
                    || revision.is_empty()
                    || revision.len() > 256
                    || name.chars().any(char::is_control)
                    || revision.chars().any(char::is_control)
                {
                    return Err(internal_state_error());
                }
                Ok((name, revision))
            })
            .collect()
    }

    async fn save_sensitive_binding(
        &self,
        binding_name: &str,
        revision: &str,
        handle: &SensitiveInputHandle,
    ) -> DevkitResult<()> {
        sqlx::query(
            "INSERT INTO developer_sensitive_bindings (project_key, binding_name, revision, handle, updated_at_unix_ms) VALUES (?1, ?2, ?3, ?4, ?5) ON CONFLICT (project_key, binding_name) DO UPDATE SET revision = excluded.revision, handle = excluded.handle, updated_at_unix_ms = excluded.updated_at_unix_ms",
        )
        .bind(&self.project_key)
        .bind(binding_name)
        .bind(revision)
        .bind(handle.opaque_reference())
        .bind(now_unix_ms() as i64)
        .execute(&self.pool)
        .await
        .map_err(|_| internal_state_error())?;
        Ok(())
    }

    pub(super) async fn acquire_lease(
        &self,
        idempotency_key: String,
        expected_remote_version: Option<String>,
        expected_remote_etag: Option<String>,
    ) -> DevkitResult<MutationControl> {
        let now = now_unix_ms();
        let mut transaction = self
            .pool
            .begin()
            .await
            .map_err(|_| internal_state_error())?;
        let current = sqlx::query(
            "SELECT owner_id, lease_version, expires_at_unix_ms FROM developer_deployment_leases WHERE project_key = ?1",
        )
        .bind(&self.project_key)
        .fetch_optional(&mut *transaction)
        .await
        .map_err(|_| internal_state_error())?;
        let next_version = if let Some(row) = current {
            let owner: String = row.get("owner_id");
            let version: i64 = row.get("lease_version");
            let expires: i64 = row.get("expires_at_unix_ms");
            if expires > now as i64 && owner != self.owner_id {
                return Err(DevkitError::new(
                    DevkitErrorCode::ConcurrentModification,
                    "another developer Host owns the deployment lease",
                )
                .retry_after((expires as u64).saturating_sub(now)));
            }
            (version as u64).saturating_add(1)
        } else {
            1
        };
        let expires_at_unix_ms = now.saturating_add(LEASE_LIFETIME_MS);
        sqlx::query(
            "INSERT INTO developer_deployment_leases (project_key, owner_id, lease_version, expires_at_unix_ms) VALUES (?1, ?2, ?3, ?4) ON CONFLICT (project_key) DO UPDATE SET owner_id = excluded.owner_id, lease_version = excluded.lease_version, expires_at_unix_ms = excluded.expires_at_unix_ms",
        )
        .bind(&self.project_key)
        .bind(&self.owner_id)
        .bind(next_version as i64)
        .bind(expires_at_unix_ms as i64)
        .execute(&mut *transaction)
        .await
        .map_err(|_| internal_state_error())?;
        transaction
            .commit()
            .await
            .map_err(|_| internal_state_error())?;
        let control = MutationControl {
            operation_id: Uuid::new_v4(),
            idempotency_key,
            expected_remote_version,
            expected_remote_etag,
            lease: OperationLease {
                owner_id: self.owner_id.clone(),
                lease_version: next_version,
                expires_at_unix_ms,
            },
        };
        control.validate(now)?;
        Ok(control)
    }

    pub(super) async fn release_lease(&self, lease: &OperationLease) -> DevkitResult<()> {
        sqlx::query(
            "DELETE FROM developer_deployment_leases WHERE project_key = ?1 AND owner_id = ?2 AND lease_version = ?3",
        )
        .bind(&self.project_key)
        .bind(&lease.owner_id)
        .bind(lease.lease_version as i64)
        .execute(&self.pool)
        .await
        .map_err(|_| internal_state_error())?;
        Ok(())
    }

    pub(super) async fn cache_plan(&self, hash: String, plan: CachedPlan) {
        let now = now_unix_ms();
        let mut plans = self.cached_plans.lock().await;
        plans.retain(|_, candidate| candidate.expires_at_unix_ms() > now);
        if plans.len() >= MAX_CACHED_PLANS
            && let Some(first) = plans.keys().next().cloned()
        {
            plans.remove(&first);
        }
        plans.insert(hash, plan);
    }

    pub(super) fn plan_expiry() -> u64 {
        now_unix_ms().saturating_add(PLAN_LIFETIME_MS)
    }
}

impl CachedPlan {
    pub(super) fn expires_at_unix_ms(&self) -> u64 {
        match self {
            Self::Deployment(plan) => plan.expires_at_unix_ms,
            Self::Destroy(plan) => plan.expires_at_unix_ms,
        }
    }
}

pub(super) fn now_unix_ms() -> u64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or_default()
        .as_millis()
        .try_into()
        .unwrap_or(u64::MAX)
}

pub(super) fn internal_state_error() -> DevkitError {
    DevkitError::new(
        DevkitErrorCode::Internal,
        "developer control-plane state is unavailable",
    )
}

fn project_key(project_identity: &str) -> anyhow::Result<String> {
    anyhow::ensure!(
        !project_identity.trim().is_empty()
            && project_identity.len() <= 16 * 1024
            && !project_identity.chars().any(char::is_control),
        "developer project identity is invalid"
    );
    let mut digest = Sha256::new();
    digest.update(b"agentweave.developer-project.v1\0");
    digest.update(project_identity.as_bytes());
    Ok(hex::encode(digest.finalize()))
}

fn validate_binding_metadata(binding_name: &str, revision: &str) -> DevkitResult<()> {
    if binding_name.is_empty()
        || binding_name.len() > 128
        || !binding_name
            .bytes()
            .all(|byte| byte.is_ascii_uppercase() || byte.is_ascii_digit() || byte == b'_')
        || revision.is_empty()
        || revision.len() > 256
        || revision.chars().any(char::is_control)
    {
        return Err(DevkitError::invalid_configuration(
            "sensitive deployment binding metadata is invalid",
        ));
    }
    Ok(())
}

async fn migrate(pool: &SqlitePool) -> anyhow::Result<()> {
    sqlx::query(
        r#"
        CREATE TABLE IF NOT EXISTS developer_provider_authorizations (
          project_key TEXT NOT NULL,
          provider_id TEXT NOT NULL,
          authorization_json TEXT NOT NULL,
          updated_at_unix_ms INTEGER NOT NULL,
          PRIMARY KEY (project_key, provider_id)
        )
        "#,
    )
    .execute(pool)
    .await?;
    sqlx::query(
        r#"
        CREATE TABLE IF NOT EXISTS developer_sensitive_bindings (
          project_key TEXT NOT NULL,
          binding_name TEXT NOT NULL,
          revision TEXT NOT NULL,
          handle TEXT NOT NULL,
          updated_at_unix_ms INTEGER NOT NULL,
          PRIMARY KEY (project_key, binding_name)
        )
        "#,
    )
    .execute(pool)
    .await?;
    sqlx::query(
        r#"
        CREATE TABLE IF NOT EXISTS developer_deployment_leases (
          project_key TEXT PRIMARY KEY,
          owner_id TEXT NOT NULL,
          lease_version INTEGER NOT NULL,
          expires_at_unix_ms INTEGER NOT NULL
        )
        "#,
    )
    .execute(pool)
    .await?;
    Ok(())
}
