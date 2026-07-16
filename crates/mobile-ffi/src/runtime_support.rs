use super::*;
use agent_runtime::credential::SecretMaterial;
use agent_runtime::storage_protection::StorageOpenOptions;
use zeroize::{Zeroize, Zeroizing};

pub(super) fn decode_storage_protection_key(
    encoded_key: Option<String>,
) -> Result<Option<Arc<SecretMaterial>>> {
    let Some(mut encoded_key) = encoded_key else {
        return Ok(None);
    };
    let mut key = Zeroizing::new([0_u8; 32]);
    let decoded = hex::decode_to_slice(encoded_key.as_bytes(), key.as_mut());
    encoded_key.zeroize();
    if decoded.is_err() {
        anyhow::bail!("storage protection key must be exactly 64 hexadecimal characters");
    }
    let secret = SecretMaterial::new(key.to_vec())?;
    drop(key);
    Ok(Some(Arc::new(secret)))
}

pub(super) fn open_mobile_storage(
    tokio: &Runtime,
    database_path: &Path,
    storage_protection_key: Option<Arc<SecretMaterial>>,
) -> Result<Storage> {
    if let Some(parent) = database_path.parent() {
        std::fs::create_dir_all(parent)?;
    }
    let database_url = format!("sqlite://{}?mode=rwc", database_path.display());
    let storage_options = storage_protection_key
        .map(|key| StorageOpenOptions::default().with_key(key))
        .unwrap_or_default();
    tokio.block_on(Storage::connect_with_options(
        &database_url,
        storage_options,
    ))
}

pub(super) struct MonotonicReloadStatus {
    generation: AtomicU64,
    status: Mutex<String>,
}

impl MonotonicReloadStatus {
    pub(super) fn new(generation: u64, status: impl Into<String>) -> Self {
        Self {
            generation: AtomicU64::new(generation),
            status: Mutex::new(status.into()),
        }
    }

    pub(super) fn record(&self, generation: u64) {
        let mut current = self.generation.load(Ordering::Acquire);
        loop {
            if generation <= current {
                return;
            }
            match self.generation.compare_exchange_weak(
                current,
                generation,
                Ordering::AcqRel,
                Ordering::Acquire,
            ) {
                Ok(_) => break,
                Err(observed) => current = observed,
            }
        }
        if let Ok(mut status) = self.status.lock()
            && self.generation.load(Ordering::Acquire) == generation
        {
            *status = format!("published_generation_{generation}");
        }
    }

    pub(super) fn snapshot(&self) -> String {
        self.status
            .lock()
            .map(|status| status.clone())
            .unwrap_or_else(|_| "unavailable".into())
    }
}

pub(super) struct TransientSecretResolver {
    secret: Mutex<Option<String>>,
}

impl TransientSecretResolver {
    pub(super) fn new(secret: Option<String>) -> Self {
        Self {
            secret: Mutex::new(secret),
        }
    }
}

#[async_trait::async_trait]
impl SecretResolver for TransientSecretResolver {
    async fn resolve_secret(&self, _secret_id: &str) -> Result<Option<String>> {
        Ok(self
            .secret
            .lock()
            .map_err(|_| anyhow::anyhow!("model secret lock is unavailable"))?
            .take())
    }
}

impl From<agent_runtime::session::Session> for MobileSessionDto {
    fn from(session: agent_runtime::session::Session) -> Self {
        Self {
            id: session.id,
            title: session.title,
            created_at: session.created_at.to_rfc3339(),
            updated_at: session.updated_at.to_rfc3339(),
        }
    }
}

impl From<agent_runtime::session::Message> for MobileMessageDto {
    fn from(message: agent_runtime::session::Message) -> Self {
        Self {
            id: message.id,
            session_id: message.session_id,
            role: message.role,
            content: message.content,
            created_at: message.created_at.to_rfc3339(),
        }
    }
}

impl TryFrom<MobileModelConfigDto> for StoredModelConfig {
    type Error = anyhow::Error;

    fn try_from(config: MobileModelConfigDto) -> Result<Self> {
        let endpoint_type = match config.endpoint_type.as_str() {
            "responses" => EndpointType::Responses,
            "chat_completions" => EndpointType::ChatCompletions,
            "completion" => EndpointType::Completion,
            value => anyhow::bail!("unsupported endpoint type: {value}"),
        };
        let stored = Self {
            provider_id: config.provider_id,
            provider_name: config.provider_name,
            endpoint_type,
            base_url: config.base_url,
            model_name: config.model_name,
            secret_id: config.secret_id,
            headers: config.headers,
        };
        stored.validate().map_err(anyhow::Error::msg)?;
        Ok(stored)
    }
}

impl From<StoredModelConfig> for MobileModelConfigDto {
    fn from(config: StoredModelConfig) -> Self {
        Self {
            provider_id: config.provider_id,
            provider_name: config.provider_name,
            endpoint_type: match config.endpoint_type {
                EndpointType::Responses => "responses",
                EndpointType::ChatCompletions => "chat_completions",
                EndpointType::Completion => "completion",
            }
            .into(),
            base_url: config.base_url,
            model_name: config.model_name,
            secret_id: config.secret_id,
            headers: config.headers,
        }
    }
}

pub(super) fn parse_platform(value: &str) -> Result<PlatformId> {
    match value {
        "android" => Ok(PlatformId::Android),
        "desktop" => Ok(PlatformId::Desktop),
        "ios" => Ok(PlatformId::Ios),
        "web" => Ok(PlatformId::Web),
        "server" => Ok(PlatformId::Server),
        _ => anyhow::bail!("unsupported platform: {value}"),
    }
}

pub(super) fn platform_name(platform: PlatformId) -> &'static str {
    match platform {
        PlatformId::Android => "android",
        PlatformId::Desktop => "desktop",
        PlatformId::Ios => "ios",
        PlatformId::Web => "web",
        PlatformId::Server => "server",
    }
}

pub(super) fn management_mode_name(mode: SkillManagementMode) -> &'static str {
    match mode {
        SkillManagementMode::Disabled => "disabled",
        SkillManagementMode::DiagnosticsOnly => "diagnostics_only",
        SkillManagementMode::OwnerOnly => "owner_only",
        SkillManagementMode::OrganizationManaged => "organization_managed",
    }
}

pub(super) fn recovery_status_name(status: RecoveryStatus) -> &'static str {
    match status {
        RecoveryStatus::CurrentSnapshotValid => "current_snapshot_valid",
        RecoveryStatus::NewSnapshotPublished => "new_snapshot_published",
        RecoveryStatus::LastKnownGoodRestored => "last_known_good_restored",
    }
}

pub(super) fn reload_report_value(
    report: &agent_runtime::skill_manager::SkillReloadReport,
) -> serde_json::Value {
    serde_json::json!({
        "previous_generation": report.previous_generation,
        "active_generation": report.active_generation,
        "active_packages": report.active_packages,
        "inactive_packages": report.inactive_packages,
    })
}

pub(super) fn approval_value(approval: &SkillApprovalRecord) -> serde_json::Value {
    serde_json::json!({
        "approval_id": approval.approval_id,
        "package_id": approval.package_id.as_str(),
        "permission_diff": approval.permission_diff,
        "requested_by": approval.requested_by,
        "revision_id": approval.revision_id,
        "status": approval.status.as_str(),
    })
}

pub(super) fn ensure_distinct_roots(roots: &[&Path]) -> Result<()> {
    for (index, left) in roots.iter().enumerate() {
        for right in roots.iter().skip(index + 1) {
            if left.starts_with(right) || right.starts_with(left) {
                anyhow::bail!("skill layer roots must be separate app-private directories");
            }
        }
    }
    Ok(())
}

pub(super) fn ensure_database_outside_skill_roots(database: &Path, roots: &[&Path]) -> Result<()> {
    if roots.iter().any(|root| database.starts_with(root)) {
        anyhow::bail!("database path must stay outside skill roots");
    }
    Ok(())
}

pub(super) fn ensure_configured_store_root(
    configured: &Path,
    prepared: &Path,
    label: &str,
) -> Result<()> {
    let configured = configured
        .canonicalize()
        .with_context(|| format!("failed to canonicalize {label}"))?;
    let prepared = prepared
        .canonicalize()
        .with_context(|| format!("failed to canonicalize prepared {label}"))?;
    if configured != prepared {
        anyhow::bail!("{label} must use the app-private managed skill layout");
    }
    Ok(())
}

pub(super) fn prepare_private_root(path: &str) -> Result<PathBuf> {
    if let Ok(metadata) = std::fs::symlink_metadata(path)
        && (metadata.file_type().is_symlink() || !metadata.is_dir())
    {
        anyhow::bail!("app-private root must be a real directory: {path}");
    }
    std::fs::create_dir_all(path)?;
    Path::new(path)
        .canonicalize()
        .with_context(|| format!("failed to canonicalize app-private root: {path}"))
}

pub(super) fn resolve_private_path(
    raw_path: &str,
    default_root: &Path,
    allowed_roots: &[PathBuf],
    label: &str,
) -> Result<PathBuf> {
    let candidate = Path::new(raw_path);
    let absolute_candidate = if candidate.is_absolute() {
        candidate.to_path_buf()
    } else {
        default_root.join(candidate)
    };
    let resolved_path = canonicalize_existing_ancestors(&absolute_candidate)?;

    if allowed_roots
        .iter()
        .any(|root| resolved_path.starts_with(root))
    {
        Ok(resolved_path)
    } else {
        anyhow::bail!("{label} must stay inside app-private storage")
    }
}

fn canonicalize_existing_ancestors(path: &Path) -> Result<PathBuf> {
    let mut resolved = PathBuf::new();

    for component in path.components() {
        match component {
            std::path::Component::Prefix(prefix) => resolved.push(prefix.as_os_str()),
            std::path::Component::RootDir => resolved.push(component.as_os_str()),
            std::path::Component::CurDir => {}
            std::path::Component::ParentDir => {
                anyhow::bail!("path must stay inside app-private storage")
            }
            std::path::Component::Normal(part) => {
                let next = resolved.join(part);
                if next.exists() {
                    resolved = next.canonicalize().with_context(|| {
                        format!("failed to canonicalize existing path: {}", next.display())
                    })?;
                } else {
                    resolved = next;
                }
            }
        }
    }

    Ok(resolved)
}

#[cfg(test)]
mod tests {
    use super::MonotonicReloadStatus;
    use std::sync::Arc;

    #[test]
    fn concurrent_reload_status_never_regresses_generation() {
        let status = Arc::new(MonotonicReloadStatus::new(1, "startup"));
        let (published, wait_for_publish) = std::sync::mpsc::channel();
        let newer = status.clone();
        let newer_thread = std::thread::spawn(move || {
            newer.record(5);
            published.send(()).unwrap();
        });
        let older = status.clone();
        let older_thread = std::thread::spawn(move || {
            wait_for_publish.recv().unwrap();
            older.record(4);
        });

        newer_thread.join().unwrap();
        older_thread.join().unwrap();

        assert_eq!(status.snapshot(), "published_generation_5");
    }
}
