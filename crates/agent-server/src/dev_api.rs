use agent_runtime::{
    instructions::{InstructionConfig, InstructionContext},
    prompt_composer::PromptCompositionDiagnostics,
    tools::{
        discovery::{ConnectorMetadata, ToolDiscoveryItem},
        schema::ToolDiagnostic,
    },
};
use axum::{
    Json, Router,
    extract::{Path, State},
    http::StatusCode,
    routing::{get, post},
};
use serde::{Deserialize, Serialize};
use std::sync::Arc;

use crate::api::AppState;
use crate::dev_skill_authoring::{
    DevSkillCreateRequest, DevSkillDeleteRequest, DevSkillMutationResponse, DevSkillSource,
    DevSkillUpdateRequest,
};
use crate::dev_skills::DevSkillInventory;

#[derive(Debug, Serialize)]
struct DevToolsResponse {
    tools: Vec<ToolDiagnostic>,
}

#[derive(Debug, Serialize)]
struct DevToolDiscoveryResponse {
    tools: Vec<ToolDiscoveryItem>,
    connectors: Vec<ConnectorMetadata>,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
struct InstructionsPreviewRequest {
    content: String,
}

#[derive(Debug, Serialize)]
struct InstructionsPreviewResponse {
    system: String,
    developer: String,
    user: String,
    triggered_skills: Vec<String>,
    diagnostics: PromptCompositionDiagnostics,
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
struct DevSkillReloadResponse {
    inventory: DevSkillInventory,
    previous_generation: u64,
    active_generation: u64,
    active_packages: usize,
    inactive_packages: usize,
    reload_status: &'static str,
}

pub(crate) fn routes() -> Router<Arc<AppState>> {
    Router::new()
        .route("/dev/tools", get(list_tools))
        .route("/dev/tool-discovery", get(discover_tools))
        .route("/dev/instructions/preview", post(preview_instructions))
        .route("/dev/skills", get(list_skills).post(create_skill))
        .route("/dev/skills/validate", post(validate_skills))
        .route("/dev/skills/reload", post(reload_skills))
        .route(
            "/dev/skills/{skill_id}",
            get(read_skill).put(update_skill).delete(delete_skill),
        )
}

async fn list_tools(
    State(state): State<Arc<AppState>>,
) -> Result<Json<DevToolsResponse>, StatusCode> {
    let registry = state
        .configured_tool_registry()
        .map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?;

    Ok(Json(DevToolsResponse {
        tools: registry.diagnostics(),
    }))
}

async fn discover_tools(
    State(state): State<Arc<AppState>>,
) -> Result<Json<DevToolDiscoveryResponse>, StatusCode> {
    let registry = state
        .configured_tool_registry()
        .map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?;
    let discovery = registry.discovery();

    Ok(Json(DevToolDiscoveryResponse {
        tools: discovery.tools,
        connectors: discovery.connectors,
    }))
}

async fn preview_instructions(
    State(state): State<Arc<AppState>>,
    Json(request): Json<InstructionsPreviewRequest>,
) -> Result<Json<InstructionsPreviewResponse>, StatusCode> {
    let runtime_config = state.runtime_config();
    let skill_catalog = state.skill_catalog();
    let triggered_skills = skill_catalog.triggered_skill_names(&request.content);
    let mut instruction_config =
        InstructionConfig::new(runtime_config.workspace_root, runtime_config.cwd);
    instruction_config.app_prompt = state.app_prompt().clone();
    instruction_config.skill_summaries = skill_catalog.summaries().to_vec();
    if let Some(memory) = state.memory_tools()
        && let Ok(records) = memory.recall_for_turn(&request.content, 8).await
        && !records.is_empty()
    {
        instruction_config.memory_context = Some(
            agent_runtime::memory_tools::MemoryToolRuntime::render_recall_context(&records)
                .map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?,
        );
    }
    if !triggered_skills.is_empty() {
        instruction_config.skill_instructions = skill_catalog
            .load_instruction_documents(&triggered_skills, runtime_config.output_limit_bytes)
            .await
            .map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?;
    }

    let context =
        InstructionContext::load(instruction_config).map_err(|_| StatusCode::BAD_REQUEST)?;
    let composition = context
        .try_model_input(&request.content, &[])
        .map_err(|_| StatusCode::BAD_REQUEST)?;
    let input = composition.input;

    Ok(Json(InstructionsPreviewResponse {
        system: input_content(&input, 0),
        developer: input_content(&input, 1),
        user: input_content(&input, 2),
        triggered_skills,
        diagnostics: composition.diagnostics,
    }))
}

fn input_content(input: &[serde_json::Value], index: usize) -> String {
    input
        .get(index)
        .and_then(|item| item.get("content"))
        .and_then(serde_json::Value::as_str)
        .unwrap_or_default()
        .to_string()
}

async fn list_skills(
    State(state): State<Arc<AppState>>,
) -> Result<Json<DevSkillInventory>, StatusCode> {
    let _guard = state.dev_skill_mutations().lock().await;
    let root = state.skills_root().ok_or(StatusCode::NOT_FOUND)?;
    crate::dev_skills::scan_skill_packages(root)
        .await
        .map(Json)
        .map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)
}

async fn validate_skills(
    State(state): State<Arc<AppState>>,
) -> Result<Json<DevSkillInventory>, StatusCode> {
    list_skills(State(state)).await
}

async fn reload_skills(
    State(state): State<Arc<AppState>>,
) -> Result<Json<DevSkillReloadResponse>, StatusCode> {
    let _guard = state.dev_skill_mutations().lock().await;
    let root = state
        .skills_root()
        .ok_or(StatusCode::UNPROCESSABLE_ENTITY)?;
    let metadata = tokio::fs::metadata(&root)
        .await
        .map_err(|_| StatusCode::UNPROCESSABLE_ENTITY)?;
    if !metadata.is_dir() {
        return Err(StatusCode::UNPROCESSABLE_ENTITY);
    }

    let manager = state.skill_manager();
    let (report, inventory) = manager
        .reload_with_pre_publish(
            |_| async move { crate::dev_skills::scan_skill_packages(root).await },
        )
        .await
        .map_err(|_| StatusCode::UNPROCESSABLE_ENTITY)?;

    Ok(Json(DevSkillReloadResponse {
        inventory,
        previous_generation: report.previous_generation,
        active_generation: report.active_generation,
        active_packages: report.active_packages,
        inactive_packages: report.inactive_packages,
        reload_status: "published",
    }))
}

async fn read_skill(
    Path(skill_id): Path<String>,
    State(state): State<Arc<AppState>>,
) -> Result<Json<DevSkillSource>, StatusCode> {
    let _guard = state.dev_skill_mutations().lock().await;
    let root = state.skills_root().ok_or(StatusCode::NOT_FOUND)?;
    crate::dev_skill_authoring::read_skill_source(&root, &skill_id)
        .await
        .map(Json)
        .map_err(dev_skill_authoring_status)
}

async fn create_skill(
    State(state): State<Arc<AppState>>,
    Json(request): Json<DevSkillCreateRequest>,
) -> Result<(StatusCode, Json<DevSkillMutationResponse>), StatusCode> {
    let _guard = state.dev_skill_mutations().lock().await;
    let root = state
        .skills_root()
        .ok_or(StatusCode::UNPROCESSABLE_ENTITY)?;
    crate::dev_skill_authoring::create_skill(&root, request)
        .await
        .map(|response| (StatusCode::CREATED, Json(response)))
        .map_err(dev_skill_authoring_status)
}

async fn update_skill(
    Path(skill_id): Path<String>,
    State(state): State<Arc<AppState>>,
    Json(request): Json<DevSkillUpdateRequest>,
) -> Result<Json<DevSkillMutationResponse>, StatusCode> {
    let _guard = state.dev_skill_mutations().lock().await;
    let root = state
        .skills_root()
        .ok_or(StatusCode::UNPROCESSABLE_ENTITY)?;
    crate::dev_skill_authoring::update_skill(&root, &skill_id, request)
        .await
        .map(Json)
        .map_err(dev_skill_authoring_status)
}

async fn delete_skill(
    Path(skill_id): Path<String>,
    State(state): State<Arc<AppState>>,
    Json(request): Json<DevSkillDeleteRequest>,
) -> Result<Json<DevSkillInventory>, StatusCode> {
    let _guard = state.dev_skill_mutations().lock().await;
    let root = state.skills_root().ok_or(StatusCode::NOT_FOUND)?;
    crate::dev_skill_authoring::delete_skill(&root, &skill_id, request)
        .await
        .map(Json)
        .map_err(dev_skill_authoring_status)
}

fn dev_skill_authoring_status(error: anyhow::Error) -> StatusCode {
    let message = error.to_string();
    if message.contains("revision conflict")
        || message.contains("changed during update")
        || message.contains("already exists")
    {
        StatusCode::CONFLICT
    } else if message.contains("not found") || message.contains("unavailable") {
        StatusCode::NOT_FOUND
    } else if message.contains("supports instruction-only")
        || message.contains("read-only")
        || message.contains("inventory validation failed")
    {
        StatusCode::UNPROCESSABLE_ENTITY
    } else if message.contains("invalid")
        || message.contains("unsafe")
        || message.contains("symbolic")
        || message.contains("must")
        || message.contains("too large")
    {
        StatusCode::BAD_REQUEST
    } else {
        StatusCode::INTERNAL_SERVER_ERROR
    }
}

#[cfg(test)]
#[path = "dev_api_tests.rs"]
mod tests;

#[cfg(test)]
#[path = "dev_api_mutation_tests.rs"]
mod mutation_tests;
