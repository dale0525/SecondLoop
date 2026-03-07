const EXTERNAL_PHASE_B_STATUS_NOT_STARTED: &str = "not_started";
const EXTERNAL_PHASE_B_STATUS_IN_PROGRESS: &str = "in_progress";
const EXTERNAL_PHASE_B_STATUS_COMPLETED: &str = "completed";
const EXTERNAL_PHASE_B_STATUS_FAILED: &str = "failed";
const EXTERNAL_PHASE_B_STATUS_NO_WORK: &str = "no_work";

#[derive(Clone, Debug)]
struct ExternalPhaseBAttachment {
    batch_id: String,
    doc_id: String,
    attachment_sha256: String,
    attachment_name: String,
    mime_type: String,
    status: String,
    last_error: Option<String>,
}

fn parse_external_stats_value(stats_json: &str) -> serde_json::Value {
    match serde_json::from_str::<serde_json::Value>(stats_json) {
        Ok(serde_json::Value::Object(map)) => serde_json::Value::Object(map),
        _ => serde_json::json!({}),
    }
}

fn read_external_batch_stats_value(conn: &Connection, batch_id: &str) -> Result<serde_json::Value> {
    let stats_json: String = conn.query_row(
        r#"SELECT stats_json FROM external_import_batches WHERE batch_id = ?1"#,
        params![batch_id],
        |row| row.get(0),
    )?;
    Ok(parse_external_stats_value(&stats_json))
}

fn write_external_batch_stats_value(
    conn: &Connection,
    batch_id: &str,
    value: &serde_json::Value,
) -> Result<()> {
    let stats_json = serde_json::to_string(value)?;
    conn.execute(
        r#"UPDATE external_import_batches
           SET stats_json = ?2,
               updated_at_ms = ?3
           WHERE batch_id = ?1"#,
        params![batch_id, stats_json, now_ms()],
    )?;
    Ok(())
}

fn normalize_external_phase_b_status(status: Option<&str>, eligible_count: i64) -> String {
    let normalized = status.unwrap_or_default().trim();
    if normalized.is_empty() {
        if eligible_count <= 0 {
            return EXTERNAL_PHASE_B_STATUS_NO_WORK.to_string();
        }
        return EXTERNAL_PHASE_B_STATUS_NOT_STARTED.to_string();
    }
    normalized.to_string()
}

fn estimate_phase_b_runtime_seconds_for_mime(mime_type: &str) -> i64 {
    let normalized = mime_type.trim().to_ascii_lowercase();
    if normalized == PDF_MIME {
        return 4;
    }
    if normalized.starts_with("image/") {
        return 2;
    }
    1
}

fn is_external_phase_b_mime_eligible(mime_type: &str) -> bool {
    let normalized = mime_type.trim().to_ascii_lowercase();
    normalized.starts_with("image/") || is_supported_document_mime_type(&normalized)
}

fn list_external_phase_b_eligible_attachments(
    conn: &Connection,
    batch_id: &str,
) -> Result<Vec<ExternalPhaseBAttachment>> {
    let mut stmt = conn.prepare(
        r#"SELECT d.batch_id,
                  d.doc_id,
                  a.sha256,
                  da.attachment_name,
                  a.mime_type,
                  COALESCE(pa.status, 'pending') AS phase_b_status,
                  COALESCE(pa.generated_chunk_count, 0) AS generated_chunk_count,
                  pa.last_error
           FROM external_document_attachments da
           JOIN external_documents d ON d.doc_id = da.doc_id
           JOIN external_attachments a ON a.sha256 = da.sha256
           LEFT JOIN external_phase_b_attachments pa
             ON pa.doc_id = da.doc_id AND pa.attachment_sha256 = da.sha256
           WHERE d.batch_id = ?1
           ORDER BY d.doc_id ASC, da.ordinal ASC, da.attachment_name ASC"#,
    )?;
    let mut rows = stmt.query(params![batch_id])?;
    let mut out = Vec::<ExternalPhaseBAttachment>::new();
    while let Some(row) = rows.next()? {
        let item = ExternalPhaseBAttachment {
            batch_id: row.get(0)?,
            doc_id: row.get(1)?,
            attachment_sha256: row.get(2)?,
            attachment_name: row.get(3)?,
            mime_type: row.get(4)?,
            status: row.get(5)?,
            last_error: row.get(7)?,
        };
        if is_external_phase_b_mime_eligible(&item.mime_type) {
            out.push(item);
        }
    }
    Ok(out)
}

fn ensure_external_phase_b_attachment_rows(conn: &Connection, batch_id: &str) -> Result<()> {
    let eligible = list_external_phase_b_eligible_attachments(conn, batch_id)?;
    let now = now_ms();
    for item in eligible {
        conn.execute(
            r#"INSERT OR IGNORE INTO external_phase_b_attachments(
                 batch_id,
                 doc_id,
                 attachment_sha256,
                 attachment_name,
                 mime_type,
                 status,
                 generated_chunk_count,
                 last_error,
                 created_at_ms,
                 updated_at_ms,
                 completed_at_ms
               ) VALUES (?1, ?2, ?3, ?4, ?5, 'pending', 0, NULL, ?6, ?6, NULL)"#,
            params![
                item.batch_id,
                item.doc_id,
                item.attachment_sha256,
                item.attachment_name,
                item.mime_type,
                now,
            ],
        )?;
    }
    Ok(())
}

fn read_external_attachment_bytes(
    conn: &Connection,
    key: &[u8; 32],
    app_dir: &Path,
    attachment_sha256: &str,
) -> Result<Vec<u8>> {
    let stored_path: String = conn.query_row(
        r#"SELECT stored_path FROM external_attachments WHERE sha256 = ?1"#,
        params![attachment_sha256],
        |row| row.get(0),
    )?;
    let blob = fs::read(app_dir.join(stored_path))?;
    decrypt_bytes(key, &blob, &external_attachment_aad(attachment_sha256))
}

fn extract_external_phase_b_text(
    bytes: &[u8],
    mime_type: &str,
    config: &ContentEnrichmentConfig,
) -> Result<String> {
    let normalized = mime_type.trim().to_ascii_lowercase();
    if normalized.starts_with("image/") {
        if !config.ocr_enabled {
            return Ok(String::new());
        }
        let payload = crate::desktop_media::ocr::desktop_ocr_image(bytes, &config.ocr_language_hints)?;
        return Ok(payload.ocr_text_full.trim().to_string());
    }

    if !is_supported_document_mime_type(&normalized) {
        return Ok(String::new());
    }

    let extracted = crate::content_extract::extract_document(mime_type, bytes)?;
    let mut merged = extracted.full_text.trim().to_string();
    if normalized == PDF_MIME && extracted.needs_ocr && config.ocr_enabled {
        let max_pages = if config.ocr_pdf_max_pages > 0 {
            config.ocr_pdf_max_pages as u32
        } else {
            extracted.page_count.unwrap_or(10).max(1)
        };
        let dpi = config.ocr_pdf_dpi.clamp(72, 600) as u32;
        if let Ok(payload) = crate::desktop_media::ocr::desktop_ocr_pdf(
            bytes,
            max_pages,
            dpi,
            0,
            &config.ocr_language_hints,
        ) {
            merged = merge_attachment_excerpt(&merged, &payload.ocr_text_full);
        }
    }
    Ok(merged.trim().to_string())
}

fn next_external_phase_b_chunk_index(conn: &Connection, doc_id: &str) -> Result<i64> {
    let max_index: Option<i64> = conn
        .query_row(
            r#"SELECT MAX(chunk_index) FROM external_document_chunks WHERE doc_id = ?1"#,
            params![doc_id],
            |row| row.get(0),
        )
        .optional()?;
    Ok(max_index.unwrap_or(-1).saturating_add(1))
}

fn clear_external_phase_b_chunks_for_attachment(
    conn: &Connection,
    doc_id: &str,
    attachment_sha256: &str,
) -> Result<()> {
    let mut stmt = conn.prepare(
        r#"SELECT chunk_index
           FROM external_phase_b_chunk_refs
           WHERE doc_id = ?1 AND attachment_sha256 = ?2
           ORDER BY chunk_index ASC"#,
    )?;
    let mut rows = stmt.query(params![doc_id, attachment_sha256])?;
    let mut indices = Vec::<i64>::new();
    while let Some(row) = rows.next()? {
        indices.push(row.get(0)?);
    }

    if indices.is_empty() {
        return Ok(());
    }

    let space_ids = list_external_embedding_space_ids(conn)?;
    for chunk_index in &indices {
        conn.execute(
            r#"DELETE FROM external_document_chunks
               WHERE doc_id = ?1 AND chunk_index = ?2"#,
            params![doc_id, chunk_index],
        )?;
        for space_id in &space_ids {
            let table = external_chunk_embeddings_table(space_id)?;
            if !sqlite_table_exists(conn, &table)? {
                continue;
            }
            conn.execute(
                &format!(
                    r#"DELETE FROM \"{table}\" WHERE doc_id = ?1 AND chunk_index = ?2"#
                ),
                params![doc_id, chunk_index],
            )?;
        }
    }

    conn.execute(
        r#"DELETE FROM external_phase_b_chunk_refs
           WHERE doc_id = ?1 AND attachment_sha256 = ?2"#,
        params![doc_id, attachment_sha256],
    )?;
    Ok(())
}

fn insert_external_phase_b_chunks_for_attachment(
    conn: &Connection,
    key: &[u8; 32],
    doc_id: &str,
    attachment_sha256: &str,
    attachment_name: &str,
    text: &str,
) -> Result<i64> {
    let normalized = text.trim();
    if normalized.is_empty() {
        return Ok(0);
    }

    let payload = format!(
        "ATTACHMENT_TEXT\nname: {}\ncontent: {}",
        attachment_name.trim(),
        normalized,
    );
    let chunks = split_attachment_text_into_chunks(&payload);
    let now = now_ms();
    let mut next_index = next_external_phase_b_chunk_index(conn, doc_id)?;
    let mut inserted = 0i64;

    if chunks.is_empty() {
        let blob = encode_external_chunk_text(key, doc_id, next_index, payload.trim())?;
        conn.execute(
            r#"INSERT INTO external_document_chunks(doc_id, chunk_index, chunk_text, created_at_ms, updated_at_ms)
               VALUES (?1, ?2, ?3, ?4, ?4)"#,
            params![doc_id, next_index, blob, now],
        )?;
        conn.execute(
            r#"INSERT INTO external_phase_b_chunk_refs(doc_id, attachment_sha256, chunk_index, created_at_ms)
               VALUES (?1, ?2, ?3, ?4)"#,
            params![doc_id, attachment_sha256, next_index, now],
        )?;
        return Ok(1);
    }

    for (start_offset, end_offset) in chunks {
        if end_offset <= start_offset {
            continue;
        }
        let chunk_text = payload[start_offset..end_offset].trim();
        if chunk_text.is_empty() {
            continue;
        }
        let blob = encode_external_chunk_text(key, doc_id, next_index, chunk_text)?;
        conn.execute(
            r#"INSERT INTO external_document_chunks(doc_id, chunk_index, chunk_text, created_at_ms, updated_at_ms)
               VALUES (?1, ?2, ?3, ?4, ?4)"#,
            params![doc_id, next_index, blob, now],
        )?;
        conn.execute(
            r#"INSERT INTO external_phase_b_chunk_refs(doc_id, attachment_sha256, chunk_index, created_at_ms)
               VALUES (?1, ?2, ?3, ?4)"#,
            params![doc_id, attachment_sha256, next_index, now],
        )?;
        next_index = next_index.saturating_add(1);
        inserted = inserted.saturating_add(1);
    }

    Ok(inserted)
}

fn mark_external_phase_b_attachment_completed(
    conn: &Connection,
    doc_id: &str,
    attachment_sha256: &str,
    generated_chunk_count: i64,
) -> Result<()> {
    let now = now_ms();
    conn.execute(
        r#"UPDATE external_phase_b_attachments
           SET status = 'completed',
               generated_chunk_count = ?3,
               last_error = NULL,
               updated_at_ms = ?4,
               completed_at_ms = ?4
           WHERE doc_id = ?1 AND attachment_sha256 = ?2"#,
        params![doc_id, attachment_sha256, generated_chunk_count.max(0), now],
    )?;
    Ok(())
}

fn mark_external_phase_b_attachment_failed(
    conn: &Connection,
    doc_id: &str,
    attachment_sha256: &str,
    last_error: &str,
) -> Result<()> {
    let now = now_ms();
    conn.execute(
        r#"UPDATE external_phase_b_attachments
           SET status = 'failed',
               last_error = ?3,
               updated_at_ms = ?4,
               completed_at_ms = NULL
           WHERE doc_id = ?1 AND attachment_sha256 = ?2"#,
        params![doc_id, attachment_sha256, last_error, now],
    )?;
    Ok(())
}

fn query_external_phase_b_counts(
    conn: &Connection,
    batch_id: &str,
) -> Result<(i64, i64, i64, i64)> {
    let eligible_count: i64 = conn.query_row(
        r#"SELECT COUNT(*) FROM external_phase_b_attachments WHERE batch_id = ?1"#,
        params![batch_id],
        |row| row.get(0),
    )?;
    let processed_count: i64 = conn.query_row(
        r#"SELECT COUNT(*) FROM external_phase_b_attachments WHERE batch_id = ?1 AND status = 'completed'"#,
        params![batch_id],
        |row| row.get(0),
    )?;
    let failed_count: i64 = conn.query_row(
        r#"SELECT COUNT(*) FROM external_phase_b_attachments WHERE batch_id = ?1 AND status = 'failed'"#,
        params![batch_id],
        |row| row.get(0),
    )?;
    let enriched_chunk_count: i64 = conn.query_row(
        r#"SELECT COUNT(*)
           FROM external_phase_b_chunk_refs r
           JOIN external_documents d ON d.doc_id = r.doc_id
           WHERE d.batch_id = ?1"#,
        params![batch_id],
        |row| row.get(0),
    )?;
    Ok((eligible_count, processed_count, failed_count, enriched_chunk_count))
}

fn update_external_phase_b_batch_stats(
    conn: &Connection,
    batch_id: &str,
    phase_b_status: &str,
    last_error: Option<&str>,
) -> Result<serde_json::Value> {
    let mut stats = read_external_batch_stats_value(conn, batch_id)?;
    let (eligible_count, processed_count, failed_count, enriched_chunk_count) =
        query_external_phase_b_counts(conn, batch_id)?;
    let now = now_ms();

    if stats.get("phase_b_started_at_ms").and_then(|v| v.as_i64()).is_none()
        && phase_b_status == EXTERNAL_PHASE_B_STATUS_IN_PROGRESS
    {
        stats["phase_b_started_at_ms"] = serde_json::json!(now);
    }
    if matches!(
        phase_b_status,
        EXTERNAL_PHASE_B_STATUS_COMPLETED | EXTERNAL_PHASE_B_STATUS_FAILED | EXTERNAL_PHASE_B_STATUS_NO_WORK
    ) {
        stats["phase_b_completed_at_ms"] = serde_json::json!(now);
    }

    let started_at_ms = stats
        .get("phase_b_started_at_ms")
        .and_then(|v| v.as_i64())
        .unwrap_or(now);
    let completed_at_ms = stats
        .get("phase_b_completed_at_ms")
        .and_then(|v| v.as_i64())
        .unwrap_or(now);

    stats["phase_b_status"] = serde_json::json!(phase_b_status);
    stats["phase_b_eligible_attachment_count"] = serde_json::json!(eligible_count);
    stats["phase_b_processed_attachment_count"] = serde_json::json!(processed_count);
    stats["phase_b_remaining_attachment_count"] =
        serde_json::json!((eligible_count - processed_count).max(0));
    stats["phase_b_failed_attachment_count"] = serde_json::json!(failed_count);
    stats["phase_b_enriched_chunk_count"] = serde_json::json!(enriched_chunk_count);
    stats["phase_b_elapsed_ms"] = serde_json::json!(completed_at_ms.saturating_sub(started_at_ms));
    match last_error {
        Some(value) if !value.trim().is_empty() => {
            stats["phase_b_last_error"] = serde_json::json!(value.trim());
        }
        _ => {
            stats["phase_b_last_error"] = serde_json::Value::Null;
        }
    }
    write_external_batch_stats_value(conn, batch_id, &stats)?;
    Ok(stats)
}

fn external_import_phase_b_state_json_from_conn(
    conn: &Connection,
    batch_id: &str,
) -> Result<serde_json::Value> {
    let (batch_status, created_at_ms, updated_at_ms, completed_at_ms, stats_json, last_error): (
        String,
        i64,
        i64,
        Option<i64>,
        String,
        Option<String>,
    ) = conn.query_row(
        r#"SELECT status, created_at_ms, updated_at_ms, completed_at_ms, stats_json, last_error
           FROM external_import_batches
           WHERE batch_id = ?1"#,
        params![batch_id],
        |row| {
            Ok((
                row.get(0)?,
                row.get(1)?,
                row.get(2)?,
                row.get(3)?,
                row.get(4)?,
                row.get(5)?,
            ))
        },
    )?;
    let stats = parse_external_stats_value(&stats_json);
    let (notes_count, attachments_count, failed_count, copied_bytes) =
        parse_external_stats_json(&stats_json);
    let (eligible_count, processed_count, phase_b_failed_count, enriched_chunk_count) =
        query_external_phase_b_counts(conn, batch_id)?;
    let phase_b_status = normalize_external_phase_b_status(
        stats.get("phase_b_status").and_then(|v| v.as_str()),
        eligible_count,
    );
    let success_doc_count: i64 = conn.query_row(
        r#"SELECT COUNT(*) FROM external_documents WHERE batch_id = ?1 AND COALESCE(is_deleted, 0) = 0"#,
        params![batch_id],
        |row| row.get(0),
    )?;
    let attachment_ref_count: i64 = conn.query_row(
        r#"SELECT COUNT(*)
           FROM external_document_attachments a
           JOIN external_documents d ON d.doc_id = a.doc_id
           WHERE d.batch_id = ?1"#,
        params![batch_id],
        |row| row.get(0),
    )?;
    let import_terminal_ms = completed_at_ms.unwrap_or(updated_at_ms);
    let import_elapsed_ms = import_terminal_ms.saturating_sub(created_at_ms);
    let phase_b_started_at_ms = stats.get("phase_b_started_at_ms").and_then(|v| v.as_i64());
    let phase_b_completed_at_ms = stats.get("phase_b_completed_at_ms").and_then(|v| v.as_i64());
    let phase_b_elapsed_ms = match (phase_b_started_at_ms, phase_b_completed_at_ms) {
        (Some(started), Some(completed)) => completed.saturating_sub(started),
        (Some(started), None) if phase_b_status == EXTERNAL_PHASE_B_STATUS_IN_PROGRESS => {
            now_ms().saturating_sub(started)
        }
        _ => 0,
    };

    Ok(serde_json::json!({
        "batch_id": batch_id,
        "batch_status": batch_status,
        "phase_b_status": phase_b_status,
        "notes_count": notes_count,
        "attachments_count": attachments_count,
        "failed_count": failed_count,
        "copied_bytes": copied_bytes,
        "eligible_attachment_count": eligible_count,
        "processed_attachment_count": processed_count,
        "remaining_attachment_count": (eligible_count - processed_count).max(0),
        "failed_attachment_count": phase_b_failed_count,
        "enriched_chunk_count": enriched_chunk_count,
        "success_doc_count": success_doc_count,
        "attachment_ref_count": attachment_ref_count,
        "created_at_ms": created_at_ms,
        "updated_at_ms": updated_at_ms,
        "completed_at_ms": completed_at_ms,
        "elapsed_ms": import_elapsed_ms,
        "phase_b_started_at_ms": phase_b_started_at_ms,
        "phase_b_completed_at_ms": phase_b_completed_at_ms,
        "phase_b_elapsed_ms": phase_b_elapsed_ms,
        "last_error": last_error,
        "phase_b_last_error": stats.get("phase_b_last_error").cloned().unwrap_or(serde_json::Value::Null),
    }))
}

pub fn estimate_external_import_phase_b(app_dir: &Path, batch_id: &str) -> Result<serde_json::Value> {
    let conn = open_external_readonly_db(app_dir)?;
    ensure_external_phase_b_attachment_rows(&conn, batch_id)?;
    let eligible = list_external_phase_b_eligible_attachments(&conn, batch_id)?;
    let processed_count: i64 = conn.query_row(
        r#"SELECT COUNT(*) FROM external_phase_b_attachments WHERE batch_id = ?1 AND status = 'completed'"#,
        params![batch_id],
        |row| row.get(0),
    )?;
    let estimated_runtime_seconds = eligible
        .iter()
        .map(|item| estimate_phase_b_runtime_seconds_for_mime(&item.mime_type))
        .fold(0i64, |acc, value| acc.saturating_add(value));
    let estimated_local_bytes = eligible.iter().try_fold(0i64, |acc, item| {
        let size: i64 = conn.query_row(
            r#"SELECT size_bytes FROM external_attachments WHERE sha256 = ?1"#,
            params![item.attachment_sha256],
            |row| row.get(0),
        )?;
        Ok::<i64, anyhow::Error>(acc.saturating_add(size.max(0)))
    })?;
    let state = external_import_phase_b_state_json_from_conn(&conn, batch_id)?;
    Ok(serde_json::json!({
        "batch_id": batch_id,
        "eligible_attachment_count": i64::try_from(eligible.len()).unwrap_or(i64::MAX),
        "remaining_attachment_count": (i64::try_from(eligible.len()).unwrap_or(i64::MAX) - processed_count).max(0),
        "estimated_runtime_seconds": estimated_runtime_seconds.max(0),
        "estimated_cloud_tokens": 0,
        "estimated_local_bytes": estimated_local_bytes.max(0),
        "estimated_local_work_units": i64::try_from(eligible.len()).unwrap_or(i64::MAX),
        "phase_b_status": state["phase_b_status"].clone(),
    }))
}

pub fn read_external_import_phase_b_state(app_dir: &Path, batch_id: &str) -> Result<serde_json::Value> {
    let conn = open_external_readonly_db(app_dir)?;
    ensure_external_phase_b_attachment_rows(&conn, batch_id)?;
    external_import_phase_b_state_json_from_conn(&conn, batch_id)
}

pub fn run_external_import_phase_b_with_callbacks(
    app_dir: &Path,
    key: &[u8; 32],
    batch_id: &str,
    on_event: &mut dyn FnMut(ExternalImportProgress),
) -> Result<serde_json::Value> {
    let conn = open_external_readonly_db(app_dir)?;
    ensure_external_phase_b_attachment_rows(&conn, batch_id)?;
    let batch_status: String = conn.query_row(
        r#"SELECT status FROM external_import_batches WHERE batch_id = ?1"#,
        params![batch_id],
        |row| row.get(0),
    )?;
    if batch_status != "completed" {
        return Err(anyhow!("phase b requires a completed import batch"));
    }

    let eligible = list_external_phase_b_eligible_attachments(&conn, batch_id)?;
    let total = i64::try_from(eligible.len()).unwrap_or(i64::MAX);
    if total == 0 {
        let _ = update_external_phase_b_batch_stats(&conn, batch_id, EXTERNAL_PHASE_B_STATUS_NO_WORK, None)?;
        emit_external_import_progress(on_event, batch_id, "completed", 0, 0, 0, EXTERNAL_PHASE_B_STATUS_NO_WORK);
        return external_import_phase_b_state_json_from_conn(&conn, batch_id);
    }

    let _ = update_external_phase_b_batch_stats(&conn, batch_id, EXTERNAL_PHASE_B_STATUS_IN_PROGRESS, None)?;
    let main_conn = open(app_dir)?;
    let config = get_content_enrichment_config(&main_conn)?;

    let mut processed_done = conn.query_row(
        r#"SELECT COUNT(*) FROM external_phase_b_attachments WHERE batch_id = ?1 AND status = 'completed'"#,
        params![batch_id],
        |row| row.get::<_, i64>(0),
    )?;
    emit_external_import_progress(
        on_event,
        batch_id,
        "indexing_phase_b",
        processed_done,
        total,
        0,
        EXTERNAL_PHASE_B_STATUS_IN_PROGRESS,
    );

    for item in eligible {
        if item.status == "completed" {
            continue;
        }

        let process_result: Result<i64> = (|| {
            let bytes = read_external_attachment_bytes(&conn, key, app_dir, &item.attachment_sha256)?;
            let extracted_text = extract_external_phase_b_text(&bytes, &item.mime_type, &config)?;

            conn.execute_batch("BEGIN IMMEDIATE;")?;
            let tx_result = (|| -> Result<i64> {
                clear_external_phase_b_chunks_for_attachment(&conn, &item.doc_id, &item.attachment_sha256)?;
                let generated_chunk_count = insert_external_phase_b_chunks_for_attachment(
                    &conn,
                    key,
                    &item.doc_id,
                    &item.attachment_sha256,
                    &item.attachment_name,
                    &extracted_text,
                )?;
                mark_external_phase_b_attachment_completed(
                    &conn,
                    &item.doc_id,
                    &item.attachment_sha256,
                    generated_chunk_count,
                )?;
                Ok(generated_chunk_count)
            })();

            match tx_result {
                Ok(count) => {
                    conn.execute_batch("COMMIT;")?;
                    Ok(count)
                }
                Err(e) => {
                    let _ = conn.execute_batch("ROLLBACK;");
                    Err(e)
                }
            }
        })();

        match process_result {
            Ok(_generated_chunk_count) => {
                processed_done = processed_done.saturating_add(1);
            }
            Err(e) => {
                let _ = mark_external_phase_b_attachment_failed(
                    &conn,
                    &item.doc_id,
                    &item.attachment_sha256,
                    &e.to_string(),
                );
            }
        }

        let (eligible_count, completed_count, failed_count, _) = query_external_phase_b_counts(&conn, batch_id)?;
        let phase_status = if failed_count > 0 {
            EXTERNAL_PHASE_B_STATUS_FAILED
        } else {
            EXTERNAL_PHASE_B_STATUS_IN_PROGRESS
        };
        let _ = update_external_phase_b_batch_stats(
            &conn,
            batch_id,
            phase_status,
            item.last_error.as_deref(),
        )?;
        emit_external_import_progress(
            on_event,
            batch_id,
            "indexing_phase_b",
            completed_count,
            eligible_count,
            failed_count,
            phase_status,
        );
    }

    loop {
        let processed = process_pending_external_document_embeddings_default(app_dir, key, 256)?;
        if processed == 0 {
            break;
        }
    }

    let (_, _, failed_count, _) = query_external_phase_b_counts(&conn, batch_id)?;
    let terminal_status = if failed_count > 0 {
        EXTERNAL_PHASE_B_STATUS_FAILED
    } else {
        EXTERNAL_PHASE_B_STATUS_COMPLETED
    };
    let _ = update_external_phase_b_batch_stats(&conn, batch_id, terminal_status, None)?;
    let state = external_import_phase_b_state_json_from_conn(&conn, batch_id)?;
    emit_external_import_progress(
        on_event,
        batch_id,
        "completed",
        state["processed_attachment_count"].as_i64().unwrap_or(0),
        state["eligible_attachment_count"].as_i64().unwrap_or(0),
        state["failed_attachment_count"].as_i64().unwrap_or(0),
        terminal_status,
    );
    Ok(state)
}

#[cfg(test)]
fn seed_external_import_phase_b_attachment_progress_for_test(
    app_dir: &Path,
    conn: &Connection,
    key: &[u8; 32],
    batch_id: &str,
) -> Result<()> {
    ensure_external_phase_b_attachment_rows(conn, batch_id)?;
    let items = list_external_phase_b_eligible_attachments(conn, batch_id)?;
    let item = items
        .into_iter()
        .next()
        .ok_or_else(|| anyhow!("missing eligible phase b attachment"))?;
    let bytes = read_external_attachment_bytes(conn, key, app_dir, &item.attachment_sha256)?;
    let text = extract_external_phase_b_text(
        &bytes,
        &item.mime_type,
        &ContentEnrichmentConfig {
            url_fetch_enabled: true,
            document_extract_enabled: true,
            document_keep_original_max_bytes: 50 * 1024 * 1024,
            audio_transcribe_enabled: true,
            audio_transcribe_engine: "whisper".to_string(),
            video_extract_enabled: true,
            video_proxy_enabled: true,
            video_proxy_max_duration_ms: 3_600_000,
            video_proxy_max_bytes: 209_715_200,
            ocr_enabled: true,
            ocr_engine_mode: "platform_native".to_string(),
            ocr_language_hints: "device_plus_en".to_string(),
            ocr_pdf_dpi: 180,
            ocr_pdf_auto_max_pages: 0,
            ocr_pdf_max_pages: 0,
            mobile_background_enabled: true,
            mobile_background_requires_wifi: true,
            mobile_background_requires_charging: true,
        },
    )?;

    conn.execute_batch("BEGIN IMMEDIATE;")?;
    let tx_result = (|| -> Result<()> {
        clear_external_phase_b_chunks_for_attachment(conn, &item.doc_id, &item.attachment_sha256)?;
        let generated_chunk_count = insert_external_phase_b_chunks_for_attachment(
            conn,
            key,
            &item.doc_id,
            &item.attachment_sha256,
            &item.attachment_name,
            &text,
        )?;
        mark_external_phase_b_attachment_completed(
            conn,
            &item.doc_id,
            &item.attachment_sha256,
            generated_chunk_count,
        )?;
        Ok(())
    })();
    match tx_result {
        Ok(()) => conn.execute_batch("COMMIT;")?,
        Err(e) => {
            let _ = conn.execute_batch("ROLLBACK;");
            return Err(e);
        }
    }
    let _ = update_external_phase_b_batch_stats(conn, batch_id, EXTERNAL_PHASE_B_STATUS_IN_PROGRESS, None)?;
    Ok(())
}
