use agent_runtime::platform::PlatformId;
use agent_runtime::skill_bundle::{BuildSkillBundleRequest, build_skill_bundle};
use agent_runtime::skill_policy::{ActorContext, SkillGrant, SkillManagementPolicy};
use mobile_ffi::{
    MobileInitConfig, MobileModelConfigDto, MobileRuntime, close_runtime, initialize_runtime_json,
    invoke_runtime_json, send_message_json,
};
use serde_json::{Value, json};
use std::collections::BTreeMap;
use std::io::{Read, Write};
use std::net::TcpListener;
use std::sync::mpsc;
use std::thread;
use std::time::{Duration, Instant};
use tempfile::tempdir;

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
            generated_at: "2026-07-12T00:00:00Z".into(),
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

#[test]
fn owner_operations_use_stored_actor_and_reject_json_actor_injection() {
    let dir = tempdir().unwrap();
    let mut config = init_config(dir.path());
    config.skill_policy = SkillManagementPolicy::owner_only();
    config.actor_context = ActorContext::owner("mobile-owner", [SkillGrant::Inspect]);
    let initialized: Value = serde_json::from_str(&initialize_runtime_json(
        &serde_json::to_string(&config).unwrap(),
    ))
    .unwrap();
    let handle = initialized["data"]["handle"].as_i64().unwrap();

    let stored_actor: Value = serde_json::from_str(&invoke_runtime_json(
        handle,
        &json!({"operation": "list_managed_skills"}).to_string(),
    ))
    .unwrap();
    let spoofed_actor: Value = serde_json::from_str(&invoke_runtime_json(
        handle,
        &json!({
            "operation": "list_managed_skills",
            "actor_context": {
                "actor_id": "attacker",
                "role": "owner",
                "tenant_id": null,
                "device_id": null,
                "grants": ["inspect"]
            }
        })
        .to_string(),
    ))
    .unwrap();

    assert_eq!(stored_actor["ok"], true);
    assert_eq!(spoofed_actor["ok"], false);
    close_runtime(handle);
}

#[test]
fn mobile_owner_bridge_exposes_real_revision_detail() {
    let dir = tempdir().unwrap();
    let mut config = init_config(dir.path());
    config.skill_policy = SkillManagementPolicy::owner_only();
    config.actor_context = ActorContext::owner(
        "mobile-owner",
        [SkillGrant::Inspect, SkillGrant::CreateDraft],
    );
    let handle = initialize_handle(&config);
    invoke_value(
        handle,
        json!({
            "operation": "create_skill_draft",
            "request": {
                "package_id": "com.example.mobile-detail",
                "display_name": "Mobile Detail",
                "description": "Revision detail contract.",
                "kind": "instruction_only",
                "required_tools": []
            }
        }),
    );

    let detail = invoke_value(
        handle,
        json!({
            "operation": "get_skill_detail",
            "package_id": "com.example.mobile-detail"
        }),
    );

    assert_eq!(detail["package_id"], "com.example.mobile-detail");
    assert_eq!(detail["revisions"].as_array().unwrap().len(), 1);
    assert_eq!(detail["editable_draft"]["editable"], true);
    assert!(detail["editable_draft"]["content_hash"].as_str().is_some());
    close_runtime(handle);
}

#[test]
fn create_only_mobile_owner_can_create_complete_initial_draft() {
    let dir = tempdir().unwrap();
    let mut config = init_config(dir.path());
    config.skill_policy = SkillManagementPolicy::owner_only();
    config.actor_context = ActorContext::owner(
        "create-only-owner",
        [SkillGrant::Inspect, SkillGrant::CreateDraft],
    );
    let handle = initialize_handle(&config);

    let created = invoke_value(
        handle,
        json!({
            "operation": "create_skill_draft",
            "request": {
                "package_id": "com.example.create-only",
                "display_name": "Create Only",
                "description": "Created without edit permission.",
                "kind": "instruction_only",
                "required_tools": []
            },
            "files": initial_draft_files(
                "com.example.create-only",
                "Create Only",
                "Initial instructions from the create request."
            )
        }),
    );
    let detail = invoke_value(
        handle,
        json!({"operation": "get_skill_detail", "package_id": "com.example.create-only"}),
    );

    assert_eq!(created["status"], "draft");
    assert_eq!(
        detail["editable_draft"]["instructions"],
        "Initial instructions from the create request."
    );
    let denied: Value = serde_json::from_str(&invoke_runtime_json(
        handle,
        &json!({
            "operation": "update_skill_draft",
            "revision_id": created["revision_id"],
            "files": initial_draft_files(
                "com.example.create-only",
                "Create Only",
                "An edit that must be denied."
            )
        })
        .to_string(),
    ))
    .unwrap();
    assert_eq!(denied["ok"], false);
    close_runtime(handle);
}

#[test]
fn mobile_draft_approval_flow_binds_requester_approver_and_audit_actors() {
    let dir = tempdir().unwrap();
    let mut requester_config = init_config(dir.path());
    requester_config.skill_policy = SkillManagementPolicy::owner_only();
    requester_config.skill_policy.rollback_approval_required = true;
    requester_config.actor_context = ActorContext::owner(
        "mobile-requester",
        [
            SkillGrant::Inspect,
            SkillGrant::CreateDraft,
            SkillGrant::Validate,
            SkillGrant::Activate,
            SkillGrant::Disable,
            SkillGrant::Rollback,
            SkillGrant::DeleteManaged,
        ],
    );
    let requester = initialize_handle(&requester_config);
    let mut approver_config = requester_config.clone();
    approver_config.actor_context = ActorContext::owner(
        "mobile-approver",
        [
            SkillGrant::Inspect,
            SkillGrant::Activate,
            SkillGrant::Rollback,
            SkillGrant::DeleteManaged,
        ],
    );
    let approver = initialize_handle(&approver_config);

    let draft = invoke_value(
        requester,
        json!({
            "operation": "create_skill_draft",
            "request": {
                "package_id": "com.example.mobile-authored",
                "display_name": "Mobile Authored",
                "description": "Created through the mobile owner bridge.",
                "kind": "instruction_only",
                "required_tools": []
            },
            "files": initial_draft_files(
                "com.example.mobile-authored",
                "Mobile Authored",
                "---\nname: mobile-authored\ndescription: Mobile authored evidence.\n---\n\nMOBILE_NEXT_TURN_ACTIVE_SKILL_EVIDENCE"
            )
        }),
    );
    let revision_id = draft["revision_id"].as_str().unwrap();
    let validation = invoke_value(
        requester,
        json!({"operation": "validate_skill_draft", "revision_id": revision_id}),
    );
    assert_eq!(validation["ok"], true);
    let approval = invoke_value(
        requester,
        json!({"operation": "request_skill_activation", "revision_id": revision_id}),
    );
    assert_eq!(approval["requested_by"], "mobile-requester");
    assert_eq!(approval["permission_diff"], validation["permissionDiff"]);
    for field in [
        "addedCapabilities",
        "removedCapabilities",
        "addedTools",
        "removedTools",
        "addedConnectors",
        "removedConnectors",
    ] {
        assert!(approval["permission_diff"][field].is_array(), "{field}");
    }
    let resolved = invoke_value(
        approver,
        json!({
            "operation": "resolve_skill_approval",
            "approval_id": approval["approval_id"],
            "approve": true
        }),
    );
    assert_eq!(resolved["status"], "approved");
    invoke_value(requester, json!({"operation": "synchronize_skills"}));

    let (base_url, captured_request, server) = capture_responses_request();
    invoke_value(
        requester,
        json!({
            "operation": "save_model_config",
            "config": model_config(base_url)
        }),
    );
    let session = invoke_value(
        requester,
        json!({"operation": "create_session", "title": "Next turn evidence"}),
    );
    let turn: Value = serde_json::from_str(&send_message_json(
        requester,
        &json!({
            "session_id": session["id"],
            "content": "Use $mobile-authored for this turn"
        })
        .to_string(),
        Some("sk-mobile-evidence".into()),
    ))
    .unwrap();
    assert_eq!(turn["ok"], true, "{turn}");
    let request = captured_request
        .recv_timeout(Duration::from_secs(2))
        .unwrap();
    let request_body = request.split_once("\r\n\r\n").unwrap().1;
    assert!(request_body.contains("MOBILE_NEXT_TURN_ACTIVE_SKILL_EVIDENCE"));
    assert!(!request_body.contains("sk-mobile-evidence"));
    if let Ok(path) = std::env::var("TASK17_MOBILE_REQUEST_EVIDENCE") {
        std::fs::write(path, request_body).unwrap();
    }
    server.join().unwrap();

    let second = invoke_value(
        requester,
        json!({
            "operation": "create_skill_draft",
            "request": {
                "package_id": "com.example.mobile-authored",
                "display_name": "Mobile Authored",
                "description": "Second mobile revision.",
                "kind": "instruction_only",
                "required_tools": []
            }
        }),
    );
    let second_revision = second["revision_id"].as_str().unwrap();
    invoke_value(
        requester,
        json!({"operation": "validate_skill_draft", "revision_id": second_revision}),
    );
    let second_approval = invoke_value(
        requester,
        json!({"operation": "request_skill_activation", "revision_id": second_revision}),
    );
    invoke_value(
        approver,
        json!({
            "operation": "resolve_skill_approval",
            "approval_id": second_approval["approval_id"],
            "approve": true
        }),
    );
    invoke_value(requester, json!({"operation": "synchronize_skills"}));

    let rollback = invoke_value(
        requester,
        json!({
            "operation": "rollback_managed_skill",
            "package_id": "com.example.mobile-authored",
            "revision_id": revision_id
        }),
    );
    assert_eq!(rollback["requested_by"], "mobile-requester");
    assert_eq!(rollback["permission_diff"], json!({}));
    invoke_value(
        approver,
        json!({
            "operation": "resolve_skill_approval",
            "approval_id": rollback["approval_id"],
            "approve": true
        }),
    );
    invoke_value(requester, json!({"operation": "synchronize_skills"}));

    let disabled = invoke_value(
        requester,
        json!({
            "operation": "disable_managed_skill",
            "package_id": "com.example.mobile-authored"
        }),
    );
    assert_eq!(disabled["active_packages"], 0);
    invoke_value(approver, json!({"operation": "synchronize_skills"}));

    let reactivation = invoke_value(
        requester,
        json!({
            "operation": "create_skill_draft",
            "request": {
                "package_id": "com.example.mobile-authored",
                "display_name": "Mobile Authored",
                "description": "Reactivation revision.",
                "kind": "instruction_only",
                "required_tools": []
            },
            "files": initial_draft_files(
                "com.example.mobile-authored",
                "Mobile Authored",
                "---\nname: mobile-reactivated\ndescription: Mobile reactivation evidence.\n---\n\nMOBILE_REACTIVATED_SKILL_EVIDENCE"
            )
        }),
    );
    let reactivation_revision = reactivation["revision_id"].as_str().unwrap();
    invoke_value(
        requester,
        json!({"operation": "validate_skill_draft", "revision_id": reactivation_revision}),
    );
    let reactivation_approval = invoke_value(
        requester,
        json!({"operation": "request_skill_activation", "revision_id": reactivation_revision}),
    );
    invoke_value(
        approver,
        json!({
            "operation": "resolve_skill_approval",
            "approval_id": reactivation_approval["approval_id"],
            "approve": true
        }),
    );
    invoke_value(requester, json!({"operation": "synchronize_skills"}));
    let reactivated = invoke_value(requester, json!({"operation": "list_managed_skills"}));
    assert_eq!(reactivated[0]["status"], "active");
    assert_eq!(reactivated[0]["active_revision_id"], reactivation_revision);

    let removal = invoke_value(
        requester,
        json!({
            "operation": "request_skill_removal",
            "package_id": "com.example.mobile-authored"
        }),
    );
    assert_eq!(removal["requested_by"], "mobile-requester");
    assert_eq!(removal["permission_diff"], json!({}));
    let removed = invoke_value(
        approver,
        json!({
            "operation": "resolve_skill_approval",
            "approval_id": removal["approval_id"],
            "approve": true
        }),
    );
    assert_eq!(removed["status"], "approved");
    let inventory = invoke_value(requester, json!({"operation": "list_skills"}));
    assert!(
        inventory
            .as_array()
            .unwrap()
            .iter()
            .all(|skill| { skill["package_id"] != json!("com.example.mobile-authored") }),
        "removed managed package leaked into layered inventory: {inventory}"
    );

    let audit_rows: Vec<(String, String, Option<String>)> =
        tokio::runtime::Runtime::new().unwrap().block_on(async {
        let pool = sqlx::SqlitePool::connect(&format!(
            "sqlite://{}",
            requester_config.database_path
        ))
        .await
        .unwrap();
        sqlx::query_as(
            "SELECT actor_id, operation, revision_id FROM skill_audit_log WHERE package_id = ? ORDER BY created_at, id",
        )
        .bind("com.example.mobile-authored")
        .fetch_all(&pool)
        .await
        .unwrap()
    });
    assert!(
        audit_rows.iter().any(|(actor, operation, revision)| {
            actor == "mobile-requester"
                && operation == "skill_approval_required"
                && revision.as_deref() == Some(revision_id)
        }),
        "{audit_rows:?}"
    );
    assert!(
        audit_rows.iter().any(|(actor, operation, revision)| {
            actor == "mobile-approver"
                && operation == "skill_snapshot_published"
                && revision.as_deref() == Some(revision_id)
        }),
        "{audit_rows:?}"
    );

    close_runtime(requester);
    close_runtime(approver);
}

#[test]
fn mobile_runtime_rejects_self_approval() {
    let dir = tempdir().unwrap();
    let mut config = init_config(dir.path());
    config.skill_policy = SkillManagementPolicy::owner_only();
    config.actor_context = ActorContext::owner(
        "mobile-requester",
        [
            SkillGrant::Inspect,
            SkillGrant::CreateDraft,
            SkillGrant::Validate,
            SkillGrant::Activate,
        ],
    );
    let requester = initialize_handle(&config);
    let draft = invoke_value(
        requester,
        json!({
            "operation": "create_skill_draft",
            "request": {
                "package_id": "com.example.self-approval",
                "display_name": "Self approval",
                "description": "Self approval must be rejected.",
                "kind": "instruction_only",
                "required_tools": []
            }
        }),
    );
    let revision_id = draft["revision_id"].as_str().unwrap();
    invoke_value(
        requester,
        json!({"operation": "validate_skill_draft", "revision_id": revision_id}),
    );
    let approval = invoke_value(
        requester,
        json!({"operation": "request_skill_activation", "revision_id": revision_id}),
    );

    let self_approval: Value = serde_json::from_str(&invoke_runtime_json(
        requester,
        &json!({
            "operation": "resolve_skill_approval",
            "approval_id": approval["approval_id"],
            "approve": true
        })
        .to_string(),
    ))
    .unwrap();

    assert_eq!(self_approval["ok"], false);
    close_runtime(requester);
}

fn initialize_handle(config: &MobileInitConfig) -> i64 {
    let response: Value = serde_json::from_str(&initialize_runtime_json(
        &serde_json::to_string(config).unwrap(),
    ))
    .unwrap();
    assert_eq!(response["ok"], true, "{response}");
    response["data"]["handle"].as_i64().unwrap()
}

fn initial_draft_files(package_id: &str, display_name: &str, instructions: &str) -> Value {
    json!([
        {
            "path": "SKILL.md",
            "content": instructions
        },
        {
            "path": "agentweave.json",
            "content": serde_json::to_string_pretty(&json!({
                "schemaVersion": 1,
                "id": package_id,
                "version": "0.1.0",
                "displayName": display_name,
                "kind": "instruction_only",
                "package": {"includeInstructions": true, "includeRuntime": false},
                "compatibility": {"minimumRuntimeVersion": null, "platforms": []},
                "requires": {
                    "packages": [],
                    "capabilities": [],
                    "runtimeTools": [],
                    "connectors": []
                }
            }))
            .unwrap()
        }
    ])
}

fn invoke_value(handle: i64, request: Value) -> Value {
    let response: Value =
        serde_json::from_str(&invoke_runtime_json(handle, &request.to_string())).unwrap();
    assert_eq!(response["ok"], true, "{response}");
    response["data"].clone()
}

fn model_config(base_url: String) -> MobileModelConfigDto {
    MobileModelConfigDto {
        provider_id: "openai".into(),
        provider_name: "OpenAI".into(),
        endpoint_type: "responses".into(),
        base_url,
        model_name: "gpt-test".into(),
        secret_id: Some("model.openai.default".into()),
        headers: BTreeMap::new(),
    }
}

fn capture_responses_request() -> (String, mpsc::Receiver<String>, thread::JoinHandle<()>) {
    let listener = TcpListener::bind("127.0.0.1:0").unwrap();
    let address = listener.local_addr().unwrap();
    let (sender, receiver) = mpsc::channel();
    let server = thread::spawn(move || {
        let (mut stream, _) = listener.accept().unwrap();
        stream
            .set_read_timeout(Some(Duration::from_secs(2)))
            .unwrap();
        let mut request = Vec::new();
        let mut buffer = [0_u8; 4096];
        let expected = loop {
            let read = stream.read(&mut buffer).unwrap();
            request.extend_from_slice(&buffer[..read]);
            if let Some(header_end) = request.windows(4).position(|window| window == b"\r\n\r\n") {
                let headers = String::from_utf8_lossy(&request[..header_end]);
                let content_length = headers
                    .lines()
                    .find_map(|line| {
                        line.to_ascii_lowercase()
                            .strip_prefix("content-length: ")
                            .map(str::to_string)
                    })
                    .unwrap()
                    .parse::<usize>()
                    .unwrap();
                break header_end + 4 + content_length;
            }
        };
        while request.len() < expected {
            let read = stream.read(&mut buffer).unwrap();
            request.extend_from_slice(&buffer[..read]);
        }
        sender.send(String::from_utf8(request).unwrap()).unwrap();
        let body = json!({
            "output": [{
                "type": "message",
                "content": [{"type": "output_text", "text": "mobile evidence reply"}]
            }]
        })
        .to_string();
        write!(
            stream,
            "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: {}\r\nConnection: close\r\n\r\n{}",
            body.len(),
            body,
        )
        .unwrap();
    });
    (format!("http://{address}/v1"), receiver, server)
}

#[test]
fn runtime_persists_sessions_and_non_secret_model_config_across_restart() {
    let dir = tempdir().unwrap();
    let config = init_config(dir.path());
    let runtime = MobileRuntime::initialize(config.clone()).unwrap();

    let session = runtime.create_session("Android runtime").unwrap();
    runtime
        .save_model_config(model_config("https://api.openai.com/v1".into()))
        .unwrap();
    drop(runtime);

    let restarted = MobileRuntime::initialize(config).unwrap();
    assert_eq!(restarted.list_sessions().unwrap()[0].id, session.id);
    assert_eq!(
        restarted.load_model_config().unwrap().unwrap().secret_id,
        Some("model.openai.default".into()),
    );
    assert!(restarted.diagnostics().unwrap().model_configured);
}

#[test]
fn json_bridge_uses_handles_for_session_operations() {
    let dir = tempdir().unwrap();
    let initialized: Value = serde_json::from_str(&initialize_runtime_json(
        &serde_json::to_string(&init_config(dir.path())).unwrap(),
    ))
    .unwrap();
    let handle = initialized["data"]["handle"].as_i64().unwrap();

    let created: Value = serde_json::from_str(&invoke_runtime_json(
        handle,
        &json!({"operation": "create_session", "title": "Bridge session"}).to_string(),
    ))
    .unwrap();
    let session_id = created["data"]["id"].as_str().unwrap();
    let listed: Value = serde_json::from_str(&invoke_runtime_json(
        handle,
        &json!({"operation": "list_sessions"}).to_string(),
    ))
    .unwrap();
    let skills: Value = serde_json::from_str(&invoke_runtime_json(
        handle,
        &json!({"operation": "list_skills"}).to_string(),
    ))
    .unwrap();

    assert_eq!(listed["data"][0]["id"], session_id);
    assert_eq!(skills["data"], json!([]));
    let closed: Value = serde_json::from_str(&close_runtime(handle)).unwrap();
    assert_eq!(closed["ok"], true);
}

#[test]
fn real_http_turn_uses_transient_api_key_without_persisting_it() {
    let listener = TcpListener::bind("127.0.0.1:0").unwrap();
    let address = listener.local_addr().unwrap();
    let server = thread::spawn(move || {
        let (mut stream, _) = listener.accept().unwrap();
        let mut request = Vec::new();
        let mut buffer = [0_u8; 4096];
        loop {
            let read = stream.read(&mut buffer).unwrap();
            if read == 0 {
                break;
            }
            request.extend_from_slice(&buffer[..read]);
            if request.windows(4).any(|window| window == b"\r\n\r\n") {
                break;
            }
        }
        let request_text = String::from_utf8_lossy(&request);
        assert!(request_text.starts_with("POST /v1/responses "));
        assert!(request_text.contains("authorization: Bearer sk-transient"));
        let body = json!({
            "output": [{
                "type": "message",
                "content": [{"type": "output_text", "text": "hello from mock"}]
            }]
        })
        .to_string();
        write!(
            stream,
            "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: {}\r\nConnection: close\r\n\r\n{}",
            body.len(),
            body,
        )
        .unwrap();
    });

    let dir = tempdir().unwrap();
    let config = init_config(dir.path());
    let database_path = config.database_path.clone();
    let runtime = MobileRuntime::initialize(config).unwrap();
    let session = runtime.create_session("HTTP turn").unwrap();
    runtime
        .save_model_config(model_config(format!("http://{address}/v1")))
        .unwrap();

    let turn = runtime
        .send_message(&session.id, "hello", Some("sk-transient".into()))
        .unwrap();
    server.join().unwrap();

    assert_eq!(turn.assistant_text, "hello from mock");
    assert_eq!(runtime.get_messages(&session.id).unwrap().len(), 2);
    assert!(
        !std::fs::read(database_path)
            .unwrap()
            .windows("sk-transient".len())
            .any(|window| window == b"sk-transient")
    );
}

#[test]
fn bridge_send_message_keeps_api_key_out_of_json_payloads() {
    let dir = tempdir().unwrap();
    let initialized: Value = serde_json::from_str(&initialize_runtime_json(
        &serde_json::to_string(&init_config(dir.path())).unwrap(),
    ))
    .unwrap();
    let handle = initialized["data"]["handle"].as_i64().unwrap();

    let response: Value = serde_json::from_str(&send_message_json(
        handle,
        &json!({"session_id": "missing", "content": "hello"}).to_string(),
        Some("sk-separate-argument".into()),
    ))
    .unwrap();

    assert_eq!(response["ok"], false);
    assert!(!response.to_string().contains("sk-separate-argument"));
    close_runtime(handle);
}

#[test]
fn owner_turn_transport_binds_initialized_author_and_rejects_approver_or_json_actor() {
    let author_root = tempdir().unwrap();
    let mut author_config = init_config(author_root.path());
    author_config.skill_policy = SkillManagementPolicy::owner_only();
    author_config.actor_context = ActorContext::owner(
        "mobile-author",
        [SkillGrant::Inspect, SkillGrant::CreateDraft],
    );
    let author_handle = initialize_handle(&author_config);
    let (author_url, author_request, author_server) = capture_responses_request();
    invoke_value(
        author_handle,
        json!({"operation": "save_model_config", "config": model_config(author_url)}),
    );
    let author_session = invoke_value(
        author_handle,
        json!({"operation": "create_session", "title": "Owner author"}),
    );
    let author_turn: Value = serde_json::from_str(&send_message_json(
        author_handle,
        &json!({
            "session_id": author_session["id"],
            "content": "create a skill"
        })
        .to_string(),
        Some("sk-author".into()),
    ))
    .unwrap();
    assert_eq!(author_turn["ok"], true, "{author_turn}");
    author_server.join().unwrap();
    let author_body = captured_http_json(&author_request.recv().unwrap());
    assert!(
        author_body["tools"]
            .as_array()
            .is_some_and(|tools| !tools.is_empty()),
        "{author_body}"
    );
    assert!(
        author_body
            .to_string()
            .contains("Create an inactive owner-managed skill draft")
    );

    let approver_root = tempdir().unwrap();
    let mut approver_config = init_config(approver_root.path());
    approver_config.skill_policy = SkillManagementPolicy::owner_only();
    approver_config.actor_context = ActorContext::owner(
        "mobile-approver",
        [SkillGrant::Inspect, SkillGrant::Activate],
    );
    let approver_handle = initialize_handle(&approver_config);
    let (approver_url, approver_request, approver_server) = capture_responses_request();
    invoke_value(
        approver_handle,
        json!({"operation": "save_model_config", "config": model_config(approver_url)}),
    );
    let approver_session = invoke_value(
        approver_handle,
        json!({"operation": "create_session", "title": "Approver"}),
    );
    let approver_turn: Value = serde_json::from_str(&send_message_json(
        approver_handle,
        &json!({
            "session_id": approver_session["id"],
            "content": "create a skill"
        })
        .to_string(),
        Some("sk-approver".into()),
    ))
    .unwrap();
    assert_eq!(approver_turn["ok"], true, "{approver_turn}");
    approver_server.join().unwrap();
    let approver_body = captured_http_json(&approver_request.recv().unwrap());
    assert!(
        approver_body["tools"].as_array().is_none_or(Vec::is_empty),
        "{approver_body}"
    );

    let injected: Value = serde_json::from_str(&send_message_json(
        approver_handle,
        &json!({
            "session_id": approver_session["id"],
            "content": "spoof",
            "actor_context": {"role": "owner", "grants": ["create_draft"]}
        })
        .to_string(),
        None,
    ))
    .unwrap();
    assert_eq!(injected["ok"], false);
    assert!(
        injected["error"]["message"]
            .as_str()
            .unwrap()
            .contains("unknown field")
    );
    close_runtime(author_handle);
    close_runtime(approver_handle);
}

fn captured_http_json(request: &str) -> Value {
    serde_json::from_str(request.split("\r\n\r\n").nth(1).unwrap()).unwrap()
}

#[test]
fn missing_model_config_preserves_submitted_user_message() {
    let dir = tempdir().unwrap();
    let runtime = MobileRuntime::initialize(init_config(dir.path())).unwrap();
    let session = runtime.create_session("Unconfigured turn").unwrap();

    let error = runtime
        .send_message(&session.id, "keep before setup", None)
        .unwrap_err();
    let messages = runtime.get_messages(&session.id).unwrap();

    assert!(
        error
            .to_string()
            .contains("model configuration is required")
    );
    assert_eq!(messages.len(), 1);
    assert_eq!(messages[0].role, "user");
    assert_eq!(messages[0].content, "keep before setup");
}

#[test]
fn failed_http_turn_preserves_submitted_user_message() {
    let listener = TcpListener::bind("127.0.0.1:0").unwrap();
    let address = listener.local_addr().unwrap();
    let server = thread::spawn(move || {
        let (mut stream, _) = listener.accept().unwrap();
        let mut buffer = [0_u8; 4096];
        let _ = stream.read(&mut buffer).unwrap();
        let body = r#"{"error":{"message":"provider unavailable"}}"#;
        write!(
            stream,
            "HTTP/1.1 503 Service Unavailable\r\nContent-Type: application/json\r\nContent-Length: {}\r\nConnection: close\r\n\r\n{}",
            body.len(),
            body,
        )
        .unwrap();
    });

    let dir = tempdir().unwrap();
    let runtime = MobileRuntime::initialize(init_config(dir.path())).unwrap();
    let session = runtime.create_session("Failed turn").unwrap();
    runtime
        .save_model_config(model_config(format!("http://{address}/v1")))
        .unwrap();

    let error = runtime
        .send_message(
            &session.id,
            "keep this message",
            Some("sk-transient".into()),
        )
        .unwrap_err();
    server.join().unwrap();
    let messages = runtime.get_messages(&session.id).unwrap();

    assert!(error.to_string().contains("503 Service Unavailable"));
    assert_eq!(messages.len(), 1);
    assert_eq!(messages[0].role, "user");
    assert_eq!(messages[0].content, "keep this message");
}

#[test]
fn closing_runtime_cancels_stalled_http_turn() {
    let listener = TcpListener::bind("127.0.0.1:0").unwrap();
    let address = listener.local_addr().unwrap();
    let (accepted_tx, accepted_rx) = std::sync::mpsc::channel();
    let server = thread::spawn(move || {
        let (mut stream, _) = listener.accept().unwrap();
        let mut buffer = [0_u8; 4096];
        let _ = stream.read(&mut buffer).unwrap();
        accepted_tx.send(()).unwrap();
        thread::sleep(Duration::from_secs(3));
    });

    let dir = tempdir().unwrap();
    let init = init_config(dir.path());
    let initialized: Value = serde_json::from_str(&initialize_runtime_json(
        &serde_json::to_string(&init).unwrap(),
    ))
    .unwrap();
    let handle = initialized["data"]["handle"].as_i64().unwrap();
    let created: Value = serde_json::from_str(&invoke_runtime_json(
        handle,
        &json!({"operation": "create_session", "title": "Cancelled turn"}).to_string(),
    ))
    .unwrap();
    let session_id = created["data"]["id"].as_str().unwrap().to_string();
    invoke_runtime_json(
        handle,
        &json!({
            "operation": "save_model_config",
            "config": model_config(format!("http://{address}/v1")),
        })
        .to_string(),
    );
    let send_session_id = session_id.clone();
    let send = thread::spawn(move || {
        send_message_json(
            handle,
            &json!({"session_id": send_session_id, "content": "cancel me"}).to_string(),
            Some("sk-transient".into()),
        )
    });
    accepted_rx.recv_timeout(Duration::from_secs(2)).unwrap();

    let started = Instant::now();
    close_runtime(handle);
    let response: Value = serde_json::from_str(&send.join().unwrap()).unwrap();

    assert!(started.elapsed() < Duration::from_secs(1));
    assert_eq!(response["ok"], false);
    assert!(
        response["error"]["message"]
            .as_str()
            .unwrap()
            .contains("closed")
    );

    let restarted = MobileRuntime::initialize(init).unwrap();
    let messages = restarted.get_messages(&session_id).unwrap();
    assert_eq!(messages.len(), 1);
    assert_eq!(messages[0].role, "user");
    server.join().unwrap();
}
