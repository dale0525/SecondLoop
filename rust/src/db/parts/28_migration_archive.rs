pub const MIGRATION_ARCHIVE_SCHEMA_VERSION: i64 = 1;

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct MigrationArchiveManifest {
    pub schema_version: i64,
    pub archive_kind: String,
    pub exported_at_ms: i64,
    pub app_version: String,
    pub items: Vec<MigrationArchiveItem>,
    pub attachments: Vec<MigrationArchiveAttachment>,
    pub relations: Vec<MigrationArchiveRelation>,
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct MigrationArchiveItem {
    pub id: String,
    pub entity_type: String,
    pub markdown_path: String,
    pub created_at_ms: i64,
    pub updated_at_ms: i64,
    pub title: String,
    pub tags: Vec<String>,
    pub status: Option<String>,
    pub extra_json: Option<String>,
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct MigrationArchiveAttachment {
    pub sha256: String,
    pub archive_path: String,
    pub original_filename: String,
    pub mime_type: Option<String>,
    pub size_bytes: i64,
    pub item_ids: Vec<String>,
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct MigrationArchiveRelation {
    pub from_id: String,
    pub to_id: String,
    pub relation_type: String,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct MigrationArchiveExportEstimate {
    pub schema_version: i64,
    pub archive_kind: String,
    pub item_count: i64,
    pub attachment_count: i64,
    pub estimated_size_bytes: i64,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct MigrationArchiveProgress {
    pub operation: String,
    pub stage: String,
    pub done: i64,
    pub total: i64,
    pub status: String,
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
struct MigrationArchiveOperationState {
    operation: String,
    stage: String,
    done: i64,
    total: i64,
    status: String,
    updated_at_ms: i64,
    last_error: Option<String>,
    item_count: Option<i64>,
    attachment_count: Option<i64>,
    relation_count: Option<i64>,
}

pub fn migration_archive_markdown_path_for_id(id: &str) -> String {
    format!("items/{id}.md")
}

pub fn migration_archive_wikilink(id: &str, title: &str) -> String {
    format!("[[{id}|{title}]]")
}

fn migration_archive_emit_progress(
    on_event: &mut dyn FnMut(MigrationArchiveProgress),
    operation: &str,
    stage: &str,
    done: i64,
    total: i64,
    status: &str,
) {
    on_event(MigrationArchiveProgress {
        operation: operation.to_string(),
        stage: stage.to_string(),
        done,
        total,
        status: status.to_string(),
    });
}

pub fn parse_migration_archive_manifest_json(
    manifest_json: &str,
) -> Result<MigrationArchiveManifest> {
    let manifest: MigrationArchiveManifest = serde_json::from_str(manifest_json)?;
    validate_migration_archive_manifest(&manifest)?;
    Ok(manifest)
}

fn validate_migration_archive_relative_path(label: &str, value: &str) -> Result<()> {
    if value.trim().is_empty() {
        return Err(anyhow!("{label} must not be empty"));
    }
    let candidate = Path::new(value);
    for component in candidate.components() {
        match component {
            std::path::Component::Prefix(_)
            | std::path::Component::RootDir
            | std::path::Component::ParentDir => {
                return Err(anyhow!("{label} contains path traversal: {value}"));
            }
            std::path::Component::CurDir | std::path::Component::Normal(_) => {}
        }
    }
    Ok(())
}

fn is_valid_migration_archive_sha256(value: &str) -> bool {
    value.len() == 64 && value.bytes().all(|byte| byte.is_ascii_hexdigit())
}

pub fn validate_migration_archive_manifest(manifest: &MigrationArchiveManifest) -> Result<()> {
    if manifest.schema_version <= 0 {
        return Err(anyhow!("schema_version must be positive"));
    }
    if manifest.schema_version > MIGRATION_ARCHIVE_SCHEMA_VERSION {
        return Err(anyhow!(
            "archive schema_version {} is newer than this build supports ({}); please update the app before importing",
            manifest.schema_version,
            MIGRATION_ARCHIVE_SCHEMA_VERSION
        ));
    }
    if manifest.archive_kind.trim() != "migration" {
        return Err(anyhow!("archive_kind must be migration"));
    }
    if manifest.app_version.trim().is_empty() {
        return Err(anyhow!("app_version must not be empty"));
    }
    for item in &manifest.items {
        if item.id.trim().is_empty() {
            return Err(anyhow!("item id must not be empty"));
        }
        validate_migration_archive_relative_path("item markdown_path", &item.markdown_path)?;
    }
    for attachment in &manifest.attachments {
        if !is_valid_migration_archive_sha256(&attachment.sha256) {
            return Err(anyhow!(
                "attachment sha256 must be 64 lowercase or uppercase hex characters: {}",
                attachment.sha256
            ));
        }
        if let Err(err) = validate_migration_archive_relative_path(
            "attachment archive_path",
            &attachment.archive_path,
        ) {
            return Err(anyhow!(
                "{err}: {}",
                attachment.archive_path
            ));
        }
    }
    Ok(())
}

fn migration_archive_root_dir(app_dir: &Path) -> PathBuf {
    app_dir.join("migration_archive")
}

fn migration_archive_staging_dir(app_dir: &Path) -> PathBuf {
    migration_archive_root_dir(app_dir).join("staging")
}

fn migration_archive_state_dir(app_dir: &Path) -> PathBuf {
    migration_archive_root_dir(app_dir).join("state")
}

fn migration_archive_state_path(app_dir: &Path, operation: &str) -> PathBuf {
    migration_archive_state_dir(app_dir).join(format!("{operation}.json"))
}

#[allow(clippy::too_many_arguments)]
fn migration_archive_write_state(
    app_dir: &Path,
    operation: &str,
    stage: &str,
    done: i64,
    total: i64,
    status: &str,
    last_error: Option<String>,
    item_count: Option<i64>,
    attachment_count: Option<i64>,
    relation_count: Option<i64>,
) -> Result<()> {
    let state = MigrationArchiveOperationState {
        operation: operation.to_string(),
        stage: stage.to_string(),
        done,
        total,
        status: status.to_string(),
        updated_at_ms: now_ms(),
        last_error,
        item_count,
        attachment_count,
        relation_count,
    };
    let state_path = migration_archive_state_path(app_dir, operation);
    if let Some(parent) = state_path.parent() {
        fs::create_dir_all(parent)?;
    }
    fs::write(state_path, serde_json::to_vec_pretty(&state)?)?;
    Ok(())
}

fn migration_archive_record_progress(
    app_dir: &Path,
    on_event: &mut dyn FnMut(MigrationArchiveProgress),
    operation: &str,
    stage: &str,
    done: i64,
    total: i64,
    status: &str,
) -> Result<()> {
    migration_archive_write_state(
        app_dir,
        operation,
        stage,
        done,
        total,
        status,
        None,
        None,
        None,
        None,
    )?;
    migration_archive_emit_progress(on_event, operation, stage, done, total, status);
    Ok(())
}

#[allow(clippy::too_many_arguments)]
fn migration_archive_record_terminal_state(
    app_dir: &Path,
    on_event: &mut dyn FnMut(MigrationArchiveProgress),
    operation: &str,
    stage: &str,
    done: i64,
    total: i64,
    status: &str,
    last_error: Option<String>,
    item_count: Option<i64>,
    attachment_count: Option<i64>,
    relation_count: Option<i64>,
) -> Result<()> {
    migration_archive_write_state(
        app_dir,
        operation,
        stage,
        done,
        total,
        status,
        last_error,
        item_count,
        attachment_count,
        relation_count,
    )?;
    migration_archive_emit_progress(on_event, operation, stage, done, total, status);
    Ok(())
}

fn migration_archive_extension_for_mime(mime_type: &str) -> &'static str {
    match mime_type.trim() {
        "image/png" => "png",
        "image/jpeg" => "jpg",
        "image/gif" => "gif",
        "image/webp" => "webp",
        "application/pdf" => "pdf",
        "text/markdown" => "md",
        "text/plain" => "txt",
        "audio/mpeg" => "mp3",
        "audio/wav" => "wav",
        "audio/mp4" => "m4a",
        "video/mp4" => "mp4",
        _ => "bin",
    }
}

fn migration_archive_attachment_path(sha256: &str, mime_type: &str) -> String {
    format!(
        "attachments/{sha256}.{}",
        migration_archive_extension_for_mime(mime_type)
    )
}

fn migration_archive_yaml_list(items: &[String]) -> String {
    if items.is_empty() {
        return "[]".to_string();
    }
    let quoted = items
        .iter()
        .map(|item| format!("\"{}\"", item.replace('"', "\\\"")))
        .collect::<Vec<String>>()
        .join(", ");
    format!("[{quoted}]")
}

fn migration_archive_markdown_doc(
    item: &MigrationArchiveItem,
    body: &str,
    attachment_paths: &[String],
    internal_links: &[String],
) -> String {
    let mut out = String::new();
    out.push_str("---\n");
    out.push_str(&format!("id: {}\n", item.id));
    out.push_str(&format!("title: \"{}\"\n", item.title.replace('"', "\\\"")));
    out.push_str(&format!("type: {}\n", item.entity_type));
    out.push_str(&format!("created_at: {}\n", item.created_at_ms));
    out.push_str(&format!("updated_at: {}\n", item.updated_at_ms));
    out.push_str(&format!("tags: {}\n", migration_archive_yaml_list(&item.tags)));
    if let Some(status) = item.status.as_ref() {
        out.push_str(&format!("status: {}\n", status));
    }
    out.push_str("---\n\n");
    out.push_str(&format!("# {}\n\n", item.title));
    let trimmed_body = body.trim();
    if !trimmed_body.is_empty() {
        out.push_str(trimmed_body);
        out.push_str("\n\n");
    }
    if !internal_links.is_empty() {
        out.push_str("## References\n\n");
        for link in internal_links {
            out.push_str(&format!("- {link}\n"));
        }
        out.push('\n');
    }
    if !attachment_paths.is_empty() {
        out.push_str("## Attachments\n\n");
        for path in attachment_paths {
            out.push_str(&format!("- [attachment](../{path})\n"));
        }
    }
    out
}

pub(crate) fn migration_archive_rewrite_embedded_attachment_refs(
    body: &str,
    attachments: &std::collections::BTreeMap<String, MigrationArchiveAttachment>,
) -> String {
    if body.trim().is_empty() || attachments.is_empty() {
        return body.to_string();
    }

    let mut rewritten = String::with_capacity(body.len());
    let mut cursor = 0;

    while cursor < body.len() {
        if let Some(block_end) = migration_archive_find_fenced_code_block_end(body, cursor) {
            rewritten.push_str(&body[cursor..block_end]);
            cursor = block_end;
            continue;
        }

        if let Some(span_end) = migration_archive_find_inline_code_span_end(body, cursor) {
            rewritten.push_str(&body[cursor..span_end]);
            cursor = span_end;
            continue;
        }

        if let Some((image_end, image_segment)) =
            migration_archive_rewrite_markdown_image_ref(body, cursor, attachments)
        {
            rewritten.push_str(&image_segment);
            cursor = image_end;
            continue;
        }

        let ch = body[cursor..].chars().next().expect("char boundary");
        rewritten.push(ch);
        cursor += ch.len_utf8();
    }

    rewritten
}

fn migration_archive_find_fenced_code_block_end(body: &str, start: usize) -> Option<usize> {
    let (fence_char, fence_len) = migration_archive_parse_fence_marker(body, start)?;
    let content_start = migration_archive_line_end(body, start)?;
    let mut cursor = content_start;
    while cursor < body.len() {
        if let Some((candidate_char, candidate_len)) =
            migration_archive_parse_fence_marker(body, cursor)
        {
            if candidate_char == fence_char && candidate_len >= fence_len {
                return migration_archive_line_end(body, cursor).or(Some(body.len()));
            }
        }
        cursor = migration_archive_line_end(body, cursor).unwrap_or(body.len());
    }
    Some(body.len())
}

fn migration_archive_parse_fence_marker(body: &str, start: usize) -> Option<(u8, usize)> {
    if !migration_archive_is_line_start(body, start) {
        return None;
    }

    let bytes = body.as_bytes();
    let mut cursor = start;
    let mut leading_spaces = 0;
    while cursor < bytes.len() && bytes[cursor] == b' ' && leading_spaces < 3 {
        cursor += 1;
        leading_spaces += 1;
    }
    if cursor >= bytes.len() {
        return None;
    }

    let fence_char = bytes[cursor];
    if fence_char != b'`' && fence_char != b'~' {
        return None;
    }

    let mut fence_len = 0;
    while cursor + fence_len < bytes.len() && bytes[cursor + fence_len] == fence_char {
        fence_len += 1;
    }
    if fence_len < 3 {
        return None;
    }

    Some((fence_char, fence_len))
}

fn migration_archive_find_inline_code_span_end(body: &str, start: usize) -> Option<usize> {
    let bytes = body.as_bytes();
    if bytes.get(start) != Some(&b'`') {
        return None;
    }

    let mut tick_count = 0;
    while start + tick_count < bytes.len() && bytes[start + tick_count] == b'`' {
        tick_count += 1;
    }
    let marker = &body[start..start + tick_count];
    let mut search = start + tick_count;
    while search < body.len() {
        if body[search..].starts_with(marker) {
            return Some(search + tick_count);
        }
        let ch = body[search..].chars().next().expect("char boundary");
        search += ch.len_utf8();
    }
    Some(body.len())
}

fn migration_archive_rewrite_markdown_image_ref(
    body: &str,
    start: usize,
    attachments: &std::collections::BTreeMap<String, MigrationArchiveAttachment>,
) -> Option<(usize, String)> {
    if !body[start..].starts_with("![") {
        return None;
    }

    let alt_end = migration_archive_find_unescaped_byte(body, start + 2, b']')?;
    let paren_start = alt_end + 1;
    if body.as_bytes().get(paren_start) != Some(&b'(') {
        return None;
    }

    let source_start = paren_start + 1;
    let bytes = body.as_bytes();
    let (token_end, normalized_source, preserve_angle_brackets) =
        if bytes.get(source_start) == Some(&b'<') {
            let source_end = migration_archive_find_unescaped_byte(body, source_start + 1, b'>')?;
            (
                source_end + 1,
                body[source_start + 1..source_end].trim().to_string(),
                true,
            )
        } else {
            let mut cursor = source_start;
            while cursor < body.len() {
                match bytes[cursor] {
                    b')' | b' ' | b'\t' | b'\n' | b'\r' => break,
                    _ => cursor += 1,
                }
            }
            if cursor == source_start {
                return None;
            }
            (cursor, body[source_start..cursor].trim().to_string(), false)
        };

    let close_paren = migration_archive_find_unescaped_byte(body, token_end, b')')?;
    let attachment_sha = normalized_source.strip_prefix("secondloop://attachment/")?;
    let attachment = attachments.get(attachment_sha)?;
    let replacement_source = format!("../{}", attachment.archive_path);
    let replacement_token = if preserve_angle_brackets {
        format!("<{replacement_source}>")
    } else {
        replacement_source
    };
    let rewritten = format!(
        "{}{}{}",
        &body[start..source_start],
        replacement_token,
        &body[token_end..=close_paren]
    );
    Some((close_paren + 1, rewritten))
}

fn migration_archive_find_unescaped_byte(body: &str, start: usize, needle: u8) -> Option<usize> {
    let bytes = body.as_bytes();
    let mut cursor = start;
    while cursor < bytes.len() {
        if bytes[cursor] == needle && (cursor == 0 || bytes[cursor - 1] != b'\\') {
            return Some(cursor);
        }
        cursor += 1;
    }
    None
}

fn migration_archive_is_line_start(body: &str, index: usize) -> bool {
    index == 0 || body.as_bytes().get(index.wrapping_sub(1)) == Some(&b'\n')
}

fn migration_archive_line_end(body: &str, start: usize) -> Option<usize> {
    if start >= body.len() {
        return None;
    }
    match body[start..].find('\n') {
        Some(offset) => Some(start + offset + 1),
        None => Some(body.len()),
    }
}
