use std::collections::BTreeMap;
use std::io::Read;

const MAX_EXTERNAL_IMPORT_ZIP_ENTRY_BYTES: u64 = 64 * 1024 * 1024;
const MAX_EXTERNAL_IMPORT_ZIP_TOTAL_BYTES: u64 = 512 * 1024 * 1024;

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
    diagnostics: Vec<ExternalImportParseDiagnostic>,
}

#[derive(Clone, Debug)]
struct ExternalImportParseDiagnostic {
    stage: String,
    severity: String,
    code: String,
    message: String,
    source_rel_path: Option<String>,
}

#[derive(Clone, Debug)]
struct MarkdownNoteCandidate {
    rel_path: String,
    rel_path_without_extension: String,
    basename: String,
    basename_without_extension: String,
    parent_dir: String,
}

#[derive(Clone, Debug, Default)]
struct MarkdownNoteIndex {
    candidates: Vec<MarkdownNoteCandidate>,
    by_key: BTreeMap<String, Vec<usize>>,
}

#[derive(Clone, Debug)]
struct MarkdownWikilinkReference {
    raw: String,
    target: String,
    is_embed: bool,
}

#[derive(Clone, Debug)]
struct ParsedWikilinkTarget {
    lookup_key: String,
    explicit_extension: Option<String>,
}

enum MarkdownNoteMatch {
    Unique,
    Ambiguous,
    Missing,
}

fn normalize_external_import_source_rel_path(root: &Path, path: &Path) -> String {
    path.strip_prefix(root)
        .unwrap_or(path)
        .to_string_lossy()
        .replace('\\', "/")
}

fn push_parse_diagnostic(
    diagnostics: &mut Vec<ExternalImportParseDiagnostic>,
    stage: &str,
    severity: &str,
    code: &str,
    message: impl Into<String>,
    source_rel_path: Option<String>,
) {
    diagnostics.push(ExternalImportParseDiagnostic {
        stage: stage.to_string(),
        severity: severity.to_string(),
        code: code.to_string(),
        message: message.into(),
        source_rel_path,
    });
}

fn warning_messages_from_diagnostics(
    diagnostics: &[ExternalImportParseDiagnostic],
) -> Vec<String> {
    diagnostics.iter().map(|item| item.message.clone()).collect()
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

fn materialize_external_import_source_from_zip_reader<R: Read + std::io::Seek>(
    app_dir: &Path,
    source_label: String,
    reader: R,
) -> Result<MaterializedExternalImportSource> {
    let stage_dir = external_readonly_staging_dir(app_dir).join(uuid::Uuid::new_v4().to_string());
    fs::create_dir_all(&stage_dir)?;

    let extract_result = (|| -> Result<()> {
        let mut archive = zip::ZipArchive::new(reader)?;
        let mut total_extracted_bytes = 0u64;
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
            let copied_bytes = std::io::copy(
                &mut entry.by_ref().take(MAX_EXTERNAL_IMPORT_ZIP_ENTRY_BYTES + 1),
                &mut out,
            )?;
            if copied_bytes > MAX_EXTERNAL_IMPORT_ZIP_ENTRY_BYTES {
                return Err(anyhow!(
                    "archive entry exceeds size limit: {}",
                    out_path.display()
                ));
            }
            total_extracted_bytes = total_extracted_bytes.saturating_add(copied_bytes);
            if total_extracted_bytes > MAX_EXTERNAL_IMPORT_ZIP_TOTAL_BYTES {
                return Err(anyhow!(
                    "archive exceeds size limit: {} bytes",
                    MAX_EXTERNAL_IMPORT_ZIP_TOTAL_BYTES
                ));
            }
        }
        Ok(())
    })();
    if let Err(err) = extract_result {
        let _ = fs::remove_dir_all(&stage_dir);
        return Err(err);
    }

    Ok(MaterializedExternalImportSource {
        root_dir: stage_dir.clone(),
        cleanup_dir: Some(stage_dir),
        source_label,
    })
}

#[cfg(test)]
fn materialize_external_import_source_from_zip_bytes(
    app_dir: &Path,
    source_label: &str,
    zip_bytes: &[u8],
) -> Result<MaterializedExternalImportSource> {
    materialize_external_import_source_from_zip_reader(
        app_dir,
        source_label.to_string(),
        std::io::Cursor::new(zip_bytes),
    )
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

    let file = fs::File::open(source_path)?;
    materialize_external_import_source_from_zip_reader(
        app_dir,
        source_label_from_path(source_path),
        file,
    )
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

fn collect_markdown_wikilinks(text: &str) -> Vec<MarkdownWikilinkReference> {
    let chars: Vec<char> = text.chars().collect();
    let mut out = Vec::<MarkdownWikilinkReference>::new();
    let mut index = 0usize;
    while index + 3 < chars.len() {
        if chars[index] == '[' && chars[index + 1] == '[' {
            let is_embed = index > 0 && chars[index - 1] == '!';
            let start = index + 2;
            let mut end = start;
            while end + 1 < chars.len() && !(chars[end] == ']' && chars[end + 1] == ']') {
                end += 1;
            }
            if end > start && end + 1 < chars.len() {
                let raw: String = chars[start..end].iter().collect();
                let target = raw
                    .split('|')
                    .next()
                    .unwrap_or("")
                    .trim()
                    .to_string();
                if !target.is_empty() {
                    out.push(MarkdownWikilinkReference {
                        raw,
                        target,
                        is_embed,
                    });
                }
                index = end + 1;
            }
        }
        index += 1;
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
        .trim_start_matches('/')
        .to_string()
}

fn normalize_note_lookup_key(value: &str) -> String {
    normalize_rel_path(value).to_ascii_lowercase()
}

fn markdown_extension_for_path(path: &Path) -> Option<String> {
    path.extension()
        .and_then(|value| value.to_str())
        .map(|value| value.trim().to_ascii_lowercase())
        .filter(|value| is_markdown_extension(value))
}

fn is_markdown_extension(value: &str) -> bool {
    matches!(value, "md" | "markdown" | "mdown" | "mkd")
}

fn is_supported_markdown_path(path: &Path) -> bool {
    path.is_file() && markdown_extension_for_path(path).is_some()
}

fn strip_markdown_extension(value: &str) -> String {
    let normalized = normalize_rel_path(value);
    let Some(extension) = Path::new(&normalized)
        .extension()
        .and_then(|item| item.to_str())
        .map(|item| item.trim().to_ascii_lowercase())
    else {
        return normalized;
    };
    if !is_markdown_extension(&extension) {
        return normalized;
    }
    let suffix_len = extension.len() + 1;
    normalized[..normalized.len().saturating_sub(suffix_len)].to_string()
}

fn is_remote_reference(value: &str) -> bool {
    let trimmed = value.trim();
    trimmed.starts_with("http://")
        || trimmed.starts_with("https://")
        || trimmed.starts_with("mailto:")
}

fn is_likely_external_attachment_link(value: &str) -> bool {
    let value = normalize_rel_path(value);
    if value.is_empty() || is_remote_reference(&value) {
        return false;
    }
    let Some(ext) = Path::new(&value)
        .extension()
        .and_then(|item| item.to_str())
        .map(|item| item.trim().to_ascii_lowercase())
    else {
        return false;
    };
    !is_markdown_extension(&ext)
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

fn build_markdown_note_index(root: &Path, markdown_paths: &[PathBuf]) -> MarkdownNoteIndex {
    let mut index = MarkdownNoteIndex::default();
    for path in markdown_paths {
        let rel_path = normalize_external_import_source_rel_path(root, path);
        let rel_path_without_extension = strip_markdown_extension(&rel_path);
        let basename = path
            .file_name()
            .and_then(|value| value.to_str())
            .map(|value| value.trim().to_string())
            .unwrap_or_else(|| rel_path.clone());
        let basename_without_extension = path
            .file_stem()
            .and_then(|value| value.to_str())
            .map(|value| value.trim().to_string())
            .unwrap_or_else(|| basename.clone());
        let parent_dir = path
            .parent()
            .map(|parent| normalize_external_import_source_rel_path(root, parent))
            .unwrap_or_default();

        let candidate = MarkdownNoteCandidate {
            rel_path: normalize_note_lookup_key(&rel_path),
            rel_path_without_extension: normalize_note_lookup_key(&rel_path_without_extension),
            basename: normalize_note_lookup_key(&basename),
            basename_without_extension: normalize_note_lookup_key(&basename_without_extension),
            parent_dir: normalize_note_lookup_key(&parent_dir),
        };
        let candidate_index = index.candidates.len();
        let mut keys = BTreeSet::<String>::new();
        keys.insert(candidate.rel_path.clone());
        keys.insert(candidate.rel_path_without_extension.clone());
        keys.insert(candidate.basename.clone());
        keys.insert(candidate.basename_without_extension.clone());
        for key in keys {
            if key.is_empty() {
                continue;
            }
            index.by_key.entry(key).or_default().push(candidate_index);
        }
        index.candidates.push(candidate);
    }
    index
}

fn path_distance(from_dir: &str, to_dir: &str) -> usize {
    let from_components: Vec<&str> = from_dir.split('/').filter(|item| !item.is_empty()).collect();
    let to_components: Vec<&str> = to_dir.split('/').filter(|item| !item.is_empty()).collect();
    let mut shared = 0usize;
    while shared < from_components.len()
        && shared < to_components.len()
        && from_components[shared] == to_components[shared]
    {
        shared += 1;
    }
    (from_components.len().saturating_sub(shared)) + (to_components.len().saturating_sub(shared))
}

fn resolve_markdown_note_target(
    note_index: &MarkdownNoteIndex,
    doc_dir: &Path,
    root: &Path,
    target: &str,
) -> MarkdownNoteMatch {
    let lookup_key = normalize_note_lookup_key(target);
    if lookup_key.is_empty() {
        return MarkdownNoteMatch::Missing;
    }
    let Some(candidate_indices) = note_index.by_key.get(&lookup_key) else {
        return MarkdownNoteMatch::Missing;
    };
    if candidate_indices.len() == 1 {
        return MarkdownNoteMatch::Unique;
    }

    let doc_dir_key = normalize_note_lookup_key(&normalize_external_import_source_rel_path(root, doc_dir));
    let mut ranked = candidate_indices
        .iter()
        .map(|candidate_index| {
            let candidate = &note_index.candidates[*candidate_index];
            (*candidate_index, path_distance(&doc_dir_key, &candidate.parent_dir))
        })
        .collect::<Vec<(usize, usize)>>();
    ranked.sort_by_key(|(_, distance)| *distance);
    let Some((_, best_distance)) = ranked.first().copied() else {
        return MarkdownNoteMatch::Missing;
    };
    let tied_best_count = ranked
        .iter()
        .filter(|(_, distance)| *distance == best_distance)
        .count();
    if tied_best_count > 1 {
        MarkdownNoteMatch::Ambiguous
    } else {
        MarkdownNoteMatch::Unique
    }
}

fn parse_wikilink_target(raw_target: &str) -> Option<ParsedWikilinkTarget> {
    let target_without_heading = raw_target.split('#').next().unwrap_or("").trim();
    let lookup_key = normalize_note_lookup_key(target_without_heading);
    if lookup_key.is_empty() {
        return None;
    }
    let explicit_extension = Path::new(&lookup_key)
        .extension()
        .and_then(|value| value.to_str())
        .map(|value| value.trim().to_ascii_lowercase());
    Some(ParsedWikilinkTarget {
        lookup_key,
        explicit_extension,
    })
}

fn push_attachment_if_resolved(
    attachments: &mut Vec<CanonicalExternalAttachmentRef>,
    seen: &mut BTreeSet<String>,
    resolved: PathBuf,
) {
    let key = resolved.to_string_lossy().to_string();
    if !seen.insert(key) {
        return;
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

fn build_canonical_markdown_document(
    root: &Path,
    path: &Path,
    note_index: &MarkdownNoteIndex,
    diagnostics: &mut Vec<ExternalImportParseDiagnostic>,
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

    let rel = normalize_external_import_source_rel_path(root, path);
    let doc_dir = path.parent().unwrap_or(root);
    let mut seen = BTreeSet::<String>::new();
    let mut attachments = Vec::<CanonicalExternalAttachmentRef>::new();

    for raw_ref in collect_markdown_paren_links(&body_markdown) {
        let Some(resolved) = resolve_attachment_path(root, doc_dir, &raw_ref) else {
            if is_likely_external_attachment_link(&raw_ref) {
                push_parse_diagnostic(
                    diagnostics,
                    "scan",
                    "warning",
                    "missing_attachment_reference",
                    format!("missing attachment reference: {raw_ref}"),
                    Some(rel.clone()),
                );
            }
            continue;
        };
        push_attachment_if_resolved(&mut attachments, &mut seen, resolved);
    }

    for wikilink in collect_markdown_wikilinks(&body_markdown) {
        let Some(parsed_target) = parse_wikilink_target(&wikilink.target) else {
            continue;
        };
        let is_explicit_markdown = parsed_target
            .explicit_extension
            .as_deref()
            .map(is_markdown_extension)
            .unwrap_or(false);
        let is_attachment_like = parsed_target
            .explicit_extension
            .as_deref()
            .map(|_| is_likely_external_attachment_link(&parsed_target.lookup_key))
            .unwrap_or(false);

        if is_attachment_like {
            if let Some(resolved) = resolve_attachment_path(root, doc_dir, &parsed_target.lookup_key) {
                push_attachment_if_resolved(&mut attachments, &mut seen, resolved);
            } else {
                push_parse_diagnostic(
                    diagnostics,
                    "scan",
                    "warning",
                    "missing_attachment_reference",
                    format!("missing attachment reference: {}", wikilink.raw),
                    Some(rel.clone()),
                );
            }
            continue;
        }

        if is_explicit_markdown || parsed_target.explicit_extension.is_none() || wikilink.is_embed {
            match resolve_markdown_note_target(note_index, doc_dir, root, &parsed_target.lookup_key) {
                MarkdownNoteMatch::Unique => {}
                MarkdownNoteMatch::Ambiguous => push_parse_diagnostic(
                    diagnostics,
                    "scan",
                    "warning",
                    "ambiguous_wikilink_target",
                    format!("ambiguous wikilink target: {}", wikilink.raw),
                    Some(rel.clone()),
                ),
                MarkdownNoteMatch::Missing => push_parse_diagnostic(
                    diagnostics,
                    "scan",
                    "warning",
                    "unresolved_wikilink_target",
                    format!("unresolved wikilink target: {}", wikilink.raw),
                    Some(rel.clone()),
                ),
            }
        }
    }

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

fn parse_materialized_external_source(
    root: &Path,
    source_label: &str,
) -> Result<ParsedExternalImportSource> {
    let mut files = Vec::<PathBuf>::new();
    collect_files_recursively(root, &mut files)?;
    files.sort();

    let markdown_paths = files
        .into_iter()
        .filter(|path| is_supported_markdown_path(path))
        .collect::<Vec<PathBuf>>();
    let note_index = build_markdown_note_index(root, &markdown_paths);

    let mut diagnostics = Vec::<ExternalImportParseDiagnostic>::new();
    let mut documents = Vec::<CanonicalExternalDocument>::new();
    for path in markdown_paths {
        match build_canonical_markdown_document(root, &path, &note_index, &mut diagnostics) {
            Ok(doc) => documents.push(doc),
            Err(e) => push_parse_diagnostic(
                &mut diagnostics,
                "scan",
                "error",
                "parse_markdown_document_failed",
                format!("failed to parse {}: {e}", path.display()),
                Some(normalize_external_import_source_rel_path(root, &path)),
            ),
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

    let warnings = warning_messages_from_diagnostics(&diagnostics);
    Ok(ParsedExternalImportSource {
        detected_source_kind: "markdown".to_string(),
        source_label: source_label.to_string(),
        documents,
        estimated_disk_usage_bytes,
        warnings,
        diagnostics,
    })
}

pub fn scan_external_import_source(
    app_dir: &Path,
    source_path: &Path,
) -> Result<ExternalImportScanSummary> {
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
