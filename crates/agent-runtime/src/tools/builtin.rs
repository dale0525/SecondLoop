use super::{
    CommandMode, RuntimeConfig, ToolDefinition, ToolPermission, ToolPersistence, ToolSource,
    command, patch, path, permission_allowed,
    result::{ToolError, ToolResult, ToolResultMetadata},
    search,
};
use serde_json::{Value, json};
use std::io::ErrorKind;
use std::time::Instant;

pub const CREATE_DIRECTORY: &str = "create_directory";
pub const LIST_DIRECTORY: &str = "list_directory";
pub const FILE_METADATA: &str = "file_metadata";
pub const READ_TEXT_FILE: &str = "read_text_file";
pub const WRITE_TEXT_FILE: &str = "write_text_file";

#[derive(Debug, Clone)]
pub struct BuiltInTools {
    config: RuntimeConfig,
}

impl BuiltInTools {
    pub fn new(config: RuntimeConfig) -> Self {
        Self { config }
    }

    pub fn definitions(&self) -> Vec<ToolDefinition> {
        definitions(self.config.mode, self.config.effective_command_mode())
    }

    pub fn handles(name: &str) -> bool {
        matches!(
            name,
            CREATE_DIRECTORY
                | LIST_DIRECTORY
                | FILE_METADATA
                | READ_TEXT_FILE
                | WRITE_TEXT_FILE
                | search::SEARCH_FILES
                | command::EXEC_COMMAND
                | patch::APPLY_PATCH
        )
    }

    pub async fn execute(&self, name: &str, call_id: &str, arguments: Value) -> ToolResult {
        let started = Instant::now();

        if name == command::EXEC_COMMAND
            && (self.config.command_mode == CommandMode::Disabled
                || !self.config.excluded_workspace_roots.is_empty())
        {
            return command::execute(&self.config, call_id, arguments, started).await;
        }

        if name == command::EXEC_COMMAND
            && !permission_allowed(
                self.config.mode,
                self.config.command_mode,
                ToolPermission::ExecuteCommand,
            )
        {
            return failure(
                name,
                call_id,
                "permission_denied",
                "tool is not allowed in the current runtime mode",
                false,
                started,
            );
        }

        let Some(definition) = self
            .definitions()
            .into_iter()
            .find(|tool| tool.name == name)
        else {
            return failure(
                name,
                call_id,
                "unknown_tool",
                "unknown built-in tool",
                false,
                started,
            );
        };

        if !permission_allowed(
            self.config.mode,
            self.config.command_mode,
            definition.permission,
        ) {
            return failure(
                name,
                call_id,
                "permission_denied",
                "tool is not allowed in the current runtime mode",
                false,
                started,
            );
        }

        let result = match name {
            CREATE_DIRECTORY => self.create_directory(call_id, arguments, started).await,
            LIST_DIRECTORY => self.list_directory(call_id, arguments, started).await,
            FILE_METADATA => self.file_metadata(call_id, arguments, started).await,
            READ_TEXT_FILE => self.read_text_file(call_id, arguments, started).await,
            WRITE_TEXT_FILE => self.write_text_file(call_id, arguments, started).await,
            search::SEARCH_FILES => {
                Ok(search::execute(&self.config, call_id, arguments, started).await)
            }
            command::EXEC_COMMAND => {
                Ok(command::execute(&self.config, call_id, arguments, started).await)
            }
            patch::APPLY_PATCH => {
                Ok(patch::execute(&self.config, call_id, arguments, started).await)
            }
            _ => Ok(failure(
                name,
                call_id,
                "unknown_tool",
                "unknown built-in tool",
                false,
                started,
            )),
        };

        match result {
            Ok(result) => result,
            Err(error) => mapped_failure(name, call_id, error, started),
        }
    }

    async fn create_directory(
        &self,
        call_id: &str,
        arguments: Value,
        started: Instant,
    ) -> anyhow::Result<ToolResult> {
        let requested = required_string(&arguments, "path")?;
        let workspace_path = path::resolve_workspace_output_path_with_exclusions(
            &self.config.workspace_root,
            requested,
            &self.config.excluded_workspace_roots,
        )?;
        let existed = workspace_path.absolute.is_dir();
        tokio::fs::create_dir_all(&workspace_path.absolute).await?;

        Ok(ToolResult::success(
            CREATE_DIRECTORY,
            call_id,
            json!({
                "path": relative_path(&workspace_path.relative),
                "created": !existed
            }),
            metadata(started),
        ))
    }

    async fn list_directory(
        &self,
        call_id: &str,
        arguments: Value,
        started: Instant,
    ) -> anyhow::Result<ToolResult> {
        let requested = required_string(&arguments, "path")?;
        let limit = optional_limit(&arguments)?;
        let workspace_path = path::resolve_existing_workspace_path_with_exclusions(
            &self.config.workspace_root,
            requested,
            &self.config.excluded_workspace_roots,
        )?;
        let excluded = path::canonical_excluded_roots(
            &self.config.workspace_root,
            &self.config.excluded_workspace_roots,
        )?;
        let mut read_dir = tokio::fs::read_dir(&workspace_path.absolute).await?;
        let mut entries = Vec::new();

        while let Some(entry) = read_dir.next_entry().await? {
            let entry_path = match tokio::fs::canonicalize(entry.path()).await {
                Ok(path) => path,
                Err(_) => entry.path(),
            };
            if path::path_is_excluded(&entry_path, &excluded) {
                continue;
            }
            let metadata = tokio::fs::symlink_metadata(entry.path()).await?;
            let name = entry.file_name().to_string_lossy().to_string();
            let entry_relative = workspace_path.relative.join(&name);
            entries.push(json!({
                "name": name,
                "path": relative_path(&entry_relative),
                "type": metadata_type(&metadata),
                "size": metadata.len()
            }));
        }

        entries.sort_by(|left, right| {
            left["path"]
                .as_str()
                .unwrap_or_default()
                .cmp(right["path"].as_str().unwrap_or_default())
        });
        let truncated = entries.len() > limit;
        entries.truncate(limit);

        Ok(ToolResult::success(
            LIST_DIRECTORY,
            call_id,
            json!({
                "path": relative_path(&workspace_path.relative),
                "entries": entries,
                "truncated": truncated
            }),
            metadata(started),
        ))
    }

    async fn file_metadata(
        &self,
        call_id: &str,
        arguments: Value,
        started: Instant,
    ) -> anyhow::Result<ToolResult> {
        let requested = required_string(&arguments, "path")?;
        let workspace_path = path::resolve_workspace_path_with_exclusions(
            &self.config.workspace_root,
            requested,
            &self.config.excluded_workspace_roots,
        )?;
        let file_metadata = match tokio::fs::symlink_metadata(&workspace_path.absolute).await {
            Ok(metadata) => metadata,
            Err(error) if error.kind() == ErrorKind::NotFound => {
                return Ok(ToolResult::success(
                    FILE_METADATA,
                    call_id,
                    json!({
                        "path": relative_path(&workspace_path.relative),
                        "exists": false
                    }),
                    metadata(started),
                ));
            }
            Err(error) => return Err(error.into()),
        };
        path::ensure_existing_path_inside_workspace_with_exclusions(
            &self.config.workspace_root,
            &workspace_path.absolute,
            &self.config.excluded_workspace_roots,
        )?;

        Ok(ToolResult::success(
            FILE_METADATA,
            call_id,
            json!({
                "path": relative_path(&workspace_path.relative),
                "exists": true,
                "type": metadata_type(&file_metadata),
                "size": file_metadata.len()
            }),
            metadata(started),
        ))
    }

    async fn read_text_file(
        &self,
        call_id: &str,
        arguments: Value,
        started: Instant,
    ) -> anyhow::Result<ToolResult> {
        let requested = required_string(&arguments, "path")?;
        let workspace_path = path::resolve_existing_workspace_path_with_exclusions(
            &self.config.workspace_root,
            requested,
            &self.config.excluded_workspace_roots,
        )?;
        let file_metadata = tokio::fs::metadata(&workspace_path.absolute).await?;
        if file_metadata.len() > self.config.output_limit_bytes as u64 {
            return Ok(output_limit_failure(READ_TEXT_FILE, call_id, started));
        }
        let bytes = tokio::fs::read(&workspace_path.absolute).await?;
        let text = String::from_utf8(bytes)
            .map_err(|_| anyhow::anyhow!("workspace path is not valid UTF-8 text"))?;

        Ok(ToolResult::success(
            READ_TEXT_FILE,
            call_id,
            json!({
                "path": relative_path(&workspace_path.relative),
                "text": text
            }),
            metadata(started),
        ))
    }

    async fn write_text_file(
        &self,
        call_id: &str,
        arguments: Value,
        started: Instant,
    ) -> anyhow::Result<ToolResult> {
        let requested = required_string(&arguments, "path")?;
        let text = required_string(&arguments, "text")?;
        let overwrite = optional_bool(&arguments, "overwrite")?;
        let workspace_path = path::resolve_workspace_output_path_with_exclusions(
            &self.config.workspace_root,
            requested,
            &self.config.excluded_workspace_roots,
        )?;

        if workspace_path.absolute.exists() && !overwrite {
            return Ok(failure(
                WRITE_TEXT_FILE,
                call_id,
                "path_exists",
                "refusing to overwrite existing path without overwrite=true",
                false,
                started,
            ));
        }
        if let Some(parent) = workspace_path.absolute.parent() {
            tokio::fs::create_dir_all(parent).await?;
        }
        tokio::fs::write(&workspace_path.absolute, text).await?;

        Ok(ToolResult::success(
            WRITE_TEXT_FILE,
            call_id,
            json!({
                "path": relative_path(&workspace_path.relative),
                "bytes": text.len()
            }),
            metadata(started),
        ))
    }
}

fn definitions(mode: super::RuntimeMode, command_mode: CommandMode) -> Vec<ToolDefinition> {
    let mut definitions = vec![
        tool_definition(
            CREATE_DIRECTORY,
            "Create a directory inside the workspace.",
            ToolPermission::WriteWorkspace,
            json!({
                "type": "object",
                "properties": { "path": { "type": "string" } },
                "required": ["path"],
                "additionalProperties": false
            }),
        ),
        tool_definition(
            LIST_DIRECTORY,
            "List entries in a workspace directory.",
            ToolPermission::ReadWorkspace,
            json!({
                "type": "object",
                "properties": {
                    "path": { "type": "string" },
                    "limit": { "type": "integer", "minimum": 1 }
                },
                "required": ["path"],
                "additionalProperties": false
            }),
        ),
        tool_definition(
            FILE_METADATA,
            "Return metadata for a workspace path.",
            ToolPermission::ReadWorkspace,
            json!({
                "type": "object",
                "properties": { "path": { "type": "string" } },
                "required": ["path"],
                "additionalProperties": false
            }),
        ),
        tool_definition(
            READ_TEXT_FILE,
            "Read a UTF-8 text file inside the workspace.",
            ToolPermission::ReadWorkspace,
            json!({
                "type": "object",
                "properties": { "path": { "type": "string" } },
                "required": ["path"],
                "additionalProperties": false
            }),
        ),
        tool_definition(
            WRITE_TEXT_FILE,
            "Write a UTF-8 text file inside the workspace.",
            ToolPermission::WriteWorkspace,
            json!({
                "type": "object",
                "properties": {
                    "path": { "type": "string" },
                    "text": { "type": "string" },
                    "overwrite": { "type": "boolean" }
                },
                "required": ["path", "text"],
                "additionalProperties": false
            }),
        ),
        search::definition(),
        patch::definition(),
    ];

    if permission_allowed(mode, command_mode, ToolPermission::ExecuteCommand) {
        definitions.push(command::definition());
    }

    definitions
}

fn tool_definition(
    name: &str,
    description: &str,
    permission: ToolPermission,
    input_schema: Value,
) -> ToolDefinition {
    ToolDefinition {
        name: name.to_string(),
        namespace: None,
        description: description.to_string(),
        input_schema,
        output_schema: None,
        permission,
        persistence: ToolPersistence::for_permission(permission),
        source: ToolSource::BuiltIn,
    }
}

fn required_string<'a>(arguments: &'a Value, name: &str) -> anyhow::Result<&'a str> {
    arguments
        .get(name)
        .and_then(Value::as_str)
        .filter(|value| !value.is_empty())
        .ok_or_else(|| anyhow::anyhow!("invalid arguments: missing string field {name}"))
}

fn optional_bool(arguments: &Value, name: &str) -> anyhow::Result<bool> {
    match arguments.get(name) {
        Some(value) => value
            .as_bool()
            .ok_or_else(|| anyhow::anyhow!("invalid arguments: field {name} must be boolean")),
        None => Ok(false),
    }
}

fn optional_limit(arguments: &Value) -> anyhow::Result<usize> {
    match arguments.get("limit") {
        Some(value) => {
            let limit = value.as_u64().ok_or_else(|| {
                anyhow::anyhow!("invalid arguments: limit must be a positive integer")
            })?;
            if limit == 0 {
                anyhow::bail!("invalid arguments: limit must be a positive integer");
            }
            Ok(limit as usize)
        }
        None => Ok(200),
    }
}

fn metadata(started: Instant) -> ToolResultMetadata {
    ToolResultMetadata {
        duration_ms: started.elapsed().as_millis() as u64,
        ..ToolResultMetadata::default()
    }
}

fn failure(
    tool: &str,
    call_id: &str,
    code: &str,
    message: impl Into<String>,
    retryable: bool,
    started: Instant,
) -> ToolResult {
    ToolResult::failure(
        tool,
        call_id,
        ToolError {
            code: code.to_string(),
            message: message.into(),
            retryable,
        },
        metadata(started),
    )
}

fn output_limit_failure(tool: &str, call_id: &str, started: Instant) -> ToolResult {
    let mut metadata = metadata(started);
    metadata.output_truncated = true;
    ToolResult::failure(
        tool,
        call_id,
        ToolError {
            code: "output_limit_exceeded".to_string(),
            message: "tool output exceeded runtime output limit".to_string(),
            retryable: false,
        },
        metadata,
    )
}

fn mapped_failure(tool: &str, call_id: &str, error: anyhow::Error, started: Instant) -> ToolResult {
    let message = error.to_string();
    let code = error_code(&message);
    failure(tool, call_id, code, message, false, started)
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
    } else if message.contains("invalid arguments") {
        "invalid_arguments"
    } else if message.contains("not valid UTF-8 text") {
        "path_not_text"
    } else if message.contains("No such file or directory")
        || message.contains("entity not found")
        || message.contains("failed to resolve workspace path")
    {
        "path_not_found"
    } else if message.contains("Permission denied") {
        "permission_denied"
    } else {
        "internal_error"
    }
}

fn metadata_type(metadata: &std::fs::Metadata) -> &'static str {
    if metadata.file_type().is_symlink() {
        "symlink"
    } else if metadata.is_dir() {
        "directory"
    } else if metadata.is_file() {
        "file"
    } else {
        "other"
    }
}

fn relative_path(path: &std::path::Path) -> String {
    let value = path.to_string_lossy().to_string();
    if value.is_empty() {
        ".".to_string()
    } else {
        value
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::tools::{CommandMode, RuntimeConfig};
    use serde_json::json;
    use std::path::PathBuf;

    #[tokio::test]
    async fn create_directory_creates_workspace_directory() {
        let root = unique_test_dir("create-directory");
        std::fs::create_dir_all(&root).unwrap();
        let tools = BuiltInTools::new(RuntimeConfig::workspace_write(&root, &root));

        let result = tools
            .execute(
                "create_directory",
                "call-1",
                json!({ "path": "src/generated" }),
            )
            .await;

        assert!(result.ok);
        assert!(root.join("src").join("generated").is_dir());
        assert_eq!(result.data.unwrap()["path"], "src/generated");
        remove_test_dir(root);
    }

    #[tokio::test]
    async fn definitions_include_exec_command_only_when_command_mode_allowed() {
        let root = unique_test_dir("command-definitions");
        std::fs::create_dir_all(&root).unwrap();

        let disabled_tools = BuiltInTools::new(RuntimeConfig::workspace_write(&root, &root));
        assert!(
            !disabled_tools
                .definitions()
                .iter()
                .any(|tool| tool.name == "exec_command")
        );

        let allowed_tools = BuiltInTools::new(
            RuntimeConfig::workspace_write(&root, &root).with_command_mode(CommandMode::Allowed),
        );
        assert!(
            allowed_tools
                .definitions()
                .iter()
                .any(|tool| tool.name == "exec_command")
        );

        remove_test_dir(root);
    }

    #[tokio::test]
    async fn definitions_exclude_exec_command_when_read_only_even_if_command_mode_allowed() {
        let root = unique_test_dir("command-definitions-read-only");
        std::fs::create_dir_all(&root).unwrap();

        let tools = BuiltInTools::new(
            RuntimeConfig::read_only(&root, &root).with_command_mode(CommandMode::Allowed),
        );

        assert!(
            !tools
                .definitions()
                .iter()
                .any(|tool| tool.name == "exec_command")
        );

        remove_test_dir(root);
    }

    #[tokio::test]
    async fn disabled_exec_command_returns_structured_failure_if_forced() {
        let root = unique_test_dir("command-disabled-forced");
        std::fs::create_dir_all(&root).unwrap();
        let tools = BuiltInTools::new(RuntimeConfig::workspace_write(&root, &root));

        let result = tools
            .execute("exec_command", "call-1", json!({ "cmd": "printf hello" }))
            .await;

        assert!(!result.ok);
        assert_eq!(result.error.unwrap().code, "command_disabled");
        remove_test_dir(root);
    }

    #[tokio::test]
    async fn read_only_allowed_exec_command_returns_permission_failure_if_forced() {
        let root = unique_test_dir("command-read-only-forced");
        std::fs::create_dir_all(&root).unwrap();
        let tools = BuiltInTools::new(
            RuntimeConfig::read_only(&root, &root).with_command_mode(CommandMode::Allowed),
        );

        let result = tools
            .execute("exec_command", "call-1", json!({ "cmd": "printf hello" }))
            .await;

        assert!(!result.ok);
        assert_eq!(result.error.unwrap().code, "permission_denied");
        remove_test_dir(root);
    }

    #[tokio::test]
    async fn search_files_dispatch_returns_matches() {
        let root = unique_test_dir("search-dispatch");
        std::fs::create_dir_all(&root).unwrap();
        std::fs::write(root.join("notes.txt"), "alpha\nneedle\n").unwrap();
        let tools = BuiltInTools::new(RuntimeConfig::workspace_write(&root, &root));

        let result = tools
            .execute("search_files", "call-1", json!({ "pattern": "needle" }))
            .await;

        assert!(result.ok);
        let data = result.data.unwrap();
        assert_eq!(data["matches"].as_array().unwrap().len(), 1);
        assert_eq!(data["matches"][0]["path"], "notes.txt");
        remove_test_dir(root);
    }

    #[tokio::test]
    async fn apply_patch_dispatch_adds_file() {
        let root = unique_test_dir("patch-dispatch");
        std::fs::create_dir_all(&root).unwrap();
        let tools = BuiltInTools::new(RuntimeConfig::workspace_write(&root, &root));

        let result = tools
            .execute(
                "apply_patch",
                "call-1",
                json!({
                    "patch": "*** Begin Patch\n*** Add File: notes/hello.txt\n+hello\n*** End Patch\n"
                }),
            )
            .await;

        assert!(result.ok);
        assert_eq!(
            std::fs::read_to_string(root.join("notes").join("hello.txt")).unwrap(),
            "hello\n"
        );
        assert_eq!(
            result.data.unwrap()["changed_files"][0]["path"],
            "notes/hello.txt"
        );
        remove_test_dir(root);
    }

    #[tokio::test]
    async fn read_only_mode_blocks_create_directory() {
        let root = unique_test_dir("read-only-create-directory");
        std::fs::create_dir_all(&root).unwrap();
        let tools = BuiltInTools::new(RuntimeConfig::read_only(&root, &root));

        let result = tools
            .execute("create_directory", "call-1", json!({ "path": "src" }))
            .await;

        assert!(!result.ok);
        assert_eq!(result.error.unwrap().code, "permission_denied");
        assert!(!root.join("src").exists());
        remove_test_dir(root);
    }

    #[tokio::test]
    async fn write_and_read_text_file_round_trip() {
        let root = unique_test_dir("write-read-round-trip");
        std::fs::create_dir_all(&root).unwrap();
        let tools = BuiltInTools::new(RuntimeConfig::workspace_write(&root, &root));

        let write_result = tools
            .execute(
                "write_text_file",
                "call-write",
                json!({ "path": "notes/hello.txt", "text": "hello" }),
            )
            .await;
        let read_result = tools
            .execute(
                "read_text_file",
                "call-read",
                json!({ "path": "notes/hello.txt" }),
            )
            .await;

        assert!(write_result.ok);
        assert!(read_result.ok);
        assert_eq!(read_result.data.unwrap()["text"], "hello");
        remove_test_dir(root);
    }

    #[tokio::test]
    async fn list_directory_returns_deterministic_entries() {
        let root = unique_test_dir("list-directory");
        std::fs::create_dir_all(root.join("dir")).unwrap();
        std::fs::write(root.join("dir").join("b.txt"), "b").unwrap();
        std::fs::create_dir_all(root.join("dir").join("a")).unwrap();
        std::fs::write(root.join("dir").join("a.txt"), "a").unwrap();
        let tools = BuiltInTools::new(RuntimeConfig::workspace_write(&root, &root));

        let result = tools
            .execute("list_directory", "call-1", json!({ "path": "dir" }))
            .await;

        assert!(result.ok);
        let data = result.data.unwrap();
        let paths: Vec<_> = data["entries"]
            .as_array()
            .unwrap()
            .iter()
            .map(|entry| entry["path"].as_str().unwrap().to_string())
            .collect();
        assert_eq!(paths, vec!["dir/a", "dir/a.txt", "dir/b.txt"]);
        remove_test_dir(root);
    }

    #[tokio::test]
    async fn file_metadata_reports_missing_path() {
        let root = unique_test_dir("metadata-missing");
        std::fs::create_dir_all(&root).unwrap();
        let tools = BuiltInTools::new(RuntimeConfig::workspace_write(&root, &root));

        let result = tools
            .execute("file_metadata", "call-1", json!({ "path": "missing.txt" }))
            .await;

        assert!(result.ok);
        let data = result.data.unwrap();
        assert_eq!(data["exists"], false);
        assert_eq!(data["path"], "missing.txt");
        remove_test_dir(root);
    }

    #[tokio::test]
    async fn list_directory_applies_entry_limit() {
        let root = unique_test_dir("list-limit");
        std::fs::create_dir_all(root.join("dir")).unwrap();
        for name in ["a.txt", "b.txt", "c.txt"] {
            std::fs::write(root.join("dir").join(name), name).unwrap();
        }
        let tools = BuiltInTools::new(RuntimeConfig::workspace_write(&root, &root));

        let result = tools
            .execute(
                "list_directory",
                "call-1",
                json!({ "path": "dir", "limit": 2 }),
            )
            .await;

        assert!(result.ok);
        let data = result.data.unwrap();
        assert_eq!(data["entries"].as_array().unwrap().len(), 2);
        assert_eq!(data["truncated"], true);
        remove_test_dir(root);
    }

    #[tokio::test]
    async fn path_escape_returns_structured_failure() {
        let root = unique_test_dir("path-escape");
        std::fs::create_dir_all(&root).unwrap();
        let tools = BuiltInTools::new(RuntimeConfig::workspace_write(&root, &root));

        let result = tools
            .execute(
                "read_text_file",
                "call-1",
                json!({ "path": "../secret.txt" }),
            )
            .await;

        assert!(!result.ok);
        assert_eq!(result.error.unwrap().code, "path_outside_workspace");
        remove_test_dir(root);
    }

    #[tokio::test]
    async fn missing_read_returns_structured_failure() {
        let root = unique_test_dir("missing-read");
        std::fs::create_dir_all(&root).unwrap();
        let tools = BuiltInTools::new(RuntimeConfig::workspace_write(&root, &root));

        let result = tools
            .execute("read_text_file", "call-1", json!({ "path": "missing.txt" }))
            .await;

        assert!(!result.ok);
        assert_eq!(result.error.unwrap().code, "path_not_found");
        remove_test_dir(root);
    }

    #[tokio::test]
    async fn invalid_arguments_return_structured_failure() {
        let root = unique_test_dir("invalid-arguments");
        std::fs::create_dir_all(&root).unwrap();
        let tools = BuiltInTools::new(RuntimeConfig::workspace_write(&root, &root));

        let result = tools
            .execute("read_text_file", "call-1", json!({ "path": 42 }))
            .await;

        assert!(!result.ok);
        assert_eq!(result.error.unwrap().code, "invalid_arguments");
        remove_test_dir(root);
    }

    #[cfg(unix)]
    #[tokio::test]
    async fn reading_symlink_to_outside_workspace_returns_structured_failure() {
        let root = unique_test_dir("read-symlink-outside-root");
        let outside = unique_test_dir("read-symlink-outside-target");
        std::fs::create_dir_all(&root).unwrap();
        std::fs::create_dir_all(&outside).unwrap();
        std::fs::write(outside.join("secret.txt"), "secret").unwrap();
        std::os::unix::fs::symlink(outside.join("secret.txt"), root.join("link.txt")).unwrap();
        let tools = BuiltInTools::new(RuntimeConfig::workspace_write(&root, &root));

        let result = tools
            .execute("read_text_file", "call-1", json!({ "path": "link.txt" }))
            .await;

        assert!(!result.ok);
        assert_eq!(result.error.unwrap().code, "path_outside_workspace");
        remove_test_dir(root);
        remove_test_dir(outside);
    }

    #[cfg(unix)]
    #[tokio::test]
    async fn write_text_file_rejects_symlink_parent_escape() {
        let root = unique_test_dir("write-symlink-root");
        let outside = unique_test_dir("write-symlink-outside");
        std::fs::create_dir_all(&root).unwrap();
        std::fs::create_dir_all(&outside).unwrap();
        std::os::unix::fs::symlink(&outside, root.join("link")).unwrap();
        let tools = BuiltInTools::new(RuntimeConfig::workspace_write(&root, &root));

        let result = tools
            .execute(
                "write_text_file",
                "call-1",
                json!({ "path": "link/new.txt", "text": "nope" }),
            )
            .await;

        assert!(!result.ok);
        assert_eq!(result.error.unwrap().code, "path_outside_workspace");
        assert!(!outside.join("new.txt").exists());
        remove_test_dir(root);
        remove_test_dir(outside);
    }

    #[cfg(unix)]
    #[tokio::test]
    async fn create_directory_rejects_symlink_parent_escape() {
        let root = unique_test_dir("mkdir-symlink-root");
        let outside = unique_test_dir("mkdir-symlink-outside");
        std::fs::create_dir_all(&root).unwrap();
        std::fs::create_dir_all(&outside).unwrap();
        std::os::unix::fs::symlink(&outside, root.join("link")).unwrap();
        let tools = BuiltInTools::new(RuntimeConfig::workspace_write(&root, &root));

        let result = tools
            .execute(
                "create_directory",
                "call-1",
                json!({ "path": "link/new-dir" }),
            )
            .await;

        assert!(!result.ok);
        assert_eq!(result.error.unwrap().code, "path_outside_workspace");
        assert!(!outside.join("new-dir").exists());
        remove_test_dir(root);
        remove_test_dir(outside);
    }

    #[tokio::test]
    async fn read_text_file_reports_non_utf8_as_path_not_text() {
        let root = unique_test_dir("non-utf8");
        std::fs::create_dir_all(&root).unwrap();
        std::fs::write(root.join("binary.bin"), [0xff, 0xfe, 0xfd]).unwrap();
        let tools = BuiltInTools::new(RuntimeConfig::workspace_write(&root, &root));

        let result = tools
            .execute("read_text_file", "call-1", json!({ "path": "binary.bin" }))
            .await;

        assert!(!result.ok);
        assert_eq!(result.error.unwrap().code, "path_not_text");
        remove_test_dir(root);
    }

    #[tokio::test]
    async fn read_text_file_rejects_file_larger_than_output_limit_before_reading() {
        let root = unique_test_dir("read-output-limit");
        std::fs::create_dir_all(&root).unwrap();
        std::fs::write(root.join("big.txt"), "abcdef").unwrap();
        let mut config = RuntimeConfig::workspace_write(&root, &root);
        config.output_limit_bytes = 4;
        let tools = BuiltInTools::new(config);

        let result = tools
            .execute("read_text_file", "call-1", json!({ "path": "big.txt" }))
            .await;

        assert!(!result.ok);
        assert_eq!(result.error.unwrap().code, "output_limit_exceeded");
        assert!(result.metadata.output_truncated);
        remove_test_dir(root);
    }

    fn unique_test_dir(name: &str) -> PathBuf {
        std::env::temp_dir().join(format!("agentweave-{name}-{}", uuid::Uuid::new_v4()))
    }

    fn remove_test_dir(path: PathBuf) {
        if path.exists() {
            std::fs::remove_dir_all(path).unwrap();
        }
    }
}
