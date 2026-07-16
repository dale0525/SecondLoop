use agent_runtime::{
    events::RuntimeEvent,
    platform::{CapabilitySet, PlatformId},
    skill_manager::{SkillManager, SkillManagerConfig},
    skill_source::{DirectorySkillSource, DiscoveredSkillPackage, SkillLayer, SkillSource},
    storage::Storage,
    tools::RuntimeConfig,
    turn::AgentRunner,
};
use async_trait::async_trait;
use axum::{
    body::{Body, to_bytes},
    http::{Request, StatusCode},
};
use serde_json::{Value, json};
use std::{
    path::{Path, PathBuf},
    sync::{
        Arc,
        atomic::{AtomicUsize, Ordering},
    },
    time::Duration,
};
use tokio::sync::Notify;
use tower::ServiceExt;

struct TestAgent;

struct BlockingDirectorySource {
    calls: AtomicUsize,
    inner: DirectorySkillSource,
    reload_started: Arc<Notify>,
    release_reload: Arc<Notify>,
}

#[async_trait]
impl SkillSource for BlockingDirectorySource {
    fn layer(&self) -> SkillLayer {
        SkillLayer::Builtin
    }

    async fn discover(&self) -> anyhow::Result<Vec<DiscoveredSkillPackage>> {
        let packages = self.inner.discover().await?;
        if self.calls.fetch_add(1, Ordering::SeqCst) > 0 {
            self.reload_started.notify_one();
            self.release_reload.notified().await;
        }
        Ok(packages)
    }
}

#[async_trait]
impl AgentRunner for TestAgent {
    async fn run(&self, _user_text: &str) -> anyhow::Result<Vec<RuntimeEvent>> {
        Ok(Vec::new())
    }
}

#[tokio::test]
async fn dev_reload_serializes_delete_across_routers_sharing_app_state() {
    let workspace = unique_test_dir("reload-delete-serialization");
    let skills_root = workspace.join("skills");
    let package_root = skills_root.join("dynamic");
    write_editable_package(&package_root, "dynamic", "Dynamic body").await;
    let expected_revision = crate::dev_skill_authoring::read_skill_source(&skills_root, "dynamic")
        .await
        .unwrap()
        .source_revision;
    let reload_started = Arc::new(Notify::new());
    let release_reload = Arc::new(Notify::new());
    let source = Arc::new(BlockingDirectorySource {
        calls: AtomicUsize::new(0),
        inner: DirectorySkillSource::new(SkillLayer::Builtin, &skills_root),
        reload_started: reload_started.clone(),
        release_reload: release_reload.clone(),
    });
    let manager = skill_manager(vec![source]).await;
    let storage = Storage::connect("sqlite::memory:").await.unwrap();
    let state = Arc::new(
        crate::api::AppState::new_with_agent(storage, Arc::new(TestAgent))
            .with_skill_manager(manager.clone())
            .with_skills_root(skills_root.clone())
            .with_runtime_config(
                RuntimeConfig::workspace_write(workspace.clone(), workspace.clone())
                    .without_builtin_tools(),
            ),
    );
    let reload_app = crate::api::router_with_dev_routes(state.clone());
    let delete_app = crate::api::router_with_dev_routes(state.clone());
    let snapshot_app = crate::api::router_with_dev_routes(state);

    let reload_task = tokio::spawn(async move {
        reload_app
            .oneshot(post_request("/dev/skills/reload"))
            .await
            .unwrap()
    });
    reload_started.notified().await;
    let mut delete_task = tokio::spawn(async move {
        delete_app
            .oneshot(delete_request("/dev/skills/dynamic", &expected_revision))
            .await
            .unwrap()
    });

    assert!(
        tokio::time::timeout(Duration::from_millis(100), &mut delete_task)
            .await
            .is_err()
    );
    assert!(package_root.exists());
    release_reload.notify_one();

    let reload = reload_task.await.unwrap();
    assert_eq!(reload.status(), StatusCode::OK);
    let reload_body = read_json(reload).await;
    assert_eq!(reload_body["activeGeneration"], 2);
    assert_eq!(reload_body["inventory"]["packages"][0]["id"], "dynamic");
    let delete = delete_task.await.unwrap();
    assert_eq!(delete.status(), StatusCode::OK);
    assert!(
        read_json(delete).await["packages"]
            .as_array()
            .unwrap()
            .is_empty()
    );
    assert_eq!(manager.current_snapshot().generation(), 2);
    assert!(!package_root.exists());
    assert!(
        manager
            .current_snapshot()
            .catalog()
            .summaries()
            .iter()
            .any(|summary| summary.name == "dynamic")
    );
    drop(snapshot_app);
    remove_test_dir(workspace).await;
}

#[cfg(unix)]
#[tokio::test]
async fn dev_reload_publishes_safe_symlink_and_ignores_escape_symlink() {
    use std::os::unix::fs::symlink;

    let workspace = unique_test_dir("reload-safe-symlink");
    let outside = unique_test_dir("reload-escape-target");
    let skills_root = workspace.join("skills");
    let host_root = skills_root.join("host");
    let linked_target = host_root.join("linked-target");
    write_combined_package(
        &host_root,
        "com.example.host",
        "host_tool",
        "host",
        "Host body",
    )
    .await;
    write_combined_package(
        &linked_target,
        "com.example.linked",
        "linked_tool",
        "linked",
        "Linked body",
    )
    .await;
    let manager = skill_manager(vec![Arc::new(DirectorySkillSource::new(
        SkillLayer::Builtin,
        &skills_root,
    ))])
    .await;
    symlink(&linked_target, skills_root.join("linked")).unwrap();
    write_combined_package(
        &outside.join("outside"),
        "com.example.outside",
        "outside_tool",
        "outside",
        "Outside body",
    )
    .await;
    symlink(outside.join("outside"), skills_root.join("escape")).unwrap();
    let storage = Storage::connect("sqlite::memory:").await.unwrap();
    let state = Arc::new(
        crate::api::AppState::new_with_agent(storage, Arc::new(TestAgent))
            .with_skill_manager(manager)
            .with_skills_root(skills_root.clone())
            .with_runtime_config(
                RuntimeConfig::workspace_write(workspace.clone(), workspace.clone())
                    .without_builtin_tools(),
            ),
    );
    let app = crate::api::router_with_dev_routes(state);

    let reload = app
        .clone()
        .oneshot(post_request("/dev/skills/reload"))
        .await
        .unwrap();

    assert_eq!(reload.status(), StatusCode::OK);
    let reload_body = read_json(reload).await;
    assert_eq!(reload_body["activePackages"], 2);
    let inventory_ids = reload_body["inventory"]["packages"]
        .as_array()
        .unwrap()
        .iter()
        .map(|package| package["id"].as_str().unwrap())
        .collect::<Vec<_>>();
    assert!(inventory_ids.contains(&"linked"));
    assert!(!inventory_ids.contains(&"escape"));

    let tools = read_json(
        app.clone()
            .oneshot(get_request("/dev/tools"))
            .await
            .unwrap(),
    )
    .await;
    assert!(
        tools["tools"]
            .as_array()
            .unwrap()
            .iter()
            .any(|tool| tool["name"] == "linked_tool")
    );
    assert!(
        !tools["tools"]
            .as_array()
            .unwrap()
            .iter()
            .any(|tool| tool["name"] == "outside_tool")
    );
    let preview = read_json(
        app.oneshot(json_request(
            "/dev/instructions/preview",
            json!({ "content": "use $linked" }),
        ))
        .await
        .unwrap(),
    )
    .await;
    assert_eq!(preview["triggered_skills"], json!(["linked"]));
    assert!(
        preview["developer"]
            .as_str()
            .unwrap()
            .contains("Linked body")
    );

    remove_test_dir(workspace).await;
    remove_test_dir(outside).await;
}

async fn skill_manager(sources: Vec<Arc<dyn SkillSource>>) -> SkillManager {
    SkillManager::new(SkillManagerConfig {
        sources,
        platform: PlatformId::Desktop,
        capabilities: CapabilitySet::desktop_runtime(),
        protected_packages: Vec::new(),
        allowed_overrides: Vec::new(),
        runtime_version: "0.1.0".parse().unwrap(),
    })
    .await
    .unwrap()
}

async fn write_combined_package(
    package_root: &Path,
    package_id: &str,
    tool_name: &str,
    instruction_name: &str,
    instruction_body: &str,
) {
    tokio::fs::create_dir_all(package_root).await.unwrap();
    tokio::fs::write(
        package_root.join("agentweave.json"),
        json!({
            "schemaVersion": 1,
            "id": package_id,
            "version": "1.0.0",
            "displayName": instruction_name,
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
            "name": instruction_name,
            "description": format!("{instruction_name} runtime."),
            "version": "1.0.0",
            "entry": {
                "type": "command",
                "command": "node",
                "args": ["index.js"]
            },
            "tools": [{
                "name": tool_name,
                "description": format!("{tool_name} tool."),
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
            "---\nname: {instruction_name}\ndescription: {instruction_name} instructions.\n---\n\n# {instruction_name}\n{instruction_body}"
        ),
    )
    .await
    .unwrap();
}

async fn write_editable_package(package_root: &Path, instruction_name: &str, body: &str) {
    tokio::fs::create_dir_all(package_root).await.unwrap();
    tokio::fs::write(
        package_root.join("agentweave.json"),
        json!({
            "schemaVersion": 1,
            "id": format!("com.example.{instruction_name}"),
            "version": "1.0.0",
            "displayName": instruction_name,
            "kind": "instruction_only",
            "package": {
                "includeInstructions": true,
                "includeRuntime": false
            }
        })
        .to_string(),
    )
    .await
    .unwrap();
    tokio::fs::write(
        package_root.join("SKILL.md"),
        format!(
            "---\nname: {instruction_name}\ndescription: Editable instructions.\n---\n\n# {instruction_name}\n{body}"
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

fn get_request(uri: &str) -> Request<Body> {
    Request::builder().uri(uri).body(Body::empty()).unwrap()
}

fn post_request(uri: &str) -> Request<Body> {
    Request::builder()
        .method("POST")
        .uri(uri)
        .body(Body::empty())
        .unwrap()
}

fn delete_request(uri: &str, expected_revision: &str) -> Request<Body> {
    Request::builder()
        .method("DELETE")
        .uri(uri)
        .header("content-type", "application/json")
        .body(Body::from(
            json!({"expectedRevision": expected_revision}).to_string(),
        ))
        .unwrap()
}

fn json_request(uri: &str, body: Value) -> Request<Body> {
    Request::builder()
        .method("POST")
        .uri(uri)
        .header("content-type", "application/json")
        .body(Body::from(body.to_string()))
        .unwrap()
}

async fn read_json(response: axum::response::Response) -> Value {
    let bytes = to_bytes(response.into_body(), 1024 * 1024).await.unwrap();
    serde_json::from_slice(&bytes).unwrap()
}
