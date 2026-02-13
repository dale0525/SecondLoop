use std::path::{Path, PathBuf};

use crate::crypto::{derive_root_key, KdfParams};
use crate::embedding;
use crate::embedding::Embedder;
use crate::frb_generated::StreamSink;
use crate::sync;
use crate::sync::RemoteStore;
use crate::{auth, db};
use crate::{geo, media_annotation};
use crate::{llm, rag, semantic_parse};
use anyhow::{anyhow, Result};

const ASK_AI_ERROR_PREFIX: &str = "\u{001e}SL_ERROR\u{001e}";
const ASK_AI_META_PREFIX: &str = "\u{001e}SL_META\u{001e}";
const ASK_AI_META_REQUEST_ID_ROLE_PREFIX: &str = "secondloop_request_id:";

fn emit_ask_ai_meta_if_any(sink: &StreamSink<String>, role: Option<&str>) -> Result<()> {
    let Some(role) = role else {
        return Ok(());
    };
    let Some(request_id) = role.strip_prefix(ASK_AI_META_REQUEST_ID_ROLE_PREFIX) else {
        return Ok(());
    };
    if request_id.trim().is_empty() {
        return Ok(());
    }

    let payload = format!(
        "{ASK_AI_META_PREFIX}{{\"type\":\"cloud_request_id\",\"request_id\":\"{request_id}\"}}"
    );
    if sink.add(payload).is_err() {
        return Err(rag::StreamCancelled.into());
    }
    Ok(())
}

fn finish_ask_ai_stream(sink: &StreamSink<String>, result: Result<()>) -> Result<()> {
    match result {
        Ok(()) => Ok(()),
        Err(e) if e.is::<rag::StreamCancelled>() => Ok(()),
        Err(e) => {
            let _ = sink.add(format!("{ASK_AI_ERROR_PREFIX}{e}"));
            Ok(())
        }
    }
}

fn key_from_bytes(bytes: Vec<u8>) -> Result<[u8; 32]> {
    if bytes.len() != 32 {
        return Err(anyhow!("invalid key length"));
    }
    let mut key = [0u8; 32];
    key.copy_from_slice(&bytes);
    Ok(key)
}

fn sync_key_from_bytes(bytes: Vec<u8>) -> Result<[u8; 32]> {
    key_from_bytes(bytes)
}

fn default_embedding_model_name_for_platform() -> &'static str {
    if cfg!(any(
        target_os = "windows",
        target_os = "macos",
        target_os = "linux"
    )) {
        embedding::PRODUCTION_MODEL_NAME
    } else {
        embedding::DEFAULT_MODEL_NAME
    }
}

fn normalize_embedding_model_name(name: &str) -> &'static str {
    match name {
        embedding::DEFAULT_MODEL_NAME => embedding::DEFAULT_MODEL_NAME,
        embedding::PRODUCTION_MODEL_NAME => embedding::PRODUCTION_MODEL_NAME,
        _ => default_embedding_model_name_for_platform(),
    }
}

#[flutter_rust_bridge::frb]
pub fn auth_is_initialized(app_dir: String) -> bool {
    auth::is_initialized(Path::new(&app_dir))
}

#[flutter_rust_bridge::frb]
pub fn auth_init_master_password(app_dir: String, password: String) -> Result<Vec<u8>> {
    let kdf = KdfParams {
        m_cost_kib: 8 * 1024,
        t_cost: 2,
        p_cost: 1,
    };
    let key = auth::init_master_password(Path::new(&app_dir), &password, kdf)?;
    Ok(key.to_vec())
}

#[flutter_rust_bridge::frb]
pub fn auth_unlock_with_password(app_dir: String, password: String) -> Result<Vec<u8>> {
    let key = auth::unlock_with_password(Path::new(&app_dir), &password)?;
    Ok(key.to_vec())
}

#[flutter_rust_bridge::frb]
pub fn auth_validate_key(app_dir: String, key: Vec<u8>) -> Result<()> {
    let key = key_from_bytes(key)?;
    auth::validate_key(Path::new(&app_dir), &key)
}

#[flutter_rust_bridge::frb]
pub fn db_list_conversations(app_dir: String, key: Vec<u8>) -> Result<Vec<db::Conversation>> {
    let key = key_from_bytes(key)?;
    let conn = db::open(Path::new(&app_dir))?;
    db::list_conversations(&conn, &key)
}

#[flutter_rust_bridge::frb]
pub fn db_create_conversation(
    app_dir: String,
    key: Vec<u8>,
    title: String,
) -> Result<db::Conversation> {
    let key = key_from_bytes(key)?;
    let conn = db::open(Path::new(&app_dir))?;
    db::create_conversation(&conn, &key, &title)
}

#[flutter_rust_bridge::frb]
pub fn db_get_or_create_main_stream_conversation(
    app_dir: String,
    key: Vec<u8>,
) -> Result<db::Conversation> {
    let key = key_from_bytes(key)?;
    let conn = db::open(Path::new(&app_dir))?;
    db::get_or_create_main_stream_conversation(&conn, &key)
}

#[flutter_rust_bridge::frb]
pub fn db_list_messages(
    app_dir: String,
    key: Vec<u8>,
    conversation_id: String,
) -> Result<Vec<db::Message>> {
    let key = key_from_bytes(key)?;
    let conn = db::open(Path::new(&app_dir))?;
    db::list_messages(&conn, &key, &conversation_id)
}

#[flutter_rust_bridge::frb]
pub fn db_list_messages_page(
    app_dir: String,
    key: Vec<u8>,
    conversation_id: String,
    before_created_at_ms: Option<i64>,
    before_id: Option<String>,
    limit: u32,
) -> Result<Vec<db::Message>> {
    let key = key_from_bytes(key)?;
    let conn = db::open(Path::new(&app_dir))?;
    db::list_messages_page(
        &conn,
        &key,
        &conversation_id,
        before_created_at_ms,
        before_id.as_deref(),
        limit as i64,
    )
}

#[flutter_rust_bridge::frb]
pub fn db_get_message_by_id(
    app_dir: String,
    key: Vec<u8>,
    message_id: String,
) -> Result<Option<db::Message>> {
    let key = key_from_bytes(key)?;
    let conn = db::open(Path::new(&app_dir))?;
    db::get_message_by_id_optional(&conn, &key, &message_id)
}

#[flutter_rust_bridge::frb]
pub fn db_insert_message(
    app_dir: String,
    key: Vec<u8>,
    conversation_id: String,
    role: String,
    content: String,
) -> Result<db::Message> {
    let key = key_from_bytes(key)?;
    let conn = db::open(Path::new(&app_dir))?;
    db::insert_message(&conn, &key, &conversation_id, &role, &content)
}

#[flutter_rust_bridge::frb]
#[allow(clippy::too_many_arguments)]
pub fn db_upsert_todo(
    app_dir: String,
    key: Vec<u8>,
    id: String,
    title: String,
    due_at_ms: Option<i64>,
    status: String,
    source_entry_id: Option<String>,
    review_stage: Option<i64>,
    next_review_at_ms: Option<i64>,
    last_review_at_ms: Option<i64>,
) -> Result<db::Todo> {
    let key = key_from_bytes(key)?;
    let conn = db::open(Path::new(&app_dir))?;
    db::upsert_todo(
        &conn,
        &key,
        &id,
        &title,
        due_at_ms,
        &status,
        source_entry_id.as_deref(),
        review_stage,
        next_review_at_ms,
        last_review_at_ms,
    )
}

#[flutter_rust_bridge::frb]
pub fn db_list_todos(app_dir: String, key: Vec<u8>) -> Result<Vec<db::Todo>> {
    let key = key_from_bytes(key)?;
    let conn = db::open(Path::new(&app_dir))?;
    db::list_todos(&conn, &key)
}

#[flutter_rust_bridge::frb]
pub fn db_list_todos_created_in_range(
    app_dir: String,
    key: Vec<u8>,
    start_at_ms_inclusive: i64,
    end_at_ms_exclusive: i64,
) -> Result<Vec<db::Todo>> {
    let key = key_from_bytes(key)?;
    let conn = db::open(Path::new(&app_dir))?;
    db::list_todos_created_in_range(&conn, &key, start_at_ms_inclusive, end_at_ms_exclusive)
}

#[flutter_rust_bridge::frb]
pub fn db_set_todo_status(
    app_dir: String,
    key: Vec<u8>,
    todo_id: String,
    new_status: String,
    source_message_id: Option<String>,
) -> Result<db::Todo> {
    let key = key_from_bytes(key)?;
    let conn = db::open(Path::new(&app_dir))?;
    db::set_todo_status(
        &conn,
        &key,
        &todo_id,
        &new_status,
        source_message_id.as_deref(),
    )
}

#[flutter_rust_bridge::frb]
pub fn db_delete_todo_and_associated_messages(
    app_dir: String,
    key: Vec<u8>,
    todo_id: String,
) -> Result<u64> {
    let key = key_from_bytes(key)?;
    let app_dir_path = Path::new(&app_dir);
    let conn = db::open(app_dir_path)?;
    db::delete_todo_and_associated_messages(&conn, &key, app_dir_path, &todo_id)
}

#[flutter_rust_bridge::frb]
pub fn db_append_todo_note(
    app_dir: String,
    key: Vec<u8>,
    todo_id: String,
    content: String,
    source_message_id: Option<String>,
) -> Result<db::TodoActivity> {
    let key = key_from_bytes(key)?;
    let conn = db::open(Path::new(&app_dir))?;
    db::append_todo_note(
        &conn,
        &key,
        &todo_id,
        &content,
        source_message_id.as_deref(),
    )
}

#[flutter_rust_bridge::frb]
pub fn db_move_todo_activity(
    app_dir: String,
    key: Vec<u8>,
    activity_id: String,
    to_todo_id: String,
) -> Result<db::TodoActivity> {
    let key = key_from_bytes(key)?;
    let conn = db::open(Path::new(&app_dir))?;
    db::move_todo_activity(&conn, &key, &activity_id, &to_todo_id)
}

#[flutter_rust_bridge::frb]
pub fn db_list_todo_activities(
    app_dir: String,
    key: Vec<u8>,
    todo_id: String,
) -> Result<Vec<db::TodoActivity>> {
    let key = key_from_bytes(key)?;
    let conn = db::open(Path::new(&app_dir))?;
    db::list_todo_activities(&conn, &key, &todo_id)
}

#[flutter_rust_bridge::frb]
pub fn db_list_todo_activities_in_range(
    app_dir: String,
    key: Vec<u8>,
    start_at_ms_inclusive: i64,
    end_at_ms_exclusive: i64,
) -> Result<Vec<db::TodoActivity>> {
    let key = key_from_bytes(key)?;
    let conn = db::open(Path::new(&app_dir))?;
    db::list_todo_activities_in_range(&conn, &key, start_at_ms_inclusive, end_at_ms_exclusive)
}

#[flutter_rust_bridge::frb]
pub fn db_link_attachment_to_todo_activity(
    app_dir: String,
    key: Vec<u8>,
    activity_id: String,
    attachment_sha256: String,
) -> Result<()> {
    let key = key_from_bytes(key)?;
    let conn = db::open(Path::new(&app_dir))?;
    db::link_attachment_to_todo_activity(&conn, &key, &activity_id, &attachment_sha256)
}

#[flutter_rust_bridge::frb]
pub fn db_list_todo_activity_attachments(
    app_dir: String,
    key: Vec<u8>,
    activity_id: String,
) -> Result<Vec<db::Attachment>> {
    let key = key_from_bytes(key)?;
    let conn = db::open(Path::new(&app_dir))?;
    db::list_todo_activity_attachments(&conn, &key, &activity_id)
}

#[flutter_rust_bridge::frb]
pub fn db_upsert_event(
    app_dir: String,
    key: Vec<u8>,
    id: String,
    title: String,
    start_at_ms: i64,
    end_at_ms: i64,
    tz: String,
    source_entry_id: Option<String>,
) -> Result<db::Event> {
    let key = key_from_bytes(key)?;
    let conn = db::open(Path::new(&app_dir))?;
    db::upsert_event(
        &conn,
        &key,
        &id,
        &title,
        start_at_ms,
        end_at_ms,
        &tz,
        source_entry_id.as_deref(),
    )
}

#[flutter_rust_bridge::frb]
pub fn db_list_events(app_dir: String, key: Vec<u8>) -> Result<Vec<db::Event>> {
    let key = key_from_bytes(key)?;
    let conn = db::open(Path::new(&app_dir))?;
    db::list_events(&conn, &key)
}

#[flutter_rust_bridge::frb]
pub fn db_edit_message(
    app_dir: String,
    key: Vec<u8>,
    message_id: String,
    content: String,
) -> Result<()> {
    let key = key_from_bytes(key)?;
    let conn = db::open(Path::new(&app_dir))?;
    db::edit_message(&conn, &key, &message_id, &content)
}

#[flutter_rust_bridge::frb]
pub fn db_set_message_deleted(
    app_dir: String,
    key: Vec<u8>,
    message_id: String,
    is_deleted: bool,
) -> Result<()> {
    let key = key_from_bytes(key)?;
    let conn = db::open(Path::new(&app_dir))?;
    db::set_message_deleted(&conn, &key, &message_id, is_deleted)
}

#[flutter_rust_bridge::frb]
pub fn db_purge_message_attachments(
    app_dir: String,
    key: Vec<u8>,
    message_id: String,
) -> Result<u64> {
    let key = key_from_bytes(key)?;
    let conn = db::open(Path::new(&app_dir))?;
    db::purge_message_attachments(&conn, &key, Path::new(&app_dir), &message_id)
}

#[flutter_rust_bridge::frb]
pub fn db_clear_local_attachment_cache(app_dir: String, key: Vec<u8>) -> Result<()> {
    let _key = key_from_bytes(key)?;
    let conn = db::open(Path::new(&app_dir))?;
    db::clear_local_attachment_cache(&conn, Path::new(&app_dir))
}

#[flutter_rust_bridge::frb]
pub fn db_insert_attachment(
    app_dir: String,
    key: Vec<u8>,
    bytes: Vec<u8>,
    mime_type: String,
) -> Result<db::Attachment> {
    let key = key_from_bytes(key)?;
    let conn = db::open(Path::new(&app_dir))?;
    db::insert_attachment(&conn, &key, Path::new(&app_dir), &bytes, &mime_type)
}

#[flutter_rust_bridge::frb]
pub fn db_link_attachment_to_message(
    app_dir: String,
    key: Vec<u8>,
    message_id: String,
    attachment_sha256: String,
) -> Result<()> {
    let key = key_from_bytes(key)?;
    let conn = db::open(Path::new(&app_dir))?;
    db::link_attachment_to_message(&conn, &key, &message_id, &attachment_sha256)
}

#[flutter_rust_bridge::frb]
pub fn db_list_message_attachments(
    app_dir: String,
    key: Vec<u8>,
    message_id: String,
) -> Result<Vec<db::Attachment>> {
    let key = key_from_bytes(key)?;
    let conn = db::open(Path::new(&app_dir))?;
    db::list_message_attachments(&conn, &key, &message_id)
}

#[flutter_rust_bridge::frb]
pub fn db_list_recent_attachments(
    app_dir: String,
    key: Vec<u8>,
    limit: u32,
) -> Result<Vec<db::Attachment>> {
    let key = key_from_bytes(key)?;
    let conn = db::open(Path::new(&app_dir))?;
    db::list_recent_attachments(&conn, &key, limit as i64)
}

#[flutter_rust_bridge::frb]
pub fn db_read_attachment_bytes(app_dir: String, key: Vec<u8>, sha256: String) -> Result<Vec<u8>> {
    let key = key_from_bytes(key)?;
    let conn = db::open(Path::new(&app_dir))?;
    db::read_attachment_bytes(&conn, &key, Path::new(&app_dir), &sha256)
}

#[flutter_rust_bridge::frb]
pub fn db_upsert_attachment_exif_metadata(
    app_dir: String,
    key: Vec<u8>,
    attachment_sha256: String,
    captured_at_ms: Option<i64>,
    latitude: Option<f64>,
    longitude: Option<f64>,
) -> Result<()> {
    let key = key_from_bytes(key)?;
    let conn = db::open(Path::new(&app_dir))?;
    db::upsert_attachment_exif_metadata(
        &conn,
        &key,
        &attachment_sha256,
        captured_at_ms,
        latitude,
        longitude,
    )
}

#[flutter_rust_bridge::frb]
pub fn db_read_attachment_exif_metadata(
    app_dir: String,
    key: Vec<u8>,
    attachment_sha256: String,
) -> Result<Option<db::AttachmentExifMetadata>> {
    let key = key_from_bytes(key)?;
    let conn = db::open(Path::new(&app_dir))?;
    db::read_attachment_exif_metadata(&conn, &key, &attachment_sha256)
}

#[flutter_rust_bridge::frb]
pub fn db_read_attachment_place_display_name(
    app_dir: String,
    key: Vec<u8>,
    attachment_sha256: String,
) -> Result<Option<String>> {
    let key = key_from_bytes(key)?;
    let conn = db::open(Path::new(&app_dir))?;
    db::read_attachment_place_display_name(&conn, &key, &attachment_sha256)
}

#[flutter_rust_bridge::frb]
pub fn db_read_attachment_annotation_caption_long(
    app_dir: String,
    key: Vec<u8>,
    attachment_sha256: String,
) -> Result<Option<String>> {
    let key = key_from_bytes(key)?;
    let conn = db::open(Path::new(&app_dir))?;
    db::read_attachment_annotation_caption_long(&conn, &key, &attachment_sha256)
}

#[flutter_rust_bridge::frb]
pub fn db_enqueue_attachment_place(
    app_dir: String,
    key: Vec<u8>,
    attachment_sha256: String,
    lang: String,
    now_ms: i64,
) -> Result<()> {
    let _key = key_from_bytes(key)?;
    let conn = db::open(Path::new(&app_dir))?;
    db::enqueue_attachment_place(&conn, &attachment_sha256, &lang, now_ms)
}

#[flutter_rust_bridge::frb]
pub fn db_enqueue_attachment_annotation(
    app_dir: String,
    key: Vec<u8>,
    attachment_sha256: String,
    lang: String,
    now_ms: i64,
) -> Result<()> {
    let _key = key_from_bytes(key)?;
    let conn = db::open(Path::new(&app_dir))?;
    db::enqueue_attachment_annotation(&conn, &attachment_sha256, &lang, now_ms)
}

#[flutter_rust_bridge::frb]
pub fn db_list_due_attachment_places(
    app_dir: String,
    key: Vec<u8>,
    now_ms: i64,
    limit: u32,
) -> Result<Vec<db::AttachmentPlaceJob>> {
    let _key = key_from_bytes(key)?;
    let conn = db::open(Path::new(&app_dir))?;
    db::list_due_attachment_places(&conn, now_ms, limit as i64)
}

#[flutter_rust_bridge::frb]
pub fn db_list_due_attachment_annotations(
    app_dir: String,
    key: Vec<u8>,
    now_ms: i64,
    limit: u32,
) -> Result<Vec<db::AttachmentAnnotationJob>> {
    let _key = key_from_bytes(key)?;
    let conn = db::open(Path::new(&app_dir))?;
    db::list_due_attachment_annotations(&conn, now_ms, limit as i64)
}

#[flutter_rust_bridge::frb]
pub fn db_mark_attachment_place_failed(
    app_dir: String,
    key: Vec<u8>,
    attachment_sha256: String,
    attempts: i64,
    next_retry_at_ms: i64,
    last_error: String,
    now_ms: i64,
) -> Result<()> {
    let _key = key_from_bytes(key)?;
    let conn = db::open(Path::new(&app_dir))?;
    db::mark_attachment_place_failed(
        &conn,
        &attachment_sha256,
        attempts,
        next_retry_at_ms,
        &last_error,
        now_ms,
    )
}

#[flutter_rust_bridge::frb]
pub fn db_mark_attachment_annotation_failed(
    app_dir: String,
    key: Vec<u8>,
    attachment_sha256: String,
    attempts: i64,
    next_retry_at_ms: i64,
    last_error: String,
    now_ms: i64,
) -> Result<()> {
    let _key = key_from_bytes(key)?;
    let conn = db::open(Path::new(&app_dir))?;
    db::mark_attachment_annotation_failed(
        &conn,
        &attachment_sha256,
        attempts,
        next_retry_at_ms,
        &last_error,
        now_ms,
    )
}

#[flutter_rust_bridge::frb]
pub fn db_mark_attachment_place_ok_json(
    app_dir: String,
    key: Vec<u8>,
    attachment_sha256: String,
    lang: String,
    payload_json: String,
    now_ms: i64,
) -> Result<()> {
    let key = key_from_bytes(key)?;
    let conn = db::open(Path::new(&app_dir))?;
    let payload: serde_json::Value = serde_json::from_str(&payload_json)
        .map_err(|e| anyhow!("invalid attachment place payload json: {e}"))?;
    db::mark_attachment_place_ok(&conn, &key, &attachment_sha256, &lang, &payload, now_ms)
}

#[flutter_rust_bridge::frb]
pub fn db_mark_attachment_annotation_ok_json(
    app_dir: String,
    key: Vec<u8>,
    attachment_sha256: String,
    lang: String,
    model_name: String,
    payload_json: String,
    now_ms: i64,
) -> Result<()> {
    let key = key_from_bytes(key)?;
    let conn = db::open(Path::new(&app_dir))?;
    let payload: serde_json::Value = serde_json::from_str(&payload_json)
        .map_err(|e| anyhow!("invalid attachment annotation payload json: {e}"))?;
    db::mark_attachment_annotation_ok(
        &conn,
        &key,
        &attachment_sha256,
        &lang,
        &model_name,
        &payload,
        now_ms,
    )
}

#[flutter_rust_bridge::frb]
pub fn db_enqueue_semantic_parse_job(
    app_dir: String,
    key: Vec<u8>,
    message_id: String,
    now_ms: i64,
) -> Result<()> {
    let _key = key_from_bytes(key)?;
    let conn = db::open(Path::new(&app_dir))?;
    db::enqueue_semantic_parse_job(&conn, &message_id, now_ms)
}

#[flutter_rust_bridge::frb]
pub fn db_list_due_semantic_parse_jobs(
    app_dir: String,
    key: Vec<u8>,
    now_ms: i64,
    limit: u32,
) -> Result<Vec<db::SemanticParseJob>> {
    let _key = key_from_bytes(key)?;
    let conn = db::open(Path::new(&app_dir))?;
    db::list_due_semantic_parse_jobs(&conn, now_ms, limit as i64)
}

#[flutter_rust_bridge::frb]
pub fn db_list_semantic_parse_jobs_by_message_ids(
    app_dir: String,
    key: Vec<u8>,
    message_ids: Vec<String>,
) -> Result<Vec<db::SemanticParseJob>> {
    let key = key_from_bytes(key)?;
    let conn = db::open(Path::new(&app_dir))?;
    db::list_semantic_parse_jobs_by_message_ids(&conn, &key, &message_ids)
}

#[flutter_rust_bridge::frb]
pub fn db_mark_semantic_parse_job_running(
    app_dir: String,
    key: Vec<u8>,
    message_id: String,
    now_ms: i64,
) -> Result<()> {
    let _key = key_from_bytes(key)?;
    let conn = db::open(Path::new(&app_dir))?;
    db::mark_semantic_parse_job_running(&conn, &message_id, now_ms)
}

#[flutter_rust_bridge::frb]
pub fn db_mark_semantic_parse_job_failed(
    app_dir: String,
    key: Vec<u8>,
    message_id: String,
    attempts: i64,
    next_retry_at_ms: i64,
    last_error: String,
    now_ms: i64,
) -> Result<()> {
    let _key = key_from_bytes(key)?;
    let conn = db::open(Path::new(&app_dir))?;
    db::mark_semantic_parse_job_failed(
        &conn,
        &message_id,
        attempts,
        next_retry_at_ms,
        &last_error,
        now_ms,
    )
}

#[flutter_rust_bridge::frb]
pub fn db_mark_semantic_parse_job_retry(
    app_dir: String,
    key: Vec<u8>,
    message_id: String,
    now_ms: i64,
) -> Result<()> {
    let _key = key_from_bytes(key)?;
    let conn = db::open(Path::new(&app_dir))?;
    db::mark_semantic_parse_job_retry(&conn, &message_id, now_ms)
}

#[flutter_rust_bridge::frb]
#[allow(clippy::too_many_arguments)]
pub fn db_mark_semantic_parse_job_succeeded(
    app_dir: String,
    key: Vec<u8>,
    message_id: String,
    applied_action_kind: String,
    applied_todo_id: Option<String>,
    applied_todo_title: Option<String>,
    applied_prev_todo_status: Option<String>,
    now_ms: i64,
) -> Result<()> {
    let key = key_from_bytes(key)?;
    let conn = db::open(Path::new(&app_dir))?;
    db::mark_semantic_parse_job_succeeded(
        &conn,
        &key,
        &message_id,
        &applied_action_kind,
        applied_todo_id.as_deref(),
        applied_todo_title.as_deref(),
        applied_prev_todo_status.as_deref(),
        now_ms,
    )
}

#[flutter_rust_bridge::frb]
pub fn db_mark_semantic_parse_job_canceled(
    app_dir: String,
    key: Vec<u8>,
    message_id: String,
    now_ms: i64,
) -> Result<()> {
    let _key = key_from_bytes(key)?;
    let conn = db::open(Path::new(&app_dir))?;
    db::mark_semantic_parse_job_canceled(&conn, &message_id, now_ms)
}

#[flutter_rust_bridge::frb]
pub fn db_mark_semantic_parse_job_undone(
    app_dir: String,
    key: Vec<u8>,
    message_id: String,
    now_ms: i64,
) -> Result<()> {
    let _key = key_from_bytes(key)?;
    let conn = db::open(Path::new(&app_dir))?;
    db::mark_semantic_parse_job_undone(&conn, &message_id, now_ms)
}

#[flutter_rust_bridge::frb]
pub fn geo_reverse_cloud_gateway(
    gateway_base_url: String,
    firebase_id_token: String,
    lat: f64,
    lon: f64,
    lang: String,
) -> Result<String> {
    if gateway_base_url.trim().is_empty() {
        return Err(anyhow!("missing gateway_base_url"));
    }
    if firebase_id_token.trim().is_empty() {
        return Err(anyhow!("missing firebase_id_token"));
    }
    if lang.trim().is_empty() {
        return Err(anyhow!("missing lang"));
    }

    let client = geo::CloudGatewayGeoClient::new(gateway_base_url, firebase_id_token);
    let payload = client.reverse_geocode(lat, lon, &lang)?;
    Ok(payload.to_string())
}

#[flutter_rust_bridge::frb]
pub fn media_annotation_cloud_gateway(
    gateway_base_url: String,
    firebase_id_token: String,
    model_name: String,
    lang: String,
    mime_type: String,
    image_bytes: Vec<u8>,
) -> Result<String> {
    if gateway_base_url.trim().is_empty() {
        return Err(anyhow!("missing gateway_base_url"));
    }
    if firebase_id_token.trim().is_empty() {
        return Err(anyhow!("missing firebase_id_token"));
    }
    if model_name.trim().is_empty() {
        return Err(anyhow!("missing model_name"));
    }
    if lang.trim().is_empty() {
        return Err(anyhow!("missing lang"));
    }
    if mime_type.trim().is_empty() {
        return Err(anyhow!("missing mime_type"));
    }
    if image_bytes.is_empty() {
        return Err(anyhow!("missing image_bytes"));
    }

    let client = media_annotation::CloudGatewayMediaAnnotationClient::new(
        gateway_base_url,
        firebase_id_token,
        model_name,
    );
    let payload = client.annotate_image(&lang, &mime_type, &image_bytes)?;
    Ok(payload.to_string())
}

#[flutter_rust_bridge::frb]
pub fn db_upsert_attachment_variant(
    app_dir: String,
    key: Vec<u8>,
    attachment_sha256: String,
    variant: String,
    bytes: Vec<u8>,
    mime_type: String,
) -> Result<db::AttachmentVariant> {
    let key = key_from_bytes(key)?;
    let conn = db::open(Path::new(&app_dir))?;
    db::upsert_attachment_variant(
        &conn,
        &key,
        Path::new(&app_dir),
        &attachment_sha256,
        &variant,
        &bytes,
        &mime_type,
    )
}

#[flutter_rust_bridge::frb]
pub fn db_read_attachment_variant_bytes(
    app_dir: String,
    key: Vec<u8>,
    attachment_sha256: String,
    variant: String,
) -> Result<Vec<u8>> {
    let key = key_from_bytes(key)?;
    let conn = db::open(Path::new(&app_dir))?;
    db::read_attachment_variant_bytes(
        &conn,
        &key,
        Path::new(&app_dir),
        &attachment_sha256,
        &variant,
    )
}

#[flutter_rust_bridge::frb]
pub fn db_enqueue_cloud_media_backup(
    app_dir: String,
    key: Vec<u8>,
    attachment_sha256: String,
    desired_variant: String,
    now_ms: i64,
) -> Result<()> {
    let _key = key_from_bytes(key)?;
    let conn = db::open(Path::new(&app_dir))?;
    db::enqueue_cloud_media_backup(&conn, &attachment_sha256, &desired_variant, now_ms)
}

#[flutter_rust_bridge::frb]
pub fn db_backfill_cloud_media_backup_images(
    app_dir: String,
    key: Vec<u8>,
    desired_variant: String,
    now_ms: i64,
) -> Result<u64> {
    let _key = key_from_bytes(key)?;
    let conn = db::open(Path::new(&app_dir))?;
    db::backfill_cloud_media_backup_images(&conn, &desired_variant, now_ms)
}

#[flutter_rust_bridge::frb]
pub fn db_list_due_cloud_media_backups(
    app_dir: String,
    key: Vec<u8>,
    now_ms: i64,
    limit: u32,
) -> Result<Vec<db::CloudMediaBackup>> {
    let _key = key_from_bytes(key)?;
    let conn = db::open(Path::new(&app_dir))?;
    db::list_due_cloud_media_backups(&conn, now_ms, limit as i64)
}

#[flutter_rust_bridge::frb]
pub fn db_mark_cloud_media_backup_failed(
    app_dir: String,
    key: Vec<u8>,
    attachment_sha256: String,
    attempts: i64,
    next_retry_at_ms: i64,
    last_error: String,
    now_ms: i64,
) -> Result<()> {
    let _key = key_from_bytes(key)?;
    let conn = db::open(Path::new(&app_dir))?;
    db::mark_cloud_media_backup_failed(
        &conn,
        &attachment_sha256,
        attempts,
        next_retry_at_ms,
        &last_error,
        now_ms,
    )
}

#[flutter_rust_bridge::frb]
pub fn db_mark_cloud_media_backup_uploaded(
    app_dir: String,
    key: Vec<u8>,
    attachment_sha256: String,
    now_ms: i64,
) -> Result<()> {
    let _key = key_from_bytes(key)?;
    let conn = db::open(Path::new(&app_dir))?;
    db::mark_cloud_media_backup_uploaded(&conn, &attachment_sha256, now_ms)
}

#[flutter_rust_bridge::frb]
pub fn db_cloud_media_backup_summary(
    app_dir: String,
    key: Vec<u8>,
) -> Result<db::CloudMediaBackupSummary> {
    let _key = key_from_bytes(key)?;
    let conn = db::open(Path::new(&app_dir))?;
    db::cloud_media_backup_summary(&conn)
}

#[flutter_rust_bridge::frb]
pub fn db_reset_vault_data_preserving_llm_profiles(app_dir: String, key: Vec<u8>) -> Result<()> {
    let key = key_from_bytes(key)?;
    auth::validate_key(Path::new(&app_dir), &key)?;
    let conn = db::open(Path::new(&app_dir))?;
    db::reset_vault_data_preserving_llm_profiles(&conn)
}

#[flutter_rust_bridge::frb]
pub fn db_get_or_create_device_id(app_dir: String) -> Result<String> {
    let conn = db::open(Path::new(&app_dir))?;
    db::get_or_create_device_id(&conn)
}

#[flutter_rust_bridge::frb]
pub fn db_create_llm_profile(
    app_dir: String,
    key: Vec<u8>,
    name: String,
    provider_type: String,
    base_url: Option<String>,
    api_key: Option<String>,
    model_name: String,
    set_active: bool,
) -> Result<db::LlmProfile> {
    let key = key_from_bytes(key)?;
    let conn = db::open(Path::new(&app_dir))?;
    db::create_llm_profile(
        &conn,
        &key,
        &name,
        &provider_type,
        base_url.as_deref(),
        api_key.as_deref(),
        &model_name,
        set_active,
    )
}

#[flutter_rust_bridge::frb]
pub fn db_list_llm_profiles(app_dir: String, key: Vec<u8>) -> Result<Vec<db::LlmProfile>> {
    let _key = key_from_bytes(key)?;
    let conn = db::open(Path::new(&app_dir))?;
    db::list_llm_profiles(&conn)
}

#[flutter_rust_bridge::frb]
pub fn db_set_active_llm_profile(app_dir: String, key: Vec<u8>, profile_id: String) -> Result<()> {
    let _key = key_from_bytes(key)?;
    let conn = db::open(Path::new(&app_dir))?;
    db::set_active_llm_profile(&conn, &profile_id)
}

#[flutter_rust_bridge::frb]
pub fn db_delete_llm_profile(app_dir: String, key: Vec<u8>, profile_id: String) -> Result<()> {
    let _key = key_from_bytes(key)?;
    let conn = db::open(Path::new(&app_dir))?;
    db::delete_llm_profile(&conn, &profile_id)
}

#[flutter_rust_bridge::frb]
pub fn db_create_embedding_profile(
    app_dir: String,
    key: Vec<u8>,
    name: String,
    provider_type: String,
    base_url: Option<String>,
    api_key: Option<String>,
    model_name: String,
    set_active: bool,
) -> Result<db::EmbeddingProfile> {
    let key = key_from_bytes(key)?;
    let conn = db::open(Path::new(&app_dir))?;
    db::create_embedding_profile(
        &conn,
        &key,
        &name,
        &provider_type,
        base_url.as_deref(),
        api_key.as_deref(),
        &model_name,
        set_active,
    )
}

#[flutter_rust_bridge::frb]
pub fn db_list_embedding_profiles(
    app_dir: String,
    key: Vec<u8>,
) -> Result<Vec<db::EmbeddingProfile>> {
    let _key = key_from_bytes(key)?;
    let conn = db::open(Path::new(&app_dir))?;
    db::list_embedding_profiles(&conn)
}

#[flutter_rust_bridge::frb]
pub fn db_set_active_embedding_profile(
    app_dir: String,
    key: Vec<u8>,
    profile_id: String,
) -> Result<()> {
    let _key = key_from_bytes(key)?;
    let conn = db::open(Path::new(&app_dir))?;
    db::set_active_embedding_profile(&conn, &profile_id)
}

#[flutter_rust_bridge::frb]
pub fn db_delete_embedding_profile(
    app_dir: String,
    key: Vec<u8>,
    profile_id: String,
) -> Result<()> {
    let _key = key_from_bytes(key)?;
    let conn = db::open(Path::new(&app_dir))?;
    db::delete_embedding_profile(&conn, &profile_id)
}

#[flutter_rust_bridge::frb]
pub fn db_process_pending_message_embeddings(
    app_dir: String,
    key: Vec<u8>,
    limit: u32,
) -> Result<u32> {
    let key = key_from_bytes(key)?;
    let conn = db::open(Path::new(&app_dir))?;
    let processed = db::process_pending_message_embeddings_active(
        &conn,
        &key,
        Path::new(&app_dir),
        limit as usize,
    )?;
    Ok(processed as u32)
}

#[flutter_rust_bridge::frb]
pub fn db_process_pending_todo_thread_embeddings(
    app_dir: String,
    key: Vec<u8>,
    todo_limit: u32,
    activity_limit: u32,
) -> Result<u32> {
    let key = key_from_bytes(key)?;
    let conn = db::open(Path::new(&app_dir))?;
    let todos = db::process_pending_todo_embeddings_active(
        &conn,
        &key,
        Path::new(&app_dir),
        todo_limit as usize,
    )?;
    let activities = db::process_pending_todo_activity_embeddings_active(
        &conn,
        &key,
        Path::new(&app_dir),
        activity_limit as usize,
    )?;
    Ok(todos.saturating_add(activities) as u32)
}

#[flutter_rust_bridge::frb]
#[allow(clippy::too_many_arguments)]
pub fn db_process_pending_todo_thread_embeddings_cloud_gateway(
    app_dir: String,
    key: Vec<u8>,
    todo_limit: u32,
    activity_limit: u32,
    gateway_base_url: String,
    firebase_id_token: String,
    model_name: String,
) -> Result<u32> {
    let gateway_base_url = gateway_base_url.trim().to_string();
    if gateway_base_url.is_empty() {
        return Err(anyhow!("missing gateway_base_url"));
    }
    let firebase_id_token = firebase_id_token.trim().to_string();
    if firebase_id_token.is_empty() {
        return Err(anyhow!("missing firebase_id_token"));
    }
    let requested_model_name = model_name.trim().to_string();
    if requested_model_name.is_empty() {
        return Err(anyhow!("missing model_name"));
    }

    let key = key_from_bytes(key)?;
    let conn = db::open(Path::new(&app_dir))?;
    let embedder = embedding::CloudGatewayEmbedder::new(
        gateway_base_url.clone(),
        firebase_id_token.clone(),
        requested_model_name.clone(),
    );

    let mut dim: Option<usize> = None;
    let mut used_cache = false;

    if let Some(cache) = db::load_cloud_gateway_embeddings_cache(&conn)? {
        if cache.base_url == gateway_base_url && cache.requested_model_name == requested_model_name
        {
            embedder.seed_effective_model_id_and_dim(&cache.effective_model_id, cache.dim);
            dim = Some(cache.dim);
            used_cache = true;
        }
    }

    let dim = match dim {
        Some(dim) => dim,
        None => {
            // Avoid wiping the current index if the embedder is misconfigured/unreachable.
            let probe = embedder.embed(&["probe".to_string()])?;
            let dim = probe.first().map(|v| v.len()).unwrap_or(0);
            if dim == 0 {
                return Err(anyhow!("cloud-gateway embedder returned empty embeddings"));
            }
            db::store_cloud_gateway_embeddings_cache(
                &conn,
                &gateway_base_url,
                &requested_model_name,
                embedder.model_name(),
                dim,
            )?;
            dim
        }
    };

    db::set_active_embedding_model(&conn, embedder.model_name(), dim)?;

    let result = (|| -> Result<u32> {
        let todos =
            db::process_pending_todo_embeddings(&conn, &key, &embedder, todo_limit as usize)?;
        let activities = db::process_pending_todo_activity_embeddings(
            &conn,
            &key,
            &embedder,
            activity_limit as usize,
        )?;
        Ok(todos.saturating_add(activities) as u32)
    })();

    match result {
        Ok(v) => Ok(v),
        Err(e) => {
            let msg = e.to_string();
            if used_cache
                && (msg.contains("cloud-gateway embedding model_id mismatch")
                    || msg.contains("cloud-gateway embedding dim mismatch"))
            {
                // Model/dim changed upstream; re-probe and retry once.
                let fresh = embedding::CloudGatewayEmbedder::new(
                    gateway_base_url.clone(),
                    firebase_id_token.clone(),
                    requested_model_name.clone(),
                );

                let probe = fresh.embed(&["probe".to_string()])?;
                let dim = probe.first().map(|v| v.len()).unwrap_or(0);
                if dim == 0 {
                    return Err(anyhow!("cloud-gateway embedder returned empty embeddings"));
                }

                db::store_cloud_gateway_embeddings_cache(
                    &conn,
                    &gateway_base_url,
                    &requested_model_name,
                    fresh.model_name(),
                    dim,
                )?;
                db::set_active_embedding_model(&conn, fresh.model_name(), dim)?;

                let todos =
                    db::process_pending_todo_embeddings(&conn, &key, &fresh, todo_limit as usize)?;
                let activities = db::process_pending_todo_activity_embeddings(
                    &conn,
                    &key,
                    &fresh,
                    activity_limit as usize,
                )?;
                return Ok(todos.saturating_add(activities) as u32);
            }
            Err(e)
        }
    }
}

#[flutter_rust_bridge::frb]
pub fn db_process_pending_todo_thread_embeddings_brok(
    app_dir: String,
    key: Vec<u8>,
    todo_limit: u32,
    activity_limit: u32,
) -> Result<u32> {
    let key = key_from_bytes(key)?;
    let conn = db::open(Path::new(&app_dir))?;

    let (_profile_id, profile) = db::load_active_embedding_profile_config(&conn, &key)?
        .ok_or_else(|| anyhow!("no active embedding profile configured"))?;

    if profile.provider_type != "openai-compatible" {
        return Err(anyhow!(
            "unsupported embedding provider_type: {}",
            profile.provider_type
        ));
    }

    let base_url = profile
        .base_url
        .filter(|v| !v.trim().is_empty())
        .ok_or_else(|| anyhow!("missing embedding base_url"))?;
    let api_key = profile
        .api_key
        .filter(|v| !v.trim().is_empty())
        .ok_or_else(|| anyhow!("missing embedding api_key"))?;
    let model_name = profile.model_name;

    let embedder = embedding::BrokEmbedder::new(base_url, api_key, model_name);
    let cached_dim = db::lookup_embedding_space_dim(&conn, embedder.model_name())?;
    let used_cache = cached_dim.is_some();

    let dim = match cached_dim {
        Some(dim) => dim,
        None => {
            // Avoid wiping the current index if the embedder is misconfigured/unreachable.
            let probe = embedder.embed(&["probe".to_string()])?;
            let dim = probe.first().map(|v| v.len()).unwrap_or(0);
            if dim == 0 {
                return Err(anyhow!("brok embedder returned empty embeddings"));
            }
            dim
        }
    };

    db::set_active_embedding_model(&conn, embedder.model_name(), dim)?;

    let result = (|| -> Result<u32> {
        let todos =
            db::process_pending_todo_embeddings(&conn, &key, &embedder, todo_limit as usize)?;
        let activities = db::process_pending_todo_activity_embeddings(
            &conn,
            &key,
            &embedder,
            activity_limit as usize,
        )?;
        Ok(todos.saturating_add(activities) as u32)
    })();

    match result {
        Ok(v) => Ok(v),
        Err(e) => {
            let msg = e.to_string();
            if used_cache && msg.contains("embedder dim mismatch") {
                // Dim likely changed for the same model_name; retry once with the actual dim.
                let actual_dim = embedder.dim();
                if actual_dim > 0 && actual_dim <= 8192 && actual_dim != dim {
                    db::set_active_embedding_model(&conn, embedder.model_name(), actual_dim)?;
                    let todos = db::process_pending_todo_embeddings(
                        &conn,
                        &key,
                        &embedder,
                        todo_limit as usize,
                    )?;
                    let activities = db::process_pending_todo_activity_embeddings(
                        &conn,
                        &key,
                        &embedder,
                        activity_limit as usize,
                    )?;
                    return Ok(todos.saturating_add(activities) as u32);
                }
            }
            Err(e)
        }
    }
}

#[flutter_rust_bridge::frb]
pub fn db_search_similar_messages(
    app_dir: String,
    key: Vec<u8>,
    query: String,
    top_k: u32,
) -> Result<Vec<db::SimilarMessage>> {
    let key = key_from_bytes(key)?;
    let conn = db::open(Path::new(&app_dir))?;
    db::search_similar_messages_active(&conn, &key, Path::new(&app_dir), &query, top_k as usize)
}

#[flutter_rust_bridge::frb]
#[allow(clippy::too_many_arguments)]
pub fn db_search_similar_messages_cloud_gateway(
    app_dir: String,
    key: Vec<u8>,
    query: String,
    top_k: u32,
    gateway_base_url: String,
    firebase_id_token: String,
    model_name: String,
) -> Result<Vec<db::SimilarMessage>> {
    if gateway_base_url.trim().is_empty() {
        return Err(anyhow!("missing gateway_base_url"));
    }
    if firebase_id_token.trim().is_empty() {
        return Err(anyhow!("missing firebase_id_token"));
    }
    if model_name.trim().is_empty() {
        return Err(anyhow!("missing model_name"));
    }

    let key = key_from_bytes(key)?;
    let conn = db::open(Path::new(&app_dir))?;
    let embedder =
        embedding::CloudGatewayEmbedder::new(gateway_base_url, firebase_id_token, model_name);

    // Avoid wiping the current index if the embedder is misconfigured/unreachable.
    let probe = embedder.embed(&[format!("query: {query}")])?;
    let dim = probe.first().map(|v| v.len()).unwrap_or(0);
    if dim == 0 {
        return Err(anyhow!("cloud-gateway embedder returned empty embeddings"));
    }

    // Best-effort: keep the index reasonably fresh without blocking too long.
    db::set_active_embedding_model(&conn, embedder.model_name(), dim)?;
    db::process_pending_message_embeddings(&conn, &key, &embedder, 64)?;
    db::process_pending_todo_embeddings(&conn, &key, &embedder, 64)?;
    db::process_pending_todo_activity_embeddings(&conn, &key, &embedder, 128)?;

    db::search_similar_messages(&conn, &key, &embedder, &query, top_k as usize)
}

#[flutter_rust_bridge::frb]
pub fn db_search_similar_messages_brok(
    app_dir: String,
    key: Vec<u8>,
    query: String,
    top_k: u32,
) -> Result<Vec<db::SimilarMessage>> {
    let key = key_from_bytes(key)?;
    let conn = db::open(Path::new(&app_dir))?;

    let (_profile_id, profile) = db::load_active_embedding_profile_config(&conn, &key)?
        .ok_or_else(|| anyhow!("no active embedding profile configured"))?;

    if profile.provider_type != "openai-compatible" {
        return Err(anyhow!(
            "unsupported embedding provider_type: {}",
            profile.provider_type
        ));
    }

    let base_url = profile
        .base_url
        .filter(|v| !v.trim().is_empty())
        .ok_or_else(|| anyhow!("missing embedding base_url"))?;
    let api_key = profile
        .api_key
        .filter(|v| !v.trim().is_empty())
        .ok_or_else(|| anyhow!("missing embedding api_key"))?;
    let model_name = profile.model_name;

    let embedder = embedding::BrokEmbedder::new(base_url, api_key, model_name);

    // Avoid wiping the current index if the embedder is misconfigured/unreachable.
    let probe = embedder.embed(&[format!("query: {query}")])?;
    let dim = probe.first().map(|v| v.len()).unwrap_or(0);
    if dim == 0 {
        return Err(anyhow!("brok embedder returned empty embeddings"));
    }

    // Best-effort: keep the index reasonably fresh without blocking too long.
    db::set_active_embedding_model(&conn, embedder.model_name(), dim)?;
    db::process_pending_message_embeddings(&conn, &key, &embedder, 64)?;
    db::process_pending_todo_embeddings(&conn, &key, &embedder, 64)?;
    db::process_pending_todo_activity_embeddings(&conn, &key, &embedder, 128)?;

    db::search_similar_messages(&conn, &key, &embedder, &query, top_k as usize)
}

#[flutter_rust_bridge::frb]
pub fn db_search_similar_todo_threads(
    app_dir: String,
    key: Vec<u8>,
    query: String,
    top_k: u32,
) -> Result<Vec<db::SimilarTodoThread>> {
    let key = key_from_bytes(key)?;
    let conn = db::open(Path::new(&app_dir))?;
    db::search_similar_todo_threads_active(&conn, &key, Path::new(&app_dir), &query, top_k as usize)
}

#[flutter_rust_bridge::frb]
#[allow(clippy::too_many_arguments)]
pub fn db_search_similar_todo_threads_cloud_gateway(
    app_dir: String,
    key: Vec<u8>,
    query: String,
    top_k: u32,
    gateway_base_url: String,
    firebase_id_token: String,
    model_name: String,
) -> Result<Vec<db::SimilarTodoThread>> {
    if gateway_base_url.trim().is_empty() {
        return Err(anyhow!("missing gateway_base_url"));
    }
    if firebase_id_token.trim().is_empty() {
        return Err(anyhow!("missing firebase_id_token"));
    }
    if model_name.trim().is_empty() {
        return Err(anyhow!("missing model_name"));
    }

    let _key = key_from_bytes(key)?;
    let conn = db::open(Path::new(&app_dir))?;
    let embedder =
        embedding::CloudGatewayEmbedder::new(gateway_base_url, firebase_id_token, model_name);

    // Avoid wiping the current index if the embedder is misconfigured/unreachable.
    let mut vectors = embedder.embed(&[format!("query: {query}")])?;
    if vectors.len() != 1 {
        return Err(anyhow!(
            "cloud-gateway embedder output length mismatch: expected 1, got {}",
            vectors.len()
        ));
    }
    let dim = vectors.first().map(|v| v.len()).unwrap_or(0);
    if dim == 0 {
        return Err(anyhow!("cloud-gateway embedder returned empty embeddings"));
    }
    let query_vector = vectors.pop().unwrap();

    db::set_active_embedding_model(&conn, embedder.model_name(), dim)?;
    db::search_similar_todo_threads_by_embedding(
        &conn,
        embedder.model_name(),
        &query_vector,
        top_k as usize,
    )
}

#[flutter_rust_bridge::frb]
pub fn db_search_similar_todo_threads_brok(
    app_dir: String,
    key: Vec<u8>,
    query: String,
    top_k: u32,
) -> Result<Vec<db::SimilarTodoThread>> {
    let key = key_from_bytes(key)?;
    let conn = db::open(Path::new(&app_dir))?;

    let (_profile_id, profile) = db::load_active_embedding_profile_config(&conn, &key)?
        .ok_or_else(|| anyhow!("no active embedding profile configured"))?;

    if profile.provider_type != "openai-compatible" {
        return Err(anyhow!(
            "unsupported embedding provider_type: {}",
            profile.provider_type
        ));
    }

    let base_url = profile
        .base_url
        .filter(|v| !v.trim().is_empty())
        .ok_or_else(|| anyhow!("missing embedding base_url"))?;
    let api_key = profile
        .api_key
        .filter(|v| !v.trim().is_empty())
        .ok_or_else(|| anyhow!("missing embedding api_key"))?;
    let model_name = profile.model_name;

    let embedder = embedding::BrokEmbedder::new(base_url, api_key, model_name);

    // Avoid wiping the current index if the embedder is misconfigured/unreachable.
    let mut vectors = embedder.embed(&[format!("query: {query}")])?;
    if vectors.len() != 1 {
        return Err(anyhow!(
            "brok embedder output length mismatch: expected 1, got {}",
            vectors.len()
        ));
    }
    let dim = vectors.first().map(|v| v.len()).unwrap_or(0);
    if dim == 0 {
        return Err(anyhow!("brok embedder returned empty embeddings"));
    }
    let query_vector = vectors.pop().unwrap();

    db::set_active_embedding_model(&conn, embedder.model_name(), dim)?;
    db::search_similar_todo_threads_by_embedding(
        &conn,
        embedder.model_name(),
        &query_vector,
        top_k as usize,
    )
}

#[flutter_rust_bridge::frb]
pub fn db_rebuild_message_embeddings(
    app_dir: String,
    key: Vec<u8>,
    batch_limit: u32,
) -> Result<u32> {
    let key = key_from_bytes(key)?;
    let conn = db::open(Path::new(&app_dir))?;
    let rebuilt = db::rebuild_message_embeddings_active(
        &conn,
        &key,
        Path::new(&app_dir),
        batch_limit as usize,
    )?;
    Ok(rebuilt as u32)
}

#[flutter_rust_bridge::frb]
pub fn db_list_embedding_model_names(app_dir: String, key: Vec<u8>) -> Result<Vec<String>> {
    let _key = key_from_bytes(key)?;
    let _conn = db::open(Path::new(&app_dir))?;

    let mut models = vec![embedding::DEFAULT_MODEL_NAME.to_string()];
    if cfg!(any(
        target_os = "windows",
        target_os = "macos",
        target_os = "linux"
    )) {
        models.push(embedding::PRODUCTION_MODEL_NAME.to_string());
    }
    Ok(models)
}

#[flutter_rust_bridge::frb]
pub fn db_get_active_embedding_model_name(app_dir: String, key: Vec<u8>) -> Result<String> {
    let _key = key_from_bytes(key)?;
    let conn = db::open(Path::new(&app_dir))?;

    let stored = db::get_active_embedding_model_name(&conn)?;
    let model_name = stored
        .as_deref()
        .map(normalize_embedding_model_name)
        .unwrap_or_else(default_embedding_model_name_for_platform);
    Ok(model_name.to_string())
}

#[flutter_rust_bridge::frb]
pub fn db_set_active_embedding_model_name(
    app_dir: String,
    key: Vec<u8>,
    model_name: String,
) -> Result<bool> {
    let _key = key_from_bytes(key)?;
    let conn = db::open(Path::new(&app_dir))?;

    let desired = match model_name.as_str() {
        embedding::DEFAULT_MODEL_NAME => embedding::DEFAULT_MODEL_NAME,
        embedding::PRODUCTION_MODEL_NAME => {
            if cfg!(any(
                target_os = "windows",
                target_os = "macos",
                target_os = "linux"
            )) {
                embedding::PRODUCTION_MODEL_NAME
            } else {
                return Err(anyhow!(
                    "production embeddings are not supported on this platform"
                ));
            }
        }
        _ => return Err(anyhow!("unknown embedding model: {model_name}")),
    };

    db::set_active_embedding_model_name(&conn, desired)
}

#[flutter_rust_bridge::frb]
#[allow(clippy::too_many_arguments)]
pub fn db_record_llm_usage_daily(
    app_dir: String,
    key: Vec<u8>,
    day: String,
    profile_id: String,
    purpose: String,
    input_tokens: Option<i64>,
    output_tokens: Option<i64>,
    total_tokens: Option<i64>,
) -> Result<()> {
    let _key = key_from_bytes(key)?;
    let conn = db::open(Path::new(&app_dir))?;
    db::record_llm_usage_daily(
        &conn,
        day.trim(),
        &profile_id,
        &purpose,
        input_tokens,
        output_tokens,
        total_tokens,
    )
}

#[flutter_rust_bridge::frb]
pub fn db_sum_llm_usage_daily_by_purpose(
    app_dir: String,
    key: Vec<u8>,
    profile_id: String,
    start_day: String,
    end_day: String,
) -> Result<Vec<db::LlmUsageAggregate>> {
    let _key = key_from_bytes(key)?;
    let conn = db::open(Path::new(&app_dir))?;
    db::sum_llm_usage_daily_by_purpose(&conn, &profile_id, start_day.trim(), end_day.trim())
}

#[flutter_rust_bridge::frb]
#[allow(clippy::too_many_arguments)]
pub fn ai_semantic_parse_message_action(
    app_dir: String,
    key: Vec<u8>,
    text: String,
    now_local_iso: String,
    locale: String,
    day_end_minutes: i32,
    candidates: Vec<semantic_parse::TodoCandidate>,
    local_day: String,
) -> Result<String> {
    let result = (|| -> Result<String> {
        let key = key_from_bytes(key)?;
        let conn = db::open(Path::new(&app_dir))?;

        let (profile_id, profile) = db::load_active_llm_profile_config(&conn, &key)?
            .ok_or_else(|| anyhow!("no active LLM profile configured"))?;

        let provider = llm::answer_provider_from_profile(&profile)?;
        let result = semantic_parse::semantic_parse_message_action_json(
            provider.as_ref(),
            &text,
            now_local_iso.trim(),
            locale.trim(),
            day_end_minutes,
            &candidates,
        );

        match result {
            Ok(json) => {
                let day = local_day.trim();
                if !day.is_empty() {
                    let _ = db::record_llm_usage_daily(
                        &conn,
                        day,
                        &profile_id,
                        "semantic_parse",
                        None,
                        None,
                        None,
                    );
                }
                Ok(json)
            }
            Err(e) => {
                let day = local_day.trim();
                if !day.is_empty() {
                    let _ = db::record_llm_usage_daily(
                        &conn,
                        day,
                        &profile_id,
                        "semantic_parse",
                        None,
                        None,
                        None,
                    );
                }
                Err(e)
            }
        }
    })();

    result
}

#[flutter_rust_bridge::frb]
#[allow(clippy::too_many_arguments)]
pub fn ai_semantic_parse_message_action_cloud_gateway(
    app_dir: String,
    key: Vec<u8>,
    text: String,
    now_local_iso: String,
    locale: String,
    day_end_minutes: i32,
    candidates: Vec<semantic_parse::TodoCandidate>,
    gateway_base_url: String,
    firebase_id_token: String,
    model_name: String,
) -> Result<String> {
    if gateway_base_url.trim().is_empty() {
        return Err(anyhow!("missing gateway_base_url"));
    }
    if firebase_id_token.trim().is_empty() {
        return Err(anyhow!("missing firebase_id_token"));
    }

    let _key = key_from_bytes(key)?;
    let _conn = db::open(Path::new(&app_dir))?;

    let provider = llm::gateway::CloudGatewayProvider::new_with_purpose(
        gateway_base_url,
        firebase_id_token,
        model_name,
        None,
        "semantic_parse".to_string(),
    );

    semantic_parse::semantic_parse_message_action_json(
        &provider,
        &text,
        now_local_iso.trim(),
        locale.trim(),
        day_end_minutes,
        &candidates,
    )
}

#[flutter_rust_bridge::frb]
pub fn ai_semantic_parse_ask_ai_time_window(
    app_dir: String,
    key: Vec<u8>,
    question: String,
    now_local_iso: String,
    locale: String,
    first_day_of_week_index: i32,
    local_day: String,
) -> Result<String> {
    let result = (|| -> Result<String> {
        let key = key_from_bytes(key)?;
        let conn = db::open(Path::new(&app_dir))?;

        let (profile_id, profile) = db::load_active_llm_profile_config(&conn, &key)?
            .ok_or_else(|| anyhow!("no active LLM profile configured"))?;

        let provider = llm::answer_provider_from_profile(&profile)?;
        let result = semantic_parse::semantic_parse_ask_ai_time_window_json(
            provider.as_ref(),
            &question,
            now_local_iso.trim(),
            locale.trim(),
            first_day_of_week_index,
        );

        match result {
            Ok(json) => {
                let day = local_day.trim();
                if !day.is_empty() {
                    let _ = db::record_llm_usage_daily(
                        &conn,
                        day,
                        &profile_id,
                        "semantic_parse",
                        None,
                        None,
                        None,
                    );
                }
                Ok(json)
            }
            Err(e) => {
                let day = local_day.trim();
                if !day.is_empty() {
                    let _ = db::record_llm_usage_daily(
                        &conn,
                        day,
                        &profile_id,
                        "semantic_parse",
                        None,
                        None,
                        None,
                    );
                }
                Err(e)
            }
        }
    })();

    result
}

#[flutter_rust_bridge::frb]
#[allow(clippy::too_many_arguments)]
pub fn ai_semantic_parse_ask_ai_time_window_cloud_gateway(
    app_dir: String,
    key: Vec<u8>,
    question: String,
    now_local_iso: String,
    locale: String,
    first_day_of_week_index: i32,
    gateway_base_url: String,
    firebase_id_token: String,
    model_name: String,
) -> Result<String> {
    if gateway_base_url.trim().is_empty() {
        return Err(anyhow!("missing gateway_base_url"));
    }
    if firebase_id_token.trim().is_empty() {
        return Err(anyhow!("missing firebase_id_token"));
    }

    let _key = key_from_bytes(key)?;
    let _conn = db::open(Path::new(&app_dir))?;

    let provider = llm::gateway::CloudGatewayProvider::new_with_purpose(
        gateway_base_url,
        firebase_id_token,
        model_name,
        None,
        "semantic_parse".to_string(),
    );

    semantic_parse::semantic_parse_ask_ai_time_window_json(
        &provider,
        &question,
        now_local_iso.trim(),
        locale.trim(),
        first_day_of_week_index,
    )
}

#[flutter_rust_bridge::frb]
pub fn rag_ask_ai_stream(
    app_dir: String,
    key: Vec<u8>,
    conversation_id: String,
    question: String,
    top_k: u32,
    this_thread_only: bool,
    local_day: String,
    sink: StreamSink<String>,
) -> Result<()> {
    let result = (|| -> Result<()> {
        let key = key_from_bytes(key)?;
        let conn = db::open(Path::new(&app_dir))?;

        let (profile_id, profile) = db::load_active_llm_profile_config(&conn, &key)?
            .ok_or_else(|| anyhow!("no active LLM profile configured"))?;

        let focus = if this_thread_only {
            rag::Focus::ThisThread
        } else {
            rag::Focus::AllMemories
        };

        let provider = llm::answer_provider_from_profile(&profile)?;
        let result = rag::ask_ai_with_provider_using_active_embeddings(
            &conn,
            &key,
            Path::new(&app_dir),
            &conversation_id,
            &question,
            top_k as usize,
            focus,
            provider.as_ref(),
            &mut |ev| {
                emit_ask_ai_meta_if_any(&sink, ev.role.as_deref())?;
                if ev.done {
                    if sink.add(String::new()).is_err() {
                        return Err(rag::StreamCancelled.into());
                    }
                    return Ok(());
                }
                if ev.text_delta.is_empty() {
                    return Ok(());
                }
                if sink.add(ev.text_delta).is_err() {
                    return Err(rag::StreamCancelled.into());
                }
                Ok(())
            },
        )
        .map(|_| ());

        match result {
            Ok(()) => {
                let day = local_day.trim();
                if !day.is_empty() {
                    let _ = db::record_llm_usage_daily(
                        &conn,
                        day,
                        &profile_id,
                        "ask_ai",
                        None,
                        None,
                        None,
                    );
                }
                Ok(())
            }
            Err(e) if e.is::<rag::StreamCancelled>() => Ok(()),
            Err(e) => {
                let day = local_day.trim();
                if !day.is_empty() {
                    let _ = db::record_llm_usage_daily(
                        &conn,
                        day,
                        &profile_id,
                        "ask_ai",
                        None,
                        None,
                        None,
                    );
                }
                Err(e)
            }
        }
    })();

    finish_ask_ai_stream(&sink, result)
}

#[flutter_rust_bridge::frb]
#[allow(clippy::too_many_arguments)]
pub fn rag_ask_ai_stream_time_window(
    app_dir: String,
    key: Vec<u8>,
    conversation_id: String,
    question: String,
    top_k: u32,
    this_thread_only: bool,
    time_start_ms: i64,
    time_end_ms: i64,
    local_day: String,
    sink: StreamSink<String>,
) -> Result<()> {
    let result = (|| -> Result<()> {
        let key = key_from_bytes(key)?;
        let conn = db::open(Path::new(&app_dir))?;

        let (profile_id, profile) = db::load_active_llm_profile_config(&conn, &key)?
            .ok_or_else(|| anyhow!("no active LLM profile configured"))?;

        let focus = if this_thread_only {
            rag::Focus::ThisThread
        } else {
            rag::Focus::AllMemories
        };

        let provider = llm::answer_provider_from_profile(&profile)?;
        let result = rag::ask_ai_with_provider_using_active_embeddings_time_window(
            &conn,
            &key,
            Path::new(&app_dir),
            &conversation_id,
            &question,
            top_k as usize,
            focus,
            time_start_ms,
            time_end_ms,
            provider.as_ref(),
            &mut |ev| {
                emit_ask_ai_meta_if_any(&sink, ev.role.as_deref())?;
                if ev.done {
                    if sink.add(String::new()).is_err() {
                        return Err(rag::StreamCancelled.into());
                    }
                    return Ok(());
                }
                if ev.text_delta.is_empty() {
                    return Ok(());
                }
                if sink.add(ev.text_delta).is_err() {
                    return Err(rag::StreamCancelled.into());
                }
                Ok(())
            },
        )
        .map(|_| ());

        match result {
            Ok(()) => {
                let day = local_day.trim();
                if !day.is_empty() {
                    let _ = db::record_llm_usage_daily(
                        &conn,
                        day,
                        &profile_id,
                        "ask_ai",
                        None,
                        None,
                        None,
                    );
                }
                Ok(())
            }
            Err(e) if e.is::<rag::StreamCancelled>() => Ok(()),
            Err(e) => {
                let day = local_day.trim();
                if !day.is_empty() {
                    let _ = db::record_llm_usage_daily(
                        &conn,
                        day,
                        &profile_id,
                        "ask_ai",
                        None,
                        None,
                        None,
                    );
                }
                Err(e)
            }
        }
    })();

    finish_ask_ai_stream(&sink, result)
}

#[flutter_rust_bridge::frb]
pub fn rag_ask_ai_stream_with_brok_embeddings(
    app_dir: String,
    key: Vec<u8>,
    conversation_id: String,
    question: String,
    top_k: u32,
    this_thread_only: bool,
    local_day: String,
    sink: StreamSink<String>,
) -> Result<()> {
    let result = (|| -> Result<()> {
        let key = key_from_bytes(key)?;
        let conn = db::open(Path::new(&app_dir))?;

        let (profile_id, profile) = db::load_active_llm_profile_config(&conn, &key)?
            .ok_or_else(|| anyhow!("no active LLM profile configured"))?;

        let (_emb_profile_id, emb_profile) = db::load_active_embedding_profile_config(&conn, &key)?
            .ok_or_else(|| anyhow!("no active embedding profile configured"))?;

        if emb_profile.provider_type != "openai-compatible" {
            return Err(anyhow!(
                "unsupported embedding provider_type: {}",
                emb_profile.provider_type
            ));
        }

        let embeddings_base_url = emb_profile
            .base_url
            .filter(|v| !v.trim().is_empty())
            .ok_or_else(|| anyhow!("missing embedding base_url"))?;
        let embeddings_api_key = emb_profile
            .api_key
            .filter(|v| !v.trim().is_empty())
            .ok_or_else(|| anyhow!("missing embedding api_key"))?;
        let embeddings_model_name = emb_profile.model_name;

        let embedder = embedding::BrokEmbedder::new(
            embeddings_base_url,
            embeddings_api_key,
            embeddings_model_name,
        );

        let focus = if this_thread_only {
            rag::Focus::ThisThread
        } else {
            rag::Focus::AllMemories
        };

        let provider = llm::answer_provider_from_profile(&profile)?;

        let result = rag::ask_ai_with_provider_using_embedder(
            &conn,
            &key,
            &embedder,
            &conversation_id,
            &question,
            top_k as usize,
            focus,
            provider.as_ref(),
            &mut |ev| {
                emit_ask_ai_meta_if_any(&sink, ev.role.as_deref())?;
                if ev.done {
                    if sink.add(String::new()).is_err() {
                        return Err(rag::StreamCancelled.into());
                    }
                    return Ok(());
                }
                if ev.text_delta.is_empty() {
                    return Ok(());
                }
                if sink.add(ev.text_delta).is_err() {
                    return Err(rag::StreamCancelled.into());
                }
                Ok(())
            },
        )
        .map(|_| ());

        match result {
            Ok(()) => {
                let day = local_day.trim();
                if !day.is_empty() {
                    let _ = db::record_llm_usage_daily(
                        &conn,
                        day,
                        &profile_id,
                        "ask_ai",
                        None,
                        None,
                        None,
                    );
                }
                Ok(())
            }
            Err(e) if e.is::<rag::StreamCancelled>() => Ok(()),
            Err(e) => {
                let day = local_day.trim();
                if !day.is_empty() {
                    let _ = db::record_llm_usage_daily(
                        &conn,
                        day,
                        &profile_id,
                        "ask_ai",
                        None,
                        None,
                        None,
                    );
                }
                Err(e)
            }
        }
    })();

    finish_ask_ai_stream(&sink, result)
}

#[flutter_rust_bridge::frb]
#[allow(clippy::too_many_arguments)]
pub fn rag_ask_ai_stream_with_brok_embeddings_time_window(
    app_dir: String,
    key: Vec<u8>,
    conversation_id: String,
    question: String,
    top_k: u32,
    this_thread_only: bool,
    time_start_ms: i64,
    time_end_ms: i64,
    local_day: String,
    sink: StreamSink<String>,
) -> Result<()> {
    let result = (|| -> Result<()> {
        let key = key_from_bytes(key)?;
        let conn = db::open(Path::new(&app_dir))?;

        let (profile_id, profile) = db::load_active_llm_profile_config(&conn, &key)?
            .ok_or_else(|| anyhow!("no active LLM profile configured"))?;

        let focus = if this_thread_only {
            rag::Focus::ThisThread
        } else {
            rag::Focus::AllMemories
        };

        let provider = llm::answer_provider_from_profile(&profile)?;

        let result = rag::ask_ai_with_provider_using_active_embeddings_time_window(
            &conn,
            &key,
            Path::new(&app_dir),
            &conversation_id,
            &question,
            top_k as usize,
            focus,
            time_start_ms,
            time_end_ms,
            provider.as_ref(),
            &mut |ev| {
                emit_ask_ai_meta_if_any(&sink, ev.role.as_deref())?;
                if ev.done {
                    if sink.add(String::new()).is_err() {
                        return Err(rag::StreamCancelled.into());
                    }
                    return Ok(());
                }
                if ev.text_delta.is_empty() {
                    return Ok(());
                }
                if sink.add(ev.text_delta).is_err() {
                    return Err(rag::StreamCancelled.into());
                }
                Ok(())
            },
        )
        .map(|_| ());

        match result {
            Ok(()) => {
                let day = local_day.trim();
                if !day.is_empty() {
                    let _ = db::record_llm_usage_daily(
                        &conn,
                        day,
                        &profile_id,
                        "ask_ai",
                        None,
                        None,
                        None,
                    );
                }
                Ok(())
            }
            Err(e) if e.is::<rag::StreamCancelled>() => Ok(()),
            Err(e) => {
                let day = local_day.trim();
                if !day.is_empty() {
                    let _ = db::record_llm_usage_daily(
                        &conn,
                        day,
                        &profile_id,
                        "ask_ai",
                        None,
                        None,
                        None,
                    );
                }
                Err(e)
            }
        }
    })();

    finish_ask_ai_stream(&sink, result)
}

#[allow(clippy::too_many_arguments)]
#[flutter_rust_bridge::frb]
pub fn rag_ask_ai_stream_cloud_gateway(
    app_dir: String,
    key: Vec<u8>,
    conversation_id: String,
    question: String,
    top_k: u32,
    this_thread_only: bool,
    gateway_base_url: String,
    firebase_id_token: String,
    model_name: String,
    sink: StreamSink<String>,
) -> Result<()> {
    let result = (|| -> Result<()> {
        if gateway_base_url.trim().is_empty() {
            return Err(anyhow!("missing gateway_base_url"));
        }
        if firebase_id_token.trim().is_empty() {
            return Err(anyhow!("missing firebase_id_token"));
        }

        let key = key_from_bytes(key)?;
        let conn = db::open(Path::new(&app_dir))?;

        let focus = if this_thread_only {
            rag::Focus::ThisThread
        } else {
            rag::Focus::AllMemories
        };

        let provider = llm::gateway::CloudGatewayProvider::new(
            gateway_base_url,
            firebase_id_token,
            model_name,
            None,
        );

        let result = rag::ask_ai_with_provider_using_active_embeddings(
            &conn,
            &key,
            Path::new(&app_dir),
            &conversation_id,
            &question,
            top_k as usize,
            focus,
            &provider,
            &mut |ev| {
                emit_ask_ai_meta_if_any(&sink, ev.role.as_deref())?;
                if ev.done {
                    if sink.add(String::new()).is_err() {
                        return Err(rag::StreamCancelled.into());
                    }
                    return Ok(());
                }
                if ev.text_delta.is_empty() {
                    return Ok(());
                }
                if sink.add(ev.text_delta).is_err() {
                    return Err(rag::StreamCancelled.into());
                }
                Ok(())
            },
        )
        .map(|_| ());

        match result {
            Ok(()) => Ok(()),
            Err(e) if e.is::<rag::StreamCancelled>() => Ok(()),
            Err(e) => Err(e),
        }
    })();

    finish_ask_ai_stream(&sink, result)
}

#[allow(clippy::too_many_arguments)]
#[flutter_rust_bridge::frb]
pub fn rag_ask_ai_stream_cloud_gateway_time_window(
    app_dir: String,
    key: Vec<u8>,
    conversation_id: String,
    question: String,
    top_k: u32,
    this_thread_only: bool,
    time_start_ms: i64,
    time_end_ms: i64,
    gateway_base_url: String,
    firebase_id_token: String,
    model_name: String,
    sink: StreamSink<String>,
) -> Result<()> {
    let result = (|| -> Result<()> {
        if gateway_base_url.trim().is_empty() {
            return Err(anyhow!("missing gateway_base_url"));
        }
        if firebase_id_token.trim().is_empty() {
            return Err(anyhow!("missing firebase_id_token"));
        }

        let key = key_from_bytes(key)?;
        let conn = db::open(Path::new(&app_dir))?;

        let focus = if this_thread_only {
            rag::Focus::ThisThread
        } else {
            rag::Focus::AllMemories
        };

        let provider = llm::gateway::CloudGatewayProvider::new(
            gateway_base_url,
            firebase_id_token,
            model_name,
            None,
        );

        let result = rag::ask_ai_with_provider_using_active_embeddings_time_window(
            &conn,
            &key,
            Path::new(&app_dir),
            &conversation_id,
            &question,
            top_k as usize,
            focus,
            time_start_ms,
            time_end_ms,
            &provider,
            &mut |ev| {
                emit_ask_ai_meta_if_any(&sink, ev.role.as_deref())?;
                if ev.done {
                    if sink.add(String::new()).is_err() {
                        return Err(rag::StreamCancelled.into());
                    }
                    return Ok(());
                }
                if ev.text_delta.is_empty() {
                    return Ok(());
                }
                if sink.add(ev.text_delta).is_err() {
                    return Err(rag::StreamCancelled.into());
                }
                Ok(())
            },
        )
        .map(|_| ());

        match result {
            Ok(()) => Ok(()),
            Err(e) if e.is::<rag::StreamCancelled>() => Ok(()),
            Err(e) => Err(e),
        }
    })();

    finish_ask_ai_stream(&sink, result)
}

#[allow(clippy::too_many_arguments)]
#[flutter_rust_bridge::frb]
pub fn rag_ask_ai_stream_cloud_gateway_with_embeddings(
    app_dir: String,
    key: Vec<u8>,
    conversation_id: String,
    question: String,
    top_k: u32,
    this_thread_only: bool,
    gateway_base_url: String,
    firebase_id_token: String,
    model_name: String,
    embeddings_model_name: String,
    sink: StreamSink<String>,
) -> Result<()> {
    let result = (|| -> Result<()> {
        if gateway_base_url.trim().is_empty() {
            return Err(anyhow!("missing gateway_base_url"));
        }
        if firebase_id_token.trim().is_empty() {
            return Err(anyhow!("missing firebase_id_token"));
        }
        if embeddings_model_name.trim().is_empty() {
            return Err(anyhow!("missing embeddings_model_name"));
        }

        let key = key_from_bytes(key)?;
        let conn = db::open(Path::new(&app_dir))?;

        let focus = if this_thread_only {
            rag::Focus::ThisThread
        } else {
            rag::Focus::AllMemories
        };

        let embedder = embedding::CloudGatewayEmbedder::new(
            gateway_base_url.clone(),
            firebase_id_token.clone(),
            embeddings_model_name,
        );
        let provider = llm::gateway::CloudGatewayProvider::new(
            gateway_base_url,
            firebase_id_token,
            model_name,
            None,
        );

        let result = rag::ask_ai_with_provider_using_embedder(
            &conn,
            &key,
            &embedder,
            &conversation_id,
            &question,
            top_k as usize,
            focus,
            &provider,
            &mut |ev| {
                emit_ask_ai_meta_if_any(&sink, ev.role.as_deref())?;
                if ev.done {
                    if sink.add(String::new()).is_err() {
                        return Err(rag::StreamCancelled.into());
                    }
                    return Ok(());
                }
                if ev.text_delta.is_empty() {
                    return Ok(());
                }
                if sink.add(ev.text_delta).is_err() {
                    return Err(rag::StreamCancelled.into());
                }
                Ok(())
            },
        )
        .map(|_| ());

        match result {
            Ok(()) => Ok(()),
            Err(e) if e.is::<rag::StreamCancelled>() => Ok(()),
            Err(e) => Err(e),
        }
    })();

    finish_ask_ai_stream(&sink, result)
}

#[allow(clippy::too_many_arguments)]
#[flutter_rust_bridge::frb]
pub fn rag_ask_ai_stream_cloud_gateway_with_embeddings_time_window(
    app_dir: String,
    key: Vec<u8>,
    conversation_id: String,
    question: String,
    top_k: u32,
    this_thread_only: bool,
    time_start_ms: i64,
    time_end_ms: i64,
    gateway_base_url: String,
    firebase_id_token: String,
    model_name: String,
    embeddings_model_name: String,
    sink: StreamSink<String>,
) -> Result<()> {
    let result = (|| -> Result<()> {
        if gateway_base_url.trim().is_empty() {
            return Err(anyhow!("missing gateway_base_url"));
        }
        if firebase_id_token.trim().is_empty() {
            return Err(anyhow!("missing firebase_id_token"));
        }
        if embeddings_model_name.trim().is_empty() {
            return Err(anyhow!("missing embeddings_model_name"));
        }

        let key = key_from_bytes(key)?;
        let conn = db::open(Path::new(&app_dir))?;

        let focus = if this_thread_only {
            rag::Focus::ThisThread
        } else {
            rag::Focus::AllMemories
        };

        // Time-window RAG doesn't need remote embeddings; keep the signature for Flutter routing parity.
        let provider = llm::gateway::CloudGatewayProvider::new(
            gateway_base_url,
            firebase_id_token,
            model_name,
            None,
        );

        let result = rag::ask_ai_with_provider_using_active_embeddings_time_window(
            &conn,
            &key,
            Path::new(&app_dir),
            &conversation_id,
            &question,
            top_k as usize,
            focus,
            time_start_ms,
            time_end_ms,
            &provider,
            &mut |ev| {
                emit_ask_ai_meta_if_any(&sink, ev.role.as_deref())?;
                if ev.done {
                    if sink.add(String::new()).is_err() {
                        return Err(rag::StreamCancelled.into());
                    }
                    return Ok(());
                }
                if ev.text_delta.is_empty() {
                    return Ok(());
                }
                if sink.add(ev.text_delta).is_err() {
                    return Err(rag::StreamCancelled.into());
                }
                Ok(())
            },
        )
        .map(|_| ());

        match result {
            Ok(()) => Ok(()),
            Err(e) if e.is::<rag::StreamCancelled>() => Ok(()),
            Err(e) => Err(e),
        }
    })();

    finish_ask_ai_stream(&sink, result)
}

#[flutter_rust_bridge::frb]
pub fn sync_derive_key(passphrase: String) -> Result<Vec<u8>> {
    let kdf = KdfParams {
        m_cost_kib: 8 * 1024,
        t_cost: 2,
        p_cost: 1,
    };
    let key = derive_root_key(&passphrase, b"secondloop-sync1", &kdf)?;
    Ok(key.to_vec())
}

#[flutter_rust_bridge::frb]
pub fn sync_webdav_test_connection(
    base_url: String,
    username: Option<String>,
    password: Option<String>,
    remote_root: String,
) -> Result<()> {
    let remote = sync::webdav::WebDavRemoteStore::new(base_url, username, password)?;
    remote.mkdir_all(&remote_root)?;
    remote.ensure_dir_exists(&remote_root)?;
    let _ = remote.list(&remote_root)?;
    Ok(())
}

#[flutter_rust_bridge::frb]
pub fn sync_webdav_push(
    app_dir: String,
    key: Vec<u8>,
    sync_key: Vec<u8>,
    base_url: String,
    username: Option<String>,
    password: Option<String>,
    remote_root: String,
) -> Result<u64> {
    let key = key_from_bytes(key)?;
    let sync_key = sync_key_from_bytes(sync_key)?;
    let conn = db::open(Path::new(&app_dir))?;
    let remote = sync::webdav::WebDavRemoteStore::new(base_url, username, password)?;
    sync::push(&conn, &key, &sync_key, &remote, &remote_root)
}

#[flutter_rust_bridge::frb]
pub fn sync_webdav_push_ops_only(
    app_dir: String,
    key: Vec<u8>,
    sync_key: Vec<u8>,
    base_url: String,
    username: Option<String>,
    password: Option<String>,
    remote_root: String,
) -> Result<u64> {
    let key = key_from_bytes(key)?;
    let sync_key = sync_key_from_bytes(sync_key)?;
    let conn = db::open(Path::new(&app_dir))?;
    let remote = sync::webdav::WebDavRemoteStore::new(base_url, username, password)?;
    sync::push_ops_only(&conn, &key, &sync_key, &remote, &remote_root)
}

#[flutter_rust_bridge::frb]
pub fn sync_webdav_pull(
    app_dir: String,
    key: Vec<u8>,
    sync_key: Vec<u8>,
    base_url: String,
    username: Option<String>,
    password: Option<String>,
    remote_root: String,
) -> Result<u64> {
    let key = key_from_bytes(key)?;
    let sync_key = sync_key_from_bytes(sync_key)?;
    let conn = db::open(Path::new(&app_dir))?;
    let remote = sync::webdav::WebDavRemoteStore::new(base_url, username, password)?;
    sync::pull(&conn, &key, &sync_key, &remote, &remote_root)
}

#[flutter_rust_bridge::frb]
pub fn sync_webdav_download_attachment_bytes(
    app_dir: String,
    key: Vec<u8>,
    sync_key: Vec<u8>,
    base_url: String,
    username: Option<String>,
    password: Option<String>,
    remote_root: String,
    sha256: String,
) -> Result<()> {
    let key = key_from_bytes(key)?;
    let sync_key = sync_key_from_bytes(sync_key)?;
    let conn = db::open(Path::new(&app_dir))?;
    let remote = sync::webdav::WebDavRemoteStore::new(base_url, username, password)?;
    sync::download_attachment_bytes(&conn, &key, &sync_key, &remote, &remote_root, &sha256)
}

#[flutter_rust_bridge::frb]
pub fn sync_webdav_upload_attachment_bytes(
    app_dir: String,
    key: Vec<u8>,
    sync_key: Vec<u8>,
    base_url: String,
    username: Option<String>,
    password: Option<String>,
    remote_root: String,
    sha256: String,
) -> Result<bool> {
    let key = key_from_bytes(key)?;
    let sync_key = sync_key_from_bytes(sync_key)?;
    let conn = db::open(Path::new(&app_dir))?;
    let remote = sync::webdav::WebDavRemoteStore::new(base_url, username, password)?;
    sync::upload_attachment_bytes(&conn, &key, &sync_key, &remote, &remote_root, &sha256)
}

#[flutter_rust_bridge::frb]
pub fn sync_webdav_clear_remote_root(
    base_url: String,
    username: Option<String>,
    password: Option<String>,
    remote_root: String,
) -> Result<()> {
    let remote = sync::webdav::WebDavRemoteStore::new(base_url, username, password)?;
    sync::clear_remote_root(&remote, &remote_root)
}

#[flutter_rust_bridge::frb]
pub fn sync_localdir_test_connection(local_dir: String, remote_root: String) -> Result<()> {
    let remote = sync::localdir::LocalDirRemoteStore::new(PathBuf::from(local_dir))?;
    remote.mkdir_all(&remote_root)?;
    let _ = remote.list(&remote_root)?;
    Ok(())
}

#[flutter_rust_bridge::frb]
pub fn sync_localdir_push(
    app_dir: String,
    key: Vec<u8>,
    sync_key: Vec<u8>,
    local_dir: String,
    remote_root: String,
) -> Result<u64> {
    let key = key_from_bytes(key)?;
    let sync_key = sync_key_from_bytes(sync_key)?;
    let conn = db::open(Path::new(&app_dir))?;
    let remote = sync::localdir::LocalDirRemoteStore::new(PathBuf::from(local_dir))?;
    sync::push(&conn, &key, &sync_key, &remote, &remote_root)
}

#[flutter_rust_bridge::frb]
pub fn sync_localdir_push_ops_only(
    app_dir: String,
    key: Vec<u8>,
    sync_key: Vec<u8>,
    local_dir: String,
    remote_root: String,
) -> Result<u64> {
    let key = key_from_bytes(key)?;
    let sync_key = sync_key_from_bytes(sync_key)?;
    let conn = db::open(Path::new(&app_dir))?;
    let remote = sync::localdir::LocalDirRemoteStore::new(PathBuf::from(local_dir))?;
    sync::push_ops_only(&conn, &key, &sync_key, &remote, &remote_root)
}

#[flutter_rust_bridge::frb]
pub fn sync_localdir_pull(
    app_dir: String,
    key: Vec<u8>,
    sync_key: Vec<u8>,
    local_dir: String,
    remote_root: String,
) -> Result<u64> {
    let key = key_from_bytes(key)?;
    let sync_key = sync_key_from_bytes(sync_key)?;
    let conn = db::open(Path::new(&app_dir))?;
    let remote = sync::localdir::LocalDirRemoteStore::new(PathBuf::from(local_dir))?;
    sync::pull(&conn, &key, &sync_key, &remote, &remote_root)
}

#[flutter_rust_bridge::frb]
pub fn sync_localdir_download_attachment_bytes(
    app_dir: String,
    key: Vec<u8>,
    sync_key: Vec<u8>,
    local_dir: String,
    remote_root: String,
    sha256: String,
) -> Result<()> {
    let key = key_from_bytes(key)?;
    let sync_key = sync_key_from_bytes(sync_key)?;
    let conn = db::open(Path::new(&app_dir))?;
    let remote = sync::localdir::LocalDirRemoteStore::new(PathBuf::from(local_dir))?;
    sync::download_attachment_bytes(&conn, &key, &sync_key, &remote, &remote_root, &sha256)
}

#[flutter_rust_bridge::frb]
pub fn sync_localdir_upload_attachment_bytes(
    app_dir: String,
    key: Vec<u8>,
    sync_key: Vec<u8>,
    local_dir: String,
    remote_root: String,
    sha256: String,
) -> Result<bool> {
    let key = key_from_bytes(key)?;
    let sync_key = sync_key_from_bytes(sync_key)?;
    let conn = db::open(Path::new(&app_dir))?;
    let remote = sync::localdir::LocalDirRemoteStore::new(PathBuf::from(local_dir))?;
    sync::upload_attachment_bytes(&conn, &key, &sync_key, &remote, &remote_root, &sha256)
}

#[flutter_rust_bridge::frb]
pub fn sync_localdir_clear_remote_root(local_dir: String, remote_root: String) -> Result<()> {
    let remote = sync::localdir::LocalDirRemoteStore::new(PathBuf::from(local_dir))?;
    sync::clear_remote_root(&remote, &remote_root)
}

#[flutter_rust_bridge::frb]
pub fn sync_managed_vault_push(
    app_dir: String,
    key: Vec<u8>,
    sync_key: Vec<u8>,
    base_url: String,
    vault_id: String,
    firebase_id_token: String,
) -> Result<u64> {
    let key = key_from_bytes(key)?;
    let sync_key = sync_key_from_bytes(sync_key)?;
    let conn = db::open(Path::new(&app_dir))?;
    sync::managed_vault::push(
        &conn,
        &key,
        &sync_key,
        &base_url,
        &vault_id,
        &firebase_id_token,
    )
}

#[flutter_rust_bridge::frb]
pub fn sync_managed_vault_push_ops_only(
    app_dir: String,
    key: Vec<u8>,
    sync_key: Vec<u8>,
    base_url: String,
    vault_id: String,
    firebase_id_token: String,
) -> Result<u64> {
    let key = key_from_bytes(key)?;
    let sync_key = sync_key_from_bytes(sync_key)?;
    let conn = db::open(Path::new(&app_dir))?;
    sync::managed_vault::push_ops_only(
        &conn,
        &key,
        &sync_key,
        &base_url,
        &vault_id,
        &firebase_id_token,
    )
}

#[flutter_rust_bridge::frb]
pub fn sync_managed_vault_pull(
    app_dir: String,
    key: Vec<u8>,
    sync_key: Vec<u8>,
    base_url: String,
    vault_id: String,
    firebase_id_token: String,
) -> Result<u64> {
    let key = key_from_bytes(key)?;
    let sync_key = sync_key_from_bytes(sync_key)?;
    let conn = db::open(Path::new(&app_dir))?;
    sync::managed_vault::pull(
        &conn,
        &key,
        &sync_key,
        &base_url,
        &vault_id,
        &firebase_id_token,
    )
}

#[flutter_rust_bridge::frb]
pub fn sync_managed_vault_upload_attachment_bytes(
    app_dir: String,
    key: Vec<u8>,
    sync_key: Vec<u8>,
    base_url: String,
    vault_id: String,
    firebase_id_token: String,
    sha256: String,
) -> Result<bool> {
    let key = key_from_bytes(key)?;
    let sync_key = sync_key_from_bytes(sync_key)?;
    let conn = db::open(Path::new(&app_dir))?;
    sync::managed_vault::upload_attachment_bytes(
        &conn,
        &key,
        &sync_key,
        &base_url,
        &vault_id,
        &firebase_id_token,
        &sha256,
    )
}

#[flutter_rust_bridge::frb]
pub fn sync_managed_vault_download_attachment_bytes(
    app_dir: String,
    key: Vec<u8>,
    sync_key: Vec<u8>,
    base_url: String,
    vault_id: String,
    firebase_id_token: String,
    sha256: String,
) -> Result<()> {
    let key = key_from_bytes(key)?;
    let sync_key = sync_key_from_bytes(sync_key)?;
    let conn = db::open(Path::new(&app_dir))?;
    sync::managed_vault::download_attachment_bytes(
        &conn,
        &key,
        &sync_key,
        &base_url,
        &vault_id,
        &firebase_id_token,
        &sha256,
    )
}

#[flutter_rust_bridge::frb]
pub fn sync_managed_vault_clear_device(
    base_url: String,
    vault_id: String,
    firebase_id_token: String,
    device_id: String,
) -> Result<()> {
    sync::managed_vault::clear_device(&base_url, &vault_id, &firebase_id_token, &device_id)
}

#[flutter_rust_bridge::frb]
pub fn sync_managed_vault_clear_vault(
    base_url: String,
    vault_id: String,
    firebase_id_token: String,
) -> Result<()> {
    sync::managed_vault::clear_vault(&base_url, &vault_id, &firebase_id_token)
}
