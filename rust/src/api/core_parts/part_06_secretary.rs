#[flutter_rust_bridge::frb]
#[allow(clippy::too_many_arguments)]
pub fn db_create_secretary_memory_proposal(
    app_dir: String,
    key: Vec<u8>,
    source_message_id: Option<String>,
    kind: String,
    title: String,
    body: String,
    confidence: f64,
    source_refs_json: Option<String>,
    action_hint: Option<String>,
    now_ms: i64,
) -> Result<db::SecretaryMemoryProposalRecord> {
    let key = key_from_bytes(key)?;
    let conn = db::open(Path::new(&app_dir))?;
    db::create_secretary_memory_proposal(
        &conn,
        &key,
        db::NewSecretaryMemoryProposal {
            source_message_id,
            kind,
            title,
            body,
            confidence,
            source_refs_json,
            action_hint,
            now_ms,
        },
    )
}

#[flutter_rust_bridge::frb]
pub fn db_list_secretary_memory_proposals(
    app_dir: String,
    key: Vec<u8>,
    state: Option<String>,
) -> Result<Vec<db::SecretaryMemoryProposalRecord>> {
    let key = key_from_bytes(key)?;
    let conn = db::open(Path::new(&app_dir))?;
    db::list_secretary_memory_proposals(&conn, &key, state.as_deref())
}

#[flutter_rust_bridge::frb]
pub fn db_accept_secretary_memory_proposal(
    app_dir: String,
    key: Vec<u8>,
    proposal_id: String,
    now_ms: i64,
) -> Result<db::MemoryPageRecord> {
    let key = key_from_bytes(key)?;
    let conn = db::open(Path::new(&app_dir))?;
    db::create_memory_page_from_proposal(&conn, &key, &proposal_id, now_ms)
}

#[flutter_rust_bridge::frb]
pub fn db_dismiss_secretary_memory_proposal(
    app_dir: String,
    key: Vec<u8>,
    proposal_id: String,
    now_ms: i64,
) -> Result<db::SecretaryMemoryProposalRecord> {
    let key = key_from_bytes(key)?;
    let conn = db::open(Path::new(&app_dir))?;
    db::set_secretary_memory_proposal_state(&conn, &key, &proposal_id, "dismissed", now_ms)
}

#[flutter_rust_bridge::frb]
pub fn db_list_memory_pages(
    app_dir: String,
    key: Vec<u8>,
    state: Option<String>,
) -> Result<Vec<db::MemoryPageRecord>> {
    let key = key_from_bytes(key)?;
    let conn = db::open(Path::new(&app_dir))?;
    db::list_memory_pages(&conn, &key, state.as_deref())
}

#[flutter_rust_bridge::frb]
pub fn db_get_memory_page(
    app_dir: String,
    key: Vec<u8>,
    page_id: String,
) -> Result<db::MemoryPageRecord> {
    let key = key_from_bytes(key)?;
    let conn = db::open(Path::new(&app_dir))?;
    db::get_memory_page(&conn, &key, &page_id)
}

#[flutter_rust_bridge::frb]
#[allow(clippy::too_many_arguments)]
pub fn db_correct_memory_page(
    app_dir: String,
    key: Vec<u8>,
    page_id: String,
    title: String,
    summary: String,
    body: String,
    reason: Option<String>,
    now_ms: i64,
) -> Result<db::MemoryPageRecord> {
    let key = key_from_bytes(key)?;
    let conn = db::open(Path::new(&app_dir))?;
    db::correct_memory_page(
        &conn,
        &key,
        db::CorrectMemoryPageInput {
            page_id,
            title,
            summary,
            body,
            reason,
            now_ms,
        },
    )
}

#[flutter_rust_bridge::frb]
pub fn db_archive_memory_page(
    app_dir: String,
    key: Vec<u8>,
    page_id: String,
    now_ms: i64,
) -> Result<db::MemoryPageRecord> {
    let key = key_from_bytes(key)?;
    let conn = db::open(Path::new(&app_dir))?;
    db::archive_memory_page(&conn, &key, &page_id, now_ms)
}

#[flutter_rust_bridge::frb]
pub fn db_restore_memory_page(
    app_dir: String,
    key: Vec<u8>,
    page_id: String,
    now_ms: i64,
) -> Result<db::MemoryPageRecord> {
    let key = key_from_bytes(key)?;
    let conn = db::open(Path::new(&app_dir))?;
    db::restore_memory_page(&conn, &key, &page_id, now_ms)
}

#[flutter_rust_bridge::frb]
#[allow(clippy::too_many_arguments)]
pub fn db_upsert_planning_output(
    app_dir: String,
    key: Vec<u8>,
    id: String,
    kind: String,
    title: String,
    body: String,
    items_json: String,
    source_refs_json: Option<String>,
    route: String,
    state: String,
    created_at_ms: i64,
    updated_at_ms: i64,
    expires_at_ms: Option<i64>,
) -> Result<db::PlanningOutputRecord> {
    let key = key_from_bytes(key)?;
    let conn = db::open(Path::new(&app_dir))?;
    db::upsert_planning_output(
        &conn,
        &key,
        db::NewPlanningOutput {
            id,
            kind,
            title,
            body,
            items_json,
            source_refs_json,
            route,
            state,
            created_at_ms,
            updated_at_ms,
            expires_at_ms,
        },
    )
}

#[flutter_rust_bridge::frb]
pub fn db_list_planning_outputs(
    app_dir: String,
    key: Vec<u8>,
    kind: Option<String>,
    now_ms: i64,
    include_expired: bool,
) -> Result<Vec<db::PlanningOutputRecord>> {
    let key = key_from_bytes(key)?;
    let conn = db::open(Path::new(&app_dir))?;
    db::list_planning_outputs(&conn, &key, kind.as_deref(), now_ms, include_expired)
}

#[flutter_rust_bridge::frb]
pub fn db_create_secretary_run(
    app_dir: String,
    key: Vec<u8>,
    trigger_kind: String,
    route: String,
    status: String,
    input_summary: Option<String>,
    output_summary: Option<String>,
    error: Option<String>,
    now_ms: i64,
) -> Result<db::SecretaryRunRecord> {
    let key = key_from_bytes(key)?;
    let conn = db::open(Path::new(&app_dir))?;
    db::create_secretary_run(
        &conn,
        &key,
        db::NewSecretaryRun {
            trigger_kind,
            route,
            status,
            input_summary,
            output_summary,
            error,
            now_ms,
        },
    )
}

#[flutter_rust_bridge::frb]
pub fn db_create_secretary_tool_call(
    app_dir: String,
    key: Vec<u8>,
    run_id: String,
    tool_name: String,
    status: String,
    requires_confirmation: bool,
    input_json: Option<String>,
    output_json: Option<String>,
    now_ms: i64,
) -> Result<db::SecretaryToolCallRecord> {
    let key = key_from_bytes(key)?;
    let conn = db::open(Path::new(&app_dir))?;
    db::create_secretary_tool_call(
        &conn,
        &key,
        db::NewSecretaryToolCall {
            run_id,
            tool_name,
            status,
            requires_confirmation,
            input_json,
            output_json,
            now_ms,
        },
    )
}

#[flutter_rust_bridge::frb]
pub fn db_list_secretary_tool_calls_for_run(
    app_dir: String,
    key: Vec<u8>,
    run_id: String,
) -> Result<Vec<db::SecretaryToolCallRecord>> {
    let key = key_from_bytes(key)?;
    let conn = db::open(Path::new(&app_dir))?;
    db::list_secretary_tool_calls_for_run(&conn, &key, &run_id)
}
