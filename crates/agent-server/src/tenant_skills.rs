use crate::tenant_initialization::{
    TenantInitializationPaths, acquire_tenant_initialization_lock, prepare_real_directory,
};
use agent_runtime::platform::{CapabilitySet, PlatformId};
use agent_runtime::skill_management::OwnerSkillManagementService;
use agent_runtime::skill_manager::{SkillManager, SkillManagerConfig};
use agent_runtime::skill_package::SkillPackageId;
use agent_runtime::skill_policy::SkillManagementPolicy;
use agent_runtime::skill_source::{ManagedSkillSource, SkillSource};
use agent_runtime::skill_state::SkillStateStore;
use agent_runtime::skill_store::{SkillRevisionStore, SkillStorePaths};
use agent_runtime::storage::Storage;
use anyhow::Context;
use semver::Version;
use std::collections::HashMap;
use std::path::{Path, PathBuf};
use std::sync::{Arc, Mutex};
use tokio::sync::{Notify, OnceCell};

pub const SINGLE_USER_TENANT_ID: &str = "local";

#[derive(Clone)]
pub struct TenantSkillRuntime {
    pub tenant_id: String,
    pub manager: SkillManager,
    pub management: OwnerSkillManagementService,
    pub state: SkillStateStore,
    pub revisions: SkillRevisionStore,
    pub storage: Storage,
    pub data_root: PathBuf,
    pub cache_root: PathBuf,
    pub database_path: PathBuf,
}

impl std::fmt::Debug for TenantSkillRuntime {
    fn fmt(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        formatter
            .debug_struct("TenantSkillRuntime")
            .field("tenant_id", &self.tenant_id)
            .field("data_root", &self.data_root)
            .field("cache_root", &self.cache_root)
            .field("database_path", &self.database_path)
            .finish_non_exhaustive()
    }
}

#[async_trait::async_trait]
pub trait TenantSkillManagerFactory: Send + Sync {
    async fn create(&self, tenant_id: &str) -> anyhow::Result<TenantSkillRuntime>;
}

#[derive(Clone)]
pub struct TenantSkillManagerRegistry {
    managers: TenantManagerCells,
    factory: Arc<dyn TenantSkillManagerFactory>,
}

struct TenantManagerEntry {
    runtime: OnceCell<Arc<TenantSkillRuntime>>,
    status: Mutex<TenantManagerStatus>,
    notify: Notify,
}

enum TenantManagerStatus {
    Initializing,
    Failed,
}

impl TenantManagerEntry {
    fn new() -> Self {
        Self {
            runtime: OnceCell::new(),
            status: Mutex::new(TenantManagerStatus::Initializing),
            notify: Notify::new(),
        }
    }
}

type TenantManagerCell = Arc<TenantManagerEntry>;
type TenantManagerCells = Arc<Mutex<HashMap<String, TenantManagerCell>>>;

impl TenantSkillManagerRegistry {
    pub fn new(factory: impl TenantSkillManagerFactory + 'static) -> Self {
        Self {
            managers: Arc::new(Mutex::new(HashMap::new())),
            factory: Arc::new(factory),
        }
    }

    pub async fn for_tenant(&self, tenant_id: &str) -> anyhow::Result<Arc<TenantSkillRuntime>> {
        let tenant_id = validate_tenant_id(tenant_id)?;
        let (cell, initialize) = {
            let mut managers = self
                .managers
                .lock()
                .expect("tenant skill registry lock poisoned");
            if let Some(cell) = managers.get(&tenant_id) {
                (cell.clone(), false)
            } else {
                let cell = Arc::new(TenantManagerEntry::new());
                managers.insert(tenant_id.clone(), cell.clone());
                (cell, true)
            }
        };
        if initialize {
            self.spawn_initialization(tenant_id, cell.clone());
        }
        loop {
            let notified = cell.notify.notified();
            if let Some(runtime) = cell.runtime.get() {
                return Ok(runtime.clone());
            }
            if matches!(
                *cell
                    .status
                    .lock()
                    .expect("tenant manager entry lock poisoned"),
                TenantManagerStatus::Failed
            ) {
                anyhow::bail!("tenant skill manager initialization failed");
            }
            notified.await;
        }
    }

    fn spawn_initialization(&self, tenant_id: String, cell: TenantManagerCell) {
        let registry = self.clone();
        tokio::spawn(async move {
            match registry.factory.create(&tenant_id).await {
                Ok(runtime) => {
                    let published = cell.runtime.set(Arc::new(runtime)).is_ok();
                    debug_assert!(published, "tenant runtime initialized more than once");
                }
                Err(_) => {
                    *cell
                        .status
                        .lock()
                        .expect("tenant manager entry lock poisoned") = TenantManagerStatus::Failed;
                    let mut managers = registry
                        .managers
                        .lock()
                        .expect("tenant skill registry lock poisoned");
                    if managers
                        .get(&tenant_id)
                        .is_some_and(|current| Arc::ptr_eq(current, &cell))
                    {
                        managers.remove(&tenant_id);
                    }
                }
            }
            cell.notify.notify_waiters();
        });
    }

    pub fn manager_count(&self) -> usize {
        self.managers
            .lock()
            .expect("tenant skill registry lock poisoned")
            .values()
            .filter(|cell| cell.runtime.get().is_some())
            .count()
    }

    pub fn entry_count(&self) -> usize {
        self.managers
            .lock()
            .expect("tenant skill registry lock poisoned")
            .len()
    }
}

pub fn validate_tenant_id(value: &str) -> anyhow::Result<String> {
    let bytes = value.as_bytes();
    let canonical = !bytes.is_empty()
        && bytes.len() <= 63
        && canonical_tenant_byte(bytes[0])
        && canonical_tenant_byte(bytes[bytes.len() - 1])
        && bytes
            .iter()
            .all(|byte| canonical_tenant_byte(*byte) || *byte == b'-');
    if !canonical {
        anyhow::bail!("tenant id must be canonical lowercase ASCII");
    }
    Ok(value.to_string())
}

fn canonical_tenant_byte(byte: u8) -> bool {
    byte.is_ascii_lowercase() || byte.is_ascii_digit()
}

#[derive(Clone)]
pub struct TenantSkillManagerConfig {
    pub data_root: PathBuf,
    pub cache_root: PathBuf,
    pub sources: Vec<Arc<dyn SkillSource>>,
    pub platform: PlatformId,
    pub capabilities: CapabilitySet,
    pub protected_packages: Vec<SkillPackageId>,
    pub allowed_overrides: Vec<SkillPackageId>,
    pub runtime_version: Version,
    pub management_policy: SkillManagementPolicy,
}

#[derive(Clone)]
pub struct FilesystemTenantSkillManagerFactory {
    config: TenantSkillManagerConfig,
    data_tenants: PathBuf,
    cache_tenants: PathBuf,
    initialization_locks: PathBuf,
    initialization_quarantine: PathBuf,
    #[cfg(test)]
    fail_migration_once: Arc<std::sync::atomic::AtomicBool>,
}

impl FilesystemTenantSkillManagerFactory {
    pub async fn new(mut config: TenantSkillManagerConfig) -> anyhow::Result<Self> {
        config.data_root = prepare_real_directory(&config.data_root).await?;
        config.cache_root = prepare_real_directory(&config.cache_root).await?;
        let data_tenants = prepare_real_directory(&config.data_root.join("tenants")).await?;
        let cache_tenants = prepare_real_directory(&config.cache_root.join("tenants")).await?;
        let initialization_locks =
            prepare_real_directory(&data_tenants.join(".initialization-locks")).await?;
        let initialization_quarantine =
            prepare_real_directory(&data_tenants.join(".initialization-quarantine")).await?;
        Ok(Self {
            config,
            data_tenants,
            cache_tenants,
            initialization_locks,
            initialization_quarantine,
            #[cfg(test)]
            fail_migration_once: Arc::new(std::sync::atomic::AtomicBool::new(false)),
        })
    }

    #[cfg(test)]
    pub(crate) fn with_migration_failure_once_for_test(self) -> Self {
        self.fail_migration_once
            .store(true, std::sync::atomic::Ordering::Release);
        self
    }
}

#[async_trait::async_trait]
impl TenantSkillManagerFactory for FilesystemTenantSkillManagerFactory {
    async fn create(&self, tenant_id: &str) -> anyhow::Result<TenantSkillRuntime> {
        let tenant_id = validate_tenant_id(tenant_id)?;
        let _initialization_lock =
            acquire_tenant_initialization_lock(&self.initialization_locks, &tenant_id)
                .await
                .context("tenant initialization lock failed")?;
        let mut cleanup = TenantInitializationPaths::capture(
            self.initialization_locks.clone(),
            self.initialization_quarantine.clone(),
            &tenant_id,
            &self.data_tenants,
            &self.cache_tenants,
        )
        .await
        .context("tenant initialization ownership capture failed")?;
        let result = self.create_runtime(tenant_id, &mut cleanup).await;
        match result {
            Ok(runtime) => {
                if let Err(error) = cleanup.commit().await {
                    runtime.storage.close().await;
                    drop(runtime);
                    return match cleanup.cleanup().await {
                        Ok(()) => {
                            Err(error).context("tenant initialization ownership commit failed")
                        }
                        Err(cleanup_error) => Err(error).context(format!(
                            "tenant initialization commit failed and owned cleanup was retained: {cleanup_error}"
                        )),
                    };
                }
                Ok(runtime)
            }
            Err(error) => match cleanup.cleanup().await {
                Ok(()) => Err(error),
                Err(cleanup_error) => Err(error).context(format!(
                    "tenant runtime failed and owned cleanup was retained: {cleanup_error}"
                )),
            },
        }
    }
}

impl FilesystemTenantSkillManagerFactory {
    async fn create_runtime(
        &self,
        tenant_id: String,
        cleanup: &mut TenantInitializationPaths,
    ) -> anyhow::Result<TenantSkillRuntime> {
        let data_root = cleanup.data.path.clone();
        let cache_root = cleanup.cache.path.clone();
        let database_path = data_root.join("state.db");
        crate::data_protection::apply_pending_restore(&database_path)
            .await
            .context("tenant pending database restore failed")?;
        cleanup
            .prepare_database()
            .await
            .context("tenant database ownership preparation failed")?;
        reject_symlink_or_non_file_if_present(&database_path).await?;
        let storage = match Storage::connect_without_migrations(&format!(
            "sqlite://{}?mode=rwc",
            database_path.display()
        ))
        .await
        {
            Ok(storage) => storage,
            Err(error) => return Err(error).context("tenant storage connection failed"),
        };
        let cleanup_storage = storage.clone();
        let result = async {
            #[cfg(test)]
            if self
                .fail_migration_once
                .swap(false, std::sync::atomic::Ordering::AcqRel)
            {
                anyhow::bail!("injected tenant storage migration failure");
            }
            storage
                .run_migrations()
                .await
                .context("tenant storage migration failed")?;
            reject_symlink_or_non_file_if_present(&database_path).await?;
            ensure_parent_identity(&data_root, &database_path).await?;
            let state = SkillStateStore::new(storage.clone());
            cleanup
                .prepare_store_paths()
                .await
                .context("tenant skill store ownership preparation failed")?;
            let paths = SkillStorePaths::prepare(&data_root.join("app"), &cache_root.join("cache"))
                .await
                .context("tenant skill store preparation failed")?;
            let revisions = SkillRevisionStore::new(paths, state.clone());
            let mut sources = self.config.sources.clone();
            sources.push(Arc::new(ManagedSkillSource::from_store(revisions.clone())));
            let manager = SkillManager::new_deferred_managed(SkillManagerConfig {
                sources,
                platform: self.config.platform,
                capabilities: self.config.capabilities.clone(),
                protected_packages: self.config.protected_packages.clone(),
                allowed_overrides: self.config.allowed_overrides.clone(),
                runtime_version: self.config.runtime_version.clone(),
            })
            .await
            .context("tenant skill manager construction failed")?;
            let management = OwnerSkillManagementService::new(
                manager.clone(),
                revisions.clone(),
                state.clone(),
                self.config.management_policy.clone(),
            );
            manager
                .startup_reconcile()
                .await
                .context("tenant startup reconciliation failed")?;
            Ok(TenantSkillRuntime {
                tenant_id,
                manager,
                management,
                state,
                revisions,
                storage,
                data_root,
                cache_root,
                database_path,
            })
        }
        .await;
        if result.is_err() {
            cleanup_storage.close().await;
            #[cfg(test)]
            notify_cleanup_observer(cleanup_storage.is_closed());
        }
        result
    }
}

#[cfg(test)]
fn cleanup_observer()
-> &'static Mutex<std::collections::VecDeque<tokio::sync::oneshot::Sender<bool>>> {
    static OBSERVER: std::sync::OnceLock<
        Mutex<std::collections::VecDeque<tokio::sync::oneshot::Sender<bool>>>,
    > = std::sync::OnceLock::new();
    OBSERVER.get_or_init(|| Mutex::new(std::collections::VecDeque::new()))
}

#[cfg(test)]
pub(crate) fn install_cleanup_observer() -> tokio::sync::oneshot::Receiver<bool> {
    let (sender, receiver) = tokio::sync::oneshot::channel();
    cleanup_observer()
        .lock()
        .expect("tenant cleanup observer lock poisoned")
        .push_back(sender);
    receiver
}

#[cfg(test)]
fn notify_cleanup_observer(closed: bool) {
    if let Some(observer) = cleanup_observer()
        .lock()
        .expect("tenant cleanup observer lock poisoned")
        .pop_front()
    {
        let _ = observer.send(closed);
    }
}

async fn reject_symlink_or_non_file_if_present(path: &Path) -> anyhow::Result<()> {
    match tokio::fs::symlink_metadata(path).await {
        Ok(metadata) => anyhow::ensure!(
            metadata.is_file() && !metadata.file_type().is_symlink(),
            "tenant database path must be a real file"
        ),
        Err(error) if error.kind() == std::io::ErrorKind::NotFound => {}
        Err(error) => return Err(error.into()),
    }
    Ok(())
}

async fn ensure_parent_identity(parent: &Path, child: &Path) -> anyhow::Result<()> {
    let canonical_parent = tokio::fs::canonicalize(parent).await?;
    let actual_parent = child
        .parent()
        .ok_or_else(|| anyhow::anyhow!("tenant database has no parent"))?;
    anyhow::ensure!(
        tokio::fs::canonicalize(actual_parent).await? == canonical_parent,
        "tenant database parent changed during initialization"
    );
    Ok(())
}
