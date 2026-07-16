use super::{
    CommandMode, RuntimeConfig, RuntimeMode, ToolDefinition, ToolPermission, ToolPersistence,
    ToolSource, path,
    process::read_limited_child_output,
    result::{ToolError, ToolResult, ToolResultMetadata},
};
use serde_json::{Value, json};
use std::{ffi::OsStr, process::Stdio, time::Instant};
use tokio::process::Command;

pub const EXEC_COMMAND: &str = "exec_command";
const COMMAND_RESULT_ENVELOPE_RESERVE_BYTES: usize = 512;

pub fn definition() -> ToolDefinition {
    ToolDefinition {
        name: EXEC_COMMAND.to_string(),
        namespace: None,
        description: "Execute a development command inside the workspace.".to_string(),
        input_schema: json!({
            "type": "object",
            "properties": {
                "cmd": { "type": "string" },
                "cwd": { "type": "string" },
                "timeout_ms": { "type": "integer", "minimum": 1 }
            },
            "required": ["cmd"],
            "additionalProperties": false
        }),
        output_schema: None,
        permission: ToolPermission::ExecuteCommand,
        persistence: ToolPersistence::Full,
        source: ToolSource::BuiltIn,
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::tools::{CommandMode, RuntimeConfig};
    use serde_json::json;
    use std::path::{Path, PathBuf};

    #[tokio::test]
    async fn exec_command_runs_simple_command_inside_workspace() {
        let root = unique_test_dir("command-simple");
        std::fs::create_dir_all(&root).unwrap();
        let config = allowed_config(&root);

        let result = execute(
            &config,
            "call-1",
            json!({ "cmd": "printf hello", "cwd": "." }),
            Instant::now(),
        )
        .await;

        assert!(result.ok);
        let data = result.data.unwrap();
        assert_eq!(data["cmd"], "printf hello");
        assert_eq!(data["cwd"], ".");
        assert_eq!(data["exit_code"], 0);
        assert_eq!(data["stdout"], "hello");
        assert_eq!(data["stderr"], "");
        assert_eq!(data["timed_out"], false);
        assert_eq!(data["terminated_by_runtime"], false);
        remove_test_dir(root);
    }

    #[tokio::test]
    async fn exec_command_reports_non_zero_exit_code() {
        let root = unique_test_dir("command-non-zero");
        std::fs::create_dir_all(&root).unwrap();
        let config = allowed_config(&root);

        let result = execute(
            &config,
            "call-1",
            json!({ "cmd": "printf nope >&2; exit 7" }),
            Instant::now(),
        )
        .await;

        assert!(result.ok);
        let data = result.data.unwrap();
        assert_eq!(data["exit_code"], 7);
        assert_eq!(data["stdout"], "");
        assert_eq!(data["stderr"], "nope");
        remove_test_dir(root);
    }

    #[tokio::test]
    async fn exec_command_rejects_command_when_disabled() {
        let root = unique_test_dir("command-disabled");
        std::fs::create_dir_all(&root).unwrap();
        let config = RuntimeConfig::workspace_write(&root, &root);

        let result = execute(
            &config,
            "call-1",
            json!({ "cmd": "printf hello" }),
            Instant::now(),
        )
        .await;

        assert!(!result.ok);
        assert_eq!(result.error.unwrap().code, "command_disabled");
        remove_test_dir(root);
    }

    #[tokio::test]
    async fn exec_command_rejects_read_only_even_when_allowed() {
        let root = unique_test_dir("command-read-only");
        std::fs::create_dir_all(&root).unwrap();
        let config = RuntimeConfig::read_only(&root, &root).with_command_mode(CommandMode::Allowed);

        let result = execute(
            &config,
            "call-1",
            json!({ "cmd": "printf hello" }),
            Instant::now(),
        )
        .await;

        assert!(!result.ok);
        assert_eq!(result.error.unwrap().code, "permission_denied");
        remove_test_dir(root);
    }

    #[tokio::test]
    async fn exec_command_rejects_workspace_escape_cwd() {
        let root = unique_test_dir("command-cwd-root");
        let outside = unique_test_dir("command-cwd-outside");
        std::fs::create_dir_all(&root).unwrap();
        std::fs::create_dir_all(&outside).unwrap();
        let config = allowed_config(&root);

        let result = execute(
            &config,
            "call-1",
            json!({ "cmd": "printf hello", "cwd": outside }),
            Instant::now(),
        )
        .await;

        assert!(!result.ok);
        assert_eq!(result.error.unwrap().code, "path_outside_workspace");
        remove_test_dir(root);
        remove_test_dir(outside);
    }

    #[tokio::test]
    async fn exec_command_blocks_denylisted_command_forms() {
        let root = unique_test_dir("command-denylist");
        std::fs::create_dir_all(&root).unwrap();
        let config = allowed_config(&root);

        for cmd in [
            "git reset --hard",
            "git clean -fd",
            "rm -rf /",
            "rm -rf .",
            "sudo true",
            "shutdown now",
            "reboot",
            "mkfs.ext4 /dev/disk",
        ] {
            let result = execute(&config, "call-1", json!({ "cmd": cmd }), Instant::now()).await;

            assert!(!result.ok, "{cmd} should be denied");
            assert_eq!(result.error.unwrap().code, "command_denied");
        }
        remove_test_dir(root);
    }

    #[tokio::test]
    async fn denylist_blocks_chained_and_variant_destructive_commands() {
        let root = unique_test_dir("command-denylist-variants");
        std::fs::create_dir_all(&root).unwrap();
        let config = allowed_config(&root);

        for cmd in [
            "true; sudo true",
            "true && reboot",
            "cd tmp && mkfs.ext4 disk",
            "rm -fr /",
            "rm -rf -- /",
            "git clean -fdx",
            "git clean -df",
            "git clean -xfd",
            "(sudo true)",
            "sh -c 'sudo true'",
            "echo $(sudo true)",
            "echo `sudo true`",
            "git -C . reset --hard",
            "git -C . clean -xdf",
            "/usr/bin/git reset --hard",
            "/usr/bin/git -C . clean -xdf",
            "/usr/bin/sudo true",
            "/bin/bash -c 'sudo true'",
            "/sbin/mkfs.ext4 /dev/disk",
            "/bin/rm -rf /",
        ] {
            let result = execute(&config, "call-1", json!({ "cmd": cmd }), Instant::now()).await;

            assert!(!result.ok, "{cmd} should be denied");
            assert_eq!(result.error.unwrap().code, "command_denied");
        }
        remove_test_dir(root);
    }

    #[tokio::test]
    async fn exec_command_rejects_unknown_arguments() {
        let root = unique_test_dir("command-unknown-args");
        std::fs::create_dir_all(&root).unwrap();
        let config = allowed_config(&root);

        let result = execute(
            &config,
            "call-1",
            json!({ "cmd": "printf hello", "unexpected": true }),
            Instant::now(),
        )
        .await;

        assert!(!result.ok);
        assert_eq!(result.error.unwrap().code, "invalid_arguments");
        remove_test_dir(root);
    }

    #[tokio::test]
    async fn explicit_timeout_above_internal_max_returns_invalid_arguments() {
        let root = unique_test_dir("command-timeout-max");
        std::fs::create_dir_all(&root).unwrap();
        let mut config = allowed_config(&root);
        config.tool_timeout_ms = 200;

        let result = execute(
            &config,
            "call-1",
            json!({ "cmd": "printf hello", "timeout_ms": 101 }),
            Instant::now(),
        )
        .await;

        assert!(!result.ok);
        assert_eq!(result.error.unwrap().code, "invalid_arguments");
        remove_test_dir(root);
    }

    #[tokio::test]
    async fn exec_command_times_out_and_stops_child() {
        let root = unique_test_dir("command-timeout");
        std::fs::create_dir_all(&root).unwrap();
        let mut config = allowed_config(&root);
        config.tool_timeout_ms = 200;

        let result = execute(
            &config,
            "call-1",
            json!({
                "cmd": "sleep 1; printf late > late.txt",
                "timeout_ms": 25
            }),
            Instant::now(),
        )
        .await;

        assert!(!result.ok);
        let error = result.error.unwrap();
        assert_eq!(error.code, "timeout");
        assert!(error.retryable);
        tokio::time::sleep(std::time::Duration::from_millis(100)).await;
        assert!(!root.join("late.txt").exists());
        remove_test_dir(root);
    }

    #[cfg(unix)]
    #[tokio::test]
    async fn exec_command_timeout_stops_background_process_group() {
        let root = unique_test_dir("command-timeout-process-group");
        std::fs::create_dir_all(&root).unwrap();
        let mut config = allowed_config(&root);
        config.tool_timeout_ms = 500;

        let result = execute(
            &config,
            "call-1",
            json!({
                "cmd": "(sleep 0.5; printf late > late.txt) & sleep 1",
                "timeout_ms": 75
            }),
            Instant::now(),
        )
        .await;

        assert!(!result.ok);
        assert_eq!(result.error.unwrap().code, "timeout");
        tokio::time::sleep(std::time::Duration::from_millis(650)).await;
        assert!(!root.join("late.txt").exists());
        remove_test_dir(root);
    }

    #[tokio::test]
    async fn exec_command_truncates_large_stdout() {
        let root = unique_test_dir("command-truncate");
        std::fs::create_dir_all(&root).unwrap();
        let mut config = allowed_config(&root);
        config.output_limit_bytes = 4;

        let result = execute(
            &config,
            "call-1",
            json!({ "cmd": "printf abcdef" }),
            Instant::now(),
        )
        .await;

        assert!(result.ok);
        assert!(result.metadata.stdout_truncated);
        assert!(result.metadata.output_truncated);
        let data = result.data.unwrap();
        assert_eq!(data["stdout"], "abcd");
        assert_eq!(data["exit_code"], Value::Null);
        assert_eq!(data["terminated_by_runtime"], true);
        remove_test_dir(root);
    }

    #[cfg(unix)]
    #[tokio::test]
    async fn exec_command_truncation_stops_background_process_group() {
        let root = unique_test_dir("command-truncate-process-group");
        std::fs::create_dir_all(&root).unwrap();
        let mut config = allowed_config(&root);
        config.output_limit_bytes = 4;
        config.tool_timeout_ms = 500;

        let result = execute(
            &config,
            "call-1",
            json!({ "cmd": "printf abcdef; (sleep 0.5; printf late > late.txt) & sleep 1" }),
            Instant::now(),
        )
        .await;

        assert!(result.ok);
        assert!(result.metadata.stdout_truncated);
        tokio::time::sleep(std::time::Duration::from_millis(650)).await;
        assert!(!root.join("late.txt").exists());
        remove_test_dir(root);
    }

    fn allowed_config(root: &Path) -> RuntimeConfig {
        RuntimeConfig::workspace_write(root, root).with_command_mode(CommandMode::Allowed)
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

pub async fn execute(
    config: &RuntimeConfig,
    call_id: &str,
    arguments: Value,
    started: Instant,
) -> ToolResult {
    if !config.excluded_workspace_roots.is_empty() {
        return failure(
            call_id,
            "permission_denied",
            "command execution is unavailable when control-plane roots are excluded",
            false,
            started,
        );
    }
    if config.command_mode == CommandMode::Disabled {
        return failure(
            call_id,
            "command_disabled",
            "command execution is disabled",
            false,
            started,
        );
    }
    if config.mode != RuntimeMode::WorkspaceWrite {
        return failure(
            call_id,
            "permission_denied",
            "command execution requires workspace-write runtime mode",
            false,
            started,
        );
    }

    let request = match CommandRequest::parse(&arguments, config.tool_timeout_ms) {
        Ok(request) => request,
        Err(message) => return failure(call_id, "invalid_arguments", message, false, started),
    };
    if command_denied(&request.cmd) {
        return failure(
            call_id,
            "command_denied",
            "command is denied by runtime policy",
            false,
            started,
        );
    }

    let cwd = match path::resolve_existing_workspace_path_with_exclusions(
        &config.workspace_root,
        &request.cwd,
        &config.excluded_workspace_roots,
    ) {
        Ok(cwd) => cwd,
        Err(error) => return path_failure(call_id, error.to_string(), started),
    };

    match run_command(config, call_id, request, cwd, started).await {
        Ok(result) => result,
        Err(error) => failure(
            call_id,
            "execution_failed",
            error.to_string(),
            false,
            started,
        ),
    }
}

#[derive(Debug)]
struct CommandRequest {
    cmd: String,
    cwd: String,
    timeout_ms: u64,
}

impl CommandRequest {
    fn parse(arguments: &Value, tool_timeout_ms: u64) -> Result<Self, String> {
        let object = arguments
            .as_object()
            .ok_or_else(|| "arguments must be an object".to_string())?;
        if object
            .keys()
            .any(|key| !matches!(key.as_str(), "cmd" | "cwd" | "timeout_ms"))
        {
            return Err("unknown command argument".to_string());
        }

        let cmd = object
            .get("cmd")
            .and_then(Value::as_str)
            .ok_or_else(|| "cmd must be a string".to_string())?
            .to_string();
        if cmd.trim().is_empty() {
            return Err("cmd must not be empty".to_string());
        }

        let cwd = match object.get("cwd") {
            Some(value) => {
                let cwd = value
                    .as_str()
                    .ok_or_else(|| "cwd must be a string".to_string())?;
                if cwd.is_empty() {
                    return Err("cwd must not be empty".to_string());
                }
                cwd.to_string()
            }
            None => ".".to_string(),
        };

        let max_timeout_ms = internal_timeout_limit_ms(tool_timeout_ms);
        let timeout_ms = match object.get("timeout_ms") {
            Some(value) => value.as_u64().ok_or_else(|| {
                "timeout_ms must be an integer from 1 to the configured maximum".to_string()
            })?,
            None => max_timeout_ms,
        };
        if timeout_ms == 0 || timeout_ms > max_timeout_ms {
            return Err("timeout_ms must be from 1 to the configured maximum".to_string());
        }

        Ok(Self {
            cmd,
            cwd,
            timeout_ms,
        })
    }
}

fn internal_timeout_limit_ms(tool_timeout_ms: u64) -> u64 {
    tool_timeout_ms.saturating_sub(100).max(1)
}

async fn run_command(
    config: &RuntimeConfig,
    call_id: &str,
    request: CommandRequest,
    cwd: path::WorkspacePath,
    started: Instant,
) -> anyhow::Result<ToolResult> {
    let mut command = shell_command(&request.cmd);
    command
        .current_dir(&cwd.absolute)
        .stdin(Stdio::null())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .kill_on_drop(true)
        .env_clear();
    configure_process_group(&mut command);
    apply_allowed_env(&mut command);

    let mut child = command.spawn()?;
    let stdout = child
        .stdout
        .take()
        .ok_or_else(|| anyhow::anyhow!("command stdout unavailable"))?;
    let stderr = child
        .stderr
        .take()
        .ok_or_else(|| anyhow::anyhow!("command stderr unavailable"))?;
    let output_limit_bytes = command_capture_limit_bytes(config.output_limit_bytes);
    let output = read_limited_child_output(stdout, stderr, output_limit_bytes);
    tokio::pin!(output);

    tokio::select! {
        output = &mut output => {
            let output = output?;
            if output.stdout_truncated || output.stderr_truncated {
                terminate_child(&mut child).await;
                let _ = child.wait().await;
                return Ok(success(
                    call_id,
                    &request.cmd,
                    &cwd.relative,
                    None,
                    output,
                    true,
                    started,
                ));
            }

            let status = child.wait().await?;
            Ok(success(
                call_id,
                &request.cmd,
                &cwd.relative,
                status.code(),
                output,
                false,
                started,
            ))
        }
        _ = tokio::time::sleep(std::time::Duration::from_millis(request.timeout_ms)) => {
            terminate_child(&mut child).await;
            let _ = child.wait().await;
            Ok(failure(
                call_id,
                "timeout",
                "command execution timed out",
                true,
                started,
            ))
        }
    }
}

#[cfg(unix)]
fn shell_command(cmd: &str) -> Command {
    let mut command = Command::new("/bin/sh");
    command.arg("-c").arg(cmd);
    command
}

#[cfg(windows)]
fn shell_command(cmd: &str) -> Command {
    let mut command = Command::new("cmd");
    command.arg("/C").arg(cmd);
    command
}

#[cfg(unix)]
fn configure_process_group(command: &mut Command) {
    command.process_group(0);
}

#[cfg(not(unix))]
fn configure_process_group(_command: &mut Command) {}

#[cfg(unix)]
async fn terminate_child(child: &mut tokio::process::Child) {
    if let Some(pid) = child.id() {
        let group = format!("-{pid}");
        let _ = Command::new("/bin/kill")
            .arg("-TERM")
            .arg(&group)
            .stdin(Stdio::null())
            .stdout(Stdio::null())
            .stderr(Stdio::null())
            .status()
            .await;
        tokio::time::sleep(std::time::Duration::from_millis(50)).await;
        if matches!(child.try_wait(), Ok(Some(_))) {
            return;
        }
        let _ = Command::new("/bin/kill")
            .arg("-KILL")
            .arg(&group)
            .stdin(Stdio::null())
            .stdout(Stdio::null())
            .stderr(Stdio::null())
            .status()
            .await;
    }
    let _ = child.kill().await;
}

#[cfg(not(unix))]
async fn terminate_child(child: &mut tokio::process::Child) {
    let _ = child.kill().await;
}

fn apply_allowed_env(command: &mut Command) {
    for key in [
        "PATH", "HOME", "TMPDIR", "TEMP", "TMP", "USER", "SHELL", "LANG", "LC_ALL",
    ] {
        if let Some(value) = std::env::var_os(key) {
            command.env(key, value);
        }
    }
}

#[derive(Clone, Copy)]
struct DenyRule {
    name: &'static str,
    denied: fn(&str) -> bool,
}

const DENY_RULES: &[DenyRule] = &[
    DenyRule {
        name: "command substitution",
        denied: has_command_substitution,
    },
    DenyRule {
        name: "nested shell -c",
        denied: nested_shell_command_denied,
    },
    DenyRule {
        name: "git reset --hard",
        denied: git_reset_hard_denied,
    },
    DenyRule {
        name: "git clean -fd",
        denied: git_clean_denied,
    },
    DenyRule {
        name: "rm -rf /",
        denied: |cmd| rm_force_recursive_target_denied(cmd, "/"),
    },
    DenyRule {
        name: "rm -rf .",
        denied: |cmd| rm_force_recursive_target_denied(cmd, "."),
    },
    DenyRule {
        name: "sudo",
        denied: |cmd| contains_token(cmd, "sudo"),
    },
    DenyRule {
        name: "shutdown",
        denied: |cmd| contains_token(cmd, "shutdown"),
    },
    DenyRule {
        name: "reboot",
        denied: |cmd| contains_token(cmd, "reboot"),
    },
    DenyRule {
        name: "mkfs",
        denied: |cmd| contains_token_prefix(cmd, "mkfs"),
    },
];

fn command_denied(cmd: &str) -> bool {
    DENY_RULES.iter().any(|rule| {
        let _ = rule.name;
        (rule.denied)(cmd)
    })
}

fn has_command_substitution(cmd: &str) -> bool {
    cmd.contains("$(") || cmd.contains('`')
}

fn nested_shell_command_denied(cmd: &str) -> bool {
    command_tokens(cmd)
        .windows(2)
        .any(|window| is_shell_token(&window[0]) && window[1] == "-c")
}

fn is_shell_token(token: &str) -> bool {
    matches!(
        executable_basename(token),
        "sh" | "/bin/sh" | "bash" | "/bin/bash" | "zsh" | "/bin/zsh"
    )
}

fn git_reset_hard_denied(cmd: &str) -> bool {
    let tokens = command_tokens(cmd);
    tokens.iter().enumerate().any(|(index, token)| {
        executable_basename(token) == "git"
            && git_tail_has_subcommand_and_option(&tokens[index + 1..], "reset", "--hard")
    })
}

fn git_clean_denied(cmd: &str) -> bool {
    let tokens = command_tokens(cmd);
    tokens.iter().enumerate().any(|(index, token)| {
        executable_basename(token) == "git"
            && git_tail_has_matching_subcommand_option(
                &tokens[index + 1..],
                "clean",
                is_git_clean_force_delete,
            )
    })
}

fn is_git_clean_force_delete(token: &str) -> bool {
    token.starts_with('-') && token.contains('f') && token.contains('d')
}

fn git_tail_has_subcommand_and_option(tokens: &[String], subcommand: &str, option: &str) -> bool {
    git_tail_has_matching_subcommand_option(tokens, subcommand, |token| token == option)
}

fn git_tail_has_matching_subcommand_option(
    tokens: &[String],
    subcommand: &str,
    option_matches: impl Fn(&str) -> bool,
) -> bool {
    let Some(subcommand_index) = tokens.iter().position(|token| token == subcommand) else {
        return false;
    };
    tokens[subcommand_index + 1..]
        .iter()
        .any(|token| option_matches(token))
}

fn rm_force_recursive_target_denied(cmd: &str, target: &str) -> bool {
    let tokens = command_tokens(cmd);
    tokens.iter().enumerate().any(|(index, token)| {
        if executable_basename(token) != "rm" {
            return false;
        }
        let rest = &tokens[index + 1..];
        rest.iter()
            .any(|candidate| is_force_recursive_rm_option(candidate))
            && rest.iter().any(|candidate| candidate == target)
    })
}

fn is_force_recursive_rm_option(token: &str) -> bool {
    token.starts_with('-') && token.contains('r') && token.contains('f')
}

fn contains_token(cmd: &str, word: &str) -> bool {
    command_tokens(cmd)
        .iter()
        .any(|token| executable_basename(token) == word)
}

fn contains_token_prefix(cmd: &str, prefix: &str) -> bool {
    command_tokens(cmd)
        .iter()
        .any(|token| executable_basename(token).starts_with(prefix))
}

fn command_tokens(cmd: &str) -> Vec<String> {
    cmd.split(|character: char| character.is_whitespace() || matches!(character, ';' | '&' | '|'))
        .filter(|token| !token.is_empty())
        .map(normalize_command_token)
        .collect()
}

fn normalize_command_token(token: &str) -> String {
    token
        .trim_matches(|character: char| {
            matches!(
                character,
                '(' | ')' | '{' | '}' | '[' | ']' | '\'' | '"' | '`' | '$'
            )
        })
        .to_ascii_lowercase()
}

fn executable_basename(token: &str) -> &str {
    token.rsplit('/').next().unwrap_or(token)
}

fn command_capture_limit_bytes(output_limit_bytes: usize) -> usize {
    if output_limit_bytes > COMMAND_RESULT_ENVELOPE_RESERVE_BYTES {
        output_limit_bytes - COMMAND_RESULT_ENVELOPE_RESERVE_BYTES
    } else {
        output_limit_bytes.max(1)
    }
}

fn success(
    call_id: &str,
    cmd: &str,
    cwd: &std::path::Path,
    exit_code: Option<i32>,
    output: super::process::LimitedChildOutput,
    terminated_by_runtime: bool,
    started: Instant,
) -> ToolResult {
    let stdout_truncated = output.stdout_truncated;
    let stderr_truncated = output.stderr_truncated;
    ToolResult::success(
        EXEC_COMMAND,
        call_id,
        json!({
            "cmd": cmd,
            "cwd": relative_path(cwd),
            "exit_code": exit_code,
            "stdout": String::from_utf8_lossy(&output.stdout),
            "stderr": String::from_utf8_lossy(&output.stderr),
            "timed_out": false,
            "terminated_by_runtime": terminated_by_runtime
        }),
        ToolResultMetadata {
            duration_ms: started.elapsed().as_millis() as u64,
            stdout_truncated,
            stderr_truncated,
            output_truncated: stdout_truncated || stderr_truncated,
        },
    )
}

fn failure(
    call_id: &str,
    code: &str,
    message: impl Into<String>,
    retryable: bool,
    started: Instant,
) -> ToolResult {
    ToolResult::failure(
        EXEC_COMMAND,
        call_id,
        ToolError {
            code: code.to_string(),
            message: message.into(),
            retryable,
        },
        ToolResultMetadata {
            duration_ms: started.elapsed().as_millis() as u64,
            ..ToolResultMetadata::default()
        },
    )
}

fn path_failure(call_id: &str, message: String, started: Instant) -> ToolResult {
    let code = if message == crate::skill_security::RESERVED_SKILL_URI_ERROR
        || message == "workspace path is reserved for skill management"
    {
        "permission_denied"
    } else if message.contains("outside workspace") || message.contains("parent traversal") {
        "path_outside_workspace"
    } else if message.contains("failed to resolve workspace path") {
        "path_not_found"
    } else {
        "invalid_arguments"
    };
    failure(call_id, code, message, false, started)
}

fn relative_path(path: &std::path::Path) -> String {
    if path.as_os_str() == OsStr::new("") {
        ".".to_string()
    } else {
        path.to_string_lossy().to_string()
    }
}
