use crate::platform::PlatformId;
#[cfg(windows)]
use crate::skill_bundle::gate_bundle_current_after_open;
use crate::skill_bundle::{
    BuildSkillBundleRequest, BundleSkillSource, SkillBundleCurrent, build_skill_bundle,
    build_skill_bundle_with_faults, gate_bundle_before_publish, gate_bundle_discovery_after_layout,
};
use crate::skill_resolver::{ResolvedSkillPackage, ResolvedSkillSet, SkillResolutionStatus};
use crate::skill_snapshot::SkillSnapshot;
use crate::skill_source::SkillSource;
use crate::skill_store_faults::{StoreFaultPoint, StoreFaults};
use semver::Version;
use sha2::{Digest, Sha256};
use std::path::Path;

#[cfg(unix)]
#[tokio::test]
async fn bundle_execution_never_spawns_from_replaced_package() {
    let fixture = BundleReviewFixture::new().await;
    build_skill_bundle(fixture.request()).await.unwrap();
    let source = BundleSkillSource::open(&fixture.output).await.unwrap();
    let packages = source.packages().await.unwrap();
    let original = packages[0].root.clone();
    let snapshot = SkillSnapshot::build(1, active_set(packages)).await.unwrap();
    let marker = fixture.temp.path().join("replacement-executed");
    let gate = crate::skill_verified::gate_bundle_execution_after_snapshot();
    let registry = snapshot.registry().clone();
    let execution = tokio::spawn(async move {
        registry
            .execute("com.example.atomic/run", serde_json::json!({}))
            .await
    });
    gate.wait_entered().await;

    make_directory_replaceable(&original).await;
    let displaced = original.with_extension("verified");
    tokio::fs::rename(&original, &displaced).await.unwrap();
    tokio::fs::create_dir(&original).await.unwrap();
    tokio::fs::write(
        original.join("run.sh"),
        format!(
            "printf replaced > '{}'; printf '{{\"ok\":false}}'\n",
            marker.display()
        ),
    )
    .await
    .unwrap();
    gate.release().await;

    assert_eq!(
        execution.await.unwrap().unwrap(),
        serde_json::json!({"ok": true})
    );
    assert!(!marker.exists());
}

#[cfg(unix)]
#[tokio::test]
async fn bundle_execution_rejects_unlocked_generation_content_added_after_snapshot() {
    let fixture = BundleReviewFixture::new().await;
    build_skill_bundle(fixture.request()).await.unwrap();
    let source = BundleSkillSource::open(&fixture.output).await.unwrap();
    let packages = source.packages().await.unwrap();
    let snapshot = SkillSnapshot::build(1, active_set(packages)).await.unwrap();
    let generation = active_generation(&fixture.output).await;
    make_owner_writable(&generation, true).await;
    tokio::fs::create_dir(generation.join("unlocked"))
        .await
        .unwrap();

    let error = snapshot
        .registry()
        .execute("com.example.atomic/run", serde_json::json!({}))
        .await
        .unwrap_err();

    assert!(format!("{error:#}").contains("unlocked content"));
}

#[cfg(windows)]
#[tokio::test]
async fn windows_builder_rejects_source_hardlink_without_replacing_current() {
    let fixture = BundleReviewFixture::new().await;
    build_skill_bundle(fixture.request()).await.unwrap();
    let old_current = tokio::fs::read(fixture.output.join("current"))
        .await
        .unwrap();
    std::fs::hard_link(
        fixture.package().join("skill.json"),
        fixture.temp.path().join("source-skill-hardlink.json"),
    )
    .unwrap();

    let error = build_skill_bundle(fixture.request()).await.unwrap_err();

    assert!(format!("{error:#}").contains("hard links"));
    assert_eq!(
        tokio::fs::read(fixture.output.join("current"))
            .await
            .unwrap(),
        old_current
    );
}

#[cfg(windows)]
#[tokio::test]
async fn windows_bundle_open_rejects_package_hardlink() {
    let fixture = BundleReviewFixture::new().await;
    build_skill_bundle(fixture.request()).await.unwrap();
    let generation = active_generation(&fixture.output).await;
    std::fs::hard_link(
        generation.join("com.example.atomic/skill.json"),
        fixture.temp.path().join("bundle-skill-hardlink.json"),
    )
    .unwrap();

    let error = BundleSkillSource::open(&fixture.output).await.unwrap_err();

    assert!(format!("{error:#}").contains("hard links"));
}

#[cfg(windows)]
#[tokio::test]
async fn windows_bundle_execution_rejects_package_hardlink() {
    let fixture = BundleReviewFixture::new().await;
    build_skill_bundle(fixture.request()).await.unwrap();
    let source = BundleSkillSource::open(&fixture.output).await.unwrap();
    let packages = source.packages().await.unwrap();
    let snapshot = SkillSnapshot::build(1, active_set(packages)).await.unwrap();
    let old_current = tokio::fs::read(fixture.output.join("current"))
        .await
        .unwrap();
    std::fs::hard_link(
        active_generation(&fixture.output)
            .await
            .join("com.example.atomic/index.js"),
        fixture.temp.path().join("execution-index-hardlink.js"),
    )
    .unwrap();

    let error = snapshot
        .registry()
        .execute("com.example.atomic/run", serde_json::json!({}))
        .await
        .unwrap_err();

    assert!(format!("{error:#}").contains("hard links"));
    assert_eq!(
        tokio::fs::read(fixture.output.join("current"))
            .await
            .unwrap(),
        old_current
    );
}

#[cfg(windows)]
#[tokio::test]
async fn windows_current_reader_allows_concurrent_atomic_publication() {
    let fixture = BundleReviewFixture::new().await;
    build_skill_bundle(fixture.request()).await.unwrap();
    let source = BundleSkillSource::open(&fixture.output).await.unwrap();
    tokio::fs::write(
        fixture.package().join("index.js"),
        "process.stdout.write('new')\n",
    )
    .await
    .unwrap();
    let gate = gate_bundle_current_after_open(&fixture.output.join("current"));
    let reader = tokio::spawn(async move { source.discover().await });
    gate.wait_entered().await;

    build_skill_bundle(fixture.request()).await.unwrap();

    gate.release().await;
    assert_eq!(reader.await.unwrap().unwrap().len(), 1);
    BundleSkillSource::open(&fixture.output).await.unwrap();
}

#[tokio::test]
async fn concurrent_reader_observes_old_then_new_complete_generation() {
    let fixture = BundleReviewFixture::new().await;
    build_skill_bundle(fixture.request()).await.unwrap();
    let source = BundleSkillSource::open(&fixture.output).await.unwrap();
    let old_hash = package_hash(&source).await;
    tokio::fs::write(
        fixture.package().join("index.js"),
        "process.stdout.write('new')\n",
    )
    .await
    .unwrap();

    let gate = gate_bundle_before_publish(&fixture.output);
    let request = fixture.request();
    let publishing = tokio::spawn(async move { build_skill_bundle(request).await });
    gate.wait_entered().await;

    assert_eq!(package_hash(&source).await, old_hash);
    gate.release().await;
    publishing.await.unwrap().unwrap();

    let new_hash = package_hash(&source).await;
    assert_ne!(new_hash, old_hash);
}

#[tokio::test]
async fn publish_failure_keeps_previous_generation_readable() {
    let fixture = BundleReviewFixture::new().await;
    build_skill_bundle(fixture.request()).await.unwrap();
    let source = BundleSkillSource::open(&fixture.output).await.unwrap();
    let old_hash = package_hash(&source).await;
    tokio::fs::write(
        fixture.package().join("index.js"),
        "process.stdout.write('new')\n",
    )
    .await
    .unwrap();
    let faults = StoreFaults::default();
    faults.fail_once(StoreFaultPoint::BundleBeforePublish);

    let error = build_skill_bundle_with_faults(fixture.request(), faults)
        .await
        .unwrap_err();

    assert!(format!("{error:#}").contains("BundleBeforePublish"));
    assert_eq!(package_hash(&source).await, old_hash);
}

#[tokio::test]
async fn post_commit_failure_keeps_committed_generation_readable() {
    let fixture = BundleReviewFixture::new().await;
    build_skill_bundle(fixture.request()).await.unwrap();
    let source = BundleSkillSource::open(&fixture.output).await.unwrap();
    let old_hash = package_hash(&source).await;
    tokio::fs::write(
        fixture.package().join("index.js"),
        "process.stdout.write('new')\n",
    )
    .await
    .unwrap();
    let faults = StoreFaults::default();
    faults.fail_once(StoreFaultPoint::WriteAfterRenameMode);

    build_skill_bundle_with_faults(fixture.request(), faults)
        .await
        .unwrap_err();

    let readable_hash = package_hash(&source).await;
    assert_ne!(readable_hash, old_hash);
}

#[tokio::test]
#[cfg(unix)]
async fn staging_generation_replacement_never_publishes_replacement() {
    let fixture = BundleReviewFixture::new().await;
    build_skill_bundle(fixture.request()).await.unwrap();
    let source = BundleSkillSource::open(&fixture.output).await.unwrap();
    let old_hash = package_hash(&source).await;
    tokio::fs::write(
        fixture.package().join("index.js"),
        "process.stdout.write('new')\n",
    )
    .await
    .unwrap();

    let gate = gate_bundle_before_publish(&fixture.output);
    let request = fixture.request();
    let publishing = tokio::spawn(async move { build_skill_bundle(request).await });
    let generation = gate.wait_entered().await;
    let displaced = fixture.temp.path().join("displaced-staging-generation");
    tokio::fs::rename(&generation, &displaced).await.unwrap();
    tokio::fs::create_dir(&generation).await.unwrap();
    tokio::fs::write(generation.join("attacker"), "replacement")
        .await
        .unwrap();
    gate.release().await;

    let error = publishing.await.unwrap().unwrap_err();
    assert!(format!("{error:#}").contains("identity changed"));
    assert_eq!(package_hash(&source).await, old_hash);
    assert_eq!(
        tokio::fs::read_to_string(generation.join("attacker"))
            .await
            .unwrap(),
        "replacement"
    );
}

#[tokio::test]
async fn staged_package_mutation_before_publication_keeps_previous_generation_readable() {
    let fixture = BundleReviewFixture::new().await;
    build_skill_bundle(fixture.request()).await.unwrap();
    let source = BundleSkillSource::open(&fixture.output).await.unwrap();
    let old_hash = package_hash(&source).await;
    let old_current = tokio::fs::read(fixture.output.join("current"))
        .await
        .unwrap();
    tokio::fs::write(
        fixture.package().join("index.js"),
        "process.stdout.write('new')\n",
    )
    .await
    .unwrap();

    let gate = gate_bundle_before_publish(&fixture.output);
    let request = fixture.request();
    let publishing = tokio::spawn(async move { build_skill_bundle(request).await });
    let generation = gate.wait_entered().await;
    tokio::fs::write(
        generation.join("com.example.atomic/index.js"),
        "process.stdout.write('tampered')\n",
    )
    .await
    .unwrap();
    gate.release().await;

    let error = publishing.await.unwrap().unwrap_err();
    assert!(format!("{error:#}").contains("staged bundle"));
    assert_eq!(
        tokio::fs::read(fixture.output.join("current"))
            .await
            .unwrap(),
        old_current
    );
    assert_eq!(package_hash(&source).await, old_hash);
}

#[tokio::test]
async fn staged_metadata_mutation_before_publication_keeps_previous_generation_readable() {
    let fixture = BundleReviewFixture::new().await;
    build_skill_bundle(fixture.request()).await.unwrap();
    let source = BundleSkillSource::open(&fixture.output).await.unwrap();
    let old_hash = package_hash(&source).await;
    let old_current = tokio::fs::read(fixture.output.join("current"))
        .await
        .unwrap();
    tokio::fs::write(
        fixture.package().join("index.js"),
        "process.stdout.write('new')\n",
    )
    .await
    .unwrap();

    let gate = gate_bundle_before_publish(&fixture.output);
    let request = fixture.request();
    let publishing = tokio::spawn(async move { build_skill_bundle(request).await });
    let generation = gate.wait_entered().await;
    tokio::fs::write(generation.join("skill-bundle.lock"), b"{}\n")
        .await
        .unwrap();
    gate.release().await;

    let error = publishing.await.unwrap().unwrap_err();
    assert!(format!("{error:#}").contains("staged bundle"));
    assert_eq!(
        tokio::fs::read(fixture.output.join("current"))
            .await
            .unwrap(),
        old_current
    );
    assert_eq!(package_hash(&source).await, old_hash);
}

#[tokio::test]
async fn invalid_first_build_leaves_no_bundle_evidence_and_retry_succeeds() {
    let fixture = BundleReviewFixture::new().await;
    tokio::fs::write(fixture.package().join("agentweave.json"), b"{")
        .await
        .unwrap();

    build_skill_bundle(fixture.request()).await.unwrap_err();

    assert!(!fixture.output.exists());
    write_runtime_package(&fixture.package()).await;
    build_skill_bundle(fixture.request()).await.unwrap();
    BundleSkillSource::open(&fixture.output).await.unwrap();
}

#[tokio::test]
async fn unresolved_first_build_leaves_no_bundle_evidence_and_retry_succeeds() {
    let fixture = BundleReviewFixture::new().await;
    let descriptor = fixture.package().join("agentweave.json");
    mutate_json(&descriptor, |value| {
        value["requires"]["packages"] = serde_json::json!(["com.example.missing"]);
    })
    .await;

    build_skill_bundle(fixture.request()).await.unwrap_err();

    assert!(!fixture.output.exists());
    mutate_json(&descriptor, |value| {
        value["requires"]["packages"] = serde_json::json!([]);
    })
    .await;
    build_skill_bundle(fixture.request()).await.unwrap();
    BundleSkillSource::open(&fixture.output).await.unwrap();
}

#[tokio::test]
async fn bundle_discover_rejects_unlocked_tree_added_after_open() {
    let fixture = BundleReviewFixture::new().await;
    build_skill_bundle(fixture.request()).await.unwrap();
    let source = BundleSkillSource::open(&fixture.output).await.unwrap();
    let generation = active_generation(&fixture.output).await;
    make_owner_writable(&generation, true).await;
    tokio::fs::create_dir(generation.join("com.example.extra"))
        .await
        .unwrap();

    let error = source.discover().await.unwrap_err();

    assert!(format!("{error:#}").contains("unlocked content"));
}

#[tokio::test]
async fn bundle_discover_rejects_unlocked_generation_layout_entry() {
    let fixture = BundleReviewFixture::new().await;
    build_skill_bundle(fixture.request()).await.unwrap();
    let source = BundleSkillSource::open(&fixture.output).await.unwrap();
    tokio::fs::create_dir(fixture.output.join("generations/unlocked-tree"))
        .await
        .unwrap();

    let error = source.discover().await.unwrap_err();

    assert!(format!("{error:#}").contains("unlocked generation"));
}

#[tokio::test]
async fn bundle_open_rejects_missing_locked_dependency_closure() {
    let fixture = BundleReviewFixture::new().await;
    build_skill_bundle(fixture.request()).await.unwrap();
    let generation = tokio::fs::canonicalize(active_generation(&fixture.output).await)
        .await
        .unwrap();
    let descriptor_path = generation.join("com.example.atomic/agentweave.json");
    mutate_json(&descriptor_path, |value| {
        value["requires"]["packages"] = serde_json::json!(["com.example.missing"]);
    })
    .await;
    let hash = crate::skill_store_secure_fs::secure_package_hash(
        &generation.join("com.example.atomic"),
        crate::skill_store::SkillStoreLimits::default().package_limits(),
    )
    .await
    .unwrap();
    mutate_json(&generation.join("skill-bundle.json"), |value| {
        value["packages"][0]["contentHash"] = serde_json::json!(hash);
    })
    .await;
    mutate_json(&generation.join("skill-bundle.lock"), |value| {
        value["packages"][0]["contentHash"] = serde_json::json!(hash);
        value["packages"][0]["dependencies"] = serde_json::json!(["com.example.missing"]);
    })
    .await;

    let error = BundleSkillSource::open(&fixture.output).await.unwrap_err();

    assert!(format!("{error:#}").contains("missing from locked set"));
}

#[tokio::test]
#[cfg(unix)]
async fn bundle_discover_rejects_generation_replaced_during_reload() {
    let fixture = BundleReviewFixture::new().await;
    build_skill_bundle(fixture.request()).await.unwrap();
    let source = BundleSkillSource::open(&fixture.output).await.unwrap();
    let generation = tokio::fs::canonicalize(active_generation(&fixture.output).await)
        .await
        .unwrap();
    let gate = gate_bundle_discovery_after_layout(&generation);
    let reload = tokio::spawn(async move { source.discover().await });
    gate.wait_entered().await;
    let displaced = generation.with_file_name(uuid::Uuid::new_v4().to_string());
    make_directory_replaceable(&generation).await;
    tokio::fs::rename(&generation, &displaced).await.unwrap();
    tokio::fs::create_dir(&generation).await.unwrap();
    gate.release().await;

    let error = reload.await.unwrap().unwrap_err();
    assert!(format!("{error:#}").contains("identity changed"));
}

#[tokio::test]
#[cfg(unix)]
async fn bundle_discover_rejects_package_directory_replaced_during_reload() {
    let fixture = BundleReviewFixture::new().await;
    build_skill_bundle(fixture.request()).await.unwrap();
    let source = BundleSkillSource::open(&fixture.output).await.unwrap();
    let generation = tokio::fs::canonicalize(active_generation(&fixture.output).await)
        .await
        .unwrap();
    let gate = gate_bundle_discovery_after_layout(&generation);
    let reload = tokio::spawn(async move { source.discover().await });
    gate.wait_entered().await;
    let package = generation.join("com.example.atomic");
    let displaced = generation.join("displaced-active-package");
    make_directory_replaceable(&package).await;
    tokio::fs::rename(&package, &displaced).await.unwrap();
    tokio::fs::create_dir(&package).await.unwrap();
    gate.release().await;

    let error = reload.await.unwrap().unwrap_err();
    let message = format!("{error:#}");
    assert!(
        message.contains("identity changed") || message.contains("unlocked content"),
        "unexpected error: {message}"
    );
}

async fn package_hash(source: &BundleSkillSource) -> String {
    source.packages().await.unwrap()[0].content_hash.clone()
}

async fn active_generation(output: &Path) -> std::path::PathBuf {
    let current: SkillBundleCurrent =
        serde_json::from_slice(&tokio::fs::read(output.join("current")).await.unwrap()).unwrap();
    output.join("generations").join(current.active.generation)
}

async fn mutate_json(path: &Path, mutate: impl FnOnce(&mut serde_json::Value)) {
    let mut value: serde_json::Value =
        serde_json::from_slice(&tokio::fs::read(path).await.unwrap()).unwrap();
    mutate(&mut value);
    let mut bytes = serde_json::to_vec_pretty(&value).unwrap();
    bytes.push(b'\n');
    make_owner_writable(path, false).await;
    tokio::fs::write(path, &bytes).await.unwrap();
    let Some(name) = path.file_name().and_then(|name| name.to_str()) else {
        return;
    };
    let field = match name {
        "skill-bundle.json" => "manifestSha256",
        "skill-bundle.lock" => "lockSha256",
        _ => return,
    };
    let output = path
        .parent()
        .and_then(Path::parent)
        .and_then(Path::parent)
        .unwrap();
    let current_path = output.join("current");
    let mut current: serde_json::Value =
        serde_json::from_slice(&tokio::fs::read(&current_path).await.unwrap()).unwrap();
    current["active"][field] = serde_json::json!(hex::encode(Sha256::digest(&bytes)));
    let mut current_bytes = serde_json::to_vec_pretty(&current).unwrap();
    current_bytes.push(b'\n');
    tokio::fs::write(current_path, current_bytes).await.unwrap();
}

async fn make_owner_writable(path: &Path, directory: bool) {
    let mut permissions = tokio::fs::metadata(path).await.unwrap().permissions();
    #[cfg(unix)]
    {
        use std::os::unix::fs::PermissionsExt;
        let access = if directory { 0o300 } else { 0o200 };
        permissions.set_mode(permissions.mode() | access);
    }
    #[cfg(windows)]
    {
        let _ = directory;
        permissions.set_readonly(false);
    }
    tokio::fs::set_permissions(path, permissions).await.unwrap();
}

async fn make_directory_replaceable(path: &Path) {
    make_owner_writable(path, true).await;
    make_owner_writable(path.parent().unwrap(), true).await;
}

struct BundleReviewFixture {
    temp: tempfile::TempDir,
    source: std::path::PathBuf,
    output: std::path::PathBuf,
}

impl BundleReviewFixture {
    async fn new() -> Self {
        let temp = tempfile::tempdir().unwrap();
        let source = temp.path().join("source");
        let output = temp.path().join("bundle");
        write_runtime_package(&source.join("com.example.atomic")).await;
        Self {
            temp,
            source,
            output,
        }
    }

    fn package(&self) -> std::path::PathBuf {
        self.source.join("com.example.atomic")
    }

    fn request(&self) -> BuildSkillBundleRequest {
        BuildSkillBundleRequest {
            source_roots: vec![self.source.clone()],
            output_root: self.output.clone(),
            platform: PlatformId::Desktop,
            runtime_version: Version::new(0, 1, 0),
            generated_at: "2026-07-12T00:00:00Z".into(),
        }
    }
}

async fn write_runtime_package(root: &Path) {
    tokio::fs::create_dir_all(root).await.unwrap();
    let descriptor = serde_json::json!({
        "schemaVersion": 1,
        "id": "com.example.atomic",
        "version": "0.1.0",
        "displayName": "Atomic",
        "kind": "native_runtime",
        "package": { "includeInstructions": false, "includeRuntime": true },
        "compatibility": { "platforms": ["desktop"] },
        "requires": {
            "packages": [],
            "capabilities": ["shell.process"],
            "runtimeTools": [],
            "connectors": []
        }
    });
    let runtime = serde_json::json!({
        "name": "atomic",
        "description": "Atomic fixture.",
        "version": "0.1.0",
        "entry": { "type": "command", "command": "sh", "args": ["run.sh"] },
        "tools": [{
            "name": "run",
            "description": "Run.",
            "input_schema": { "type": "object" }
        }]
    });
    tokio::fs::write(
        root.join("agentweave.json"),
        serde_json::to_vec_pretty(&descriptor).unwrap(),
    )
    .await
    .unwrap();
    tokio::fs::write(
        root.join("skill.json"),
        serde_json::to_vec(&runtime).unwrap(),
    )
    .await
    .unwrap();
    tokio::fs::write(root.join("index.js"), "process.stdout.write('old')\n")
        .await
        .unwrap();
    tokio::fs::write(root.join("run.sh"), "printf '{\"ok\":true}'\n")
        .await
        .unwrap();
}

fn active_set(packages: Vec<crate::skill_source::DiscoveredSkillPackage>) -> ResolvedSkillSet {
    ResolvedSkillSet {
        active: packages
            .into_iter()
            .map(|package| ResolvedSkillPackage {
                package,
                status: SkillResolutionStatus::Active,
                reason: "active".into(),
            })
            .collect(),
        inactive: Vec::new(),
    }
}
