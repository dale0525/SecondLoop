use crate::{MobileInitConfig, MobileModelConfigDto, MobileRuntime};
use agent_runtime::skill_management::{CreateSkillDraftRequest, DraftFileUpdate};
use serde::{Deserialize, Serialize};
use serde_json::{Value, json};
use std::collections::HashMap;
use std::sync::atomic::{AtomicI64, Ordering};
use std::sync::{Arc, Mutex, OnceLock};

static NEXT_HANDLE: AtomicI64 = AtomicI64::new(1);
static RUNTIMES: OnceLock<Mutex<HashMap<i64, Arc<MobileRuntime>>>> = OnceLock::new();

#[derive(Debug, Deserialize)]
#[serde(tag = "operation", rename_all = "snake_case", deny_unknown_fields)]
enum RuntimeRequest {
    Diagnostics,
    ListSkills,
    ListManagedSkills,
    GetSkillDetail {
        package_id: String,
    },
    CreateSkillDraft {
        request: CreateSkillDraftRequest,
        #[serde(default)]
        files: Vec<DraftFileUpdate>,
    },
    UpdateSkillDraft {
        revision_id: String,
        files: Vec<DraftFileUpdate>,
    },
    ValidateSkillDraft {
        revision_id: String,
    },
    RequestSkillActivation {
        revision_id: String,
    },
    ResolveSkillApproval {
        approval_id: String,
        approve: bool,
    },
    DisableManagedSkill {
        package_id: String,
    },
    RollbackManagedSkill {
        package_id: String,
        revision_id: String,
    },
    RequestSkillRemoval {
        package_id: String,
    },
    SynchronizeSkills,
    CreateSession {
        title: String,
    },
    ListSessions,
    GetMessages {
        session_id: String,
    },
    DeleteSession {
        session_id: String,
    },
    SaveModelConfig {
        config: MobileModelConfigDto,
    },
    LoadModelConfig,
    RefreshSecurityContext {
        security_context: agent_runtime::identity::SecurityContext,
    },
    ListMemories {
        #[serde(default)]
        query: String,
        #[serde(default = "default_memory_limit")]
        limit: usize,
    },
    ForgetMemory {
        memory_id: String,
        expected_version: u64,
    },
    ExportMemories,
    ListMailAccounts,
    MailAccountStatus {
        account_id: String,
    },
    ConnectMailAccount {
        account_id: String,
    },
    DisconnectMailAccount {
        account_id: String,
    },
    ListFoundationActions,
    ResolveFoundationAction {
        approval_id: String,
        decision: agent_runtime::approval::ApprovalDecision,
    },
    CreateScheduledJob {
        request: agent_runtime::scheduler::ScheduledJobRequest,
    },
    RunSchedulerTick {
        #[serde(default = "default_automation_limit")]
        limit: usize,
    },
    ClaimNotifications {
        worker: String,
        #[serde(default = "default_automation_limit")]
        limit: usize,
    },
    FinishNotification {
        notification_id: String,
        worker: String,
        outcome: agent_runtime::automation::NotificationDeliveryOutcome,
    },
}

#[derive(Debug, Deserialize)]
#[serde(deny_unknown_fields)]
struct SendMessageRequest {
    session_id: String,
    content: String,
}

#[derive(Serialize)]
struct BridgeError {
    code: &'static str,
    message: String,
}

pub fn initialize_runtime_json(request_json: &str) -> String {
    let result = (|| {
        let config: MobileInitConfig = serde_json::from_str(request_json)?;
        let runtime = MobileRuntime::initialize(config)?;
        let handle = NEXT_HANDLE.fetch_add(1, Ordering::Relaxed);
        runtimes()
            .lock()
            .map_err(|_| anyhow::anyhow!("runtime registry is unavailable"))?
            .insert(handle, Arc::new(runtime));
        Ok(json!({"handle": handle}))
    })();
    bridge_result(result)
}

pub fn invoke_runtime_json(handle: i64, request_json: &str) -> String {
    let result = (|| {
        let request = parse_runtime_request(request_json)?;
        let runtime = runtime(handle)?;
        match request {
            RuntimeRequest::Diagnostics => serde_json::to_value(runtime.diagnostics()?),
            RuntimeRequest::ListSkills => serde_json::to_value(runtime.list_skills()?),
            RuntimeRequest::ListManagedSkills => {
                serde_json::to_value(runtime.list_managed_skills()?)
            }
            RuntimeRequest::GetSkillDetail { package_id } => {
                serde_json::to_value(runtime.get_skill_detail(&package_id)?)
            }
            RuntimeRequest::CreateSkillDraft { request, files } => {
                serde_json::to_value(runtime.create_skill_draft_with_files(request, files)?)
            }
            RuntimeRequest::UpdateSkillDraft { revision_id, files } => {
                serde_json::to_value(runtime.update_skill_draft(&revision_id, files)?)
            }
            RuntimeRequest::ValidateSkillDraft { revision_id } => {
                serde_json::to_value(runtime.validate_skill_draft(&revision_id)?)
            }
            RuntimeRequest::RequestSkillActivation { revision_id } => {
                serde_json::to_value(runtime.request_skill_activation(&revision_id)?)
            }
            RuntimeRequest::ResolveSkillApproval {
                approval_id,
                approve,
            } => Ok(runtime.resolve_skill_approval(&approval_id, approve)?),
            RuntimeRequest::DisableManagedSkill { package_id } => {
                Ok(runtime.disable_managed_skill(&package_id)?)
            }
            RuntimeRequest::RollbackManagedSkill {
                package_id,
                revision_id,
            } => Ok(runtime.rollback_managed_skill(&package_id, &revision_id)?),
            RuntimeRequest::RequestSkillRemoval { package_id } => {
                serde_json::to_value(runtime.request_skill_removal(&package_id)?)
            }
            RuntimeRequest::SynchronizeSkills => {
                serde_json::to_value(runtime.synchronize_skills()?)
            }
            RuntimeRequest::CreateSession { title } => {
                serde_json::to_value(runtime.create_session(&title)?)
            }
            RuntimeRequest::ListSessions => serde_json::to_value(runtime.list_sessions()?),
            RuntimeRequest::GetMessages { session_id } => {
                serde_json::to_value(runtime.get_messages(&session_id)?)
            }
            RuntimeRequest::DeleteSession { session_id } => {
                runtime.delete_session(&session_id)?;
                Ok(Value::Null)
            }
            RuntimeRequest::SaveModelConfig { config } => {
                runtime.save_model_config(config)?;
                Ok(Value::Null)
            }
            RuntimeRequest::LoadModelConfig => serde_json::to_value(runtime.load_model_config()?),
            RuntimeRequest::RefreshSecurityContext { security_context } => {
                runtime.refresh_security_context(security_context)?;
                Ok(Value::Null)
            }
            RuntimeRequest::ListMemories { query, limit } => {
                Ok(runtime.list_memories(&query, limit)?)
            }
            RuntimeRequest::ForgetMemory {
                memory_id,
                expected_version,
            } => Ok(runtime.forget_memory(&memory_id, expected_version)?),
            RuntimeRequest::ExportMemories => Ok(runtime.export_memories()?),
            RuntimeRequest::ListMailAccounts => Ok(runtime.list_mail_accounts()?),
            RuntimeRequest::MailAccountStatus { account_id } => {
                Ok(runtime.mail_account_status(&account_id)?)
            }
            RuntimeRequest::ConnectMailAccount { account_id } => {
                Ok(runtime.connect_mail_account(&account_id)?)
            }
            RuntimeRequest::DisconnectMailAccount { account_id } => {
                Ok(runtime.disconnect_mail_account(&account_id)?)
            }
            RuntimeRequest::ListFoundationActions => {
                serde_json::to_value(runtime.list_foundation_actions()?)
            }
            RuntimeRequest::ResolveFoundationAction {
                approval_id,
                decision,
            } => serde_json::to_value(runtime.resolve_foundation_action(&approval_id, decision)?),
            RuntimeRequest::CreateScheduledJob { request } => {
                serde_json::to_value(runtime.create_scheduled_job(request)?)
            }
            RuntimeRequest::RunSchedulerTick { limit } => {
                serde_json::to_value(runtime.run_scheduler_tick(limit)?)
            }
            RuntimeRequest::ClaimNotifications { worker, limit } => {
                serde_json::to_value(runtime.claim_notifications(&worker, limit)?)
            }
            RuntimeRequest::FinishNotification {
                notification_id,
                worker,
                outcome,
            } => serde_json::to_value(runtime.finish_notification(
                &notification_id,
                &worker,
                outcome,
            )?),
        }
        .map_err(Into::into)
    })();
    bridge_result(result)
}

fn default_memory_limit() -> usize {
    50
}

fn default_automation_limit() -> usize {
    25
}

fn parse_runtime_request(request_json: &str) -> anyhow::Result<RuntimeRequest> {
    let value: Value = serde_json::from_str(request_json)?;
    let object = value
        .as_object()
        .ok_or_else(|| anyhow::anyhow!("runtime request must be a JSON object"))?;
    if object.keys().any(|key| {
        matches!(
            key.as_str(),
            "actor" | "actor_context" | "actorContext" | "principal"
        )
    }) {
        anyhow::bail!("runtime request actor is established during initialization");
    }
    serde_json::from_value(value).map_err(Into::into)
}

pub fn send_message_json(handle: i64, request_json: &str, api_key: Option<String>) -> String {
    let result = (|| {
        let request: SendMessageRequest = serde_json::from_str(request_json)?;
        let runtime = runtime(handle)?;
        serde_json::to_value(runtime.send_message(
            &request.session_id,
            &request.content,
            api_key,
        )?)
        .map_err(Into::into)
    })();
    bridge_result(result)
}

pub fn close_runtime(handle: i64) -> String {
    let result = (|| {
        let removed = runtimes()
            .lock()
            .map_err(|_| anyhow::anyhow!("runtime registry is unavailable"))?
            .remove(&handle);
        let runtime = removed.ok_or_else(|| anyhow::anyhow!("runtime handle not found"))?;
        runtime.close();
        Ok(Value::Null)
    })();
    bridge_result(result)
}

fn runtime(handle: i64) -> anyhow::Result<Arc<MobileRuntime>> {
    runtimes()
        .lock()
        .map_err(|_| anyhow::anyhow!("runtime registry is unavailable"))?
        .get(&handle)
        .cloned()
        .ok_or_else(|| anyhow::anyhow!("runtime handle not found"))
}

fn runtimes() -> &'static Mutex<HashMap<i64, Arc<MobileRuntime>>> {
    RUNTIMES.get_or_init(|| Mutex::new(HashMap::new()))
}

fn bridge_result(result: anyhow::Result<Value>) -> String {
    match result {
        Ok(data) => json!({"ok": true, "data": data}).to_string(),
        Err(error) => json!({
            "ok": false,
            "error": BridgeError {
                code: "runtime_error",
                message: error.to_string(),
            }
        })
        .to_string(),
    }
}
