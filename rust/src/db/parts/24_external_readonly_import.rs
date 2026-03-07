use std::collections::BTreeMap;

#[derive(Clone, Debug)]
struct MaterializedExternalImportSource {
    root_dir: PathBuf,
    cleanup_dir: Option<PathBuf>,
    source_label: String,
}

#[derive(Clone, Debug)]
struct CanonicalExternalAttachmentRef {
    source_path: PathBuf,
    attachment_name: String,
    size_bytes: i64,
}

#[derive(Clone, Debug)]
struct CanonicalExternalDocument {
    external_origin_id: String,
    source_rel_path: String,
    title: String,
    body_markdown: String,
    tags: Vec<String>,
    created_at_ms: i64,
    updated_at_ms: i64,
    attachments: Vec<CanonicalExternalAttachmentRef>,
}

#[derive(Clone, Debug)]
struct ParsedExternalImportSource {
    detected_source_kind: String,
    source_label: String,
    documents: Vec<CanonicalExternalDocument>,
    estimated_disk_usage_bytes: i64,
    warnings: Vec<String>,
}

fn emit_external_import_progress(
    on_event: &mut dyn FnMut(ExternalImportProgress),
    batch_id: &str,
    stage: &str,
    done: i64,
    total: i64,
    failed_count: i64,
    status: &str,
) {
    on_event(ExternalImportProgress {
        batch_id: batch_id.to_string(),
        stage: stage.to_string(),
        done,
        total,
        failed_count,
        status: status.to_string(),
    });
}

fn source_label_from_path(path: &Path) -> String {
    path.file_name()
        .and_then(|value| value.to_str())
        .map(|value| value.trim())
        .filter(|value| !value.is_empty())
        .unwrap_or("external-import")
        .to_string()
}

fn materialize_external_import_source(
    app_dir: &Path,
    source_path: &Path,
) -> Result<MaterializedExternalImportSource> {
    if source_path.is_dir() {
        return Ok(MaterializedExternalImportSource {
            root_dir: source_path.to_path_buf(),
            cleanup_dir: None,
            source_label: source_label_from_path(source_path),
        });
    }

    let extension = source_path
        .extension()
        .and_then(|value| value.to_str())
        .map(|value| value.trim().to_ascii_lowercase())
        .unwrap_or_default();
    if extension != "zip" {
        return Err(anyhow!("unsupported import source: expected directory or .zip"));
    }

    let stage_dir = external_readonly_staging_dir(app_dir).join(uuid::Uuid::new_v4().to_string());
    fs::create_dir_all(&stage_dir)?;

    let file = fs::File::open(source_path)?;
    let mut archive = zip::ZipArchive::new(file)?;
    for index in 0..archive.len() {
        let mut entry = archive.by_index(index)?;
        let Some(name) = entry.enclosed_name().map(|value| value.to_path_buf()) else {
            continue;
        };
        let out_path = stage_dir.join(name);
        if entry.is_dir() {
            fs::create_dir_all(&out_path)?;
            continue;
        }
        if let Some(parent) = out_path.parent() {
            fs::create_dir_all(parent)?;
        }
        let mut out = fs::File::create(&out_path)?;
        std::io::copy(&mut entry, &mut out)?;
    }

    Ok(MaterializedExternalImportSource {
        root_dir: stage_dir.clone(),
        cleanup_dir: Some(stage_dir),
        source_label: source_label_from_path(source_path),
    })
}

fn cleanup_materialized_external_import_source(source: &MaterializedExternalImportSource) {
    if let Some(path) = source.cleanup_dir.as_ref() {
        let _ = fs::remove_dir_all(path);
    }
}

fn collect_files_recursively(root: &Path, out: &mut Vec<PathBuf>) -> Result<()> {
    if !root.exists() {
        return Ok(());
    }
    for entry in fs::read_dir(root)? {
        let entry = entry?;
        let path = entry.path();
        if path.is_dir() {
            collect_files_recursively(&path, out)?;
        } else {
            out.push(path);
        }
    }
    Ok(())
}

fn detect_external_source_kind(root: &Path) -> Result<String> {
    if root.join(".obsidian").exists() {
        return Ok("obsidian".to_string());
    }

    let mut files = Vec::<PathBuf>::new();
    collect_files_recursively(root, &mut files)?;
    if files.iter().any(|path| {
        path.extension()
            .and_then(|value| value.to_str())
            .map(|value| value.eq_ignore_ascii_case("sy"))
            .unwrap_or(false)
    }) {
        return Ok("siyuan".to_string());
    }
    Ok("generic_markdown_export".to_string())
}

fn parse_frontmatter_tags(text: &str) -> (Vec<String>, String) {
    let mut tags = BTreeSet::<String>::new();
    let normalized = text.replace("\r\n", "\n");
    if !normalized.starts_with("---\n") {
        return (Vec::new(), normalized);
    }
    let Some(end) = normalized[4..].find("\n---\n") else {
        return (Vec::new(), normalized);
    };
    let end_index = 4 + end;
    let frontmatter = &normalized[4..end_index];
    let body = normalized[(end_index + 5)..].to_string();

    let mut in_tags_list = false;
    for raw_line in frontmatter.lines() {
        let line = raw_line.trim();
        if let Some(rest) = line.strip_prefix("tags:") {
            in_tags_list = true;
            let rest = rest.trim();
            if rest.starts_with('[') && rest.ends_with(']') {
                for item in rest.trim_matches(|ch| ch == '[' || ch == ']').split(',') {
                    let token = item.trim().trim_matches('"').trim_matches('\'');
                    if !token.is_empty() {
                        tags.insert(token.to_string());
                    }
                }
                in_tags_list = false;
            }
            continue;
        }
        if in_tags_list {
            if let Some(item) = line.strip_prefix('-') {
                let token = item.trim().trim_matches('"').trim_matches('\'');
                if !token.is_empty() {
                    tags.insert(token.to_string());
                }
                continue;
            }
            in_tags_list = false;
        }
    }

    (tags.into_iter().collect(), body)
}

fn first_heading_title(text: &str) -> Option<String> {
    for line in text.lines() {
        let trimmed = line.trim();
        if let Some(rest) = trimmed.strip_prefix("# ") {
            let title = rest.trim();
            if !title.is_empty() {
                return Some(title.to_string());
            }
        }
    }
    None
}

fn collect_markdown_paren_links(text: &str) -> Vec<String> {
    let chars: Vec<char> = text.chars().collect();
    let mut out = Vec::<String>::new();
    let mut index = 0usize;
    while index + 2 < chars.len() {
        if chars[index] == ']' && chars[index + 1] == '(' {
            let start = index + 2;
            let mut end = start;
            while end < chars.len() && chars[end] != ')' {
                end += 1;
            }
            if end > start && end < chars.len() {
                let value: String = chars[start..end].iter().collect();
                let cleaned = value.trim().trim_matches('<').trim_matches('>');
                if !cleaned.is_empty() {
                    out.push(cleaned.to_string());
                }
                index = end;
            }
        }
        index += 1;
    }
    out
}

fn collect_obsidian_wikilinks(text: &str) -> Vec<String> {
    let chars: Vec<char> = text.chars().collect();
    let mut out = Vec::<String>::new();
    let mut index = 0usize;
    while index + 3 < chars.len() {
        if chars[index] == '[' && chars[index + 1] == '[' {
            let start = index + 2;
            let mut end = start;
            while end + 1 < chars.len() && !(chars[end] == ']' && chars[end + 1] == ']') {
                end += 1;
            }
            if end > start && end + 1 < chars.len() {
                let value: String = chars[start..end].iter().collect();
                let cleaned = value
                    .split('|')
                    .next()
                    .unwrap_or("")
                    .trim()
                    .trim_start_matches('!')
                    .trim();
                if !cleaned.is_empty() {
                    out.push(cleaned.to_string());
                }
                index = end + 1;
            }
        }
        index += 1;
    }
    out
}

fn collect_siyuan_asset_refs(raw: &str) -> Vec<String> {
    let mut out = Vec::<String>::new();
    let needle = "assets/";
    let bytes = raw.as_bytes();
    let mut index = 0usize;
    while let Some(found) = raw[index..].find(needle) {
        let start = index + found;
        let mut end = start + needle.len();
        while end < bytes.len() {
            let ch = bytes[end] as char;
            if ch.is_whitespace() || matches!(ch, '"' | '\'' | ')' | ']' | '}' | '<' | '>') {
                break;
            }
            end += 1;
        }
        let value = raw[start..end].trim();
        if !value.is_empty() {
            out.push(value.to_string());
        }
        index = end;
    }
    out
}

fn normalize_rel_path(value: &str) -> String {
    value
        .replace('\\', "/")
        .split('#')
        .next()
        .unwrap_or("")
        .split('?')
        .next()
        .unwrap_or("")
        .trim()
        .trim_start_matches("./")
        .to_string()
}

fn is_likely_external_attachment_link(value: &str) -> bool {
    let value = normalize_rel_path(value);
    if value.is_empty() {
        return false;
    }
    if value.starts_with("http://") || value.starts_with("https://") || value.starts_with("mailto:") {
        return false;
    }
    let ext = Path::new(&value)
        .extension()
        .and_then(|item| item.to_str())
        .map(|item| item.trim().to_ascii_lowercase())
        .unwrap_or_default();
    matches!(
        ext.as_str(),
        "png"
            | "jpg"
            | "jpeg"
            | "gif"
            | "webp"
            | "svg"
            | "pdf"
            | "doc"
            | "docx"
            | "ppt"
            | "pptx"
            | "xls"
            | "xlsx"
            | "csv"
            | "txt"
            | "mp3"
            | "wav"
            | "m4a"
            | "mp4"
            | "mov"
            | "avi"
            | "mkv"
    )
}

fn resolve_attachment_path(root: &Path, doc_dir: &Path, raw_ref: &str) -> Option<PathBuf> {
    let normalized = normalize_rel_path(raw_ref);
    if normalized.is_empty() || !is_likely_external_attachment_link(&normalized) {
        return None;
    }

    let direct = doc_dir.join(&normalized);
    if direct.exists() {
        return Some(direct);
    }

    let rooted = root.join(&normalized);
    if rooted.exists() {
        return Some(rooted);
    }

    let filename = Path::new(&normalized).file_name()?.to_str()?.to_string();
    let candidate = root.join("assets").join(filename);
    if candidate.exists() {
        return Some(candidate);
    }

    None
}

fn metadata_time_ms(path: &Path) -> i64 {
    let Ok(metadata) = fs::metadata(path) else {
        return now_ms();
    };
    let Ok(modified) = metadata.modified() else {
        return now_ms();
    };
    let Ok(duration) = modified.duration_since(std::time::UNIX_EPOCH) else {
        return now_ms();
    };
    i64::try_from(duration.as_millis()).unwrap_or(i64::MAX)
}

fn build_canonical_markdown_document(
    root: &Path,
    path: &Path,
    warnings: &mut Vec<String>,
) -> Result<CanonicalExternalDocument> {
    let raw = fs::read_to_string(path)?;
    let (tags, body_without_frontmatter) = parse_frontmatter_tags(&raw);
    let body_markdown = body_without_frontmatter.replace("\r\n", "\n");
    let title = first_heading_title(&body_markdown)
        .or_else(|| {
            path.file_stem()
                .and_then(|value| value.to_str())
                .map(|value| value.trim().to_string())
        })
        .filter(|value| !value.is_empty())
        .unwrap_or_else(|| "Untitled import".to_string());

    let doc_dir = path.parent().unwrap_or(root);
    let mut seen = BTreeSet::<String>::new();
    let mut attachments = Vec::<CanonicalExternalAttachmentRef>::new();
    let mut refs = collect_markdown_paren_links(&body_markdown);
    refs.extend(collect_obsidian_wikilinks(&body_markdown));
    for raw_ref in refs {
        let Some(resolved) = resolve_attachment_path(root, doc_dir, &raw_ref) else {
            if is_likely_external_attachment_link(&raw_ref) {
                warnings.push(format!(
                    "missing attachment reference: {} ({})",
                    raw_ref,
                    path.display()
                ));
            }
            continue;
        };
        let key = resolved.to_string_lossy().to_string();
        if !seen.insert(key) {
            continue;
        }
        let size_bytes = fs::metadata(&resolved)
            .ok()
            .and_then(|meta| i64::try_from(meta.len()).ok())
            .unwrap_or(0);
        let attachment_name = resolved
            .file_name()
            .and_then(|value| value.to_str())
            .unwrap_or("attachment")
            .to_string();
        attachments.push(CanonicalExternalAttachmentRef {
            source_path: resolved,
            attachment_name,
            size_bytes,
        });
    }

    let rel = path
        .strip_prefix(root)
        .unwrap_or(path)
        .to_string_lossy()
        .replace('\\', "/");
    let ts = metadata_time_ms(path);
    Ok(CanonicalExternalDocument {
        external_origin_id: rel.clone(),
        source_rel_path: rel,
        title,
        body_markdown,
        tags,
        created_at_ms: ts,
        updated_at_ms: ts,
        attachments,
    })
}

fn collect_json_strings(value: &serde_json::Value, out: &mut Vec<String>) {
    match value {
        serde_json::Value::Object(map) => {
            for key in ["title", "name", "content", "markdown", "text", "path", "src"] {
                if let Some(text) = map.get(key).and_then(|item| item.as_str()) {
                    let trimmed = text.trim();
                    if !trimmed.is_empty() {
                        out.push(trimmed.to_string());
                    }
                }
            }
            for value in map.values() {
                collect_json_strings(value, out);
            }
        }
        serde_json::Value::Array(items) => {
            for item in items {
                collect_json_strings(item, out);
            }
        }
        serde_json::Value::String(text) => {
            let trimmed = text.trim();
            if !trimmed.is_empty() {
                out.push(trimmed.to_string());
            }
        }
        _ => {}
    }
}

fn build_canonical_siyuan_document(
    root: &Path,
    path: &Path,
    warnings: &mut Vec<String>,
) -> Result<CanonicalExternalDocument> {
    let raw = fs::read_to_string(path)?;
    let json: serde_json::Value = serde_json::from_str(&raw).unwrap_or(serde_json::json!({
        "content": raw,
    }));
    let mut strings = Vec::<String>::new();
    collect_json_strings(&json, &mut strings);
    let mut uniq = BTreeSet::<String>::new();
    strings.retain(|item| uniq.insert(item.clone()));

    let title = json
        .get("title")
        .and_then(|item| item.as_str())
        .map(str::trim)
        .filter(|item| !item.is_empty())
        .map(|item| item.to_string())
        .or_else(|| {
            path.file_stem()
                .and_then(|value| value.to_str())
                .map(|value| value.trim().to_string())
        })
        .filter(|value| !value.is_empty())
        .unwrap_or_else(|| "SiYuan Import".to_string());

    let body_markdown = strings.join("\n\n");
    let doc_dir = path.parent().unwrap_or(root);
    let mut seen = BTreeSet::<String>::new();
    let mut attachments = Vec::<CanonicalExternalAttachmentRef>::new();
    let mut refs = collect_siyuan_asset_refs(&raw);
    refs.extend(collect_siyuan_asset_refs(&body_markdown));
    for raw_ref in refs {
        let Some(resolved) = resolve_attachment_path(root, doc_dir, &raw_ref) else {
            warnings.push(format!(
                "missing SiYuan asset reference: {} ({})",
                raw_ref,
                path.display()
            ));
            continue;
        };
        let key = resolved.to_string_lossy().to_string();
        if !seen.insert(key) {
            continue;
        }
        let size_bytes = fs::metadata(&resolved)
            .ok()
            .and_then(|meta| i64::try_from(meta.len()).ok())
            .unwrap_or(0);
        let attachment_name = resolved
            .file_name()
            .and_then(|value| value.to_str())
            .unwrap_or("attachment")
            .to_string();
        attachments.push(CanonicalExternalAttachmentRef {
            source_path: resolved,
            attachment_name,
            size_bytes,
        });
    }

    let rel = path
        .strip_prefix(root)
        .unwrap_or(path)
        .to_string_lossy()
        .replace('\\', "/");
    let ts = metadata_time_ms(path);
    Ok(CanonicalExternalDocument {
        external_origin_id: rel.clone(),
        source_rel_path: rel,
        title,
        body_markdown,
        tags: Vec::new(),
        created_at_ms: ts,
        updated_at_ms: ts,
        attachments,
    })
}

fn parse_materialized_external_source(
    root: &Path,
    source_label: &str,
) -> Result<ParsedExternalImportSource> {
    let detected_source_kind = detect_external_source_kind(root)?;
    let mut files = Vec::<PathBuf>::new();
    collect_files_recursively(root, &mut files)?;

    let mut warnings = Vec::<String>::new();
    let mut documents = Vec::<CanonicalExternalDocument>::new();

    match detected_source_kind.as_str() {
        "siyuan" => {
            files.sort();
            for path in files {
                let is_sy = path
                    .extension()
                    .and_then(|value| value.to_str())
                    .map(|value| value.eq_ignore_ascii_case("sy"))
                    .unwrap_or(false);
                if !is_sy {
                    continue;
                }
                match build_canonical_siyuan_document(root, &path, &mut warnings) {
                    Ok(doc) => documents.push(doc),
                    Err(e) => warnings.push(format!("failed to parse {}: {e}", path.display())),
                }
            }
        }
        _ => {
            files.sort();
            for path in files {
                let is_md = path
                    .extension()
                    .and_then(|value| value.to_str())
                    .map(|value| value.eq_ignore_ascii_case("md"))
                    .unwrap_or(false);
                if !is_md || path.components().any(|part| part.as_os_str() == ".obsidian") {
                    continue;
                }
                match build_canonical_markdown_document(root, &path, &mut warnings) {
                    Ok(doc) => documents.push(doc),
                    Err(e) => warnings.push(format!("failed to parse {}: {e}", path.display())),
                }
            }
        }
    }

    let mut unique_attachments = BTreeMap::<String, i64>::new();
    let mut estimated_disk_usage_bytes = 0i64;
    for doc in &documents {
        estimated_disk_usage_bytes = estimated_disk_usage_bytes
            .saturating_add(i64::try_from(doc.body_markdown.len()).unwrap_or(i64::MAX));
        for attachment in &doc.attachments {
            unique_attachments
                .entry(attachment.source_path.to_string_lossy().to_string())
                .or_insert(attachment.size_bytes.max(0));
        }
    }
    estimated_disk_usage_bytes = estimated_disk_usage_bytes.saturating_add(
        unique_attachments
            .values()
            .copied()
            .fold(0i64, |acc, value| acc.saturating_add(value.max(0))),
    );

    Ok(ParsedExternalImportSource {
        detected_source_kind,
        source_label: source_label.to_string(),
        documents,
        estimated_disk_usage_bytes,
        warnings,
    })
}

pub fn scan_external_import_source(app_dir: &Path, source_path: &Path) -> Result<ExternalImportScanSummary> {
    let materialized = materialize_external_import_source(app_dir, source_path)?;
    let parsed = parse_materialized_external_source(&materialized.root_dir, &materialized.source_label);
    cleanup_materialized_external_import_source(&materialized);
    let parsed = parsed?;

    let mut unique_attachments = BTreeSet::<String>::new();
    for doc in &parsed.documents {
        for attachment in &doc.attachments {
            unique_attachments.insert(attachment.source_path.to_string_lossy().to_string());
        }
    }

    Ok(ExternalImportScanSummary {
        detected_source_kind: parsed.detected_source_kind,
        source_label: parsed.source_label,
        notes_count: i64::try_from(parsed.documents.len()).unwrap_or(i64::MAX),
        attachments_count: i64::try_from(unique_attachments.len()).unwrap_or(i64::MAX),
        estimated_disk_usage_bytes: parsed.estimated_disk_usage_bytes,
        warnings: parsed.warnings,
    })
}

fn insert_external_import_batch(
    conn: &Connection,
    batch_id: &str,
    source_kind: &str,
    source_label: &str,
) -> Result<()> {
    let now = now_ms();
    conn.execute(
        r#"INSERT INTO external_import_batches(
             batch_id, source_kind, source_label, status, created_at_ms, updated_at_ms, completed_at_ms, stats_json, last_error
           ) VALUES (?1, ?2, ?3, 'in_progress', ?4, ?4, NULL, '{}', NULL)"#,
        params![batch_id, source_kind, source_label, now],
    )?;
    Ok(())
}

fn update_external_import_batch(
    conn: &Connection,
    batch_id: &str,
    status: &str,
    stats_json: &str,
    last_error: Option<&str>,
    completed_at_ms: Option<i64>,
) -> Result<()> {
    let now = now_ms();
    conn.execute(
        r#"UPDATE external_import_batches
           SET status = ?2,
               updated_at_ms = ?3,
               completed_at_ms = ?4,
               stats_json = ?5,
               last_error = ?6
           WHERE batch_id = ?1"#,
        params![batch_id, status, now, completed_at_ms, stats_json, last_error],
    )?;
    Ok(())
}

fn insert_external_document(
    conn: &Connection,
    key: &[u8; 32],
    batch_id: &str,
    doc: &CanonicalExternalDocument,
) -> Result<String> {
    let doc_id = uuid::Uuid::new_v4().to_string();
    let title_blob = encode_external_document_title(key, &doc_id, &doc.title)?;
    let body_blob = encode_external_document_body(key, &doc_id, &doc.body_markdown)?;
    let tags_json = serde_json::to_string(&doc.tags).unwrap_or_else(|_| "[]".to_string());
    let tags_blob = encode_external_document_tags(key, &doc_id, &tags_json)?;
    let checksum_sha256 = sha256_hex(doc.body_markdown.as_bytes());

    conn.execute(
        r#"INSERT INTO external_documents(
             doc_id, batch_id, external_origin_id, source_rel_path, title, body_markdown, tags_json,
             created_at_ms, updated_at_ms, checksum_sha256, is_deleted
           ) VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, 0)"#,
        params![
            doc_id,
            batch_id,
            doc.external_origin_id,
            doc.source_rel_path,
            title_blob,
            body_blob,
            tags_blob,
            doc.created_at_ms,
            doc.updated_at_ms,
            checksum_sha256,
        ],
    )?;

    let chunks = split_attachment_text_into_chunks(&doc.body_markdown);
    if chunks.is_empty() && !doc.body_markdown.trim().is_empty() {
        let blob = encode_external_chunk_text(key, &doc_id, 0, doc.body_markdown.trim())?;
        conn.execute(
            r#"INSERT INTO external_document_chunks(doc_id, chunk_index, chunk_text, created_at_ms, updated_at_ms)
               VALUES (?1, 0, ?2, ?3, ?3)"#,
            params![doc_id, blob, now_ms()],
        )?;
    } else {
        let now = now_ms();
        for (chunk_index, (start_offset, end_offset)) in chunks.into_iter().enumerate() {
            if end_offset <= start_offset {
                continue;
            }
            let chunk_text = doc.body_markdown[start_offset..end_offset].trim();
            if chunk_text.is_empty() {
                continue;
            }
            let chunk_index_i64 = i64::try_from(chunk_index).unwrap_or(i64::MAX);
            let blob = encode_external_chunk_text(key, &doc_id, chunk_index_i64, chunk_text)?;
            conn.execute(
                r#"INSERT INTO external_document_chunks(doc_id, chunk_index, chunk_text, created_at_ms, updated_at_ms)
                   VALUES (?1, ?2, ?3, ?4, ?4)"#,
                params![doc_id, chunk_index_i64, blob, now],
            )?;
        }
    }

    Ok(doc_id)
}

fn copy_or_link_external_attachment(
    app_dir: &Path,
    conn: &Connection,
    key: &[u8; 32],
    source_path: &Path,
) -> Result<(String, bool, i64)> {
    let bytes = fs::read(source_path)?;
    let sha256 = sha256_hex(&bytes);
    let size_bytes = i64::try_from(bytes.len()).unwrap_or(i64::MAX);

    let existing: Option<(i64, String)> = conn
        .query_row(
            r#"SELECT ref_count, stored_path FROM external_attachments WHERE sha256 = ?1"#,
            params![sha256],
            |row| Ok((row.get(0)?, row.get(1)?)),
        )
        .optional()?;

    if existing.is_some() {
        conn.execute(
            r#"UPDATE external_attachments
               SET ref_count = ref_count + 1
               WHERE sha256 = ?1"#,
            params![sha256],
        )?;
        return Ok((sha256, false, size_bytes));
    }

    fs::create_dir_all(external_readonly_attachment_dir(app_dir))?;
    let rel_path = format!(
        "external_readonly/storage/attachments/{sha256}.bin"
    );
    let full_path = app_dir.join(&rel_path);
    let blob = encrypt_bytes(key, &bytes, &external_attachment_aad(&sha256))?;
    fs::write(full_path, blob)?;

    conn.execute(
        r#"INSERT INTO external_attachments(sha256, stored_path, size_bytes, mime_type, ref_count, created_at_ms)
           VALUES (?1, ?2, ?3, ?4, 1, ?5)"#,
        params![
            sha256,
            rel_path,
            size_bytes,
            infer_external_mime_type(source_path),
            now_ms(),
        ],
    )?;

    Ok((sha256, true, size_bytes))
}

fn link_external_attachment_to_document(
    conn: &Connection,
    doc_id: &str,
    sha256: &str,
    attachment_name: &str,
    ordinal: i64,
) -> Result<()> {
    conn.execute(
        r#"INSERT INTO external_document_attachments(doc_id, sha256, attachment_name, ordinal)
           VALUES (?1, ?2, ?3, ?4)"#,
        params![doc_id, sha256, attachment_name, ordinal],
    )?;
    Ok(())
}

fn cancel_requested(app_dir: &Path, batch_id: &str, should_cancel: &dyn Fn() -> bool) -> bool {
    should_cancel() || external_cancel_flag_path(app_dir, batch_id).exists()
}

fn delete_external_import_batch_internal(
    app_dir: &Path,
    conn: &Connection,
    batch_id: &str,
    remove_batch_row: bool,
    terminal_status: Option<&str>,
) -> Result<()> {
    let mut attachment_decrements = BTreeMap::<String, i64>::new();
    let mut stmt = conn.prepare(
        r#"SELECT a.sha256, COUNT(*)
           FROM external_document_attachments a
           JOIN external_documents d ON d.doc_id = a.doc_id
           WHERE d.batch_id = ?1
           GROUP BY a.sha256"#,
    )?;
    let mut rows = stmt.query(params![batch_id])?;
    while let Some(row) = rows.next()? {
        let sha256: String = row.get(0)?;
        let decrement: i64 = row.get(1)?;
        attachment_decrements.insert(sha256, decrement.max(0));
    }

    let space_ids = list_external_embedding_space_ids(conn)?;
    for space_id in space_ids {
        let table = external_chunk_embeddings_table(&space_id)?;
        if !sqlite_table_exists(conn, &table)? {
            continue;
        }
        conn.execute(
            &format!(
                r#"DELETE FROM "{table}"
                   WHERE doc_id IN (
                     SELECT doc_id FROM external_documents WHERE batch_id = ?1
                   )"#
            ),
            params![batch_id],
        )?;
    }

    let mut files_to_remove = Vec::<PathBuf>::new();
    for (sha256, decrement) in attachment_decrements {
        let existing: Option<(i64, String)> = conn
            .query_row(
                r#"SELECT ref_count, stored_path FROM external_attachments WHERE sha256 = ?1"#,
                params![sha256],
                |row| Ok((row.get(0)?, row.get(1)?)),
            )
            .optional()?;
        let Some((ref_count, stored_path)) = existing else {
            continue;
        };
        if ref_count <= decrement {
            conn.execute(
                r#"DELETE FROM external_attachments WHERE sha256 = ?1"#,
                params![sha256],
            )?;
            files_to_remove.push(app_dir.join(stored_path));
        } else {
            conn.execute(
                r#"UPDATE external_attachments SET ref_count = ?2 WHERE sha256 = ?1"#,
                params![sha256, ref_count - decrement],
            )?;
        }
    }

    conn.execute(
        r#"DELETE FROM external_documents WHERE batch_id = ?1"#,
        params![batch_id],
    )?;

    if remove_batch_row {
        conn.execute(
            r#"DELETE FROM external_import_batches WHERE batch_id = ?1"#,
            params![batch_id],
        )?;
    } else if let Some(status) = terminal_status {
        update_external_import_batch(conn, batch_id, status, &build_external_stats_json(0, 0, 0, 0), None, Some(now_ms()))?;
    }

    for path in files_to_remove {
        let _ = best_effort_remove_external_path(&path);
    }
    let _ = best_effort_remove_external_path(&external_cancel_flag_path(app_dir, batch_id));
    Ok(())
}

pub fn delete_external_import_batch(app_dir: &Path, batch_id: &str) -> Result<()> {
    let conn = open_external_readonly_db(app_dir)?;
    conn.execute_batch("BEGIN IMMEDIATE;")?;
    let result = delete_external_import_batch_internal(app_dir, &conn, batch_id, true, None);
    match result {
        Ok(()) => {
            conn.execute_batch("COMMIT;")?;
            Ok(())
        }
        Err(e) => {
            let _ = conn.execute_batch("ROLLBACK;");
            Err(e)
        }
    }
}

pub fn run_external_import_with_callbacks(
    app_dir: &Path,
    key: &[u8; 32],
    source_path: &Path,
    on_event: &mut dyn FnMut(ExternalImportProgress),
    should_cancel: &dyn Fn() -> bool,
) -> Result<ExternalImportBatchSummary> {
    let materialized = materialize_external_import_source(app_dir, source_path)?;
    let parsed_result = parse_materialized_external_source(&materialized.root_dir, &materialized.source_label);
    let parsed = match parsed_result {
        Ok(parsed) => parsed,
        Err(e) => {
            cleanup_materialized_external_import_source(&materialized);
            return Err(e);
        }
    };

    let batch_id = uuid::Uuid::new_v4().to_string();
    let mut failed_count = 0i64;
    let mut copied_bytes = 0i64;
    let mut unique_attachment_shas = BTreeSet::<String>::new();

    let conn = open_external_readonly_db(app_dir)?;
    insert_external_import_batch(&conn, &batch_id, &parsed.detected_source_kind, &parsed.source_label)?;

    emit_external_import_progress(on_event, &batch_id, "preparing", 0, 1, 0, "in_progress");
    emit_external_import_progress(
        on_event,
        &batch_id,
        "scanning",
        i64::try_from(parsed.documents.len()).unwrap_or(i64::MAX),
        i64::try_from(parsed.documents.len()).unwrap_or(i64::MAX),
        0,
        "in_progress",
    );

    let result = (|| -> Result<ExternalImportBatchSummary> {
        let mut imported_docs = Vec::<(String, Vec<CanonicalExternalAttachmentRef>)>::new();
        let total_docs = i64::try_from(parsed.documents.len()).unwrap_or(i64::MAX);
        for (index, doc) in parsed.documents.iter().enumerate() {
            if cancel_requested(app_dir, &batch_id, should_cancel) {
                conn.execute_batch("BEGIN IMMEDIATE;")?;
                let cancel_result = delete_external_import_batch_internal(
                    app_dir,
                    &conn,
                    &batch_id,
                    false,
                    Some("cancelled"),
                );
                match cancel_result {
                    Ok(()) => conn.execute_batch("COMMIT;")?,
                    Err(e) => {
                        let _ = conn.execute_batch("ROLLBACK;");
                        return Err(e);
                    }
                }
                let summary = read_external_import_batch_summary(&conn, &batch_id)?;
                emit_external_import_progress(on_event, &batch_id, "rollback", 1, 1, failed_count, "cancelled");
                emit_external_import_progress(on_event, &batch_id, "cancelled", 1, 1, failed_count, "cancelled");
                return Ok(summary);
            }

            match insert_external_document(&conn, key, &batch_id, doc) {
                Ok(doc_id) => imported_docs.push((doc_id, doc.attachments.clone())),
                Err(_) => {
                    failed_count += 1;
                }
            }
            emit_external_import_progress(
                on_event,
                &batch_id,
                "parsing",
                i64::try_from(index + 1).unwrap_or(i64::MAX),
                total_docs,
                failed_count,
                "in_progress",
            );
        }

        let total_attachment_refs = imported_docs
            .iter()
            .map(|(_, attachments)| attachments.len())
            .sum::<usize>();
        for (ordinal_base, (doc_id, attachments)) in imported_docs.iter().enumerate() {
            let _ = ordinal_base;
            for (attachment_index, attachment) in attachments.iter().enumerate() {
                if cancel_requested(app_dir, &batch_id, should_cancel) {
                    conn.execute_batch("BEGIN IMMEDIATE;")?;
                    let cancel_result = delete_external_import_batch_internal(
                        app_dir,
                        &conn,
                        &batch_id,
                        false,
                        Some("cancelled"),
                    );
                    match cancel_result {
                        Ok(()) => conn.execute_batch("COMMIT;")?,
                        Err(e) => {
                            let _ = conn.execute_batch("ROLLBACK;");
                            return Err(e);
                        }
                    }
                    let summary = read_external_import_batch_summary(&conn, &batch_id)?;
                    emit_external_import_progress(on_event, &batch_id, "rollback", 1, 1, failed_count, "cancelled");
                    emit_external_import_progress(on_event, &batch_id, "cancelled", 1, 1, failed_count, "cancelled");
                    return Ok(summary);
                }

                match copy_or_link_external_attachment(app_dir, &conn, key, &attachment.source_path) {
                    Ok((sha256, inserted_new, size_bytes)) => {
                        if inserted_new {
                            copied_bytes = copied_bytes.saturating_add(size_bytes.max(0));
                        }
                        unique_attachment_shas.insert(sha256.clone());
                        if link_external_attachment_to_document(
                            &conn,
                            doc_id,
                            &sha256,
                            &attachment.attachment_name,
                            i64::try_from(attachment_index).unwrap_or(i64::MAX),
                        )
                        .is_err()
                        {
                            failed_count += 1;
                        }
                    }
                    Err(_) => {
                        failed_count += 1;
                    }
                }
                let done = conn
                    .query_row(
                        r#"SELECT COUNT(*) FROM external_document_attachments a
                           JOIN external_documents d ON d.doc_id = a.doc_id
                           WHERE d.batch_id = ?1"#,
                        params![batch_id],
                        |row| row.get::<_, i64>(0),
                    )
                    .unwrap_or(0);
                emit_external_import_progress(
                    on_event,
                    &batch_id,
                    "copying_attachments",
                    done,
                    i64::try_from(total_attachment_refs).unwrap_or(i64::MAX),
                    failed_count,
                    "in_progress",
                );
            }
        }

        let total_chunks: i64 = conn.query_row(
            r#"SELECT COUNT(*)
               FROM external_document_chunks c
               JOIN external_documents d ON d.doc_id = c.doc_id
               WHERE d.batch_id = ?1"#,
            params![batch_id],
            |row| row.get(0),
        )?;

        let mut indexed = 0i64;
        loop {
            let processed = process_pending_external_document_embeddings_default(app_dir, key, 256)?;
            if processed == 0 {
                break;
            }
            indexed = indexed.saturating_add(i64::try_from(processed).unwrap_or(i64::MAX));
            emit_external_import_progress(
                on_event,
                &batch_id,
                "indexing_phase_a",
                indexed.min(total_chunks.max(0)),
                total_chunks,
                failed_count,
                "in_progress",
            );
        }
        emit_external_import_progress(on_event, &batch_id, "verifying", 1, 1, failed_count, "in_progress");

        let stats_json = build_external_stats_json(
            i64::try_from(parsed.documents.len()).unwrap_or(i64::MAX),
            i64::try_from(unique_attachment_shas.len()).unwrap_or(i64::MAX),
            failed_count,
            copied_bytes,
        );
        update_external_import_batch(
            &conn,
            &batch_id,
            "completed",
            &stats_json,
            None,
            Some(now_ms()),
        )?;

        let summary = read_external_import_batch_summary(&conn, &batch_id)?;
        emit_external_import_progress(on_event, &batch_id, "completed", 1, 1, failed_count, "completed");
        Ok(summary)
    })();

    cleanup_materialized_external_import_source(&materialized);

    match result {
        Ok(summary) => Ok(summary),
        Err(e) => {
            let stats_json = build_external_stats_json(0, 0, failed_count, copied_bytes);
            let _ = update_external_import_batch(&conn, &batch_id, "failed", &stats_json, Some(&e.to_string()), Some(now_ms()));
            let _ = delete_external_import_batch_internal(app_dir, &conn, &batch_id, false, Some("failed"));
            Err(e)
        }
    }
}
