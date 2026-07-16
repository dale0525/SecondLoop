use super::*;
use crate::platform::{CapabilitySet, PlatformId};
use crate::skill_manager::{SkillManager, SkillManagerConfig};
use crate::skill_source::{DirectorySkillSource, SkillLayer};
use crate::tools::RuntimeConfig;
use futures::stream;
use semver::Version;
use std::fs;
use std::path::{Path, PathBuf};
use std::sync::{
    Arc, Mutex,
    atomic::{AtomicUsize, Ordering},
};
use tempfile::tempdir;

struct FakeModel {
    calls: AtomicUsize,
    requests: Mutex<Vec<model_gateway::responses::GatewayRequest>>,
}

#[async_trait]
impl ModelClient for FakeModel {
    async fn stream(
        &self,
        request: model_gateway::responses::GatewayRequest,
    ) -> anyhow::Result<ModelEventStream> {
        self.requests.lock().unwrap().push(request);
        let call = self.calls.fetch_add(1, Ordering::SeqCst);
        let events = if call == 0 {
            vec![
                Ok(GatewayEvent::ToolCall {
                    call_id: "call-1".into(),
                    name: "echo".into(),
                    legacy_alias_selected: false,
                    arguments: serde_json::json!({ "text": "hello" }),
                }),
                Ok(GatewayEvent::Completed),
            ]
        } else {
            vec![
                Ok(GatewayEvent::TextDelta {
                    text: "done".into(),
                }),
                Ok(GatewayEvent::Completed),
            ]
        };
        Ok(Box::pin(stream::iter(events)))
    }
}

#[tokio::test]
async fn executes_tool_and_continues_until_text_response() {
    let skills_root = Path::new(env!("CARGO_MANIFEST_DIR"))
        .parent()
        .and_then(Path::parent)
        .unwrap()
        .join("skills");
    let skills = SkillRegistry::load_development(skills_root).await.unwrap();
    let runner = TurnRunner::new(
        FakeModel {
            calls: AtomicUsize::new(0),
            requests: Mutex::new(Vec::new()),
        },
        skills,
    );

    let events = runner.run("echo hello").await.unwrap();

    assert!(matches!(
        events.last(),
        Some(RuntimeEvent::TurnFinished { .. })
    ));
    assert!(events.iter().any(|event| matches!(
        event,
        RuntimeEvent::ToolCallFinished { call_id, .. } if call_id == "call-1"
    )));
}

#[tokio::test]
async fn sends_runtime_tool_schemas_to_the_model() {
    let skills_root = Path::new(env!("CARGO_MANIFEST_DIR"))
        .parent()
        .and_then(Path::parent)
        .unwrap()
        .join("skills");
    let model = FakeModel {
        calls: AtomicUsize::new(0),
        requests: Mutex::new(Vec::new()),
    };
    let skills = SkillRegistry::load_development(skills_root).await.unwrap();
    let runner = TurnRunner::new(model, skills);

    let _events = runner.run("echo hello").await.unwrap();
    let requests = runner.model.requests.lock().unwrap();

    assert!(
        requests[0]
            .tools
            .iter()
            .any(|tool| tool.advertised_name() == "echo")
    );
    assert_eq!(requests[0].tools[0].input_schema["type"], "object");
}

struct ScriptedModel {
    calls: AtomicUsize,
    requests: Mutex<Vec<model_gateway::responses::GatewayRequest>>,
    responses: Vec<Vec<GatewayEvent>>,
}

#[async_trait]
impl ModelClient for ScriptedModel {
    async fn stream(
        &self,
        request: model_gateway::responses::GatewayRequest,
    ) -> anyhow::Result<ModelEventStream> {
        self.requests.lock().unwrap().push(request);
        let call = self.calls.fetch_add(1, Ordering::SeqCst);
        let events = self
            .responses
            .get(call)
            .or_else(|| self.responses.last())
            .cloned()
            .unwrap_or_else(|| vec![GatewayEvent::Completed])
            .into_iter()
            .map(Ok);
        Ok(Box::pin(stream::iter(events)))
    }
}

struct FakePhaseTwoModel {
    calls: AtomicUsize,
    tool_name: &'static str,
    arguments: serde_json::Value,
    requests: Mutex<Vec<model_gateway::responses::GatewayRequest>>,
}

#[async_trait]
impl ModelClient for FakePhaseTwoModel {
    async fn stream(
        &self,
        request: model_gateway::responses::GatewayRequest,
    ) -> anyhow::Result<ModelEventStream> {
        self.requests.lock().unwrap().push(request);
        let call = self.calls.fetch_add(1, Ordering::SeqCst);
        let events = if call == 0 {
            vec![
                Ok(GatewayEvent::ToolCall {
                    call_id: "call-1".into(),
                    name: self.tool_name.into(),
                    legacy_alias_selected: false,
                    arguments: self.arguments.clone(),
                }),
                Ok(GatewayEvent::Completed),
            ]
        } else {
            vec![
                Ok(GatewayEvent::TextDelta {
                    text: "done".into(),
                }),
                Ok(GatewayEvent::Completed),
            ]
        };
        Ok(Box::pin(stream::iter(events)))
    }
}

fn skills_root() -> std::path::PathBuf {
    Path::new(env!("CARGO_MANIFEST_DIR"))
        .parent()
        .and_then(Path::parent)
        .unwrap()
        .join("skills")
}

fn test_workspace(name: &str) -> std::path::PathBuf {
    let root = std::env::temp_dir().join(format!("agentweave-turn-{name}-{}", Uuid::new_v4()));
    fs::create_dir_all(&root).unwrap();
    root
}

fn remove_workspace(root: &Path) {
    let _ = fs::remove_dir_all(root);
}

fn tool_result(events: &[RuntimeEvent]) -> serde_json::Value {
    events
        .iter()
        .find_map(|event| match event {
            RuntimeEvent::ToolCallFinished { result, .. } => Some(result.clone()),
            _ => None,
        })
        .expect("tool result event should be present")
}

fn request_has_tool(request: &model_gateway::responses::GatewayRequest, name: &str) -> bool {
    request
        .tools
        .iter()
        .any(|tool| tool.advertised_name() == name)
}

struct PreferenceExtractor;

#[async_trait]
impl crate::memory_lifecycle::MemoryCandidateExtractor for PreferenceExtractor {
    async fn extract_candidates(
        &self,
        transcript: &crate::memory_lifecycle::MemoryTurnTranscript,
    ) -> anyhow::Result<Vec<crate::memory::MemoryDraft>> {
        assert_eq!(transcript.session_id, "session-memory");
        assert_eq!(transcript.user_text, "以后默认把会议安排在下午");
        assert_eq!(transcript.assistant_text, "我会先把它作为待确认偏好。");
        Ok(vec![crate::memory::MemoryDraft {
            kind: crate::memory::MemoryKind::parse(crate::memory::MemoryKind::PREFERENCE)?,
            value: crate::memory::MemoryValue::new("会议默认安排在下午")?,
            evidence: vec![crate::memory::MemoryEvidence {
                source: crate::memory::MemoryEvidenceSource::UserStatement,
                source_id: Some(transcript.session_id.clone()),
                excerpt: Some(transcript.user_text.clone()),
                observed_at: chrono::Utc::now(),
            }],
            confidence: crate::memory::MemoryConfidence::from_basis_points(9_000)?,
            sensitivity: crate::memory::MemorySensitivity::Personal,
            retention: crate::memory::MemoryRetention::Persistent,
            conflict_key: Some("meeting-time-preference".into()),
            supersedes: None,
        }])
    }
}

#[tokio::test]
async fn post_turn_memory_candidates_are_proposed_through_the_provider_lifecycle() {
    use crate::memory::{MemoryExportRequest, MemoryProvider, MemoryScope, MemoryState};

    let storage = crate::storage::Storage::connect("sqlite::memory:")
        .await
        .unwrap();
    let provider = Arc::new(storage.local_memory_provider());
    provider.initialize().await.unwrap();
    let scope = MemoryScope::new("app", "tenant", "user").unwrap();
    let memory =
        crate::memory_tools::MemoryToolRuntime::new(provider.clone(), scope.clone()).unwrap();
    let workspace = test_workspace("memory-lifecycle");
    let runner = TurnRunner::new_with_config(
        ScriptedModel {
            calls: AtomicUsize::new(0),
            requests: Mutex::new(Vec::new()),
            responses: vec![vec![
                GatewayEvent::TextDelta {
                    text: "我会先把它作为待确认偏好。".into(),
                },
                GatewayEvent::Completed,
            ]],
        },
        SkillRegistry::empty(),
        RuntimeConfig::workspace_write(workspace.clone(), workspace.clone()),
    )
    .with_memory_tools(memory)
    .with_memory_candidate_extractor(Arc::new(PreferenceExtractor));

    let events = runner
        .run_request(TurnRequest::new("以后默认把会议安排在下午").with_session_id("session-memory"))
        .await
        .unwrap();
    assert!(events.iter().any(|event| matches!(
        event,
        RuntimeEvent::MemoryCandidatesProposed { memory_ids } if memory_ids.len() == 1
    )));
    let exported = provider
        .export(MemoryExportRequest {
            scope,
            include_proposals: true,
            include_tombstones: false,
        })
        .await
        .unwrap();
    assert_eq!(exported.records.len(), 1);
    assert_eq!(exported.records[0].state, MemoryState::Proposed);
    remove_workspace(&workspace);
}

#[tokio::test]
async fn builtin_create_directory_creates_workspace_directory_through_turn_loop() {
    let workspace = test_workspace("create-directory");
    let skills = SkillRegistry::load_development(skills_root())
        .await
        .unwrap();
    let config = RuntimeConfig::workspace_write(workspace.clone(), workspace.clone());
    let runner = TurnRunner::new_with_config(
        ScriptedModel {
            calls: AtomicUsize::new(0),
            requests: Mutex::new(Vec::new()),
            responses: vec![
                vec![
                    GatewayEvent::ToolCall {
                        call_id: "call-create".into(),
                        name: "create_directory".into(),
                        legacy_alias_selected: false,
                        arguments: serde_json::json!({ "path": "made-by-tool" }),
                    },
                    GatewayEvent::Completed,
                ],
                vec![
                    GatewayEvent::TextDelta {
                        text: "created".into(),
                    },
                    GatewayEvent::Completed,
                ],
            ],
        },
        skills,
        config,
    );

    let events = runner.run("create a directory").await.unwrap();

    assert!(workspace.join("made-by-tool").is_dir());
    let result = events
        .iter()
        .find_map(|event| match event {
            RuntimeEvent::ToolCallFinished {
                call_id, result, ..
            } if call_id == "call-create" => Some(result),
            _ => None,
        })
        .unwrap();
    assert_eq!(result["ok"], true);
    assert_eq!(result["tool"], "create_directory");
    assert_eq!(result["data"]["path"], "made-by-tool");
    remove_workspace(&workspace);
}

#[tokio::test]
async fn phase_two_search_files_executes_through_turn_loop() {
    let workspace = test_workspace("phase-two-search-files");
    fs::write(workspace.join("notes.txt"), "find me\n").unwrap();
    let skills = SkillRegistry::load_development(skills_root())
        .await
        .unwrap();
    let config = RuntimeConfig::workspace_write(workspace.clone(), workspace.clone());
    let runner = TurnRunner::new_with_config(
        FakePhaseTwoModel {
            calls: AtomicUsize::new(0),
            tool_name: "search_files",
            arguments: serde_json::json!({ "pattern": "find" }),
            requests: Mutex::new(Vec::new()),
        },
        skills,
        config,
    );

    let events = runner.run("search for find").await.unwrap();

    let result = tool_result(&events);
    assert_eq!(result["ok"], true);
    assert_eq!(result["tool"], "search_files");
    assert_eq!(result["data"]["matches"][0]["path"], "notes.txt");
    remove_workspace(&workspace);
}

#[tokio::test]
async fn phase_two_exec_command_is_advertised_only_when_allowed() {
    let disabled_workspace = test_workspace("phase-two-command-disabled");
    let disabled_skills = SkillRegistry::load_development(skills_root())
        .await
        .unwrap();
    let disabled_config =
        RuntimeConfig::workspace_write(disabled_workspace.clone(), disabled_workspace.clone());
    let disabled_runner = TurnRunner::new_with_config(
        ScriptedModel {
            calls: AtomicUsize::new(0),
            requests: Mutex::new(Vec::new()),
            responses: vec![vec![
                GatewayEvent::TextDelta {
                    text: "done".into(),
                },
                GatewayEvent::Completed,
            ]],
        },
        disabled_skills,
        disabled_config,
    );

    let _events = disabled_runner
        .run("what tools are available?")
        .await
        .unwrap();
    {
        let disabled_requests = disabled_runner.model.requests.lock().unwrap();
        assert!(!request_has_tool(&disabled_requests[0], "exec_command"));
    }
    remove_workspace(&disabled_workspace);

    let workspace = test_workspace("phase-two-command-allowed");
    let skills = SkillRegistry::load_development(skills_root())
        .await
        .unwrap();
    let config = RuntimeConfig::workspace_write(workspace.clone(), workspace.clone())
        .with_command_mode(crate::tools::CommandMode::Allowed);
    let runner = TurnRunner::new_with_config(
        FakePhaseTwoModel {
            calls: AtomicUsize::new(0),
            tool_name: "exec_command",
            arguments: serde_json::json!({ "cmd": "printf hello" }),
            requests: Mutex::new(Vec::new()),
        },
        skills,
        config,
    );

    let events = runner.run("run printf").await.unwrap();

    let requests = runner.model.requests.lock().unwrap();
    assert!(request_has_tool(&requests[0], "exec_command"));
    drop(requests);
    let result = tool_result(&events);
    assert_eq!(result["ok"], true);
    assert_eq!(result["tool"], "exec_command");
    assert_eq!(result["data"]["stdout"], "hello");
    remove_workspace(&workspace);
}

#[tokio::test]
async fn phase_two_apply_patch_executes_through_turn_loop() {
    let workspace = test_workspace("phase-two-apply-patch");
    let skills = SkillRegistry::load_development(skills_root())
        .await
        .unwrap();
    let config = RuntimeConfig::workspace_write(workspace.clone(), workspace.clone());
    let runner = TurnRunner::new_with_config(
        FakePhaseTwoModel {
            calls: AtomicUsize::new(0),
            tool_name: "apply_patch",
            arguments: serde_json::json!({
                "patch": "*** Begin Patch\n*** Add File: notes.txt\n+patched\n*** End Patch\n"
            }),
            requests: Mutex::new(Vec::new()),
        },
        skills,
        config,
    );

    let events = runner.run("apply a patch").await.unwrap();

    assert_eq!(
        fs::read_to_string(workspace.join("notes.txt")).unwrap(),
        "patched\n"
    );
    let result = tool_result(&events);
    assert_eq!(result["ok"], true);
    assert_eq!(result["tool"], "apply_patch");
    assert_eq!(result["data"]["changed_files"][0]["path"], "notes.txt");
    remove_workspace(&workspace);
}

#[tokio::test]
async fn approval_required_blocks_tool_before_raw_arguments_event() {
    let workspace = test_workspace("approval-required");
    let skills = SkillRegistry::load_development(skills_root())
        .await
        .unwrap();
    let mut config = RuntimeConfig::workspace_write(workspace.clone(), workspace.clone());
    config.approval_policy = crate::policy::ApprovalPolicy::OnWorkspaceWrite;
    let runner = TurnRunner::new_with_config(
        FakePhaseTwoModel {
            calls: AtomicUsize::new(0),
            tool_name: "create_directory",
            arguments: serde_json::json!({ "path": "blocked-secret-path" }),
            requests: Mutex::new(Vec::new()),
        },
        skills,
        config,
    );

    let events = runner.run("create a directory").await.unwrap();

    assert!(!workspace.join("blocked-secret-path").exists());
    assert!(events.iter().any(|event| matches!(
        event,
        RuntimeEvent::ApprovalRequired { name, .. } if name == "create_directory"
    )));
    assert!(!events.iter().any(|event| matches!(
        event,
        RuntimeEvent::ToolCallStarted { arguments, .. }
            if arguments.to_string().contains("blocked-secret-path")
    )));
    let result = tool_result(&events);
    assert_eq!(result["ok"], false);
    assert_eq!(result["error"]["code"], "approval_required");
    remove_workspace(&workspace);
}

#[tokio::test]
async fn deferred_external_tools_are_not_sent_as_model_tool_schemas() {
    let workspace = test_workspace("deferred-tools-hidden");
    let skills = SkillRegistry::load_development(skills_root())
        .await
        .unwrap();
    let config = RuntimeConfig {
        external_tools: vec![crate::tools::discovery::ExternalToolConfig::mcp(
            "search",
            "expensive_lookup",
            "Search a remote corpus.",
            serde_json::json!({ "type": "object" }),
            crate::tools::discovery::ExternalToolVisibility::Deferred {
                summary: "Remote corpus lookup.".into(),
            },
        )],
        ..RuntimeConfig::workspace_write(workspace.clone(), workspace.clone())
    };
    let runner = TurnRunner::new_with_config(
        ScriptedModel {
            calls: AtomicUsize::new(0),
            requests: Mutex::new(Vec::new()),
            responses: vec![vec![
                GatewayEvent::TextDelta {
                    text: "done".into(),
                },
                GatewayEvent::Completed,
            ]],
        },
        skills,
        config,
    );

    let _events = runner.run("hello").await.unwrap();
    let requests = runner.model.requests.lock().unwrap();

    assert!(!request_has_tool(
        &requests[0],
        "mcp__search__expensive_lookup"
    ));
    remove_workspace(&workspace);
}

#[tokio::test]
async fn goal_context_is_injected_into_turn_input() {
    let workspace = test_workspace("goal-context");
    let skills = SkillRegistry::load_development(skills_root())
        .await
        .unwrap();
    let runner = TurnRunner::new_with_config(
        ScriptedModel {
            calls: AtomicUsize::new(0),
            requests: Mutex::new(Vec::new()),
            responses: vec![vec![GatewayEvent::Completed]],
        },
        skills,
        RuntimeConfig::workspace_write(workspace.clone(), workspace.clone()),
    );

    let request = crate::turn_request::TurnRequest::new("continue")
        .with_goal(crate::turn_request::TurnGoal::new("finish phase 7"));
    let _events = runner.run_request(request).await.unwrap();
    let requests = runner.model.requests.lock().unwrap();

    assert!(requests[0].input.iter().any(|item| {
        item["content"]
            .as_str()
            .unwrap_or_default()
            .contains("<active_goal>")
    }));
    remove_workspace(&workspace);
}

#[tokio::test]
async fn usage_budget_accumulates_gateway_usage_and_stops_turn() {
    let workspace = test_workspace("usage-budget");
    let skills = SkillRegistry::load_development(skills_root())
        .await
        .unwrap();
    let runner = TurnRunner::new_with_config(
        ScriptedModel {
            calls: AtomicUsize::new(0),
            requests: Mutex::new(Vec::new()),
            responses: vec![vec![
                GatewayEvent::Usage {
                    input_tokens: 6,
                    output_tokens: 5,
                },
                GatewayEvent::Completed,
            ]],
        },
        skills,
        RuntimeConfig::workspace_write(workspace.clone(), workspace.clone()),
    );

    let request = crate::turn_request::TurnRequest::new("hello").with_token_budget(10);
    let events = runner.run_request(request).await.unwrap();

    assert!(events.iter().any(|event| matches!(
        event,
        RuntimeEvent::UsageReported {
            total_tokens: 11,
            exceeded: true,
            ..
        }
    )));
    assert!(events.iter().any(|event| matches!(
        event,
        RuntimeEvent::TurnFailed { message, .. } if message.contains("token budget exceeded")
    )));
    remove_workspace(&workspace);
}

#[tokio::test]
async fn context_compaction_emits_event_when_budget_applies() {
    let workspace = test_workspace("context-compaction");
    let skills = SkillRegistry::load_development(skills_root())
        .await
        .unwrap();
    let runner = TurnRunner::new_with_config(
        ScriptedModel {
            calls: AtomicUsize::new(0),
            requests: Mutex::new(Vec::new()),
            responses: vec![vec![GatewayEvent::Completed]],
        },
        skills,
        RuntimeConfig::workspace_write(workspace.clone(), workspace.clone()),
    );

    let request = crate::turn_request::TurnRequest::new("hello").with_context_budget_bytes(64);
    let events = runner.run_request(request).await.unwrap();

    assert!(
        events
            .iter()
            .any(|event| matches!(event, RuntimeEvent::ContextCompacted { .. }))
    );
    remove_workspace(&workspace);
}

#[tokio::test]
async fn phase_three_injects_summary_and_triggered_skill_instruction() {
    let workspace = test_workspace("phase-three-skill-instructions");
    let skills_root = workspace.join("skills");
    fs::create_dir_all(skills_root.join("planning")).unwrap();
    fs::write(
        skills_root.join("planning").join("SKILL.md"),
        "---\nname: planning\ndescription: Write plans.\n---\n\n# Planning\nUse checklists.",
    )
    .unwrap();
    let catalog = crate::skill_catalog::SkillCatalog::load_development(&skills_root)
        .await
        .unwrap();
    let skills = SkillRegistry::load_development(&skills_root).await.unwrap();
    let config = RuntimeConfig::workspace_write(workspace.clone(), workspace.clone());
    let runner = TurnRunner::new_with_catalog_and_config(
        ScriptedModel {
            calls: AtomicUsize::new(0),
            requests: Mutex::new(Vec::new()),
            responses: vec![vec![
                GatewayEvent::TextDelta {
                    text: "done".into(),
                },
                GatewayEvent::Completed,
            ]],
        },
        skills,
        catalog,
        config,
    );

    let _events = runner.run("use $planning").await.unwrap();
    let requests = runner.model.requests.lock().unwrap();
    let developer = requests[0].input[1]["content"].as_str().unwrap();

    assert!(developer.contains("<available_skills count=\"1\">"));
    assert!(developer.contains("<skill_instructions name=\"planning\""));
    assert!(developer.contains("Use checklists."));
    remove_workspace(&workspace);
}

#[tokio::test]
async fn first_request_includes_instruction_context_and_tool_schemas() {
    let workspace = test_workspace("instructions");
    fs::write(
        workspace.join("AGENTS.md"),
        "Project instruction from AGENTS.md",
    )
    .unwrap();
    let skills = SkillRegistry::load_development(skills_root())
        .await
        .unwrap();
    let config = RuntimeConfig::workspace_write(workspace.clone(), workspace.clone());
    let runner = TurnRunner::new_with_config(
        ScriptedModel {
            calls: AtomicUsize::new(0),
            requests: Mutex::new(Vec::new()),
            responses: vec![vec![
                GatewayEvent::TextDelta {
                    text: "done".into(),
                },
                GatewayEvent::Completed,
            ]],
        },
        skills,
        config,
    );

    let _events = runner.run("hello").await.unwrap();
    let requests = runner.model.requests.lock().unwrap();
    let first = &requests[0];

    assert_eq!(first.input[0]["role"], "system");
    assert!(
        first.input[0]["content"]
            .as_str()
            .unwrap()
            .contains("AgentWeave is a Codex-like runtime")
    );
    assert_eq!(first.input[1]["role"], "developer");
    let developer = first.input[1]["content"].as_str().unwrap();
    assert!(developer.contains("Use tools for concrete workspace actions"));
    assert!(developer.contains("Project instruction from AGENTS.md"));
    assert_eq!(first.input[2]["role"], "user");
    assert!(
        first
            .tools
            .iter()
            .any(|tool| tool.advertised_name() == "create_directory")
    );
    assert!(
        first
            .tools
            .iter()
            .any(|tool| tool.advertised_name() == "echo")
    );
    remove_workspace(&workspace);
}

#[tokio::test]
async fn read_only_mode_denies_create_directory_and_does_not_create_folder() {
    let workspace = test_workspace("read-only");
    let skills = SkillRegistry::load_development(skills_root())
        .await
        .unwrap();
    let config = RuntimeConfig::read_only(workspace.clone(), workspace.clone());
    let runner = TurnRunner::new_with_config(
        ScriptedModel {
            calls: AtomicUsize::new(0),
            requests: Mutex::new(Vec::new()),
            responses: vec![
                vec![
                    GatewayEvent::ToolCall {
                        call_id: "call-denied".into(),
                        name: "create_directory".into(),
                        legacy_alias_selected: false,
                        arguments: serde_json::json!({ "path": "blocked" }),
                    },
                    GatewayEvent::Completed,
                ],
                vec![
                    GatewayEvent::TextDelta {
                        text: "denied".into(),
                    },
                    GatewayEvent::Completed,
                ],
            ],
        },
        skills,
        config,
    );

    let events = runner.run("try to create a directory").await.unwrap();

    assert!(!workspace.join("blocked").exists());
    let result = events
        .iter()
        .find_map(|event| match event {
            RuntimeEvent::ToolCallFinished {
                call_id, result, ..
            } if call_id == "call-denied" => Some(result),
            _ => None,
        })
        .unwrap();
    assert_eq!(result["ok"], false);
    assert_eq!(result["error"]["code"], "permission_denied");
    remove_workspace(&workspace);
}

#[tokio::test]
async fn runaway_tool_loop_stops_at_max_tool_calls_per_turn() {
    let workspace = test_workspace("max-tool-calls");
    let skills = SkillRegistry::load_development(skills_root())
        .await
        .unwrap();
    let mut config = RuntimeConfig::workspace_write(workspace.clone(), workspace.clone());
    config.max_tool_calls_per_turn = 2;
    let runner = TurnRunner::new_with_config(
        ScriptedModel {
            calls: AtomicUsize::new(0),
            requests: Mutex::new(Vec::new()),
            responses: vec![vec![
                GatewayEvent::ToolCall {
                    call_id: "call-loop".into(),
                    name: "echo".into(),
                    legacy_alias_selected: false,
                    arguments: serde_json::json!({ "text": "again" }),
                },
                GatewayEvent::Completed,
            ]],
        },
        skills,
        config,
    );

    let events = runner.run("loop forever").await.unwrap();

    let finished_tool_calls = events
        .iter()
        .filter(|event| matches!(event, RuntimeEvent::ToolCallFinished { .. }))
        .count();
    assert_eq!(finished_tool_calls, 2);
    assert!(events.iter().any(|event| matches!(
        event,
        RuntimeEvent::TurnFailed { message, .. } if message.contains("max tool calls exceeded")
    )));
    remove_workspace(&workspace);
}

struct SnapshotSwapModel {
    calls: AtomicUsize,
    manager: SkillManager,
    package_root: PathBuf,
    fail_reload: bool,
}

#[async_trait]
impl ModelClient for SnapshotSwapModel {
    async fn stream(&self, request: GatewayRequest) -> anyhow::Result<ModelEventStream> {
        let call = self.calls.fetch_add(1, Ordering::SeqCst);
        let events = match call {
            0 => {
                assert!(request_has_tool(&request, "first_tool"));
                if self.fail_reload {
                    tokio::fs::write(self.package_root.join("agentweave.json"), "{invalid").await?;
                    assert!(self.manager.reload().await.is_err());
                } else {
                    write_turn_runtime_package(&self.package_root, "second_tool").await;
                    self.manager.reload().await?;
                }
                vec![
                    GatewayEvent::ToolCall {
                        call_id: "call-first".into(),
                        name: "first_tool".into(),
                        legacy_alias_selected: false,
                        arguments: serde_json::json!({}),
                    },
                    GatewayEvent::Completed,
                ]
            }
            1 => vec![
                GatewayEvent::TextDelta {
                    text: "first turn done".into(),
                },
                GatewayEvent::Completed,
            ],
            2 => {
                assert!(request_has_tool(&request, "second_tool"));
                assert!(!request_has_tool(&request, "first_tool"));
                vec![
                    GatewayEvent::ToolCall {
                        call_id: "call-second".into(),
                        name: "second_tool".into(),
                        legacy_alias_selected: false,
                        arguments: serde_json::json!({}),
                    },
                    GatewayEvent::Completed,
                ]
            }
            _ => vec![
                GatewayEvent::TextDelta {
                    text: "second turn done".into(),
                },
                GatewayEvent::Completed,
            ],
        };
        Ok(Box::pin(stream::iter(events.into_iter().map(Ok))))
    }
}

#[tokio::test]
async fn turn_keeps_the_snapshot_captured_at_start() {
    let root = tempdir().unwrap();
    let package_root = root.path().join("runtime");
    write_turn_runtime_package(&package_root, "first_tool").await;
    let manager = turn_skill_manager(root.path()).await;
    let workspace = test_workspace("snapshot-swap");
    let runner = TurnRunner::new_with_manager_and_config(
        SnapshotSwapModel {
            calls: AtomicUsize::new(0),
            manager: manager.clone(),
            package_root,
            fail_reload: false,
        },
        manager.clone(),
        RuntimeConfig::workspace_write(workspace.clone(), workspace.clone()),
    );

    let events = runner.run("use the tool").await.unwrap();

    assert!(events.iter().any(|event| matches!(
        event,
        RuntimeEvent::ToolCallStarted { name, .. } if name == "first_tool"
    )));
    assert!(!events.iter().any(|event| matches!(
        event,
        RuntimeEvent::ToolCallStarted { name, .. } if name == "second_tool"
    )));
    assert!(events.iter().any(|event| matches!(
        event,
        RuntimeEvent::ToolCallFinished { result, .. }
            if result["ok"] == true && result["tool"] == "first_tool"
    )));
    assert_eq!(manager.current_snapshot().generation(), 2);
    remove_workspace(&workspace);
}

async fn turn_skill_manager(root: &Path) -> SkillManager {
    SkillManager::new(SkillManagerConfig {
        sources: vec![Arc::new(DirectorySkillSource::new(
            SkillLayer::Builtin,
            root,
        ))],
        platform: PlatformId::Desktop,
        capabilities: CapabilitySet::desktop_runtime(),
        protected_packages: Vec::new(),
        allowed_overrides: Vec::new(),
        runtime_version: Version::new(0, 1, 0),
    })
    .await
    .unwrap()
}

async fn write_turn_runtime_package(package_root: &Path, tool_name: &str) {
    tokio::fs::create_dir_all(package_root).await.unwrap();
    tokio::fs::write(
        package_root.join("agentweave.json"),
        serde_json::json!({
            "schemaVersion": 1,
            "id": "com.example.turn-runtime",
            "version": "1.0.0",
            "displayName": "Turn runtime",
            "kind": "native_runtime",
            "package": {
                "includeInstructions": false,
                "includeRuntime": true
            }
        })
        .to_string(),
    )
    .await
    .unwrap();
    tokio::fs::write(
        package_root.join("skill.json"),
        serde_json::json!({
            "name": "turn-runtime",
            "description": "Runtime used by turn snapshot tests.",
            "version": "1.0.0",
            "entry": {
                "type": "command",
                "command": "node",
                "args": ["index.js"]
            },
            "tools": [{
                "name": tool_name,
                "description": "Test tool.",
                "input_schema": { "type": "object" }
            }]
        })
        .to_string(),
    )
    .await
    .unwrap();
    tokio::fs::write(
        package_root.join("index.js"),
        "process.stdin.resume();\nprocess.stdin.on('end', () => process.stdout.write(JSON.stringify({ tool: process.env.AGENTWEAVE_TOOL_NAME })));\n",
    )
    .await
    .unwrap();
}

#[path = "turn_snapshot_followup_tests.rs"]
mod snapshot_followup_tests;

#[path = "turn_persistence_tests.rs"]
mod persistence_tests;
