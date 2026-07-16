use super::{
    RuntimeConfig, ToolDefinition, ToolPermission, ToolPersistence, ToolSource,
    result::{ToolError, ToolResult, ToolResultMetadata},
};
use serde_json::{Value, json};
use std::{
    fs,
    io::ErrorKind,
    path::{Path, PathBuf},
    time::Instant,
};

pub const APPLY_PATCH: &str = "apply_patch";

pub fn definition() -> ToolDefinition {
    ToolDefinition {
        name: APPLY_PATCH.to_string(),
        namespace: None,
        description: "Apply a minimal patch inside the workspace.".to_string(),
        input_schema: json!({
            "type": "object",
            "properties": {
                "patch": { "type": "string" }
            },
            "required": ["patch"],
            "additionalProperties": false
        }),
        output_schema: None,
        permission: ToolPermission::WriteWorkspace,
        persistence: ToolPersistence::Full,
        source: ToolSource::BuiltIn,
    }
}

pub async fn execute(
    config: &RuntimeConfig,
    call_id: &str,
    arguments: Value,
    started: Instant,
) -> ToolResult {
    let args = match parse_args(arguments) {
        Ok(args) => args,
        Err(message) => return failure(call_id, "invalid_arguments", message, started),
    };
    let patch = match parse_patch(&args.patch) {
        Ok(patch) => patch,
        Err(message) => return failure(call_id, "invalid_patch", message, started),
    };
    let planned = match plan_patch(config, patch) {
        Ok(planned) => planned,
        Err(error) => {
            return failure(call_id, error.code, error.message, started);
        }
    };

    for change in &planned.changes {
        match change {
            PlannedChange::Add {
                absolute, content, ..
            } => {
                if let Some(parent) = absolute.parent()
                    && let Err(error) = fs::create_dir_all(parent)
                {
                    return failure(call_id, "internal_error", error.to_string(), started);
                }
                if let Err(error) = fs::write(absolute, content) {
                    return failure(call_id, "internal_error", error.to_string(), started);
                }
            }
            PlannedChange::Update {
                absolute, content, ..
            } => {
                if let Err(error) = fs::write(absolute, content) {
                    return failure(call_id, "internal_error", error.to_string(), started);
                }
            }
            PlannedChange::Delete { absolute, .. } => {
                if let Err(error) = fs::remove_file(absolute) {
                    return failure(call_id, "internal_error", error.to_string(), started);
                }
            }
        }
    }

    ToolResult::success(
        APPLY_PATCH,
        call_id,
        json!({
            "changed_files": planned
                .changes
                .into_iter()
                .map(|change| {
                    let summary = change.summary();
                    json!({
                        "path": summary.path,
                        "action": summary.action,
                        "added_lines": summary.added_lines,
                        "removed_lines": summary.removed_lines
                    })
                })
                .collect::<Vec<_>>()
        }),
        metadata(started),
    )
}

struct ApplyPatchArgs {
    patch: String,
}

#[derive(Debug)]
struct Patch {
    operations: Vec<PatchOperation>,
}

#[derive(Debug)]
enum PatchOperation {
    Add { path: String, lines: Vec<String> },
    Update { path: String, hunks: Vec<Hunk> },
    Delete { path: String },
}

#[derive(Debug)]
struct Hunk {
    lines: Vec<HunkLine>,
}

#[derive(Debug)]
enum HunkLine {
    Context(String),
    Add(String),
    Remove(String),
}

#[derive(Debug)]
struct PlannedPatch {
    changes: Vec<PlannedChange>,
}

#[derive(Debug)]
enum PlannedChange {
    Add {
        path: String,
        absolute: PathBuf,
        content: String,
        added_lines: usize,
    },
    Update {
        path: String,
        absolute: PathBuf,
        content: String,
        added_lines: usize,
        removed_lines: usize,
    },
    Delete {
        path: String,
        absolute: PathBuf,
        removed_lines: usize,
    },
}

#[derive(Debug)]
struct ChangeSummary {
    path: String,
    action: &'static str,
    added_lines: usize,
    removed_lines: usize,
}

#[derive(Debug)]
struct PatchFailure {
    code: &'static str,
    message: String,
}

impl PlannedChange {
    fn summary(self) -> ChangeSummary {
        match self {
            Self::Add {
                path, added_lines, ..
            } => ChangeSummary {
                path,
                action: "add",
                added_lines,
                removed_lines: 0,
            },
            Self::Update {
                path,
                added_lines,
                removed_lines,
                ..
            } => ChangeSummary {
                path,
                action: "update",
                added_lines,
                removed_lines,
            },
            Self::Delete {
                path,
                removed_lines,
                ..
            } => ChangeSummary {
                path,
                action: "delete",
                added_lines: 0,
                removed_lines,
            },
        }
    }
}

fn parse_args(arguments: Value) -> Result<ApplyPatchArgs, String> {
    let Value::Object(mut object) = arguments else {
        return Err("arguments must be an object".to_string());
    };
    if object.len() != 1 || !object.contains_key("patch") {
        return Err("only patch argument is allowed".to_string());
    }
    let Some(Value::String(patch)) = object.remove("patch") else {
        return Err("patch must be a string".to_string());
    };
    if patch.is_empty() {
        return Err("patch must not be empty".to_string());
    }
    Ok(ApplyPatchArgs { patch })
}

fn parse_patch(input: &str) -> Result<Patch, String> {
    let lines = patch_lines(input);
    let mut parser = PatchParser { lines, index: 0 };
    parser.expect_exact("*** Begin Patch")?;
    let mut operations = Vec::new();

    while !parser.is_done() {
        if parser.peek_is("*** End of File") {
            parser.index += 1;
            continue;
        }
        if parser.peek_is("*** End Patch") {
            parser.index += 1;
            if !parser.is_done() {
                return Err("unexpected content after end marker".to_string());
            }
            if operations.is_empty() {
                return Err("patch must include at least one operation".to_string());
            }
            return Ok(Patch { operations });
        }
        operations.push(parser.parse_operation()?);
    }

    Err("missing end marker".to_string())
}

struct PatchParser {
    lines: Vec<String>,
    index: usize,
}

impl PatchParser {
    fn is_done(&self) -> bool {
        self.index >= self.lines.len()
    }

    fn peek(&self) -> Option<&str> {
        self.lines.get(self.index).map(String::as_str)
    }

    fn peek_is(&self, value: &str) -> bool {
        self.peek() == Some(value)
    }

    fn expect_exact(&mut self, value: &str) -> Result<(), String> {
        match self.peek() {
            Some(line) if line == value => {
                self.index += 1;
                Ok(())
            }
            _ => Err(format!("expected {value}")),
        }
    }

    fn parse_operation(&mut self) -> Result<PatchOperation, String> {
        let line = self
            .peek()
            .ok_or_else(|| "expected patch operation".to_string())?
            .to_string();
        if let Some(path) = line.strip_prefix("*** Add File: ") {
            self.index += 1;
            self.parse_add(path.to_string())
        } else if let Some(path) = line.strip_prefix("*** Update File: ") {
            self.index += 1;
            self.parse_update(path.to_string())
        } else if let Some(path) = line.strip_prefix("*** Delete File: ") {
            self.index += 1;
            if path.is_empty() {
                return Err("delete path must not be empty".to_string());
            }
            Ok(PatchOperation::Delete {
                path: path.to_string(),
            })
        } else {
            Err(format!("unsupported patch line: {line}"))
        }
    }

    fn parse_add(&mut self, path: String) -> Result<PatchOperation, String> {
        if path.is_empty() {
            return Err("add path must not be empty".to_string());
        }
        let mut lines = Vec::new();
        while let Some(line) = self.peek() {
            if is_boundary(line) {
                break;
            }
            let Some(content) = line.strip_prefix('+') else {
                return Err("add file lines must start with +".to_string());
            };
            lines.push(format!("{content}\n"));
            self.index += 1;
        }
        if lines.is_empty() {
            return Err("add file requires content lines".to_string());
        }
        Ok(PatchOperation::Add { path, lines })
    }

    fn parse_update(&mut self, path: String) -> Result<PatchOperation, String> {
        if path.is_empty() {
            return Err("update path must not be empty".to_string());
        }
        let mut hunks = Vec::new();
        loop {
            match self.peek() {
                Some(line) if line == "@@" || line.starts_with("@@ ") => {
                    self.index += 1;
                    hunks.push(self.parse_hunk()?);
                }
                Some(line) if is_boundary(line) => break,
                Some(line) => return Err(format!("expected hunk marker, got {line}")),
                None => break,
            }
        }
        if hunks.is_empty() {
            return Err("update file requires at least one hunk".to_string());
        }
        Ok(PatchOperation::Update { path, hunks })
    }

    fn parse_hunk(&mut self) -> Result<Hunk, String> {
        let mut lines = Vec::new();
        while let Some(line) = self.peek() {
            if line == "@@" || line.starts_with("@@ ") || is_boundary(line) {
                break;
            }
            let Some((&prefix, content)) = line.as_bytes().split_first() else {
                return Err("hunk lines must start with space, -, or +".to_string());
            };
            let content = std::str::from_utf8(content)
                .map_err(|_| "hunk lines must start with space, -, or +".to_string())?;
            let content = format!("{content}\n");
            let hunk_line = match prefix {
                b' ' => HunkLine::Context(content),
                b'+' => HunkLine::Add(content),
                b'-' => HunkLine::Remove(content),
                _ => return Err("hunk lines must start with space, -, or +".to_string()),
            };
            lines.push(hunk_line);
            self.index += 1;
        }
        if lines.is_empty() {
            return Err("hunk requires at least one line".to_string());
        }
        Ok(Hunk { lines })
    }
}

fn patch_lines(input: &str) -> Vec<String> {
    input
        .lines()
        .map(|line| line.strip_suffix('\r').unwrap_or(line).to_string())
        .collect()
}

fn is_boundary(line: &str) -> bool {
    line == "*** End Patch"
        || line == "*** End of File"
        || line.starts_with("*** Add File: ")
        || line.starts_with("*** Update File: ")
        || line.starts_with("*** Delete File: ")
}

fn plan_patch(config: &RuntimeConfig, patch: Patch) -> Result<PlannedPatch, PatchFailure> {
    let mut changes = Vec::new();
    for operation in patch.operations {
        changes.push(match operation {
            PatchOperation::Add { path, lines } => plan_add(config, path, lines)?,
            PatchOperation::Update { path, hunks } => plan_update(config, path, hunks)?,
            PatchOperation::Delete { path } => plan_delete(config, path)?,
        });
    }
    validate_planned_changes(&changes)?;
    Ok(PlannedPatch { changes })
}

fn validate_planned_changes(changes: &[PlannedChange]) -> Result<(), PatchFailure> {
    for (index, change) in changes.iter().enumerate() {
        for other in changes.iter().skip(index + 1) {
            if change.path() == other.path() {
                return Err(PatchFailure::new(
                    "patch_apply_failed",
                    "multiple operations target the same path",
                ));
            }
            if change.is_add() && other.is_add() && paths_overlap(change.path(), other.path()) {
                return Err(PatchFailure::new(
                    "patch_apply_failed",
                    "add operations have parent-child path conflict",
                ));
            }
        }
    }
    Ok(())
}

fn plan_add(
    config: &RuntimeConfig,
    path: String,
    lines: Vec<String>,
) -> Result<PlannedChange, PatchFailure> {
    let requested_path = super::path::resolve_workspace_path_with_exclusions(
        &config.workspace_root,
        &path,
        &config.excluded_workspace_roots,
    )
    .map_err(path_failure)?;
    match fs::symlink_metadata(&requested_path.absolute) {
        Ok(_) => return Err(PatchFailure::new("path_exists", "path already exists")),
        Err(error) if error.kind() == ErrorKind::NotFound => {}
        Err(error) => return Err(PatchFailure::new("internal_error", error.to_string())),
    }
    let workspace_path = super::path::resolve_workspace_output_path_with_exclusions(
        &config.workspace_root,
        &path,
        &config.excluded_workspace_roots,
    )
    .map_err(path_failure)?;
    Ok(PlannedChange::Add {
        path: display_path(&workspace_path.relative),
        absolute: workspace_path.absolute,
        added_lines: lines.len(),
        content: lines.concat(),
    })
}

fn plan_update(
    config: &RuntimeConfig,
    path: String,
    hunks: Vec<Hunk>,
) -> Result<PlannedChange, PatchFailure> {
    let workspace_path = super::path::resolve_existing_workspace_path_with_exclusions(
        &config.workspace_root,
        &path,
        &config.excluded_workspace_roots,
    )
    .map_err(path_failure)?;
    ensure_file(&workspace_path.absolute)?;
    let original = read_text_file(&workspace_path.absolute)?;
    let (content, added_lines, removed_lines) = apply_hunks(original, &hunks)?;
    Ok(PlannedChange::Update {
        path: display_path(&workspace_path.relative),
        absolute: workspace_path.absolute,
        content,
        added_lines,
        removed_lines,
    })
}

fn plan_delete(config: &RuntimeConfig, path: String) -> Result<PlannedChange, PatchFailure> {
    let workspace_path = super::path::resolve_existing_workspace_path_with_exclusions(
        &config.workspace_root,
        &path,
        &config.excluded_workspace_roots,
    )
    .map_err(path_failure)?;
    ensure_file(&workspace_path.absolute)?;
    let removed_lines = fs::read(&workspace_path.absolute)
        .map(|bytes| count_lines(&bytes))
        .map_err(|error| PatchFailure::new("internal_error", error.to_string()))?;
    Ok(PlannedChange::Delete {
        path: display_path(&workspace_path.relative),
        absolute: workspace_path.absolute,
        removed_lines,
    })
}

fn apply_hunks(original: String, hunks: &[Hunk]) -> Result<(String, usize, usize), PatchFailure> {
    let mut lines = split_text_lines(&original);
    let mut added_lines = 0;
    let mut removed_lines = 0;
    for hunk in hunks {
        let old_lines = hunk
            .lines
            .iter()
            .filter_map(|line| match line {
                HunkLine::Context(text) | HunkLine::Remove(text) => Some(text.clone()),
                HunkLine::Add(_) => None,
            })
            .collect::<Vec<_>>();
        let new_lines = hunk
            .lines
            .iter()
            .filter_map(|line| match line {
                HunkLine::Context(text) | HunkLine::Add(text) => Some(text.clone()),
                HunkLine::Remove(_) => None,
            })
            .collect::<Vec<_>>();
        let start = unique_subsequence_start(&lines, &old_lines)?;
        added_lines += hunk
            .lines
            .iter()
            .filter(|line| matches!(line, HunkLine::Add(_)))
            .count();
        removed_lines += hunk
            .lines
            .iter()
            .filter(|line| matches!(line, HunkLine::Remove(_)))
            .count();
        lines.splice(start..start + old_lines.len(), new_lines);
    }
    Ok((lines.concat(), added_lines, removed_lines))
}

fn split_text_lines(text: &str) -> Vec<String> {
    if text.is_empty() {
        Vec::new()
    } else {
        text.split_inclusive('\n')
            .map(ToString::to_string)
            .collect()
    }
}

fn unique_subsequence_start(lines: &[String], needle: &[String]) -> Result<usize, PatchFailure> {
    if needle.is_empty() {
        return Err(PatchFailure::new(
            "patch_apply_failed",
            "update hunk must include context or removal lines",
        ));
    }
    let mut matches = lines
        .windows(needle.len())
        .enumerate()
        .filter(|(_, window)| *window == needle);
    let Some((start, _)) = matches.next() else {
        return Err(PatchFailure::new(
            "patch_apply_failed",
            "hunk context did not match file",
        ));
    };
    if matches.next().is_some() {
        return Err(PatchFailure::new(
            "patch_apply_failed",
            "hunk context matched multiple locations",
        ));
    }
    Ok(start)
}

fn paths_overlap(left: &str, right: &str) -> bool {
    let left = Path::new(left);
    let right = Path::new(right);
    left.starts_with(right) || right.starts_with(left)
}

impl PlannedChange {
    fn path(&self) -> &str {
        match self {
            Self::Add { path, .. } | Self::Update { path, .. } | Self::Delete { path, .. } => path,
        }
    }

    fn is_add(&self) -> bool {
        matches!(self, Self::Add { .. })
    }
}

fn ensure_file(path: &Path) -> Result<(), PatchFailure> {
    let metadata = fs::metadata(path).map_err(|error| {
        PatchFailure::new(error_code_for_path(&error.to_string()), error.to_string())
    })?;
    if !metadata.is_file() {
        return Err(PatchFailure::new("path_not_file", "path is not a file"));
    }
    Ok(())
}

fn read_text_file(path: &Path) -> Result<String, PatchFailure> {
    fs::read_to_string(path).map_err(|error| {
        if error.kind() == ErrorKind::InvalidData {
            PatchFailure::new("path_not_text", error.to_string())
        } else {
            PatchFailure::new("internal_error", error.to_string())
        }
    })
}

fn count_lines(bytes: &[u8]) -> usize {
    if bytes.is_empty() {
        0
    } else {
        bytes.iter().filter(|byte| **byte == b'\n').count() + usize::from(!bytes.ends_with(b"\n"))
    }
}

fn display_path(path: &Path) -> String {
    path.components()
        .map(|component| component.as_os_str().to_string_lossy())
        .collect::<Vec<_>>()
        .join("/")
}

fn path_failure(error: anyhow::Error) -> PatchFailure {
    let message = error.to_string();
    PatchFailure::new(error_code_for_path(&message), message)
}

fn error_code_for_path(message: &str) -> &'static str {
    if message == crate::skill_security::RESERVED_SKILL_URI_ERROR
        || message == "workspace path is reserved for skill management"
    {
        "permission_denied"
    } else if message.contains("outside workspace") || message.contains("parent traversal") {
        "path_escape"
    } else if message.contains("No such file") || message.contains("not found") {
        "path_not_found"
    } else {
        "internal_error"
    }
}

impl PatchFailure {
    fn new(code: &'static str, message: impl Into<String>) -> Self {
        Self {
            code,
            message: message.into(),
        }
    }
}

fn metadata(started: Instant) -> ToolResultMetadata {
    ToolResultMetadata {
        duration_ms: started.elapsed().as_millis() as u64,
        ..ToolResultMetadata::default()
    }
}

fn failure(
    call_id: &str,
    code: &'static str,
    message: impl Into<String>,
    started: Instant,
) -> ToolResult {
    ToolResult::failure(
        APPLY_PATCH,
        call_id,
        ToolError {
            code: code.to_string(),
            message: message.into(),
            retryable: false,
        },
        metadata(started),
    )
}

#[cfg(test)]
#[path = "patch_tests.rs"]
mod patch_tests;
