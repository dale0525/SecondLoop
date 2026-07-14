use super::*;
use crate::local_transport::{TRANSPORT_HEADER, TransportAuth};
use crate::owner_api::{OwnerApiConfig, OwnerAuth};
use agent_runtime::{
    platform::{CapabilitySet, PlatformId},
    skill::SkillRegistry,
    skill_management::OwnerSkillManagementService,
    skill_manager::{SkillManager, SkillManagerConfig},
    skill_policy::{ActorContext, SkillGrant, SkillManagementPolicy},
    skill_source::{DirectorySkillSource, SkillLayer},
    skill_state::SkillStateStore,
    skill_store::{SkillRevisionStore, SkillStorePaths},
    storage::Storage,
    tools::RuntimeConfig,
    turn::{ModelClient, ModelEventStream, TurnRunner},
};
use async_trait::async_trait;
use axum::body::Body;
use axum::body::to_bytes;
use axum::http::{HeaderMap, Request, StatusCode, header};
use futures::stream;
use model_gateway::responses::{GatewayEvent, GatewayRequest};
use serde_json::{Value, json};
use std::path::{Path, PathBuf};
use std::sync::{
    Mutex,
    atomic::{AtomicUsize, Ordering},
};
use tower::ServiceExt;

struct SkillCallingModel {
    calls: AtomicUsize,
}

#[async_trait]
impl ModelClient for SkillCallingModel {
    async fn stream(&self, request: GatewayRequest) -> anyhow::Result<ModelEventStream> {
        let call = self.calls.fetch_add(1, Ordering::SeqCst);
        assert!(
            request
                .tools
                .iter()
                .any(|tool| tool.advertised_name() == "echo")
        );
        let events = if call == 0 {
            vec![
                Ok(GatewayEvent::ToolCall {
                    call_id: "call-1".into(),
                    name: "echo".into(),
                    legacy_alias_selected: false,
                    arguments: json!({ "text": "hidden skill result" }),
                }),
                Ok(GatewayEvent::Completed),
            ]
        } else {
            vec![
                Ok(GatewayEvent::TextDelta {
                    text: "The hidden capability returned hidden skill result.".into(),
                }),
                Ok(GatewayEvent::Completed),
            ]
        };

        Ok(Box::pin(stream::iter(events)))
    }
}

struct ToolSchemaCaptureModel {
    tool_names: Arc<Mutex<Vec<String>>>,
}

#[async_trait]
impl ModelClient for ToolSchemaCaptureModel {
    async fn stream(&self, request: GatewayRequest) -> anyhow::Result<ModelEventStream> {
        *self.tool_names.lock().unwrap() = request
            .tools
            .into_iter()
            .map(|tool| tool.advertised_name().to_string())
            .collect();
        Ok(Box::pin(stream::iter(vec![
            Ok(GatewayEvent::TextDelta {
                text: "default done".into(),
            }),
            Ok(GatewayEvent::Completed),
        ])))
    }
}

#[tokio::test]
async fn health_returns_ok() {
    let storage = Storage::connect("sqlite::memory:").await.unwrap();
    let app = router(Arc::new(AppState::new(storage)));
    let response = app
        .oneshot(
            Request::builder()
                .uri("/health")
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(response.status(), StatusCode::OK);
}

#[tokio::test]
async fn authenticated_router_protects_every_route_without_enabling_cors() {
    const TOKEN: &str = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQ";
    let storage = Storage::connect("sqlite::memory:").await.unwrap();
    let app = router_for_transport(
        Arc::new(AppState::new(storage)),
        false,
        Some(TransportAuth::new(TOKEN).unwrap()),
    );

    for request in [
        Request::builder()
            .uri("/health")
            .body(Body::empty())
            .unwrap(),
        Request::builder()
            .uri("/sessions")
            .body(Body::empty())
            .unwrap(),
    ] {
        let response = app.clone().oneshot(request).await.unwrap();
        assert_eq!(response.status(), StatusCode::UNAUTHORIZED);
        assert_eq!(
            read_json(response).await,
            json!({ "error": "unauthorized" })
        );
    }

    let response = app
        .oneshot(
            Request::builder()
                .uri("/health")
                .header(&TRANSPORT_HEADER, TOKEN)
                .header(header::ORIGIN, "http://127.0.0.1:5173")
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(response.status(), StatusCode::OK);
    assert!(
        response
            .headers()
            .get(header::ACCESS_CONTROL_ALLOW_ORIGIN)
            .is_none()
    );
}

#[tokio::test]
async fn create_session_and_post_message_returns_runtime_events() {
    let storage = Storage::connect("sqlite::memory:").await.unwrap();
    let app = router(Arc::new(AppState::new(storage.clone())));

    let create_response = app
        .clone()
        .oneshot(json_request(
            "/sessions",
            json!({ "title": "MVP Verification" }),
        ))
        .await
        .unwrap();
    assert_eq!(create_response.status(), StatusCode::OK);
    let created = read_json(create_response).await;
    let session_id = created["id"].as_str().unwrap();
    assert_eq!(created["title"], "MVP Verification");

    let message_response = app
        .oneshot(json_request(
            &format!("/sessions/{session_id}/messages"),
            json!({ "content": "Run the renderer smoke test" }),
        ))
        .await
        .unwrap();

    assert_eq!(message_response.status(), StatusCode::OK);
    let message = read_json(message_response).await;
    assert_eq!(message["accepted"], true);
    assert_eq!(
        message["assistant_message"]["content"],
        "MVP agent received: Run the renderer smoke test"
    );
    assert_eq!(message["events"][0]["type"], "turn_started");
    assert_eq!(message["events"][1]["type"], "assistant_text_delta");
    assert_eq!(
        message["events"][2],
        json!({
            "type": "assistant_message_finished",
            "text": "MVP agent received: Run the renderer smoke test"
        })
    );
    assert_eq!(message["events"][3]["type"], "turn_finished");

    let stored_messages = storage.list_messages(session_id).await.unwrap();
    assert_eq!(stored_messages.len(), 2);
    assert_eq!(stored_messages[0].role, "user");
    assert_eq!(stored_messages[0].content, "Run the renderer smoke test");
    assert_eq!(stored_messages[1].role, "assistant");
    assert_eq!(
        stored_messages[1].content,
        "MVP agent received: Run the renderer smoke test"
    );
}

#[tokio::test]
async fn post_message_runs_packaged_skills_through_the_agent_turn_loop() {
    let storage = Storage::connect("sqlite::memory:").await.unwrap();
    let skills_root = packaged_echo_skill().await;
    let skills = SkillRegistry::load_packaged(&skills_root).await.unwrap();
    let runner = TurnRunner::new(
        SkillCallingModel {
            calls: AtomicUsize::new(0),
        },
        skills,
    );
    let app = router(Arc::new(AppState::new_with_agent(
        storage.clone(),
        Arc::new(runner),
    )));

    let create_response = app
        .clone()
        .oneshot(json_request(
            "/sessions",
            json!({ "title": "Hidden skill" }),
        ))
        .await
        .unwrap();
    let created = read_json(create_response).await;
    let session_id = created["id"].as_str().unwrap();

    let message_response = app
        .oneshot(json_request(
            &format!("/sessions/{session_id}/messages"),
            json!({ "content": "Use the hidden echo capability" }),
        ))
        .await
        .unwrap();

    assert_eq!(message_response.status(), StatusCode::OK);
    let message = read_json(message_response).await;
    assert_eq!(
        message["assistant_message"]["content"],
        "The hidden capability returned hidden skill result."
    );
    assert_eq!(message["events"][0]["type"], "turn_started");
    assert!(
        message["events"]
            .as_array()
            .unwrap()
            .iter()
            .any(|event| event["type"] == "tool_call_finished")
    );

    let stored_messages = storage.list_messages(session_id).await.unwrap();
    assert_eq!(
        stored_messages[1].content,
        "The hidden capability returned hidden skill result."
    );

    remove_test_dir(skills_root).await;
}

#[tokio::test]
async fn post_message_rejects_missing_session() {
    let storage = Storage::connect("sqlite::memory:").await.unwrap();
    let app = router(Arc::new(AppState::new(storage)));

    let response = app
        .oneshot(json_request(
            "/sessions/missing-session/messages",
            json!({ "content": "hello" }),
        ))
        .await
        .unwrap();

    assert_eq!(response.status(), StatusCode::NOT_FOUND);
    let body = read_json(response).await;
    assert_eq!(body["error"], "session not found");
}

#[tokio::test]
async fn test_model_connection_uses_supplied_chat_completions_profile() {
    let storage = Storage::connect("sqlite::memory:").await.unwrap();
    let provider_capture = Arc::new(ProviderCapture::default());
    let provider_base_url = spawn_provider_server(provider_capture.clone()).await;
    let app = router(Arc::new(AppState::new(storage)));

    let response = app
        .oneshot(json_request(
            "/model/test",
            json!({
                "apiKey": "local-secret",
                "baseUrl": provider_base_url,
                "endpointType": "chat_completions",
                "modelName": "qwen2.5"
            }),
        ))
        .await
        .unwrap();

    assert_eq!(response.status(), StatusCode::OK);
    let body = read_json(response).await;
    assert_eq!(body["ok"], true);
    assert_eq!(body["message"], "Connection succeeded");

    let captured = provider_capture
        .request
        .lock()
        .unwrap()
        .clone()
        .expect("provider should receive test request");
    assert_eq!(captured.authorization, Some("Bearer local-secret".into()));
    assert_eq!(captured.body["model"], "qwen2.5");
    assert_eq!(captured.body["stream"], false);
    assert_eq!(captured.body["messages"][0]["role"], "user");
}

#[tokio::test]
async fn post_message_uses_supplied_model_settings_for_agent_turn() {
    let storage = Storage::connect("sqlite::memory:").await.unwrap();
    let provider_capture = Arc::new(ProviderCapture::default());
    let provider_base_url = spawn_provider_server(provider_capture.clone()).await;
    let workspace = unique_test_dir("server-configured-provider-workspace");
    tokio::fs::create_dir_all(&workspace).await.unwrap();
    tokio::fs::write(
        workspace.join("AGENTS.md"),
        "Project instruction from configured workspace",
    )
    .await
    .unwrap();
    let runtime_config = RuntimeConfig::workspace_write(workspace.clone(), workspace.clone());
    let skills = development_skills().await;
    let app = router(Arc::new(
        AppState::new_with_agent_and_skills(storage.clone(), Arc::new(DeterministicAgent), skills)
            .with_runtime_config(runtime_config),
    ));

    let create_response = app
        .clone()
        .oneshot(json_request(
            "/sessions",
            json!({ "title": "Configured provider" }),
        ))
        .await
        .unwrap();
    let created = read_json(create_response).await;
    let session_id = created["id"].as_str().unwrap();

    let message_response = app
        .oneshot(json_request(
            &format!("/sessions/{session_id}/messages"),
            json!({
                "content": "Use the configured provider",
                "modelSettings": {
                    "apiKey": "local-secret",
                    "baseUrl": provider_base_url,
                    "endpointType": "chat_completions",
                    "modelName": "qwen2.5"
                }
            }),
        ))
        .await
        .unwrap();

    assert_eq!(message_response.status(), StatusCode::OK);
    let message = read_json(message_response).await;
    assert_eq!(message["assistant_message"]["content"], "ok");

    let captured = provider_capture
        .request
        .lock()
        .unwrap()
        .clone()
        .expect("provider should receive chat request");
    assert_eq!(captured.authorization, Some("Bearer local-secret".into()));
    assert_eq!(captured.body["model"], "qwen2.5");
    let messages = captured.body["messages"].as_array().unwrap();
    assert!(messages.iter().any(|message| message["role"] == "system"));
    let project_instruction = messages
        .iter()
        .find(|message| {
            message["role"] == "system"
                && message["content"]
                    .as_str()
                    .is_some_and(|content| content.contains("Project instruction"))
        })
        .and_then(|message| message["content"].as_str())
        .expect("project instruction system message should be present");
    assert!(project_instruction.contains("Project instruction from configured workspace"));
    assert!(messages.iter().any(|message| {
        message["role"] == "user" && message["content"] == "Use the configured provider"
    }));

    remove_test_dir(workspace).await;
}

#[tokio::test]
async fn custom_model_settings_preserve_management_service_and_request_actor() {
    let storage = Storage::connect("sqlite::memory:").await.unwrap();
    let app_root = unique_test_dir("settings-owner-app");
    let cache_root = unique_test_dir("settings-owner-cache");
    tokio::fs::create_dir_all(&app_root).await.unwrap();
    tokio::fs::create_dir_all(&cache_root).await.unwrap();
    let paths = SkillStorePaths::prepare(&app_root, &cache_root)
        .await
        .unwrap();
    let state_store = SkillStateStore::new(storage.clone());
    let manager = SkillManager::from_registry_and_catalog(
        SkillRegistry::empty(),
        agent_runtime::skill_catalog::SkillCatalog::empty(),
    );
    let service = OwnerSkillManagementService::new(
        manager.clone(),
        SkillRevisionStore::new(paths, state_store.clone()),
        state_store,
        SkillManagementPolicy::owner_only(),
    );
    let owner = ActorContext::owner("owner-1", [SkillGrant::Inspect, SkillGrant::CreateDraft]);
    let owner_config = OwnerApiConfig::new(
        service,
        OwnerAuth::new("secret-token", owner.clone()).unwrap(),
    );
    let default_tools = Arc::new(Mutex::new(Vec::new()));
    let state = AppState::new_with_model_skill_manager_and_owner(
        storage,
        ToolSchemaCaptureModel {
            tool_names: default_tools,
        },
        manager,
        RuntimeConfig::read_only(".", ".").without_builtin_tools(),
        owner_config,
    );
    let provider_capture = Arc::new(ProviderCapture::default());
    let provider_base_url = spawn_provider_server(provider_capture.clone()).await;
    let request = UserMessageRequest {
        content: "owner custom model turn".into(),
        model_settings: Some(ModelConnectionTestRequest {
            api_key: None,
            base_url: provider_base_url,
            endpoint_type: EndpointType::ChatCompletions,
            model_name: "qwen2.5".into(),
        }),
    };

    run_agent_turn_for_actor(&state, "session-1", &request, owner, Vec::new())
        .await
        .unwrap();

    let body = provider_capture
        .request
        .lock()
        .unwrap()
        .as_ref()
        .unwrap()
        .body
        .clone();
    let tools = body["tools"].as_array().unwrap();
    assert!(!tools.is_empty());
    assert!(tools.iter().all(|tool| {
        tool["function"]["name"]
            .as_str()
            .is_some_and(|name| name.starts_with("ga_") && name.len() <= 64)
    }));
    remove_test_dir(app_root).await;
    remove_test_dir(cache_root).await;
}

#[tokio::test]
async fn post_message_rejects_completion_endpoint_for_tool_using_turns() {
    let storage = Storage::connect("sqlite::memory:").await.unwrap();
    let skills = development_skills().await;
    let app = router(Arc::new(AppState::new_with_agent_and_skills(
        storage,
        Arc::new(DeterministicAgent),
        skills,
    )));

    let create_response = app
        .clone()
        .oneshot(json_request(
            "/sessions",
            json!({ "title": "Completion endpoint" }),
        ))
        .await
        .unwrap();
    let created = read_json(create_response).await;
    let session_id = created["id"].as_str().unwrap();

    let message_response = app
        .oneshot(json_request(
            &format!("/sessions/{session_id}/messages"),
            json!({
                "content": "Use completion endpoint",
                "modelSettings": {
                    "baseUrl": "http://127.0.0.1:9/v1",
                    "endpointType": "completion",
                    "modelName": "legacy"
                }
            }),
        ))
        .await
        .unwrap();

    assert_eq!(message_response.status(), StatusCode::BAD_REQUEST);
    let body = read_json(message_response).await;
    assert_eq!(
        body["error"],
        "model endpoint does not support runtime tools"
    );
}

#[tokio::test]
async fn app_state_accepts_runtime_config_for_model_settings_turns() {
    let storage = Storage::connect("sqlite::memory:").await.unwrap();
    let workspace = unique_test_dir("server-runtime-config");
    tokio::fs::create_dir_all(&workspace).await.unwrap();
    let runtime_config = RuntimeConfig::workspace_write(workspace.clone(), workspace.clone());
    let skills = development_skills().await;

    let state = AppState::new_with_agent_and_skills(storage, Arc::new(DeterministicAgent), skills)
        .with_runtime_config(runtime_config);

    assert_eq!(state.runtime_config.workspace_root, workspace);
    assert_eq!(
        state.runtime_config.cwd,
        state.runtime_config.workspace_root
    );

    remove_test_dir(state.runtime_config.workspace_root).await;
}

#[tokio::test]
async fn app_state_reads_skills_from_the_current_snapshot() {
    let storage = Storage::connect("sqlite::memory:").await.unwrap();
    let skills_root = packaged_echo_skill().await;
    let manager = dynamic_skill_manager(&skills_root).await;
    let state = AppState::new_with_agent(storage, Arc::new(DeterministicAgent))
        .with_skill_manager(manager.clone());

    assert_eq!(state.skills().tools()[0].name, "echo");

    write_packaged_tool(&skills_root, "second_tool").await;
    manager.reload().await.unwrap();

    assert_eq!(state.skills().tools()[0].name, "second_tool");
    assert_eq!(state.skill_manager().current_snapshot().generation(), 2);
    remove_test_dir(skills_root).await;
}

#[tokio::test]
async fn production_state_binds_default_settings_and_dev_views_to_one_manager() {
    let storage = Storage::connect("sqlite::memory:").await.unwrap();
    let skills_root = packaged_echo_skill().await;
    let manager = dynamic_skill_manager(&skills_root).await;
    let default_tools = Arc::new(Mutex::new(Vec::new()));
    let workspace = unique_test_dir("atomic-production-state");
    tokio::fs::create_dir_all(&workspace).await.unwrap();
    let state = Arc::new(
        AppState::new_with_model_and_skill_manager(
            storage.clone(),
            ToolSchemaCaptureModel {
                tool_names: default_tools.clone(),
            },
            manager.clone(),
            RuntimeConfig::workspace_write(workspace.clone(), workspace.clone())
                .without_builtin_tools(),
        )
        .with_skills_root(skills_root.clone()),
    );

    write_packaged_tool(&skills_root, "second_tool").await;
    manager.reload().await.unwrap();
    let default_session = storage.create_session("Default turn").await.unwrap();
    let settings_session = storage.create_session("Settings turn").await.unwrap();
    let provider_capture = Arc::new(ProviderCapture::default());
    let provider_base_url = spawn_provider_server(provider_capture.clone()).await;
    let app = router_with_dev_routes(state.clone());

    let default_response = app
        .clone()
        .oneshot(json_request(
            &format!("/sessions/{}/messages", default_session.id),
            json!({ "content": "default" }),
        ))
        .await
        .unwrap();
    assert_eq!(default_response.status(), StatusCode::OK);

    let settings_response = app
        .clone()
        .oneshot(json_request(
            &format!("/sessions/{}/messages", settings_session.id),
            json!({
                "content": "settings",
                "modelSettings": {
                    "baseUrl": provider_base_url,
                    "endpointType": "chat_completions",
                    "modelName": "qwen2.5"
                }
            }),
        ))
        .await
        .unwrap();
    assert_eq!(settings_response.status(), StatusCode::OK);

    let dev_tools = read_json(
        app.oneshot(
            Request::builder()
                .uri("/dev/tools")
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap(),
    )
    .await;

    let default_names = default_tools.lock().unwrap().clone();
    assert!(default_names.iter().any(|name| name == "second_tool"));
    assert!(!default_names.iter().any(|name| name == "echo"));
    let provider_body = provider_capture
        .request
        .lock()
        .unwrap()
        .as_ref()
        .unwrap()
        .body
        .to_string();
    assert!(provider_body.contains("second_tool"));
    assert!(!provider_body.contains("\"name\":\"echo\""));
    assert!(
        dev_tools["tools"]
            .as_array()
            .unwrap()
            .iter()
            .any(|tool| { tool["name"] == "second_tool" })
    );
    assert_eq!(state.skill_manager().current_snapshot().generation(), 2);

    remove_test_dir(skills_root).await;
    remove_test_dir(workspace).await;
}

#[test]
fn internal_api_errors_return_500() {
    let response = ApiError::Internal(anyhow::anyhow!("storage unavailable")).into_response();

    assert_eq!(response.status(), StatusCode::INTERNAL_SERVER_ERROR);
}

#[test]
fn upstream_model_errors_return_bad_gateway() {
    let response = agent_turn_error(anyhow::anyhow!(
        "upstream model request failed: 400 Bad Request"
    ))
    .into_response();

    assert_eq!(response.status(), StatusCode::BAD_GATEWAY);
}

#[tokio::test]
async fn supports_vite_desktop_cors_preflight() {
    let storage = Storage::connect("sqlite::memory:").await.unwrap();
    let app = router(Arc::new(AppState::new(storage)));

    for origin in ["http://127.0.0.1:5173", "http://localhost:5173"] {
        let response = app
            .clone()
            .oneshot(
                Request::builder()
                    .method("OPTIONS")
                    .uri("/sessions/session-1/messages")
                    .header(header::ORIGIN, origin)
                    .header(header::ACCESS_CONTROL_REQUEST_METHOD, "POST")
                    .header(header::ACCESS_CONTROL_REQUEST_HEADERS, "content-type")
                    .body(Body::empty())
                    .unwrap(),
            )
            .await
            .unwrap();

        assert_eq!(response.status(), StatusCode::OK);
        assert_eq!(
            response.headers()[header::ACCESS_CONTROL_ALLOW_ORIGIN],
            origin
        );
        assert!(
            response.headers()[header::ACCESS_CONTROL_ALLOW_METHODS]
                .to_str()
                .unwrap()
                .contains("POST")
        );
        assert!(
            response.headers()[header::ACCESS_CONTROL_ALLOW_HEADERS]
                .to_str()
                .unwrap()
                .contains("content-type")
        );
    }
}

#[tokio::test]
async fn owner_draft_put_supports_vite_desktop_cors_preflight() {
    let storage = Storage::connect("sqlite::memory:").await.unwrap();
    let app = router(Arc::new(AppState::new(storage)));
    let revision_id = uuid::Uuid::new_v4();
    let response = app
        .oneshot(
            Request::builder()
                .method("OPTIONS")
                .uri(format!("/owner/skills/drafts/{revision_id}"))
                .header(header::ORIGIN, "http://127.0.0.1:5173")
                .header(header::ACCESS_CONTROL_REQUEST_METHOD, "PUT")
                .header(
                    header::ACCESS_CONTROL_REQUEST_HEADERS,
                    "authorization,content-type",
                )
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
    let methods = response.headers()[header::ACCESS_CONTROL_ALLOW_METHODS]
        .to_str()
        .unwrap();
    assert!(methods.split(',').any(|method| method.trim() == "PUT"));
    let headers = response.headers()[header::ACCESS_CONTROL_ALLOW_HEADERS]
        .to_str()
        .unwrap();
    assert!(
        headers
            .split(',')
            .any(|name| name.trim() == "authorization")
    );
    assert!(headers.split(',').any(|name| name.trim() == "content-type"));
}

#[tokio::test]
async fn production_router_does_not_expose_skill_inventory() {
    let storage = Storage::connect("sqlite::memory:").await.unwrap();
    let app = router(Arc::new(AppState::new(storage)));

    for uri in ["/skills", "/dev/skills"] {
        let response = app
            .clone()
            .oneshot(
                Request::builder()
                    .method("GET")
                    .uri(uri)
                    .body(Body::empty())
                    .unwrap(),
            )
            .await
            .unwrap();

        assert_eq!(response.status(), StatusCode::NOT_FOUND);
    }
}

fn json_request(uri: &str, body: Value) -> Request<Body> {
    Request::builder()
        .method("POST")
        .uri(uri)
        .header(header::CONTENT_TYPE, "application/json")
        .body(Body::from(body.to_string()))
        .unwrap()
}

async fn read_json(response: axum::response::Response) -> Value {
    let bytes = to_bytes(response.into_body(), usize::MAX).await.unwrap();
    serde_json::from_slice(&bytes).unwrap()
}

#[derive(Clone, Debug)]
struct CapturedProviderRequest {
    authorization: Option<String>,
    body: Value,
}

#[derive(Default)]
struct ProviderCapture {
    request: Mutex<Option<CapturedProviderRequest>>,
}

async fn spawn_provider_server(capture: Arc<ProviderCapture>) -> String {
    let app = Router::new()
        .route("/v1/chat/completions", post(capture_provider_request))
        .with_state(capture);
    let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
    let addr = listener.local_addr().unwrap();

    tokio::spawn(async move {
        axum::serve(listener, app).await.unwrap();
    });

    format!("http://{addr}/v1")
}

async fn capture_provider_request(
    State(capture): State<Arc<ProviderCapture>>,
    headers: HeaderMap,
    Json(body): Json<Value>,
) -> Json<Value> {
    let authorization = headers
        .get(header::AUTHORIZATION)
        .and_then(|value| value.to_str().ok())
        .map(str::to_string);
    *capture.request.lock().unwrap() = Some(CapturedProviderRequest {
        authorization,
        body,
    });

    Json(json!({
        "choices": [
            {
                "message": {
                    "content": "ok"
                }
            }
        ]
    }))
}

async fn development_skills() -> SkillRegistry {
    let skills_root = Path::new(env!("CARGO_MANIFEST_DIR"))
        .parent()
        .and_then(Path::parent)
        .unwrap()
        .join("skills");
    SkillRegistry::load_development(skills_root).await.unwrap()
}

async fn packaged_echo_skill() -> PathBuf {
    let root = unique_test_dir("server-packaged-echo");
    let skill_dir = root.join("echo");
    tokio::fs::create_dir_all(&skill_dir).await.unwrap();
    tokio::fs::write(
        root.join("skill-bundle.json"),
        json!({
            "skills": [
                { "path": "echo" }
            ]
        })
        .to_string(),
    )
    .await
    .unwrap();
    tokio::fs::write(
        skill_dir.join("skill.json"),
        json!({
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
                    "input_schema": {
                        "type": "object",
                        "properties": {
                            "text": { "type": "string" }
                        },
                        "required": ["text"]
                    }
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

async fn dynamic_skill_manager(root: &Path) -> SkillManager {
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

async fn write_packaged_tool(root: &Path, tool_name: &str) {
    tokio::fs::write(
        root.join("echo/skill.json"),
        json!({
            "name": "echo",
            "description": "Echo a text payload.",
            "version": "0.1.0",
            "entry": {
                "type": "command",
                "command": "node",
                "args": ["index.js"]
            },
            "tools": [{
                "name": tool_name,
                "description": "Return the provided text.",
                "input_schema": { "type": "object" }
            }]
        })
        .to_string(),
    )
    .await
    .unwrap();
}

fn unique_test_dir(name: &str) -> PathBuf {
    std::env::temp_dir().join(format!("agentweave-{name}-{}", uuid::Uuid::new_v4()))
}

async fn remove_test_dir(path: impl AsRef<Path>) {
    if path.as_ref().exists() {
        tokio::fs::remove_dir_all(path).await.unwrap();
    }
}
