fn knowledge_document_text_aad(document_id: &str, field: &str) -> Vec<u8> {
    format!("knowledge.document.{field}:{document_id}").into_bytes()
}

fn knowledge_unit_text_aad(unit_id: &str, field: &str) -> Vec<u8> {
    format!("knowledge.unit.{field}:{unit_id}").into_bytes()
}

fn knowledge_page_text_aad(page_id: &str, field: &str) -> Vec<u8> {
    format!("knowledge.page.{field}:{page_id}").into_bytes()
}

fn knowledge_page_version_text_aad(version_id: &str, field: &str) -> Vec<u8> {
    format!("knowledge.page.version.{field}:{version_id}").into_bytes()
}

fn knowledge_claim_text_aad(claim_id: &str, field: &str) -> Vec<u8> {
    format!("knowledge.claim.{field}:{claim_id}").into_bytes()
}

fn default_knowledge_memory_feedback() -> crate::knowledge::KnowledgeMemoryFeedback {
    crate::knowledge::KnowledgeMemoryFeedback {
        status: None,
        use_for_ask_ai: true,
        is_deleted: false,
        marked_inaccurate: false,
        corrected_title: None,
        corrected_summary: None,
        updated_at_ms: None,
    }
}

fn normalize_optional_trimmed(value: Option<String>) -> Option<String> {
    value.and_then(|raw| {
        let trimmed = raw.trim();
        if trimmed.is_empty() {
            None
        } else {
            Some(trimmed.to_string())
        }
    })
}

fn normalize_knowledge_string_set(values: &[String], max_len: usize) -> Vec<String> {
    let mut out = std::collections::BTreeSet::<String>::new();
    for value in values {
        let trimmed = value.trim();
        if trimmed.is_empty() {
            continue;
        }
        out.insert(trimmed.to_string());
        if out.len() >= max_len {
            break;
        }
    }
    out.into_iter().collect()
}

fn merge_page_text(primary: &str, secondary: &str) -> String {
    let primary = primary.trim();
    let secondary = secondary.trim();
    match (primary.is_empty(), secondary.is_empty()) {
        (true, true) => String::new(),
        (false, true) => primary.to_string(),
        (true, false) => secondary.to_string(),
        (false, false) => crate::knowledge::memory_dedup::merge_lines(primary, secondary),
    }
}

fn encode_knowledge_memory_status(
    status: Option<crate::knowledge::KnowledgeMemoryStatus>,
) -> Result<Option<String>> {
    status
        .map(|value| -> Result<String> {
            Ok(serde_json::to_string(&value)?.trim_matches('"').to_string())
        })
        .transpose()
}

fn decode_knowledge_memory_status(
    raw: Option<String>,
) -> Result<Option<crate::knowledge::KnowledgeMemoryStatus>> {
    raw.map(|value| {
        serde_json::from_str::<crate::knowledge::KnowledgeMemoryStatus>(&format!("\"{value}\""))
            .map_err(anyhow::Error::from)
    })
    .transpose()
}

type KnowledgeMemoryFeedbackRow = (
    Option<String>,
    i64,
    i64,
    i64,
    Option<String>,
    Option<String>,
    i64,
    i64,
    String,
    i64,
);

fn load_existing_knowledge_memory_feedback_row(
    conn: &Connection,
    document_id: &str,
) -> Result<Option<KnowledgeMemoryFeedbackRow>> {
    conn.query_row(
        r#"SELECT status,
                  use_for_ask_ai,
                  is_deleted,
                  marked_inaccurate,
                  corrected_title,
                  corrected_summary,
                  created_at_ms,
                  updated_at_ms,
                  COALESCE(updated_by_device_id, ''),
                  COALESCE(updated_by_seq, 0)
           FROM knowledge_document_feedback
           WHERE document_id = ?1"#,
        params![document_id],
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
            ))
        },
    )
    .optional()
    .map_err(Into::into)
}

pub fn encode_knowledge_document_text(
    key: &[u8; 32],
    document_id: &str,
    field: &str,
    text: &str,
) -> Result<Vec<u8>> {
    encrypt_bytes(key, text.as_bytes(), &knowledge_document_text_aad(document_id, field))
}

pub fn decode_knowledge_document_text(
    key: &[u8; 32],
    document_id: &str,
    field: &str,
    blob: &[u8],
) -> Result<String> {
    let bytes = decrypt_bytes(key, blob, &knowledge_document_text_aad(document_id, field))?;
    String::from_utf8(bytes).map_err(|_| anyhow!("knowledge document text is not valid utf-8"))
}

pub fn encode_knowledge_unit_text(
    key: &[u8; 32],
    unit_id: &str,
    field: &str,
    text: &str,
) -> Result<Vec<u8>> {
    encrypt_bytes(key, text.as_bytes(), &knowledge_unit_text_aad(unit_id, field))
}

pub fn decode_knowledge_unit_text(
    key: &[u8; 32],
    unit_id: &str,
    field: &str,
    blob: &[u8],
) -> Result<String> {
    let bytes = decrypt_bytes(key, blob, &knowledge_unit_text_aad(unit_id, field))?;
    String::from_utf8(bytes).map_err(|_| anyhow!("knowledge unit text is not valid utf-8"))
}

pub fn encode_knowledge_page_text(
    key: &[u8; 32],
    page_id: &str,
    field: &str,
    text: &str,
) -> Result<Vec<u8>> {
    encrypt_bytes(key, text.as_bytes(), &knowledge_page_text_aad(page_id, field))
}

pub fn decode_knowledge_page_text(
    key: &[u8; 32],
    page_id: &str,
    field: &str,
    blob: &[u8],
) -> Result<String> {
    let bytes = decrypt_bytes(key, blob, &knowledge_page_text_aad(page_id, field))?;
    String::from_utf8(bytes).map_err(|_| anyhow!("knowledge page text is not valid utf-8"))
}

pub fn encode_knowledge_claim_text(
    key: &[u8; 32],
    claim_id: &str,
    field: &str,
    text: &str,
) -> Result<Vec<u8>> {
    encrypt_bytes(key, text.as_bytes(), &knowledge_claim_text_aad(claim_id, field))
}

pub fn decode_knowledge_claim_text(
    key: &[u8; 32],
    claim_id: &str,
    field: &str,
    blob: &[u8],
) -> Result<String> {
    let bytes = decrypt_bytes(key, blob, &knowledge_claim_text_aad(claim_id, field))?;
    String::from_utf8(bytes).map_err(|_| anyhow!("knowledge claim text is not valid utf-8"))
}

pub fn encode_knowledge_page_version_text(
    key: &[u8; 32],
    version_id: &str,
    field: &str,
    text: &str,
) -> Result<Vec<u8>> {
    encrypt_bytes(
        key,
        text.as_bytes(),
        &knowledge_page_version_text_aad(version_id, field),
    )
}

pub fn decode_knowledge_page_version_text(
    key: &[u8; 32],
    version_id: &str,
    field: &str,
    blob: &[u8],
) -> Result<String> {
    let bytes = decrypt_bytes(key, blob, &knowledge_page_version_text_aad(version_id, field))?;
    String::from_utf8(bytes)
        .map_err(|_| anyhow!("knowledge page version text is not valid utf-8"))
}

pub fn get_knowledge_memory_feedback(
    conn: &Connection,
    document_id: &str,
) -> Result<crate::knowledge::KnowledgeMemoryFeedback> {
    let row = conn
        .query_row(
            r#"SELECT status,
                      use_for_ask_ai,
                      is_deleted,
                      marked_inaccurate,
                      corrected_title,
                      corrected_summary,
                      updated_at_ms
               FROM knowledge_document_feedback
               WHERE document_id = ?1"#,
            params![document_id],
            |row| {
                Ok((
                    row.get::<_, Option<String>>(0)?,
                    row.get::<_, i64>(1)?,
                    row.get::<_, i64>(2)?,
                    row.get::<_, i64>(3)?,
                    row.get::<_, Option<String>>(4)?,
                    row.get::<_, Option<String>>(5)?,
                    row.get::<_, Option<i64>>(6)?,
                ))
            },
        )
        .optional()?;
    let Some((status, use_for_ask_ai, is_deleted, marked_inaccurate, corrected_title, corrected_summary, updated_at_ms)) = row else {
        return Ok(default_knowledge_memory_feedback());
    };
    Ok(crate::knowledge::KnowledgeMemoryFeedback {
        status: decode_knowledge_memory_status(status)?,
        use_for_ask_ai: use_for_ask_ai != 0,
        is_deleted: is_deleted != 0,
        marked_inaccurate: marked_inaccurate != 0,
        corrected_title: normalize_optional_trimmed(corrected_title),
        corrected_summary: normalize_optional_trimmed(corrected_summary),
        updated_at_ms,
    })
}

pub fn load_knowledge_memory_feedback_map(
    conn: &Connection,
    document_ids: &std::collections::BTreeSet<String>,
) -> Result<std::collections::BTreeMap<String, crate::knowledge::KnowledgeMemoryFeedback>> {
    let mut out = std::collections::BTreeMap::new();
    if document_ids.is_empty() {
        return Ok(out);
    }

    let placeholders = document_ids
        .iter()
        .enumerate()
        .map(|(index, _)| format!("?{}", index + 1))
        .collect::<Vec<_>>()
        .join(", ");
    let sql = format!(
        r#"SELECT document_id,
                  status,
                  use_for_ask_ai,
                  is_deleted,
                  marked_inaccurate,
                  corrected_title,
                  corrected_summary,
                  updated_at_ms
           FROM knowledge_document_feedback
           WHERE document_id IN ({placeholders})"#
    );
    let values = document_ids.iter().map(String::as_str).collect::<Vec<_>>();

    let mut stmt = conn.prepare(&sql)?;
    let mut rows = stmt.query(rusqlite::params_from_iter(values.iter().copied()))?;
    while let Some(row) = rows.next()? {
        let document_id: String = row.get(0)?;
        let status: Option<String> = row.get(1)?;
        let use_for_ask_ai: i64 = row.get(2)?;
        let is_deleted: i64 = row.get(3)?;
        let marked_inaccurate: i64 = row.get(4)?;
        let corrected_title: Option<String> = row.get(5)?;
        let corrected_summary: Option<String> = row.get(6)?;
        let updated_at_ms: Option<i64> = row.get(7)?;

        out.insert(
            document_id,
            crate::knowledge::KnowledgeMemoryFeedback {
                status: decode_knowledge_memory_status(status)?,
                use_for_ask_ai: use_for_ask_ai != 0,
                is_deleted: is_deleted != 0,
                marked_inaccurate: marked_inaccurate != 0,
                corrected_title: normalize_optional_trimmed(corrected_title),
                corrected_summary: normalize_optional_trimmed(corrected_summary),
                updated_at_ms,
            },
        );
    }

    for document_id in document_ids {
        out.entry(document_id.clone())
            .or_insert_with(default_knowledge_memory_feedback);
    }

    Ok(out)
}

#[allow(clippy::too_many_arguments)]
pub fn upsert_knowledge_memory_feedback(
    conn: &Connection,
    key: &[u8; 32],
    document_id: &str,
    status: Option<crate::knowledge::KnowledgeMemoryStatus>,
    use_for_ask_ai: bool,
    is_deleted: bool,
    marked_inaccurate: bool,
    corrected_title: Option<String>,
    corrected_summary: Option<String>,
) -> Result<crate::knowledge::KnowledgeMemoryFeedback> {
    let now = now_ms();
    let encoded_status = encode_knowledge_memory_status(status)?;
    let corrected_title = normalize_optional_trimmed(corrected_title);
    let corrected_summary = normalize_optional_trimmed(corrected_summary);
    let existing = load_existing_knowledge_memory_feedback_row(conn, document_id)?;
    let created_at_ms = existing
        .as_ref()
        .map(|row| row.6)
        .unwrap_or(now);
    conn.execute_batch("BEGIN IMMEDIATE;")?;
    let result = (|| -> Result<crate::knowledge::KnowledgeMemoryFeedback> {
        let device_id = get_or_create_device_id(conn)?;
        let seq = next_device_seq(conn, &device_id)?;
        conn.execute(
            r#"INSERT INTO knowledge_document_feedback(
                   document_id,
                   status,
                   use_for_ask_ai,
                   is_deleted,
                   marked_inaccurate,
                   corrected_title,
                   corrected_summary,
                   created_at_ms,
                   updated_at_ms,
                   updated_by_device_id,
                   updated_by_seq
               ) VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?11)
               ON CONFLICT(document_id) DO UPDATE SET
                 status = excluded.status,
                 use_for_ask_ai = excluded.use_for_ask_ai,
                 is_deleted = excluded.is_deleted,
                 marked_inaccurate = excluded.marked_inaccurate,
                 corrected_title = excluded.corrected_title,
                 corrected_summary = excluded.corrected_summary,
                 updated_at_ms = excluded.updated_at_ms,
                 updated_by_device_id = excluded.updated_by_device_id,
                 updated_by_seq = excluded.updated_by_seq"#,
            params![
                document_id,
                encoded_status,
                if use_for_ask_ai { 1 } else { 0 },
                if is_deleted { 1 } else { 0 },
                if marked_inaccurate { 1 } else { 0 },
                corrected_title,
                corrected_summary,
                created_at_ms,
                now,
                device_id.as_str(),
                seq,
            ],
        )?;
        let op = serde_json::json!({
            "op_id": uuid::Uuid::new_v4().to_string(),
            "device_id": device_id.as_str(),
            "seq": seq,
            "ts_ms": now,
            "type": "knowledge.memory_feedback.upsert.v1",
            "payload": {
                "document_id": document_id,
                "status": status.map(|value| serde_json::to_string(&value))
                    .transpose()?
                    .map(|value| value.trim_matches('"').to_string()),
                "use_for_ask_ai": use_for_ask_ai,
                "is_deleted": is_deleted,
                "marked_inaccurate": marked_inaccurate,
                "corrected_title": corrected_title,
                "corrected_summary": corrected_summary,
                "created_at_ms": created_at_ms,
                "updated_at_ms": now,
            }
        });
        insert_oplog(conn, key, &op)?;
        get_knowledge_memory_feedback(conn, document_id)
    })();

    match result {
        Ok(feedback) => match conn.execute_batch("COMMIT;") {
            Ok(()) => Ok(feedback),
            Err(error) => {
                let _ = conn.execute_batch("ROLLBACK;");
                Err(error.into())
            }
        },
        Err(error) => {
            let _ = conn.execute_batch("ROLLBACK;");
            Err(error)
        }
    }
}

const KV_KNOWLEDGE_MEMORY_FEEDBACK_OPLOG_BACKFILLED: &str =
    "oplog.backfill.knowledge_memory_feedback.v1";

pub fn backfill_knowledge_memory_feedback_oplog_if_needed(
    conn: &Connection,
    key: &[u8; 32],
) -> Result<u64> {
    if kv_get_string(conn, KV_KNOWLEDGE_MEMORY_FEEDBACK_OPLOG_BACKFILLED)?.is_some() {
        return Ok(0);
    }

    conn.execute_batch("BEGIN IMMEDIATE;")?;
    let result = (|| -> Result<u64> {
        let device_id = get_or_create_device_id(conn)?;
        let mut stmt = conn.prepare(
            r#"SELECT document_id,
                      status,
                      use_for_ask_ai,
                      is_deleted,
                      marked_inaccurate,
                      corrected_title,
                      corrected_summary,
                      created_at_ms,
                      updated_at_ms
               FROM knowledge_document_feedback
               ORDER BY updated_at_ms ASC, document_id ASC"#,
        )?;
        let mut rows = stmt.query([])?;
        let mut inserted = 0u64;
        while let Some(row) = rows.next()? {
            let document_id: String = row.get(0)?;
            let status: Option<String> = row.get(1)?;
            let use_for_ask_ai: i64 = row.get(2)?;
            let is_deleted: i64 = row.get(3)?;
            let marked_inaccurate: i64 = row.get(4)?;
            let corrected_title: Option<String> = row.get(5)?;
            let corrected_summary: Option<String> = row.get(6)?;
            let created_at_ms: i64 = row.get(7)?;
            let updated_at_ms: i64 = row.get(8)?;
            let seq = next_device_seq(conn, &device_id)?;

            conn.execute(
                r#"UPDATE knowledge_document_feedback
                   SET updated_by_device_id = ?2,
                       updated_by_seq = ?3
                   WHERE document_id = ?1"#,
                params![document_id, device_id.as_str(), seq],
            )?;

            let op = serde_json::json!({
                "op_id": uuid::Uuid::new_v4().to_string(),
                "device_id": device_id.as_str(),
                "seq": seq,
                "ts_ms": updated_at_ms,
                "type": "knowledge.memory_feedback.upsert.v1",
                "payload": {
                    "document_id": document_id,
                    "status": status,
                    "use_for_ask_ai": use_for_ask_ai != 0,
                    "is_deleted": is_deleted != 0,
                    "marked_inaccurate": marked_inaccurate != 0,
                    "corrected_title": normalize_optional_trimmed(corrected_title),
                    "corrected_summary": normalize_optional_trimmed(corrected_summary),
                    "created_at_ms": created_at_ms,
                    "updated_at_ms": updated_at_ms,
                }
            });
            insert_oplog(conn, key, &op)?;
            inserted += 1;
        }

        kv_set_string(conn, KV_KNOWLEDGE_MEMORY_FEEDBACK_OPLOG_BACKFILLED, "1")?;
        Ok(inserted)
    })();

    match result {
        Ok(inserted) => match conn.execute_batch("COMMIT;") {
            Ok(()) => Ok(inserted),
            Err(error) => {
                let _ = conn.execute_batch("ROLLBACK;");
                Err(error.into())
            }
        },
        Err(error) => {
            let _ = conn.execute_batch("ROLLBACK;");
            Err(error)
        }
    }
}

pub fn ensure_knowledge_rebuild_state_defaults(conn: &Connection) -> Result<()> {
    conn.execute(
        r#"INSERT OR IGNORE INTO knowledge_rebuild_state(
               state_key,
               knowledge_schema_version,
               normalization_version,
               segmentation_version,
               embedding_policy_version,
               retrieval_policy_version,
               last_indexed_model_name,
               last_indexed_dim,
               status,
               rebuild_required,
               stale_reason,
               last_error,
               last_rebuild_started_at_ms,
               last_rebuild_completed_at_ms,
               current_document_id,
               current_stage,
               documents_indexed,
               units_indexed,
               embeddings_indexed,
               total_documents,
               cancel_requested
           ) VALUES (?1, ?2, ?3, ?4, ?5, ?6, NULL, NULL, 'empty', 0, NULL, NULL, NULL, NULL, NULL, NULL, 0, 0, 0, 0, 0)"#,
        params![
            1i64,
            crate::knowledge::KNOWLEDGE_SCHEMA_VERSION,
            crate::knowledge::KNOWLEDGE_NORMALIZATION_VERSION,
            crate::knowledge::KNOWLEDGE_SEGMENTATION_VERSION,
            crate::knowledge::KNOWLEDGE_EMBEDDING_POLICY_VERSION,
            crate::knowledge::KNOWLEDGE_RETRIEVAL_POLICY_VERSION,
        ],
    )?;
    Ok(())
}

fn load_existing_knowledge_document_ids(
    conn: &Connection,
    document_ids: &std::collections::BTreeSet<String>,
) -> Result<Vec<String>> {
    if document_ids.is_empty() {
        return Ok(Vec::new());
    }

    let placeholders = document_ids
        .iter()
        .enumerate()
        .map(|(index, _)| format!("?{}", index + 1))
        .collect::<Vec<_>>()
        .join(", ");
    let sql = format!(
        "SELECT document_id FROM knowledge_documents WHERE document_id IN ({placeholders})"
    );
    let values = document_ids.iter().map(String::as_str).collect::<Vec<_>>();

    let mut stmt = conn.prepare(&sql)?;
    let mut rows = stmt.query(rusqlite::params_from_iter(values.iter().copied()))?;
    let mut out = Vec::<String>::new();
    while let Some(row) = rows.next()? {
        out.push(row.get(0)?);
    }
    Ok(out)
}

pub fn load_knowledge_usage_map(
    conn: &Connection,
    document_ids: &std::collections::BTreeSet<String>,
) -> Result<std::collections::BTreeMap<String, crate::knowledge::usage::KnowledgeUsageStats>> {
    let mut out = std::collections::BTreeMap::new();
    if document_ids.is_empty() {
        return Ok(out);
    }

    let placeholders = document_ids
        .iter()
        .enumerate()
        .map(|(index, _)| format!("?{}", index + 1))
        .collect::<Vec<_>>()
        .join(", ");
    let sql = format!(
        "SELECT document_id, retrieve_count, last_retrieved_at_ms \
         FROM knowledge_document_usage \
         WHERE document_id IN ({placeholders})"
    );
    let values = document_ids.iter().map(String::as_str).collect::<Vec<_>>();

    let mut stmt = conn.prepare(&sql)?;
    let mut rows = stmt.query(rusqlite::params_from_iter(values.iter().copied()))?;
    while let Some(row) = rows.next()? {
        let document_id: String = row.get(0)?;
        out.insert(
            document_id,
            crate::knowledge::usage::KnowledgeUsageStats {
                retrieve_count: row.get(1)?,
                last_retrieved_at_ms: row.get(2)?,
            },
        );
    }

    Ok(out)
}

pub fn touch_knowledge_documents_usage(
    conn: &Connection,
    document_ids: &[String],
    now_ms: i64,
) -> Result<usize> {
    let unique = document_ids
        .iter()
        .filter(|value| !value.trim().is_empty())
        .cloned()
        .collect::<std::collections::BTreeSet<_>>();
    if unique.is_empty() {
        return Ok(0);
    }

    let existing = load_existing_knowledge_document_ids(conn, &unique)?;
    if existing.is_empty() {
        return Ok(0);
    }

    for document_id in &existing {
        conn.execute(
            r#"INSERT INTO knowledge_document_usage(document_id, retrieve_count, last_retrieved_at_ms)
               VALUES (?1, 1, ?2)
               ON CONFLICT(document_id)
               DO UPDATE SET
                 retrieve_count = knowledge_document_usage.retrieve_count + 1,
                 last_retrieved_at_ms = excluded.last_retrieved_at_ms"#,
            params![document_id, now_ms],
        )?;
    }
    Ok(existing.len())
}

fn encode_string_list(values: &[String]) -> Result<String> {
    Ok(serde_json::to_string(values)?)
}

fn decode_string_list(raw: String) -> Result<Vec<String>> {
    Ok(serde_json::from_str(&raw)?)
}

fn encode_page_state(state: crate::knowledge::KnowledgePageState) -> Result<String> {
    Ok(serde_json::to_string(&state)?.trim_matches('"').to_string())
}

fn decode_page_state(raw: String) -> Result<crate::knowledge::KnowledgePageState> {
    Ok(serde_json::from_str(&format!("\"{raw}\""))?)
}

fn encode_page_type(page_type: crate::knowledge::KnowledgePageType) -> Result<String> {
    Ok(serde_json::to_string(&page_type)?.trim_matches('"').to_string())
}

fn decode_page_type(raw: String) -> Result<crate::knowledge::KnowledgePageType> {
    Ok(serde_json::from_str(&format!("\"{raw}\""))?)
}

fn encode_claim_type(claim_type: crate::knowledge::KnowledgeClaimType) -> Result<String> {
    Ok(serde_json::to_string(&claim_type)?.trim_matches('"').to_string())
}

fn decode_claim_type(raw: String) -> Result<crate::knowledge::KnowledgeClaimType> {
    Ok(serde_json::from_str(&format!("\"{raw}\""))?)
}

fn encode_claim_time_scope(scope: crate::knowledge::KnowledgeClaimTimeScope) -> Result<String> {
    Ok(serde_json::to_string(&scope)?.trim_matches('"').to_string())
}

fn decode_claim_time_scope(raw: String) -> Result<crate::knowledge::KnowledgeClaimTimeScope> {
    Ok(serde_json::from_str(&format!("\"{raw}\""))?)
}

fn encode_claim_status(status: crate::knowledge::KnowledgeClaimStatus) -> Result<String> {
    Ok(serde_json::to_string(&status)?.trim_matches('"').to_string())
}

fn decode_claim_status(raw: String) -> Result<crate::knowledge::KnowledgeClaimStatus> {
    Ok(serde_json::from_str(&format!("\"{raw}\""))?)
}

fn encode_history_change_type(
    change_type: crate::knowledge::KnowledgePageChangeType,
) -> Result<String> {
    Ok(serde_json::to_string(&change_type)?.trim_matches('"').to_string())
}

fn decode_history_change_type(raw: String) -> Result<crate::knowledge::KnowledgePageChangeType> {
    Ok(serde_json::from_str(&format!("\"{raw}\""))?)
}

fn encode_lint_kind(kind: crate::knowledge::KnowledgeLintKind) -> Result<String> {
    Ok(serde_json::to_string(&kind)?.trim_matches('"').to_string())
}

fn decode_lint_kind(raw: String) -> Result<crate::knowledge::KnowledgeLintKind> {
    Ok(serde_json::from_str(&format!("\"{raw}\""))?)
}

pub fn touch_knowledge_pages_usage(
    conn: &Connection,
    page_ids: &[String],
    now_ms: i64,
) -> Result<usize> {
    let unique = page_ids
        .iter()
        .filter(|value| !value.trim().is_empty())
        .cloned()
        .collect::<std::collections::BTreeSet<_>>();
    if unique.is_empty() {
        return Ok(0);
    }
    let mut touched = 0usize;
    for page_id in unique {
        touched += conn.execute(
            "UPDATE knowledge_pages SET last_used_at_ms = ?2 WHERE page_id = ?1",
            params![page_id, now_ms],
        )?;
    }
    Ok(touched)
}

#[derive(Clone, Debug)]
struct StoredKnowledgePageRow {
    page_id: String,
    page_type: crate::knowledge::KnowledgePageType,
    state: crate::knowledge::KnowledgePageState,
    default_allowed: bool,
    requires_temporal_framing: bool,
    confidence_level: f64,
    source_count: i64,
    conflict_count: i64,
    created_at_ms: i64,
    updated_at_ms: i64,
    last_used_at_ms: Option<i64>,
    human_corrected: bool,
    tags: Vec<String>,
    primary_evidence_ids: Vec<String>,
    related_page_ids: Vec<String>,
    source_document_ids: Vec<String>,
    claim_ids: Vec<String>,
    compiled_title_blob: Vec<u8>,
    compiled_summary_blob: Vec<u8>,
    compiled_body_blob: Vec<u8>,
    manual_title_blob: Option<Vec<u8>>,
    manual_summary_blob: Option<Vec<u8>>,
    manual_body_blob: Option<Vec<u8>>,
}

fn load_stored_knowledge_page_row(
    conn: &Connection,
    page_id: &str,
) -> Result<Option<StoredKnowledgePageRow>> {
    let row = conn
        .query_row(
        r#"SELECT page_id,
                  page_type,
                  state,
                  answer_default_allowed,
                  answer_requires_temporal_framing,
                  confidence_level,
                  source_count,
                  conflict_count,
                  created_at_ms,
                  updated_at_ms,
                  last_used_at_ms,
                  human_corrected,
                  tags_json,
                  primary_evidence_json,
                  related_page_ids_json,
                  source_document_ids_json,
                  claim_ids_json,
                  compiled_title,
                  compiled_summary,
                  compiled_body,
                  manual_title,
                  manual_summary,
                  manual_body
           FROM knowledge_pages
           WHERE page_id = ?1"#,
        params![page_id],
        |row| {
            Ok((
                row.get::<_, String>(0)?,
                row.get::<_, String>(1)?,
                row.get::<_, String>(2)?,
                row.get::<_, i64>(3)?,
                row.get::<_, i64>(4)?,
                row.get::<_, f64>(5)?,
                row.get::<_, i64>(6)?,
                row.get::<_, i64>(7)?,
                row.get::<_, i64>(8)?,
                row.get::<_, i64>(9)?,
                row.get::<_, Option<i64>>(10)?,
                row.get::<_, i64>(11)?,
                row.get::<_, String>(12)?,
                row.get::<_, String>(13)?,
                row.get::<_, String>(14)?,
                row.get::<_, String>(15)?,
                row.get::<_, String>(16)?,
                row.get::<_, Vec<u8>>(17)?,
                row.get::<_, Vec<u8>>(18)?,
                row.get::<_, Vec<u8>>(19)?,
                row.get::<_, Option<Vec<u8>>>(20)?,
                row.get::<_, Option<Vec<u8>>>(21)?,
                row.get::<_, Option<Vec<u8>>>(22)?,
            ))
        },
    )
    .optional()
    .map_err(anyhow::Error::from)?;

    let Some(row) = row else {
        return Ok(None);
    };

    Ok(Some(StoredKnowledgePageRow {
        page_id: row.0,
        page_type: decode_page_type(row.1)?,
        state: decode_page_state(row.2)?,
        default_allowed: row.3 != 0,
        requires_temporal_framing: row.4 != 0,
        confidence_level: row.5,
        source_count: row.6,
        conflict_count: row.7,
        created_at_ms: row.8,
        updated_at_ms: row.9,
        last_used_at_ms: row.10,
        human_corrected: row.11 != 0,
        tags: decode_string_list(row.12)?,
        primary_evidence_ids: decode_string_list(row.13)?,
        related_page_ids: decode_string_list(row.14)?,
        source_document_ids: decode_string_list(row.15)?,
        claim_ids: decode_string_list(row.16)?,
        compiled_title_blob: row.17,
        compiled_summary_blob: row.18,
        compiled_body_blob: row.19,
        manual_title_blob: row.20,
        manual_summary_blob: row.21,
        manual_body_blob: row.22,
    }))
}

fn stored_row_to_page(
    key: &[u8; 32],
    row: &StoredKnowledgePageRow,
) -> Result<crate::knowledge::KnowledgePage> {
    let compiled_title = decode_knowledge_page_text(key, &row.page_id, "compiled_title", &row.compiled_title_blob)?;
    let compiled_summary =
        decode_knowledge_page_text(key, &row.page_id, "compiled_summary", &row.compiled_summary_blob)?;
    let compiled_body = decode_knowledge_page_text(key, &row.page_id, "compiled_body", &row.compiled_body_blob)?;
    let manual_title = row
        .manual_title_blob
        .as_ref()
        .map(|blob| decode_knowledge_page_text(key, &row.page_id, "manual_title", blob))
        .transpose()?;
    let manual_summary = row
        .manual_summary_blob
        .as_ref()
        .map(|blob| decode_knowledge_page_text(key, &row.page_id, "manual_summary", blob))
        .transpose()?;
    let manual_body = row
        .manual_body_blob
        .as_ref()
        .map(|blob| decode_knowledge_page_text(key, &row.page_id, "manual_body", blob))
        .transpose()?;

    Ok(crate::knowledge::KnowledgePage {
        page_id: row.page_id.clone(),
        page_type: row.page_type,
        title: manual_title.unwrap_or(compiled_title),
        current_summary: manual_summary.unwrap_or(compiled_summary),
        current_body: manual_body.unwrap_or(compiled_body),
        state: row.state,
        answer_policy: crate::knowledge::KnowledgeAnswerPolicy {
            default_allowed: row.default_allowed,
            requires_temporal_framing: row.requires_temporal_framing,
        },
        confidence_level: row.confidence_level,
        created_at_ms: row.created_at_ms,
        updated_at_ms: row.updated_at_ms,
        last_used_at_ms: row.last_used_at_ms,
        source_count: row.source_count,
        conflict_count: row.conflict_count,
        human_corrected: row.human_corrected,
        tags: row.tags.clone(),
        primary_evidence_ids: row.primary_evidence_ids.clone(),
        related_page_ids: row.related_page_ids.clone(),
    })
}

fn load_current_knowledge_page(
    conn: &Connection,
    key: &[u8; 32],
    page_id: &str,
) -> Result<Option<crate::knowledge::KnowledgePage>> {
    load_stored_knowledge_page_row(conn, page_id)?
        .as_ref()
        .map(|row| stored_row_to_page(key, row))
        .transpose()
}

fn evidence_kind_for_claim_status(
    status: crate::knowledge::KnowledgeClaimStatus,
) -> crate::knowledge::KnowledgePageEvidenceKind {
    match status {
        crate::knowledge::KnowledgeClaimStatus::Active
        | crate::knowledge::KnowledgeClaimStatus::Supporting => {
            crate::knowledge::KnowledgePageEvidenceKind::Support
        }
        crate::knowledge::KnowledgeClaimStatus::Disputed => {
            crate::knowledge::KnowledgePageEvidenceKind::Conflict
        }
        crate::knowledge::KnowledgeClaimStatus::Candidate
        | crate::knowledge::KnowledgeClaimStatus::Outdated
        | crate::knowledge::KnowledgeClaimStatus::Dismissed => {
            crate::knowledge::KnowledgePageEvidenceKind::Supplement
        }
    }
}

fn list_knowledge_page_history_internal(
    conn: &Connection,
    page_id: &str,
    limit: usize,
) -> Result<Vec<crate::knowledge::KnowledgePageChangeRecord>> {
    let mut stmt = conn.prepare(
        r#"SELECT change_id, page_id, change_type, actor, reason, answer_impacted, created_at_ms
           FROM knowledge_page_history
           WHERE page_id = ?1
           ORDER BY created_at_ms DESC, change_id DESC
           LIMIT ?2"#,
    )?;
    let mut rows = stmt.query(params![page_id, limit as i64])?;
    let mut out = Vec::new();
    while let Some(row) = rows.next()? {
        out.push(crate::knowledge::KnowledgePageChangeRecord {
            change_id: row.get(0)?,
            page_id: row.get(1)?,
            change_type: decode_history_change_type(row.get(2)?)?,
            actor: row.get(3)?,
            reason: normalize_optional_trimmed(row.get(4)?),
            answer_impacted: row.get::<_, i64>(5)? != 0,
            created_at_ms: row.get(6)?,
        });
    }
    Ok(out)
}

fn list_knowledge_page_version_snapshots_internal(
    conn: &Connection,
    key: &[u8; 32],
    page_id: &str,
    limit: usize,
) -> Result<Vec<crate::knowledge::KnowledgePageVersionSnapshot>> {
    let mut stmt = conn.prepare(
        r#"SELECT version_id,
                  page_id,
                  change_type,
                  actor,
                  reason,
                  state,
                  answer_default_allowed,
                  answer_requires_temporal_framing,
                  confidence_level,
                  source_count,
                  conflict_count,
                  human_corrected,
                  title,
                  summary,
                  body,
                  created_at_ms
           FROM knowledge_page_versions
           WHERE page_id = ?1
           ORDER BY created_at_ms DESC, version_id DESC
           LIMIT ?2"#,
    )?;
    let mut rows = stmt.query(params![page_id, limit as i64])?;
    let mut out = Vec::new();
    while let Some(row) = rows.next()? {
        let version_id: String = row.get(0)?;
        out.push(crate::knowledge::KnowledgePageVersionSnapshot {
            version_id: version_id.clone(),
            page_id: row.get(1)?,
            change_type: decode_history_change_type(row.get(2)?)?,
            actor: row.get(3)?,
            reason: normalize_optional_trimmed(row.get(4)?),
            state: decode_page_state(row.get(5)?)?,
            answer_policy: crate::knowledge::KnowledgeAnswerPolicy {
                default_allowed: row.get::<_, i64>(6)? != 0,
                requires_temporal_framing: row.get::<_, i64>(7)? != 0,
            },
            confidence_level: row.get(8)?,
            source_count: row.get(9)?,
            conflict_count: row.get(10)?,
            human_corrected: row.get::<_, i64>(11)? != 0,
            title: decode_knowledge_page_version_text(key, &version_id, "title", &row.get::<_, Vec<u8>>(12)?)?,
            summary: decode_knowledge_page_version_text(key, &version_id, "summary", &row.get::<_, Vec<u8>>(13)?)?,
            body: decode_knowledge_page_version_text(key, &version_id, "body", &row.get::<_, Vec<u8>>(14)?)?,
            created_at_ms: row.get(15)?,
        });
    }
    Ok(out)
}

fn list_knowledge_page_evidence_entries_internal(
    conn: &Connection,
    key: &[u8; 32],
    claim_ids: &[String],
) -> Result<Vec<crate::knowledge::KnowledgePageEvidenceEntry>> {
    let mut out = Vec::new();
    for claim_id in claim_ids {
        let row = conn
            .query_row(
                r#"SELECT statement, source_ref_ids_json, status, updated_at_ms
                   FROM knowledge_claims
                   WHERE claim_id = ?1"#,
                params![claim_id],
                |row| {
                    Ok((
                        row.get::<_, Vec<u8>>(0)?,
                        row.get::<_, String>(1)?,
                        row.get::<_, String>(2)?,
                        row.get::<_, i64>(3)?,
                    ))
                },
            )
            .optional()?;
        let Some((statement_blob, source_ref_ids_json, status_raw, updated_at_ms)) = row else {
            continue;
        };
        let status = decode_claim_status(status_raw)?;
        out.push(crate::knowledge::KnowledgePageEvidenceEntry {
            evidence_id: format!("evidence:{claim_id}"),
            kind: evidence_kind_for_claim_status(status),
            summary: decode_knowledge_claim_text(key, claim_id, "statement", &statement_blob)?,
            source_ref_ids: decode_string_list(source_ref_ids_json)?,
            created_at_ms: updated_at_ms,
        });
    }
    out.sort_by(|left, right| {
        right
            .created_at_ms
            .cmp(&left.created_at_ms)
            .then_with(|| left.evidence_id.cmp(&right.evidence_id))
    });
    Ok(out)
}

pub fn list_recent_knowledge_page_changes(
    conn: &Connection,
    limit: usize,
) -> Result<Vec<crate::knowledge::KnowledgePageChangeRecord>> {
    let mut stmt = conn.prepare(
        r#"SELECT change_id, page_id, change_type, actor, reason, answer_impacted, created_at_ms
           FROM knowledge_page_history
           ORDER BY created_at_ms DESC, change_id DESC
           LIMIT ?1"#,
    )?;
    let mut rows = stmt.query(params![limit.max(1) as i64])?;
    let mut out = Vec::new();
    while let Some(row) = rows.next()? {
        out.push(crate::knowledge::KnowledgePageChangeRecord {
            change_id: row.get(0)?,
            page_id: row.get(1)?,
            change_type: decode_history_change_type(row.get(2)?)?,
            actor: row.get(3)?,
            reason: normalize_optional_trimmed(row.get(4)?),
            answer_impacted: row.get::<_, i64>(5)? != 0,
            created_at_ms: row.get(6)?,
        });
    }
    Ok(out)
}

fn list_knowledge_page_lints_internal(
    conn: &Connection,
    page_id: &str,
) -> Result<Vec<crate::knowledge::KnowledgeLintRecord>> {
    let mut stmt = conn.prepare(
        r#"SELECT lint_id, page_id, kind, summary, created_at_ms
           FROM knowledge_page_lints
           WHERE page_id = ?1
           ORDER BY created_at_ms DESC, lint_id DESC"#,
    )?;
    let mut rows = stmt.query(params![page_id])?;
    let mut out = Vec::new();
    while let Some(row) = rows.next()? {
        out.push(crate::knowledge::KnowledgeLintRecord {
            lint_id: row.get(0)?,
            page_id: row.get(1)?,
            kind: decode_lint_kind(row.get(2)?)?,
            summary: row.get(3)?,
            created_at_ms: row.get(4)?,
        });
    }
    Ok(out)
}

fn append_knowledge_page_history(
    conn: &Connection,
    page_id: &str,
    change_type: crate::knowledge::KnowledgePageChangeType,
    actor: &str,
    reason: Option<&str>,
    answer_impacted: bool,
    created_at_ms: i64,
) -> Result<()> {
    conn.execute(
        r#"INSERT INTO knowledge_page_history(
               change_id,
               page_id,
               change_type,
               actor,
               reason,
               answer_impacted,
               created_at_ms
           ) VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7)"#,
        params![
            uuid::Uuid::new_v4().to_string(),
            page_id,
            encode_history_change_type(change_type)?,
            actor,
            normalize_optional_trimmed(reason.map(ToString::to_string)),
            if answer_impacted { 1 } else { 0 },
            created_at_ms,
        ],
    )?;
    Ok(())
}

fn append_knowledge_page_version_snapshot(
    conn: &Connection,
    key: &[u8; 32],
    page: &crate::knowledge::KnowledgePage,
    change_type: crate::knowledge::KnowledgePageChangeType,
    actor: &str,
    reason: Option<&str>,
    created_at_ms: i64,
) -> Result<()> {
    let version_id = uuid::Uuid::new_v4().to_string();
    conn.execute(
        r#"INSERT INTO knowledge_page_versions(
               version_id,
               page_id,
               change_type,
               actor,
               reason,
               state,
               answer_default_allowed,
               answer_requires_temporal_framing,
               confidence_level,
               source_count,
               conflict_count,
               human_corrected,
               title,
               summary,
               body,
               created_at_ms
           ) VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?11, ?12, ?13, ?14, ?15, ?16)"#,
        params![
            version_id.clone(),
            &page.page_id,
            encode_history_change_type(change_type)?,
            actor,
            normalize_optional_trimmed(reason.map(ToString::to_string)),
            encode_page_state(page.state)?,
            if page.answer_policy.default_allowed { 1 } else { 0 },
            if page.answer_policy.requires_temporal_framing {
                1
            } else {
                0
            },
            page.confidence_level,
            page.source_count,
            page.conflict_count,
            if page.human_corrected { 1 } else { 0 },
            encode_knowledge_page_version_text(key, &version_id, "title", &page.title)?,
            encode_knowledge_page_version_text(
                key,
                &version_id,
                "summary",
                &page.current_summary,
            )?,
            encode_knowledge_page_version_text(key, &version_id, "body", &page.current_body)?,
            created_at_ms,
        ],
    )?;
    Ok(())
}

fn record_knowledge_page_change(
    conn: &Connection,
    key: &[u8; 32],
    page_id: &str,
    change_type: crate::knowledge::KnowledgePageChangeType,
    actor: &str,
    reason: Option<&str>,
    answer_impacted: bool,
    created_at_ms: i64,
) -> Result<()> {
    append_knowledge_page_history(
        conn,
        page_id,
        change_type,
        actor,
        reason,
        answer_impacted,
        created_at_ms,
    )?;
    let page = load_current_knowledge_page(conn, key, page_id)?
        .ok_or_else(|| anyhow!("knowledge page not found while recording version: {page_id}"))?;
    append_knowledge_page_version_snapshot(
        conn,
        key,
        &page,
        change_type,
        actor,
        reason,
        created_at_ms,
    )?;
    Ok(())
}

fn replace_knowledge_page_lints(
    conn: &Connection,
    page_id: &str,
    lints: &[crate::knowledge::KnowledgeLintRecord],
) -> Result<()> {
    conn.execute(
        "DELETE FROM knowledge_page_lints WHERE page_id = ?1",
        params![page_id],
    )?;
    for lint in lints {
        conn.execute(
            r#"INSERT INTO knowledge_page_lints(lint_id, page_id, kind, summary, created_at_ms)
               VALUES (?1, ?2, ?3, ?4, ?5)"#,
            params![
                lint.lint_id,
                lint.page_id,
                encode_lint_kind(lint.kind)?,
                lint.summary,
                lint.created_at_ms,
            ],
        )?;
    }
    Ok(())
}

fn build_knowledge_page_lints(
    page: &crate::knowledge::KnowledgePage,
    source_document_ids: &[String],
) -> Vec<crate::knowledge::KnowledgeLintRecord> {
    let now = now_ms();
    let mut out = Vec::new();
    if page.conflict_count > 0 {
        out.push(crate::knowledge::KnowledgeLintRecord {
            lint_id: format!("lint:{}:conflict", page.page_id),
            page_id: page.page_id.clone(),
            kind: crate::knowledge::KnowledgeLintKind::Conflict,
            summary: "Conflicting claims exist on this page.".to_string(),
            created_at_ms: now,
        });
    }
    if source_document_ids.len() <= 1 {
        out.push(crate::knowledge::KnowledgeLintRecord {
            lint_id: format!("lint:{}:evidence", page.page_id),
            page_id: page.page_id.clone(),
            kind: crate::knowledge::KnowledgeLintKind::EvidenceWeakness,
            summary: "This page is supported by very little evidence.".to_string(),
            created_at_ms: now,
        });
    }
    if page.human_corrected {
        out.push(crate::knowledge::KnowledgeLintRecord {
            lint_id: format!("lint:{}:manual", page.page_id),
            page_id: page.page_id.clone(),
            kind: crate::knowledge::KnowledgeLintKind::RegenerationRisk,
            summary: "This page has manual corrections and should not be silently overwritten."
                .to_string(),
            created_at_ms: now,
        });
    }
    if matches!(
        page.state,
        crate::knowledge::KnowledgePageState::Outdated
            | crate::knowledge::KnowledgePageState::NeedsReview
    ) {
        out.push(crate::knowledge::KnowledgeLintRecord {
            lint_id: format!("lint:{}:state", page.page_id),
            page_id: page.page_id.clone(),
            kind: crate::knowledge::KnowledgeLintKind::Staleness,
            summary: "This page needs a review before it can be fully trusted.".to_string(),
            created_at_ms: now,
        });
    }
    if !page.answer_policy.default_allowed {
        out.push(crate::knowledge::KnowledgeLintRecord {
            lint_id: format!("lint:{}:muted", page.page_id),
            page_id: page.page_id.clone(),
            kind: crate::knowledge::KnowledgeLintKind::UnusedKnowledge,
            summary: "This page is excluded from answer generation.".to_string(),
            created_at_ms: now,
        });
    }
    out
}

fn answer_policy_for_state_with_override(
    state: crate::knowledge::KnowledgePageState,
    allowed: bool,
) -> crate::knowledge::KnowledgeAnswerPolicy {
    let mut policy = crate::knowledge::state_default_answer_policy(state);
    policy.default_allowed = allowed;
    policy.requires_temporal_framing =
        allowed && state == crate::knowledge::KnowledgePageState::Outdated;
    policy
}

pub fn replace_knowledge_claims(
    conn: &Connection,
    key: &[u8; 32],
    claims: &[crate::knowledge::KnowledgeClaim],
) -> Result<()> {
    conn.execute_batch("BEGIN IMMEDIATE;")?;
    let result = (|| -> Result<()> {
        conn.execute("DELETE FROM knowledge_claims", [])?;
        for claim in claims {
            conn.execute(
                r#"INSERT INTO knowledge_claims(
                       claim_id,
                       subject_id,
                       claim_type,
                       facet_key,
                       statement,
                       normalized_value,
                       time_scope,
                       valid_from_ms,
                       valid_until_ms,
                       confidence,
                       source_ref_ids_json,
                       source_count,
                       conflict_with_claim_ids_json,
                       status,
                       human_confirmed,
                       human_corrected,
                       answer_allowed,
                       created_at_ms,
                       updated_at_ms
                   ) VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?11, ?12, ?13, ?14, ?15, ?16, ?17, ?18, ?19)"#,
                params![
                    claim.claim_id,
                    claim.subject_id,
                    encode_claim_type(claim.claim_type)?,
                    claim.facet_key,
                    encode_knowledge_claim_text(key, &claim.claim_id, "statement", &claim.statement)?,
                    claim.normalized_value
                        .as_ref()
                        .map(|value| {
                            encode_knowledge_claim_text(
                                key,
                                &claim.claim_id,
                                "normalized_value",
                                value,
                            )
                        })
                        .transpose()?,
                    encode_claim_time_scope(claim.time_scope)?,
                    claim.valid_from_ms,
                    claim.valid_until_ms,
                    claim.confidence,
                    encode_string_list(&claim.source_ref_ids)?,
                    claim.source_count,
                    encode_string_list(&claim.conflict_with_claim_ids)?,
                    encode_claim_status(claim.status)?,
                    if claim.human_confirmed { 1 } else { 0 },
                    if claim.human_corrected { 1 } else { 0 },
                    if claim.answer_allowed { 1 } else { 0 },
                    claim.created_at_ms,
                    claim.updated_at_ms,
                ],
            )?;
        }
        Ok(())
    })();

    match result {
        Ok(()) => {
            conn.execute_batch("COMMIT;")?;
            Ok(())
        }
        Err(error) => {
            let _ = conn.execute_batch("ROLLBACK;");
            Err(error)
        }
    }
}

pub(crate) fn upsert_compiled_knowledge_pages(
    conn: &Connection,
    key: &[u8; 32],
    pages: &[crate::knowledge::compiler::CompiledKnowledgePageRecord],
) -> Result<()> {
    conn.execute_batch("BEGIN IMMEDIATE;")?;
    let result = (|| -> Result<()> {
        for item in pages {
            let existing = load_stored_knowledge_page_row(conn, &item.page.page_id)?;
            let existing_page = existing
                .as_ref()
                .map(|row| stored_row_to_page(key, row))
                .transpose()?;
            let preserved_state = match existing.as_ref().map(|row| row.state) {
                Some(crate::knowledge::KnowledgePageState::Removed) | None => item.page.state,
                Some(state) => state,
            };
            let existing_allowed = existing
                .as_ref()
                .map(|row| row.default_allowed)
                .unwrap_or(item.page.answer_policy.default_allowed);
            let allowed = match preserved_state {
                crate::knowledge::KnowledgePageState::Archived
                | crate::knowledge::KnowledgePageState::Removed => false,
                _ => existing_allowed,
            };
            let answer_policy = answer_policy_for_state_with_override(preserved_state, allowed);
            let created_at_ms = existing
                .as_ref()
                .map(|row| row.created_at_ms)
                .unwrap_or(item.page.created_at_ms);
            let updated_at_ms = item
                .page
                .updated_at_ms
                .max(existing.as_ref().map(|row| row.updated_at_ms).unwrap_or(0));
            let last_used_at_ms = existing.as_ref().and_then(|row| row.last_used_at_ms);
            let human_corrected = existing.as_ref().is_some_and(|row| {
                row.manual_title_blob.is_some()
                    || row.manual_summary_blob.is_some()
                    || row.manual_body_blob.is_some()
                    || row.human_corrected
            });
            let page_id = item.page.page_id.clone();
            let effective_page = crate::knowledge::KnowledgePage {
                page_id: item.page.page_id.clone(),
                page_type: item.page.page_type,
                title: item.page.title.clone(),
                current_summary: item.page.current_summary.clone(),
                current_body: item.page.current_body.clone(),
                state: preserved_state,
                answer_policy: answer_policy.clone(),
                confidence_level: item.page.confidence_level,
                created_at_ms,
                updated_at_ms,
                last_used_at_ms,
                source_count: item.page.source_count,
                conflict_count: item.page.conflict_count,
                human_corrected,
                tags: item.page.tags.clone(),
                primary_evidence_ids: item.page.primary_evidence_ids.clone(),
                related_page_ids: item.page.related_page_ids.clone(),
            };

            conn.execute(
                r#"INSERT INTO knowledge_pages(
                       page_id,
                       page_type,
                       state,
                       answer_default_allowed,
                       answer_requires_temporal_framing,
                       confidence_level,
                       source_count,
                       conflict_count,
                       created_at_ms,
                       updated_at_ms,
                       last_used_at_ms,
                       human_corrected,
                       tags_json,
                       primary_evidence_json,
                       related_page_ids_json,
                       source_document_ids_json,
                       claim_ids_json,
                       compiled_title,
                       compiled_summary,
                       compiled_body,
                       manual_title,
                       manual_summary,
                       manual_body
                   ) VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?11, ?12, ?13, ?14, ?15, ?16, ?17, ?18, ?19, ?20, ?21, ?22, ?23)
                   ON CONFLICT(page_id) DO UPDATE SET
                     page_type = excluded.page_type,
                     state = excluded.state,
                     answer_default_allowed = excluded.answer_default_allowed,
                     answer_requires_temporal_framing = excluded.answer_requires_temporal_framing,
                     confidence_level = excluded.confidence_level,
                     source_count = excluded.source_count,
                     conflict_count = excluded.conflict_count,
                     updated_at_ms = excluded.updated_at_ms,
                     last_used_at_ms = COALESCE(knowledge_pages.last_used_at_ms, excluded.last_used_at_ms),
                     human_corrected = excluded.human_corrected,
                     tags_json = excluded.tags_json,
                     primary_evidence_json = excluded.primary_evidence_json,
                     related_page_ids_json = excluded.related_page_ids_json,
                     source_document_ids_json = excluded.source_document_ids_json,
                     claim_ids_json = excluded.claim_ids_json,
                     compiled_title = excluded.compiled_title,
                     compiled_summary = excluded.compiled_summary,
                     compiled_body = excluded.compiled_body,
                     manual_title = COALESCE(knowledge_pages.manual_title, excluded.manual_title),
                     manual_summary = COALESCE(knowledge_pages.manual_summary, excluded.manual_summary),
                     manual_body = COALESCE(knowledge_pages.manual_body, excluded.manual_body)"#,
                params![
                    item.page.page_id,
                    encode_page_type(item.page.page_type)?,
                    encode_page_state(preserved_state)?,
                    if answer_policy.default_allowed { 1 } else { 0 },
                    if answer_policy.requires_temporal_framing { 1 } else { 0 },
                    item.page.confidence_level,
                    item.page.source_count,
                    item.page.conflict_count,
                    created_at_ms,
                    updated_at_ms,
                    last_used_at_ms,
                    if human_corrected { 1 } else { 0 },
                    encode_string_list(&item.page.tags)?,
                    encode_string_list(&item.page.primary_evidence_ids)?,
                    encode_string_list(&item.page.related_page_ids)?,
                    encode_string_list(&item.source_document_ids)?,
                    encode_string_list(&item.claim_ids)?,
                    encode_knowledge_page_text(key, &page_id, "compiled_title", &item.page.title)?,
                    encode_knowledge_page_text(
                        key,
                        &page_id,
                        "compiled_summary",
                        &item.page.current_summary,
                    )?,
                    encode_knowledge_page_text(key, &page_id, "compiled_body", &item.page.current_body)?,
                    existing.as_ref().and_then(|row| row.manual_title_blob.clone()),
                    existing.as_ref().and_then(|row| row.manual_summary_blob.clone()),
                    existing.as_ref().and_then(|row| row.manual_body_blob.clone()),
                ],
            )?;

            replace_knowledge_page_lints(
                conn,
                &page_id,
                &build_knowledge_page_lints(&effective_page, &item.source_document_ids),
            )?;

            match existing_page {
                None => record_knowledge_page_change(
                    conn,
                    key,
                    &page_id,
                    crate::knowledge::KnowledgePageChangeType::Created,
                    "system",
                    Some("Compiled from current claims."),
                    answer_policy.default_allowed,
                    updated_at_ms,
                )?,
                Some(previous) if previous != effective_page => record_knowledge_page_change(
                    conn,
                    key,
                    &page_id,
                    crate::knowledge::KnowledgePageChangeType::Updated,
                    "system",
                    Some("Recompiled from source claims."),
                    previous.current_body != effective_page.current_body,
                    updated_at_ms,
                )?,
                Some(_) => {}
            }
        }
        Ok(())
    })();

    match result {
        Ok(()) => {
            conn.execute_batch("COMMIT;")?;
            Ok(())
        }
        Err(error) => {
            let _ = conn.execute_batch("ROLLBACK;");
            Err(error)
        }
    }
}

pub fn mark_missing_knowledge_pages_removed(
    conn: &Connection,
    key: &[u8; 32],
    active_page_ids: &[String],
) -> Result<()> {
    let placeholders = if active_page_ids.is_empty() {
        String::new()
    } else {
        active_page_ids
            .iter()
            .enumerate()
            .map(|(index, _)| format!("?{}", index + 1))
            .collect::<Vec<_>>()
            .join(", ")
    };
    let sql = if active_page_ids.is_empty() {
        "SELECT page_id, state FROM knowledge_pages".to_string()
    } else {
        format!(
            "SELECT page_id, state FROM knowledge_pages WHERE page_id NOT IN ({placeholders})"
        )
    };
    let mut stmt = conn.prepare(&sql)?;
    let values = active_page_ids.iter().map(String::as_str).collect::<Vec<_>>();
    let mut rows = stmt.query(rusqlite::params_from_iter(values.iter().copied()))?;
    let now = now_ms();
    while let Some(row) = rows.next()? {
        let page_id: String = row.get(0)?;
        let state = decode_page_state(row.get(1)?)?;
        if state == crate::knowledge::KnowledgePageState::Removed {
            continue;
        }
        conn.execute(
            r#"UPDATE knowledge_pages
               SET state = ?2,
                   answer_default_allowed = 0,
                   answer_requires_temporal_framing = 0,
                   updated_at_ms = ?3
               WHERE page_id = ?1"#,
            params![
                page_id,
                encode_page_state(crate::knowledge::KnowledgePageState::Removed)?,
                now,
            ],
        )?;
        replace_knowledge_page_lints(
            conn,
            &page_id,
            &[crate::knowledge::KnowledgeLintRecord {
                lint_id: format!("lint:{page_id}:removed"),
                page_id: page_id.clone(),
                kind: crate::knowledge::KnowledgeLintKind::UnusedKnowledge,
                summary: "This page no longer has supporting claims.".to_string(),
                created_at_ms: now,
            }],
        )?;
        record_knowledge_page_change(
            conn,
            key,
            &page_id,
            crate::knowledge::KnowledgePageChangeType::Removed,
            "system",
            Some("Removed because no source claims remain."),
            true,
            now,
        )?;
    }
    Ok(())
}

pub fn list_knowledge_page_summaries(
    conn: &Connection,
    key: &[u8; 32],
) -> Result<Vec<crate::knowledge::KnowledgePageSummary>> {
    let mut stmt = conn.prepare(
        r#"SELECT page_id
           FROM knowledge_pages
           WHERE state != 'removed'
           ORDER BY COALESCE(last_used_at_ms, 0) DESC, updated_at_ms DESC, page_id ASC"#,
    )?;
    let page_ids = stmt
        .query_map([], |row| row.get::<_, String>(0))?
        .collect::<std::result::Result<Vec<_>, _>>()?;
    let mut out = Vec::new();
    for page_id in page_ids {
        if let Some(detail) = get_knowledge_page_detail(conn, key, &page_id)? {
            out.push(crate::knowledge::KnowledgePageSummary::from(&detail.page));
        }
    }
    Ok(out)
}

pub fn get_knowledge_page_detail(
    conn: &Connection,
    key: &[u8; 32],
    page_id: &str,
) -> Result<Option<crate::knowledge::KnowledgePageDetail>> {
    let Some(row) = load_stored_knowledge_page_row(conn, page_id)? else {
        return Ok(None);
    };
    let page = stored_row_to_page(key, &row)?;
    let history = list_knowledge_page_history_internal(conn, page_id, 32)?;
    let version_snapshots = list_knowledge_page_version_snapshots_internal(conn, key, page_id, 32)?;
    let evidence_entries =
        list_knowledge_page_evidence_entries_internal(conn, key, &row.claim_ids)?;
    let lint_records = list_knowledge_page_lints_internal(conn, page_id)?;
    Ok(Some(crate::knowledge::KnowledgePageDetail {
        page,
        source_document_ids: row.source_document_ids,
        claim_ids: row.claim_ids,
        history,
        version_snapshots,
        evidence_entries,
        lint_records,
    }))
}

pub fn apply_knowledge_page_correction(
    conn: &Connection,
    key: &[u8; 32],
    page_id: &str,
    title: Option<String>,
    summary: Option<String>,
    body: Option<String>,
) -> Result<crate::knowledge::KnowledgePageDetail> {
    let now = now_ms();
    let Some(existing) = load_stored_knowledge_page_row(conn, page_id)? else {
        return Err(anyhow!("knowledge page not found: {page_id}"));
    };
    conn.execute(
        r#"UPDATE knowledge_pages
           SET state = ?2,
               answer_default_allowed = 1,
               answer_requires_temporal_framing = 0,
               updated_at_ms = ?3,
               human_corrected = 1,
               manual_title = COALESCE(?4, manual_title),
               manual_summary = COALESCE(?5, manual_summary),
               manual_body = COALESCE(?6, manual_body)
           WHERE page_id = ?1"#,
        params![
            page_id,
            encode_page_state(crate::knowledge::KnowledgePageState::Active)?,
            now,
            normalize_optional_trimmed(title)
                .as_deref()
                .map(|value| encode_knowledge_page_text(key, page_id, "manual_title", value))
                .transpose()?,
            normalize_optional_trimmed(summary)
                .as_deref()
                .map(|value| encode_knowledge_page_text(key, page_id, "manual_summary", value))
                .transpose()?,
            normalize_optional_trimmed(body)
                .as_deref()
                .map(|value| encode_knowledge_page_text(key, page_id, "manual_body", value))
                .transpose()?,
        ],
    )?;
    let page = stored_row_to_page(
        key,
        &StoredKnowledgePageRow {
            state: crate::knowledge::KnowledgePageState::Active,
            default_allowed: true,
            requires_temporal_framing: false,
            updated_at_ms: now,
            human_corrected: true,
            ..existing
        },
    )?;
    replace_knowledge_page_lints(
        conn,
        page_id,
        &build_knowledge_page_lints(&page, &page.primary_evidence_ids),
    )?;
    record_knowledge_page_change(
        conn,
        key,
        page_id,
        crate::knowledge::KnowledgePageChangeType::Corrected,
        "user",
        Some("Manual correction applied."),
        true,
        now,
    )?;
    get_knowledge_page_detail(conn, key, page_id)?
        .ok_or_else(|| anyhow!("knowledge page disappeared after correction"))
}

pub fn mark_knowledge_page_wrong(
    conn: &Connection,
    key: &[u8; 32],
    page_id: &str,
    reason: crate::knowledge::KnowledgeWrongReason,
    note: Option<String>,
) -> Result<crate::knowledge::KnowledgePageDetail> {
    let now = now_ms();
    let Some(detail) = get_knowledge_page_detail(conn, key, page_id)? else {
        return Err(anyhow!("knowledge page not found: {page_id}"));
    };
    let next_state = crate::knowledge::apply_wrong_reason(detail.page.state, reason);
    let next_policy = crate::knowledge::state_default_answer_policy(next_state);
    conn.execute(
        r#"UPDATE knowledge_pages
           SET state = ?2,
               answer_default_allowed = ?3,
               answer_requires_temporal_framing = ?4,
               updated_at_ms = ?5
           WHERE page_id = ?1"#,
        params![
            page_id,
            encode_page_state(next_state)?,
            if next_policy.default_allowed { 1 } else { 0 },
            if next_policy.requires_temporal_framing { 1 } else { 0 },
            now,
        ],
    )?;
    record_knowledge_page_change(
        conn,
        key,
        page_id,
        match next_state {
            crate::knowledge::KnowledgePageState::Archived => {
                crate::knowledge::KnowledgePageChangeType::Archived
            }
            _ => crate::knowledge::KnowledgePageChangeType::Downgraded,
        },
        "user",
        note.as_deref(),
        true,
        now,
    )?;
    let updated = get_knowledge_page_detail(conn, key, page_id)?
        .ok_or_else(|| anyhow!("knowledge page missing after wrong flow"))?;
    replace_knowledge_page_lints(
        conn,
        page_id,
        &build_knowledge_page_lints(&updated.page, &updated.source_document_ids),
    )?;
    get_knowledge_page_detail(conn, key, page_id)?
        .ok_or_else(|| anyhow!("knowledge page missing after lint refresh"))
}

pub fn set_knowledge_page_answer_allowed(
    conn: &Connection,
    key: &[u8; 32],
    page_id: &str,
    allowed: bool,
    note: Option<String>,
) -> Result<crate::knowledge::KnowledgePageDetail> {
    let now = now_ms();
    let Some(detail) = get_knowledge_page_detail(conn, key, page_id)? else {
        return Err(anyhow!("knowledge page not found: {page_id}"));
    };
    let next_state = if allowed
        && detail.page.state == crate::knowledge::KnowledgePageState::AnswerMuted
    {
        crate::knowledge::KnowledgePageState::Active
    } else {
        detail.page.state
    };
    if allowed
        && matches!(
            next_state,
            crate::knowledge::KnowledgePageState::Archived
                | crate::knowledge::KnowledgePageState::Removed
        )
    {
        return Err(anyhow!(
            "knowledge page cannot be re-enabled for answers in state: {next_state:?}"
        ));
    }
    let next_policy = answer_policy_for_state_with_override(next_state, allowed);
    conn.execute(
        r#"UPDATE knowledge_pages
           SET state = ?2,
               answer_default_allowed = ?3,
               answer_requires_temporal_framing = ?4,
               updated_at_ms = ?5
           WHERE page_id = ?1"#,
        params![
            page_id,
            encode_page_state(next_state)?,
            if next_policy.default_allowed { 1 } else { 0 },
            if next_policy.requires_temporal_framing { 1 } else { 0 },
            now,
        ],
    )?;
    record_knowledge_page_change(
        conn,
        key,
        page_id,
        if allowed {
            crate::knowledge::KnowledgePageChangeType::Updated
        } else {
            crate::knowledge::KnowledgePageChangeType::Muted
        },
        "user",
        note.as_deref(),
        true,
        now,
    )?;
    let updated = get_knowledge_page_detail(conn, key, page_id)?
        .ok_or_else(|| anyhow!("knowledge page missing after answer policy update"))?;
    replace_knowledge_page_lints(
        conn,
        page_id,
        &build_knowledge_page_lints(&updated.page, &updated.source_document_ids),
    )?;
    get_knowledge_page_detail(conn, key, page_id)?
        .ok_or_else(|| anyhow!("knowledge page missing after lint refresh"))
}

pub fn archive_knowledge_page(
    conn: &Connection,
    key: &[u8; 32],
    page_id: &str,
    note: Option<String>,
) -> Result<crate::knowledge::KnowledgePageDetail> {
    set_knowledge_page_state(
        conn,
        key,
        page_id,
        crate::knowledge::KnowledgePageState::Archived,
        crate::knowledge::KnowledgePageChangeType::Archived,
        note,
    )
}

pub fn remove_knowledge_page(
    conn: &Connection,
    key: &[u8; 32],
    page_id: &str,
    note: Option<String>,
) -> Result<crate::knowledge::KnowledgePageDetail> {
    set_knowledge_page_state(
        conn,
        key,
        page_id,
        crate::knowledge::KnowledgePageState::Removed,
        crate::knowledge::KnowledgePageChangeType::Removed,
        note,
    )
}

pub fn merge_knowledge_page_into(
    conn: &Connection,
    key: &[u8; 32],
    page_id: &str,
    target_page_id: &str,
    note: Option<String>,
) -> Result<crate::knowledge::KnowledgePageDetail> {
    if page_id == target_page_id {
        return Err(anyhow!("cannot merge a page into itself"));
    }
    let source_row = load_stored_knowledge_page_row(conn, page_id)?
        .ok_or_else(|| anyhow!("knowledge page not found: {page_id}"))?;
    let target_row = load_stored_knowledge_page_row(conn, target_page_id)?
        .ok_or_else(|| anyhow!("knowledge page not found: {target_page_id}"))?;
    let source = stored_row_to_page(key, &source_row)?;
    let target = stored_row_to_page(key, &target_row)?;
    let now = now_ms();
    let merged_reason = note.unwrap_or_else(|| format!("Merged into {target_page_id}."));
    let merged_tags = normalize_knowledge_string_set(
        &target
            .tags
            .iter()
            .chain(source.tags.iter())
            .cloned()
            .collect::<Vec<_>>(),
        32,
    );
    let merged_primary_evidence_ids = normalize_knowledge_string_set(
        &target
            .primary_evidence_ids
            .iter()
            .chain(source.primary_evidence_ids.iter())
            .cloned()
            .collect::<Vec<_>>(),
        32,
    );
    let merged_related_page_ids = normalize_knowledge_string_set(
        &target
            .related_page_ids
            .iter()
            .chain(source.related_page_ids.iter())
            .filter(|value| value.as_str() != page_id && value.as_str() != target_page_id)
            .cloned()
            .collect::<Vec<_>>(),
        32,
    );
    let merged_source_document_ids = normalize_knowledge_string_set(
        &target_row
            .source_document_ids
            .iter()
            .chain(source_row.source_document_ids.iter())
            .cloned()
            .collect::<Vec<_>>(),
        128,
    );
    let merged_claim_ids = normalize_knowledge_string_set(
        &target_row
            .claim_ids
            .iter()
            .chain(source_row.claim_ids.iter())
            .cloned()
            .collect::<Vec<_>>(),
        256,
    );
    let merged_summary = merge_page_text(&target.current_summary, &source.current_summary);
    let merged_body = merge_page_text(&target.current_body, &source.current_body);
    let merged_confidence = target.confidence_level.max(source.confidence_level);
    let merged_source_count = target.source_count.saturating_add(source.source_count);
    let merged_conflict_count = target.conflict_count.max(source.conflict_count);
    let merged_human_corrected = target.human_corrected || source.human_corrected;
    let merged_target_state = match target.state {
        crate::knowledge::KnowledgePageState::Archived
        | crate::knowledge::KnowledgePageState::Removed => crate::knowledge::KnowledgePageState::Active,
        state => state,
    };
    let merged_target_allowed = match merged_target_state {
        crate::knowledge::KnowledgePageState::Archived
        | crate::knowledge::KnowledgePageState::Removed => false,
        _ => target.answer_policy.default_allowed,
    };
    let merged_target_policy =
        answer_policy_for_state_with_override(merged_target_state, merged_target_allowed);

    conn.execute(
        r#"UPDATE knowledge_pages
           SET state = ?2,
               answer_default_allowed = ?3,
               answer_requires_temporal_framing = ?4,
               confidence_level = ?5,
               source_count = ?6,
               conflict_count = ?7,
               updated_at_ms = ?8,
               human_corrected = ?9,
               tags_json = ?10,
               primary_evidence_json = ?11,
               related_page_ids_json = ?12,
               source_document_ids_json = ?13,
               claim_ids_json = ?14,
               compiled_summary = ?15,
               compiled_body = ?16
           WHERE page_id = ?1"#,
        params![
            target_page_id,
            encode_page_state(merged_target_state)?,
            if merged_target_policy.default_allowed { 1 } else { 0 },
            if merged_target_policy.requires_temporal_framing { 1 } else { 0 },
            merged_confidence,
            merged_source_count,
            merged_conflict_count,
            now,
            if merged_human_corrected { 1 } else { 0 },
            encode_string_list(&merged_tags)?,
            encode_string_list(&merged_primary_evidence_ids)?,
            encode_string_list(&merged_related_page_ids)?,
            encode_string_list(&merged_source_document_ids)?,
            encode_string_list(&merged_claim_ids)?,
            encode_knowledge_page_text(key, target_page_id, "compiled_summary", &merged_summary)?,
            encode_knowledge_page_text(key, target_page_id, "compiled_body", &merged_body)?,
        ],
    )?;
    conn.execute(
        r#"UPDATE knowledge_pages
           SET state = ?2,
               answer_default_allowed = 0,
               answer_requires_temporal_framing = 0,
               updated_at_ms = ?3
           WHERE page_id = ?1"#,
        params![
            page_id,
            encode_page_state(crate::knowledge::KnowledgePageState::Archived)?,
            now,
        ],
    )?;
    record_knowledge_page_change(
        conn,
        key,
        page_id,
        crate::knowledge::KnowledgePageChangeType::Merged,
        "user",
        Some(&merged_reason),
        true,
        now,
    )?;
    record_knowledge_page_change(
        conn,
        key,
        target_page_id,
        crate::knowledge::KnowledgePageChangeType::Updated,
        "user",
        Some(&format!("Merged content and provenance from {page_id}.")),
        false,
        now,
    )?;
    let updated_target = get_knowledge_page_detail(conn, key, target_page_id)?
        .ok_or_else(|| anyhow!("knowledge page missing after target merge"))?;
    replace_knowledge_page_lints(
        conn,
        target_page_id,
        &build_knowledge_page_lints(&updated_target.page, &updated_target.source_document_ids),
    )?;
    let updated = get_knowledge_page_detail(conn, key, page_id)?
        .ok_or_else(|| anyhow!("knowledge page missing after merge"))?;
    replace_knowledge_page_lints(
        conn,
        page_id,
        &build_knowledge_page_lints(&updated.page, &updated.source_document_ids),
    )?;
    get_knowledge_page_detail(conn, key, page_id)?
        .ok_or_else(|| anyhow!("knowledge page missing after merge lint refresh"))
}

fn set_knowledge_page_state(
    conn: &Connection,
    key: &[u8; 32],
    page_id: &str,
    next_state: crate::knowledge::KnowledgePageState,
    change_type: crate::knowledge::KnowledgePageChangeType,
    note: Option<String>,
) -> Result<crate::knowledge::KnowledgePageDetail> {
    let now = now_ms();
    let Some(_detail) = get_knowledge_page_detail(conn, key, page_id)? else {
        return Err(anyhow!("knowledge page not found: {page_id}"));
    };
    let next_policy = crate::knowledge::state_default_answer_policy(next_state);
    conn.execute(
        r#"UPDATE knowledge_pages
           SET state = ?2,
               answer_default_allowed = ?3,
               answer_requires_temporal_framing = ?4,
               updated_at_ms = ?5
           WHERE page_id = ?1"#,
        params![
            page_id,
            encode_page_state(next_state)?,
            if next_policy.default_allowed { 1 } else { 0 },
            if next_policy.requires_temporal_framing { 1 } else { 0 },
            now,
        ],
    )?;
    record_knowledge_page_change(
        conn,
        key,
        page_id,
        change_type,
        "user",
        note.as_deref(),
        true,
        now,
    )?;
    let updated = get_knowledge_page_detail(conn, key, page_id)?
        .ok_or_else(|| anyhow!("knowledge page missing after state update"))?;
    replace_knowledge_page_lints(
        conn,
        page_id,
        &build_knowledge_page_lints(&updated.page, &updated.source_document_ids),
    )?;
    get_knowledge_page_detail(conn, key, page_id)?
        .ok_or_else(|| anyhow!("knowledge page missing after lint refresh"))
}

pub fn reset_knowledge_index(conn: &Connection) -> Result<()> {
    conn.execute_batch(
        r#"
DELETE FROM knowledge_document_usage;
DELETE FROM knowledge_page_lints;
DELETE FROM knowledge_page_history;
DELETE FROM knowledge_page_versions;
DELETE FROM knowledge_pages;
DELETE FROM knowledge_claims;
DELETE FROM knowledge_embeddings;
DELETE FROM knowledge_index_jobs;
DELETE FROM knowledge_units;
DELETE FROM knowledge_documents;
UPDATE knowledge_rebuild_state
SET status = 'empty',
    rebuild_required = 0,
    stale_reason = NULL,
    last_error = NULL,
    last_rebuild_started_at_ms = NULL,
    last_rebuild_completed_at_ms = NULL,
    current_document_id = NULL,
    current_stage = NULL,
    documents_indexed = 0,
    units_indexed = 0,
    embeddings_indexed = 0,
    total_documents = 0,
    cancel_requested = 0,
    last_indexed_model_name = NULL,
    last_indexed_dim = NULL
WHERE state_key = 1;
"#,
    )?;
    ensure_knowledge_rebuild_state_defaults(conn)
}

pub fn read_knowledge_embedding_model_state(conn: &Connection) -> Result<(String, i64)> {
    let model_name = get_active_embedding_model_name(conn)?
        .unwrap_or_else(|| crate::embedding::DEFAULT_MODEL_NAME.to_string());
    let dim = current_embedding_dim(conn)? as i64;
    Ok((model_name, dim))
}
