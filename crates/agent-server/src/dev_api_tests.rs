use agent_runtime::{
    events::RuntimeEvent,
    platform::{CapabilitySet, PlatformId},
    skill::SkillRegistry,
    skill_catalog::SkillCatalog,
    skill_manager::{SkillManager, SkillManagerConfig},
    skill_source::{DirectorySkillSource, DiscoveredSkillPackage, SkillLayer, SkillSource},
    storage::Storage,
    tools::RuntimeConfig,
    turn::AgentRunner,
};
use async_trait::async_trait;
use axum::{
    body::{Body, to_bytes},
    http::{Request, StatusCode, header},
};
use serde_json::{Value, json};
use std::{
    path::PathBuf,
    sync::{
        Arc,
        atomic::{AtomicUsize, Ordering},
    },
};
use tower::ServiceExt;

use super::dev_skill_authoring_status;
use crate::dev_skill_authoring_error::DevSkillAuthoringError;

#[test]
fn authoring_error_mapping_requires_an_explicit_classification() {
    assert_eq!(
        dev_skill_authoring_status(anyhow::anyhow!(
            "filesystem unavailable while reading an invalid package"
        )),
        StatusCode::INTERNAL_SERVER_ERROR
    );
    assert_eq!(
        dev_skill_authoring_status(DevSkillAuthoringError::bad_request("invalid directory").into()),
        StatusCode::BAD_REQUEST
    );
    assert_eq!(
        dev_skill_authoring_status(DevSkillAuthoringError::conflict("revision changed").into()),
        StatusCode::CONFLICT
    );
    let dependency_error = anyhow::Error::msg("package dependency failed").context(
        DevSkillAuthoringError::unprocessable("skill inventory validation failed"),
    );
    assert_eq!(
        dev_skill_authoring_status(dependency_error),
        StatusCode::UNPROCESSABLE_ENTITY
    );
}

struct TestAgent;

struct DeleteDiagnosticsRootOnReloadSource {
    calls: AtomicUsize,
    diagnostics_root: PathBuf,
}

#[async_trait]
impl SkillSource for DeleteDiagnosticsRootOnReloadSource {
    fn layer(&self) -> SkillLayer {
        SkillLayer::Builtin
    }

    async fn discover(&self) -> anyhow::Result<Vec<DiscoveredSkillPackage>> {
        if self.calls.fetch_add(1, Ordering::SeqCst) > 0 {
            tokio::fs::remove_dir_all(&self.diagnostics_root).await?;
        }
        Ok(Vec::new())
    }
}

#[async_trait]
impl AgentRunner for TestAgent {
    async fn run(&self, _user_text: &str) -> anyhow::Result<Vec<RuntimeEvent>> {
        Ok(Vec::new())
    }
}

#[tokio::test]
async fn dev_tools_route_is_not_mounted_by_default() {
    let storage = Storage::connect("sqlite::memory:").await.unwrap();
    let app = crate::api::router(Arc::new(crate::api::AppState::new(storage)));

    let response = app
        .oneshot(
            Request::builder()
                .uri("/dev/tools")
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(response.status(), StatusCode::NOT_FOUND);
}

#[tokio::test]
async fn dev_skills_route_is_not_mounted_by_default() {
    let storage = Storage::connect("sqlite::memory:").await.unwrap();
    let app = crate::api::router(Arc::new(crate::api::AppState::new(storage)));

    let response = app
        .oneshot(
            Request::builder()
                .uri("/dev/skills")
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(response.status(), StatusCode::NOT_FOUND);
}

#[tokio::test]
async fn dev_tools_route_returns_tool_diagnostics_when_enabled() {
    let storage = Storage::connect("sqlite::memory:").await.unwrap();
    let skills_root = development_skills().await;
    let skills = SkillRegistry::load_development(&skills_root).await.unwrap();
    let state = Arc::new(crate::api::AppState::new_with_agent_and_skills(
        storage,
        Arc::new(TestAgent),
        skills,
    ));
    let app = crate::api::router_with_dev_routes(state);

    let response = app
        .oneshot(
            Request::builder()
                .uri("/dev/tools")
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(response.status(), StatusCode::OK);
    let body = read_json(response).await;
    let tools = body["tools"].as_array().unwrap();
    assert!(tools.iter().any(|tool| tool["name"] == "echo"));
    assert!(tools.iter().all(|tool| tool["name"] != "create_directory"));
    assert!(tools.iter().all(|tool| tool.get("schema").is_some()));
    remove_test_dir(skills_root).await;
}

#[tokio::test]
async fn dev_skills_route_returns_inventory_when_enabled() {
    let storage = Storage::connect("sqlite::memory:").await.unwrap();
    let skills_root = development_skills().await;
    let skills = SkillRegistry::load_development(&skills_root).await.unwrap();
    let state = Arc::new(
        crate::api::AppState::new_with_agent_and_skills(storage, Arc::new(TestAgent), skills)
            .with_skills_root(skills_root.clone()),
    );
    let app = crate::api::router_with_dev_routes(state);

    let response = app
        .oneshot(
            Request::builder()
                .uri("/dev/skills")
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(response.status(), StatusCode::OK);
    let body = read_json(response).await;
    assert_eq!(body["packages"][0]["id"], "echo");
    assert_eq!(body["packages"][0]["packageKind"], "runtime");
    remove_test_dir(skills_root).await;
}

#[tokio::test]
async fn dev_delete_skill_rejects_unsafe_id() {
    let storage = Storage::connect("sqlite::memory:").await.unwrap();
    let skills_root = development_skills().await;
    let skills = SkillRegistry::load_development(&skills_root).await.unwrap();
    let state = Arc::new(
        crate::api::AppState::new_with_agent_and_skills(storage, Arc::new(TestAgent), skills)
            .with_skills_root(skills_root.clone()),
    );
    let app = crate::api::router_with_dev_routes(state);

    let response = app
        .oneshot(json_delete_request(
            "/dev/skills/..%2Fecho",
            json!({ "expectedRevision": "a".repeat(64) }),
        ))
        .await
        .unwrap();

    assert_eq!(response.status(), StatusCode::BAD_REQUEST);
    assert!(skills_root.join("echo").exists());
    remove_test_dir(skills_root).await;
}

#[tokio::test]
async fn dev_delete_skill_rejects_runtime_package_as_read_only() {
    let storage = Storage::connect("sqlite::memory:").await.unwrap();
    let skills_root = development_skills().await;
    let skills = SkillRegistry::load_development(&skills_root).await.unwrap();
    let state = Arc::new(
        crate::api::AppState::new_with_agent_and_skills(storage, Arc::new(TestAgent), skills)
            .with_skills_root(skills_root.clone()),
    );
    let app = crate::api::router_with_dev_routes(state);

    let response = app
        .oneshot(json_delete_request(
            "/dev/skills/echo",
            json!({ "expectedRevision": "a".repeat(64) }),
        ))
        .await
        .unwrap();

    assert_eq!(response.status(), StatusCode::UNPROCESSABLE_ENTITY);
    assert!(skills_root.join("echo/skill.json").exists());
    remove_test_dir(skills_root).await;
}

#[tokio::test]
async fn dev_delete_skill_requires_current_revision_for_editable_package() {
    let storage = Storage::connect("sqlite::memory:").await.unwrap();
    let skills_root = unique_test_dir("delete-editable");
    write_editable_package(&skills_root, "planning").await;
    let skills = SkillRegistry::load_development(&skills_root).await.unwrap();
    let state = Arc::new(
        crate::api::AppState::new_with_agent_and_skills(storage, Arc::new(TestAgent), skills)
            .with_skills_root(skills_root.clone()),
    );
    let app = crate::api::router_with_dev_routes(state);
    let source = read_json(
        app.clone()
            .oneshot(
                Request::builder()
                    .uri("/dev/skills/planning")
                    .body(Body::empty())
                    .unwrap(),
            )
            .await
            .unwrap(),
    )
    .await;

    let conflict = app
        .clone()
        .oneshot(json_delete_request(
            "/dev/skills/planning",
            json!({ "expectedRevision": "a".repeat(64) }),
        ))
        .await
        .unwrap();
    assert_eq!(conflict.status(), StatusCode::CONFLICT);
    assert!(skills_root.join("planning/SKILL.md").exists());

    let deleted = app
        .oneshot(json_delete_request(
            "/dev/skills/planning",
            json!({ "expectedRevision": source["sourceRevision"] }),
        ))
        .await
        .unwrap();
    assert_eq!(deleted.status(), StatusCode::OK);
    assert!(
        read_json(deleted).await["packages"]
            .as_array()
            .unwrap()
            .is_empty()
    );
    assert!(!skills_root.join("planning").exists());
    remove_test_dir(skills_root).await;
}

#[tokio::test]
async fn dev_delete_skill_supports_desktop_cors_preflight() {
    let storage = Storage::connect("sqlite::memory:").await.unwrap();
    let skills_root = development_skills().await;
    let skills = SkillRegistry::load_development(&skills_root).await.unwrap();
    let state = Arc::new(
        crate::api::AppState::new_with_agent_and_skills(storage, Arc::new(TestAgent), skills)
            .with_skills_root(skills_root.clone()),
    );
    let app = crate::api::router_with_dev_routes(state);

    let response = app
        .oneshot(
            Request::builder()
                .method("OPTIONS")
                .uri("/dev/skills/echo")
                .header(header::ORIGIN, "http://127.0.0.1:5173")
                .header(header::ACCESS_CONTROL_REQUEST_METHOD, "DELETE")
                .header(header::ACCESS_CONTROL_REQUEST_HEADERS, "content-type")
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(response.status(), StatusCode::OK);
    assert_eq!(
        response.headers()[header::ACCESS_CONTROL_ALLOW_ORIGIN],
        "http://127.0.0.1:5173"
    );
    assert!(
        response.headers()[header::ACCESS_CONTROL_ALLOW_METHODS]
            .to_str()
            .unwrap()
            .contains("DELETE")
    );
    assert!(
        response.headers()[header::ACCESS_CONTROL_ALLOW_HEADERS]
            .to_str()
            .unwrap()
            .contains("content-type")
    );
    remove_test_dir(skills_root).await;
}

#[tokio::test]
async fn dev_tool_discovery_returns_deferred_tools_and_connectors() {
    let storage = Storage::connect("sqlite::memory:").await.unwrap();
    let workspace = unique_test_dir("tool-discovery");
    tokio::fs::create_dir_all(&workspace).await.unwrap();
    let skills_root = workspace.join("skills");
    tokio::fs::create_dir_all(&skills_root).await.unwrap();
    let skills = SkillRegistry::load_development(&skills_root).await.unwrap();
    let mut config = RuntimeConfig::workspace_write(workspace.clone(), workspace.clone());
    config
        .external_tools
        .push(agent_runtime::tools::discovery::ExternalToolConfig::mcp(
            "search",
            "expensive_lookup",
            "Search a remote corpus.",
            serde_json::json!({ "type": "object" }),
            agent_runtime::tools::discovery::ExternalToolVisibility::Deferred {
                summary: "Remote corpus lookup.".into(),
            },
        ));
    config
        .connectors
        .push(agent_runtime::tools::discovery::ConnectorMetadata {
            id: "search".into(),
            name: "Search MCP".into(),
            description: "Remote search connector.".into(),
            version: "0.1.0".into(),
            permissions: vec![agent_runtime::tools::ToolPermission::ReadWorkspace],
            auth_state: agent_runtime::tools::discovery::ConnectorAuthState::NotRequired,
            tool_count: 1,
        });
    let state = Arc::new(
        crate::api::AppState::new_with_agent_and_skills(storage, Arc::new(TestAgent), skills)
            .with_runtime_config(config),
    );
    let app = crate::api::router_with_dev_routes(state);

    let response = app
        .oneshot(
            Request::builder()
                .uri("/dev/tool-discovery")
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(response.status(), StatusCode::OK);
    let body = read_json(response).await;
    assert!(body["tools"].as_array().unwrap().iter().any(|tool| {
        tool["name"] == "mcp__search__expensive_lookup"
            && tool["deferred"] == true
            && tool["schema_loaded"] == false
    }));
    assert_eq!(body["connectors"][0]["id"], "search");
    remove_test_dir(workspace).await;
}

#[tokio::test]
async fn dev_instructions_preview_returns_project_and_skill_context() {
    let storage = Storage::connect("sqlite::memory:").await.unwrap();
    let workspace = unique_test_dir("instructions-preview");
    tokio::fs::create_dir_all(&workspace).await.unwrap();
    tokio::fs::write(workspace.join("AGENTS.md"), "Project rules")
        .await
        .unwrap();
    let skills_root = workspace.join("skills");
    tokio::fs::create_dir_all(skills_root.join("planning"))
        .await
        .unwrap();
    tokio::fs::write(
        skills_root.join("planning").join("SKILL.md"),
        "---\nname: planning\ndescription: Write plans.\n---\n\n# Planning\nUse checklists.",
    )
    .await
    .unwrap();
    let skills = SkillRegistry::load_development(&skills_root).await.unwrap();
    let catalog = SkillCatalog::load_development(&skills_root).await.unwrap();
    let state = Arc::new(
        crate::api::AppState::new_with_agent_and_skills(storage, Arc::new(TestAgent), skills)
            .with_runtime_config(RuntimeConfig::workspace_write(
                workspace.clone(),
                workspace.clone(),
            ))
            .with_skill_catalog(catalog),
    );
    let app = crate::api::router_with_dev_routes(state);

    let response = app
        .oneshot(json_request(
            "/dev/instructions/preview",
            json!({ "content": "use $planning" }),
        ))
        .await
        .unwrap();

    assert_eq!(response.status(), StatusCode::OK);
    let body = read_json(response).await;
    assert!(
        body["developer"]
            .as_str()
            .unwrap()
            .contains("Project rules")
    );
    assert!(
        body["developer"]
            .as_str()
            .unwrap()
            .contains("<available_skills")
    );
    assert!(
        body["developer"]
            .as_str()
            .unwrap()
            .contains("<skill_instructions name=\"planning\"")
    );
    remove_test_dir(workspace).await;
}

#[tokio::test]
async fn dev_reload_replaces_runtime_and_instruction_views() {
    let storage = Storage::connect("sqlite::memory:").await.unwrap();
    let workspace = unique_test_dir("reload-replaces");
    tokio::fs::create_dir_all(&workspace).await.unwrap();
    let skills_root = workspace.join("skills");
    let package_root = skills_root.join("dynamic");
    write_dynamic_package(&package_root, "first_tool", "first", "First body").await;
    let manager = dynamic_skill_manager(&skills_root).await;
    let state = Arc::new(
        crate::api::AppState::new_with_agent(storage, Arc::new(TestAgent))
            .with_skill_manager(manager.clone())
            .with_skills_root(skills_root.clone())
            .with_runtime_config(
                RuntimeConfig::workspace_write(workspace.clone(), workspace.clone())
                    .without_builtin_tools(),
            ),
    );
    let app = crate::api::router_with_dev_routes(state);

    write_dynamic_package(&package_root, "second_tool", "second", "Second body").await;
    let reload = app
        .clone()
        .oneshot(
            Request::builder()
                .method("POST")
                .uri("/dev/skills/reload")
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(reload.status(), StatusCode::OK);
    let body = read_json(reload).await;
    assert_eq!(
        body.as_object()
            .unwrap()
            .keys()
            .cloned()
            .collect::<Vec<_>>(),
        vec![
            "activeGeneration",
            "activePackages",
            "inactivePackages",
            "inventory",
            "previousGeneration",
            "reloadStatus",
        ]
    );
    assert_eq!(body["previousGeneration"], 1);
    assert_eq!(body["activeGeneration"], 2);
    assert_eq!(body["activePackages"], 1);
    assert_eq!(body["inactivePackages"], 0);
    assert_eq!(body["reloadStatus"], "published");
    assert_eq!(body["inventory"]["packages"][0]["id"], "dynamic");

    let tools = read_json(
        app.clone()
            .oneshot(
                Request::builder()
                    .uri("/dev/tools")
                    .body(Body::empty())
                    .unwrap(),
            )
            .await
            .unwrap(),
    )
    .await;
    assert!(
        tools["tools"]
            .as_array()
            .unwrap()
            .iter()
            .any(|tool| tool["name"] == "second_tool")
    );
    assert!(
        !tools["tools"]
            .as_array()
            .unwrap()
            .iter()
            .any(|tool| tool["name"] == "first_tool")
    );

    let discovery = read_json(
        app.clone()
            .oneshot(
                Request::builder()
                    .uri("/dev/tool-discovery")
                    .body(Body::empty())
                    .unwrap(),
            )
            .await
            .unwrap(),
    )
    .await;
    assert!(
        discovery["tools"]
            .as_array()
            .unwrap()
            .iter()
            .any(|tool| tool["name"] == "second_tool")
    );
    assert!(
        !discovery["tools"]
            .as_array()
            .unwrap()
            .iter()
            .any(|tool| tool["name"] == "first_tool")
    );

    let preview = read_json(
        app.oneshot(json_request(
            "/dev/instructions/preview",
            json!({ "content": "use $second" }),
        ))
        .await
        .unwrap(),
    )
    .await;
    assert_eq!(preview["triggered_skills"], json!(["second"]));
    assert!(
        preview["developer"]
            .as_str()
            .unwrap()
            .contains("Second body")
    );
    assert!(
        !preview["developer"]
            .as_str()
            .unwrap()
            .contains("First body")
    );
    remove_test_dir(workspace).await;
}

#[tokio::test]
async fn dev_reload_diagnostic_failure_does_not_publish_candidate() {
    let storage = Storage::connect("sqlite::memory:").await.unwrap();
    let diagnostics_root = unique_test_dir("reload-diagnostics-fail");
    tokio::fs::create_dir_all(&diagnostics_root).await.unwrap();
    let source = Arc::new(DeleteDiagnosticsRootOnReloadSource {
        calls: AtomicUsize::new(0),
        diagnostics_root: diagnostics_root.clone(),
    });
    let manager = SkillManager::new(SkillManagerConfig {
        sources: vec![source],
        platform: PlatformId::Desktop,
        capabilities: CapabilitySet::desktop_runtime(),
        protected_packages: Vec::new(),
        allowed_overrides: Vec::new(),
        runtime_version: "0.1.0".parse().unwrap(),
    })
    .await
    .unwrap();
    let state = Arc::new(
        crate::api::AppState::new_with_agent(storage, Arc::new(TestAgent))
            .with_skill_manager(manager.clone())
            .with_skills_root(diagnostics_root),
    );
    let app = crate::api::router_with_dev_routes(state);

    let reload = app
        .oneshot(
            Request::builder()
                .method("POST")
                .uri("/dev/skills/reload")
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(reload.status(), StatusCode::UNPROCESSABLE_ENTITY);
    assert_eq!(manager.current_snapshot().generation(), 1);
}

#[tokio::test]
async fn dev_reload_rejects_invalid_candidate_and_keeps_previous_snapshot() {
    let storage = Storage::connect("sqlite::memory:").await.unwrap();
    let workspace = unique_test_dir("reload-invalid");
    let skills_root = workspace.join("skills");
    let package_root = skills_root.join("stable");
    write_dynamic_package(&package_root, "stable_tool", "stable", "Stable body").await;
    let manager = dynamic_skill_manager(&skills_root).await;
    let state = Arc::new(
        crate::api::AppState::new_with_agent(storage, Arc::new(TestAgent))
            .with_skill_manager(manager.clone())
            .with_skills_root(skills_root.clone())
            .with_runtime_config(
                RuntimeConfig::workspace_write(workspace.clone(), workspace.clone())
                    .without_builtin_tools(),
            ),
    );
    let app = crate::api::router_with_dev_routes(state);
    tokio::fs::write(package_root.join("agentweave.json"), "{invalid")
        .await
        .unwrap();

    let reload = app
        .clone()
        .oneshot(
            Request::builder()
                .method("POST")
                .uri("/dev/skills/reload")
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(reload.status(), StatusCode::UNPROCESSABLE_ENTITY);
    assert_eq!(manager.current_snapshot().generation(), 1);
    let tools = read_json(
        app.clone()
            .oneshot(
                Request::builder()
                    .uri("/dev/tools")
                    .body(Body::empty())
                    .unwrap(),
            )
            .await
            .unwrap(),
    )
    .await;
    assert!(
        tools["tools"]
            .as_array()
            .unwrap()
            .iter()
            .any(|tool| tool["name"] == "stable_tool")
    );
    let preview = read_json(
        app.oneshot(json_request(
            "/dev/instructions/preview",
            json!({ "content": "use $stable" }),
        ))
        .await
        .unwrap(),
    )
    .await;
    assert_eq!(preview["triggered_skills"], json!(["stable"]));
    assert!(
        preview["developer"]
            .as_str()
            .unwrap()
            .contains("Stable body")
    );
    remove_test_dir(workspace).await;
}

#[tokio::test]
async fn dev_reload_rejects_static_skill_manager() {
    let storage = Storage::connect("sqlite::memory:").await.unwrap();
    let skills_root = development_skills().await;
    let skills = SkillRegistry::load_development(&skills_root).await.unwrap();
    let manager = SkillManager::from_registry_and_catalog(skills, SkillCatalog::empty());
    let state = Arc::new(
        crate::api::AppState::new_with_agent(storage, Arc::new(TestAgent))
            .with_skill_manager(manager)
            .with_skills_root(skills_root.clone()),
    );
    let app = crate::api::router_with_dev_routes(state);

    let reload = app
        .oneshot(
            Request::builder()
                .method("POST")
                .uri("/dev/skills/reload")
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(reload.status(), StatusCode::UNPROCESSABLE_ENTITY);
    remove_test_dir(skills_root).await;
}

#[tokio::test]
async fn dev_reload_missing_skills_root_does_not_advance_generation() {
    let storage = Storage::connect("sqlite::memory:").await.unwrap();
    let skills_root = unique_test_dir("reload-missing-root");
    tokio::fs::create_dir_all(&skills_root).await.unwrap();
    let manager = dynamic_skill_manager(&skills_root).await;
    let state = Arc::new(
        crate::api::AppState::new_with_agent(storage, Arc::new(TestAgent))
            .with_skill_manager(manager.clone())
            .with_skills_root(skills_root.clone()),
    );
    tokio::fs::remove_dir_all(&skills_root).await.unwrap();
    let app = crate::api::router_with_dev_routes(state);

    let reload = app
        .oneshot(
            Request::builder()
                .method("POST")
                .uri("/dev/skills/reload")
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(reload.status(), StatusCode::UNPROCESSABLE_ENTITY);
    assert_eq!(manager.current_snapshot().generation(), 1);
}

async fn development_skills() -> PathBuf {
    let root = unique_test_dir("dev-tools");
    let skill_dir = root.join("echo");
    tokio::fs::create_dir_all(&skill_dir).await.unwrap();
    tokio::fs::write(
        skill_dir.join("skill.json"),
        serde_json::json!({
            "name": "echo",
            "description": "Echo a text payload.",
            "version": "0.1.0",
            "entry": {
                "type": "command",
                "command": "node",
                "args": ["index.js"]
            },
            "tools": [
                {
                    "name": "echo",
                    "description": "Return the provided text.",
                    "input_schema": { "type": "object" }
                }
            ]
        })
        .to_string(),
    )
    .await
    .unwrap();
    tokio::fs::write(
        skill_dir.join("index.js"),
        "process.stdin.resume();\nprocess.stdin.on('data', (chunk) => process.stdout.write(chunk));\n",
    )
    .await
    .unwrap();
    root
}

async fn write_editable_package(root: &std::path::Path, directory: &str) {
    let package = root.join(directory);
    tokio::fs::create_dir_all(&package).await.unwrap();
    tokio::fs::write(
        package.join("agentweave.json"),
        json!({
            "schemaVersion": 1,
            "id": format!("com.example.{directory}"),
            "version": "0.1.0",
            "displayName": "Planning",
            "kind": "instruction_only",
            "package": {"includeInstructions": true, "includeRuntime": false}
        })
        .to_string(),
    )
    .await
    .unwrap();
    tokio::fs::write(
        package.join("SKILL.md"),
        "---\nname: planning\ndescription: Plan bounded work.\n---\n\n# Planning\n",
    )
    .await
    .unwrap();
}

async fn dynamic_skill_manager(root: &std::path::Path) -> SkillManager {
    SkillManager::new(SkillManagerConfig {
        sources: vec![Arc::new(DirectorySkillSource::new(
            SkillLayer::Builtin,
            root,
        ))],
        platform: PlatformId::Desktop,
        capabilities: CapabilitySet::desktop_runtime(),
        protected_packages: Vec::new(),
        allowed_overrides: Vec::new(),
        runtime_version: "0.1.0".parse().unwrap(),
    })
    .await
    .unwrap()
}

async fn write_dynamic_package(
    package_root: &std::path::Path,
    tool_name: &str,
    instruction_name: &str,
    instruction_body: &str,
) {
    tokio::fs::create_dir_all(package_root).await.unwrap();
    tokio::fs::write(
        package_root.join("agentweave.json"),
        json!({
            "schemaVersion": 1,
            "id": "com.example.dynamic",
            "version": "1.0.0",
            "displayName": "Dynamic",
            "kind": "native_runtime",
            "package": {
                "includeInstructions": true,
                "includeRuntime": true
            }
        })
        .to_string(),
    )
    .await
    .unwrap();
    tokio::fs::write(
        package_root.join("skill.json"),
        json!({
            "name": "dynamic",
            "description": "Dynamic test skill.",
            "version": "1.0.0",
            "entry": {
                "type": "command",
                "command": "node",
                "args": ["index.js"]
            },
            "tools": [{
                "name": tool_name,
                "description": "Dynamic tool.",
                "input_schema": { "type": "object" }
            }]
        })
        .to_string(),
    )
    .await
    .unwrap();
    tokio::fs::write(package_root.join("index.js"), "process.stdin.resume();\n")
        .await
        .unwrap();
    tokio::fs::write(
        package_root.join("SKILL.md"),
        format!(
            "---\nname: {instruction_name}\ndescription: Dynamic instructions.\n---\n\n# Dynamic\n{instruction_body}"
        ),
    )
    .await
    .unwrap();
}

fn unique_test_dir(name: &str) -> PathBuf {
    std::env::temp_dir().join(format!(
        "agentweave-dev-api-{name}-{}",
        uuid::Uuid::new_v4()
    ))
}

async fn remove_test_dir(path: PathBuf) {
    if path.exists() {
        tokio::fs::remove_dir_all(path).await.unwrap();
    }
}

async fn read_json(response: axum::response::Response) -> Value {
    let bytes = to_bytes(response.into_body(), 1024 * 1024).await.unwrap();
    serde_json::from_slice(&bytes).unwrap()
}

fn json_request(uri: &str, body: Value) -> Request<Body> {
    Request::builder()
        .method("POST")
        .uri(uri)
        .header("content-type", "application/json")
        .body(Body::from(body.to_string()))
        .unwrap()
}

fn json_delete_request(uri: &str, body: Value) -> Request<Body> {
    Request::builder()
        .method("DELETE")
        .uri(uri)
        .header("content-type", "application/json")
        .body(Body::from(body.to_string()))
        .unwrap()
}
