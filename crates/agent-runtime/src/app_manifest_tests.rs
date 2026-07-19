use super::*;
use serde_json::{Value, json};
use std::fs;
use tempfile::TempDir;

fn valid_manifest() -> Value {
    json!({
        "schemaVersion": 1,
        "appId": "com.example.secretary",
        "package": {
            "id": "com.example.secretary-app",
            "version": "1.2.3"
        },
        "compatibility": {
            "runtime": ">=0.1.0, <2.0.0",
            "platforms": ["desktop", "android", "server"]
        },
        "requires": {
            "packages": [
                { "id": "com.example.calendar", "version": "^2.0.0" },
                { "id": "com.example.mail", "version": ">=1.4.0, <2.0.0" }
            ],
            "capabilities": ["calendar.read", "mail.read"],
            "runtimeTools": ["calendar.search", "mail.search"],
            "connectors": ["google.calendar", "google.gmail"]
        },
        "features": ["daily.briefing", "meeting.preparation"],
        "policy": {
            "externalSideEffects": "require_approval",
            "network": "declared_only",
            "backgroundExecution": "declared_only",
            "memoryPersistence": "local_only",
            "skillManagement": "owner_only"
        },
        "branding": {
            "displayName": "Example Secretary",
            "shortName": "Secretary",
            "description": "A private personal secretary.",
            "icon": "assets/icon.svg",
            "wordmark": "assets/wordmark.svg",
            "accentColor": "#3366CC"
        },
        "instructions": {
            "system": "instructions/system.md",
            "developer": "instructions/developer.md",
            "additional": ["instructions/privacy.md"]
        }
    })
}

fn valid_v2_manifest() -> Value {
    let mut value = valid_manifest();
    value["schemaVersion"] = json!(2);
    value["modelAccess"] = json!({
        "configurationPolicy": "app_managed",
        "profile": {
            "providerId": "example.gateway",
            "endpointType": "responses",
            "baseUrl": "https://gateway.example.test/v1",
            "modelName": "assistant-model",
            "authentication": "user_identity",
            "headers": {"X-App-Version": "1"}
        }
    });
    value["identity"] = json!({
        "mode": "required",
        "provider": {
            "id": "agentweave.identity.oidc",
            "version": "^1.0.0",
            "publicConfig": {
                "issuer": "https://identity.example.test",
                "clientId": "public-desktop-client",
                "audience": "com.example.secretary.gateway"
            }
        }
    });
    value["entitlements"] = json!({
        "mode": "required",
        "provider": {
            "id": "agentweave.entitlements.http",
            "version": "^1.0.0",
            "publicConfig": {"endpoint": "https://access.example.test/v1"}
        }
    });
    value
}

fn manifest_bytes(value: &Value) -> Vec<u8> {
    serde_json::to_vec(value).unwrap()
}

fn create_package(value: &Value) -> TempDir {
    let temp = TempDir::new().unwrap();
    for directory in ["assets", "instructions"] {
        fs::create_dir_all(temp.path().join(directory)).unwrap();
    }
    for resource in [
        "assets/icon.svg",
        "assets/wordmark.svg",
        "instructions/system.md",
        "instructions/developer.md",
        "instructions/privacy.md",
    ] {
        fs::write(temp.path().join(resource), format!("resource:{resource}")).unwrap();
    }
    fs::write(
        temp.path().join(AGENT_APP_MANIFEST_FILE),
        manifest_bytes(value),
    )
    .unwrap();
    temp
}

#[test]
fn parses_complete_v1_manifest_and_platform_aliases() {
    let mut value = valid_manifest();
    value["compatibility"]["platforms"] = json!(["macos", "windows", "android"]);

    let manifest = AgentAppManifest::parse_json(&manifest_bytes(&value)).unwrap();

    assert_eq!(manifest.app_id.as_str(), "com.example.secretary");
    assert_eq!(manifest.package.id.as_str(), "com.example.secretary-app");
    assert_eq!(manifest.package.version, Version::new(1, 2, 3));
    assert_eq!(
        manifest.compatibility.platforms,
        BTreeSet::from([AgentAppPlatform::Desktop, AgentAppPlatform::Android])
    );
    assert!(manifest.supports_platform(PlatformId::Desktop));
    assert!(manifest.supports_platform(PlatformId::Android));
    assert!(!manifest.supports_platform(PlatformId::Server));
}

#[test]
fn empty_platform_set_means_all_compatible_platforms() {
    let mut value = valid_manifest();
    value["compatibility"]["platforms"] = json!([]);
    let manifest = AgentAppManifest::parse_json(&manifest_bytes(&value)).unwrap();

    for platform in [
        PlatformId::Desktop,
        PlatformId::Android,
        PlatformId::Ios,
        PlatformId::Web,
        PlatformId::Server,
    ] {
        assert!(manifest.supports_platform(platform));
    }
}

#[test]
fn rejects_unknown_fields_at_root_and_nested_levels() {
    let mut root = valid_manifest();
    root["extension"] = json!(true);
    let error = AgentAppManifest::parse_json(&manifest_bytes(&root)).unwrap_err();
    assert!(error.to_string().contains("unknown field"));

    let mut nested = valid_manifest();
    nested["branding"]["theme"] = json!("dark");
    let error = AgentAppManifest::parse_json(&manifest_bytes(&nested)).unwrap_err();
    assert!(error.to_string().contains("unknown field"));
}

#[test]
fn rejects_unsupported_schema_versions() {
    let mut value = valid_manifest();
    value["schemaVersion"] = json!(3);

    let error = AgentAppManifest::parse_json(&manifest_bytes(&value)).unwrap_err();

    assert!(
        error
            .to_string()
            .contains("unsupported agent app manifest schema version 3")
    );
}

#[test]
fn parses_complete_v2_access_configuration() {
    let manifest = AgentAppManifest::parse_json(&manifest_bytes(&valid_v2_manifest())).unwrap();

    assert_eq!(manifest.schema_version, 2);
    assert_eq!(
        manifest
            .identity
            .as_ref()
            .and_then(|identity| identity.provider.as_ref())
            .unwrap()
            .id
            .as_str(),
        "agentweave.identity.oidc"
    );
    assert_eq!(
        manifest
            .model_access
            .as_ref()
            .and_then(|access| access.profile.as_ref())
            .unwrap()
            .authentication,
        AgentAppModelAuthentication::UserIdentity
    );
}

#[test]
fn v1_cannot_smuggle_v2_access_fields() {
    let mut value = valid_manifest();
    value["identity"] = json!({"mode": "local_single_user", "provider": null});

    let error = AgentAppManifest::parse_json(&manifest_bytes(&value)).unwrap_err();

    assert!(
        error
            .to_string()
            .contains("schema version 1 cannot declare")
    );
}

#[test]
fn v2_requires_every_access_section() {
    for missing in ["modelAccess", "identity", "entitlements"] {
        let mut value = valid_v2_manifest();
        value.as_object_mut().unwrap().remove(missing);
        let error = AgentAppManifest::parse_json(&manifest_bytes(&value)).unwrap_err();
        assert!(
            error.to_string().contains(missing),
            "unexpected error when {missing} is missing: {error:#}"
        );
    }
}

#[test]
fn provider_modes_require_exact_provider_presence() {
    let mut missing = valid_v2_manifest();
    missing["identity"]["provider"] = Value::Null;
    assert!(
        AgentAppManifest::parse_json(&manifest_bytes(&missing))
            .unwrap_err()
            .to_string()
            .contains("requires a provider")
    );

    let mut unexpected = valid_v2_manifest();
    unexpected["entitlements"]["mode"] = json!("disabled");
    assert!(
        AgentAppManifest::parse_json(&manifest_bytes(&unexpected))
            .unwrap_err()
            .to_string()
            .contains("provider is forbidden")
    );
}

#[test]
fn remote_app_managed_profile_requires_identity_and_entitlements() {
    let mut anonymous = valid_v2_manifest();
    anonymous["modelAccess"]["profile"]["authentication"] = json!("none");
    assert!(
        AgentAppManifest::parse_json(&manifest_bytes(&anonymous))
            .unwrap_err()
            .to_string()
            .contains("requires user_identity")
    );

    let mut unmetered = valid_v2_manifest();
    unmetered["entitlements"] = json!({"mode": "disabled", "provider": null});
    assert!(
        AgentAppManifest::parse_json(&manifest_bytes(&unmetered))
            .unwrap_err()
            .to_string()
            .contains("requires entitlements.mode=required")
    );
}

#[test]
fn loopback_app_managed_profile_can_be_device_local() {
    let mut value = valid_v2_manifest();
    value["modelAccess"]["profile"]["baseUrl"] = json!("http://127.0.0.1:11434/v1");
    value["modelAccess"]["profile"]["authentication"] = json!("none");
    value["identity"] = json!({"mode": "local_single_user", "provider": null});
    value["entitlements"] = json!({"mode": "disabled", "provider": null});

    AgentAppManifest::parse_json(&manifest_bytes(&value)).unwrap();
}

#[test]
fn model_profile_rejects_insecure_remote_urls_and_sensitive_headers() {
    let mut insecure = valid_v2_manifest();
    insecure["modelAccess"]["profile"]["baseUrl"] = json!("http://gateway.example.test/v1");
    assert!(
        AgentAppManifest::parse_json(&manifest_bytes(&insecure))
            .unwrap_err()
            .to_string()
            .contains("must use HTTPS")
    );

    let mut sensitive = valid_v2_manifest();
    sensitive["modelAccess"]["profile"]["headers"] =
        json!({"Authorization": "must-not-be-packaged"});
    assert!(
        AgentAppManifest::parse_json(&manifest_bytes(&sensitive))
            .unwrap_err()
            .to_string()
            .contains("sensitive header")
    );
}

#[test]
fn provider_public_config_is_bounded_and_cannot_contain_credentials() {
    let mut scalar = valid_v2_manifest();
    scalar["identity"]["provider"]["publicConfig"] = json!("not-an-object");
    assert!(
        AgentAppManifest::parse_json(&manifest_bytes(&scalar))
            .unwrap_err()
            .to_string()
            .contains("must be an object")
    );

    let mut secret = valid_v2_manifest();
    secret["identity"]["provider"]["publicConfig"]["apiKey"] = json!("forbidden");
    assert!(
        AgentAppManifest::parse_json(&manifest_bytes(&secret))
            .unwrap_err()
            .to_string()
            .contains("must not contain credential field")
    );
}

#[test]
fn rejects_unstable_ids_and_invalid_semver() {
    let mut app_id = valid_manifest();
    app_id["appId"] = json!("Example.Secretary");
    assert!(AgentAppManifest::parse_json(&manifest_bytes(&app_id)).is_err());

    let mut package_id = valid_manifest();
    package_id["package"]["id"] = json!("secretary");
    assert!(AgentAppManifest::parse_json(&manifest_bytes(&package_id)).is_err());

    let mut version = valid_manifest();
    version["package"]["version"] = json!("v1");
    assert!(AgentAppManifest::parse_json(&manifest_bytes(&version)).is_err());
}

#[test]
fn rejects_duplicate_package_requirements() {
    let mut value = valid_manifest();
    value["requires"]["packages"] = json!([
        { "id": "com.example.mail", "version": "^1.0" },
        { "id": "com.example.mail", "version": "^2.0" }
    ]);

    let error = AgentAppManifest::parse_json(&manifest_bytes(&value)).unwrap_err();

    assert!(
        error
            .to_string()
            .contains("duplicate required app package id")
    );
}

#[test]
fn validates_packaged_theme_selection_and_custom_theme_resources() {
    let mut value = valid_manifest();
    value["appearance"] = json!({
        "defaultTheme": "com.example.brand-dark",
        "themes": {
            "builtins": ["vscode.dark-2026", "vscode.light-2026"],
            "custom": [{
                "id": "com.example.brand-dark",
                "label": "Brand Dark",
                "path": "themes/brand-dark.jsonc"
            }]
        }
    });

    let manifest = AgentAppManifest::parse_json(&manifest_bytes(&value)).unwrap();
    let appearance = manifest.appearance.as_ref().unwrap();
    assert_eq!(appearance.default_theme.as_str(), "com.example.brand-dark");
    assert_eq!(appearance.themes.custom.len(), 1);

    let mut unsupported = value.clone();
    unsupported["appearance"]["themes"]["builtins"] = json!(["vscode.unknown"]);
    assert!(
        AgentAppManifest::parse_json(&manifest_bytes(&unsupported))
            .unwrap_err()
            .to_string()
            .contains("unsupported built-in App theme")
    );

    let mut unselected_default = value;
    unselected_default["appearance"]["defaultTheme"] = json!("com.example.missing");
    assert!(
        AgentAppManifest::parse_json(&manifest_bytes(&unselected_default))
            .unwrap_err()
            .to_string()
            .contains("defaultTheme")
    );
}

#[test]
fn validates_localization_catalog_selection() {
    let mut value = valid_manifest();
    value["localization"] = json!({
        "defaultLocale": "en",
        "locales": [
            {"id": "en", "label": "English", "resource": "locales/en.json"},
            {"id": "zh-CN", "label": "简体中文", "resource": "locales/zh-CN.json"}
        ]
    });

    let manifest = AgentAppManifest::parse_json(&manifest_bytes(&value)).unwrap();
    let localization = manifest.localization.as_ref().unwrap();
    assert_eq!(localization.default_locale.as_str(), "en");
    assert_eq!(localization.locales[1].id.as_str(), "zh-CN");

    let mut missing_default = value.clone();
    missing_default["localization"]["defaultLocale"] = json!("fr");
    assert!(
        AgentAppManifest::parse_json(&manifest_bytes(&missing_default))
            .unwrap_err()
            .to_string()
            .contains("defaultLocale")
    );

    let mut invalid_resource = value.clone();
    invalid_resource["localization"]["locales"][0]["resource"] = json!("translations/en.json");
    assert!(
        AgentAppManifest::parse_json(&manifest_bytes(&invalid_resource))
            .unwrap_err()
            .to_string()
            .contains("locales directory")
    );
}

#[test]
fn rejects_absolute_parent_and_nonportable_resource_paths() {
    for invalid in [
        "/etc/passwd",
        "../outside.md",
        "instructions/../outside.md",
        "C:\\Windows\\secret.txt",
        "instructions\\system.md",
        "instructions//system.md",
    ] {
        let mut value = valid_manifest();
        value["instructions"]["system"] = json!(invalid);
        let error = AgentAppManifest::parse_json(&manifest_bytes(&value)).unwrap_err();
        assert!(
            error.to_string().contains("app resource path"),
            "unexpected error for {invalid}: {error:#}"
        );
    }
}

#[test]
fn explicitly_rejects_credential_shaped_fields() {
    for field in ["apiKey", "oauthToken", "clientSecret", "password"] {
        let mut value = valid_manifest();
        value["policy"][field] = json!("must-not-live-here");
        let error = AgentAppManifest::parse_json(&manifest_bytes(&value)).unwrap_err();
        assert!(
            error
                .to_string()
                .contains("must not contain credential field"),
            "unexpected error for {field}: {error:#}"
        );
    }
}

#[test]
fn canonical_json_and_hash_ignore_set_and_requirement_input_order() {
    let first = valid_manifest();
    let mut second = valid_manifest();
    second["compatibility"]["platforms"] = json!(["server", "android", "linux"]);
    second["requires"]["packages"] = json!([
        { "id": "com.example.mail", "version": ">=1.4.0, <2.0.0" },
        { "id": "com.example.calendar", "version": "^2.0.0" }
    ]);
    second["requires"]["capabilities"] = json!(["mail.read", "calendar.read"]);
    second["features"] = json!(["meeting.preparation", "daily.briefing"]);

    let first = AgentAppManifest::parse_json(&manifest_bytes(&first)).unwrap();
    let second = AgentAppManifest::parse_json(&manifest_bytes(&second)).unwrap();

    assert_eq!(
        first.canonical_json().unwrap(),
        second.canonical_json().unwrap()
    );
    assert_eq!(
        first.canonical_sha256().unwrap(),
        second.canonical_sha256().unwrap()
    );
    assert_eq!(first.canonical_sha256().unwrap().len(), 64);
}

#[tokio::test]
async fn loads_manifest_and_resolves_all_resources_inside_canonical_root() {
    let package = create_package(&valid_manifest());

    let loaded = AgentAppManifest::load(package.path()).await.unwrap();

    assert_eq!(loaded.root, fs::canonicalize(package.path()).unwrap());
    assert_eq!(loaded.resources.len(), 5);
    assert_eq!(
        loaded.manifest_sha256(),
        loaded.manifest.canonical_sha256().unwrap()
    );
    assert_eq!(
        loaded.canonical_json(),
        loaded.manifest.canonical_json().unwrap()
    );
    let system = RelativeResourcePath::parse("instructions/system.md").unwrap();
    assert_eq!(
        loaded.resource_path(&system),
        Some(
            fs::canonicalize(package.path().join(system.as_path()))
                .unwrap()
                .as_path()
        )
    );
}

#[tokio::test]
async fn loads_custom_theme_as_a_confined_app_resource() {
    let mut value = valid_manifest();
    value["appearance"] = json!({
        "defaultTheme": "com.example.brand-dark",
        "themes": {
            "builtins": ["vscode.dark-2026"],
            "custom": [{
                "id": "com.example.brand-dark",
                "path": "themes/brand-dark.jsonc"
            }]
        }
    });
    let package = create_package(&value);
    fs::create_dir(package.path().join("themes")).unwrap();
    fs::write(
        package.path().join("themes/brand-dark.jsonc"),
        r##"{ "colors": { "editor.background": "#111111" } }"##,
    )
    .unwrap();

    let loaded = AgentAppManifest::load(package.path()).await.unwrap();
    let theme = RelativeResourcePath::parse("themes/brand-dark.jsonc").unwrap();

    assert_eq!(loaded.resources.len(), 6);
    assert_eq!(
        loaded.resource_path(&theme),
        Some(
            fs::canonicalize(package.path().join(theme.as_path()))
                .unwrap()
                .as_path()
        )
    );
}

#[tokio::test]
async fn loads_localization_catalogs_as_confined_resources() {
    let mut value = valid_manifest();
    value["localization"] = json!({
        "defaultLocale": "en",
        "locales": [
            {"id": "en", "label": "English", "resource": "locales/en.json"},
            {"id": "zh-CN", "label": "简体中文", "resource": "locales/zh-CN.json"}
        ]
    });
    let package = create_package(&value);
    fs::create_dir(package.path().join("locales")).unwrap();
    fs::write(
        package.path().join("locales/en.json"),
        r#"{"app.title":"Agent"}"#,
    )
    .unwrap();
    fs::write(
        package.path().join("locales/zh-CN.json"),
        r#"{"app.title":"智能体"}"#,
    )
    .unwrap();

    let loaded = AgentAppManifest::load(package.path()).await.unwrap();

    assert_eq!(loaded.resources.len(), 7);
    let chinese = RelativeResourcePath::parse("locales/zh-CN.json").unwrap();
    assert!(loaded.resource_path(&chinese).is_some());
}

#[tokio::test]
async fn load_rejects_mismatched_localization_catalogs() {
    let mut value = valid_manifest();
    value["localization"] = json!({
        "defaultLocale": "en",
        "locales": [
            {"id": "en", "label": "English", "resource": "locales/en.json"},
            {"id": "zh-CN", "label": "简体中文", "resource": "locales/zh-CN.json"}
        ]
    });
    let package = create_package(&value);
    fs::create_dir(package.path().join("locales")).unwrap();
    fs::write(
        package.path().join("locales/en.json"),
        r#"{"welcome":"Hello {name}"}"#,
    )
    .unwrap();
    fs::write(
        package.path().join("locales/zh-CN.json"),
        r#"{"welcome":"你好"}"#,
    )
    .unwrap();

    let error = AgentAppManifest::load(package.path()).await.unwrap_err();

    assert!(
        error
            .to_string()
            .contains("preserve message keys and placeholders")
    );
}

#[tokio::test]
async fn load_rejects_missing_or_non_file_resources() {
    let missing = create_package(&valid_manifest());
    fs::remove_file(missing.path().join("instructions/system.md")).unwrap();
    let error = AgentAppManifest::load(missing.path()).await.unwrap_err();
    assert!(
        error
            .to_string()
            .contains("invalid app resource instructions/system.md")
    );

    let directory = create_package(&valid_manifest());
    fs::remove_file(directory.path().join("instructions/system.md")).unwrap();
    fs::create_dir(directory.path().join("instructions/system.md")).unwrap();
    let error = AgentAppManifest::load(directory.path()).await.unwrap_err();
    assert!(
        error
            .to_string()
            .contains("invalid app resource instructions/system.md")
    );
}

#[cfg(unix)]
#[tokio::test]
async fn load_rejects_symlinked_package_roots_and_resource_escapes() {
    use std::os::unix::fs::symlink;

    let package = create_package(&valid_manifest());
    let link_parent = TempDir::new().unwrap();
    let root_link = link_parent.path().join("app-link");
    symlink(package.path(), &root_link).unwrap();
    let error = AgentAppManifest::load(&root_link).await.unwrap_err();
    assert!(error.to_string().contains("root must be a real directory"));

    let outside = TempDir::new().unwrap();
    let escape = create_package(&valid_manifest());
    fs::remove_file(escape.path().join("instructions/system.md")).unwrap();
    symlink(
        outside.path().join("outside.md"),
        escape.path().join("instructions/system.md"),
    )
    .unwrap();
    fs::write(outside.path().join("outside.md"), "outside").unwrap();
    let error = AgentAppManifest::load(escape.path()).await.unwrap_err();
    assert!(
        error
            .to_string()
            .contains("invalid app resource instructions/system.md")
    );
}

#[cfg(unix)]
#[tokio::test]
async fn load_rejects_symlinked_manifest_file() {
    use std::os::unix::fs::symlink;

    let package = create_package(&valid_manifest());
    let outside = TempDir::new().unwrap();
    let outside_manifest = outside.path().join("outside.json");
    fs::write(&outside_manifest, manifest_bytes(&valid_manifest())).unwrap();
    fs::remove_file(package.path().join(AGENT_APP_MANIFEST_FILE)).unwrap();
    symlink(
        &outside_manifest,
        package.path().join(AGENT_APP_MANIFEST_FILE),
    )
    .unwrap();

    let error = AgentAppManifest::load(package.path()).await.unwrap_err();

    assert!(error.to_string().contains("invalid app manifest file"));
}
