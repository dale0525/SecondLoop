use std::collections::BTreeSet;
use std::fs;
use std::path::{Path, PathBuf};
use std::time::Duration;

use anyhow::{anyhow, Result};
use rusqlite::{params, Connection, OptionalExtension};
use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};
use zerocopy::IntoBytes;

use crate::crypto::{decrypt_bytes, encrypt_bytes};
use crate::embedding::Embedder;
use crate::vector;

const DEFAULT_EMBEDDING_DIM: usize = crate::embedding::DEFAULT_EMBED_DIM;
const LOOP_HOME_CONVERSATION_ID: &str = "loop_home";
const KV_ACTIVE_EMBEDDING_MODEL_NAME: &str = "embedding.active_model_name";
const KV_ACTIVE_EMBEDDING_DIM: &str = "embedding.active_dim";
const KV_CLOUD_GATEWAY_EMBEDDINGS_CACHE_BASE_URL: &str = "embedding.cloud_gateway.embeddings.base_url";
const KV_CLOUD_GATEWAY_EMBEDDINGS_CACHE_REQUESTED_MODEL_NAME: &str =
    "embedding.cloud_gateway.embeddings.requested_model_name";
const KV_CLOUD_GATEWAY_EMBEDDINGS_CACHE_MODEL_ID: &str = "embedding.cloud_gateway.embeddings.model_id";
const KV_CLOUD_GATEWAY_EMBEDDINGS_CACHE_DIM: &str = "embedding.cloud_gateway.embeddings.dim";

fn normalize_todo_followup_task_type_hint(task_type_hint: Option<&str>) -> Option<&str> {
    task_type_hint.map(str::trim).filter(|value| !value.is_empty())
}

fn resolved_todo_followup_task_type_hint(task_type_hint: Option<&str>) -> Option<&'static str> {
    match normalize_todo_followup_task_type_hint(task_type_hint) {
        Some(value) if value.eq_ignore_ascii_case("research") => Some("research"),
        Some(value) if value.eq_ignore_ascii_case("comparison") => Some("comparison"),
        Some(value) if value.eq_ignore_ascii_case("live_info_lookup") => Some("live_info_lookup"),
        Some(value) if value.eq_ignore_ascii_case("reference_collection") => Some("reference_collection"),
        Some(value) if value.eq_ignore_ascii_case("execution") => Some("execution"),
        Some(value) if value.eq_ignore_ascii_case("coordination") => Some("coordination"),
        Some(value) if value.eq_ignore_ascii_case("planning") => Some("planning"),
        Some(value) if value.eq_ignore_ascii_case("unknown") => None,
        Some(_) | None => None,
    }
}

fn todo_followup_task_type_allows_auto_followup(title: &str, task_type_hint: Option<&str>) -> bool {
    match resolved_todo_followup_task_type_hint(task_type_hint) {
        Some("research")
        | Some("comparison")
        | Some("live_info_lookup")
        | Some("reference_collection") => true,
        Some("execution") | Some("coordination") | Some("planning") => false,
        Some(_) | None => classify_todo_followup_task_type_for_create(title),
    }
}

fn classify_todo_followup_task_type_for_create(title: &str) -> bool {
    let normalized = title.trim().to_lowercase();
    if normalized.is_empty() {
        return false;
    }

    if contains_any(
        &normalized,
        &["对比", "比较", "选型", "benchmark", "compare", "comparison"],
    ) {
        return true;
    }

    if contains_any(
        &normalized,
        &[
            "收集资料",
            "搜集资料",
            "参考资料",
            "资料收集",
            "官网链接",
            "材料要求",
            "资料要求",
        ],
    ) || contains_in_order(&normalized, "收集", "链接")
        || contains_in_order(&normalized, "collect", "link")
    {
        return true;
    }

    if contains_any(
        &normalized,
        &[
            "机场",
            "航班",
            "航站楼",
            "到达时间",
            "停车",
            "入园时间",
            "检票入口",
            "接机",
            "车次",
            "高铁",
            "火车",
            "terminal",
            "arrival",
            "parking",
        ],
    ) {
        return true;
    }

    if contains_any(
        &normalized,
        &["调研", "研究", "分析", "了解", "盘点", "survey", "research", "investigate"],
    ) {
        return true;
    }

    if contains_any(&normalized, &["开会", "约时间", "沟通", "联系", "同步", "coordinate", "meeting"]) {
        return false;
    }

    if contains_any(&normalized, &["计划", "安排", "规划", "roadmap", "plan"]) {
        return false;
    }

    if contains_any(&normalized, &["修复", "修一下", "修理", "提交", "发送", "付款", "上线", "实现", "fix", "ship", "submit", "pay"]) {
        return false;
    }

    false
}

fn contains_any(haystack: &str, needles: &[&str]) -> bool {
    needles.iter().any(|needle| haystack.contains(needle))
}

fn contains_in_order(haystack: &str, first: &str, second: &str) -> bool {
    let Some(index) = haystack.find(first) else {
        return false;
    };
    haystack[index + first.len()..].contains(second)
}

#[derive(Clone, Debug)]
pub struct CloudGatewayEmbeddingsCache {
    pub base_url: String,
    pub requested_model_name: String,
    pub effective_model_id: String,
    pub dim: usize,
}

#[derive(Clone, Debug)]
pub struct Conversation {
    pub id: String,
    pub title: String,
    pub created_at_ms: i64,
    pub updated_at_ms: i64,
}

#[derive(Clone, Debug)]
pub struct Message {
    pub id: String,
    pub conversation_id: String,
    pub role: String,
    pub content: String,
    pub created_at_ms: i64,
    pub is_memory: bool,
    pub citations_json: Option<String>,
}

#[derive(Clone, Debug)]
pub struct Tag {
    pub id: String,
    pub name: String,
    pub system_key: Option<String>,
    pub is_system: bool,
    pub color: Option<String>,
    pub created_at_ms: i64,
    pub updated_at_ms: i64,
}

#[derive(Clone, Debug)]
pub struct TagMergeSuggestion {
    pub source_tag: Tag,
    pub target_tag: Tag,
    pub reason: String,
    pub score: f64,
    pub source_usage_count: i64,
    pub target_usage_count: i64,
}

#[derive(Clone, Debug)]
pub struct SimilarMessage {
    pub message: Message,
    pub distance: f64,
}

#[derive(Clone, Debug)]
pub struct SimilarTodoThread {
    pub todo_id: String,
    pub distance: f64,
}

#[derive(Clone, Debug)]
pub struct AttachmentTextChunk {
    pub attachment_sha256: String,
    pub kind: String,
    pub chunk_index: i64,
    pub start_offset: i64,
    pub end_offset: i64,
    pub text_len: i64,
    pub created_at_ms: i64,
    pub updated_at_ms: i64,
}

#[derive(Clone, Debug)]
pub struct SimilarAttachmentChunk {
    pub attachment_sha256: String,
    pub kind: String,
    pub chunk_index: i64,
    pub distance: f64,
    pub snippet: String,
}

#[derive(Clone, Debug)]
pub struct LlmUsageAggregate {
    pub purpose: String,
    pub requests: i64,
    pub requests_with_usage: i64,
    pub input_tokens: i64,
    pub output_tokens: i64,
    pub total_tokens: i64,
}

#[derive(Clone, Debug)]
pub struct LlmProfile {
    pub id: String,
    pub name: String,
    pub provider_type: String,
    pub base_url: Option<String>,
    pub model_name: String,
    pub is_active: bool,
    pub created_at_ms: i64,
    pub updated_at_ms: i64,
}

#[derive(Clone, Debug)]
pub struct LlmProfileConfig {
    pub provider_type: String,
    pub base_url: Option<String>,
    pub api_key: Option<String>,
    pub model_name: String,
}

#[derive(Clone, Debug)]
pub struct EmbeddingProfile {
    pub id: String,
    pub name: String,
    pub provider_type: String,
    pub base_url: Option<String>,
    pub model_name: String,
    pub is_active: bool,
    pub created_at_ms: i64,
    pub updated_at_ms: i64,
}

#[derive(Clone, Debug)]
pub struct EmbeddingProfileConfig {
    pub provider_type: String,
    pub base_url: Option<String>,
    pub api_key: Option<String>,
    pub model_name: String,
}

#[derive(Clone, Debug)]
pub struct EmbeddingArtifactManifest {
    pub artifact_id: String,
    pub source_kind: String,
    pub source_id: String,
    pub source_revision: i64,
    pub chunk_hash: String,
    pub chunk_ordinal: i64,
    pub profile_id: String,
    pub producer_device_id: Option<String>,
    pub producer_class: String,
    pub quality_tier: String,
    pub vector_format: String,
    pub dimension: i64,
    pub blob_ref: String,
    pub status: String,
    pub supersedes_artifact_id: Option<String>,
    pub created_at_ms: i64,
    pub updated_at_ms: i64,
}

#[derive(Clone, Debug)]
pub struct EmbeddingArtifactManifestInput<'a> {
    pub source_kind: &'a str,
    pub source_id: &'a str,
    pub source_revision: i64,
    pub chunk_hash: &'a str,
    pub chunk_ordinal: i64,
    pub profile_id: &'a str,
    pub producer_device_id: Option<&'a str>,
    pub producer_class: &'a str,
    pub quality_tier: &'a str,
    pub vector_format: &'a str,
    pub dimension: i64,
    pub blob_ref: &'a str,
    pub created_at_ms: Option<i64>,
}

#[derive(Clone, Debug)]
pub struct Attachment {
    pub sha256: String,
    pub mime_type: String,
    pub path: String,
    pub byte_len: i64,
    pub created_at_ms: i64,
}

#[derive(Clone, Debug)]
pub struct AttachmentVariant {
    pub attachment_sha256: String,
    pub variant: String,
    pub mime_type: String,
    pub path: String,
    pub byte_len: i64,
    pub created_at_ms: i64,
}

#[derive(Clone, Debug)]
pub struct AttachmentDerivation {
    pub root_sha256: String,
    pub child_sha256: String,
    pub role: String,
    pub created_at_ms: i64,
}

#[derive(Clone, Debug, Deserialize, Serialize)]
pub struct AttachmentExifMetadata {
    pub captured_at_ms: Option<i64>,
    pub latitude: Option<f64>,
    pub longitude: Option<f64>,
}

#[derive(Clone, Debug)]
pub struct AttachmentPlaceJob {
    pub attachment_sha256: String,
    pub status: String,
    pub lang: String,
    pub attempts: i64,
    pub next_retry_at_ms: Option<i64>,
    pub last_error: Option<String>,
    pub created_at_ms: i64,
    pub updated_at_ms: i64,
}

#[derive(Clone, Debug)]
pub struct AttachmentAnnotationJob {
    pub attachment_sha256: String,
    pub status: String,
    pub lang: String,
    pub model_name: Option<String>,
    pub attempts: i64,
    pub next_retry_at_ms: Option<i64>,
    pub last_error: Option<String>,
    pub created_at_ms: i64,
    pub updated_at_ms: i64,
}

#[derive(Clone, Debug)]
pub struct SemanticParseJob {
    pub message_id: String,
    pub status: String,
    pub attempt_id: i64,
    pub attempts: i64,
    pub next_retry_at_ms: Option<i64>,
    pub last_error: Option<String>,
    pub applied_action_kind: Option<String>,
    pub applied_todo_id: Option<String>,
    pub applied_todo_title: Option<String>,
    pub applied_prev_todo_status: Option<String>,
    pub suggested_tags: Option<Vec<String>>,
    pub suggested_tag_confidence: Option<f64>,
    pub tag_suggestion_state: Option<String>,
    pub applied_tag_ids: Option<Vec<String>>,
    pub undone_at_ms: Option<i64>,
    pub created_at_ms: i64,
    pub updated_at_ms: i64,
}

#[derive(Clone, Debug)]
pub struct CloudMediaBackup {
    pub attachment_sha256: String,
    pub desired_variant: String,
    pub byte_len: i64,
    pub status: String,
    pub attempts: i64,
    pub next_retry_at_ms: Option<i64>,
    pub last_error: Option<String>,
    pub updated_at_ms: i64,
}

#[derive(Clone, Debug)]
pub struct CloudMediaBackupSummary {
    pub pending: i64,
    pub failed: i64,
    pub uploaded: i64,
    pub last_uploaded_at_ms: Option<i64>,
    pub last_error: Option<String>,
    pub last_error_at_ms: Option<i64>,
}

#[derive(Clone, Debug)]
pub struct Todo {
    pub id: String,
    pub title: String,
    pub due_at_ms: Option<i64>,
    pub status: String,
    pub source_entry_id: Option<String>,
    pub created_at_ms: i64,
    pub updated_at_ms: i64,
    pub review_stage: Option<i64>,
    pub next_review_at_ms: Option<i64>,
    pub last_review_at_ms: Option<i64>,
    pub manual_importance_nudge_score: Option<i64>,
    pub manual_urgency_nudge_score: Option<i64>,
}

#[derive(Clone, Debug)]
pub struct TodoActivity {
    pub id: String,
    pub todo_id: String,
    pub activity_type: String,
    pub from_status: Option<String>,
    pub to_status: Option<String>,
    pub content: Option<String>,
    pub source_message_id: Option<String>,
    pub created_at_ms: i64,
}

#[derive(Clone, Debug)]
pub struct TodoChecklistItem {
    pub id: String,
    pub todo_id: String,
    pub content: String,
    pub is_done: bool,
    pub sort_order: i64,
    pub created_at_ms: i64,
    pub updated_at_ms: i64,
}

#[derive(Clone, Debug)]
pub struct TodoChecklistSuggestion {
    pub id: String,
    pub todo_id: String,
    pub content: String,
    pub sort_order: i64,
    pub state: String,
    pub source: String,
    pub generation_key: Option<String>,
    pub created_at_ms: i64,
    pub updated_at_ms: i64,
    pub dismissed_at_ms: Option<i64>,
    pub applied_checklist_item_id: Option<String>,
}

pub const TODO_CHECKLIST_SUGGESTION_STATE_PENDING: &str = "pending";
pub const TODO_CHECKLIST_SUGGESTION_STATE_APPLIED: &str = "applied";
pub const TODO_CHECKLIST_SUGGESTION_STATE_DISMISSED: &str = "dismissed";

#[derive(Clone, Debug)]
pub struct TodoChecklistProgress {
    pub todo_id: String,
    pub done_count: i64,
    pub total_count: i64,
}

#[derive(Clone, Debug)]
pub struct TodoFollowupSuggestionDraftInput {
    pub content: String,
    pub generation_mode: String,
    pub citations_json: Option<String>,
}

#[derive(Clone, Debug)]
pub struct TodoFollowupSuggestion {
    pub id: String,
    pub todo_id: String,
    pub content: String,
    pub state: String,
    pub source: String,
    pub generation_mode: String,
    pub generation_key: Option<String>,
    pub citations_json: Option<String>,
    pub created_at_ms: i64,
    pub updated_at_ms: i64,
    pub dismissed_at_ms: Option<i64>,
    pub applied_activity_id: Option<String>,
}

#[derive(Clone, Debug)]
pub struct TodoFollowupGenerationJob {
    pub todo_id: String,
    pub trigger_kind: String,
    pub status: String,
    pub attempts: i64,
    pub next_retry_at_ms: Option<i64>,
    pub last_error: Option<String>,
    pub include_manual_followups: bool,
    pub manual_override_followup: bool,
    pub task_type_hint: Option<String>,
    pub created_at_ms: i64,
    pub updated_at_ms: i64,
}

#[derive(Clone, Debug)]
pub struct Event {
    pub id: String,
    pub title: String,
    pub start_at_ms: i64,
    pub end_at_ms: i64,
    pub tz: String,
    pub source_entry_id: Option<String>,
    pub created_at_ms: i64,
    pub updated_at_ms: i64,
}

fn db_path(app_dir: &Path) -> PathBuf {
    app_dir.join("secondloop.sqlite3")
}

fn now_ms() -> i64 {
    crate::platform::time::now_ms()
}

fn semantic_parse_job_title_aad(message_id: &str) -> Vec<u8> {
    format!("semantic_parse_job.title:{message_id}").into_bytes()
}

fn semantic_parse_job_suggested_tags_aad(message_id: &str) -> Vec<u8> {
    format!("semantic_parse_job.suggested_tags:{message_id}").into_bytes()
}

fn semantic_parse_job_applied_tag_ids_aad(message_id: &str) -> Vec<u8> {
    format!("semantic_parse_job.applied_tag_ids:{message_id}").into_bytes()
}

pub fn get_or_create_device_id(conn: &Connection) -> Result<String> {
    let existing: Option<String> = conn
        .query_row(
            r#"SELECT value FROM kv WHERE key = 'device_id'"#,
            [],
            |row| row.get(0),
        )
        .optional()?;

    if let Some(device_id) = existing {
        return Ok(device_id);
    }

    let device_id = uuid::Uuid::new_v4().to_string();
    conn.execute(
        r#"INSERT INTO kv(key, value) VALUES ('device_id', ?1)"#,
        params![device_id],
    )?;
    Ok(device_id)
}

pub fn get_active_embedding_model_name(conn: &Connection) -> Result<Option<String>> {
    let existing: Option<String> = conn
        .query_row(
            "SELECT value FROM kv WHERE key = ?1",
            params![KV_ACTIVE_EMBEDDING_MODEL_NAME],
            |row| row.get(0),
        )
        .optional()?;
    Ok(existing)
}

fn parse_vec_dim_from_column_type(column_type: &str) -> Option<usize> {
    let type_lc = column_type.trim().to_ascii_lowercase();
    let rest = type_lc.strip_prefix("float[")?;
    let digits = rest.strip_suffix(']')?;
    digits.parse::<usize>().ok()
}

fn vec0_dim_from_table(conn: &Connection, table: &str) -> Result<Option<usize>> {
    let stmt = match table {
        "message_embeddings" => "PRAGMA table_info(message_embeddings)",
        "todo_embeddings" => "PRAGMA table_info(todo_embeddings)",
        "todo_activity_embeddings" => "PRAGMA table_info(todo_activity_embeddings)",
        _ => return Err(anyhow!("unknown vec0 table: {table}")),
    };

    let mut stmt = conn.prepare(stmt)?;
    let mut rows = stmt.query([])?;

    while let Some(row) = rows.next()? {
        let name: String = row.get(1)?;
        if name != "embedding" {
            continue;
        }
        let column_type: String = row.get(2)?;
        return Ok(parse_vec_dim_from_column_type(&column_type));
    }

    Ok(None)
}

pub fn get_active_embedding_dim(conn: &Connection) -> Result<Option<usize>> {
    let existing: Option<String> = conn
        .query_row(
            "SELECT value FROM kv WHERE key = ?1",
            params![KV_ACTIVE_EMBEDDING_DIM],
            |row| row.get(0),
        )
        .optional()?;

    let Some(raw) = existing else {
        return Ok(None);
    };
    let trimmed = raw.trim();
    if trimmed.is_empty() {
        return Ok(None);
    }
    let dim = trimmed
        .parse::<usize>()
        .map_err(|_| anyhow!("invalid {KV_ACTIVE_EMBEDDING_DIM}: {raw}"))?;
    Ok(Some(dim))
}

pub fn lookup_embedding_space_dim(conn: &Connection, model_name: &str) -> Result<Option<usize>> {
    if !sqlite_table_exists(conn, "embedding_spaces")? {
        return Ok(None);
    }

    let dim_i64: Option<i64> = conn
        .query_row(
            r#"SELECT dim
               FROM embedding_spaces
               WHERE model_name = ?1
               ORDER BY updated_at_ms DESC
               LIMIT 1"#,
            params![model_name],
            |row| row.get(0),
        )
        .optional()?;

    let Some(dim_i64) = dim_i64 else {
        return Ok(None);
    };
    let dim = usize::try_from(dim_i64).unwrap_or(0);
    if dim == 0 || dim > 8192 {
        return Ok(None);
    }
    Ok(Some(dim))
}

pub fn load_cloud_gateway_embeddings_cache(
    conn: &Connection,
) -> Result<Option<CloudGatewayEmbeddingsCache>> {
    let base_url = kv_get_string(conn, KV_CLOUD_GATEWAY_EMBEDDINGS_CACHE_BASE_URL)?
        .unwrap_or_default()
        .trim()
        .to_string();
    let requested_model_name = kv_get_string(conn, KV_CLOUD_GATEWAY_EMBEDDINGS_CACHE_REQUESTED_MODEL_NAME)?
        .unwrap_or_default()
        .trim()
        .to_string();
    let effective_model_id = kv_get_string(conn, KV_CLOUD_GATEWAY_EMBEDDINGS_CACHE_MODEL_ID)?
        .unwrap_or_default()
        .trim()
        .to_string();
    let dim_raw = kv_get_string(conn, KV_CLOUD_GATEWAY_EMBEDDINGS_CACHE_DIM)?
        .unwrap_or_default()
        .trim()
        .to_string();

    if base_url.is_empty()
        || requested_model_name.is_empty()
        || effective_model_id.is_empty()
        || dim_raw.is_empty()
    {
        return Ok(None);
    }

    let dim = dim_raw
        .parse::<usize>()
        .map_err(|_| anyhow!("invalid {KV_CLOUD_GATEWAY_EMBEDDINGS_CACHE_DIM}: {dim_raw}"))?;
    if dim == 0 || dim > 8192 {
        return Ok(None);
    }

    Ok(Some(CloudGatewayEmbeddingsCache {
        base_url,
        requested_model_name,
        effective_model_id,
        dim,
    }))
}

pub fn store_cloud_gateway_embeddings_cache(
    conn: &Connection,
    base_url: &str,
    requested_model_name: &str,
    effective_model_id: &str,
    dim: usize,
) -> Result<()> {
    if dim == 0 || dim > 8192 {
        return Err(anyhow!("invalid embedding dim: {dim}"));
    }

    kv_set_string(
        conn,
        KV_CLOUD_GATEWAY_EMBEDDINGS_CACHE_BASE_URL,
        base_url.trim(),
    )?;
    kv_set_string(
        conn,
        KV_CLOUD_GATEWAY_EMBEDDINGS_CACHE_REQUESTED_MODEL_NAME,
        requested_model_name.trim(),
    )?;
    kv_set_string(
        conn,
        KV_CLOUD_GATEWAY_EMBEDDINGS_CACHE_MODEL_ID,
        effective_model_id.trim(),
    )?;
    kv_set_string(
        conn,
        KV_CLOUD_GATEWAY_EMBEDDINGS_CACHE_DIM,
        &dim.to_string(),
    )?;
    Ok(())
}

fn current_embedding_dim(conn: &Connection) -> Result<usize> {
    if let Some(dim) = get_active_embedding_dim(conn)? {
        return Ok(dim);
    }
    if let Some(dim) = vec0_dim_from_table(conn, "message_embeddings")? {
        return Ok(dim);
    }
    Ok(DEFAULT_EMBEDDING_DIM)
}

fn embedding_space_id(model_name: &str, dim: usize) -> Result<String> {
    let model_name = model_name.trim();
    if model_name.is_empty() {
        return Err(anyhow!("missing embedding model_name"));
    }
    if dim == 0 || dim > 8192 {
        return Err(anyhow!("invalid embedding dim: {dim}"));
    }

    let mut s = String::new();
    for ch in model_name.chars() {
        if ch.is_ascii_alphanumeric() {
            s.push(ch.to_ascii_lowercase());
        } else {
            s.push('_');
        }
    }
    while s.contains("__") {
        s = s.replace("__", "_");
    }
    let s = s.trim_matches('_');
    let s = if s.is_empty() { "unknown" } else { s };
    Ok(format!("s_{s}_{dim}"))
}

fn is_safe_sqlite_ident(name: &str) -> bool {
    name.chars()
        .all(|ch| ch.is_ascii_alphanumeric() || ch == '_')
}

fn sqlite_table_exists(conn: &Connection, name: &str) -> Result<bool> {
    let count: i64 = conn.query_row(
        "SELECT COUNT(*) FROM sqlite_master WHERE type = 'table' AND name = ?1",
        params![name],
        |row| row.get(0),
    )?;
    Ok(count > 0)
}

fn sqlite_vec_table_sql(table: &str, columns: &str) -> String {
    if crate::vector::is_available() {
        format!(r#"CREATE VIRTUAL TABLE "{table}" USING vec0({columns});"#)
    } else {
        format!(r#"CREATE TABLE "{table}"({columns});"#)
    }
}

fn vec0_dim_from_sqlite_master(conn: &Connection, table: &str) -> Result<Option<usize>> {
    let sql: Option<String> = conn
        .query_row(
            "SELECT sql FROM sqlite_master WHERE type = 'table' AND name = ?1",
            params![table],
            |row| row.get(0),
        )
        .optional()?;
    let Some(sql) = sql else {
        return Ok(None);
    };
    let sql_lc = sql.to_ascii_lowercase();
    let Some(start) = sql_lc.find("float[") else {
        return Ok(None);
    };
    let after = &sql_lc[start + "float[".len()..];
    let Some(end) = after.find(']') else {
        return Ok(None);
    };
    let digits = &after[..end];
    Ok(digits.parse::<usize>().ok())
}

fn message_embeddings_table(space_id: &str) -> Result<String> {
    if !is_safe_sqlite_ident(space_id) {
        return Err(anyhow!("unsafe embedding space_id: {space_id}"));
    }
    Ok(format!("message_embeddings__{space_id}"))
}

fn todo_embeddings_table(space_id: &str) -> Result<String> {
    if !is_safe_sqlite_ident(space_id) {
        return Err(anyhow!("unsafe embedding space_id: {space_id}"));
    }
    Ok(format!("todo_embeddings__{space_id}"))
}

fn todo_activity_embeddings_table(space_id: &str) -> Result<String> {
    if !is_safe_sqlite_ident(space_id) {
        return Err(anyhow!("unsafe embedding space_id: {space_id}"));
    }
    Ok(format!("todo_activity_embeddings__{space_id}"))
}

fn attachment_chunk_embeddings_table(space_id: &str) -> Result<String> {
    if !is_safe_sqlite_ident(space_id) {
        return Err(anyhow!("unsafe embedding space_id: {space_id}"));
    }
    Ok(format!("attachment_chunk_embeddings__{space_id}"))
}

fn ensure_attachment_chunk_vec_table_for_space(
    conn: &Connection,
    space_id: &str,
    dim: usize,
) -> Result<()> {
    if dim == 0 || dim > 8192 {
        return Err(anyhow!("invalid embedding dim: {dim}"));
    }

    let table = attachment_chunk_embeddings_table(space_id)?;
    if !sqlite_table_exists(conn, &table)? {
        conn.execute_batch(&sqlite_vec_table_sql(
            &table,
            &format!(
                r#"
  embedding {},
  chunk_rowid INTEGER,
  attachment_sha256 TEXT,
  kind TEXT,
  chunk_index INTEGER,
  model_name TEXT
"#,
                if crate::vector::is_available() {
                    format!("float[{dim}]")
                } else {
                    "BLOB".to_string()
                }
            ),
        ))?;
    }

    if !crate::vector::is_available() {
        return Ok(());
    }

    let actual_dim = vec0_dim_from_sqlite_master(conn, &table)?.unwrap_or(0);
    if actual_dim != dim {
        return Err(anyhow!(
            "attachment-chunk vec0 dim mismatch: expected {dim}, got {actual_dim} (table={table})"
        ));
    }

    Ok(())
}

fn ensure_vec_tables_for_space(conn: &Connection, space_id: &str, dim: usize) -> Result<()> {
    if dim == 0 || dim > 8192 {
        return Err(anyhow!("invalid embedding dim: {dim}"));
    }

    let message_table = message_embeddings_table(space_id)?;
    let todo_table = todo_embeddings_table(space_id)?;
    let activity_table = todo_activity_embeddings_table(space_id)?;

    if !sqlite_table_exists(conn, &message_table)? {
        conn.execute_batch(&sqlite_vec_table_sql(
            &message_table,
            &format!(
                r#"
  embedding {},
  message_id TEXT,
  model_name TEXT
"#,
                if crate::vector::is_available() {
                    format!("float[{dim}]")
                } else {
                    "BLOB".to_string()
                }
            ),
        ))?;
    }
    if !sqlite_table_exists(conn, &todo_table)? {
        conn.execute_batch(&sqlite_vec_table_sql(
            &todo_table,
            &format!(
                r#"
  embedding {},
  todo_id TEXT,
  model_name TEXT
"#,
                if crate::vector::is_available() {
                    format!("float[{dim}]")
                } else {
                    "BLOB".to_string()
                }
            ),
        ))?;
    }
    if !sqlite_table_exists(conn, &activity_table)? {
        conn.execute_batch(&sqlite_vec_table_sql(
            &activity_table,
            &format!(
                r#"
  embedding {},
  activity_id TEXT,
  todo_id TEXT,
  model_name TEXT
"#,
                if crate::vector::is_available() {
                    format!("float[{dim}]")
                } else {
                    "BLOB".to_string()
                }
            ),
        ))?;
    }

    ensure_attachment_chunk_vec_table_for_space(conn, space_id, dim)?;

    if !crate::vector::is_available() {
        return Ok(());
    }

    let msg_dim = vec0_dim_from_sqlite_master(conn, &message_table)?.unwrap_or(0);
    if msg_dim != dim {
        return Err(anyhow!(
            "message vec0 dim mismatch: expected {dim}, got {msg_dim} (table={message_table})"
        ));
    }
    let todo_dim = vec0_dim_from_sqlite_master(conn, &todo_table)?.unwrap_or(0);
    if todo_dim != dim {
        return Err(anyhow!(
            "todo vec0 dim mismatch: expected {dim}, got {todo_dim} (table={todo_table})"
        ));
    }
    let act_dim = vec0_dim_from_sqlite_master(conn, &activity_table)?.unwrap_or(0);
    if act_dim != dim {
        return Err(anyhow!(
            "todo-activity vec0 dim mismatch: expected {dim}, got {act_dim} (table={activity_table})"
        ));
    }

    Ok(())
}

fn recompute_needs_embedding_for_space(conn: &Connection, space_id: &str) -> Result<()> {
    let message_table = message_embeddings_table(space_id)?;
    let todo_table = todo_embeddings_table(space_id)?;
    let activity_table = todo_activity_embeddings_table(space_id)?;

    conn.execute_batch(&format!(
        r#"
UPDATE messages
SET needs_embedding = CASE
  WHEN COALESCE(is_deleted, 0) = 0
   AND COALESCE(is_memory, 1) = 1
   AND NOT EXISTS (SELECT 1 FROM "{message_table}" me WHERE me.rowid = messages.rowid)
  THEN 1
  ELSE 0
END;

UPDATE todos
SET needs_embedding = CASE
  WHEN status != 'dismissed'
   AND NOT EXISTS (SELECT 1 FROM "{todo_table}" te WHERE te.rowid = todos.rowid)
  THEN 1
  ELSE 0
END;

UPDATE todo_activities
SET needs_embedding = CASE
  WHEN NOT EXISTS (
    SELECT 1 FROM "{activity_table}" tae WHERE tae.rowid = todo_activities.rowid
  )
  THEN 1
  ELSE 0
END;
"#
    ))?;
    Ok(())
}

pub fn set_active_embedding_model(conn: &Connection, model_name: &str, dim: usize) -> Result<bool> {
    let existing_model = get_active_embedding_model_name(conn)?;
    let existing_dim = get_active_embedding_dim(conn)?;
    if existing_model.as_deref() == Some(model_name) && existing_dim == Some(dim) {
        return Ok(false);
    }

    conn.execute_batch("BEGIN IMMEDIATE;")?;

    let result = (|| -> Result<bool> {
        let next_space_id = embedding_space_id(model_name, dim)?;

        conn.execute(
            r#"INSERT INTO kv(key, value)
               VALUES (?1, ?2)
               ON CONFLICT(key) DO UPDATE SET value = excluded.value"#,
            params![KV_ACTIVE_EMBEDDING_MODEL_NAME, model_name],
        )?;
        conn.execute(
            r#"INSERT INTO kv(key, value)
               VALUES (?1, ?2)
               ON CONFLICT(key) DO UPDATE SET value = excluded.value"#,
            params![KV_ACTIVE_EMBEDDING_DIM, dim.to_string()],
        )?;

        conn.execute_batch(
            r#"
CREATE TABLE IF NOT EXISTS embedding_spaces (
  space_id TEXT PRIMARY KEY,
  model_name TEXT NOT NULL,
  dim INTEGER NOT NULL,
  created_at_ms INTEGER NOT NULL,
  updated_at_ms INTEGER NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_embedding_spaces_updated_at_ms
  ON embedding_spaces(updated_at_ms);
"#,
        )?;

        let now = now_ms();
        conn.execute(
            r#"INSERT INTO embedding_spaces(space_id, model_name, dim, created_at_ms, updated_at_ms)
               VALUES (?1, ?2, ?3, ?4, ?4)
               ON CONFLICT(space_id) DO UPDATE SET
                 model_name = excluded.model_name,
                 dim = excluded.dim,
                 updated_at_ms = excluded.updated_at_ms"#,
            params![next_space_id, model_name, dim as i64, now],
        )?;

        ensure_vec_tables_for_space(conn, &next_space_id, dim)?;
        recompute_needs_embedding_for_space(conn, &next_space_id)?;

        Ok(true)
    })();

    match result {
        Ok(changed) => {
            conn.execute_batch("COMMIT;")?;
            Ok(changed)
        }
        Err(e) => {
            let _ = conn.execute_batch("ROLLBACK;");
            Err(e)
        }
    }
}

pub fn set_active_embedding_model_name(conn: &Connection, model_name: &str) -> Result<bool> {
    let dim = match model_name {
        crate::embedding::DEFAULT_MODEL_NAME | crate::embedding::PRODUCTION_MODEL_NAME => {
            DEFAULT_EMBEDDING_DIM
        }
        _ => current_embedding_dim(conn)?,
    };
    set_active_embedding_model(conn, model_name, dim)
}
