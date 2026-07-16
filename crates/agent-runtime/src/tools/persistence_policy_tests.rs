use super::*;

fn definition(permission: ToolPermission, persistence: ToolPersistence) -> ToolDefinition {
    ToolDefinition {
        name: "test_tool".into(),
        namespace: None,
        description: "Test persistence policy.".into(),
        input_schema: serde_json::json!({"type": "object"}),
        output_schema: None,
        permission,
        persistence,
        source: ToolSource::BuiltIn,
    }
}

#[test]
fn sensitive_permissions_force_metadata_only() {
    for permission in [
        ToolPermission::ReadSensitive,
        ToolPermission::CredentialAccess,
    ] {
        assert_eq!(
            definition(permission, ToolPersistence::Full).effective_persistence(),
            ToolPersistence::MetadataOnly
        );
    }
}

#[test]
fn missing_policy_deserializes_fail_closed() {
    let mut value = serde_json::to_value(definition(
        ToolPermission::ReadSensitive,
        ToolPersistence::Full,
    ))
    .unwrap();
    value.as_object_mut().unwrap().remove("persistence");

    let decoded: ToolDefinition = serde_json::from_value(value).unwrap();
    assert_eq!(decoded.persistence, ToolPersistence::MetadataOnly);
    assert_eq!(
        decoded.effective_persistence(),
        ToolPersistence::MetadataOnly
    );
}

#[test]
fn ordinary_tools_can_retain_full_persistence() {
    assert_eq!(
        definition(ToolPermission::ReadWorkspace, ToolPersistence::Full).effective_persistence(),
        ToolPersistence::Full
    );
}
