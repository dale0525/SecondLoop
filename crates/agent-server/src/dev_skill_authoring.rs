use agent_runtime::{
    skill_catalog::SkillCatalog,
    skill_package::{SkillPackageDescriptor, SkillPackageKind, read_package_regular_file_nofollow},
};
use anyhow::Context;
use serde::{Deserialize, Serialize};
use serde_json::Value;
use sha2::{Digest, Sha256};
use std::{
    future::Future,
    path::{Path, PathBuf},
    time::UNIX_EPOCH,
};

use crate::dev_skills::{
    DevSkillInventory, ensure_package_is_not_required, scan_skill_packages,
    scan_skill_packages_with_candidate,
};

const MAX_SKILL_MD_BYTES: usize = 256 * 1024;
const MAX_MANIFEST_BYTES: usize = 64 * 1024;

#[derive(Clone, Debug, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub(crate) struct DevSkillCreateRequest {
    pub directory: String,
    pub skill_md: String,
    pub manifest: Value,
}

#[derive(Clone, Debug, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub(crate) struct DevSkillUpdateRequest {
    pub expected_revision: String,
    pub skill_md: String,
    pub manifest: Value,
}

#[derive(Clone, Debug, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub(crate) struct DevSkillDeleteRequest {
    pub expected_revision: String,
}

#[derive(Clone, Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub(crate) struct DevSkillSource {
    pub directory: String,
    pub source_revision: String,
    pub skill_md: String,
    pub manifest: Value,
}

#[derive(Clone, Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub(crate) struct DevSkillMutationResponse {
    pub inventory: DevSkillInventory,
    pub source: DevSkillSource,
}

pub(crate) async fn read_skill_source(
    root: &Path,
    directory: &str,
) -> anyhow::Result<DevSkillSource> {
    let canonical_root = canonical_root(root).await?;
    validate_directory(directory)?;
    let package = safe_existing_package(&canonical_root, directory).await?;
    source_from_package(&package, directory).await
}

pub(crate) async fn create_skill(
    root: &Path,
    request: DevSkillCreateRequest,
) -> anyhow::Result<DevSkillMutationResponse> {
    let canonical_root = canonical_root(root).await?;
    validate_directory(&request.directory)?;
    validate_source(&request.skill_md, &request.manifest)?;
    let target = canonical_root.join(&request.directory);
    ensure_path_absent(&target, "skill package already exists").await?;
    let staging = temporary_path(&canonical_root, "create");
    let result = async {
        write_source_tree(&staging, &request.skill_md, &request.manifest, true).await?;
        validate_staged_package(&canonical_root, &staging).await?;
        let candidate_inventory = scan_skill_packages_with_candidate(
            &canonical_root,
            &request.directory,
            &staging,
            false,
        )
        .await?;
        ensure_inventory_has_no_validation_errors(&candidate_inventory)?;
        let published = capture_editable_package(&staging, &request.directory).await?;
        ensure_path_absent(&target, "skill package already exists").await?;
        tokio::fs::rename(&staging, &target)
            .await
            .context("failed to publish skill package")?;
        match mutation_response(&canonical_root, &request.directory).await {
            Ok(response) => Ok(response),
            Err(error) => {
                remove_published_package(&target, &request.directory, &published.snapshot)
                    .await
                    .context("failed to roll back skill package creation")?;
                Err(error)
            }
        }
    }
    .await;
    remove_if_present(&staging).await;
    result
}

pub(crate) async fn update_skill(
    root: &Path,
    directory: &str,
    request: DevSkillUpdateRequest,
) -> anyhow::Result<DevSkillMutationResponse> {
    update_skill_with_pre_publish(root, directory, request, || async {}).await
}

async fn update_skill_with_pre_publish<F, Fut>(
    root: &Path,
    directory: &str,
    request: DevSkillUpdateRequest,
    pre_publish: F,
) -> anyhow::Result<DevSkillMutationResponse>
where
    F: FnOnce() -> Fut,
    Fut: Future<Output = ()>,
{
    let canonical_root = canonical_root(root).await?;
    validate_directory(directory)?;
    validate_revision(&request.expected_revision)?;
    validate_source(&request.skill_md, &request.manifest)?;
    let target = safe_existing_package(&canonical_root, directory).await?;
    let current = capture_editable_package(&target, directory).await?;
    anyhow::ensure!(
        current.source.source_revision == request.expected_revision,
        "skill package revision conflict"
    );
    let staging = temporary_path(&canonical_root, "update");
    let backup = temporary_path(&canonical_root, "backup");
    let result = async {
        copy_package_tree(&target, &staging).await?;
        write_source_tree(&staging, &request.skill_md, &request.manifest, false).await?;
        validate_staged_package(&canonical_root, &staging).await?;
        let candidate_inventory =
            scan_skill_packages_with_candidate(&canonical_root, directory, &staging, true).await?;
        ensure_inventory_has_no_validation_errors(&candidate_inventory)?;
        let published = capture_editable_package(&staging, directory).await?;
        if published.package_id != current.package_id {
            ensure_package_is_not_required(&candidate_inventory, &current.package_id)?;
        }
        pre_publish().await;
        ensure_package_unchanged(&target, directory, &current.snapshot).await?;
        tokio::fs::rename(&target, &backup)
            .await
            .context("failed to prepare skill package replacement")?;
        if let Err(error) = ensure_package_unchanged(&backup, directory, &current.snapshot).await {
            restore_moved_package(&target, &backup)
                .await
                .context("failed to restore concurrently changed skill package")?;
            return Err(error);
        }
        if let Err(error) = tokio::fs::rename(&staging, &target).await {
            restore_moved_package(&target, &backup)
                .await
                .context("failed to restore skill package after publish failure")?;
            return Err(error).context("failed to publish skill package replacement");
        }
        match mutation_response(&canonical_root, directory).await {
            Ok(response) => {
                ensure_package_unchanged(&backup, directory, &current.snapshot).await?;
                remove_path(&backup).await?;
                Ok(response)
            }
            Err(error) => {
                restore_published_package(&target, &backup, directory, &published.snapshot)
                    .await
                    .context("failed to restore skill package after validation failure")?;
                Err(error)
            }
        }
    }
    .await;
    remove_if_present(&staging).await;
    result
}

pub(crate) async fn delete_skill(
    root: &Path,
    directory: &str,
    request: DevSkillDeleteRequest,
) -> anyhow::Result<DevSkillInventory> {
    let canonical_root = canonical_root(root).await?;
    validate_directory(directory)?;
    validate_revision(&request.expected_revision)?;
    let target = safe_existing_package(&canonical_root, directory).await?;
    let current = capture_editable_package(&target, directory).await?;
    anyhow::ensure!(
        current.source.source_revision == request.expected_revision,
        "skill package revision conflict"
    );

    let backup = temporary_path(&canonical_root, "delete");
    ensure_package_unchanged(&target, directory, &current.snapshot).await?;
    tokio::fs::rename(&target, &backup)
        .await
        .context("failed to prepare skill package deletion")?;
    if let Err(error) = ensure_package_unchanged(&backup, directory, &current.snapshot).await {
        restore_moved_package(&target, &backup)
            .await
            .context("failed to restore concurrently changed skill package")?;
        return Err(error);
    }

    let inventory = match scan_skill_packages(&canonical_root)
        .await
        .and_then(|inventory| {
            ensure_inventory_has_no_validation_errors(&inventory)?;
            ensure_package_is_not_required(&inventory, &current.package_id)?;
            Ok(inventory)
        }) {
        Ok(inventory) => inventory,
        Err(error) => {
            restore_moved_package(&target, &backup)
                .await
                .context("failed to restore skill package after inventory scan failure")?;
            return Err(error);
        }
    };
    if let Err(error) = ensure_package_unchanged(&backup, directory, &current.snapshot).await {
        restore_moved_package(&target, &backup)
            .await
            .context("failed to restore concurrently changed skill package")?;
        return Err(error);
    }
    remove_path(&backup)
        .await
        .context("failed to finalize skill package deletion")?;
    Ok(inventory)
}

async fn mutation_response(
    root: &Path,
    directory: &str,
) -> anyhow::Result<DevSkillMutationResponse> {
    let inventory = scan_skill_packages(root).await?;
    ensure_inventory_has_no_validation_errors(&inventory)?;
    Ok(DevSkillMutationResponse {
        source: read_skill_source(root, directory).await?,
        inventory,
    })
}

fn ensure_inventory_has_no_validation_errors(inventory: &DevSkillInventory) -> anyhow::Result<()> {
    anyhow::ensure!(
        inventory
            .packages
            .iter()
            .all(|package| package.validation.errors.is_empty()),
        "skill inventory validation failed"
    );
    Ok(())
}

async fn canonical_root(root: &Path) -> anyhow::Result<PathBuf> {
    let metadata = tokio::fs::symlink_metadata(root)
        .await
        .context("failed to inspect development skills root")?;
    anyhow::ensure!(
        metadata.is_dir() && !metadata.file_type().is_symlink(),
        "development skills root must be a real directory"
    );
    let canonical = tokio::fs::canonicalize(root)
        .await
        .context("failed to resolve development skills root")?;
    anyhow::ensure!(
        tokio::fs::metadata(&canonical).await?.is_dir(),
        "development skills root is not a directory"
    );
    Ok(canonical)
}

fn validate_directory(value: &str) -> anyhow::Result<()> {
    anyhow::ensure!(
        !value.is_empty()
            && value.len() <= 128
            && value
                .bytes()
                .enumerate()
                .all(|(index, byte)| byte.is_ascii_lowercase()
                    || byte.is_ascii_digit()
                    || (byte == b'-' && index > 0)),
        "skill package directory is invalid"
    );
    anyhow::ensure!(!value.ends_with('-'), "skill package directory is invalid");
    Ok(())
}

fn validate_revision(value: &str) -> anyhow::Result<()> {
    anyhow::ensure!(
        value.len() == 64 && value.bytes().all(|byte| byte.is_ascii_hexdigit()),
        "skill package revision is invalid"
    );
    Ok(())
}

fn validate_source(skill_md: &str, manifest: &Value) -> anyhow::Result<SkillPackageDescriptor> {
    anyhow::ensure!(
        !skill_md.trim().is_empty() && skill_md.len() <= MAX_SKILL_MD_BYTES,
        "SKILL.md content is invalid"
    );
    let manifest_bytes = serde_json::to_vec(manifest)?;
    anyhow::ensure!(
        manifest_bytes.len() <= MAX_MANIFEST_BYTES,
        "skill package manifest is too large"
    );
    let descriptor: SkillPackageDescriptor = serde_json::from_value(manifest.clone())?;
    anyhow::ensure!(
        matches!(
            descriptor.kind,
            SkillPackageKind::InstructionOnly | SkillPackageKind::HostToolsOnly
        ),
        "development editor supports instruction-only and host-tools-only packages"
    );
    Ok(descriptor)
}

async fn safe_existing_package(root: &Path, directory: &str) -> anyhow::Result<PathBuf> {
    let target = root.join(directory);
    let metadata = tokio::fs::symlink_metadata(&target)
        .await
        .context("skill package not found")?;
    anyhow::ensure!(
        metadata.is_dir() && !metadata.file_type().is_symlink(),
        "skill package must be a real directory"
    );
    let canonical = tokio::fs::canonicalize(&target).await?;
    anyhow::ensure!(
        canonical.parent() == Some(root),
        "unsafe skill package path"
    );
    Ok(canonical)
}

#[derive(Debug, PartialEq, Eq)]
struct PackageSnapshot {
    directory_identity: same_file::Handle,
    source_revision: String,
    tree_revision: String,
}

#[derive(Debug)]
struct CapturedPackage {
    package_id: String,
    source: DevSkillSource,
    snapshot: PackageSnapshot,
}

async fn capture_editable_package(
    package: &Path,
    directory: &str,
) -> anyhow::Result<CapturedPackage> {
    let loaded = SkillPackageDescriptor::load(package).await?;
    let descriptor = loaded.descriptor;
    anyhow::ensure!(
        matches!(
            descriptor.kind,
            SkillPackageKind::InstructionOnly | SkillPackageKind::HostToolsOnly
        ),
        "runtime skill packages are read-only"
    );
    anyhow::ensure!(
        !descriptor.id.as_str().starts_with("agentweave.foundation."),
        "Foundation skill packages are read-only"
    );
    let package_id = descriptor.id.as_str().to_string();
    match tokio::fs::symlink_metadata(package.join("skill.json")).await {
        Ok(_) => anyhow::bail!("runtime skill packages are read-only"),
        Err(error) if error.kind() == std::io::ErrorKind::NotFound => {}
        Err(error) => return Err(error.into()),
    }
    let source = source_from_package(package, directory).await?;
    let directory_identity = same_file::Handle::from_path(package)
        .context("failed to identify skill package directory")?;
    let package = package.to_path_buf();
    let tree_revision = tokio::task::spawn_blocking(move || package_tree_revision(&package))
        .await
        .context("failed to inspect skill package tree")??;
    Ok(CapturedPackage {
        package_id,
        snapshot: PackageSnapshot {
            directory_identity,
            source_revision: source.source_revision.clone(),
            tree_revision,
        },
        source,
    })
}

async fn ensure_package_unchanged(
    package: &Path,
    directory: &str,
    expected: &PackageSnapshot,
) -> anyhow::Result<()> {
    let actual = capture_editable_package(package, directory)
        .await
        .map_err(|_| anyhow::anyhow!("skill package changed during update"))?;
    anyhow::ensure!(
        actual.snapshot == *expected,
        "skill package changed during update"
    );
    Ok(())
}

fn package_tree_revision(root: &Path) -> anyhow::Result<String> {
    let mut digest = Sha256::new();
    hash_tree_entry(root, Path::new(""), &mut digest)?;
    Ok(hex::encode(digest.finalize()))
}

fn hash_tree_entry(root: &Path, relative: &Path, digest: &mut Sha256) -> anyhow::Result<()> {
    let path = root.join(relative);
    let metadata = std::fs::symlink_metadata(&path)?;
    anyhow::ensure!(
        !metadata.file_type().is_symlink(),
        "skill package cannot contain symbolic links"
    );
    hash_bytes(digest, relative.to_string_lossy().as_bytes());
    hash_metadata(digest, &path, &metadata)?;

    if metadata.is_dir() {
        digest.update([b'd']);
        let mut entries = std::fs::read_dir(&path)?.collect::<Result<Vec<_>, _>>()?;
        entries.sort_by_key(std::fs::DirEntry::file_name);
        for entry in entries {
            hash_tree_entry(root, &relative.join(entry.file_name()), digest)?;
        }
    } else if metadata.is_file() {
        digest.update([b'f']);
        hash_bytes(digest, &std::fs::read(path)?);
    } else {
        anyhow::bail!("skill package contains an unsupported entry");
    }
    Ok(())
}

fn hash_metadata(
    digest: &mut Sha256,
    path: &Path,
    metadata: &std::fs::Metadata,
) -> anyhow::Result<()> {
    let identity = file_identity(path, metadata)?;
    digest.update(identity[0].to_le_bytes());
    digest.update(identity[1].to_le_bytes());
    digest.update(metadata.len().to_le_bytes());
    digest.update([u8::from(metadata.permissions().readonly())]);
    let modified = metadata
        .modified()
        .ok()
        .and_then(|value| value.duration_since(UNIX_EPOCH).ok())
        .map(|value| value.as_nanos())
        .unwrap_or(u128::MAX);
    digest.update(modified.to_le_bytes());
    hash_platform_metadata(digest, metadata);
    Ok(())
}

fn hash_bytes(digest: &mut Sha256, value: &[u8]) {
    digest.update(value.len().to_le_bytes());
    digest.update(value);
}

#[cfg(unix)]
fn file_identity(_path: &Path, metadata: &std::fs::Metadata) -> anyhow::Result<[u64; 2]> {
    use std::os::unix::fs::MetadataExt;
    Ok([metadata.dev(), metadata.ino()])
}

#[cfg(windows)]
fn file_identity(path: &Path, _metadata: &std::fs::Metadata) -> anyhow::Result<[u64; 2]> {
    use std::hash::{Hash, Hasher};
    let handle = same_file::Handle::from_path(path)?;
    let mut hasher = std::collections::hash_map::DefaultHasher::new();
    handle.hash(&mut hasher);
    Ok([hasher.finish(), 0])
}

#[cfg(not(any(unix, windows)))]
fn file_identity(_path: &Path, _metadata: &std::fs::Metadata) -> anyhow::Result<[u64; 2]> {
    Ok([0, 0])
}

#[cfg(unix)]
fn hash_platform_metadata(digest: &mut Sha256, metadata: &std::fs::Metadata) {
    use std::os::unix::fs::MetadataExt;
    digest.update(metadata.mode().to_le_bytes());
    digest.update(metadata.uid().to_le_bytes());
    digest.update(metadata.gid().to_le_bytes());
    digest.update(metadata.nlink().to_le_bytes());
}

#[cfg(windows)]
fn hash_platform_metadata(digest: &mut Sha256, metadata: &std::fs::Metadata) {
    use std::os::windows::fs::MetadataExt;
    digest.update(metadata.file_attributes().to_le_bytes());
    digest.update(metadata.creation_time().to_le_bytes());
    digest.update(metadata.last_write_time().to_le_bytes());
}

#[cfg(not(any(unix, windows)))]
fn hash_platform_metadata(_digest: &mut Sha256, _metadata: &std::fs::Metadata) {}

async fn source_from_package(package: &Path, directory: &str) -> anyhow::Result<DevSkillSource> {
    let skill_md_bytes = read_confined_file(package, "SKILL.md", MAX_SKILL_MD_BYTES).await?;
    let skill_md = String::from_utf8(skill_md_bytes).context("SKILL.md must be valid UTF-8")?;
    let manifest_bytes = read_confined_file(package, "agentweave.json", MAX_MANIFEST_BYTES).await?;
    let manifest: Value = serde_json::from_slice(&manifest_bytes)?;
    validate_source(&skill_md, &manifest)?;
    Ok(DevSkillSource {
        directory: directory.to_string(),
        source_revision: source_revision(skill_md.as_bytes(), &manifest_bytes),
        skill_md,
        manifest,
    })
}

async fn read_confined_file(package: &Path, name: &str, maximum: usize) -> anyhow::Result<Vec<u8>> {
    read_package_regular_file_nofollow(package, Path::new(name), maximum)
        .await
        .with_context(|| format!("{name} must be a confined regular file"))
}

async fn write_source_tree(
    package: &Path,
    skill_md: &str,
    manifest: &Value,
    create_interface: bool,
) -> anyhow::Result<()> {
    tokio::fs::create_dir_all(package).await?;
    tokio::fs::write(package.join("SKILL.md"), normalized_text(skill_md)).await?;
    tokio::fs::write(
        package.join("agentweave.json"),
        format!("{}\n", serde_json::to_string_pretty(manifest)?),
    )
    .await?;
    if create_interface {
        let descriptor: SkillPackageDescriptor = serde_json::from_value(manifest.clone())?;
        let summary =
            SkillCatalog::read_development_skill_summary(package, package.join("SKILL.md")).await?;
        let agents = package.join("agents");
        tokio::fs::create_dir_all(&agents).await?;
        let display = descriptor.display_name.replace('"', "'");
        tokio::fs::write(
            agents.join("openai.yaml"),
            format!(
                "interface:\n  display_name: \"{display}\"\n  short_description: \"App instruction skill\"\n  default_prompt: \"Use ${} when its description matches the request.\"\n",
                summary.name,
            ),
        )
        .await?;
    }
    Ok(())
}

fn normalized_text(value: &str) -> String {
    format!("{}\n", value.trim_end())
}

async fn validate_staged_package(root: &Path, package: &Path) -> anyhow::Result<()> {
    let loaded = SkillPackageDescriptor::load(package).await?;
    anyhow::ensure!(
        loaded.descriptor.package.include_instructions,
        "edited package must include instructions"
    );
    SkillCatalog::read_development_skill_summary(root, &package.join("SKILL.md")).await?;
    Ok(())
}

fn temporary_path(root: &Path, purpose: &str) -> PathBuf {
    root.join(format!(".agentweave-{purpose}-{}", uuid::Uuid::new_v4()))
}

async fn copy_package_tree(source: &Path, destination: &Path) -> anyhow::Result<()> {
    let source = source.to_path_buf();
    let destination = destination.to_path_buf();
    tokio::task::spawn_blocking(move || copy_tree_sync(&source, &destination)).await??;
    Ok(())
}

fn copy_tree_sync(source: &Path, destination: &Path) -> anyhow::Result<()> {
    std::fs::create_dir(destination)?;
    for entry in std::fs::read_dir(source)? {
        let entry = entry?;
        let file_type = entry.file_type()?;
        anyhow::ensure!(
            !file_type.is_symlink(),
            "skill package cannot contain symbolic links"
        );
        let target = destination.join(entry.file_name());
        if file_type.is_dir() {
            copy_tree_sync(&entry.path(), &target)?;
        } else if file_type.is_file() {
            std::fs::copy(entry.path(), target)?;
        } else {
            anyhow::bail!("skill package contains an unsupported entry");
        }
    }
    Ok(())
}

async fn restore_moved_package(target: &Path, backup: &Path) -> anyhow::Result<()> {
    ensure_path_absent(target, "skill package path was occupied during rollback").await?;
    tokio::fs::rename(backup, target).await?;
    Ok(())
}

async fn ensure_path_absent(path: &Path, occupied_message: &str) -> anyhow::Result<()> {
    match tokio::fs::symlink_metadata(path).await {
        Ok(_) => anyhow::bail!(occupied_message.to_string()),
        Err(error) if error.kind() == std::io::ErrorKind::NotFound => Ok(()),
        Err(error) => Err(error.into()),
    }
}

async fn remove_published_package(
    target: &Path,
    directory: &str,
    published: &PackageSnapshot,
) -> anyhow::Result<()> {
    ensure_package_unchanged(target, directory, published).await?;
    remove_path(target).await?;
    Ok(())
}

async fn restore_published_package(
    target: &Path,
    backup: &Path,
    directory: &str,
    published: &PackageSnapshot,
) -> anyhow::Result<()> {
    remove_published_package(target, directory, published).await?;
    restore_moved_package(target, backup).await
}

async fn remove_path(path: &Path) -> anyhow::Result<()> {
    match tokio::fs::symlink_metadata(path).await {
        Ok(metadata) if metadata.is_dir() && !metadata.file_type().is_symlink() => {
            tokio::fs::remove_dir_all(path).await?;
        }
        Ok(_) => tokio::fs::remove_file(path).await?,
        Err(error) if error.kind() == std::io::ErrorKind::NotFound => {}
        Err(error) => return Err(error.into()),
    }
    Ok(())
}

async fn remove_if_present(path: &Path) {
    let _ = remove_path(path).await;
}

fn source_revision(skill_md: &[u8], manifest: &[u8]) -> String {
    let mut digest = Sha256::new();
    digest.update(skill_md.len().to_le_bytes());
    digest.update(skill_md);
    digest.update(manifest.len().to_le_bytes());
    digest.update(manifest);
    hex::encode(digest.finalize())
}

#[cfg(test)]
mod tests {
    use super::*;

    fn test_root(label: &str) -> PathBuf {
        std::env::temp_dir().join(format!(
            "agentweave-dev-authoring-{label}-{}",
            uuid::Uuid::new_v4()
        ))
    }

    fn manifest() -> Value {
        serde_json::json!({
            "schemaVersion": 1,
            "id": "com.example.planning",
            "version": "0.1.0",
            "displayName": "Planning",
            "kind": "instruction_only",
            "package": {"includeInstructions": true, "includeRuntime": false},
            "compatibility": {"platforms": ["desktop"]},
            "requires": {
                "packages": [],
                "capabilities": [],
                "runtimeTools": [],
                "connectors": []
            }
        })
    }

    fn skill_md(body: &str) -> String {
        format!(
            "---\nname: planning\ndescription: Plan bounded work.\n---\n\n# Planning\n\n{body}\n"
        )
    }

    #[tokio::test]
    async fn creates_reads_and_updates_instruction_packages_with_revision_checks() {
        let root = test_root("lifecycle");
        tokio::fs::create_dir_all(&root).await.unwrap();
        let created = create_skill(
            &root,
            DevSkillCreateRequest {
                directory: "planning".into(),
                skill_md: skill_md("Create a plan."),
                manifest: manifest(),
            },
        )
        .await
        .unwrap();
        assert_eq!(created.source.directory, "planning");
        assert_eq!(created.inventory.packages.len(), 1);
        assert!(root.join("planning/agents/openai.yaml").is_file());

        let revision = created.source.source_revision.clone();
        let updated = update_skill(
            &root,
            "planning",
            DevSkillUpdateRequest {
                expected_revision: revision.clone(),
                skill_md: skill_md("Create and verify a plan."),
                manifest: manifest(),
            },
        )
        .await
        .unwrap();
        assert_ne!(updated.source.source_revision, revision);
        assert!(updated.source.skill_md.contains("verify"));

        let conflict = update_skill(
            &root,
            "planning",
            DevSkillUpdateRequest {
                expected_revision: revision,
                skill_md: skill_md("Stale edit."),
                manifest: manifest(),
            },
        )
        .await
        .unwrap_err();
        assert!(conflict.to_string().contains("revision conflict"));
        let _ = tokio::fs::remove_dir_all(root).await;
    }

    #[tokio::test]
    async fn duplicate_instruction_name_creation_fails_without_publishing_candidate() {
        let root = test_root("duplicate-name-rollback");
        tokio::fs::create_dir_all(&root).await.unwrap();
        create_skill(
            &root,
            DevSkillCreateRequest {
                directory: "planning".into(),
                skill_md: skill_md("Original instructions."),
                manifest: manifest(),
            },
        )
        .await
        .unwrap();
        let mut duplicate_manifest = manifest();
        duplicate_manifest["id"] = serde_json::json!("com.example.duplicate-planning");

        let error = create_skill(
            &root,
            DevSkillCreateRequest {
                directory: "duplicate-planning".into(),
                skill_md: skill_md("Duplicate instructions."),
                manifest: duplicate_manifest,
            },
        )
        .await
        .unwrap_err();

        assert!(error.to_string().contains("inventory validation failed"));
        assert!(!root.join("duplicate-planning").exists());
        assert!(
            read_skill_source(&root, "planning")
                .await
                .unwrap()
                .skill_md
                .contains("Original instructions")
        );
        assert_no_temporary_packages(&root).await;
        let _ = tokio::fs::remove_dir_all(root).await;
    }

    #[tokio::test]
    async fn update_detects_external_edit_before_replacement_and_preserves_it() {
        let root = test_root("external-edit");
        tokio::fs::create_dir_all(&root).await.unwrap();
        let created = create_skill(
            &root,
            DevSkillCreateRequest {
                directory: "planning".into(),
                skill_md: skill_md("Original instructions."),
                manifest: manifest(),
            },
        )
        .await
        .unwrap();
        let externally_edited = skill_md("External editor won the race.");
        let external_path = root.join("planning/SKILL.md");
        let hook_content = externally_edited.clone();

        let error = update_skill_with_pre_publish(
            &root,
            "planning",
            DevSkillUpdateRequest {
                expected_revision: created.source.source_revision,
                skill_md: skill_md("API replacement must not win."),
                manifest: manifest(),
            },
            move || async move {
                tokio::fs::write(&external_path, &hook_content)
                    .await
                    .unwrap();
            },
        )
        .await
        .unwrap_err();

        assert!(error.to_string().contains("changed during update"));
        assert_eq!(
            tokio::fs::read_to_string(root.join("planning/SKILL.md"))
                .await
                .unwrap(),
            externally_edited
        );
        assert_no_temporary_packages(&root).await;
        let _ = tokio::fs::remove_dir_all(root).await;
    }

    #[tokio::test]
    async fn delete_rejects_runtime_package_without_removing_it() {
        let root = test_root("delete-runtime-read-only");
        let package = root.join("runtime");
        tokio::fs::create_dir_all(&package).await.unwrap();
        tokio::fs::write(
            package.join("skill.json"),
            serde_json::json!({
                "name": "runtime",
                "description": "Runtime package.",
                "version": "0.1.0",
                "entry": {"type": "command", "command": "node", "args": ["index.js"]},
                "tools": []
            })
            .to_string(),
        )
        .await
        .unwrap();
        tokio::fs::write(package.join("index.js"), "process.stdin.resume();\n")
            .await
            .unwrap();

        let error = delete_skill(
            &root,
            "runtime",
            DevSkillDeleteRequest {
                expected_revision: "a".repeat(64),
            },
        )
        .await
        .unwrap_err();

        assert!(
            error
                .to_string()
                .contains("runtime skill packages are read-only")
        );
        assert!(package.join("skill.json").exists());
        let _ = tokio::fs::remove_dir_all(root).await;
    }

    #[tokio::test]
    async fn rejects_native_runtime_and_unsafe_directories() {
        let root = test_root("validation");
        tokio::fs::create_dir_all(&root).await.unwrap();
        let mut native = manifest();
        native["kind"] = serde_json::json!("native_runtime");
        native["package"]["includeInstructions"] = serde_json::json!(false);
        native["package"]["includeRuntime"] = serde_json::json!(true);
        assert!(
            create_skill(
                &root,
                DevSkillCreateRequest {
                    directory: "native".into(),
                    skill_md: skill_md("Unsafe."),
                    manifest: native,
                },
            )
            .await
            .unwrap_err()
            .to_string()
            .contains("supports instruction-only")
        );
        assert!(
            create_skill(
                &root,
                DevSkillCreateRequest {
                    directory: "../escape".into(),
                    skill_md: skill_md("Unsafe."),
                    manifest: manifest(),
                },
            )
            .await
            .is_err()
        );
        let _ = tokio::fs::remove_dir_all(root).await;
    }

    #[cfg(unix)]
    #[tokio::test]
    async fn refuses_symlinked_source_files() {
        use std::os::unix::fs::symlink;

        let root = test_root("source-symlink");
        let package = root.join("planning");
        tokio::fs::create_dir_all(&package).await.unwrap();
        let outside = root.join("outside.md");
        tokio::fs::write(&outside, skill_md("Outside instructions."))
            .await
            .unwrap();
        symlink(&outside, package.join("SKILL.md")).unwrap();
        tokio::fs::write(
            package.join("agentweave.json"),
            serde_json::to_vec(&manifest()).unwrap(),
        )
        .await
        .unwrap();

        let error = read_skill_source(&root, "planning").await.unwrap_err();
        assert!(error.to_string().contains("confined regular file"));
        let _ = tokio::fs::remove_dir_all(root).await;
    }

    async fn assert_no_temporary_packages(root: &Path) {
        let mut entries = tokio::fs::read_dir(root).await.unwrap();
        while let Some(entry) = entries.next_entry().await.unwrap() {
            assert!(
                !entry
                    .file_name()
                    .to_string_lossy()
                    .starts_with(".agentweave-"),
                "temporary package was not cleaned up: {}",
                entry.path().display()
            );
        }
    }
}

#[cfg(test)]
#[path = "dev_skill_authoring_dependency_tests.rs"]
mod dependency_tests;
