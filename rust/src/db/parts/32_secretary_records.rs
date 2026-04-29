const SECRETARY_MEMORY_PROPOSAL_STATE_PENDING: &str = "pending";
const SECRETARY_MEMORY_PROPOSAL_STATE_ACCEPTED: &str = "accepted";
const SECRETARY_MEMORY_PROPOSAL_STATE_DISMISSED: &str = "dismissed";

fn encrypted_secretary_string(
    key: &[u8; 32],
    value: &str,
    aad: impl AsRef<[u8]>,
) -> Result<Vec<u8>> {
    encrypt_bytes(key, value.as_bytes(), aad.as_ref())
}

fn decrypted_secretary_string(
    key: &[u8; 32],
    blob: &[u8],
    aad: impl AsRef<[u8]>,
    field_name: &str,
) -> Result<String> {
    let bytes = decrypt_bytes(key, blob, aad.as_ref())?;
    String::from_utf8(bytes).map_err(|_| anyhow!("{field_name} is not valid utf-8"))
}

fn encrypted_secretary_optional_string(
    key: &[u8; 32],
    value: Option<&str>,
    aad: impl AsRef<[u8]>,
) -> Result<Option<Vec<u8>>> {
    value
        .map(|value| encrypted_secretary_string(key, value, aad.as_ref()))
        .transpose()
}

fn decrypted_secretary_optional_string(
    key: &[u8; 32],
    blob: Option<Vec<u8>>,
    aad: impl AsRef<[u8]>,
    field_name: &str,
) -> Result<Option<String>> {
    blob.map(|blob| decrypted_secretary_string(key, &blob, aad.as_ref(), field_name))
        .transpose()
}

fn insert_secretary_oplog(
    conn: &Connection,
    key: &[u8; 32],
    op_type: &str,
    ts_ms: i64,
    payload: serde_json::Value,
) -> Result<()> {
    let device_id = get_or_create_device_id(conn)?;
    let seq = next_device_seq(conn, &device_id)?;
    let op = serde_json::json!({
        "op_id": uuid::Uuid::new_v4().to_string(),
        "device_id": device_id,
        "seq": seq,
        "ts_ms": ts_ms,
        "type": op_type,
        "payload": payload,
    });
    insert_oplog(conn, key, &op)
}

fn secretary_memory_proposal_title_aad(id: &str) -> Vec<u8> {
    format!("secretary_memory_proposal.title:{id}").into_bytes()
}

fn secretary_memory_proposal_body_aad(id: &str) -> Vec<u8> {
    format!("secretary_memory_proposal.body:{id}").into_bytes()
}

fn secretary_memory_proposal_source_refs_aad(id: &str) -> Vec<u8> {
    format!("secretary_memory_proposal.source_refs_json:{id}").into_bytes()
}

type SecretaryMemoryProposalRow = (
    String,
    Option<String>,
    String,
    Vec<u8>,
    Vec<u8>,
    f64,
    String,
    Option<Vec<u8>>,
    Option<String>,
    i64,
    i64,
    Option<i64>,
    Option<i64>,
);

fn secretary_memory_proposal_from_row(
    key: &[u8; 32],
    row: SecretaryMemoryProposalRow,
) -> Result<SecretaryMemoryProposalRecord> {
    let (
        id,
        source_message_id,
        kind,
        title_blob,
        body_blob,
        confidence,
        state,
        source_refs_blob,
        action_hint,
        created_at_ms,
        updated_at_ms,
        accepted_at_ms,
        dismissed_at_ms,
    ) = row;
    let title = decrypted_secretary_string(
        key,
        &title_blob,
        secretary_memory_proposal_title_aad(&id),
        "secretary memory proposal title",
    )?;
    let body = decrypted_secretary_string(
        key,
        &body_blob,
        secretary_memory_proposal_body_aad(&id),
        "secretary memory proposal body",
    )?;
    let source_refs_json = decrypted_secretary_optional_string(
        key,
        source_refs_blob,
        secretary_memory_proposal_source_refs_aad(&id),
        "secretary memory proposal source refs",
    )?;

    Ok(SecretaryMemoryProposalRecord {
        id,
        source_message_id,
        kind,
        title,
        body,
        confidence,
        state,
        source_refs_json,
        action_hint,
        created_at_ms,
        updated_at_ms,
        accepted_at_ms,
        dismissed_at_ms,
    })
}

pub fn create_secretary_memory_proposal(
    conn: &Connection,
    key: &[u8; 32],
    input: NewSecretaryMemoryProposal,
) -> Result<SecretaryMemoryProposalRecord> {
    let id = uuid::Uuid::new_v4().to_string();
    let title_blob = encrypted_secretary_string(
        key,
        input.title.trim(),
        secretary_memory_proposal_title_aad(&id),
    )?;
    let body_blob = encrypted_secretary_string(
        key,
        input.body.trim(),
        secretary_memory_proposal_body_aad(&id),
    )?;
    let source_refs_blob = encrypted_secretary_optional_string(
        key,
        input.source_refs_json.as_deref(),
        secretary_memory_proposal_source_refs_aad(&id),
    )?;

    conn.execute(
        r#"
INSERT INTO secretary_memory_proposals(
  id, source_message_id, kind, title, body, confidence, state, source_refs_json,
  action_hint, created_at_ms, updated_at_ms, accepted_at_ms, dismissed_at_ms
)
VALUES (?1, ?2, ?3, ?4, ?5, ?6, 'pending', ?7, ?8, ?9, ?9, NULL, NULL)
"#,
        params![
            id.as_str(),
            input.source_message_id.as_deref(),
            input.kind.as_str(),
            title_blob,
            body_blob,
            input.confidence,
            source_refs_blob,
            input.action_hint.as_deref(),
            input.now_ms,
        ],
    )?;

    let record = get_secretary_memory_proposal(conn, key, &id)?;
    insert_secretary_memory_proposal_upsert_op(conn, key, &record)?;
    Ok(record)
}

fn insert_secretary_memory_proposal_upsert_op(
    conn: &Connection,
    key: &[u8; 32],
    record: &SecretaryMemoryProposalRecord,
) -> Result<()> {
    insert_secretary_oplog(
        conn,
        key,
        "secretary.memory_proposal.upsert.v1",
        record.updated_at_ms,
        serde_json::json!({
            "proposal_id": record.id,
            "source_message_id": record.source_message_id,
            "kind": record.kind,
            "title": record.title,
            "body": record.body,
            "confidence": record.confidence,
            "state": record.state,
            "source_refs_json": record.source_refs_json,
            "action_hint": record.action_hint,
            "created_at_ms": record.created_at_ms,
            "updated_at_ms": record.updated_at_ms,
            "accepted_at_ms": record.accepted_at_ms,
            "dismissed_at_ms": record.dismissed_at_ms,
        }),
    )
}

pub fn get_secretary_memory_proposal(
    conn: &Connection,
    key: &[u8; 32],
    id: &str,
) -> Result<SecretaryMemoryProposalRecord> {
    let row = conn
        .query_row(
            r#"
SELECT id, source_message_id, kind, title, body, confidence, state,
       source_refs_json, action_hint, created_at_ms, updated_at_ms,
       accepted_at_ms, dismissed_at_ms
FROM secretary_memory_proposals
WHERE id = ?1
"#,
            params![id],
            |row| {
                Ok((
                    row.get(0)?,
                    row.get(1)?,
                    row.get(2)?,
                    row.get(3)?,
                    row.get(4)?,
                    row.get(5)?,
                    row.get(6)?,
                    row.get(7)?,
                    row.get(8)?,
                    row.get(9)?,
                    row.get(10)?,
                    row.get(11)?,
                    row.get(12)?,
                ))
            },
        )
        .optional()?
        .ok_or_else(|| anyhow!("secretary memory proposal not found"))?;
    secretary_memory_proposal_from_row(key, row)
}

pub fn list_secretary_memory_proposals(
    conn: &Connection,
    key: &[u8; 32],
    state: Option<&str>,
) -> Result<Vec<SecretaryMemoryProposalRecord>> {
    let sql = if state.is_some() {
        r#"
SELECT id, source_message_id, kind, title, body, confidence, state,
       source_refs_json, action_hint, created_at_ms, updated_at_ms,
       accepted_at_ms, dismissed_at_ms
FROM secretary_memory_proposals
WHERE state = ?1
ORDER BY updated_at_ms DESC, created_at_ms DESC, id ASC
"#
    } else {
        r#"
SELECT id, source_message_id, kind, title, body, confidence, state,
       source_refs_json, action_hint, created_at_ms, updated_at_ms,
       accepted_at_ms, dismissed_at_ms
FROM secretary_memory_proposals
ORDER BY updated_at_ms DESC, created_at_ms DESC, id ASC
"#
    };
    let mut stmt = conn.prepare(sql)?;
    let mut rows = if let Some(state) = state {
        stmt.query(params![state])?
    } else {
        stmt.query([])?
    };
    let mut records = Vec::new();
    while let Some(row) = rows.next()? {
        records.push(secretary_memory_proposal_from_row(
            key,
            (
                row.get(0)?,
                row.get(1)?,
                row.get(2)?,
                row.get(3)?,
                row.get(4)?,
                row.get(5)?,
                row.get(6)?,
                row.get(7)?,
                row.get(8)?,
                row.get(9)?,
                row.get(10)?,
                row.get(11)?,
                row.get(12)?,
            ),
        )?);
    }
    Ok(records)
}

pub fn set_secretary_memory_proposal_state(
    conn: &Connection,
    key: &[u8; 32],
    id: &str,
    state: &str,
    now_ms: i64,
) -> Result<SecretaryMemoryProposalRecord> {
    if ![
        SECRETARY_MEMORY_PROPOSAL_STATE_PENDING,
        SECRETARY_MEMORY_PROPOSAL_STATE_ACCEPTED,
        SECRETARY_MEMORY_PROPOSAL_STATE_DISMISSED,
    ]
    .contains(&state)
    {
        return Err(anyhow!("invalid secretary memory proposal state: {state}"));
    }

    conn.execute(
        r#"
UPDATE secretary_memory_proposals
SET state = ?2,
    updated_at_ms = ?3,
    accepted_at_ms = CASE WHEN ?2 = 'accepted' THEN ?3 ELSE accepted_at_ms END,
    dismissed_at_ms = CASE WHEN ?2 = 'dismissed' THEN ?3 ELSE dismissed_at_ms END
WHERE id = ?1
"#,
        params![id, state, now_ms],
    )?;
    let record = get_secretary_memory_proposal(conn, key, id)?;
    insert_secretary_oplog(
        conn,
        key,
        "secretary.memory_proposal.state.v1",
        record.updated_at_ms,
        serde_json::json!({
            "proposal_id": record.id,
            "state": record.state,
            "updated_at_ms": record.updated_at_ms,
            "accepted_at_ms": record.accepted_at_ms,
            "dismissed_at_ms": record.dismissed_at_ms,
        }),
    )?;
    Ok(record)
}

fn planning_output_title_aad(id: &str) -> Vec<u8> {
    format!("planning_output.title:{id}").into_bytes()
}

fn planning_output_body_aad(id: &str) -> Vec<u8> {
    format!("planning_output.body:{id}").into_bytes()
}

fn planning_output_items_aad(id: &str) -> Vec<u8> {
    format!("planning_output.items_json:{id}").into_bytes()
}

fn planning_output_source_refs_aad(id: &str) -> Vec<u8> {
    format!("planning_output.source_refs_json:{id}").into_bytes()
}

type PlanningOutputRow = (
    String,
    String,
    Vec<u8>,
    Vec<u8>,
    Vec<u8>,
    Option<Vec<u8>>,
    String,
    String,
    i64,
    i64,
    Option<i64>,
    Option<i64>,
);

fn planning_output_from_row(key: &[u8; 32], row: PlanningOutputRow) -> Result<PlanningOutputRecord> {
    let (
        id,
        kind,
        title_blob,
        body_blob,
        items_blob,
        source_refs_blob,
        route,
        state,
        created_at_ms,
        updated_at_ms,
        expires_at_ms,
        dismissed_at_ms,
    ) = row;
    Ok(PlanningOutputRecord {
        title: decrypted_secretary_string(
            key,
            &title_blob,
            planning_output_title_aad(&id),
            "planning output title",
        )?,
        body: decrypted_secretary_string(
            key,
            &body_blob,
            planning_output_body_aad(&id),
            "planning output body",
        )?,
        items_json: decrypted_secretary_string(
            key,
            &items_blob,
            planning_output_items_aad(&id),
            "planning output items",
        )?,
        source_refs_json: decrypted_secretary_optional_string(
            key,
            source_refs_blob,
            planning_output_source_refs_aad(&id),
            "planning output source refs",
        )?,
        id,
        kind,
        route,
        state,
        created_at_ms,
        updated_at_ms,
        expires_at_ms,
        dismissed_at_ms,
    })
}

pub fn upsert_planning_output(
    conn: &Connection,
    key: &[u8; 32],
    input: NewPlanningOutput,
) -> Result<PlanningOutputRecord> {
    let title_blob = encrypted_secretary_string(
        key,
        input.title.as_str(),
        planning_output_title_aad(&input.id),
    )?;
    let body_blob =
        encrypted_secretary_string(key, input.body.as_str(), planning_output_body_aad(&input.id))?;
    let items_blob = encrypted_secretary_string(
        key,
        input.items_json.as_str(),
        planning_output_items_aad(&input.id),
    )?;
    let source_refs_blob = encrypted_secretary_optional_string(
        key,
        input.source_refs_json.as_deref(),
        planning_output_source_refs_aad(&input.id),
    )?;

    conn.execute(
        r#"
INSERT INTO planning_outputs(
  id, kind, title, body, items_json, source_refs_json, route, state,
  created_at_ms, updated_at_ms, expires_at_ms, dismissed_at_ms
)
VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?11, NULL)
ON CONFLICT(id) DO UPDATE SET
  kind = excluded.kind,
  title = excluded.title,
  body = excluded.body,
  items_json = excluded.items_json,
  source_refs_json = excluded.source_refs_json,
  route = excluded.route,
  state = excluded.state,
  updated_at_ms = excluded.updated_at_ms,
  expires_at_ms = excluded.expires_at_ms,
  dismissed_at_ms = CASE
    WHEN excluded.state = 'dismissed' THEN excluded.updated_at_ms
    ELSE planning_outputs.dismissed_at_ms
  END
"#,
        params![
            input.id.as_str(),
            input.kind.as_str(),
            title_blob,
            body_blob,
            items_blob,
            source_refs_blob,
            input.route.as_str(),
            input.state.as_str(),
            input.created_at_ms,
            input.updated_at_ms,
            input.expires_at_ms,
        ],
    )?;
    let record = get_planning_output(conn, key, &input.id)?;
    insert_planning_output_upsert_op(conn, key, &record)?;
    Ok(record)
}

fn insert_planning_output_upsert_op(
    conn: &Connection,
    key: &[u8; 32],
    record: &PlanningOutputRecord,
) -> Result<()> {
    insert_secretary_oplog(
        conn,
        key,
        "planning.output.upsert.v1",
        record.updated_at_ms,
        serde_json::json!({
            "output_id": record.id,
            "kind": record.kind,
            "title": record.title,
            "body": record.body,
            "items_json": record.items_json,
            "source_refs_json": record.source_refs_json,
            "route": record.route,
            "state": record.state,
            "created_at_ms": record.created_at_ms,
            "updated_at_ms": record.updated_at_ms,
            "expires_at_ms": record.expires_at_ms,
            "dismissed_at_ms": record.dismissed_at_ms,
        }),
    )
}

pub fn get_planning_output(
    conn: &Connection,
    key: &[u8; 32],
    id: &str,
) -> Result<PlanningOutputRecord> {
    let row = conn
        .query_row(
            r#"
SELECT id, kind, title, body, items_json, source_refs_json, route, state,
       created_at_ms, updated_at_ms, expires_at_ms, dismissed_at_ms
FROM planning_outputs
WHERE id = ?1
"#,
            params![id],
            |row| {
                Ok((
                    row.get(0)?,
                    row.get(1)?,
                    row.get(2)?,
                    row.get(3)?,
                    row.get(4)?,
                    row.get(5)?,
                    row.get(6)?,
                    row.get(7)?,
                    row.get(8)?,
                    row.get(9)?,
                    row.get(10)?,
                    row.get(11)?,
                ))
            },
        )
        .optional()?
        .ok_or_else(|| anyhow!("planning output not found"))?;
    planning_output_from_row(key, row)
}

pub fn list_planning_outputs(
    conn: &Connection,
    key: &[u8; 32],
    kind: Option<&str>,
    now_ms: i64,
    include_expired: bool,
) -> Result<Vec<PlanningOutputRecord>> {
    let mut sql = String::from(
        r#"
SELECT id, kind, title, body, items_json, source_refs_json, route, state,
       created_at_ms, updated_at_ms, expires_at_ms, dismissed_at_ms
FROM planning_outputs
WHERE 1 = 1
"#,
    );
    if kind.is_some() {
        sql.push_str(" AND kind = ?1");
    }
    if !include_expired {
        sql.push_str(" AND (expires_at_ms IS NULL OR expires_at_ms > ?");
        sql.push_str(if kind.is_some() { "2)" } else { "1)" });
    }
    sql.push_str(" ORDER BY updated_at_ms DESC, created_at_ms DESC, id ASC");

    let mut stmt = conn.prepare(&sql)?;
    let mut rows = match (kind, include_expired) {
        (Some(kind), false) => stmt.query(params![kind, now_ms])?,
        (Some(kind), true) => stmt.query(params![kind])?,
        (None, false) => stmt.query(params![now_ms])?,
        (None, true) => stmt.query([])?,
    };
    let mut records = Vec::new();
    while let Some(row) = rows.next()? {
        records.push(planning_output_from_row(
            key,
            (
                row.get(0)?,
                row.get(1)?,
                row.get(2)?,
                row.get(3)?,
                row.get(4)?,
                row.get(5)?,
                row.get(6)?,
                row.get(7)?,
                row.get(8)?,
                row.get(9)?,
                row.get(10)?,
                row.get(11)?,
            ),
        )?);
    }
    Ok(records)
}

fn secretary_run_input_aad(id: &str) -> Vec<u8> {
    format!("secretary_run.input_summary:{id}").into_bytes()
}

fn secretary_run_output_aad(id: &str) -> Vec<u8> {
    format!("secretary_run.output_summary:{id}").into_bytes()
}

fn secretary_run_error_aad(id: &str) -> Vec<u8> {
    format!("secretary_run.error:{id}").into_bytes()
}

type SecretaryRunRow = (
    String,
    String,
    String,
    String,
    Option<Vec<u8>>,
    Option<Vec<u8>>,
    Option<Vec<u8>>,
    i64,
    i64,
);

fn secretary_run_from_row(key: &[u8; 32], row: SecretaryRunRow) -> Result<SecretaryRunRecord> {
    let (
        id,
        trigger_kind,
        route,
        status,
        input_blob,
        output_blob,
        error_blob,
        created_at_ms,
        updated_at_ms,
    ) = row;
    Ok(SecretaryRunRecord {
        input_summary: decrypted_secretary_optional_string(
            key,
            input_blob,
            secretary_run_input_aad(&id),
            "secretary run input summary",
        )?,
        output_summary: decrypted_secretary_optional_string(
            key,
            output_blob,
            secretary_run_output_aad(&id),
            "secretary run output summary",
        )?,
        error: decrypted_secretary_optional_string(
            key,
            error_blob,
            secretary_run_error_aad(&id),
            "secretary run error",
        )?,
        id,
        trigger_kind,
        route,
        status,
        created_at_ms,
        updated_at_ms,
    })
}

pub fn create_secretary_run(
    conn: &Connection,
    key: &[u8; 32],
    input: NewSecretaryRun,
) -> Result<SecretaryRunRecord> {
    let id = uuid::Uuid::new_v4().to_string();
    let input_blob = encrypted_secretary_optional_string(
        key,
        input.input_summary.as_deref(),
        secretary_run_input_aad(&id),
    )?;
    let output_blob = encrypted_secretary_optional_string(
        key,
        input.output_summary.as_deref(),
        secretary_run_output_aad(&id),
    )?;
    let error_blob =
        encrypted_secretary_optional_string(key, input.error.as_deref(), secretary_run_error_aad(&id))?;
    conn.execute(
        r#"
INSERT INTO secretary_runs(
  id, trigger_kind, route, status, input_summary, output_summary, error,
  created_at_ms, updated_at_ms
)
VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?8)
"#,
        params![
            id.as_str(),
            input.trigger_kind.as_str(),
            input.route.as_str(),
            input.status.as_str(),
            input_blob,
            output_blob,
            error_blob,
            input.now_ms,
        ],
    )?;
    let record = get_secretary_run(conn, key, &id)?;
    insert_secretary_run_upsert_op(conn, key, &record)?;
    Ok(record)
}

fn insert_secretary_run_upsert_op(
    conn: &Connection,
    key: &[u8; 32],
    record: &SecretaryRunRecord,
) -> Result<()> {
    insert_secretary_oplog(
        conn,
        key,
        "secretary.run.upsert.v1",
        record.updated_at_ms,
        serde_json::json!({
            "run_id": record.id,
            "trigger_kind": record.trigger_kind,
            "route": record.route,
            "status": record.status,
            "input_summary": record.input_summary,
            "output_summary": record.output_summary,
            "error": record.error,
            "created_at_ms": record.created_at_ms,
            "updated_at_ms": record.updated_at_ms,
        }),
    )
}

pub fn get_secretary_run(conn: &Connection, key: &[u8; 32], id: &str) -> Result<SecretaryRunRecord> {
    let row = conn
        .query_row(
            r#"
SELECT id, trigger_kind, route, status, input_summary, output_summary, error,
       created_at_ms, updated_at_ms
FROM secretary_runs
WHERE id = ?1
"#,
            params![id],
            |row| {
                Ok((
                    row.get(0)?,
                    row.get(1)?,
                    row.get(2)?,
                    row.get(3)?,
                    row.get(4)?,
                    row.get(5)?,
                    row.get(6)?,
                    row.get(7)?,
                    row.get(8)?,
                ))
            },
        )
        .optional()?
        .ok_or_else(|| anyhow!("secretary run not found"))?;
    secretary_run_from_row(key, row)
}

fn secretary_tool_call_input_aad(id: &str) -> Vec<u8> {
    format!("secretary_tool_call.input_json:{id}").into_bytes()
}

fn secretary_tool_call_output_aad(id: &str) -> Vec<u8> {
    format!("secretary_tool_call.output_json:{id}").into_bytes()
}

type SecretaryToolCallRow = (
    String,
    String,
    String,
    String,
    i64,
    Option<Vec<u8>>,
    Option<Vec<u8>>,
    i64,
    i64,
);

fn secretary_tool_call_from_row(
    key: &[u8; 32],
    row: SecretaryToolCallRow,
) -> Result<SecretaryToolCallRecord> {
    let (
        id,
        run_id,
        tool_name,
        status,
        requires_confirmation,
        input_blob,
        output_blob,
        created_at_ms,
        updated_at_ms,
    ) = row;
    Ok(SecretaryToolCallRecord {
        input_json: decrypted_secretary_optional_string(
            key,
            input_blob,
            secretary_tool_call_input_aad(&id),
            "secretary tool call input json",
        )?,
        output_json: decrypted_secretary_optional_string(
            key,
            output_blob,
            secretary_tool_call_output_aad(&id),
            "secretary tool call output json",
        )?,
        id,
        run_id,
        tool_name,
        status,
        requires_confirmation: requires_confirmation != 0,
        created_at_ms,
        updated_at_ms,
    })
}

pub fn create_secretary_tool_call(
    conn: &Connection,
    key: &[u8; 32],
    input: NewSecretaryToolCall,
) -> Result<SecretaryToolCallRecord> {
    let id = uuid::Uuid::new_v4().to_string();
    let input_blob = encrypted_secretary_optional_string(
        key,
        input.input_json.as_deref(),
        secretary_tool_call_input_aad(&id),
    )?;
    let output_blob = encrypted_secretary_optional_string(
        key,
        input.output_json.as_deref(),
        secretary_tool_call_output_aad(&id),
    )?;
    conn.execute(
        r#"
INSERT INTO secretary_tool_calls(
  id, run_id, tool_name, status, requires_confirmation, input_json, output_json,
  created_at_ms, updated_at_ms
)
VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?8)
"#,
        params![
            id.as_str(),
            input.run_id.as_str(),
            input.tool_name.as_str(),
            input.status.as_str(),
            if input.requires_confirmation { 1i64 } else { 0i64 },
            input_blob,
            output_blob,
            input.now_ms,
        ],
    )?;
    let record = get_secretary_tool_call(conn, key, &id)?;
    insert_secretary_tool_call_upsert_op(conn, key, &record)?;
    Ok(record)
}

fn insert_secretary_tool_call_upsert_op(
    conn: &Connection,
    key: &[u8; 32],
    record: &SecretaryToolCallRecord,
) -> Result<()> {
    insert_secretary_oplog(
        conn,
        key,
        "secretary.tool_call.upsert.v1",
        record.updated_at_ms,
        serde_json::json!({
            "tool_call_id": record.id,
            "run_id": record.run_id,
            "tool_name": record.tool_name,
            "status": record.status,
            "requires_confirmation": record.requires_confirmation,
            "input_json": record.input_json,
            "output_json": record.output_json,
            "created_at_ms": record.created_at_ms,
            "updated_at_ms": record.updated_at_ms,
        }),
    )
}

pub fn get_secretary_tool_call(
    conn: &Connection,
    key: &[u8; 32],
    id: &str,
) -> Result<SecretaryToolCallRecord> {
    let row = conn
        .query_row(
            r#"
SELECT id, run_id, tool_name, status, requires_confirmation, input_json,
       output_json, created_at_ms, updated_at_ms
FROM secretary_tool_calls
WHERE id = ?1
"#,
            params![id],
            |row| {
                Ok((
                    row.get(0)?,
                    row.get(1)?,
                    row.get(2)?,
                    row.get(3)?,
                    row.get(4)?,
                    row.get(5)?,
                    row.get(6)?,
                    row.get(7)?,
                    row.get(8)?,
                ))
            },
        )
        .optional()?
        .ok_or_else(|| anyhow!("secretary tool call not found"))?;
    secretary_tool_call_from_row(key, row)
}

pub fn list_secretary_tool_calls_for_run(
    conn: &Connection,
    key: &[u8; 32],
    run_id: &str,
) -> Result<Vec<SecretaryToolCallRecord>> {
    let mut stmt = conn.prepare(
        r#"
SELECT id, run_id, tool_name, status, requires_confirmation, input_json,
       output_json, created_at_ms, updated_at_ms
FROM secretary_tool_calls
WHERE run_id = ?1
ORDER BY created_at_ms ASC, id ASC
"#,
    )?;
    let mut rows = stmt.query(params![run_id])?;
    let mut records = Vec::new();
    while let Some(row) = rows.next()? {
        records.push(secretary_tool_call_from_row(
            key,
            (
                row.get(0)?,
                row.get(1)?,
                row.get(2)?,
                row.get(3)?,
                row.get(4)?,
                row.get(5)?,
                row.get(6)?,
                row.get(7)?,
                row.get(8)?,
            ),
        )?);
    }
    Ok(records)
}
