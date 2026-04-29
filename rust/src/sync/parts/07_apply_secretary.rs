fn sync_payload_str<'a>(payload: &'a serde_json::Value, op: &str, field: &str) -> Result<&'a str> {
    payload[field]
        .as_str()
        .ok_or_else(|| anyhow!("{op} missing {field}"))
}

fn sync_payload_i64(payload: &serde_json::Value, op: &str, field: &str) -> Result<i64> {
    payload[field]
        .as_i64()
        .ok_or_else(|| anyhow!("{op} missing {field}"))
}

fn sync_payload_opt_i64(payload: &serde_json::Value, field: &str) -> Option<i64> {
    payload.get(field).and_then(|value| value.as_i64())
}

fn sync_payload_opt_str<'a>(payload: &'a serde_json::Value, field: &str) -> Option<&'a str> {
    payload.get(field).and_then(|value| value.as_str())
}

fn secretary_memory_proposal_title_aad_for_sync(id: &str) -> Vec<u8> {
    format!("secretary_memory_proposal.title:{id}").into_bytes()
}

fn secretary_memory_proposal_body_aad_for_sync(id: &str) -> Vec<u8> {
    format!("secretary_memory_proposal.body:{id}").into_bytes()
}

fn secretary_memory_proposal_source_refs_aad_for_sync(id: &str) -> Vec<u8> {
    format!("secretary_memory_proposal.source_refs_json:{id}").into_bytes()
}

fn planning_output_title_aad_for_sync(id: &str) -> Vec<u8> {
    format!("planning_output.title:{id}").into_bytes()
}

fn planning_output_body_aad_for_sync(id: &str) -> Vec<u8> {
    format!("planning_output.body:{id}").into_bytes()
}

fn planning_output_items_aad_for_sync(id: &str) -> Vec<u8> {
    format!("planning_output.items_json:{id}").into_bytes()
}

fn planning_output_source_refs_aad_for_sync(id: &str) -> Vec<u8> {
    format!("planning_output.source_refs_json:{id}").into_bytes()
}

fn secretary_run_input_aad_for_sync(id: &str) -> Vec<u8> {
    format!("secretary_run.input_summary:{id}").into_bytes()
}

fn secretary_run_output_aad_for_sync(id: &str) -> Vec<u8> {
    format!("secretary_run.output_summary:{id}").into_bytes()
}

fn secretary_run_error_aad_for_sync(id: &str) -> Vec<u8> {
    format!("secretary_run.error:{id}").into_bytes()
}

fn secretary_tool_call_input_aad_for_sync(id: &str) -> Vec<u8> {
    format!("secretary_tool_call.input_json:{id}").into_bytes()
}

fn secretary_tool_call_output_aad_for_sync(id: &str) -> Vec<u8> {
    format!("secretary_tool_call.output_json:{id}").into_bytes()
}

fn knowledge_page_compiled_title_aad_for_sync(page_id: &str) -> Vec<u8> {
    format!("knowledge_page.compiled_title:{page_id}").into_bytes()
}

fn knowledge_page_compiled_summary_aad_for_sync(page_id: &str) -> Vec<u8> {
    format!("knowledge_page.compiled_summary:{page_id}").into_bytes()
}

fn knowledge_page_compiled_body_aad_for_sync(page_id: &str) -> Vec<u8> {
    format!("knowledge_page.compiled_body:{page_id}").into_bytes()
}

fn knowledge_page_manual_title_aad_for_sync(page_id: &str) -> Vec<u8> {
    format!("knowledge_page.manual_title:{page_id}").into_bytes()
}

fn knowledge_page_manual_summary_aad_for_sync(page_id: &str) -> Vec<u8> {
    format!("knowledge_page.manual_summary:{page_id}").into_bytes()
}

fn knowledge_page_manual_body_aad_for_sync(page_id: &str) -> Vec<u8> {
    format!("knowledge_page.manual_body:{page_id}").into_bytes()
}

fn encrypt_sync_string(key: &[u8; 32], value: &str, aad: Vec<u8>) -> Result<Vec<u8>> {
    encrypt_bytes(key, value.as_bytes(), aad.as_ref())
}

fn encrypt_sync_optional_string(
    key: &[u8; 32],
    value: Option<&str>,
    aad: Vec<u8>,
) -> Result<Option<Vec<u8>>> {
    value
        .map(|value| encrypt_sync_string(key, value, aad.clone()))
        .transpose()
}

fn apply_secretary_memory_proposal_upsert(
    conn: &Connection,
    db_key: &[u8; 32],
    payload: &serde_json::Value,
) -> Result<()> {
    let op = "secretary.memory_proposal.upsert.v1";
    let id = sync_payload_str(payload, op, "proposal_id")?;
    let updated_at_ms = sync_payload_i64(payload, op, "updated_at_ms")?;
    let existing_updated_at_ms: Option<i64> = conn
        .query_row(
            "SELECT updated_at_ms FROM secretary_memory_proposals WHERE id = ?1",
            params![id],
            |row| row.get(0),
        )
        .optional()?;
    if existing_updated_at_ms.is_some_and(|existing| updated_at_ms < existing) {
        return Ok(());
    }

    let title = encrypt_sync_string(
        db_key,
        sync_payload_str(payload, op, "title")?,
        secretary_memory_proposal_title_aad_for_sync(id),
    )?;
    let body = encrypt_sync_string(
        db_key,
        sync_payload_str(payload, op, "body")?,
        secretary_memory_proposal_body_aad_for_sync(id),
    )?;
    let source_refs_json = encrypt_sync_optional_string(
        db_key,
        sync_payload_opt_str(payload, "source_refs_json"),
        secretary_memory_proposal_source_refs_aad_for_sync(id),
    )?;
    conn.execute(
        r#"
INSERT INTO secretary_memory_proposals(
  id, source_message_id, kind, title, body, confidence, state, source_refs_json,
  action_hint, created_at_ms, updated_at_ms, accepted_at_ms, dismissed_at_ms
)
VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?11, ?12, ?13)
ON CONFLICT(id) DO UPDATE SET
  source_message_id = excluded.source_message_id,
  kind = excluded.kind,
  title = excluded.title,
  body = excluded.body,
  confidence = excluded.confidence,
  state = excluded.state,
  source_refs_json = excluded.source_refs_json,
  action_hint = excluded.action_hint,
  created_at_ms = min(secretary_memory_proposals.created_at_ms, excluded.created_at_ms),
  updated_at_ms = excluded.updated_at_ms,
  accepted_at_ms = excluded.accepted_at_ms,
  dismissed_at_ms = excluded.dismissed_at_ms
"#,
        params![
            id,
            sync_payload_opt_str(payload, "source_message_id"),
            sync_payload_str(payload, op, "kind")?,
            title,
            body,
            payload["confidence"].as_f64().unwrap_or(0.0),
            sync_payload_str(payload, op, "state")?,
            source_refs_json,
            sync_payload_opt_str(payload, "action_hint"),
            sync_payload_i64(payload, op, "created_at_ms")?,
            updated_at_ms,
            sync_payload_opt_i64(payload, "accepted_at_ms"),
            sync_payload_opt_i64(payload, "dismissed_at_ms"),
        ],
    )?;
    Ok(())
}

fn apply_secretary_memory_proposal_state(
    conn: &Connection,
    payload: &serde_json::Value,
) -> Result<()> {
    let op = "secretary.memory_proposal.state.v1";
    let id = sync_payload_str(payload, op, "proposal_id")?;
    let updated_at_ms = sync_payload_i64(payload, op, "updated_at_ms")?;
    conn.execute(
        r#"
UPDATE secretary_memory_proposals
SET state = ?2,
    updated_at_ms = ?3,
    accepted_at_ms = ?4,
    dismissed_at_ms = ?5
WHERE id = ?1
  AND updated_at_ms <= ?3
"#,
        params![
            id,
            sync_payload_str(payload, op, "state")?,
            updated_at_ms,
            sync_payload_opt_i64(payload, "accepted_at_ms"),
            sync_payload_opt_i64(payload, "dismissed_at_ms"),
        ],
    )?;
    Ok(())
}

fn apply_knowledge_page_upsert(
    conn: &Connection,
    db_key: &[u8; 32],
    payload: &serde_json::Value,
) -> Result<()> {
    let op = "knowledge.page.upsert.v1";
    let page_id = sync_payload_str(payload, op, "page_id")?;
    let updated_at_ms = sync_payload_i64(payload, op, "updated_at_ms")?;
    let existing: Option<(i64, i64, Option<Vec<u8>>, Option<Vec<u8>>, Option<Vec<u8>>)> = conn
        .query_row(
            r#"
SELECT updated_at_ms, human_corrected, manual_title, manual_summary, manual_body
FROM knowledge_pages
WHERE page_id = ?1
"#,
            params![page_id],
            |row| {
                Ok((
                    row.get(0)?,
                    row.get(1)?,
                    row.get(2)?,
                    row.get(3)?,
                    row.get(4)?,
                ))
            },
        )
        .optional()?;
    if existing
        .as_ref()
        .is_some_and(|(existing_updated_at_ms, _, _, _, _)| updated_at_ms < *existing_updated_at_ms)
    {
        return Ok(());
    }

    let incoming_human_corrected = payload["human_corrected"].as_bool().unwrap_or(false);
    let existing_human_corrected = existing
        .as_ref()
        .map(|(_, human_corrected, _, _, _)| *human_corrected != 0)
        .unwrap_or(false);
    let title = sync_payload_str(payload, op, "title")?;
    let summary = sync_payload_str(payload, op, "summary")?;
    let body = sync_payload_str(payload, op, "body")?;
    let compiled_title = encrypt_sync_string(
        db_key,
        title,
        knowledge_page_compiled_title_aad_for_sync(page_id),
    )?;
    let compiled_summary = encrypt_sync_string(
        db_key,
        summary,
        knowledge_page_compiled_summary_aad_for_sync(page_id),
    )?;
    let compiled_body = encrypt_sync_string(
        db_key,
        body,
        knowledge_page_compiled_body_aad_for_sync(page_id),
    )?;
    let (manual_title, manual_summary, manual_body, human_corrected) =
        if incoming_human_corrected {
            (
                Some(encrypt_sync_string(
                    db_key,
                    title,
                    knowledge_page_manual_title_aad_for_sync(page_id),
                )?),
                Some(encrypt_sync_string(
                    db_key,
                    summary,
                    knowledge_page_manual_summary_aad_for_sync(page_id),
                )?),
                Some(encrypt_sync_string(
                    db_key,
                    body,
                    knowledge_page_manual_body_aad_for_sync(page_id),
                )?),
                1i64,
            )
        } else if existing_human_corrected {
            let (_, _, manual_title, manual_summary, manual_body) = existing.expect("existing");
            (manual_title, manual_summary, manual_body, 1i64)
        } else {
            (None, None, None, 0i64)
        };

    conn.execute(
        r#"
INSERT INTO knowledge_pages(
  page_id, page_type, state, answer_default_allowed,
  answer_requires_temporal_framing, confidence_level, source_count,
  conflict_count, created_at_ms, updated_at_ms, last_used_at_ms,
  human_corrected, tags_json, primary_evidence_json,
  related_page_ids_json, source_document_ids_json, claim_ids_json,
  compiled_title, compiled_summary, compiled_body,
  manual_title, manual_summary, manual_body
)
VALUES (?1, ?2, ?3, 1, 0, ?4, ?5, 0, ?6, ?7, NULL, ?8, '[]', ?9, '[]', ?10,
        '[]', ?11, ?12, ?13, ?14, ?15, ?16)
ON CONFLICT(page_id) DO UPDATE SET
  page_type = excluded.page_type,
  state = excluded.state,
  confidence_level = excluded.confidence_level,
  source_count = excluded.source_count,
  created_at_ms = min(knowledge_pages.created_at_ms, excluded.created_at_ms),
  updated_at_ms = excluded.updated_at_ms,
  human_corrected = excluded.human_corrected,
  primary_evidence_json = excluded.primary_evidence_json,
  source_document_ids_json = excluded.source_document_ids_json,
  compiled_title = excluded.compiled_title,
  compiled_summary = excluded.compiled_summary,
  compiled_body = excluded.compiled_body,
  manual_title = excluded.manual_title,
  manual_summary = excluded.manual_summary,
  manual_body = excluded.manual_body
"#,
        params![
            page_id,
            sync_payload_str(payload, op, "page_type")?,
            sync_payload_str(payload, op, "state")?,
            payload["confidence_level"].as_f64().unwrap_or(0.0),
            sync_payload_i64(payload, op, "source_count")?,
            sync_payload_i64(payload, op, "created_at_ms")?,
            updated_at_ms,
            human_corrected,
            sync_payload_str(payload, op, "primary_evidence_json")?,
            sync_payload_str(payload, op, "source_document_ids_json")?,
            compiled_title,
            compiled_summary,
            compiled_body,
            manual_title,
            manual_summary,
            manual_body,
        ],
    )?;
    Ok(())
}

fn apply_knowledge_page_state(conn: &Connection, payload: &serde_json::Value) -> Result<()> {
    let op = "knowledge.page.state.v1";
    let page_id = sync_payload_str(payload, op, "page_id")?;
    let updated_at_ms = sync_payload_i64(payload, op, "updated_at_ms")?;
    conn.execute(
        r#"
UPDATE knowledge_pages
SET state = ?2,
    updated_at_ms = ?3
WHERE page_id = ?1
  AND updated_at_ms <= ?3
"#,
        params![page_id, sync_payload_str(payload, op, "state")?, updated_at_ms],
    )?;
    Ok(())
}

fn apply_planning_output_upsert(
    conn: &Connection,
    db_key: &[u8; 32],
    payload: &serde_json::Value,
) -> Result<()> {
    let op = "planning.output.upsert.v1";
    let id = sync_payload_str(payload, op, "output_id")?;
    let updated_at_ms = sync_payload_i64(payload, op, "updated_at_ms")?;
    let existing_updated_at_ms: Option<i64> = conn
        .query_row(
            "SELECT updated_at_ms FROM planning_outputs WHERE id = ?1",
            params![id],
            |row| row.get(0),
        )
        .optional()?;
    if existing_updated_at_ms.is_some_and(|existing| updated_at_ms < existing) {
        return Ok(());
    }

    let title = encrypt_sync_string(
        db_key,
        sync_payload_str(payload, op, "title")?,
        planning_output_title_aad_for_sync(id),
    )?;
    let body = encrypt_sync_string(
        db_key,
        sync_payload_str(payload, op, "body")?,
        planning_output_body_aad_for_sync(id),
    )?;
    let items = encrypt_sync_string(
        db_key,
        sync_payload_str(payload, op, "items_json")?,
        planning_output_items_aad_for_sync(id),
    )?;
    let source_refs = encrypt_sync_optional_string(
        db_key,
        sync_payload_opt_str(payload, "source_refs_json"),
        planning_output_source_refs_aad_for_sync(id),
    )?;
    conn.execute(
        r#"
INSERT INTO planning_outputs(
  id, kind, title, body, items_json, source_refs_json, route, state,
  created_at_ms, updated_at_ms, expires_at_ms, dismissed_at_ms
)
VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?11, ?12)
ON CONFLICT(id) DO UPDATE SET
  kind = excluded.kind,
  title = excluded.title,
  body = excluded.body,
  items_json = excluded.items_json,
  source_refs_json = excluded.source_refs_json,
  route = excluded.route,
  state = excluded.state,
  created_at_ms = min(planning_outputs.created_at_ms, excluded.created_at_ms),
  updated_at_ms = excluded.updated_at_ms,
  expires_at_ms = excluded.expires_at_ms,
  dismissed_at_ms = excluded.dismissed_at_ms
"#,
        params![
            id,
            sync_payload_str(payload, op, "kind")?,
            title,
            body,
            items,
            source_refs,
            sync_payload_str(payload, op, "route")?,
            sync_payload_str(payload, op, "state")?,
            sync_payload_i64(payload, op, "created_at_ms")?,
            updated_at_ms,
            sync_payload_opt_i64(payload, "expires_at_ms"),
            sync_payload_opt_i64(payload, "dismissed_at_ms"),
        ],
    )?;
    Ok(())
}

fn apply_planning_output_state(conn: &Connection, payload: &serde_json::Value) -> Result<()> {
    let op = "planning.output.state.v1";
    let id = sync_payload_str(payload, op, "output_id")?;
    let updated_at_ms = sync_payload_i64(payload, op, "updated_at_ms")?;
    conn.execute(
        r#"
UPDATE planning_outputs
SET state = ?2,
    updated_at_ms = ?3,
    dismissed_at_ms = ?4
WHERE id = ?1
  AND updated_at_ms <= ?3
"#,
        params![
            id,
            sync_payload_str(payload, op, "state")?,
            updated_at_ms,
            sync_payload_opt_i64(payload, "dismissed_at_ms"),
        ],
    )?;
    Ok(())
}

fn apply_secretary_run_upsert(
    conn: &Connection,
    db_key: &[u8; 32],
    payload: &serde_json::Value,
) -> Result<()> {
    let op = "secretary.run.upsert.v1";
    let id = sync_payload_str(payload, op, "run_id")?;
    let updated_at_ms = sync_payload_i64(payload, op, "updated_at_ms")?;
    let existing_updated_at_ms: Option<i64> = conn
        .query_row(
            "SELECT updated_at_ms FROM secretary_runs WHERE id = ?1",
            params![id],
            |row| row.get(0),
        )
        .optional()?;
    if existing_updated_at_ms.is_some_and(|existing| updated_at_ms < existing) {
        return Ok(());
    }
    let input = encrypt_sync_optional_string(
        db_key,
        sync_payload_opt_str(payload, "input_summary"),
        secretary_run_input_aad_for_sync(id),
    )?;
    let output = encrypt_sync_optional_string(
        db_key,
        sync_payload_opt_str(payload, "output_summary"),
        secretary_run_output_aad_for_sync(id),
    )?;
    let error = encrypt_sync_optional_string(
        db_key,
        sync_payload_opt_str(payload, "error"),
        secretary_run_error_aad_for_sync(id),
    )?;
    conn.execute(
        r#"
INSERT INTO secretary_runs(
  id, trigger_kind, route, status, input_summary, output_summary, error,
  created_at_ms, updated_at_ms
)
VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9)
ON CONFLICT(id) DO UPDATE SET
  trigger_kind = excluded.trigger_kind,
  route = excluded.route,
  status = excluded.status,
  input_summary = excluded.input_summary,
  output_summary = excluded.output_summary,
  error = excluded.error,
  created_at_ms = min(secretary_runs.created_at_ms, excluded.created_at_ms),
  updated_at_ms = excluded.updated_at_ms
"#,
        params![
            id,
            sync_payload_str(payload, op, "trigger_kind")?,
            sync_payload_str(payload, op, "route")?,
            sync_payload_str(payload, op, "status")?,
            input,
            output,
            error,
            sync_payload_i64(payload, op, "created_at_ms")?,
            updated_at_ms,
        ],
    )?;
    Ok(())
}

fn apply_secretary_tool_call_upsert(
    conn: &Connection,
    db_key: &[u8; 32],
    payload: &serde_json::Value,
) -> Result<()> {
    let op = "secretary.tool_call.upsert.v1";
    let id = sync_payload_str(payload, op, "tool_call_id")?;
    let updated_at_ms = sync_payload_i64(payload, op, "updated_at_ms")?;
    let existing_updated_at_ms: Option<i64> = conn
        .query_row(
            "SELECT updated_at_ms FROM secretary_tool_calls WHERE id = ?1",
            params![id],
            |row| row.get(0),
        )
        .optional()?;
    if existing_updated_at_ms.is_some_and(|existing| updated_at_ms < existing) {
        return Ok(());
    }
    let input = encrypt_sync_optional_string(
        db_key,
        sync_payload_opt_str(payload, "input_json"),
        secretary_tool_call_input_aad_for_sync(id),
    )?;
    let output = encrypt_sync_optional_string(
        db_key,
        sync_payload_opt_str(payload, "output_json"),
        secretary_tool_call_output_aad_for_sync(id),
    )?;
    conn.execute(
        r#"
INSERT INTO secretary_tool_calls(
  id, run_id, tool_name, status, requires_confirmation, input_json, output_json,
  created_at_ms, updated_at_ms
)
VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9)
ON CONFLICT(id) DO UPDATE SET
  run_id = excluded.run_id,
  tool_name = excluded.tool_name,
  status = excluded.status,
  requires_confirmation = excluded.requires_confirmation,
  input_json = excluded.input_json,
  output_json = excluded.output_json,
  created_at_ms = min(secretary_tool_calls.created_at_ms, excluded.created_at_ms),
  updated_at_ms = excluded.updated_at_ms
"#,
        params![
            id,
            sync_payload_str(payload, op, "run_id")?,
            sync_payload_str(payload, op, "tool_name")?,
            sync_payload_str(payload, op, "status")?,
            if payload["requires_confirmation"].as_bool().unwrap_or(false) {
                1i64
            } else {
                0i64
            },
            input,
            output,
            sync_payload_i64(payload, op, "created_at_ms")?,
            updated_at_ms,
        ],
    )?;
    Ok(())
}
