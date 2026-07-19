use super::server_app::{ResolvedServerApp, resolve_secret_store};
use agent_runtime::{
    app_manifest::AgentAppIdentityMode, credential::SecretMaterial, storage::Storage,
};
use std::{
    path::{Path, PathBuf},
    sync::Arc,
};

pub(super) fn credential_root_for_database(database_path: Option<&Path>) -> Option<PathBuf> {
    database_path
        .and_then(Path::parent)
        .map(|parent| parent.join("credentials"))
}

pub(super) async fn resolve_identity_runtime(
    storage: &Storage,
    app: &ResolvedServerApp,
    credential_vault_key: Option<Arc<SecretMaterial>>,
    credential_root: Option<&Path>,
    tenant_id: &str,
) -> anyhow::Result<Option<agent_server::identity_api::IdentityRuntime>> {
    let Some(policy) = app.runtime_policy() else {
        return Ok(None);
    };
    let identity = policy.identity();
    if identity.mode == AgentAppIdentityMode::LocalSingleUser {
        return Ok(None);
    }
    let binding = identity.provider.as_ref().ok_or_else(|| {
        anyhow::anyhow!("required identity configuration is missing its provider binding")
    })?;
    let secrets = resolve_secret_store(credential_vault_key.as_deref(), credential_root)?
        .ok_or_else(|| {
            anyhow::anyhow!("required identity provider needs the persistent Credential Vault")
        })?;
    agent_server::identity_api::IdentityRuntime::oidc(
        binding,
        app.app_id(),
        tenant_id,
        storage.sqlite_pool(),
        secrets,
    )
    .await
    .map(Some)
}
