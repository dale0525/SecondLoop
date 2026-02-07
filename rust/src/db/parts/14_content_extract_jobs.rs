const URL_MANIFEST_MIME: &str = "application/x.secondloop.url+json";
const VIDEO_MANIFEST_MIME: &str = "application/x.secondloop.video+json";
const DOCX_MIME: &str = "application/vnd.openxmlformats-officedocument.wordprocessingml.document";
const PDF_MIME: &str = "application/pdf";

const DOCUMENT_EXTRACT_MODEL_NAME: &str = "document_extract.v1";

fn retry_backoff_ms(attempts: i64) -> i64 {
    let clamped = attempts.clamp(1, 10) as u32;
    let multiplier = 1i64.checked_shl(clamped.saturating_sub(1)).unwrap_or(i64::MAX);
    5_000i64.saturating_mul(multiplier)
}

fn read_attachment_mime_type(conn: &Connection, attachment_sha256: &str) -> Result<String> {
    let mime: Option<String> = conn
        .query_row(
            r#"SELECT mime_type FROM attachments WHERE sha256 = ?1"#,
            params![attachment_sha256],
            |row| row.get(0),
        )
        .optional()?;
    mime.ok_or_else(|| anyhow!("attachment not found"))
}

fn list_due_attachment_annotations_filtered(
    conn: &Connection,
    now_ms: i64,
    limit: i64,
    mime_sql_filter: &str,
) -> Result<Vec<AttachmentAnnotationJob>> {
    let limit = limit.clamp(1, 500);
    let sql = format!(
        r#"
SELECT aa.attachment_sha256, aa.status, aa.lang, aa.model_name, aa.attempts, aa.next_retry_at, aa.last_error, aa.created_at, aa.updated_at
FROM attachment_annotations aa
JOIN attachments a ON a.sha256 = aa.attachment_sha256
WHERE aa.status != 'ok'
  AND (aa.next_retry_at IS NULL OR aa.next_retry_at <= ?1)
  AND ({mime_sql_filter})
ORDER BY aa.updated_at ASC, aa.attachment_sha256 ASC
LIMIT ?2
"#
    );

    let mut stmt = conn.prepare(&sql)?;
    let mut rows = stmt.query(params![now_ms, limit])?;

    let mut result = Vec::new();
    while let Some(row) = rows.next()? {
        result.push(AttachmentAnnotationJob {
            attachment_sha256: row.get(0)?,
            status: row.get(1)?,
            lang: row.get(2)?,
            model_name: row.get(3)?,
            attempts: row.get(4)?,
            next_retry_at_ms: row.get(5)?,
            last_error: row.get(6)?,
            created_at_ms: row.get(7)?,
            updated_at_ms: row.get(8)?,
        });
    }
    Ok(result)
}

pub fn list_due_image_attachment_annotations(
    conn: &Connection,
    now_ms: i64,
    limit: i64,
) -> Result<Vec<AttachmentAnnotationJob>> {
    list_due_attachment_annotations_filtered(conn, now_ms, limit, "a.mime_type LIKE 'image/%'")
}

pub fn list_due_url_manifest_attachment_annotations(
    conn: &Connection,
    now_ms: i64,
    limit: i64,
) -> Result<Vec<AttachmentAnnotationJob>> {
    list_due_attachment_annotations_filtered(
        conn,
        now_ms,
        limit,
        &format!("a.mime_type = '{URL_MANIFEST_MIME}'"),
    )
}

fn document_mime_sql_filter() -> String {
    format!(
        r#"
a.mime_type = '{PDF_MIME}'
OR a.mime_type = '{DOCX_MIME}'
OR a.mime_type LIKE 'text/%'
OR a.mime_type IN (
  'application/json',
  'application/xml',
  'application/xhtml+xml',
  'application/x-yaml',
  'application/yaml',
  'application/toml',
  'application/x-toml',
  'application/ini',
  'application/x-ini',
  'application/csv',
  'application/x-csv'
)
"#
    )
}

pub fn list_due_document_attachment_annotations(
    conn: &Connection,
    now_ms: i64,
    limit: i64,
) -> Result<Vec<AttachmentAnnotationJob>> {
    // Keep in sync with `crate::content_extract::extract_document` supported types.
    list_due_attachment_annotations_filtered(conn, now_ms, limit, &document_mime_sql_filter())
}

pub fn list_due_video_manifest_attachment_annotations(
    conn: &Connection,
    now_ms: i64,
    limit: i64,
) -> Result<Vec<AttachmentAnnotationJob>> {
    list_due_attachment_annotations_filtered(
        conn,
        now_ms,
        limit,
        &format!("a.mime_type = '{VIDEO_MANIFEST_MIME}'"),
    )
}

fn list_due_content_extract_attachment_annotations(
    conn: &Connection,
    now_ms: i64,
    limit: i64,
    include_documents: bool,
    include_video_manifests: bool,
) -> Result<Vec<AttachmentAnnotationJob>> {
    let mut filters = Vec::<String>::new();
    if include_documents {
        filters.push(document_mime_sql_filter());
    }
    if include_video_manifests {
        filters.push(format!("a.mime_type = '{VIDEO_MANIFEST_MIME}'"));
    }
    if filters.is_empty() {
        return Ok(Vec::new());
    }
    let filter = filters.join("\nOR\n");
    list_due_attachment_annotations_filtered(conn, now_ms, limit, &filter)
}

fn is_supported_document_mime_type(mime_type: &str) -> bool {
    let mt = mime_type.trim().to_ascii_lowercase();
    if mt == PDF_MIME || mt == DOCX_MIME {
        return true;
    }
    if mt.starts_with("text/") {
        return true;
    }
    matches!(
        mt.as_str(),
        "application/json"
            | "application/xml"
            | "application/xhtml+xml"
            | "application/x-yaml"
            | "application/yaml"
            | "application/toml"
            | "application/x-toml"
            | "application/ini"
            | "application/x-ini"
            | "application/csv"
            | "application/x-csv"
    )
}

fn is_url_manifest_mime_type(mime_type: &str) -> bool {
    mime_type.trim().eq_ignore_ascii_case(URL_MANIFEST_MIME)
}

pub fn maybe_auto_enqueue_content_enrichment_for_attachment(
    conn: &Connection,
    attachment_sha256: &str,
    mime_type: &str,
    now_ms: i64,
) -> Result<()> {
    let cfg = get_content_enrichment_config(conn)?;
    if !cfg.url_fetch_enabled && !cfg.document_extract_enabled && !cfg.audio_transcribe_enabled {
        return Ok(());
    }

    let normalized_mime = mime_type.trim().to_ascii_lowercase();

    // Avoid auto-enqueueing images (LLM captioning is user-controlled).
    if normalized_mime.starts_with("image/") {
        return Ok(());
    }

    if cfg.audio_transcribe_enabled && normalized_mime.starts_with("audio/") {
        enqueue_attachment_annotation(conn, attachment_sha256, "und", now_ms)?;
        return Ok(());
    }

    if cfg.url_fetch_enabled && is_url_manifest_mime_type(&normalized_mime) {
        // Language isn't used for local/URL extraction; keep deterministic.
        enqueue_attachment_annotation(conn, attachment_sha256, "und", now_ms)?;
        return Ok(());
    }

    if cfg.document_extract_enabled && is_supported_document_mime_type(&normalized_mime) {
        enqueue_attachment_annotation(conn, attachment_sha256, "und", now_ms)?;
        return Ok(());
    }

    Ok(())
}

pub fn process_pending_document_extractions(
    conn: &Connection,
    key: &[u8; 32],
    app_dir: &Path,
    limit: usize,
) -> Result<usize> {
    let cfg = get_content_enrichment_config(conn)?;
    let process_documents = cfg.document_extract_enabled;
    if !process_documents {
        return Ok(0);
    }

    let now = now_ms();
    let due = list_due_content_extract_attachment_annotations(
        conn,
        now,
        limit as i64,
        process_documents,
        false,
    )?;
    if due.is_empty() {
        return Ok(0);
    }

    let mut processed = 0usize;
    for job in due {
        if job.status == "ok" {
            continue;
        }

        let result: Result<()> = (|| {
            let mime_type = read_attachment_mime_type(conn, &job.attachment_sha256)?;
            let bytes = read_attachment_bytes(conn, key, app_dir, &job.attachment_sha256)?;
            let normalized_mime = mime_type.trim().to_ascii_lowercase();

            if !process_documents || !is_supported_document_mime_type(&normalized_mime) {
                return Ok(());
            }

            let extracted = crate::content_extract::extract_document(&mime_type, &bytes)?;
            let is_pdf = mime_type.trim().eq_ignore_ascii_case(PDF_MIME);

            let mut ocr_lang_hints: Option<String> = None;
            let mut ocr_page_count: Option<u32> = None;

            if is_pdf && extracted.needs_ocr {
                ocr_lang_hints = Some(cfg.ocr_language_hints.clone());
                ocr_page_count = extracted.page_count;
            }

            let payload = serde_json::json!({
                "schema": "secondloop.document_extract.v1",
                "mime_type": mime_type,
                "extracted_text_full": extracted.full_text,
                "extracted_text_excerpt": extracted.excerpt,
                "needs_ocr": extracted.needs_ocr,
                "page_count": extracted.page_count,
                "ocr_text_full": serde_json::Value::Null,
                "ocr_text_excerpt": serde_json::Value::Null,
                "ocr_engine": serde_json::Value::Null,
                "ocr_lang_hints": ocr_lang_hints,
                "ocr_is_truncated": serde_json::Value::Null,
                "ocr_page_count": ocr_page_count,
                "ocr_processed_pages": serde_json::Value::Null,
            });

            mark_attachment_annotation_ok(
                conn,
                key,
                &job.attachment_sha256,
                &job.lang,
                DOCUMENT_EXTRACT_MODEL_NAME,
                &payload,
                now,
            )?;
            Ok(())
        })();

        match result {
            Ok(()) => {
                processed += 1;
            }
            Err(e) => {
                let attempts = job.attempts.saturating_add(1);
                let next_retry_at_ms = now.saturating_add(retry_backoff_ms(attempts));
                mark_attachment_annotation_failed(
                    conn,
                    &job.attachment_sha256,
                    attempts,
                    next_retry_at_ms,
                    &e.to_string(),
                    now,
                )?;
            }
        }
    }

    Ok(processed)
}

pub fn read_attachment_annotation_payload_json(
    conn: &Connection,
    key: &[u8; 32],
    attachment_sha256: &str,
) -> Result<Option<String>> {
    let row: Option<(String, Vec<u8>)> = conn
        .query_row(
            r#"SELECT lang, payload
               FROM attachment_annotations
               WHERE attachment_sha256 = ?1
                 AND status = 'ok'
                 AND payload IS NOT NULL"#,
            params![attachment_sha256],
            |row| Ok((row.get(0)?, row.get(1)?)),
        )
        .optional()?;

    let Some((lang, payload_blob)) = row else {
        return Ok(None);
    };

    let aad = format!("attachment.annotation:{attachment_sha256}:{lang}");
    let json = match decrypt_bytes(key, &payload_blob, aad.as_bytes()) {
        Ok(v) => v,
        Err(_) => return Ok(None),
    };

    let s = match String::from_utf8(json) {
        Ok(v) => v,
        Err(_) => return Ok(None),
    };
    Ok(Some(s))
}
