const MEMORY_PAGE_TYPE: &str = "memory";
const MEMORY_PAGE_STATE_ACTIVE: &str = "active";
const MEMORY_PAGE_STATE_ARCHIVED: &str = "archived";

fn knowledge_page_compiled_title_aad(page_id: &str) -> Vec<u8> {
    format!("knowledge_page.compiled_title:{page_id}").into_bytes()
}

fn knowledge_page_compiled_summary_aad(page_id: &str) -> Vec<u8> {
    format!("knowledge_page.compiled_summary:{page_id}").into_bytes()
}

fn knowledge_page_compiled_body_aad(page_id: &str) -> Vec<u8> {
    format!("knowledge_page.compiled_body:{page_id}").into_bytes()
}

fn knowledge_page_manual_title_aad(page_id: &str) -> Vec<u8> {
    format!("knowledge_page.manual_title:{page_id}").into_bytes()
}

fn knowledge_page_manual_summary_aad(page_id: &str) -> Vec<u8> {
    format!("knowledge_page.manual_summary:{page_id}").into_bytes()
}

fn knowledge_page_manual_body_aad(page_id: &str) -> Vec<u8> {
    format!("knowledge_page.manual_body:{page_id}").into_bytes()
}

fn knowledge_page_version_title_aad(version_id: &str) -> Vec<u8> {
    format!("knowledge_page_version.title:{version_id}").into_bytes()
}

fn knowledge_page_version_summary_aad(version_id: &str) -> Vec<u8> {
    format!("knowledge_page_version.summary:{version_id}").into_bytes()
}

fn knowledge_page_version_body_aad(version_id: &str) -> Vec<u8> {
    format!("knowledge_page_version.body:{version_id}").into_bytes()
}

type MemoryPageRow = (
    String,
    String,
    String,
    i64,
    i64,
    i64,
    f64,
    i64,
    String,
    String,
    Vec<u8>,
    Vec<u8>,
    Vec<u8>,
    Option<Vec<u8>>,
    Option<Vec<u8>>,
    Option<Vec<u8>>,
);

fn memory_page_from_row(key: &[u8; 32], row: MemoryPageRow) -> Result<MemoryPageRecord> {
    let (
        page_id,
        page_type,
        state,
        source_count,
        created_at_ms,
        updated_at_ms,
        confidence_level,
        human_corrected,
        primary_evidence_json,
        source_document_ids_json,
        compiled_title_blob,
        compiled_summary_blob,
        compiled_body_blob,
        manual_title_blob,
        manual_summary_blob,
        manual_body_blob,
    ) = row;

    let compiled_title = decrypted_secretary_string(
        key,
        &compiled_title_blob,
        knowledge_page_compiled_title_aad(&page_id),
        "knowledge page compiled title",
    )?;
    let compiled_summary = decrypted_secretary_string(
        key,
        &compiled_summary_blob,
        knowledge_page_compiled_summary_aad(&page_id),
        "knowledge page compiled summary",
    )?;
    let compiled_body = decrypted_secretary_string(
        key,
        &compiled_body_blob,
        knowledge_page_compiled_body_aad(&page_id),
        "knowledge page compiled body",
    )?;
    let manual_title = decrypted_secretary_optional_string(
        key,
        manual_title_blob,
        knowledge_page_manual_title_aad(&page_id),
        "knowledge page manual title",
    )?;
    let manual_summary = decrypted_secretary_optional_string(
        key,
        manual_summary_blob,
        knowledge_page_manual_summary_aad(&page_id),
        "knowledge page manual summary",
    )?;
    let manual_body = decrypted_secretary_optional_string(
        key,
        manual_body_blob,
        knowledge_page_manual_body_aad(&page_id),
        "knowledge page manual body",
    )?;

    Ok(MemoryPageRecord {
        page_id,
        page_type,
        state,
        source_count,
        title: manual_title.unwrap_or(compiled_title),
        summary: manual_summary.unwrap_or(compiled_summary),
        body: manual_body.unwrap_or(compiled_body),
        primary_evidence_json,
        source_document_ids_json,
        confidence_level,
        human_corrected: human_corrected != 0,
        created_at_ms,
        updated_at_ms,
    })
}

fn get_memory_page_row(conn: &Connection, page_id: &str) -> Result<MemoryPageRow> {
    conn.query_row(
        r#"
SELECT page_id, page_type, state, source_count, created_at_ms, updated_at_ms,
       confidence_level, human_corrected, primary_evidence_json,
       source_document_ids_json, compiled_title, compiled_summary, compiled_body,
       manual_title, manual_summary, manual_body
FROM knowledge_pages
WHERE page_id = ?1 AND page_type = ?2
"#,
        params![page_id, MEMORY_PAGE_TYPE],
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
                row.get(13)?,
                row.get(14)?,
                row.get(15)?,
            ))
        },
    )
    .optional()?
    .ok_or_else(|| anyhow!("memory page not found"))
}

pub fn create_memory_page_from_proposal(
    conn: &Connection,
    key: &[u8; 32],
    proposal_id: &str,
    now_ms: i64,
) -> Result<MemoryPageRecord> {
    run_immediate_transaction(conn, || {
        let proposal = get_secretary_memory_proposal(conn, key, proposal_id)?;
        let page_id = uuid::Uuid::new_v4().to_string();
        let title_blob = encrypted_secretary_string(
            key,
            proposal.title.as_str(),
            knowledge_page_compiled_title_aad(&page_id),
        )?;
        let summary_blob = encrypted_secretary_string(
            key,
            proposal.body.as_str(),
            knowledge_page_compiled_summary_aad(&page_id),
        )?;
        let body_blob = encrypted_secretary_string(
            key,
            proposal.body.as_str(),
            knowledge_page_compiled_body_aad(&page_id),
        )?;
        let primary_evidence_json = proposal
            .source_refs_json
            .as_deref()
            .filter(|value| !value.trim().is_empty())
            .unwrap_or("[]")
            .to_string();
        let source_document_ids_json = match proposal.source_message_id.as_deref() {
            Some(source_message_id) => serde_json::to_string(&vec![source_message_id])?,
            None => "[]".to_string(),
        };
        let source_count = if proposal.source_message_id.is_some() { 1 } else { 0 };
        let tags_json = serde_json::to_string(&vec![proposal.kind.as_str()])?;

        conn.execute(
            r#"
INSERT INTO knowledge_pages(
  page_id, page_type, state, answer_default_allowed,
  answer_requires_temporal_framing, confidence_level, source_count,
  conflict_count, created_at_ms, updated_at_ms, last_used_at_ms,
  human_corrected, tags_json, primary_evidence_json,
  related_page_ids_json, source_document_ids_json, claim_ids_json,
  compiled_title, compiled_summary, compiled_body, manual_title,
  manual_summary, manual_body
)
VALUES (
  ?1, ?2, 'active', 1,
  0, ?3, ?4,
  0, ?5, ?5, NULL,
  0, ?6, ?7,
  '[]', ?8, '[]',
  ?9, ?10, ?11, NULL,
  NULL, NULL
)
"#,
            params![
                page_id.as_str(),
                MEMORY_PAGE_TYPE,
                proposal.confidence,
                source_count,
                now_ms,
                tags_json,
                primary_evidence_json,
                source_document_ids_json,
                title_blob,
                summary_blob,
                body_blob,
            ],
        )?;

        set_secretary_memory_proposal_state(
            conn,
            key,
            proposal_id,
            SECRETARY_MEMORY_PROPOSAL_STATE_ACCEPTED,
            now_ms,
        )?;
        insert_memory_page_history(
            conn,
            &page_id,
            "memory.accepted",
            "user",
            Some("Accepted secretary memory proposal"),
            now_ms,
        )?;
        get_memory_page(conn, key, &page_id)
    })
}

pub fn get_memory_page(
    conn: &Connection,
    key: &[u8; 32],
    page_id: &str,
) -> Result<MemoryPageRecord> {
    memory_page_from_row(key, get_memory_page_row(conn, page_id)?)
}

pub fn list_memory_pages(
    conn: &Connection,
    key: &[u8; 32],
    state: Option<&str>,
) -> Result<Vec<MemoryPageRecord>> {
    let sql = if state.is_some() {
        r#"
SELECT page_id, page_type, state, source_count, created_at_ms, updated_at_ms,
       confidence_level, human_corrected, primary_evidence_json,
       source_document_ids_json, compiled_title, compiled_summary, compiled_body,
       manual_title, manual_summary, manual_body
FROM knowledge_pages
WHERE page_type = ?1 AND state = ?2
ORDER BY updated_at_ms DESC, page_id ASC
"#
    } else {
        r#"
SELECT page_id, page_type, state, source_count, created_at_ms, updated_at_ms,
       confidence_level, human_corrected, primary_evidence_json,
       source_document_ids_json, compiled_title, compiled_summary, compiled_body,
       manual_title, manual_summary, manual_body
FROM knowledge_pages
WHERE page_type = ?1
ORDER BY updated_at_ms DESC, page_id ASC
"#
    };
    let mut stmt = conn.prepare(sql)?;
    let mut rows = if let Some(state) = state {
        stmt.query(params![MEMORY_PAGE_TYPE, state])?
    } else {
        stmt.query(params![MEMORY_PAGE_TYPE])?
    };
    let mut result = Vec::new();
    while let Some(row) = rows.next()? {
        result.push(memory_page_from_row(
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
                row.get(13)?,
                row.get(14)?,
                row.get(15)?,
            ),
        )?);
    }
    Ok(result)
}

pub fn correct_memory_page(
    conn: &Connection,
    key: &[u8; 32],
    input: CorrectMemoryPageInput,
) -> Result<MemoryPageRecord> {
    run_immediate_transaction(conn, || {
        let current = get_memory_page(conn, key, &input.page_id)?;
        insert_memory_page_version(
            conn,
            key,
            &current,
            "memory.corrected",
            "user",
            input.reason.as_deref(),
            input.now_ms,
        )?;

        let manual_title = encrypted_secretary_string(
            key,
            input.title.as_str(),
            knowledge_page_manual_title_aad(&input.page_id),
        )?;
        let manual_summary = encrypted_secretary_string(
            key,
            input.summary.as_str(),
            knowledge_page_manual_summary_aad(&input.page_id),
        )?;
        let manual_body = encrypted_secretary_string(
            key,
            input.body.as_str(),
            knowledge_page_manual_body_aad(&input.page_id),
        )?;
        conn.execute(
            r#"
UPDATE knowledge_pages
SET manual_title = ?2,
    manual_summary = ?3,
    manual_body = ?4,
    human_corrected = 1,
    updated_at_ms = ?5
WHERE page_id = ?1 AND page_type = ?6
"#,
            params![
                input.page_id.as_str(),
                manual_title,
                manual_summary,
                manual_body,
                input.now_ms,
                MEMORY_PAGE_TYPE,
            ],
        )?;
        insert_memory_page_history(
            conn,
            &input.page_id,
            "memory.corrected",
            "user",
            input.reason.as_deref().or(Some("User corrected memory")),
            input.now_ms,
        )?;
        get_memory_page(conn, key, &input.page_id)
    })
}

pub fn archive_memory_page(
    conn: &Connection,
    key: &[u8; 32],
    page_id: &str,
    now_ms: i64,
) -> Result<MemoryPageRecord> {
    set_memory_page_state(conn, key, page_id, MEMORY_PAGE_STATE_ARCHIVED, "memory.archived", now_ms)
}

pub fn restore_memory_page(
    conn: &Connection,
    key: &[u8; 32],
    page_id: &str,
    now_ms: i64,
) -> Result<MemoryPageRecord> {
    set_memory_page_state(conn, key, page_id, MEMORY_PAGE_STATE_ACTIVE, "memory.restored", now_ms)
}

fn set_memory_page_state(
    conn: &Connection,
    key: &[u8; 32],
    page_id: &str,
    state: &str,
    change_type: &str,
    now_ms: i64,
) -> Result<MemoryPageRecord> {
    run_immediate_transaction(conn, || {
        conn.execute(
            r#"
UPDATE knowledge_pages
SET state = ?2,
    updated_at_ms = ?3
WHERE page_id = ?1 AND page_type = ?4
"#,
            params![page_id, state, now_ms, MEMORY_PAGE_TYPE],
        )?;
        insert_memory_page_history(conn, page_id, change_type, "user", None, now_ms)?;
        get_memory_page(conn, key, page_id)
    })
}

fn insert_memory_page_history(
    conn: &Connection,
    page_id: &str,
    change_type: &str,
    actor: &str,
    reason: Option<&str>,
    now_ms: i64,
) -> Result<()> {
    conn.execute(
        r#"
INSERT INTO knowledge_page_history(
  change_id, page_id, change_type, actor, reason, answer_impacted, created_at_ms
)
VALUES (?1, ?2, ?3, ?4, ?5, 1, ?6)
"#,
        params![
            uuid::Uuid::new_v4().to_string(),
            page_id,
            change_type,
            actor,
            reason,
            now_ms,
        ],
    )?;
    Ok(())
}

fn insert_memory_page_version(
    conn: &Connection,
    key: &[u8; 32],
    page: &MemoryPageRecord,
    change_type: &str,
    actor: &str,
    reason: Option<&str>,
    now_ms: i64,
) -> Result<()> {
    let version_id = uuid::Uuid::new_v4().to_string();
    let title = encrypted_secretary_string(
        key,
        page.title.as_str(),
        knowledge_page_version_title_aad(&version_id),
    )?;
    let summary = encrypted_secretary_string(
        key,
        page.summary.as_str(),
        knowledge_page_version_summary_aad(&version_id),
    )?;
    let body = encrypted_secretary_string(
        key,
        page.body.as_str(),
        knowledge_page_version_body_aad(&version_id),
    )?;
    conn.execute(
        r#"
INSERT INTO knowledge_page_versions(
  version_id, page_id, change_type, actor, reason, state,
  answer_default_allowed, answer_requires_temporal_framing, confidence_level,
  source_count, conflict_count, human_corrected, title, summary, body,
  created_at_ms
)
VALUES (?1, ?2, ?3, ?4, ?5, ?6, 1, 0, ?7, 0, 0, ?8, ?9, ?10, ?11, ?12)
"#,
        params![
            version_id,
            page.page_id.as_str(),
            change_type,
            actor,
            reason,
            page.state.as_str(),
            page.confidence_level,
            if page.human_corrected { 1i64 } else { 0i64 },
            title,
            summary,
            body,
            now_ms,
        ],
    )?;
    Ok(())
}
