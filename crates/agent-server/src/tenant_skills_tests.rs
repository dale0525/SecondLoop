use crate::tenant_skills::{
    FilesystemTenantSkillManagerFactory, TenantSkillManagerConfig, TenantSkillManagerFactory,
    TenantSkillManagerRegistry, install_cleanup_observer,
};
use agent_runtime::platform::{CapabilitySet, PlatformId};
use agent_runtime::skill_policy::SkillManagementPolicy;
use agent_runtime::skill_source::{DiscoveredSkillPackage, SkillLayer, SkillSource};
use std::path::{Path, PathBuf};
use std::sync::Arc;
use std::time::{Duration, Instant};

#[tokio::test]
async fn post_connect_failure_closes_pool_before_cleanup() {
    let root = tempfile::tempdir().unwrap();
    let closed = install_cleanup_observer();
    let factory = FilesystemTenantSkillManagerFactory::new(config(
        root.path(),
        vec![Arc::new(FailingSource)],
    ))
    .await
    .unwrap();

    assert!(factory.create("close-order").await.is_err());

    assert!(closed.await.unwrap());
    assert!(!root.path().join("data/tenants/close-order").exists());
    assert!(!root.path().join("cache/tenants/close-order").exists());
}

#[tokio::test]
async fn fresh_migration_failure_closes_cleans_and_retries_immediately() {
    let root = tempfile::tempdir().unwrap();
    let closed = install_cleanup_observer();
    let factory = FilesystemTenantSkillManagerFactory::new(config(root.path(), Vec::new()))
        .await
        .unwrap()
        .with_migration_failure_once_for_test();

    assert!(factory.create("migration-retry").await.is_err());
    assert!(closed.await.unwrap());
    assert!(!root.path().join("data/tenants/migration-retry").exists());
    assert!(!root.path().join("cache/tenants/migration-retry").exists());

    let runtime = factory.create("migration-retry").await.unwrap();
    assert_eq!(runtime.manager.current_snapshot().generation(), 1);
}

#[tokio::test]
async fn cooperating_processes_serialize_all_tenant_initialization() {
    let root = tempfile::tempdir().unwrap();
    let marker = root.path().join("child-locked");
    let release = root.path().join("release-child");
    let mut child = tokio::process::Command::new(std::env::current_exe().unwrap())
        .arg("tenant_skills_tests::subprocess_holds_tenant_initialization_lock")
        .arg("--exact")
        .arg("--nocapture")
        .env("AGENTWEAVE_TEST_TENANT_ROOT", root.path())
        .env("AGENTWEAVE_TEST_TENANT_LOCKED", &marker)
        .env("AGENTWEAVE_TEST_TENANT_RELEASE", &release)
        .spawn()
        .unwrap();
    wait_for_path(&marker).await;

    let registry = TenantSkillManagerRegistry::new(
        FilesystemTenantSkillManagerFactory::new(config(root.path(), Vec::new()))
            .await
            .unwrap(),
    );
    let access = tokio::spawn(async move { registry.for_tenant("process-shared").await });
    tokio::time::sleep(Duration::from_millis(100)).await;
    assert!(!access.is_finished());

    tokio::fs::write(&release, b"release").await.unwrap();
    let output = child.wait().await.unwrap();
    assert!(output.success());
    assert_eq!(access.await.unwrap().unwrap().tenant_id, "process-shared");
}

#[tokio::test]
async fn subprocess_holds_tenant_initialization_lock() {
    let Some(root) = std::env::var_os("AGENTWEAVE_TEST_TENANT_ROOT") else {
        return;
    };
    let marker = PathBuf::from(std::env::var_os("AGENTWEAVE_TEST_TENANT_LOCKED").unwrap());
    let release = PathBuf::from(std::env::var_os("AGENTWEAVE_TEST_TENANT_RELEASE").unwrap());
    let factory = FilesystemTenantSkillManagerFactory::new(config(
        Path::new(&root),
        vec![Arc::new(ProcessBlockingSource { marker, release })],
    ))
    .await
    .unwrap();

    factory.create("process-shared").await.unwrap();
}

struct FailingSource;

#[async_trait::async_trait]
impl SkillSource for FailingSource {
    fn layer(&self) -> SkillLayer {
        SkillLayer::Builtin
    }

    async fn discover(&self) -> anyhow::Result<Vec<DiscoveredSkillPackage>> {
        anyhow::bail!("injected post-connect failure")
    }
}

struct ProcessBlockingSource {
    marker: PathBuf,
    release: PathBuf,
}

#[async_trait::async_trait]
impl SkillSource for ProcessBlockingSource {
    fn layer(&self) -> SkillLayer {
        SkillLayer::Builtin
    }

    async fn discover(&self) -> anyhow::Result<Vec<DiscoveredSkillPackage>> {
        tokio::fs::write(&self.marker, b"locked").await?;
        wait_for_path(&self.release).await;
        Ok(Vec::new())
    }
}

fn config(root: &Path, sources: Vec<Arc<dyn SkillSource>>) -> TenantSkillManagerConfig {
    TenantSkillManagerConfig {
        data_root: root.join("data"),
        cache_root: root.join("cache"),
        sources,
        platform: PlatformId::Server,
        capabilities: CapabilitySet::server_runtime(),
        protected_packages: Vec::new(),
        allowed_overrides: Vec::new(),
        runtime_version: "0.1.0".parse().unwrap(),
        management_policy: SkillManagementPolicy::owner_only(),
        storage_protection_key: None,
        credential_vault_key: None,
    }
}

#[tokio::test]
async fn tenant_storage_receives_protection_key_before_open() {
    let root = tempfile::tempdir().unwrap();
    let mut tenant_config = config(root.path(), Vec::new());
    tenant_config.storage_protection_key = Some(Arc::new(
        agent_runtime::credential::SecretMaterial::new(vec![4; 32]).unwrap(),
    ));
    let factory = FilesystemTenantSkillManagerFactory::new(tenant_config)
        .await
        .unwrap();
    let runtime = factory.create("protected").await.unwrap();
    assert_eq!(
        runtime.storage.protection_status().state(),
        agent_runtime::storage_protection::StorageProtectionState::Configured
    );
    runtime.storage.close().await;
    assert_eq!(
        &std::fs::read(runtime.database_path).unwrap()[..16],
        b"SQLite format 3\0"
    );
}

async fn wait_for_path(path: &Path) {
    let started = Instant::now();
    while !path.exists() {
        assert!(
            started.elapsed() < Duration::from_secs(10),
            "timed out waiting for path"
        );
        tokio::time::sleep(Duration::from_millis(10)).await;
    }
}
