use std::path::{Path, PathBuf};

use crate::crypto::{derive_root_key, KdfParams};
use crate::embedding;
use crate::frb_generated::StreamSink;
use crate::sync;
use crate::sync::RemoteStore;
use crate::{auth, db};
use crate::{llm, rag};
use anyhow::{anyhow, Result};

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
pub fn db_search_similar_todo_threads(
    app_dir: String,
    key: Vec<u8>,
    query: String,
    top_k: u32,
) -> Result<Vec<db::SimilarTodoThread>> {
    let key = key_from_bytes(key)?;
    let conn = db::open(Path::new(&app_dir))?;

    // Best-effort: keep the index reasonably fresh without blocking too long.
    // If embeddings are unavailable (e.g. fastembed init failure), callers can catch and fall back.
    db::process_pending_todo_embeddings_active(&conn, &key, Path::new(&app_dir), 64)?;
    db::process_pending_todo_activity_embeddings_active(&conn, &key, Path::new(&app_dir), 128)?;

    db::search_similar_todo_threads_active(&conn, &key, Path::new(&app_dir), &query, top_k as usize)
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
                let _ =
                    db::record_llm_usage_daily(&conn, day, &profile_id, "ask_ai", None, None, None);
            }
            Ok(())
        }
        Err(e) if e.is::<rag::StreamCancelled>() => Ok(()),
        Err(e) => {
            let day = local_day.trim();
            if !day.is_empty() {
                let _ =
                    db::record_llm_usage_daily(&conn, day, &profile_id, "ask_ai", None, None, None);
            }
            Err(e)
        }
    }
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
