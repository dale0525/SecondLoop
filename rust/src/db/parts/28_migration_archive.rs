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
        if item.markdown_path.trim().is_empty() {
            return Err(anyhow!("markdown_path must not be empty"));
        }
    }
    for attachment in &manifest.attachments {
        let candidate = Path::new(&attachment.archive_path);
        if candidate.is_absolute()
            || candidate
                .components()
                .any(|component| component == std::path::Component::ParentDir)
        {
            return Err(anyhow!(
                "attachment archive_path contains path traversal: {}",
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

    let mut rewritten = body.to_string();
    for attachment in attachments.values() {
        let source = format!("secondloop://attachment/{}", attachment.sha256);
        let replacement = format!("../{}", attachment.archive_path);
        rewritten = rewritten.replace(&format!("({source})"), &format!("({replacement})"));
        rewritten = rewritten.replace(&format!("(<{source}>)"), &format!("(<{replacement}>)"));
    }

    rewritten
}
