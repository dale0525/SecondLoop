use super::{
    RuntimeConfig, ToolDefinition, ToolPermission, ToolPersistence, ToolSource,
    result::{ToolError, ToolResult, ToolResultMetadata},
};
use serde_json::{Value, json};
use std::{
    io::ErrorKind,
    path::{Path, PathBuf},
    process::Stdio,
    time::Instant,
};
use tokio::{
    io::{AsyncBufReadExt, BufReader},
    process::Command,
};

pub const SEARCH_FILES: &str = "search_files";
const MAX_SEARCH_RESULTS: usize = 1_000;
const MAX_MATCH_TEXT_BYTES: usize = 4_096;

pub fn definition() -> ToolDefinition {
    ToolDefinition {
        name: SEARCH_FILES.to_string(),
        namespace: None,
        description: "Search for text matches inside the workspace.".to_string(),
        input_schema: json!({
            "type": "object",
            "properties": {
                "pattern": { "type": "string" },
                "path": { "type": "string" },
                "limit": { "type": "integer", "minimum": 1 }
            },
            "required": ["pattern"],
            "additionalProperties": false
        }),
        output_schema: None,
        permission: ToolPermission::ReadWorkspace,
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
    let args = match parse_args(&arguments) {
        Ok(args) => args,
        Err(error) => {
            return failure("invalid_arguments", error.to_string(), call_id, started);
        }
    };
    let workspace_path = match super::path::resolve_existing_workspace_path_with_exclusions(
        &config.workspace_root,
        &args.path,
        &config.excluded_workspace_roots,
    ) {
        Ok(path) => path,
        Err(error) => {
            return failure(
                error_code(&error.to_string()),
                error.to_string(),
                call_id,
                started,
            );
        }
    };
    let workspace_root = match config.workspace_root.canonicalize() {
        Ok(path) => path,
        Err(error) => return failure("path_not_found", error.to_string(), call_id, started),
    };
    let excluded = match super::path::canonical_excluded_roots(
        &config.workspace_root,
        &config.excluded_workspace_roots,
    ) {
        Ok(paths) => paths,
        Err(error) => return failure("permission_denied", error.to_string(), call_id, started),
    };

    let (matches, truncated, engine) = match rg_search(
        &workspace_root,
        &workspace_path.absolute,
        &args.pattern,
        args.limit,
        &excluded,
    )
    .await
    {
        Ok(Some((matches, truncated))) => (matches, truncated, "rg"),
        Ok(None) => {
            match fallback_search(
                &workspace_path.absolute,
                &workspace_path.relative,
                &args.pattern,
                args.limit,
                &excluded,
            )
            .await
            {
                Ok((matches, truncated)) => (matches, truncated, "fallback"),
                Err(error) => {
                    return failure("search_failed", error.to_string(), call_id, started);
                }
            }
        }
        Err(error) => return failure("search_failed", error.to_string(), call_id, started),
    };

    ToolResult::success(
        SEARCH_FILES,
        call_id,
        json!({
            "path": relative_path(&workspace_path.relative),
            "pattern": args.pattern,
            "matches": matches
                .into_iter()
                .map(|item| json!({
                    "path": item.path,
                    "line": item.line,
                    "column": item.column,
                    "text": item.text
                }))
                .collect::<Vec<_>>(),
            "truncated": truncated,
            "engine": engine
        }),
        metadata(started),
    )
}

#[derive(Debug)]
struct SearchArgs {
    pattern: String,
    path: String,
    limit: usize,
}

#[derive(Debug, Clone)]
struct SearchMatch {
    path: String,
    line: usize,
    column: usize,
    text: String,
}

fn parse_args(arguments: &Value) -> anyhow::Result<SearchArgs> {
    let pattern = arguments
        .get("pattern")
        .and_then(Value::as_str)
        .filter(|value| !value.is_empty())
        .ok_or_else(|| anyhow::anyhow!("invalid arguments: missing string field pattern"))?
        .to_string();
    let path = match arguments.get("path") {
        Some(value) => value
            .as_str()
            .filter(|value| !value.is_empty())
            .ok_or_else(|| anyhow::anyhow!("invalid arguments: field path must be a string"))?
            .to_string(),
        None => ".".to_string(),
    };
    let limit = match arguments.get("limit") {
        Some(value) => {
            let limit = value.as_u64().ok_or_else(|| {
                anyhow::anyhow!("invalid arguments: limit must be a positive integer")
            })?;
            if limit == 0 {
                anyhow::bail!("invalid arguments: limit must be a positive integer");
            }
            let limit = usize::try_from(limit)
                .map_err(|_| anyhow::anyhow!("invalid arguments: limit is too large"))?;
            if limit > MAX_SEARCH_RESULTS {
                anyhow::bail!("invalid arguments: limit must be at most {MAX_SEARCH_RESULTS}");
            }
            limit
        }
        None => 100,
    };

    Ok(SearchArgs {
        pattern,
        path,
        limit,
    })
}

async fn rg_search(
    workspace_root: &Path,
    absolute: &Path,
    pattern: &str,
    limit: usize,
    excluded: &[PathBuf],
) -> anyhow::Result<Option<(Vec<SearchMatch>, bool)>> {
    let mut command = Command::new("rg");
    command
        .current_dir(workspace_root)
        .arg("--json")
        .arg("--color")
        .arg("never");
    for root in excluded {
        let Ok(relative) = root.strip_prefix(workspace_root) else {
            continue;
        };
        let relative = relative.to_string_lossy().replace('\\', "/");
        if !relative.is_empty() {
            command.arg("--glob").arg(format!("!{relative}"));
            command.arg("--glob").arg(format!("!{relative}/**"));
        }
    }
    let target = absolute
        .strip_prefix(workspace_root)
        .ok()
        .filter(|path| !path.as_os_str().is_empty())
        .unwrap_or_else(|| Path::new("."));
    let mut child = match command
        .arg("--")
        .arg(pattern)
        .arg(target)
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .spawn()
    {
        Ok(child) => child,
        Err(error) if error.kind() == ErrorKind::NotFound => return Ok(None),
        Err(error) => return Err(error.into()),
    };
    let stdout = child
        .stdout
        .take()
        .ok_or_else(|| anyhow::anyhow!("rg stdout was not captured"))?;
    let mut lines = BufReader::new(stdout).lines();

    let mut matches = Vec::new();
    let mut truncated = false;
    while let Some(line) = lines.next_line().await? {
        let event: Value = match serde_json::from_str(&line) {
            Ok(event) => event,
            Err(_) => continue,
        };
        if event.get("type").and_then(Value::as_str) != Some("match") {
            continue;
        }
        if matches.len() >= limit {
            truncated = true;
            break;
        }

        let data = &event["data"];
        let match_path = data["path"]["text"].as_str().unwrap_or_default();
        let display_path = Path::new(match_path)
            .strip_prefix(workspace_root)
            .unwrap_or_else(|_| Path::new(match_path))
            .to_path_buf();
        let line_text = data["lines"]["text"]
            .as_str()
            .unwrap_or_default()
            .trim_end_matches(['\n', '\r']);
        let column = data["submatches"]
            .as_array()
            .and_then(|items| items.first())
            .and_then(|item| item["start"].as_u64())
            .map(|value| value as usize + 1)
            .unwrap_or(1);

        matches.push(SearchMatch {
            path: relative_path(&display_path),
            line: data["line_number"].as_u64().unwrap_or(1) as usize,
            column,
            text: truncate_match_text(line_text),
        });
    }

    if truncated {
        drop(lines);
        child.kill().await?;
        return Ok(Some((matches, true)));
    }

    let output = child.wait_with_output().await?;
    if !output.status.success() && output.status.code() != Some(1) {
        anyhow::bail!(
            "rg failed: {}",
            String::from_utf8_lossy(&output.stderr).trim()
        );
    }

    Ok(Some((matches, truncated)))
}

async fn fallback_search(
    absolute: &Path,
    relative: &Path,
    pattern: &str,
    limit: usize,
    excluded: &[PathBuf],
) -> anyhow::Result<(Vec<SearchMatch>, bool)> {
    let mut files = Vec::new();
    collect_files(absolute, relative, excluded, &mut files).await?;
    files.sort_by(|left, right| left.1.cmp(&right.1));

    let mut matches = Vec::new();
    for (absolute_file, relative_file) in files {
        let bytes = match tokio::fs::read(&absolute_file).await {
            Ok(bytes) => bytes,
            Err(_) => continue,
        };
        let text = match String::from_utf8(bytes) {
            Ok(text) => text,
            Err(_) => continue,
        };
        for (line_index, line) in text.lines().enumerate() {
            if let Some(column_index) = line.find(pattern) {
                if matches.len() >= limit {
                    return Ok((matches, true));
                }
                matches.push(SearchMatch {
                    path: relative_path(&relative_file),
                    line: line_index + 1,
                    column: column_index + 1,
                    text: truncate_match_text(line),
                });
            }
        }
    }

    Ok((matches, false))
}

async fn collect_files(
    absolute: &Path,
    relative: &Path,
    excluded: &[PathBuf],
    files: &mut Vec<(PathBuf, PathBuf)>,
) -> anyhow::Result<()> {
    let mut stack = vec![(absolute.to_path_buf(), relative.to_path_buf())];
    while let Some((current_absolute, current_relative)) = stack.pop() {
        if super::path::path_is_excluded(&current_absolute, excluded) {
            continue;
        }
        let metadata = tokio::fs::symlink_metadata(&current_absolute).await?;
        if metadata.is_file() {
            files.push((current_absolute, current_relative));
            continue;
        }
        if !metadata.is_dir() {
            continue;
        }

        let mut entries = tokio::fs::read_dir(&current_absolute).await?;
        while let Some(entry) = entries.next_entry().await? {
            let file_name = entry.file_name();
            stack.push((entry.path(), current_relative.join(file_name)));
        }
    }

    Ok(())
}

fn metadata(started: Instant) -> ToolResultMetadata {
    ToolResultMetadata {
        duration_ms: started.elapsed().as_millis() as u64,
        ..ToolResultMetadata::default()
    }
}

fn failure(code: &str, message: impl Into<String>, call_id: &str, started: Instant) -> ToolResult {
    ToolResult::failure(
        SEARCH_FILES,
        call_id,
        ToolError {
            code: code.to_string(),
            message: message.into(),
            retryable: false,
        },
        metadata(started),
    )
}

fn error_code(message: &str) -> &'static str {
    if message == crate::skill_security::RESERVED_SKILL_URI_ERROR
        || message == "workspace path is reserved for skill management"
    {
        "permission_denied"
    } else if message.contains("outside workspace")
        || message.contains("parent traversal")
        || message.contains("empty workspace path")
        || message.contains("must be an absolute path")
    {
        "path_outside_workspace"
    } else if message.contains("No such file or directory")
        || message.contains("entity not found")
        || message.contains("failed to resolve workspace path")
    {
        "path_not_found"
    } else {
        "internal_error"
    }
}

fn relative_path(path: &Path) -> String {
    let normalized = path
        .components()
        .filter(|component| !matches!(component, std::path::Component::CurDir))
        .collect::<PathBuf>();
    let value = normalized.to_string_lossy().to_string();
    if value.is_empty() {
        ".".to_string()
    } else {
        value
    }
}

fn truncate_match_text(text: &str) -> String {
    if text.len() <= MAX_MATCH_TEXT_BYTES {
        return text.to_string();
    }

    let mut end = MAX_MATCH_TEXT_BYTES;
    while !text.is_char_boundary(end) {
        end -= 1;
    }
    text[..end].to_string()
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::tools::RuntimeConfig;
    use serde_json::json;
    use std::path::PathBuf;

    #[tokio::test]
    async fn search_files_returns_structured_matches() {
        let root = unique_test_dir("search-matches");
        tokio::fs::create_dir_all(root.join("src")).await.unwrap();
        tokio::fs::write(
            root.join("src").join("lib.rs"),
            "fn main() {\n    let needle = true;\n}\n",
        )
        .await
        .unwrap();
        tokio::fs::write(root.join("src").join("other.rs"), "nothing here\n")
            .await
            .unwrap();
        let config = RuntimeConfig::workspace_write(&root, &root);

        let result = execute(
            &config,
            "call-1",
            json!({ "pattern": "needle", "path": "src", "limit": 10 }),
            std::time::Instant::now(),
        )
        .await;

        assert!(result.ok);
        let data = result.data.unwrap();
        assert_eq!(data["path"], "src");
        assert_eq!(data["pattern"], "needle");
        assert_eq!(data["truncated"], false);
        let matches = data["matches"].as_array().unwrap();
        assert_eq!(matches.len(), 1);
        assert_eq!(matches[0]["path"], "src/lib.rs");
        assert_eq!(matches[0]["line"], 2);
        assert_eq!(matches[0]["column"], 9);
        assert!(matches[0]["text"].as_str().unwrap().contains("needle"));
        remove_test_dir(root).await;
    }

    #[tokio::test]
    async fn search_files_applies_limit_and_truncation_flag() {
        let root = unique_test_dir("search-limit");
        tokio::fs::create_dir_all(&root).await.unwrap();
        tokio::fs::write(root.join("a.txt"), "needle\nneedle\nneedle\n")
            .await
            .unwrap();
        let config = RuntimeConfig::workspace_write(&root, &root);

        let result = execute(
            &config,
            "call-1",
            json!({ "pattern": "needle", "limit": 2 }),
            std::time::Instant::now(),
        )
        .await;

        assert!(result.ok);
        let data = result.data.unwrap();
        assert_eq!(data["matches"].as_array().unwrap().len(), 2);
        assert_eq!(data["truncated"], true);
        remove_test_dir(root).await;
    }

    #[tokio::test]
    async fn search_files_rejects_workspace_escape() {
        let root = unique_test_dir("search-escape");
        tokio::fs::create_dir_all(&root).await.unwrap();
        let config = RuntimeConfig::workspace_write(&root, &root);

        let result = execute(
            &config,
            "call-1",
            json!({ "pattern": "secret", "path": "../outside" }),
            std::time::Instant::now(),
        )
        .await;

        assert!(!result.ok);
        assert_eq!(result.error.unwrap().code, "path_outside_workspace");
        remove_test_dir(root).await;
    }

    #[tokio::test]
    async fn search_files_rejects_invalid_arguments() {
        let root = unique_test_dir("search-invalid-args");
        tokio::fs::create_dir_all(&root).await.unwrap();
        let config = RuntimeConfig::workspace_write(&root, &root);

        let result = execute(
            &config,
            "call-1",
            json!({ "pattern": "", "limit": 0 }),
            std::time::Instant::now(),
        )
        .await;

        assert!(!result.ok);
        assert_eq!(result.error.unwrap().code, "invalid_arguments");
        remove_test_dir(root).await;
    }

    #[tokio::test]
    async fn search_files_rejects_limit_above_maximum() {
        let root = unique_test_dir("search-limit-above-max");
        tokio::fs::create_dir_all(&root).await.unwrap();
        let config = RuntimeConfig::workspace_write(&root, &root);

        let result = execute(
            &config,
            "call-1",
            json!({ "pattern": "needle", "limit": 1001 }),
            std::time::Instant::now(),
        )
        .await;

        assert!(!result.ok);
        assert_eq!(result.error.unwrap().code, "invalid_arguments");
        remove_test_dir(root).await;
    }

    #[tokio::test]
    async fn fallback_search_truncates_long_match_text() {
        let root = unique_test_dir("search-long-text");
        tokio::fs::create_dir_all(&root).await.unwrap();
        let long_line = format!("needle{}尾", "a".repeat(5000));
        tokio::fs::write(root.join("long.txt"), format!("{long_line}\n"))
            .await
            .unwrap();

        let (matches, truncated) = fallback_search(&root, Path::new(""), "needle", 10, &[])
            .await
            .unwrap();

        assert!(!truncated);
        assert_eq!(matches.len(), 1);
        assert!(matches[0].text.len() <= 4096);
        assert!(matches[0].text.starts_with("needle"));
        assert!(matches[0].text.is_char_boundary(matches[0].text.len()));
        remove_test_dir(root).await;
    }

    fn unique_test_dir(name: &str) -> PathBuf {
        std::env::temp_dir().join(format!("agentweave-{name}-{}", uuid::Uuid::new_v4()))
    }

    async fn remove_test_dir(path: PathBuf) {
        if path.exists() {
            tokio::fs::remove_dir_all(path).await.unwrap();
        }
    }
}
