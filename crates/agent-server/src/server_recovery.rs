use super::*;
use agent_runtime::{app_manifest::AgentAppId, credential::SecretMaterial};
use serde_json::Value;
use sha2::{Digest, Sha256};
use std::sync::Arc;

const MAX_RECOVERY_DOCUMENT_BYTES: u64 = 256 * 1024;

pub(super) struct RecoveryRequirement {
    app_id: AgentAppId,
    app_root: PathBuf,
}

pub(super) async fn requirement(
    dev_api_enabled: bool,
) -> anyhow::Result<Option<RecoveryRequirement>> {
    if !dev_api_enabled {
        return Ok(None);
    }
    let Ok(expected_revision) = std::env::var("AGENTWEAVE_DEV_RECOVERY_REVISION") else {
        return Ok(None);
    };
    anyhow::ensure!(
        expected_revision.len() == 64
            && expected_revision
                .bytes()
                .all(|byte| byte.is_ascii_hexdigit()),
        "AGENTWEAVE_DEV_RECOVERY_REVISION is invalid"
    );
    let app_root = std::env::var("AGENTWEAVE_APP_ROOT")
        .map(PathBuf::from)
        .map_err(|_| anyhow::anyhow!("AGENTWEAVE_APP_ROOT is required for Developer Recovery"))?;
    let app_root = tokio::fs::canonicalize(app_root).await?;
    let manifest = read_recovery_document(&app_root.join("agent-app.json"), true).await?;
    let project = read_recovery_document(&app_root.join("agentweave-project.json"), false).await?;
    let mut hasher = Sha256::new();
    hasher.update(&manifest);
    hasher.update(b"\0");
    hasher.update(&project);
    if format!("{:x}", hasher.finalize()) != expected_revision {
        return Ok(None);
    }
    let document: Value = serde_json::from_slice(&manifest)?;
    let app_id = document
        .get("appId")
        .and_then(Value::as_str)
        .ok_or_else(|| anyhow::anyhow!("Developer Recovery requires agent app manifest appId"))?;
    let app_id = AgentAppId::parse(app_id)?;
    Ok(Some(RecoveryRequirement { app_id, app_root }))
}

pub(super) async fn serve(
    transport: agent_server::local_transport::PreparedLocalTransport,
    storage_protection_key: Option<Arc<SecretMaterial>>,
    credential_vault_key: Option<Arc<SecretMaterial>>,
    dev_skills_root: PathBuf,
    requirement: RecoveryRequirement,
) -> anyhow::Result<()> {
    let transport_auth = transport.auth().ok_or_else(|| {
        anyhow::anyhow!("Developer Recovery requires authenticated local transport")
    })?;
    let database_url =
        std::env::var("AGENTWEAVE_DATABASE_URL").unwrap_or_else(|_| DEFAULT_DATABASE_URL.into());
    let (storage, database_path) = open_storage(&database_url, storage_protection_key).await?;
    let credential_root =
        server_identity_startup::credential_root_for_database(database_path.as_deref());
    let secrets = server_app::resolve_secret_store(
        credential_vault_key.as_deref(),
        credential_root.as_deref(),
    )?
    .ok_or_else(|| {
        anyhow::anyhow!("Developer Recovery requires the persistent Credential Vault")
    })?;
    let project_identity = format!(
        "app={};root={}",
        requirement.app_id.as_str(),
        requirement.app_root.to_string_lossy(),
    );
    let control_plane = agent_server::developer_control_plane::DeveloperControlPlane::cloudflare(
        storage.sqlite_pool(),
        secrets,
        &project_identity,
        requirement.app_id.as_str(),
        agent_server::developer_control_plane::CloudflareOAuthDefaults::from_environment()?,
    )
    .await?;
    let state = Arc::new(agent_server::recovery_api::state(
        storage,
        requirement.app_id.as_str(),
        dev_skills_root,
        control_plane,
    ));
    let app = agent_server::recovery_api::router_for_transport(state, transport_auth);
    let addr = transport.address();
    let listener = transport.into_listener();
    tracing::warn!("agent server entered Developer Recovery on http://{addr}");
    axum::serve(listener, app).await?;
    Ok(())
}

async fn read_recovery_document(path: &std::path::Path, required: bool) -> anyhow::Result<Vec<u8>> {
    let metadata = match tokio::fs::symlink_metadata(path).await {
        Ok(metadata) => metadata,
        Err(error) if !required && error.kind() == std::io::ErrorKind::NotFound => {
            return Ok(Vec::new());
        }
        Err(error) => return Err(error.into()),
    };
    anyhow::ensure!(
        metadata.is_file()
            && !metadata.file_type().is_symlink()
            && metadata.len() <= MAX_RECOVERY_DOCUMENT_BYTES,
        "Developer Recovery configuration is not an allowed file"
    );
    Ok(tokio::fs::read(path).await?)
}

#[cfg(test)]
mod tests {
    #[test]
    fn recovery_revision_is_closed_and_bounded() {
        let values = [String::new(), "0".into(), "z".repeat(64), "0".repeat(65)];
        for value in values {
            assert!(value.len() != 64 || !value.bytes().all(|byte| byte.is_ascii_hexdigit()));
        }
    }
}
