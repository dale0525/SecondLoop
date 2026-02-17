const URL_MANIFEST_MIME: &str = "application/x.secondloop.url+json";
const VIDEO_MANIFEST_MIME: &str = "application/x.secondloop.video+json";
const DOCX_MIME: &str = "application/vnd.openxmlformats-officedocument.wordprocessingml.document";
const PDF_MIME: &str = "application/pdf";

const DOCUMENT_EXTRACT_MODEL_NAME: &str = "document_extract.v1";
const VIDEO_EXTRACT_MODEL_NAME: &str = "video_extract.v1";
const AUDIO_TRANSCRIPT_SCHEMA: &str = "secondloop.audio_transcript.v1";
const VIDEO_MANIFEST_SCHEMA_V1: &str = "secondloop.video_manifest.v1";
const VIDEO_MANIFEST_SCHEMA_V2: &str = "secondloop.video_manifest.v2";
const VIDEO_MANIFEST_SCHEMA_V3: &str = "secondloop.video_manifest.v3";
const VIDEO_EXTRACT_EXCERPT_MAX_BYTES: usize = 8 * 1024;

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
enum ContentExtractProcessOutcome {
    Completed,
    Deferred,
}

fn retry_backoff_ms(attempts: i64) -> i64 {
    let clamped = attempts.clamp(1, 10) as u32;
    let multiplier = 1i64
        .checked_shl(clamped.saturating_sub(1))
        .unwrap_or(i64::MAX);
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

#[derive(Clone, Debug)]
struct VideoManifestSegmentRef {
    index: i64,
    sha256: String,
    mime_type: String,
}

#[derive(Clone, Debug)]
struct ParsedVideoManifestPayload {
    video_sha256: String,
    video_mime_type: String,
    audio_sha256: Option<String>,
    audio_mime_type: Option<String>,
    segments: Vec<VideoManifestSegmentRef>,
}

fn truncate_utf8_for_excerpt(text: &str, max_bytes: usize) -> String {
    if text.len() <= max_bytes {
        return text.to_string();
    }
    if max_bytes == 0 {
        return String::new();
    }

    let mut end = max_bytes;
    while end > 0 && !text.is_char_boundary(end) {
        end -= 1;
    }
    text[..end].to_string()
}

fn is_supported_video_manifest_schema(schema: &str) -> bool {
    let normalized = schema.trim();
    if normalized == VIDEO_MANIFEST_SCHEMA_V1
        || normalized == VIDEO_MANIFEST_SCHEMA_V2
        || normalized == VIDEO_MANIFEST_SCHEMA_V3
    {
        return true;
    }

    const PREFIX: &str = "secondloop.video_manifest.v";
    let Some(version) = normalized.strip_prefix(PREFIX) else {
        return false;
    };
    !version.is_empty() && version.bytes().all(|ch| ch.is_ascii_digit())
}

fn parse_video_manifest_payload(bytes: &[u8]) -> Result<ParsedVideoManifestPayload> {
    let raw = std::str::from_utf8(bytes).map_err(|_| anyhow!("video manifest is not utf-8"))?;
    let value: serde_json::Value =
        serde_json::from_str(raw).map_err(|_| anyhow!("video manifest is not valid json"))?;
    let payload = value
        .as_object()
        .ok_or_else(|| anyhow!("video manifest payload must be a json object"))?;

    let schema = payload
        .get("schema")
        .and_then(|item| item.as_str())
        .map(|item| item.trim())
        .unwrap_or("");
    if !is_supported_video_manifest_schema(schema) {
        return Err(anyhow!("unsupported video manifest schema"));
    }

    fn read_non_empty_field(
        payload: &serde_json::Map<String, serde_json::Value>,
        keys: &[&str],
        fallback_value: &str,
    ) -> String {
        for key in keys {
            let value = payload
                .get(*key)
                .and_then(|item| item.as_str())
                .map(|item| item.trim())
                .unwrap_or("");
            if !value.is_empty() {
                return value.to_string();
            }
        }

        fallback_value.trim().to_string()
    }

    let mut segments = Vec::<VideoManifestSegmentRef>::new();
    if let Some(items) = payload
        .get("video_segments")
        .or_else(|| payload.get("videoSegments"))
        .and_then(|item| item.as_array())
    {
        for (fallback_index, item) in items.iter().enumerate() {
            let Some(segment) = item.as_object() else {
                continue;
            };

            let sha256 = segment
                .get("sha256")
                .and_then(|value| value.as_str())
                .map(|value| value.trim())
                .unwrap_or("");
            let mime_type = segment
                .get("mime_type")
                .or_else(|| segment.get("mimeType"))
                .and_then(|value| value.as_str())
                .map(|value| value.trim())
                .unwrap_or("");
            if sha256.is_empty() || mime_type.is_empty() {
                continue;
            }

            let index = match segment.get("index") {
                Some(serde_json::Value::Number(value)) => {
                    value.as_i64().unwrap_or(fallback_index as i64)
                }
                Some(serde_json::Value::String(value)) => {
                    value.trim().parse::<i64>().unwrap_or(fallback_index as i64)
                }
                _ => fallback_index as i64,
            };

            segments.push(VideoManifestSegmentRef {
                index,
                sha256: sha256.to_string(),
                mime_type: mime_type.to_string(),
            });
        }
    }

    segments.sort_by(|a, b| {
        let by_index = a.index.cmp(&b.index);
        if by_index != std::cmp::Ordering::Equal {
            return by_index;
        }
        a.sha256.cmp(&b.sha256)
    });

    let first_segment_sha256 = segments
        .first()
        .map(|segment| segment.sha256.as_str())
        .unwrap_or("");
    let first_segment_mime_type = segments
        .first()
        .map(|segment| segment.mime_type.as_str())
        .unwrap_or("");

    let video_sha256 = read_non_empty_field(
        payload,
        &[
            "video_sha256",
            "videoSha256",
            "original_sha256",
            "originalSha256",
        ],
        first_segment_sha256,
    );
    let video_mime_type = read_non_empty_field(
        payload,
        &[
            "video_mime_type",
            "videoMimeType",
            "original_mime_type",
            "originalMimeType",
        ],
        first_segment_mime_type,
    );
    if video_sha256.is_empty() || video_mime_type.is_empty() {
        return Err(anyhow!("video manifest missing required video reference"));
    }

    if segments.is_empty() {
        segments.push(VideoManifestSegmentRef {
            index: 0,
            sha256: video_sha256.clone(),
            mime_type: video_mime_type.clone(),
        });
    }

    let audio_sha256 = payload
        .get("audio_sha256")
        .or_else(|| payload.get("audioSha256"))
        .and_then(|item| item.as_str())
        .map(|item| item.trim())
        .filter(|item| !item.is_empty())
        .map(|item| item.to_string());
    let audio_mime_type = payload
        .get("audio_mime_type")
        .or_else(|| payload.get("audioMimeType"))
        .and_then(|item| item.as_str())
        .map(|item| item.trim())
        .filter(|item| !item.is_empty())
        .map(|item| item.to_string());

    Ok(ParsedVideoManifestPayload {
        video_sha256,
        video_mime_type,
        audio_sha256,
        audio_mime_type,
        segments,
    })
}

fn parse_audio_transcript_payload(payload_json: &str) -> Result<(String, String)> {
    let value: serde_json::Value =
        serde_json::from_str(payload_json).map_err(|_| anyhow!("audio transcript is not json"))?;
    let payload = value
        .as_object()
        .ok_or_else(|| anyhow!("audio transcript payload must be a json object"))?;

    let schema = payload
        .get("schema")
        .and_then(|item| item.as_str())
        .map(|item| item.trim())
        .unwrap_or("");
    if !schema.is_empty() && schema != AUDIO_TRANSCRIPT_SCHEMA {
        return Err(anyhow!("unsupported audio transcript schema"));
    }

    let transcript_full = payload
        .get("transcript_full")
        .and_then(|item| item.as_str())
        .map(|item| item.trim())
        .unwrap_or("")
        .to_string();
    let transcript_excerpt = payload
        .get("transcript_excerpt")
        .and_then(|item| item.as_str())
        .map(|item| item.trim())
        .unwrap_or("")
        .to_string();

    let normalized_full = if transcript_full.is_empty() {
        transcript_excerpt.clone()
    } else {
        transcript_full
    };
    let normalized_excerpt = if transcript_excerpt.is_empty() {
        truncate_utf8_for_excerpt(&normalized_full, VIDEO_EXTRACT_EXCERPT_MAX_BYTES)
    } else {
        transcript_excerpt
    };

    Ok((normalized_full, normalized_excerpt))
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

fn is_video_manifest_mime_type(mime_type: &str) -> bool {
    mime_type.trim().eq_ignore_ascii_case(VIDEO_MANIFEST_MIME)
}

pub fn maybe_auto_enqueue_content_enrichment_for_attachment(
    conn: &Connection,
    attachment_sha256: &str,
    mime_type: &str,
    now_ms: i64,
) -> Result<()> {
    let cfg = get_content_enrichment_config(conn)?;
    if !cfg.url_fetch_enabled
        && !cfg.document_extract_enabled
        && !cfg.audio_transcribe_enabled
        && !cfg.video_extract_enabled
    {
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

    if cfg.video_extract_enabled && is_video_manifest_mime_type(&normalized_mime) {
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
    let process_video_manifests = cfg.video_extract_enabled;
    if !process_documents && !process_video_manifests {
        return Ok(0);
    }

    let now = now_ms();
    let due = list_due_content_extract_attachment_annotations(
        conn,
        now,
        limit as i64,
        process_documents,
        process_video_manifests,
    )?;
    if due.is_empty() {
        return Ok(0);
    }

    let mut processed = 0usize;
    for job in due {
        if job.status == "ok" {
            continue;
        }

        let result: Result<ContentExtractProcessOutcome> = (|| {
            let mime_type = read_attachment_mime_type(conn, &job.attachment_sha256)?;
            let bytes = read_attachment_bytes(conn, key, app_dir, &job.attachment_sha256)?;
            let normalized_mime = mime_type.trim().to_ascii_lowercase();

            if process_documents && is_supported_document_mime_type(&normalized_mime) {
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
                return Ok(ContentExtractProcessOutcome::Completed);
            }

            if process_video_manifests && is_video_manifest_mime_type(&normalized_mime) {
                let manifest = parse_video_manifest_payload(&bytes)?;

                let mut transcript_full = String::new();
                let mut transcript_excerpt = String::new();
                if let Some(audio_sha256) = manifest.audio_sha256.as_deref() {
                    let transcript_payload_json =
                        read_attachment_annotation_payload_json(conn, key, audio_sha256)?;

                    if let Some(payload_json) = transcript_payload_json {
                        let (full, excerpt) = parse_audio_transcript_payload(&payload_json)?;
                        transcript_full = full;
                        transcript_excerpt = excerpt;
                    } else if cfg.audio_transcribe_enabled {
                        enqueue_attachment_annotation(conn, audio_sha256, "und", now)?;
                        enqueue_attachment_annotation(
                            conn,
                            &job.attachment_sha256,
                            &job.lang,
                            now,
                        )?;
                        return Ok(ContentExtractProcessOutcome::Deferred);
                    }
                }

                let readable_text_full = transcript_full.trim().to_string();
                let readable_text_excerpt = if transcript_excerpt.trim().is_empty() {
                    truncate_utf8_for_excerpt(&readable_text_full, VIDEO_EXTRACT_EXCERPT_MAX_BYTES)
                } else {
                    transcript_excerpt.trim().to_string()
                };

                let segment_payloads = manifest
                    .segments
                    .iter()
                    .map(|segment| {
                        serde_json::json!({
                            "index": segment.index,
                            "sha256": segment.sha256,
                            "mime_type": segment.mime_type,
                        })
                    })
                    .collect::<Vec<_>>();

                let needs_ocr = true;
                let payload = serde_json::json!({
                    "schema": "secondloop.video_extract.v1",
                    "mime_type": VIDEO_MANIFEST_MIME,
                    "original_sha256": manifest.video_sha256,
                    "original_mime_type": manifest.video_mime_type,
                    "video_segment_count": manifest.segments.len(),
                    "video_processed_segment_count": 0,
                    "video_ocr_segment_limit": 0,
                    "video_segments": segment_payloads,
                    "audio_sha256": manifest.audio_sha256,
                    "audio_mime_type": manifest.audio_mime_type,
                    "transcript_full": if readable_text_full.is_empty() {
                        serde_json::Value::Null
                    } else {
                        serde_json::Value::String(readable_text_full.clone())
                    },
                    "transcript_excerpt": if readable_text_excerpt.is_empty() {
                        serde_json::Value::Null
                    } else {
                        serde_json::Value::String(readable_text_excerpt.clone())
                    },
                    "needs_ocr": needs_ocr,
                    "readable_text_full": readable_text_full,
                    "readable_text_excerpt": readable_text_excerpt,
                    "ocr_text_full": serde_json::Value::Null,
                    "ocr_text_excerpt": serde_json::Value::Null,
                    "ocr_engine": serde_json::Value::Null,
                    "ocr_lang_hints": serde_json::Value::Null,
                    "ocr_is_truncated": serde_json::Value::Null,
                    "ocr_page_count": serde_json::Value::Null,
                    "ocr_processed_pages": serde_json::Value::Null,
                });

                mark_attachment_annotation_ok(
                    conn,
                    key,
                    &job.attachment_sha256,
                    &job.lang,
                    VIDEO_EXTRACT_MODEL_NAME,
                    &payload,
                    now,
                )?;
                return Ok(ContentExtractProcessOutcome::Completed);
            }

            Ok(ContentExtractProcessOutcome::Completed)
        })();

        match result {
            Ok(ContentExtractProcessOutcome::Completed) => {
                processed += 1;
            }
            Ok(ContentExtractProcessOutcome::Deferred) => {}
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
