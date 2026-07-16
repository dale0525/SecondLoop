use super::server_skill_startup::{
    BuiltinSkillsMode, app_packages_root_from_lookup, load_skill_manager,
    load_skill_manager_with_mode,
};
use agent_runtime::platform::PlatformId;
use agent_runtime::skill_bundle::{BuildSkillBundleRequest, build_skill_bundle};
use agent_runtime::storage::Storage;
use std::path::Path;

struct TestDir(std::path::PathBuf);

impl TestDir {
    fn new(name: &str) -> Self {
        let path = std::env::temp_dir().join(format!(
            "agentweave-startup-{name}-{}",
            uuid::Uuid::new_v4()
        ));
        std::fs::create_dir_all(&path).unwrap();
        Self(path)
    }

    fn path(&self) -> &Path {
        &self.0
    }
}

impl Drop for TestDir {
    fn drop(&mut self) {
        let _ = std::fs::remove_dir_all(&self.0);
    }
}

#[test]
fn explicit_packaged_app_source_overrides_source_tree_packages() {
    let values = std::collections::BTreeMap::from([
        ("AGENTWEAVE_APP_ROOT", "/release/agent-app/app"),
        (
            "AGENTWEAVE_APP_PACKAGES_ROOT",
            "/release/agent-app/packages",
        ),
    ]);
    let root = app_packages_root_from_lookup(|name| values.get(name).map(Into::into)).unwrap();

    assert_eq!(root, Some("/release/agent-app/packages".into()));
}

#[test]
fn development_app_source_defaults_to_app_local_packages() {
    let root = app_packages_root_from_lookup(|name| {
        (name == "AGENTWEAVE_APP_ROOT").then(|| "/source/example-app".into())
    })
    .unwrap();

    assert_eq!(root, Some("/source/example-app/packages".into()));
}

#[test]
fn explicit_app_packages_source_requires_an_absolute_nonempty_path() {
    for value in ["", "relative/packages"] {
        let result = app_packages_root_from_lookup(|name| {
            (name == "AGENTWEAVE_APP_PACKAGES_ROOT").then(|| value.into())
        });
        assert!(result.is_err());
    }
}

#[tokio::test]
async fn startup_treats_lock_only_root_as_damaged_bundle() {
    assert_bundle_startup_error("skill-bundle.lock", "{}").await;
}

#[tokio::test]
async fn startup_treats_manifest_only_root_as_damaged_bundle() {
    assert_bundle_startup_error("skill-bundle.json", "{}").await;
}

#[tokio::test]
async fn startup_treats_generation_layout_without_current_as_damaged_bundle() {
    let temp = TestDir::new("generation-only");
    tokio::fs::create_dir_all(temp.path().join("generations"))
        .await
        .unwrap();

    let error = load_skill_manager(
        temp.path(),
        Storage::connect("sqlite::memory:").await.unwrap(),
        None,
    )
    .await
    .err()
    .unwrap();

    assert!(format!("{error:#}").contains("bundle current marker"));
}

#[tokio::test]
async fn deleting_bundle_metadata_never_downgrades_to_directory_discovery() {
    let temp = TestDir::new("metadata-deletion");
    let source = temp.path().join("source");
    let output = temp.path().join("bundle");
    write_package(&source.join("com.example.startup")).await;
    build_skill_bundle(BuildSkillBundleRequest {
        source_roots: vec![source],
        output_root: output.clone(),
        platform: PlatformId::Desktop,
        runtime_version: env!("CARGO_PKG_VERSION").parse().unwrap(),
        generated_at: "2026-07-12T00:00:00Z".into(),
    })
    .await
    .unwrap();
    tokio::fs::remove_file(output.join("current"))
        .await
        .unwrap();

    let error = load_skill_manager(
        &output,
        Storage::connect("sqlite::memory:").await.unwrap(),
        None,
    )
    .await
    .err()
    .unwrap();

    assert!(format!("{error:#}").contains("bundle current marker"));
}

#[tokio::test]
async fn deleting_manifest_and_lock_never_downgrades_to_directory_discovery() {
    let temp = TestDir::new("generation-metadata-deletion");
    let source = temp.path().join("source");
    let output = temp.path().join("bundle");
    write_package(&source.join("com.example.startup")).await;
    build_skill_bundle(BuildSkillBundleRequest {
        source_roots: vec![source],
        output_root: output.clone(),
        platform: PlatformId::Desktop,
        runtime_version: env!("CARGO_PKG_VERSION").parse().unwrap(),
        generated_at: "2026-07-12T00:00:00Z".into(),
    })
    .await
    .unwrap();
    let current: serde_json::Value =
        serde_json::from_slice(&tokio::fs::read(output.join("current")).await.unwrap()).unwrap();
    let generation = output
        .join("generations")
        .join(current["active"]["generation"].as_str().unwrap());
    make_metadata_removable(&generation).await;
    tokio::fs::remove_file(generation.join("skill-bundle.json"))
        .await
        .unwrap();
    tokio::fs::remove_file(generation.join("skill-bundle.lock"))
        .await
        .unwrap();

    let error = load_skill_manager(
        &output,
        Storage::connect("sqlite::memory:").await.unwrap(),
        None,
    )
    .await
    .err()
    .unwrap();

    assert!(format!("{error:#}").contains("bundle metadata"));
}

#[tokio::test]
async fn deleting_direct_bundle_metadata_never_downgrades_to_directory_discovery() {
    let temp = TestDir::new("direct-metadata-deletion");
    let source = temp.path().join("source");
    let generated = temp.path().join("generated");
    let direct = temp.path().join("direct");
    write_package(&source.join("com.example.startup")).await;
    build_skill_bundle(BuildSkillBundleRequest {
        source_roots: vec![source],
        output_root: generated.clone(),
        platform: PlatformId::Desktop,
        runtime_version: env!("CARGO_PKG_VERSION").parse().unwrap(),
        generated_at: "2026-07-12T00:00:00Z".into(),
    })
    .await
    .unwrap();
    let current: serde_json::Value =
        serde_json::from_slice(&tokio::fs::read(generated.join("current")).await.unwrap()).unwrap();
    let generation = generated
        .join("generations")
        .join(current["active"]["generation"].as_str().unwrap());
    copy_direct_bundle(&generation, &direct).await;
    make_metadata_removable(&direct).await;
    tokio::fs::remove_file(direct.join("skill-bundle.json"))
        .await
        .unwrap();
    tokio::fs::remove_file(direct.join("skill-bundle.lock"))
        .await
        .unwrap();

    let result = load_skill_manager_with_mode(
        &direct,
        Storage::connect("sqlite::memory:").await.unwrap(),
        None,
        BuiltinSkillsMode::Bundle,
    )
    .await;

    assert!(
        result.is_err(),
        "direct bundle downgraded to directory mode"
    );
}

#[tokio::test]
async fn automatic_startup_rejects_direct_bundle_without_authoritative_mode() {
    let temp = TestDir::new("direct-auto-rejected");
    let source = temp.path().join("source");
    let generated = temp.path().join("generated");
    let direct = temp.path().join("direct");
    write_package(&source.join("com.example.startup")).await;
    build_skill_bundle(BuildSkillBundleRequest {
        source_roots: vec![source],
        output_root: generated.clone(),
        platform: PlatformId::Desktop,
        runtime_version: env!("CARGO_PKG_VERSION").parse().unwrap(),
        generated_at: "2026-07-12T00:00:00Z".into(),
    })
    .await
    .unwrap();
    let current: serde_json::Value =
        serde_json::from_slice(&tokio::fs::read(generated.join("current")).await.unwrap()).unwrap();
    let generation = generated
        .join("generations")
        .join(current["active"]["generation"].as_str().unwrap());
    copy_direct_bundle(&generation, &direct).await;

    let error = load_skill_manager(
        &direct,
        Storage::connect("sqlite::memory:").await.unwrap(),
        None,
    )
    .await
    .err()
    .unwrap();

    assert!(format!("{error:#}").contains("requires AGENTWEAVE_BUILTIN_SKILLS_MODE=bundle"));
}

async fn copy_direct_bundle(generation: &Path, direct: &Path) {
    let package = direct.join("com.example.startup");
    tokio::fs::create_dir_all(&package).await.unwrap();
    for name in ["skill-bundle.json", "skill-bundle.lock"] {
        tokio::fs::copy(generation.join(name), direct.join(name))
            .await
            .unwrap();
    }
    for name in ["agentweave.json", "skill.json", "index.js"] {
        tokio::fs::copy(
            generation.join("com.example.startup").join(name),
            package.join(name),
        )
        .await
        .unwrap();
    }
}

async fn make_metadata_removable(root: &Path) {
    #[cfg(unix)]
    {
        use std::os::unix::fs::PermissionsExt;
        let metadata = tokio::fs::metadata(root).await.unwrap();
        let mut permissions = metadata.permissions();
        permissions.set_mode(permissions.mode() | 0o300);
        tokio::fs::set_permissions(root, permissions).await.unwrap();
    }
    #[cfg(windows)]
    {
        let mut permissions = tokio::fs::metadata(root).await.unwrap().permissions();
        permissions.set_readonly(false);
        tokio::fs::set_permissions(root, permissions).await.unwrap();
        for name in ["skill-bundle.json", "skill-bundle.lock"] {
            let path = root.join(name);
            let mut permissions = tokio::fs::metadata(&path).await.unwrap().permissions();
            permissions.set_readonly(false);
            tokio::fs::set_permissions(path, permissions).await.unwrap();
        }
    }
}

async fn assert_bundle_startup_error(name: &str, contents: &str) {
    let temp = TestDir::new("single-evidence");
    tokio::fs::write(temp.path().join(name), contents)
        .await
        .unwrap();

    let result = load_skill_manager(
        temp.path(),
        Storage::connect("sqlite::memory:").await.unwrap(),
        None,
    )
    .await;

    assert!(
        result.is_err(),
        "{name} unexpectedly downgraded to directory mode"
    );
}

async fn write_package(root: &Path) {
    tokio::fs::create_dir_all(root).await.unwrap();
    tokio::fs::write(
        root.join("agentweave.json"),
        serde_json::json!({
            "schemaVersion": 1,
            "id": "com.example.startup",
            "version": "0.1.0",
            "displayName": "Startup",
            "kind": "native_runtime",
            "package": { "includeInstructions": false, "includeRuntime": true },
            "compatibility": { "platforms": ["desktop"] },
            "requires": {
                "packages": [], "capabilities": ["shell.process"],
                "runtimeTools": [], "connectors": []
            }
        })
        .to_string(),
    )
    .await
    .unwrap();
    tokio::fs::write(
        root.join("skill.json"),
        serde_json::json!({
            "name": "startup", "description": "Startup fixture.", "version": "0.1.0",
            "entry": { "type": "command", "command": "node", "args": ["index.js"] },
            "tools": [{ "name": "run", "description": "Run.", "input_schema": {"type":"object"} }]
        })
        .to_string(),
    )
    .await
    .unwrap();
    tokio::fs::write(root.join("index.js"), "process.stdout.write('{}')\n")
        .await
        .unwrap();
}
