#[flutter_rust_bridge::frb]
pub fn auth_is_initialized(app_dir: String) -> bool {
    crate::api::auth_state::auth_is_initialized(Path::new(&app_dir))
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
pub fn auth_init_master_password_with_existing_key(
    app_dir: String,
    password: String,
    key: Vec<u8>,
) -> Result<Vec<u8>> {
    let kdf = KdfParams {
        m_cost_kib: 8 * 1024,
        t_cost: 2,
        p_cost: 1,
    };
    let session_key = key_from_bytes(key)?;
    let key = auth::init_master_password_with_existing_key(
        Path::new(&app_dir),
        &password,
        kdf,
        session_key,
    )?;
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
pub fn db_get_or_create_loop_home_conversation(
    app_dir: String,
    key: Vec<u8>,
) -> Result<db::Conversation> {
    let key = key_from_bytes(key)?;
    let conn = db::open(Path::new(&app_dir))?;
    db::get_or_create_loop_home_conversation(&conn, &key)
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
    citations_json: Option<String>,
) -> Result<db::Message> {
    let key = key_from_bytes(key)?;
    let conn = db::open(Path::new(&app_dir))?;
    match citations_json.as_deref() {
        Some(value) => db::insert_message_non_memory_with_citations(
            &conn,
            &key,
            &conversation_id,
            &role,
            &content,
            Some(value),
        ),
        None => db::insert_message(&conn, &key, &conversation_id, &role, &content),
    }
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
    manual_importance_nudge_score: Option<i64>,
    manual_urgency_nudge_score: Option<i64>,
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
        manual_importance_nudge_score,
        manual_urgency_nudge_score,
    )
}

#[flutter_rust_bridge::frb]
pub fn db_list_todos(app_dir: String, key: Vec<u8>) -> Result<Vec<db::Todo>> {
    let key = key_from_bytes(key)?;
    let conn = db::open(Path::new(&app_dir))?;
    db::list_todos(&conn, &key)
}

#[flutter_rust_bridge::frb]
pub fn db_get_todo_by_id(
    app_dir: String,
    key: Vec<u8>,
    todo_id: String,
) -> Result<Option<db::Todo>> {
    let key = key_from_bytes(key)?;
    let conn = db::open(Path::new(&app_dir))?;
    db::find_todo(&conn, &key, &todo_id)
}

#[flutter_rust_bridge::frb]
pub fn db_get_todo_followup_generation_job(
    app_dir: String,
    key: Vec<u8>,
    todo_id: String,
) -> Result<Option<db::TodoFollowupGenerationJob>> {
    let key = key_from_bytes(key)?;
    let conn = db::open(Path::new(&app_dir))?;
    ensure_todo_access(&conn, &key, &todo_id)?;
    db::find_todo_followup_generation_job(&conn, &todo_id)
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

#[allow(clippy::too_many_arguments)]
#[flutter_rust_bridge::frb]
pub fn db_transition_todo(
    app_dir: String,
    key: Vec<u8>,
    todo_id: String,
    new_status: Option<String>,
    due_at_ms: Option<i64>,
    clear_due_at_ms: bool,
    review_stage: Option<i64>,
    clear_review_stage: bool,
    next_review_at_ms: Option<i64>,
    clear_next_review_at_ms: bool,
    last_review_at_ms: Option<i64>,
    clear_last_review_at_ms: bool,
    manual_importance_nudge_score: Option<i64>,
    clear_manual_importance_nudge_score: bool,
    manual_urgency_nudge_score: Option<i64>,
    clear_manual_urgency_nudge_score: bool,
    source_message_id: Option<String>,
) -> Result<db::Todo> {
    let key = key_from_bytes(key)?;
    let conn = db::open(Path::new(&app_dir))?;
    db::transition_todo(
        &conn,
        &key,
        &todo_id,
        new_status.as_deref(),
        due_at_ms,
        clear_due_at_ms,
        review_stage,
        clear_review_stage,
        next_review_at_ms,
        clear_next_review_at_ms,
        last_review_at_ms,
        clear_last_review_at_ms,
        manual_importance_nudge_score,
        clear_manual_importance_nudge_score,
        manual_urgency_nudge_score,
        clear_manual_urgency_nudge_score,
        source_message_id.as_deref(),
    )
}

#[flutter_rust_bridge::frb]
pub fn db_update_todo_due_with_scope(
    app_dir: String,
    key: Vec<u8>,
    todo_id: String,
    due_at_ms: i64,
    scope: String,
) -> Result<db::Todo> {
    let key = key_from_bytes(key)?;
    let conn = db::open(Path::new(&app_dir))?;
    let parsed_scope = db::TodoRecurrenceEditScope::from_wire(&scope)?;
    db::update_todo_due_with_scope(&conn, &key, &todo_id, due_at_ms, parsed_scope)
}

#[flutter_rust_bridge::frb]
pub fn db_update_todo_status_with_scope(
    app_dir: String,
    key: Vec<u8>,
    todo_id: String,
    new_status: String,
    source_message_id: Option<String>,
    scope: String,
) -> Result<db::Todo> {
    let key = key_from_bytes(key)?;
    let conn = db::open(Path::new(&app_dir))?;
    let parsed_scope = db::TodoRecurrenceEditScope::from_wire(&scope)?;
    db::update_todo_status_with_scope(
        &conn,
        &key,
        &todo_id,
        &new_status,
        source_message_id.as_deref(),
        parsed_scope,
    )
}

#[flutter_rust_bridge::frb]
pub fn db_update_todo_recurrence_rule_with_scope(
    app_dir: String,
    key: Vec<u8>,
    todo_id: String,
    rule_json: String,
    scope: String,
) -> Result<()> {
    let key = key_from_bytes(key)?;
    let conn = db::open(Path::new(&app_dir))?;
    let parsed_scope = db::TodoRecurrenceEditScope::from_wire(&scope)?;
    db::update_todo_recurrence_rule_with_scope(&conn, &key, &todo_id, &rule_json, parsed_scope)
}

#[flutter_rust_bridge::frb]
pub fn db_upsert_todo_recurrence(
    app_dir: String,
    key: Vec<u8>,
    todo_id: String,
    series_id: String,
    rule_json: String,
) -> Result<()> {
    let key = key_from_bytes(key)?;
    let conn = db::open(Path::new(&app_dir))?;
    db::upsert_todo_recurrence_with_sync(&conn, &key, &todo_id, &series_id, &rule_json)
}

#[flutter_rust_bridge::frb]
pub fn db_get_todo_recurrence_rule_json(
    app_dir: String,
    todo_id: String,
) -> Result<Option<String>> {
    let conn = db::open(Path::new(&app_dir))?;
    db::get_todo_recurrence_rule_json(&conn, &todo_id)
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
pub fn db_create_todo_checklist_item(
    app_dir: String,
    key: Vec<u8>,
    todo_id: String,
    content: String,
) -> Result<db::TodoChecklistItem> {
    let key = key_from_bytes(key)?;
    let conn = db::open(Path::new(&app_dir))?;
    db::create_todo_checklist_item(&conn, &key, &todo_id, &content)
}

#[flutter_rust_bridge::frb]
pub fn db_list_todo_checklist_items(
    app_dir: String,
    key: Vec<u8>,
    todo_id: String,
) -> Result<Vec<db::TodoChecklistItem>> {
    let key = key_from_bytes(key)?;
    let conn = db::open(Path::new(&app_dir))?;
    db::list_todo_checklist_items(&conn, &key, &todo_id)
}

#[flutter_rust_bridge::frb]
pub fn db_update_todo_checklist_item_content(
    app_dir: String,
    key: Vec<u8>,
    item_id: String,
    content: String,
) -> Result<db::TodoChecklistItem> {
    let key = key_from_bytes(key)?;
    let conn = db::open(Path::new(&app_dir))?;
    db::update_todo_checklist_item_content(&conn, &key, &item_id, &content)
}

#[flutter_rust_bridge::frb]
pub fn db_set_todo_checklist_item_done(
    app_dir: String,
    key: Vec<u8>,
    item_id: String,
    is_done: bool,
) -> Result<db::TodoChecklistItem> {
    let key = key_from_bytes(key)?;
    let conn = db::open(Path::new(&app_dir))?;
    db::set_todo_checklist_item_done(&conn, &key, &item_id, is_done)
}

#[flutter_rust_bridge::frb]
pub fn db_delete_todo_checklist_item(app_dir: String, key: Vec<u8>, item_id: String) -> Result<()> {
    let key = key_from_bytes(key)?;
    let conn = db::open(Path::new(&app_dir))?;
    db::delete_todo_checklist_item(&conn, &key, &item_id)
}

#[flutter_rust_bridge::frb]
pub fn db_reorder_todo_checklist_items(
    app_dir: String,
    key: Vec<u8>,
    todo_id: String,
    ordered_item_ids: Vec<String>,
) -> Result<()> {
    let key = key_from_bytes(key)?;
    let conn = db::open(Path::new(&app_dir))?;
    db::reorder_todo_checklist_items(&conn, &key, &todo_id, &ordered_item_ids)
}

#[flutter_rust_bridge::frb]
pub fn db_list_todo_checklist_progress(
    app_dir: String,
    key: Vec<u8>,
) -> Result<Vec<db::TodoChecklistProgress>> {
    let key = key_from_bytes(key)?;
    let conn = db::open(Path::new(&app_dir))?;
    db::list_todo_checklist_progress(&conn, &key)
}

#[flutter_rust_bridge::frb]
pub fn db_list_todo_checklist_suggestions(
    app_dir: String,
    key: Vec<u8>,
    todo_id: String,
) -> Result<Vec<db::TodoChecklistSuggestion>> {
    let key = key_from_bytes(key)?;
    let conn = db::open(Path::new(&app_dir))?;
    db::list_todo_checklist_suggestions(&conn, &key, &todo_id)
}

#[flutter_rust_bridge::frb]
pub fn db_upsert_generated_todo_checklist_suggestions(
    app_dir: String,
    key: Vec<u8>,
    todo_id: String,
    suggestions: Vec<String>,
    source: String,
    generation_key: Option<String>,
) -> Result<Vec<db::TodoChecklistSuggestion>> {
    let key = key_from_bytes(key)?;
    let conn = db::open(Path::new(&app_dir))?;
    db::upsert_generated_todo_checklist_suggestions(
        &conn,
        &key,
        &todo_id,
        &suggestions,
        &source,
        generation_key.as_deref(),
    )
}

#[flutter_rust_bridge::frb]
pub fn db_apply_todo_checklist_suggestions(
    app_dir: String,
    key: Vec<u8>,
    todo_id: String,
    suggestion_ids: Vec<String>,
) -> Result<Vec<db::TodoChecklistItem>> {
    let key = key_from_bytes(key)?;
    let conn = db::open(Path::new(&app_dir))?;
    db::apply_todo_checklist_suggestions(&conn, &key, &todo_id, &suggestion_ids)
}

#[flutter_rust_bridge::frb]
pub fn db_dismiss_todo_checklist_suggestions(
    app_dir: String,
    key: Vec<u8>,
    todo_id: String,
    suggestion_ids: Vec<String>,
) -> Result<()> {
    let key = key_from_bytes(key)?;
    let conn = db::open(Path::new(&app_dir))?;
    db::dismiss_todo_checklist_suggestions(&conn, &key, &todo_id, &suggestion_ids)
}

#[flutter_rust_bridge::frb]
pub fn db_dismiss_all_todo_checklist_suggestions(
    app_dir: String,
    key: Vec<u8>,
    todo_id: String,
) -> Result<()> {
    let key = key_from_bytes(key)?;
    let conn = db::open(Path::new(&app_dir))?;
    db::dismiss_all_todo_checklist_suggestions(&conn, &key, &todo_id)
}

#[flutter_rust_bridge::frb]
pub fn db_list_todo_followup_suggestions(
    app_dir: String,
    key: Vec<u8>,
    todo_id: String,
) -> Result<Vec<db::TodoFollowupSuggestion>> {
    let key = key_from_bytes(key)?;
    let conn = db::open(Path::new(&app_dir))?;
    ensure_todo_access(&conn, &key, &todo_id)?;
    db::list_todo_followup_suggestions(&conn, &key, &todo_id)
}

#[flutter_rust_bridge::frb]
pub fn db_upsert_generated_todo_followup_suggestions(
    app_dir: String,
    key: Vec<u8>,
    todo_id: String,
    suggestions: Vec<db::TodoFollowupSuggestionDraftInput>,
    source: String,
    generation_key: Option<String>,
) -> Result<Vec<db::TodoFollowupSuggestion>> {
    let key = key_from_bytes(key)?;
    let conn = db::open(Path::new(&app_dir))?;
    ensure_todo_access(&conn, &key, &todo_id)?;
    db::upsert_generated_todo_followup_suggestions(
        &conn,
        &key,
        &todo_id,
        &suggestions,
        &source,
        generation_key.as_deref(),
    )
}

#[flutter_rust_bridge::frb]
pub fn db_upsert_generated_todo_followup_suggestions_if_current_claim(
    app_dir: String,
    key: Vec<u8>,
    todo_id: String,
    job_started_at_ms: i64,
    suggestions: Vec<db::TodoFollowupSuggestionDraftInput>,
    source: String,
    generation_key: Option<String>,
) -> Result<bool> {
    let key = key_from_bytes(key)?;
    let conn = db::open(Path::new(&app_dir))?;
    ensure_todo_access(&conn, &key, &todo_id)?;
    db::upsert_generated_todo_followup_suggestions_if_current_claim(
        &conn,
        &key,
        &todo_id,
        job_started_at_ms,
        &suggestions,
        &source,
        generation_key.as_deref(),
    )
}

#[flutter_rust_bridge::frb]
#[allow(clippy::too_many_arguments)]
pub fn db_upsert_todo_with_auto_followup_job(
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
    task_type_hint: Option<String>,
    now_ms: i64,
) -> Result<db::Todo> {
    let key = key_from_bytes(key)?;
    let conn = db::open(Path::new(&app_dir))?;
    db::upsert_todo_with_auto_followup_job(
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
        task_type_hint.as_deref(),
        now_ms,
    )
}

#[flutter_rust_bridge::frb]
pub fn db_apply_todo_followup_suggestions(
    app_dir: String,
    key: Vec<u8>,
    todo_id: String,
    suggestion_ids: Vec<String>,
) -> Result<Vec<db::TodoActivity>> {
    let key = key_from_bytes(key)?;
    let conn = db::open(Path::new(&app_dir))?;
    ensure_todo_access(&conn, &key, &todo_id)?;
    db::apply_todo_followup_suggestions(&conn, &key, &todo_id, &suggestion_ids)
}

#[flutter_rust_bridge::frb]
pub fn db_dismiss_todo_followup_suggestions(
    app_dir: String,
    key: Vec<u8>,
    todo_id: String,
    suggestion_ids: Vec<String>,
) -> Result<()> {
    let key = key_from_bytes(key)?;
    let conn = db::open(Path::new(&app_dir))?;
    ensure_todo_access(&conn, &key, &todo_id)?;
    db::dismiss_todo_followup_suggestions(&conn, &key, &todo_id, &suggestion_ids)
}

#[flutter_rust_bridge::frb]
pub fn db_dismiss_all_todo_followup_suggestions(
    app_dir: String,
    key: Vec<u8>,
    todo_id: String,
) -> Result<()> {
    let key = key_from_bytes(key)?;
    let conn = db::open(Path::new(&app_dir))?;
    ensure_todo_access(&conn, &key, &todo_id)?;
    db::dismiss_all_todo_followup_suggestions(&conn, &key, &todo_id)
}

#[flutter_rust_bridge::frb]
pub fn db_enqueue_todo_followup_generation_job(
    app_dir: String,
    key: Vec<u8>,
    todo_id: String,
    trigger_kind: String,
    manual_override_followup: bool,
    task_type_hint: Option<String>,
    now_ms: i64,
) -> Result<()> {
    let key = key_from_bytes(key)?;
    let conn = db::open(Path::new(&app_dir))?;
    ensure_todo_access(&conn, &key, &todo_id)?;
    db::enqueue_todo_followup_generation_job(
        &conn,
        &todo_id,
        &trigger_kind,
        manual_override_followup,
        task_type_hint.as_deref(),
        now_ms,
    )
}

#[flutter_rust_bridge::frb]
pub fn db_list_due_todo_followup_generation_jobs(
    app_dir: String,
    key: Vec<u8>,
    now_ms: i64,
    limit: u32,
) -> Result<Vec<db::TodoFollowupGenerationJob>> {
    let app_dir = PathBuf::from(app_dir);
    let key = key_from_bytes(key)?;
    auth::validate_key(&app_dir, &key)?;
    let conn = db::open(&app_dir)?;
    list_visible_due_todo_followup_generation_jobs(&conn, &key, now_ms, limit)
}

#[flutter_rust_bridge::frb]
pub fn db_mark_todo_followup_generation_job_running(
    app_dir: String,
    key: Vec<u8>,
    todo_id: String,
    now_ms: i64,
) -> Result<()> {
    let key = key_from_bytes(key)?;
    let conn = db::open(Path::new(&app_dir))?;
    ensure_todo_access(&conn, &key, &todo_id)?;
    db::mark_todo_followup_generation_job_running(&conn, &todo_id, now_ms)
}

#[flutter_rust_bridge::frb]
pub fn db_mark_todo_followup_generation_job_failed(
    app_dir: String,
    key: Vec<u8>,
    todo_id: String,
    attempts: i64,
    next_retry_at_ms: i64,
    last_error: String,
    now_ms: i64,
) -> Result<()> {
    let key = key_from_bytes(key)?;
    let conn = db::open(Path::new(&app_dir))?;
    ensure_todo_access(&conn, &key, &todo_id)?;
    db::mark_todo_followup_generation_job_failed(
        &conn,
        &todo_id,
        attempts,
        next_retry_at_ms,
        &last_error,
        now_ms,
    )
}

#[flutter_rust_bridge::frb]
pub fn db_mark_todo_followup_generation_job_succeeded(
    app_dir: String,
    key: Vec<u8>,
    todo_id: String,
    now_ms: i64,
) -> Result<()> {
    let key = key_from_bytes(key)?;
    let conn = db::open(Path::new(&app_dir))?;
    ensure_todo_access(&conn, &key, &todo_id)?;
    db::mark_todo_followup_generation_job_succeeded(&conn, &todo_id, now_ms)
}

#[flutter_rust_bridge::frb]
pub fn db_mark_todo_followup_generation_job_skipped(
    app_dir: String,
    key: Vec<u8>,
    todo_id: String,
    now_ms: i64,
) -> Result<()> {
    let key = key_from_bytes(key)?;
    let conn = db::open(Path::new(&app_dir))?;
    ensure_todo_access(&conn, &key, &todo_id)?;
    db::mark_todo_followup_generation_job_skipped(&conn, &todo_id, now_ms)
}

#[flutter_rust_bridge::frb]
pub fn db_mark_todo_followup_generation_job_canceled(
    app_dir: String,
    key: Vec<u8>,
    todo_id: String,
    now_ms: i64,
) -> Result<()> {
    let key = key_from_bytes(key)?;
    let conn = db::open(Path::new(&app_dir))?;
    ensure_todo_access(&conn, &key, &todo_id)?;
    db::mark_todo_followup_generation_job_canceled(&conn, &todo_id, now_ms)
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
