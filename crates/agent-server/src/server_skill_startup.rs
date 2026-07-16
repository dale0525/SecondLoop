use agent_runtime::{
    platform::{CapabilitySet, PlatformId},
    skill_bundle::{
        BundleSkillSource, SKILL_BUNDLE_CURRENT_FILE, SKILL_BUNDLE_GENERATIONS_DIR,
        SKILL_BUNDLE_LOCK_FILE, SKILL_BUNDLE_MANIFEST_FILE,
    },
    skill_manager::{SkillManager, SkillManagerConfig},
    skill_source::{DirectorySkillSource, ManagedSkillSource, SkillLayer, SkillSource},
    skill_state::SkillStateStore,
    skill_store::{SkillRevisionStore, SkillStorePaths},
    storage::Storage,
};
use std::path::{Path, PathBuf};
use std::sync::Arc;

#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub(super) enum BuiltinSkillsMode {
    #[default]
    Auto,
    Directory,
    Bundle,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub(super) struct ManagedSkillsConfig {
    pub(super) app_data_root: PathBuf,
    pub(super) cache_root: PathBuf,
}

pub(super) struct LoadedSkillManager {
    pub(super) manager: SkillManager,
    pub(super) managed_store: Option<SkillRevisionStore>,
    #[cfg(test)]
    pub(super) managed_source: Option<ManagedSkillSource>,
}

impl LoadedSkillManager {
    pub(super) fn control_roots(&self, builtin_root: &Path) -> Vec<PathBuf> {
        let mut roots = vec![builtin_root.to_path_buf()];
        if let Some(store) = &self.managed_store {
            roots.extend([
                store.paths().managed.clone(),
                store.paths().staging.clone(),
                store.paths().quarantine.clone(),
            ]);
        }
        roots
    }
}

pub(super) fn managed_skills_config_from_lookup<F>(
    lookup: F,
) -> anyhow::Result<Option<ManagedSkillsConfig>>
where
    F: Fn(&str) -> Option<std::ffi::OsString>,
{
    if lookup("AGENTWEAVE_MANAGED_SKILLS").as_deref() != Some(std::ffi::OsStr::new("1")) {
        return Ok(None);
    }
    let required_root = |name: &str| -> anyhow::Result<PathBuf> {
        let value = lookup(name).ok_or_else(|| {
            anyhow::anyhow!("{name} is required when AGENTWEAVE_MANAGED_SKILLS=1")
        })?;
        if value.is_empty() {
            anyhow::bail!("{name} cannot be empty when AGENTWEAVE_MANAGED_SKILLS=1");
        }
        Ok(PathBuf::from(value))
    };
    Ok(Some(ManagedSkillsConfig {
        app_data_root: required_root("AGENTWEAVE_APP_DATA_ROOT")?,
        cache_root: required_root("AGENTWEAVE_CACHE_ROOT")?,
    }))
}

pub(super) fn builtin_skills_mode_from_lookup<F>(lookup: F) -> anyhow::Result<BuiltinSkillsMode>
where
    F: Fn(&str) -> Option<std::ffi::OsString>,
{
    let Some(value) = lookup("AGENTWEAVE_BUILTIN_SKILLS_MODE") else {
        return Ok(BuiltinSkillsMode::Auto);
    };
    let value = value
        .into_string()
        .map_err(|_| anyhow::anyhow!("AGENTWEAVE_BUILTIN_SKILLS_MODE must be valid UTF-8"))?;
    match value.as_str() {
        "auto" => Ok(BuiltinSkillsMode::Auto),
        "directory" => Ok(BuiltinSkillsMode::Directory),
        "bundle" => Ok(BuiltinSkillsMode::Bundle),
        _ => anyhow::bail!("AGENTWEAVE_BUILTIN_SKILLS_MODE must be auto, directory, or bundle"),
    }
}

#[cfg(test)]
pub(super) async fn load_skill_manager(
    root: &Path,
    storage: Storage,
    managed_config: Option<ManagedSkillsConfig>,
) -> anyhow::Result<LoadedSkillManager> {
    load_skill_manager_with_mode(root, storage, managed_config, BuiltinSkillsMode::Auto).await
}

pub(super) async fn load_skill_manager_with_mode(
    root: &Path,
    storage: Storage,
    managed_config: Option<ManagedSkillsConfig>,
    builtin_mode: BuiltinSkillsMode,
) -> anyhow::Result<LoadedSkillManager> {
    let deferred_managed_startup = managed_config.is_some();
    let builtin = load_builtin_skill_source(root, builtin_mode).await?;
    let mut sources = vec![builtin];
    if let Some(app_packages) = load_app_package_source_from_env().await? {
        sources.push(app_packages);
    }
    let mut managed_store = None;
    #[cfg(test)]
    let mut managed_source = None;
    if let Some(config) = managed_config {
        let paths = SkillStorePaths::prepare(&config.app_data_root, &config.cache_root).await?;
        let store = SkillRevisionStore::new(paths, SkillStateStore::new(storage));
        let source = ManagedSkillSource::from_store(store.clone());
        sources.push(Arc::new(source.clone()));
        managed_store = Some(store);
        #[cfg(test)]
        {
            managed_source = Some(source);
        }
    }
    let config = SkillManagerConfig {
        sources,
        platform: PlatformId::Desktop,
        capabilities: CapabilitySet::desktop_runtime(),
        protected_packages: Vec::new(),
        allowed_overrides: Vec::new(),
        runtime_version: env!("CARGO_PKG_VERSION").parse()?,
    };
    let manager = if deferred_managed_startup {
        SkillManager::new_deferred_managed(config).await?
    } else {
        SkillManager::new(config).await?
    };
    Ok(LoadedSkillManager {
        manager,
        managed_store,
        #[cfg(test)]
        managed_source,
    })
}

pub(super) async fn load_app_package_source_from_env()
-> anyhow::Result<Option<Arc<dyn SkillSource>>> {
    let Some(packages) = app_packages_root_from_lookup(|name| std::env::var_os(name))? else {
        return Ok(None);
    };
    match tokio::fs::symlink_metadata(&packages).await {
        Ok(metadata) => anyhow::ensure!(
            metadata.is_dir() && !metadata.file_type().is_symlink(),
            "Agent App packages root must be a real directory"
        ),
        Err(error) if error.kind() == std::io::ErrorKind::NotFound => return Ok(None),
        Err(error) => return Err(error.into()),
    }
    Ok(Some(Arc::new(DirectorySkillSource::new(
        SkillLayer::Session,
        packages,
    ))))
}

pub(super) fn app_packages_root_from_lookup<F>(lookup: F) -> anyhow::Result<Option<PathBuf>>
where
    F: Fn(&str) -> Option<std::ffi::OsString>,
{
    if let Some(root) = lookup("AGENTWEAVE_APP_PACKAGES_ROOT") {
        anyhow::ensure!(!root.is_empty(), "Agent App packages root cannot be empty");
        let root = PathBuf::from(root);
        anyhow::ensure!(
            root.is_absolute(),
            "Agent App packages root must be absolute"
        );
        return Ok(Some(root));
    }
    Ok(lookup("AGENTWEAVE_APP_ROOT").map(|root| PathBuf::from(root).join("packages")))
}

pub(super) async fn load_builtin_skill_source(
    root: &Path,
    builtin_mode: BuiltinSkillsMode,
) -> anyhow::Result<Arc<dyn SkillSource>> {
    let evidence = bundle_evidence(root).await?;
    let use_bundle = match builtin_mode {
        BuiltinSkillsMode::Bundle => true,
        BuiltinSkillsMode::Directory => {
            anyhow::ensure!(
                !evidence.any(),
                "builtin directory mode rejects bundle layout evidence"
            );
            false
        }
        BuiltinSkillsMode::Auto if evidence.generation_container => true,
        BuiltinSkillsMode::Auto if evidence.direct_metadata => {
            anyhow::bail!("direct bundle startup requires AGENTWEAVE_BUILTIN_SKILLS_MODE=bundle");
        }
        BuiltinSkillsMode::Auto => false,
    };
    Ok(if use_bundle {
        Arc::new(BundleSkillSource::open(root).await?)
    } else {
        Arc::new(DirectorySkillSource::new(SkillLayer::Builtin, root))
    })
}

#[derive(Clone, Copy, Debug, Default)]
struct BundleEvidence {
    direct_metadata: bool,
    generation_container: bool,
}

impl BundleEvidence {
    fn any(self) -> bool {
        self.direct_metadata || self.generation_container
    }
}

async fn bundle_evidence(root: &Path) -> anyhow::Result<BundleEvidence> {
    let mut evidence = BundleEvidence::default();
    for (entry, direct) in [
        (SKILL_BUNDLE_MANIFEST_FILE, true),
        (SKILL_BUNDLE_LOCK_FILE, true),
        (SKILL_BUNDLE_CURRENT_FILE, false),
        (SKILL_BUNDLE_GENERATIONS_DIR, false),
    ] {
        match tokio::fs::symlink_metadata(root.join(entry)).await {
            Ok(_) if direct => evidence.direct_metadata = true,
            Ok(_) => evidence.generation_container = true,
            Err(error) if error.kind() == std::io::ErrorKind::NotFound => {}
            Err(error) => return Err(error.into()),
        }
    }
    Ok(evidence)
}
