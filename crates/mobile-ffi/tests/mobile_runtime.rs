use agent_runtime::platform::PlatformId;
use agent_runtime::skill_bundle::{BuildSkillBundleRequest, build_skill_bundle};
use agent_runtime::skill_management::{CreateSkillDraftRequest, DraftFileUpdate};
use agent_runtime::skill_package::{SkillPackageId, SkillPackageKind};
use agent_runtime::skill_policy::{ActorContext, SkillGrant, SkillManagementPolicy};
use agent_runtime::skill_state::{NewSkillRevision, SkillStateStore};
use agent_runtime::storage::Storage;
use mobile_ffi::{MobileInitConfig, MobileRuntime};
use tempfile::tempdir;

fn android_config(root: &std::path::Path) -> MobileInitConfig {
    build_bundle(root, PlatformId::Android);
    mobile_config(root)
}

fn build_bundle(root: &std::path::Path, platform: PlatformId) {
    let app_data_dir = root.join("files");
    let builtin_skills_dir = app_data_dir.join("builtin-skills");
    let source_root = root.join("source-skills");
    std::fs::create_dir_all(&source_root).unwrap();
    let tokio = tokio::runtime::Runtime::new().unwrap();
    tokio
        .block_on(build_skill_bundle(BuildSkillBundleRequest {
            source_roots: vec![source_root],
            output_root: builtin_skills_dir.clone(),
            platform,
            runtime_version: "0.1.0".parse().unwrap(),
            generated_at: "2026-07-12T00:00:00Z".into(),
        }))
        .unwrap();
}

fn mobile_config(root: &std::path::Path) -> MobileInitConfig {
    let app_data_dir = root.join("files");
    let cache_dir = root.join("cache");
    let builtin_skills_dir = app_data_dir.join("builtin-skills");
    MobileInitConfig {
        app_data_dir: app_data_dir.display().to_string(),
        app_package_dir: None,
        cache_dir: cache_dir.display().to_string(),
        database_path: app_data_dir.join("agentweave.db").display().to_string(),
        builtin_skills_dir: builtin_skills_dir.display().to_string(),
        managed_skills_dir: app_data_dir.join("managed-skills").display().to_string(),
        staging_skills_dir: cache_dir.join("skill-staging").display().to_string(),
        quarantine_skills_dir: app_data_dir.join("skill-quarantine").display().to_string(),
        skill_policy: SkillManagementPolicy::default(),
        actor_context: ActorContext::anonymous(),
        platform: "android".into(),
        capabilities: vec![
            "network.http".into(),
            "filesystem.app_data".into(),
            "secure_storage".into(),
            "model.http_provider".into(),
        ],
        storage_protection_key_hex: None,
    }
}

fn write_instruction_package(
    skills_root: &std::path::Path,
    folder: &str,
    id: &str,
    name: &str,
    platform: &str,
) {
    let package_root = skills_root.join(folder);
    std::fs::create_dir_all(&package_root).unwrap();
    std::fs::write(
        package_root.join("agentweave.json"),
        serde_json::json!({
            "schemaVersion": 1,
            "id": id,
            "version": "1.0.0",
            "displayName": name,
            "kind": "instruction_only",
            "package": {
                "includeInstructions": true,
                "includeRuntime": false
            },
            "compatibility": {
                "platforms": [platform]
            }
        })
        .to_string(),
    )
    .unwrap();
    std::fs::write(
        package_root.join("SKILL.md"),
        format!("---\nname: {name}\ndescription: {name} instructions.\n---\n\n# {name}\n"),
    )
    .unwrap();
}

#[test]
fn initializes_runtime_and_returns_android_capabilities() {
    let dir = tempdir().unwrap();
    let runtime = MobileRuntime::initialize(android_config(dir.path())).unwrap();

    let diagnostics = runtime.diagnostics().unwrap();
    assert_eq!(diagnostics.platform, "android");
    assert!(diagnostics.capabilities.contains(&"network.http".into()));
    assert!(diagnostics.database_ready);
    assert_eq!(diagnostics.storage_protection_state, "not_provided");
}

#[test]
fn mobile_init_config_redacts_storage_protection_key() {
    let dir = tempdir().unwrap();
    let mut config = android_config(dir.path());
    let secret = "11".repeat(32);
    let mut wire = serde_json::to_value(&config).unwrap();
    wire["storage_protection_key_hex"] = serde_json::Value::String(secret.clone());
    config = serde_json::from_value(wire).unwrap();

    let debug = format!("{config:?}");
    let serialized = serde_json::to_string(&config).unwrap();

    assert!(!debug.contains(&secret));
    assert!(debug.contains("storage_protection_key_configured: true"));
    assert!(!serialized.contains(&secret));
    assert!(!serialized.contains("storage_protection_key_hex"));
}

#[test]
fn configured_mobile_storage_key_does_not_claim_active_protection_without_provider() {
    let dir = tempdir().unwrap();
    let mut config = android_config(dir.path());
    let database_path = config.database_path.clone();
    config.storage_protection_key_hex = Some("22".repeat(32));

    let runtime = MobileRuntime::initialize(config).unwrap();
    let diagnostics = runtime.diagnostics().unwrap();

    assert_eq!(diagnostics.storage_protection_state, "configured");
    let database_header = std::fs::read(database_path).unwrap();
    assert!(database_header.starts_with(b"SQLite format 3\0"));
}

#[test]
fn invalid_mobile_storage_key_is_not_echoed_in_errors() {
    let dir = tempdir().unwrap();
    let mut config = android_config(dir.path());
    let invalid_secret = "not-a-storage-key".repeat(4);
    config.storage_protection_key_hex = Some(invalid_secret.clone());

    let error = MobileRuntime::initialize(config).err().unwrap().to_string();

    assert!(!error.contains(&invalid_secret));
    assert!(error.contains("exactly 64 hexadecimal characters"));
}

#[test]
fn lists_instruction_only_skills_from_the_runtime_catalog() {
    let dir = tempdir().unwrap();
    write_instruction_package(
        &dir.path().join("source-skills"),
        "notes",
        "com.example.notes",
        "notes",
        "android",
    );

    let runtime = MobileRuntime::initialize(android_config(dir.path())).unwrap();
    let skills = runtime.list_skills().unwrap();

    assert_eq!(skills.len(), 1);
    assert_eq!(skills[0].package_id, "com.example.notes");
    assert_eq!(skills[0].display_name, "notes");
    assert!(skills[0].available);
    assert_eq!(skills[0].source_layer, "builtin");
}

#[test]
fn android_runtime_reports_platform_incompatible_bundle_packages() {
    let dir = tempdir().unwrap();
    let skills_root = dir.path().join("source-skills");
    write_instruction_package(
        &skills_root,
        "desktop",
        "com.example.desktop",
        "desktop-only",
        "desktop",
    );

    build_bundle(dir.path(), PlatformId::Desktop);
    let runtime = MobileRuntime::initialize(mobile_config(dir.path())).unwrap();
    let skills = runtime.list_skills().unwrap();

    assert_eq!(skills.len(), 1);
    assert_eq!(skills[0].package_id, "com.example.desktop");
    assert!(!skills[0].available);
    assert_eq!(skills[0].status, "platform_unsupported");
}

#[test]
fn owner_inventory_preserves_builtin_only_unavailable_effective_layer() {
    let dir = tempdir().unwrap();
    write_instruction_package(
        &dir.path().join("source-skills"),
        "desktop-owner",
        "com.example.desktop-owner",
        "Desktop Owner Skill",
        "desktop",
    );
    build_bundle(dir.path(), PlatformId::Desktop);
    let mut config = mobile_config(dir.path());
    config.skill_policy = SkillManagementPolicy::owner_only();
    config.actor_context = ActorContext::owner("inventory-owner", [SkillGrant::Inspect]);

    let skill = MobileRuntime::initialize(config)
        .unwrap()
        .list_skills()
        .unwrap()
        .remove(0);

    assert_eq!(skill.status, "platform_unsupported");
    assert!(!skill.available);
    assert_eq!(skill.source_layer, "builtin");
    assert_eq!(
        skill.effective.as_ref().map(|layer| layer.status.as_str()),
        Some("platform_unsupported")
    );
    assert!(skill.managed.is_none());
}

#[test]
fn android_init_uses_separate_skill_roots_and_disabled_policy_by_default() {
    let dir = tempdir().unwrap();
    write_instruction_package(
        &dir.path().join("source-skills"),
        "builtin",
        "com.example.builtin",
        "builtin",
        "android",
    );

    let runtime = MobileRuntime::initialize(android_config(dir.path())).unwrap();

    assert_eq!(
        runtime.diagnostics().unwrap().skill_management_mode,
        "disabled"
    );
    assert_eq!(runtime.list_skills().unwrap().len(), 1);
    assert_eq!(runtime.list_skills().unwrap()[0].source_layer, "builtin");
    assert!(!runtime.list_skills().unwrap()[0].built_in_collision);
}

#[test]
fn inventory_prefers_allowed_managed_override_as_active_winner() {
    let dir = tempdir().unwrap();
    let package_id = SkillPackageId::parse("com.example.layered").unwrap();
    write_instruction_package(
        &dir.path().join("source-skills"),
        "layered",
        package_id.as_str(),
        "Built-in Layer",
        "android",
    );
    let mut config = android_config(dir.path());
    config.skill_policy = SkillManagementPolicy::owner_only().allow_override(package_id.clone());
    let seeded = seed_managed_skill(&config, package_id.clone(), None);
    let skills = seeded.published_inventory;

    assert_eq!(skills.len(), 1);
    assert_eq!(skills[0].source_layer, "managed");
    assert_eq!(skills[0].status, "active");
    assert!(skills[0].available);
    assert!(skills[0].built_in_collision);
    assert_eq!(
        skills[0].active_revision_id.as_deref(),
        Some(seeded.revision_id.as_str())
    );
}

#[test]
fn inventory_prefers_builtin_when_managed_override_is_denied() {
    let dir = tempdir().unwrap();
    let package_id = SkillPackageId::parse("com.example.denied-layered").unwrap();
    write_instruction_package(
        &dir.path().join("source-skills"),
        "denied-layered",
        package_id.as_str(),
        "Built-in Winner",
        "android",
    );
    let mut allowed = android_config(dir.path());
    allowed.skill_policy = SkillManagementPolicy::owner_only().allow_override(package_id.clone());
    seed_managed_skill(&allowed, package_id, None);
    clear_skill_snapshots(&allowed);
    let mut denied = allowed;
    denied.skill_policy = SkillManagementPolicy::owner_only();

    let runtime = MobileRuntime::initialize(denied).unwrap();
    let skills = runtime.list_skills().unwrap();

    assert_eq!(skills.len(), 1);
    assert_eq!(skills[0].source_layer, "builtin");
    assert_eq!(skills[0].display_name, "Built-in Winner");
    assert_eq!(skills[0].status, "active");
    assert!(skills[0].available);
    assert!(skills[0].built_in_collision);
    assert_eq!(skills[0].active_revision_id, None);
}

#[test]
fn inventory_reports_authoritative_revision_for_inactive_managed_skill() {
    let dir = tempdir().unwrap();
    let package_id = SkillPackageId::parse("com.example.desktop-managed").unwrap();
    build_bundle(dir.path(), PlatformId::Desktop);
    let mut desktop = mobile_config(dir.path());
    desktop.platform = "desktop".into();
    desktop.skill_policy = SkillManagementPolicy::owner_only();
    let descriptor = serde_json::json!({
        "schemaVersion": 1,
        "id": package_id.as_str(),
        "version": "0.1.0",
        "displayName": "Desktop Managed",
        "kind": "instruction_only",
        "package": {"includeInstructions": true, "includeRuntime": false},
        "compatibility": {"platforms": ["desktop"]}
    })
    .to_string();
    let seeded = seed_managed_skill(&desktop, package_id, Some(descriptor));
    clear_skill_snapshots(&desktop);
    let mut android = desktop;
    android.platform = "android".into();

    let runtime = MobileRuntime::initialize(android.clone()).unwrap();
    let skills = runtime.list_skills().unwrap();

    assert_eq!(skills.len(), 1);
    assert_eq!(skills[0].source_layer, "managed");
    assert_eq!(skills[0].status, "platform_unsupported");
    assert!(!skills[0].available);
    assert_eq!(
        skills[0].active_revision_id.as_deref(),
        Some(seeded.revision_id.as_str())
    );

    let replacement = uuid::Uuid::new_v4().to_string();
    tokio::runtime::Runtime::new().unwrap().block_on(async {
        let pool = sqlx::SqlitePool::connect(&format!("sqlite://{}", android.database_path))
            .await
            .unwrap();
        sqlx::query(
            "INSERT INTO skill_revisions (revision_id, package_id, version, content_hash, storage_path, descriptor_json, validation_json, created_by, created_at, lifecycle_status) SELECT ?, package_id, version, 'different-content-hash', ?, descriptor_json, validation_json, created_by, created_at, lifecycle_status FROM skill_revisions WHERE revision_id = ?",
        )
        .bind(&replacement)
        .bind(format!("managed/{replacement}"))
        .bind(&seeded.revision_id)
        .execute(&pool)
        .await
        .unwrap();
        sqlx::query("UPDATE skill_installations SET active_revision_id = ? WHERE package_id = ?")
            .bind(&replacement)
            .bind("com.example.desktop-managed")
            .execute(&pool)
            .await
            .unwrap();
    });

    let error = runtime
        .list_skills()
        .expect_err("inventory must reject a revision changed after the captured snapshot");
    assert!(error.to_string().contains("content"));
}

#[test]
fn quarantine_count_uses_authoritative_revision_rows_with_internal_directories_present() {
    let dir = tempdir().unwrap();
    let config = android_config(dir.path());
    let runtime = MobileRuntime::initialize(config.clone()).unwrap();
    let revision_id = uuid::Uuid::new_v4().to_string();
    let tokio = tokio::runtime::Runtime::new().unwrap();
    tokio.block_on(async {
        let storage = Storage::connect(&format!("sqlite://{}?mode=rwc", config.database_path))
            .await
            .unwrap();
        SkillStateStore::new(storage)
            .create_quarantined_revision_record(
                &revision_id,
                NewSkillRevision {
                    package_id: SkillPackageId::parse("com.example.quarantined").unwrap(),
                    version: "1.0.0".into(),
                    content_hash: "quarantined-hash".into(),
                    storage_path: format!("quarantine/{revision_id}"),
                    descriptor_json: serde_json::json!({}),
                    validation_json: serde_json::json!({"quarantined": true}),
                    created_by: "recovery".into(),
                },
            )
            .await
            .unwrap();
    });
    let quarantine = std::path::Path::new(&config.quarantine_skills_dir);
    std::fs::create_dir_all(quarantine.join(".incoming")).unwrap();
    std::fs::create_dir_all(quarantine.join(".maintenance")).unwrap();
    std::fs::create_dir_all(quarantine.join(&revision_id)).unwrap();

    assert_eq!(runtime.diagnostics().unwrap().quarantined_count, 1);
}

#[test]
fn rejects_database_path_inside_a_skill_root() {
    let dir = tempdir().unwrap();
    let mut config = android_config(dir.path());
    config.database_path = std::path::Path::new(&config.managed_skills_dir)
        .join("runtime.db")
        .display()
        .to_string();

    let error = MobileRuntime::initialize(config)
        .err()
        .expect("database inside managed skill root should fail");

    assert!(error.to_string().contains("database path"));
}

#[test]
fn rejects_database_path_equal_to_a_skill_root() {
    let dir = tempdir().unwrap();
    let mut config = android_config(dir.path());
    config.database_path = config.quarantine_skills_dir.clone();

    let error = MobileRuntime::initialize(config)
        .err()
        .expect("database equal to quarantine root should fail");

    assert!(error.to_string().contains("database path"));
}

#[test]
fn inventory_propagates_authoritative_state_read_failures() {
    let dir = tempdir().unwrap();
    let config = android_config(dir.path());
    let runtime = MobileRuntime::initialize(config.clone()).unwrap();
    tokio::runtime::Runtime::new().unwrap().block_on(async {
        let pool = sqlx::SqlitePool::connect(&format!("sqlite://{}", config.database_path))
            .await
            .unwrap();
        sqlx::query("DROP TABLE skill_snapshots")
            .execute(&pool)
            .await
            .unwrap();
    });

    let error = runtime
        .list_skills()
        .expect_err("inventory state failure should propagate");

    assert!(error.to_string().contains("skill_snapshots"));
}

#[test]
fn rejects_unverified_builtin_directory_without_development_fallback() {
    let dir = tempdir().unwrap();
    let mut config = android_config(dir.path());
    config.builtin_skills_dir = dir.path().join("source-skills").display().to_string();

    MobileRuntime::initialize(config)
        .err()
        .expect("unverified built-in directory should fail closed");
}

#[test]
fn generated_bundle_round_trips_from_installed_revision_layout() {
    let dir = tempdir().unwrap();
    build_bundle(dir.path(), PlatformId::Android);
    let generated = dir.path().join("files/builtin-skills");
    let installed = dir
        .path()
        .join("files/builtin-revisions/revisions/content-hash");
    std::fs::create_dir_all(installed.parent().unwrap()).unwrap();
    std::fs::rename(&generated, &installed).unwrap();
    let mut config = mobile_config(dir.path());
    config.builtin_skills_dir = installed.display().to_string();

    let runtime = MobileRuntime::initialize(config).unwrap();

    assert!(runtime.list_skills().unwrap().is_empty());
    assert!(runtime.diagnostics().unwrap().skills_ready);
}

fn seed_managed_skill(
    config: &MobileInitConfig,
    package_id: SkillPackageId,
    descriptor: Option<String>,
) -> SeededManagedSkill {
    let grants = [
        SkillGrant::Inspect,
        SkillGrant::CreateDraft,
        SkillGrant::EditDraft,
        SkillGrant::Validate,
        SkillGrant::Activate,
        SkillGrant::OverrideBuiltin,
    ];
    let mut requester_config = config.clone();
    requester_config.actor_context = ActorContext::owner("inventory-requester", grants);
    let requester = MobileRuntime::initialize(requester_config).unwrap();
    let draft = requester
        .create_skill_draft(CreateSkillDraftRequest {
            package_id,
            display_name: "Managed Layer".into(),
            description: "Managed inventory layer.".into(),
            kind: SkillPackageKind::InstructionOnly,
            required_tools: Vec::new(),
        })
        .unwrap();
    if let Some(descriptor) = descriptor {
        requester
            .update_skill_draft(
                &draft.revision_id,
                vec![DraftFileUpdate {
                    path: "agentweave.json".into(),
                    content: descriptor,
                }],
            )
            .unwrap();
    }
    requester.validate_skill_draft(&draft.revision_id).unwrap();
    let approval = requester
        .request_skill_activation(&draft.revision_id)
        .unwrap();
    let approval_id = approval["approval_id"].as_str().unwrap();
    let mut approver_config = config.clone();
    approver_config.actor_context = ActorContext::owner("inventory-approver", grants);
    let approver = MobileRuntime::initialize(approver_config).unwrap();
    approver.resolve_skill_approval(approval_id, true).unwrap();
    SeededManagedSkill {
        revision_id: draft.revision_id,
        published_inventory: approver.list_skills().unwrap(),
    }
}

struct SeededManagedSkill {
    revision_id: String,
    published_inventory: Vec<mobile_ffi::MobileSkillDto>,
}

fn clear_skill_snapshots(config: &MobileInitConfig) {
    tokio::runtime::Runtime::new().unwrap().block_on(async {
        let pool = sqlx::SqlitePool::connect(&format!("sqlite://{}", config.database_path))
            .await
            .unwrap();
        sqlx::query("DELETE FROM skill_snapshots")
            .execute(&pool)
            .await
            .unwrap();
    });
}

#[test]
fn rejects_database_path_with_parent_dir_traversal() {
    let dir = tempdir().unwrap();
    let app_data_dir = dir.path().join("files");
    let mut config = android_config(dir.path());
    config.database_path = app_data_dir.join("../escape.db").display().to_string();
    let error = MobileRuntime::initialize(config)
        .err()
        .expect("database path traversal should fail");

    assert!(error.to_string().contains("app-private"));
}

#[test]
fn rejects_managed_skills_dir_with_parent_dir_traversal() {
    let dir = tempdir().unwrap();
    let app_data_dir = dir.path().join("files");

    let mut config = android_config(dir.path());
    config.managed_skills_dir = app_data_dir.join("../skills").display().to_string();
    let error = MobileRuntime::initialize(config)
        .err()
        .expect("skills path traversal should fail");

    assert!(error.to_string().contains("app-private"));
}

#[test]
fn rejects_absolute_builtin_skills_dir_outside_app_private_roots() {
    let dir = tempdir().unwrap();
    let outside_dir = tempdir().unwrap();

    let mut config = android_config(dir.path());
    config.builtin_skills_dir = outside_dir.path().join("skills").display().to_string();
    let error = MobileRuntime::initialize(config)
        .err()
        .expect("absolute skills dir outside app-private roots should fail");

    assert!(error.to_string().contains("app-private"));
}

#[cfg(unix)]
mod unix_symlink_tests {
    use super::*;
    use std::os::unix::fs::symlink;

    #[test]
    fn rejects_symlink_escape_in_database_parent() {
        let dir = tempdir().unwrap();
        let outside_dir = tempdir().unwrap();
        let app_data_dir = dir.path().join("files");
        let escape_link = app_data_dir.join("escape");

        std::fs::create_dir_all(&app_data_dir).unwrap();
        symlink(outside_dir.path(), &escape_link).unwrap();

        let mut config = android_config(dir.path());
        config.database_path = escape_link.join("agentweave.db").display().to_string();
        let error = MobileRuntime::initialize(config)
            .err()
            .expect("database path via symlink escape should fail");

        assert!(error.to_string().contains("app-private"));
    }

    #[test]
    fn rejects_symlink_escape_in_builtin_skills_dir() {
        let dir = tempdir().unwrap();
        let outside_dir = tempdir().unwrap();
        let app_data_dir = dir.path().join("files");
        let escape_link = app_data_dir.join("escape");

        std::fs::create_dir_all(&app_data_dir).unwrap();
        symlink(outside_dir.path(), &escape_link).unwrap();

        let mut config = android_config(dir.path());
        config.builtin_skills_dir = escape_link.join("skills").display().to_string();
        let error = MobileRuntime::initialize(config)
            .err()
            .expect("skills path via symlink escape should fail");

        assert!(error.to_string().contains("app-private"));
    }
}
