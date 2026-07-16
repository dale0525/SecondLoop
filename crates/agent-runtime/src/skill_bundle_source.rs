use super::{
    SKILL_BUNDLE_CURRENT_FILE, SKILL_BUNDLE_CURRENT_SCHEMA_VERSION, SKILL_BUNDLE_GENERATIONS_DIR,
    SKILL_BUNDLE_LOCK_FILE, SKILL_BUNDLE_MANIFEST_FILE, SKILL_BUNDLE_SCHEMA_VERSION,
    SkillBundleCurrent, SkillBundleGeneration, SkillBundleLock, SkillBundleManifest,
};
use crate::skill_package::{DescriptorSource, SkillCompatibility, SkillPackageDescriptor};
use crate::skill_source::{
    BundleExecutionBinding, BundleGenerationBinding, DiscoveredSkillPackage, SkillLayer,
    SkillSource, VerifiedPackageContent, canonical_relative_path,
};
use crate::skill_store::SkillStoreLimits;
use crate::skill_store_locks::StoreRootIdentity;
use crate::skill_store_operations::error_is_not_found;
use crate::skill_store_prepared_fs::{open_regular_file, open_replaceable_regular_file};
use crate::skill_store_secure_roots::{
    PreparedStoreDirectory, PreparedStoreUnknownKind, list_opened_child_directories,
    open_prepared_directory, opened_package_snapshot,
};
use anyhow::Context;
use async_trait::async_trait;
use sha2::{Digest, Sha256};
use std::collections::{BTreeMap, BTreeSet};
use std::path::{Path, PathBuf};
use std::sync::Arc;
#[cfg(test)]
use std::time::Duration;
use tokio::io::AsyncReadExt;

#[cfg(test)]
use std::sync::{Mutex, OnceLock};

#[cfg(all(test, unix))]
#[derive(Clone)]
pub(crate) struct BundleMetadataGate {
    entered: Arc<tokio::sync::Barrier>,
    release: Arc<tokio::sync::Barrier>,
}

#[cfg(all(test, unix))]
impl BundleMetadataGate {
    pub(crate) async fn wait_entered(&self) {
        wait_test_gate(&self.entered, "bundle metadata entry").await;
    }

    pub(crate) async fn release(&self) {
        wait_test_gate(&self.release, "bundle metadata release").await;
    }
}

#[cfg(all(test, unix))]
pub(crate) fn gate_bundle_metadata_after_inspection(path: &Path) -> BundleMetadataGate {
    let gate = BundleMetadataGate {
        entered: Arc::new(tokio::sync::Barrier::new(2)),
        release: Arc::new(tokio::sync::Barrier::new(2)),
    };
    metadata_gates()
        .lock()
        .unwrap()
        .insert(canonical_test_path(path), gate.clone());
    gate
}

#[cfg(all(test, unix))]
fn metadata_gates() -> &'static Mutex<BTreeMap<PathBuf, BundleMetadataGate>> {
    static GATES: OnceLock<Mutex<BTreeMap<PathBuf, BundleMetadataGate>>> = OnceLock::new();
    GATES.get_or_init(|| Mutex::new(BTreeMap::new()))
}

#[cfg(all(test, unix))]
async fn checkpoint_metadata_after_inspection(path: &Path) {
    let gate = metadata_gates()
        .lock()
        .unwrap()
        .remove(&canonical_test_path(path));
    if let Some(gate) = gate {
        wait_test_gate(&gate.entered, "bundle metadata checkpoint entry").await;
        wait_test_gate(&gate.release, "bundle metadata checkpoint release").await;
    }
}

#[cfg(not(all(test, unix)))]
async fn checkpoint_metadata_after_inspection(_path: &Path) {}

#[cfg(all(test, windows))]
#[derive(Clone)]
pub(crate) struct BundleCurrentReadGate {
    entered: Arc<tokio::sync::Barrier>,
    release: Arc<tokio::sync::Barrier>,
}

#[cfg(all(test, windows))]
impl BundleCurrentReadGate {
    pub(crate) async fn wait_entered(&self) {
        wait_test_gate(&self.entered, "bundle current read entry").await;
    }

    pub(crate) async fn release(&self) {
        wait_test_gate(&self.release, "bundle current read release").await;
    }
}

#[cfg(all(test, windows))]
pub(crate) fn gate_bundle_current_after_open(path: &Path) -> BundleCurrentReadGate {
    let gate = BundleCurrentReadGate {
        entered: Arc::new(tokio::sync::Barrier::new(2)),
        release: Arc::new(tokio::sync::Barrier::new(2)),
    };
    current_read_gates()
        .lock()
        .unwrap()
        .insert(canonical_test_path(path), gate.clone());
    gate
}

#[cfg(all(test, windows))]
fn current_read_gates() -> &'static Mutex<BTreeMap<PathBuf, BundleCurrentReadGate>> {
    static GATES: OnceLock<Mutex<BTreeMap<PathBuf, BundleCurrentReadGate>>> = OnceLock::new();
    GATES.get_or_init(|| Mutex::new(BTreeMap::new()))
}

#[cfg(test)]
fn canonical_test_path(path: &Path) -> PathBuf {
    let Some(parent) = path.parent() else {
        return path.to_path_buf();
    };
    std::fs::canonicalize(parent)
        .map(|parent| parent.join(path.file_name().unwrap_or_default()))
        .unwrap_or_else(|_| path.to_path_buf())
}

#[cfg(all(test, windows))]
async fn checkpoint_current_after_open(path: &Path) {
    let gate = current_read_gates()
        .lock()
        .unwrap()
        .remove(&canonical_test_path(path));
    if let Some(gate) = gate {
        wait_test_gate(&gate.entered, "bundle current checkpoint entry").await;
        wait_test_gate(&gate.release, "bundle current checkpoint release").await;
    }
}

#[cfg(not(all(test, windows)))]
async fn checkpoint_current_after_open(_path: &Path) {}

#[cfg(test)]
#[derive(Clone)]
pub(crate) struct BundleCurrentReadCompleteGate {
    entered: Arc<tokio::sync::Barrier>,
    release: Arc<tokio::sync::Barrier>,
}

#[cfg(test)]
impl BundleCurrentReadCompleteGate {
    pub(crate) async fn wait_entered(&self) {
        wait_test_gate(&self.entered, "bundle current complete-read entry").await;
    }

    pub(crate) async fn release(&self) {
        wait_test_gate(&self.release, "bundle current complete-read release").await;
    }
}

#[cfg(test)]
struct PendingCurrentReadGate {
    remaining_reads: usize,
    gate: BundleCurrentReadCompleteGate,
}

#[cfg(test)]
pub(crate) fn gate_bundle_current_after_read(
    path: &Path,
    skip_reads: usize,
) -> BundleCurrentReadCompleteGate {
    let gate = BundleCurrentReadCompleteGate {
        entered: Arc::new(tokio::sync::Barrier::new(2)),
        release: Arc::new(tokio::sync::Barrier::new(2)),
    };
    complete_current_read_gates().lock().unwrap().insert(
        canonical_test_path(path),
        PendingCurrentReadGate {
            remaining_reads: skip_reads,
            gate: gate.clone(),
        },
    );
    gate
}

#[cfg(test)]
fn complete_current_read_gates() -> &'static Mutex<BTreeMap<PathBuf, PendingCurrentReadGate>> {
    static GATES: OnceLock<Mutex<BTreeMap<PathBuf, PendingCurrentReadGate>>> = OnceLock::new();
    GATES.get_or_init(|| Mutex::new(BTreeMap::new()))
}

#[cfg(test)]
async fn checkpoint_current_after_read(path: &Path) {
    let key = canonical_test_path(path);
    let gate = {
        let mut gates = complete_current_read_gates().lock().unwrap();
        let Some(pending) = gates.get_mut(&key) else {
            return;
        };
        if pending.remaining_reads > 0 {
            pending.remaining_reads -= 1;
            return;
        }
        gates.remove(&key).map(|pending| pending.gate)
    };
    if let Some(gate) = gate {
        wait_test_gate(
            &gate.entered,
            "bundle current complete-read checkpoint entry",
        )
        .await;
        wait_test_gate(
            &gate.release,
            "bundle current complete-read checkpoint release",
        )
        .await;
    }
}

#[cfg(not(test))]
async fn checkpoint_current_after_read(_path: &Path) {}

#[cfg(test)]
#[derive(Clone)]
pub(crate) struct BundleDiscoveryGate {
    entered: Arc<tokio::sync::Barrier>,
    release: Arc<tokio::sync::Barrier>,
}

#[cfg(test)]
impl BundleDiscoveryGate {
    pub(crate) async fn wait_entered(&self) {
        wait_test_gate(&self.entered, "bundle discovery entry").await;
    }

    pub(crate) async fn release(&self) {
        wait_test_gate(&self.release, "bundle discovery release").await;
    }
}

#[cfg(test)]
pub(crate) fn gate_bundle_discovery_after_layout(generation: &Path) -> BundleDiscoveryGate {
    let gate = BundleDiscoveryGate {
        entered: Arc::new(tokio::sync::Barrier::new(2)),
        release: Arc::new(tokio::sync::Barrier::new(2)),
    };
    discovery_gates()
        .lock()
        .unwrap()
        .insert(canonical_test_path(generation), gate.clone());
    gate
}

#[cfg(test)]
fn discovery_gates() -> &'static Mutex<BTreeMap<PathBuf, BundleDiscoveryGate>> {
    static GATES: OnceLock<Mutex<BTreeMap<PathBuf, BundleDiscoveryGate>>> = OnceLock::new();
    GATES.get_or_init(|| Mutex::new(BTreeMap::new()))
}

#[cfg(test)]
async fn checkpoint_discovery_after_layout(generation: &Path) {
    let gate = discovery_gates()
        .lock()
        .unwrap()
        .remove(&canonical_test_path(generation));
    if let Some(gate) = gate {
        wait_test_gate(&gate.entered, "bundle discovery checkpoint entry").await;
        wait_test_gate(&gate.release, "bundle discovery checkpoint release").await;
    }
}

#[cfg(not(test))]
async fn checkpoint_discovery_after_layout(_generation: &Path) {}

#[cfg(test)]
async fn wait_test_gate(barrier: &tokio::sync::Barrier, label: &str) {
    tokio::time::timeout(Duration::from_secs(10), barrier.wait())
        .await
        .unwrap_or_else(|_| panic!("timed out waiting for {label}"));
}

#[derive(Clone, Debug)]
pub struct BundleSkillSource {
    root: PathBuf,
    root_identity: StoreRootIdentity,
    prepared_root: PreparedStoreDirectory,
}

impl BundleSkillSource {
    pub async fn open(root: impl Into<PathBuf>) -> anyhow::Result<Self> {
        let root = root.into();
        let metadata = tokio::fs::symlink_metadata(&root)
            .await
            .with_context(|| format!("failed to inspect bundle root {}", root.display()))?;
        anyhow::ensure!(
            metadata.is_dir() && !metadata.file_type().is_symlink(),
            "bundle root must be a real directory: {}",
            root.display()
        );
        let root = tokio::fs::canonicalize(&root).await?;
        let root_identity = StoreRootIdentity::capture(root.clone())?;
        let prepared_root = PreparedStoreDirectory::open(&root_identity, Path::new(""))?;
        let source = Self {
            root,
            root_identity,
            prepared_root,
        };
        source.load_current_packages().await?;
        Ok(source)
    }

    pub fn root(&self) -> &Path {
        &self.root
    }

    async fn load_current_packages(&self) -> anyhow::Result<Vec<DiscoveredSkillPackage>> {
        self.load_current_selection()
            .await
            .map(|(packages, _)| packages)
    }

    pub(crate) async fn current_generation(&self) -> anyhow::Result<Option<SkillBundleGeneration>> {
        self.load_current_selection()
            .await
            .map(|(_, generation)| generation)
    }

    async fn load_current_selection(
        &self,
    ) -> anyhow::Result<(Vec<DiscoveredSkillPackage>, Option<SkillBundleGeneration>)> {
        self.root_identity.verify("bundle")?;
        self.prepared_root.verify()?;
        let selection = match read_json::<SkillBundleCurrent>(
            &self.prepared_root,
            Path::new(SKILL_BUNDLE_CURRENT_FILE),
        )
        .await
        {
            Ok(current) => {
                anyhow::ensure!(
                    current.schema_version == SKILL_BUNDLE_CURRENT_SCHEMA_VERSION,
                    "unsupported skill bundle current schema version: {}",
                    current.schema_version
                );
                verify_generation_container(&self.prepared_root).await?;
                validate_generation_commitment(&current.active)?;
                if let Some(previous) = &current.previous {
                    validate_generation_commitment(previous)?;
                    anyhow::ensure!(
                        previous.generation != current.active.generation,
                        "bundle current active and previous generations must be distinct"
                    );
                }
                match self.load_committed_generation(&current.active).await {
                    Ok(packages) => (packages, Some(current.active)),
                    Err(active_error) => {
                        let previous = current.previous.context(format!(
                            "active bundle generation failed commitment validation: {active_error:#}; no last-known-good generation is recorded"
                        ))?;
                        let packages = self
                            .load_committed_generation(&previous)
                            .await
                            .map_err(|previous_error| {
                                anyhow::anyhow!(
                                    "active bundle generation failed commitment validation: {active_error:#}; previous last-known-good generation also failed validation: {previous_error:#}"
                                )
                            })?;
                        (packages, Some(previous))
                    }
                }
            }
            Err(error) if error_is_not_found(&error) => {
                if has_direct_bundle_evidence(&self.prepared_root).await? {
                    (
                        load_generation(&self.prepared_root, &self.root, None).await?,
                        None,
                    )
                } else {
                    return Err(error).context("bundle current marker is missing");
                }
            }
            Err(error) => return Err(error),
        };
        self.root_identity.verify("bundle")?;
        Ok(selection)
    }

    async fn load_committed_generation(
        &self,
        commitment: &SkillBundleGeneration,
    ) -> anyhow::Result<Vec<DiscoveredSkillPackage>> {
        let relative = PathBuf::from(SKILL_BUNDLE_GENERATIONS_DIR).join(&commitment.generation);
        let generation = open_prepared_directory(&self.root_identity, &relative)
            .await
            .with_context(|| {
                format!(
                    "failed to open committed bundle generation {}",
                    commitment.generation
                )
            })?;
        let packages = load_generation(&generation, &self.root, Some(commitment)).await?;
        generation.verify()?;
        Ok(packages)
    }
}

async fn load_generation(
    generation: &PreparedStoreDirectory,
    bundle_root: &Path,
    commitment: Option<&SkillBundleGeneration>,
) -> anyhow::Result<Vec<DiscoveredSkillPackage>> {
    let (manifest, manifest_bytes, manifest_identity): (SkillBundleManifest, _, _) =
        read_json_with_bytes(generation, Path::new(SKILL_BUNDLE_MANIFEST_FILE)).await?;
    let (lock, lock_bytes, lock_identity): (SkillBundleLock, _, _) =
        read_json_with_bytes(generation, Path::new(SKILL_BUNDLE_LOCK_FILE)).await?;
    if let Some(commitment) = commitment {
        anyhow::ensure!(
            metadata_sha256(&manifest_bytes) == commitment.manifest_sha256,
            "bundle manifest commitment mismatch for generation {}",
            commitment.generation
        );
        anyhow::ensure!(
            metadata_sha256(&lock_bytes) == commitment.lock_sha256,
            "bundle lock commitment mismatch for generation {}",
            commitment.generation
        );
    }
    anyhow::ensure!(
        manifest.schema_version == SKILL_BUNDLE_SCHEMA_VERSION,
        "unsupported skill bundle manifest schema version: {}",
        manifest.schema_version
    );
    anyhow::ensure!(
        lock.schema_version == SKILL_BUNDLE_SCHEMA_VERSION,
        "unsupported skill bundle lock schema version: {}",
        lock.schema_version
    );
    validate_canonical_order(&manifest, &lock)?;
    let manifest_by_id = unique_manifest_packages(&manifest)?;
    let lock_by_id = unique_lock_packages(&lock)?;
    anyhow::ensure!(
        manifest_by_id.keys().eq(lock_by_id.keys()),
        "bundle manifest and lock package sets do not match"
    );
    validate_dependency_closure(&lock_by_id)?;
    for package in &manifest.packages {
        validate_package_path(package)?;
    }
    let package_directories = verify_top_level_entries(generation, &manifest).await?;
    let generation_binding = Arc::new(BundleGenerationBinding {
        directory: generation.clone(),
        manifest_bytes: Arc::from(manifest_bytes),
        manifest_identity,
        lock_bytes: Arc::from(lock_bytes),
        lock_identity,
        package_directories: package_directories.clone(),
        package_hashes: manifest
            .packages
            .iter()
            .map(|package| {
                (
                    package.id.as_str().to_string(),
                    package.content_hash.clone(),
                )
            })
            .collect(),
    });
    checkpoint_discovery_after_layout(generation.path()).await;

    let mut packages = Vec::with_capacity(manifest.packages.len());
    for manifest_package in &manifest.packages {
        let locked = lock_by_id
            .get(&manifest_package.id)
            .context("bundle lock package is missing")?;
        anyhow::ensure!(
            manifest_package.version == locked.version
                && manifest_package.content_hash == locked.content_hash,
            "bundle manifest and lock disagree for {}",
            manifest_package.id.as_str()
        );
        let package_directory = package_directories
            .get(manifest_package.id.as_str())
            .context("bundle package directory is missing")?;
        let snapshot = opened_package_snapshot(
            package_directory,
            SkillStoreLimits::default().package_limits(),
        )
        .await?;
        anyhow::ensure!(
            snapshot.content_hash == locked.content_hash,
            "content hash mismatch for {}",
            manifest_package.id.as_str()
        );
        anyhow::ensure!(
            snapshot.descriptor.source == DescriptorSource::Explicit,
            "bundled package requires an explicit descriptor"
        );
        let expected = expected_descriptor(manifest_package, locked.dependencies.clone());
        let actual = canonical_descriptor(snapshot.descriptor.descriptor);
        anyhow::ensure!(
            actual == expected,
            "bundle descriptor does not match manifest and lock for {}",
            manifest_package.id.as_str()
        );
        let limits = SkillStoreLimits::default();
        packages.push(DiscoveredSkillPackage {
            layer: SkillLayer::Builtin,
            root: package_directory.path().to_path_buf(),
            descriptor: expected,
            content_hash: locked.content_hash.clone(),
            warnings: Vec::new(),
            verified_content: Some(VerifiedPackageContent {
                runtime_manifest: snapshot.runtime_manifest.map(Arc::from),
                instructions_file: snapshot.instructions_file.map(Arc::from),
                file_paths: Arc::new(snapshot.file_paths),
                expected_content_hash: locked.content_hash.clone(),
                limits,
                execution_binding: None,
                bundle_execution_binding: Some(BundleExecutionBinding {
                    directory: package_directory.clone(),
                    generation: generation_binding.clone(),
                    bundle_root: bundle_root.to_path_buf(),
                }),
            }),
        });
    }
    packages.sort_by(|left, right| left.descriptor.id.cmp(&right.descriptor.id));
    verify_bundle_generation_binding(&generation_binding).await?;
    Ok(packages)
}

fn validate_generation_commitment(commitment: &SkillBundleGeneration) -> anyhow::Result<()> {
    validate_generation_id(&commitment.generation)?;
    for (label, hash) in [
        ("manifest", commitment.manifest_sha256.as_str()),
        ("lock", commitment.lock_sha256.as_str()),
    ] {
        anyhow::ensure!(
            hash.len() == 64 && hash.bytes().all(|byte| byte.is_ascii_hexdigit()),
            "bundle current {label} commitment must be a SHA-256 hex digest"
        );
        anyhow::ensure!(
            hash.bytes().all(|byte| !byte.is_ascii_uppercase()),
            "bundle current {label} commitment must use canonical lowercase hex"
        );
    }
    Ok(())
}

pub(super) fn metadata_sha256(bytes: &[u8]) -> String {
    hex::encode(Sha256::digest(bytes))
}

fn validate_canonical_order(
    manifest: &SkillBundleManifest,
    lock: &SkillBundleLock,
) -> anyhow::Result<()> {
    anyhow::ensure!(
        manifest
            .packages
            .windows(2)
            .all(|items| items[0].id < items[1].id),
        "bundle manifest packages must be sorted and unique"
    );
    anyhow::ensure!(
        lock.packages
            .windows(2)
            .all(|items| items[0].id < items[1].id),
        "bundle lock packages must be sorted and unique"
    );
    for package in &manifest.packages {
        ensure_sorted_unique(&package.platforms, "platforms", package.id.as_str())?;
        ensure_sorted_unique(&package.capabilities, "capabilities", package.id.as_str())?;
        ensure_sorted_unique(&package.runtime_tools, "runtime tools", package.id.as_str())?;
        ensure_sorted_unique(&package.connectors, "connectors", package.id.as_str())?;
    }
    for package in &lock.packages {
        anyhow::ensure!(
            package
                .dependencies
                .windows(2)
                .all(|items| items[0] < items[1]),
            "bundle lock dependencies must be sorted and unique for {}",
            package.id.as_str()
        );
    }
    Ok(())
}

fn ensure_sorted_unique(values: &[String], label: &str, package_id: &str) -> anyhow::Result<()> {
    anyhow::ensure!(
        values.windows(2).all(|items| items[0] < items[1]),
        "bundle manifest {label} must be sorted and unique for {package_id}"
    );
    Ok(())
}

#[async_trait]
impl SkillSource for BundleSkillSource {
    fn layer(&self) -> SkillLayer {
        SkillLayer::Builtin
    }

    async fn discover(&self) -> anyhow::Result<Vec<DiscoveredSkillPackage>> {
        self.load_current_packages().await
    }
}

async fn read_json<T: serde::de::DeserializeOwned>(
    root: &PreparedStoreDirectory,
    relative: &Path,
) -> anyhow::Result<T> {
    read_json_with_bytes(root, relative)
        .await
        .map(|(value, _, _)| value)
}

async fn read_json_with_bytes<T: serde::de::DeserializeOwned>(
    root: &PreparedStoreDirectory,
    relative: &Path,
) -> anyhow::Result<(T, Vec<u8>, Arc<same_file::Handle>)> {
    let (bytes, identity) = read_metadata_bytes(root, relative).await?;
    let value = serde_json::from_slice(&bytes).with_context(|| {
        format!(
            "failed to parse bundle metadata {}",
            root.path().join(relative).display()
        )
    })?;
    Ok((value, bytes, identity))
}

async fn read_metadata_bytes(
    root: &PreparedStoreDirectory,
    relative: &Path,
) -> anyhow::Result<(Vec<u8>, Arc<same_file::Handle>)> {
    root.verify()?;
    let path = root.path().join(relative);
    checkpoint_metadata_after_inspection(&path).await;
    let opened = if relative == Path::new(SKILL_BUNDLE_CURRENT_FILE) {
        open_replaceable_regular_file(root, relative).await
    } else {
        open_regular_file(root, relative).await
    };
    let (file, expected_bytes, _) =
        opened.with_context(|| format!("failed to open bundle metadata {}", path.display()))?;
    let identity = Arc::new(same_file::Handle::from_file(
        file.try_clone().await?.into_std().await,
    )?);
    if relative == Path::new(SKILL_BUNDLE_CURRENT_FILE) {
        checkpoint_current_after_open(&path).await;
    }
    let limits = SkillStoreLimits::default();
    anyhow::ensure!(
        expected_bytes <= limits.max_file_bytes,
        "bundle metadata exceeds {} byte limit: {}",
        limits.max_file_bytes,
        path.display()
    );
    let mut bytes = Vec::with_capacity(usize::try_from(expected_bytes)?);
    file.take(limits.max_file_bytes + 1)
        .read_to_end(&mut bytes)
        .await
        .with_context(|| format!("failed to read bundle metadata {}", path.display()))?;
    anyhow::ensure!(
        u64::try_from(bytes.len())? == expected_bytes,
        "bundle metadata changed while reading: {}",
        path.display()
    );
    if relative == Path::new(SKILL_BUNDLE_CURRENT_FILE) {
        checkpoint_current_after_read(&path).await;
    }
    root.verify()?;
    Ok((bytes, identity))
}

pub(crate) async fn verify_bundle_generation_binding(
    binding: &BundleGenerationBinding,
) -> anyhow::Result<()> {
    binding.directory.verify()?;
    verify_bound_top_level_entries(binding).await?;
    let (manifest_bytes, manifest_identity) =
        read_metadata_bytes(&binding.directory, Path::new(SKILL_BUNDLE_MANIFEST_FILE)).await?;
    anyhow::ensure!(
        manifest_identity.as_ref() == binding.manifest_identity.as_ref()
            && manifest_bytes == binding.manifest_bytes.as_ref(),
        "bundle manifest identity or bytes changed after verification"
    );
    let (lock_bytes, lock_identity) =
        read_metadata_bytes(&binding.directory, Path::new(SKILL_BUNDLE_LOCK_FILE)).await?;
    anyhow::ensure!(
        lock_identity.as_ref() == binding.lock_identity.as_ref()
            && lock_bytes == binding.lock_bytes.as_ref(),
        "bundle lock identity or bytes changed after verification"
    );
    for (id, directory) in &binding.package_directories {
        directory.verify()?;
        let snapshot =
            opened_package_snapshot(directory, SkillStoreLimits::default().package_limits())
                .await?;
        anyhow::ensure!(
            binding.package_hashes.get(id) == Some(&snapshot.content_hash),
            "content hash mismatch for {id}"
        );
        directory.verify()?;
    }
    verify_bound_top_level_entries(binding).await?;
    binding.directory.verify()
}

async fn verify_bound_top_level_entries(binding: &BundleGenerationBinding) -> anyhow::Result<()> {
    let listing = list_opened_child_directories(&binding.directory, 4096).await?;
    anyhow::ensure!(
        !listing.exceeded,
        "bundle contains too many top-level entries"
    );
    let actual_packages = listing
        .children
        .iter()
        .map(|child| child.name.as_str())
        .collect::<BTreeSet<_>>();
    let expected_packages = binding
        .package_directories
        .keys()
        .map(String::as_str)
        .collect::<BTreeSet<_>>();
    anyhow::ensure!(
        actual_packages == expected_packages,
        "bundle contains unlocked content"
    );
    let actual_metadata = listing
        .unknown
        .iter()
        .filter(|entry| entry.kind == PreparedStoreUnknownKind::RegularFile)
        .map(|entry| entry.name.as_str())
        .collect::<BTreeSet<_>>();
    let expected_metadata = BTreeSet::from([SKILL_BUNDLE_MANIFEST_FILE, SKILL_BUNDLE_LOCK_FILE]);
    anyhow::ensure!(
        listing.unknown.len() == expected_metadata.len() && actual_metadata == expected_metadata,
        "bundle contains unlocked content"
    );
    for directory in binding.package_directories.values() {
        directory.verify()?;
    }
    Ok(())
}

fn unique_manifest_packages(
    manifest: &SkillBundleManifest,
) -> anyhow::Result<BTreeMap<&crate::skill_package::SkillPackageId, &super::SkillBundlePackage>> {
    let mut by_id = BTreeMap::new();
    let mut paths = BTreeSet::new();
    for package in &manifest.packages {
        anyhow::ensure!(
            by_id.insert(&package.id, package).is_none(),
            "duplicate package id in bundle manifest: {}",
            package.id.as_str()
        );
        anyhow::ensure!(
            paths.insert(&package.path),
            "duplicate package path in bundle manifest: {}",
            package.path.display()
        );
    }
    Ok(by_id)
}

fn unique_lock_packages(
    lock: &SkillBundleLock,
) -> anyhow::Result<BTreeMap<&crate::skill_package::SkillPackageId, &super::SkillBundleLockPackage>>
{
    let mut by_id = BTreeMap::new();
    for package in &lock.packages {
        anyhow::ensure!(
            by_id.insert(&package.id, package).is_none(),
            "duplicate package id in bundle lock: {}",
            package.id.as_str()
        );
        anyhow::ensure!(
            package.dependencies.windows(2).all(|ids| ids[0] < ids[1]),
            "bundle lock dependencies must be sorted and unique for {}",
            package.id.as_str()
        );
    }
    Ok(by_id)
}

fn validate_dependency_closure(
    lock_by_id: &BTreeMap<&crate::skill_package::SkillPackageId, &super::SkillBundleLockPackage>,
) -> anyhow::Result<()> {
    for package in lock_by_id.values() {
        for dependency in &package.dependencies {
            anyhow::ensure!(
                lock_by_id.contains_key(dependency),
                "bundle lock dependency is missing from locked set for {}: {}",
                package.id.as_str(),
                dependency.as_str()
            );
        }
    }
    Ok(())
}

fn validate_package_path(package: &super::SkillBundlePackage) -> anyhow::Result<()> {
    canonical_relative_path(&package.path)?;
    anyhow::ensure!(
        package.path == Path::new(package.id.as_str()) && package.path.components().count() == 1,
        "bundle package path must equal package id: {}",
        package.path.display()
    );
    Ok(())
}

async fn verify_top_level_entries(
    root: &PreparedStoreDirectory,
    manifest: &SkillBundleManifest,
) -> anyhow::Result<BTreeMap<String, PreparedStoreDirectory>> {
    let mut expected = manifest
        .packages
        .iter()
        .map(|package| package.id.as_str().to_string())
        .collect::<BTreeSet<_>>();
    let listing = list_opened_child_directories(root, 4096).await?;
    anyhow::ensure!(
        !listing.exceeded,
        "bundle contains too many top-level entries"
    );
    let mut directories = BTreeMap::new();
    for child in listing.children {
        anyhow::ensure!(
            expected.remove(&child.name),
            "bundle contains unlocked content: {}",
            child.name
        );
        directories.insert(child.name, child.directory);
    }
    let mut metadata = BTreeSet::from([
        SKILL_BUNDLE_MANIFEST_FILE.to_string(),
        SKILL_BUNDLE_LOCK_FILE.to_string(),
    ]);
    for unknown in listing.unknown {
        anyhow::ensure!(
            unknown.kind == PreparedStoreUnknownKind::RegularFile && metadata.remove(&unknown.name),
            "bundle contains unlocked content: {}",
            unknown.name
        );
    }
    anyhow::ensure!(
        expected.is_empty() && metadata.is_empty(),
        "bundle is missing locked content"
    );
    Ok(directories)
}

fn validate_generation_id(generation: &str) -> anyhow::Result<()> {
    let parsed = uuid::Uuid::parse_str(generation)
        .with_context(|| format!("invalid bundle generation id: {generation}"))?;
    anyhow::ensure!(
        parsed.to_string() == generation,
        "bundle generation id is not canonical: {generation}"
    );
    Ok(())
}

async fn verify_generation_container(root: &PreparedStoreDirectory) -> anyhow::Result<()> {
    let listing = list_opened_child_directories(root, 4096).await?;
    anyhow::ensure!(!listing.exceeded, "bundle container has too many entries");
    anyhow::ensure!(
        listing.children.len() == 1 && listing.children[0].name == SKILL_BUNDLE_GENERATIONS_DIR,
        "bundle container layout is invalid"
    );
    verify_generation_store(&listing.children[0].directory).await?;
    let mut has_current = false;
    for unknown in listing.unknown {
        if unknown.name == SKILL_BUNDLE_CURRENT_FILE
            && unknown.kind == PreparedStoreUnknownKind::RegularFile
        {
            has_current = true;
            continue;
        }
        let is_atomic_temporary = unknown.kind == PreparedStoreUnknownKind::RegularFile
            && unknown.name.starts_with(".skill-write-")
            && unknown.name.ends_with(".tmp");
        anyhow::ensure!(
            is_atomic_temporary,
            "bundle container contains unlocked content: {}",
            unknown.name
        );
    }
    anyhow::ensure!(has_current, "bundle current marker is missing");
    Ok(())
}

async fn verify_generation_store(store: &PreparedStoreDirectory) -> anyhow::Result<()> {
    let listing = list_opened_child_directories(store, 4096).await?;
    anyhow::ensure!(
        !listing.exceeded,
        "bundle generation store contains too many entries"
    );
    anyhow::ensure!(
        listing.unknown.is_empty(),
        "bundle generation store contains unlocked generation content"
    );
    for child in listing.children {
        validate_generation_id(&child.name).with_context(|| {
            format!(
                "bundle generation store contains unlocked generation: {}",
                child.name
            )
        })?;
    }
    Ok(())
}

async fn has_direct_bundle_evidence(root: &PreparedStoreDirectory) -> anyhow::Result<bool> {
    root.verify()?;
    let manifest = tokio::fs::symlink_metadata(root.path().join(SKILL_BUNDLE_MANIFEST_FILE)).await;
    let lock = tokio::fs::symlink_metadata(root.path().join(SKILL_BUNDLE_LOCK_FILE)).await;
    root.verify()?;
    Ok(manifest.is_ok() || lock.is_ok())
}

fn expected_descriptor(
    package: &super::SkillBundlePackage,
    dependencies: Vec<crate::skill_package::SkillPackageId>,
) -> SkillPackageDescriptor {
    SkillPackageDescriptor {
        schema_version: crate::skill_package::SKILL_PACKAGE_SCHEMA_VERSION,
        id: package.id.clone(),
        version: package.version.clone(),
        display_name: package.display_name.clone(),
        kind: package.kind,
        package: package.targets(),
        compatibility: SkillCompatibility {
            minimum_runtime_version: package.minimum_runtime_version.clone(),
            platforms: package.platforms.clone(),
        },
        requires: package.requirements(dependencies),
    }
}

fn canonical_descriptor(mut descriptor: SkillPackageDescriptor) -> SkillPackageDescriptor {
    sort_dedup(&mut descriptor.compatibility.platforms);
    descriptor.requires.packages.sort();
    descriptor.requires.packages.dedup();
    sort_dedup(&mut descriptor.requires.capabilities);
    sort_dedup(&mut descriptor.requires.runtime_tools);
    sort_dedup(&mut descriptor.requires.connectors);
    descriptor
}

fn sort_dedup(values: &mut Vec<String>) {
    values.sort();
    values.dedup();
}
