use super::*;

fn test_root() -> PathBuf {
    std::env::temp_dir().join(format!(
        "agentweave-dev-authoring-delete-dependent-rollback-{}",
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

#[tokio::test]
async fn delete_rolls_back_when_another_package_requires_the_candidate() {
    let root = test_root();
    tokio::fs::create_dir_all(&root).await.unwrap();
    let created = create_skill(
        &root,
        DevSkillCreateRequest {
            directory: "planning".into(),
            skill_md:
                "---\nname: planning\ndescription: Plan work.\n---\n\n# Planning\n\nOriginal.\n"
                    .into(),
            manifest: manifest(),
        },
    )
    .await
    .unwrap();
    let mut dependent_manifest = manifest();
    dependent_manifest["id"] = serde_json::json!("com.example.dependent");
    dependent_manifest["displayName"] = serde_json::json!("Dependent");
    dependent_manifest["requires"]["packages"] = serde_json::json!(["com.example.planning"]);
    create_skill(
        &root,
        DevSkillCreateRequest {
            directory: "dependent".into(),
            skill_md:
                "---\nname: dependent\ndescription: Depend on planning.\n---\n\n# Dependent\n"
                    .into(),
            manifest: dependent_manifest,
        },
    )
    .await
    .unwrap();

    let error = delete_skill(
        &root,
        "planning",
        DevSkillDeleteRequest {
            expected_revision: created.source.source_revision,
        },
    )
    .await
    .unwrap_err();

    assert!(error.to_string().contains("inventory validation failed"));
    assert!(root.join("planning/SKILL.md").is_file());
    assert!(root.join("dependent/SKILL.md").is_file());
    let entries = std::fs::read_dir(&root)
        .unwrap()
        .map(|entry| entry.unwrap().file_name())
        .collect::<Vec<_>>();
    assert!(
        entries
            .iter()
            .all(|name| !name.to_string_lossy().starts_with(".agentweave-"))
    );
    let _ = tokio::fs::remove_dir_all(root).await;
}
