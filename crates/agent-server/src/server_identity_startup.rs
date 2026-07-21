use super::server_app::{ResolvedServerApp, resolve_secret_store};
use agent_runtime::{
    app_manifest::AgentAppIdentityMode,
    credential::{CredentialVault, SecretMaterial},
    credential_sqlite::SqliteCredentialMetadataStore,
    storage::Storage,
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
    if binding.id.as_str() == identity_oidc::OIDC_IDENTITY_PROVIDER_ID {
        return agent_server::identity_api::IdentityRuntime::oidc(
            binding,
            app.app_id(),
            tenant_id,
            storage.sqlite_pool(),
            secrets,
        )
        .await
        .map(Some);
    }
    if binding.id.as_str() == identity_firebase::FIREBASE_IDENTITY_PROVIDER_ID {
        let metadata = SqliteCredentialMetadataStore::from_storage(storage).await?;
        let vault = Arc::new(CredentialVault::new_persistent(secrets, metadata));
        let store = Arc::new(
            agent_server::firebase_identity_store::VaultFirebaseSessionStore::new(
                vault,
                app.app_id().to_owned(),
                tenant_id.to_owned(),
            )
            .map_err(|_| anyhow::anyhow!("Firebase secure storage is unavailable"))?,
        );
        return agent_server::identity_api::IdentityRuntime::firebase(
            binding,
            app.app_id(),
            tenant_id,
            store,
        )
        .map(Some);
    }
    anyhow::bail!("required identity provider is not supported by this Host")
}
