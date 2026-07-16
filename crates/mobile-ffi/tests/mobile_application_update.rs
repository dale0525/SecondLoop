use agent_runtime::platform::PlatformId;
use agent_runtime::skill_bundle::{BuildSkillBundleRequest, build_skill_bundle};
use agent_runtime::skill_policy::{ActorContext, SkillGrant, SkillManagementPolicy};
use mobile_ffi::{
    MobileInitConfig, MobileRuntime, close_runtime, initialize_runtime_json, invoke_runtime_json,
};
use serde_json::{Value, json};
use tempfile::tempdir;

#[test]
fn mobile_application_update_retains_compatible_managed_revision() {
    let dir = tempdir().unwrap();
    write_bundle_instruction_package(
        &dir.path().join("source-skills/builtin"),
        "1.0.0",
        "Builtin v1",
    );
    let mut requester_config = init_config(dir.path());
    requester_config.skill_policy = SkillManagementPolicy::owner_only();
    requester_config.actor_context = ActorContext::owner(
        "update-requester",
        [
            SkillGrant::Inspect,
            SkillGrant::CreateDraft,
            SkillGrant::Validate,
            SkillGrant::Activate,
        ],
    );
    let requester = initialize_handle(&requester_config);
    let mut approver_config = requester_config.clone();
    approver_config.actor_context = ActorContext::owner("update-approver", [SkillGrant::Activate]);
    let approver = initialize_handle(&approver_config);
    let draft = invoke_value(
        requester,
        json!({
            "operation": "create_skill_draft",
            "request": {
                "package_id": "com.example.mobile-retained",
                "display_name": "Retained managed",
                "description": "Compatible across application updates.",
                "kind": "instruction_only",
                "required_tools": []
            },
            "files": initial_draft_files()
        }),
    );
    let revision_id = draft["revision_id"].as_str().unwrap().to_string();
    invoke_value(
        requester,
        json!({"operation": "validate_skill_draft", "revision_id": revision_id}),
    );
    let approval = invoke_value(
        requester,
        json!({"operation": "request_skill_activation", "revision_id": revision_id}),
    );
    invoke_value(
        approver,
        json!({
            "operation": "resolve_skill_approval",
            "approval_id": approval["approval_id"],
            "approve": true
        }),
    );
    close_runtime(requester);
    close_runtime(approver);

    write_bundle_instruction_package(
        &dir.path().join("source-skills/builtin"),
        "2.0.0",
        "Builtin v2 application update",
    );
    let mut updated_config = init_config(dir.path());
    updated_config.skill_policy = SkillManagementPolicy::owner_only();
    updated_config.actor_context = ActorContext::owner("update-reader", [SkillGrant::Inspect]);
    let updated = MobileRuntime::initialize(updated_config).unwrap();
    let managed = updated.list_managed_skills().unwrap();

    assert_eq!(managed.len(), 1);
    assert_eq!(
        managed[0].package_id.as_str(),
        "com.example.mobile-retained"
    );
    assert_eq!(managed[0].status, "active");
    assert_eq!(
        managed[0].active_revision_id.as_deref(),
        Some(revision_id.as_str())
    );
}

fn init_config(root: &std::path::Path) -> MobileInitConfig {
    let app_data_dir = root.join("files");
    let cache_dir = root.join("cache");
    let builtin_skills_dir = app_data_dir.join("builtin-skills");
    let source_root = root.join("source-skills");
    std::fs::create_dir_all(&source_root).unwrap();
    tokio::runtime::Runtime::new()
        .unwrap()
        .block_on(build_skill_bundle(BuildSkillBundleRequest {
            source_roots: vec![source_root],
            output_root: builtin_skills_dir.clone(),
            platform: PlatformId::Android,
            runtime_version: "0.1.0".parse().unwrap(),
            generated_at: "2026-07-13T00:00:00Z".into(),
        }))
        .unwrap();
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

fn initial_draft_files() -> Value {
    json!([
        {
            "path": "SKILL.md",
            "content": "---\nname: retained-managed\ndescription: Retained managed evidence.\n---\n\nRETAINED_MANAGED_MOBILE_EVIDENCE"
        },
        {
            "path": "agentweave.json",
            "content": serde_json::to_string_pretty(&json!({
                "schemaVersion": 1,
                "id": "com.example.mobile-retained",
                "version": "0.1.0",
                "displayName": "Retained managed",
                "kind": "instruction_only",
                "package": {"includeInstructions": true, "includeRuntime": false},
                "compatibility": {"minimumRuntimeVersion": null, "platforms": []},
                "requires": {
                    "packages": [],
                    "capabilities": [],
                    "runtimeTools": [],
                    "connectors": []
                }
            })).unwrap()
        }
    ])
}

fn initialize_handle(config: &MobileInitConfig) -> i64 {
    let response: Value = serde_json::from_str(&initialize_runtime_json(
        &serde_json::to_string(config).unwrap(),
    ))
    .unwrap();
    assert_eq!(response["ok"], true, "{response}");
    response["data"]["handle"].as_i64().unwrap()
}

fn invoke_value(handle: i64, request: Value) -> Value {
    let response: Value =
        serde_json::from_str(&invoke_runtime_json(handle, &request.to_string())).unwrap();
    assert_eq!(response["ok"], true, "{response}");
    response["data"].clone()
}

fn write_bundle_instruction_package(root: &std::path::Path, version: &str, instructions: &str) {
    std::fs::create_dir_all(root).unwrap();
    std::fs::write(
        root.join("SKILL.md"),
        format!(
            "---\nname: mobile-builtin\ndescription: Mobile builtin instructions.\n---\n\n{instructions}\n"
        ),
    )
    .unwrap();
    std::fs::write(
        root.join("agentweave.json"),
        serde_json::to_vec_pretty(&json!({
            "schemaVersion": 1,
            "id": "com.example.mobile-builtin",
            "version": version,
            "displayName": "Mobile builtin",
            "kind": "instruction_only",
            "package": {"includeInstructions": true, "includeRuntime": false},
            "compatibility": {"platforms": ["android"]},
            "requires": {
                "packages": [],
                "capabilities": [],
                "runtimeTools": [],
                "connectors": []
            }
        }))
        .unwrap(),
    )
    .unwrap();
}
