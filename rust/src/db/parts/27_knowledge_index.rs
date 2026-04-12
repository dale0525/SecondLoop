fn knowledge_document_text_aad(document_id: &str, field: &str) -> Vec<u8> {
    format!("knowledge.document.{field}:{document_id}").into_bytes()
}

fn knowledge_unit_text_aad(unit_id: &str, field: &str) -> Vec<u8> {
    format!("knowledge.unit.{field}:{unit_id}").into_bytes()
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

pub fn reset_knowledge_index(conn: &Connection) -> Result<()> {
    conn.execute_batch(
        r#"
DELETE FROM knowledge_document_usage;
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
