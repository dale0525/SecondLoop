#[flutter_rust_bridge::frb]
pub fn db_list_events(app_dir: String, key: Vec<u8>) -> Result<Vec<db::Event>> {
    let key = key_from_bytes(key)?;
    let conn = db::open(Path::new(&app_dir))?;
    db::list_events(&conn, &key)
}

#[flutter_rust_bridge::frb]
pub fn db_get_event_by_id(
    app_dir: String,
    key: Vec<u8>,
    event_id: String,
) -> Result<Option<db::Event>> {
    let key = key_from_bytes(key)?;
    let conn = db::open(Path::new(&app_dir))?;
    db::find_event(&conn, &key, &event_id)
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
pub fn db_upsert_attachment_derivation(
    app_dir: String,
    key: Vec<u8>,
    root_sha256: String,
    child_sha256: String,
    role: String,
    created_at_ms: i64,
) -> Result<()> {
    let _key = key_from_bytes(key)?;
    let conn = db::open(Path::new(&app_dir))?;
    db::upsert_attachment_derivation(&conn, &root_sha256, &child_sha256, &role, created_at_ms)
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
    let _ = db::mark_semantic_parse_job_running(&conn, &message_id, now_ms)?;
    Ok(())
}

#[flutter_rust_bridge::frb]
pub fn db_claim_semantic_parse_job_running(
    app_dir: String,
    key: Vec<u8>,
    message_id: String,
    now_ms: i64,
) -> Result<i64> {
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
pub fn db_mark_semantic_parse_job_failed_if_current_attempt(
    app_dir: String,
    key: Vec<u8>,
    message_id: String,
    expected_attempt_id: i64,
    attempts: i64,
    next_retry_at_ms: i64,
    last_error: String,
    now_ms: i64,
) -> Result<bool> {
    let _key = key_from_bytes(key)?;
    let conn = db::open(Path::new(&app_dir))?;
    db::mark_semantic_parse_job_failed_if_current_attempt(
        &conn,
        &message_id,
        expected_attempt_id,
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
    suggested_tags: Option<Vec<String>>,
    suggested_tag_confidence: Option<f64>,
    tag_suggestion_state: Option<String>,
    applied_tag_ids: Option<Vec<String>>,
    now_ms: i64,
) -> Result<()> {
    let key = key_from_bytes(key)?;
    let conn = db::open(Path::new(&app_dir))?;
    db::mark_semantic_parse_job_succeeded_with_tag_metadata(
        &conn,
        &key,
        &message_id,
        &applied_action_kind,
        applied_todo_id.as_deref(),
        applied_todo_title.as_deref(),
        applied_prev_todo_status.as_deref(),
        suggested_tags.as_deref(),
        suggested_tag_confidence,
        tag_suggestion_state.as_deref(),
        applied_tag_ids.as_deref(),
        now_ms,
    )
}

#[flutter_rust_bridge::frb]
#[allow(clippy::too_many_arguments)]
pub fn db_mark_semantic_parse_job_succeeded_if_current_attempt(
    app_dir: String,
    key: Vec<u8>,
    message_id: String,
    expected_attempt_id: i64,
    applied_action_kind: String,
    applied_todo_id: Option<String>,
    applied_todo_title: Option<String>,
    applied_prev_todo_status: Option<String>,
    suggested_tags: Option<Vec<String>>,
    suggested_tag_confidence: Option<f64>,
    tag_suggestion_state: Option<String>,
    applied_tag_ids: Option<Vec<String>>,
    now_ms: i64,
) -> Result<bool> {
    let key = key_from_bytes(key)?;
    let conn = db::open(Path::new(&app_dir))?;
    db::mark_semantic_parse_job_succeeded_with_tag_metadata_if_current_attempt(
        &conn,
        &key,
        &message_id,
        expected_attempt_id,
        &applied_action_kind,
        applied_todo_id.as_deref(),
        applied_todo_title.as_deref(),
        applied_prev_todo_status.as_deref(),
        suggested_tags.as_deref(),
        suggested_tag_confidence,
        tag_suggestion_state.as_deref(),
        applied_tag_ids.as_deref(),
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
pub fn db_requeue_running_semantic_parse_jobs(
    app_dir: String,
    key: Vec<u8>,
    now_ms: i64,
) -> Result<i64> {
    let _key = key_from_bytes(key)?;
    let conn = db::open(Path::new(&app_dir))?;
    db::requeue_running_semantic_parse_jobs(&conn, now_ms)
}

#[flutter_rust_bridge::frb]
pub fn db_mark_semantic_parse_job_canceled_if_current_attempt(
    app_dir: String,
    key: Vec<u8>,
    message_id: String,
    expected_attempt_id: i64,
    now_ms: i64,
) -> Result<bool> {
    let _key = key_from_bytes(key)?;
    let conn = db::open(Path::new(&app_dir))?;
    db::mark_semantic_parse_job_canceled_if_current_attempt(
        &conn,
        &message_id,
        expected_attempt_id,
        now_ms,
    )
}

#[flutter_rust_bridge::frb]
#[allow(clippy::too_many_arguments)]
pub fn db_complete_semantic_parse_no_action_if_current_attempt(
    app_dir: String,
    key: Vec<u8>,
    message_id: String,
    expected_attempt_id: i64,
    pending_suggested_tags: Option<Vec<String>>,
    auto_apply_suggested_tags: Option<Vec<String>>,
    suggested_tag_confidence: Option<f64>,
    now_ms: i64,
) -> Result<Option<Vec<String>>> {
    let key = key_from_bytes(key)?;
    let conn = db::open(Path::new(&app_dir))?;
    db::complete_semantic_parse_no_action_if_current_attempt(
        &conn,
        &key,
        &message_id,
        expected_attempt_id,
        pending_suggested_tags.as_deref(),
        auto_apply_suggested_tags.as_deref(),
        suggested_tag_confidence,
        now_ms,
    )
}

#[flutter_rust_bridge::frb]
#[allow(clippy::too_many_arguments)]
pub fn db_complete_semantic_parse_create_if_current_attempt(
    app_dir: String,
    key: Vec<u8>,
    message_id: String,
    expected_attempt_id: i64,
    todo_id: String,
    title: String,
    due_at_ms: Option<i64>,
    status: String,
    review_stage: Option<i64>,
    next_review_at_ms: Option<i64>,
    last_review_at_ms: Option<i64>,
    task_type_hint: Option<String>,
    recurrence_rule_json: Option<String>,
    checklist_suggestions: Vec<String>,
    checklist_source: String,
    checklist_generation_key: Option<String>,
    pending_suggested_tags: Option<Vec<String>>,
    auto_apply_suggested_tags: Option<Vec<String>>,
    suggested_tag_confidence: Option<f64>,
    now_ms: i64,
) -> Result<bool> {
    let key = key_from_bytes(key)?;
    let conn = db::open(Path::new(&app_dir))?;
    db::complete_semantic_parse_create_if_current_attempt(
        &conn,
        &key,
        &message_id,
        expected_attempt_id,
        &todo_id,
        &title,
        due_at_ms,
        &status,
        review_stage,
        next_review_at_ms,
        last_review_at_ms,
        task_type_hint.as_deref(),
        recurrence_rule_json.as_deref(),
        &checklist_suggestions,
        &checklist_source,
        checklist_generation_key.as_deref(),
        pending_suggested_tags.as_deref(),
        auto_apply_suggested_tags.as_deref(),
        suggested_tag_confidence,
        now_ms,
    )
}

#[flutter_rust_bridge::frb]
#[allow(clippy::too_many_arguments)]
pub fn db_complete_semantic_parse_followup_if_current_attempt(
    app_dir: String,
    key: Vec<u8>,
    message_id: String,
    expected_attempt_id: i64,
    todo_id: String,
    todo_title: Option<String>,
    new_status: String,
    pending_suggested_tags: Option<Vec<String>>,
    auto_apply_suggested_tags: Option<Vec<String>>,
    suggested_tag_confidence: Option<f64>,
    now_ms: i64,
) -> Result<bool> {
    let key = key_from_bytes(key)?;
    let conn = db::open(Path::new(&app_dir))?;
    db::complete_semantic_parse_followup_if_current_attempt(
        &conn,
        &key,
        &message_id,
        expected_attempt_id,
        &todo_id,
        todo_title.as_deref(),
        Some(new_status.as_str()),
        None,
        pending_suggested_tags.as_deref(),
        auto_apply_suggested_tags.as_deref(),
        suggested_tag_confidence,
        now_ms,
    )
}

#[flutter_rust_bridge::frb]
#[allow(clippy::too_many_arguments)]
pub fn db_complete_semantic_parse_todo_command_if_current_attempt(
    app_dir: String,
    key: Vec<u8>,
    message_id: String,
    expected_attempt_id: i64,
    todo_id: String,
    todo_title: Option<String>,
    applied_action_kind: String,
    new_title: Option<String>,
    new_status: Option<String>,
    due_at_ms: Option<i64>,
    manual_importance_nudge_score: Option<i64>,
    manual_urgency_nudge_score: Option<i64>,
    pending_suggested_tags: Option<Vec<String>>,
    auto_apply_suggested_tags: Option<Vec<String>>,
    suggested_tag_confidence: Option<f64>,
    now_ms: i64,
) -> Result<bool> {
    let key = key_from_bytes(key)?;
    let conn = db::open(Path::new(&app_dir))?;
    db::complete_semantic_parse_todo_command_if_current_attempt(
        &conn,
        &key,
        &message_id,
        expected_attempt_id,
        &todo_id,
        todo_title.as_deref(),
        &applied_action_kind,
        new_title.as_deref(),
        new_status.as_deref(),
        due_at_ms,
        manual_importance_nudge_score,
        manual_urgency_nudge_score,
        pending_suggested_tags.as_deref(),
        auto_apply_suggested_tags.as_deref(),
        suggested_tag_confidence,
        now_ms,
    )
}

#[flutter_rust_bridge::frb]
pub fn db_apply_semantic_parse_tags_if_current_attempt(
    app_dir: String,
    key: Vec<u8>,
    message_id: String,
    expected_attempt_id: i64,
    suggested_tags: Vec<String>,
) -> Result<Vec<String>> {
    let key = key_from_bytes(key)?;
    let conn = db::open(Path::new(&app_dir))?;
    db::apply_semantic_parse_tags_if_current_attempt(
        &conn,
        &key,
        &message_id,
        expected_attempt_id,
        &suggested_tags,
    )
}

#[flutter_rust_bridge::frb]
#[allow(clippy::too_many_arguments)]
pub fn db_upsert_todo_from_semantic_parse_if_current_attempt(
    app_dir: String,
    key: Vec<u8>,
    message_id: String,
    expected_attempt_id: i64,
    todo_id: String,
    title: String,
    due_at_ms: Option<i64>,
    status: String,
    review_stage: Option<i64>,
    next_review_at_ms: Option<i64>,
    last_review_at_ms: Option<i64>,
    task_type_hint: Option<String>,
    recurrence_rule_json: Option<String>,
    now_ms: i64,
) -> Result<Option<String>> {
    let key = key_from_bytes(key)?;
    let conn = db::open(Path::new(&app_dir))?;
    db::upsert_semantic_parse_todo_create_if_current_attempt(
        &conn,
        &key,
        &message_id,
        expected_attempt_id,
        &todo_id,
        &title,
        due_at_ms,
        &status,
        review_stage,
        next_review_at_ms,
        last_review_at_ms,
        task_type_hint.as_deref(),
        recurrence_rule_json.as_deref(),
        now_ms,
    )
}

#[flutter_rust_bridge::frb]
pub fn db_upsert_generated_todo_checklist_suggestions_if_current_attempt(
    app_dir: String,
    key: Vec<u8>,
    message_id: String,
    expected_attempt_id: i64,
    todo_id: String,
    suggestions: Vec<String>,
    source: String,
    generation_key: Option<String>,
) -> Result<bool> {
    let key = key_from_bytes(key)?;
    let conn = db::open(Path::new(&app_dir))?;
    db::upsert_semantic_parse_checklist_suggestions_if_current_attempt(
        &conn,
        &key,
        &message_id,
        expected_attempt_id,
        &todo_id,
        &suggestions,
        &source,
        generation_key.as_deref(),
    )
}

#[flutter_rust_bridge::frb]
pub fn db_set_todo_status_from_semantic_parse_if_current_attempt(
    app_dir: String,
    key: Vec<u8>,
    message_id: String,
    expected_attempt_id: i64,
    todo_id: String,
    new_status: String,
) -> Result<Option<String>> {
    let key = key_from_bytes(key)?;
    let conn = db::open(Path::new(&app_dir))?;
    db::set_semantic_parse_todo_status_if_current_attempt(
        &conn,
        &key,
        &message_id,
        expected_attempt_id,
        &todo_id,
        &new_status,
    )
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
