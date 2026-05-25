#!/usr/bin/env python3
from __future__ import annotations

import argparse
import dataclasses
import hashlib
import json
import os
import platform
import shutil
import subprocess
import sys
import time
from datetime import datetime, timezone
from pathlib import Path
from typing import Iterable


ASSET_MD5 = {
    "qa-ocr-sample.png": "d31b5939f46e7ca11fc19ac1b68e69a4",
    "qa-meeting-audio.m4a": "01961fbfbc9afbf21b27f08b1a64a6fb",
    "qa-scan-sample.pdf": "b0630c9e12ae4edd076b43eec4f6c1d0",
}

MANAGED_PRO_INTEGRATION_WRAPPERS = (
    "integration_test/scenarios/email_calendar_protocol_tools_test.dart",
    "integration_test/scenarios/external_tool_block_test.dart",
    "integration_test/scenarios/formal_task_mutation_approval_test.dart",
    "integration_test/scenarios/high_cost_confirmation_test.dart",
    "integration_test/scenarios/managed_pro_bootstrap_test.dart",
    "integration_test/scenarios/media_pipeline_runtime_test.dart",
    "integration_test/scenarios/memory_approval_test.dart",
    "integration_test/scenarios/plan_draft_generation_test.dart",
    "integration_test/scenarios/provider_failure_and_recovery_test.dart",
    "integration_test/scenarios/recurring_reminder_rule_test.dart",
    "integration_test/scenarios/reminder_approval_test.dart",
    "integration_test/scenarios/runtime_mode_selection_test.dart",
    "integration_test/scenarios/time_driven_reminder_test.dart",
    "integration_test/scenarios/web_research_citations_test.dart",
    "integration_test/scenarios/working_set_summary_test.dart",
)

LIVE_MANAGED_PRO_ENABLE_KEY = "SECONDLOOP_LIVE_MANAGED_PRO_ACCEPTANCE"
LIVE_MANAGED_PRO_REQUIRED_KEYS = (
    LIVE_MANAGED_PRO_ENABLE_KEY,
    "SECONDLOOP_LIVE_MANAGED_PRO_EMAIL",
    "SECONDLOOP_LIVE_MANAGED_PRO_PASSWORD",
    "SECONDLOOP_FIREBASE_WEB_API_KEY",
)


@dataclasses.dataclass(frozen=True)
class EvidenceCommand:
    command_id: str
    description: str
    argv: tuple[str, ...] = ()
    cwd: str = "app"
    kind: str = "process"
    requires_staging_reset: bool = False
    requires_desktop_integration: bool = False


@dataclasses.dataclass(frozen=True)
class AcceptanceCase:
    case_id: str
    title: str
    evidence_ids: tuple[str, ...]
    notes: tuple[str, ...] = ()


@dataclasses.dataclass(frozen=True)
class AcceptanceSuite:
    commands: tuple[EvidenceCommand, ...]
    cases: tuple[AcceptanceCase, ...]


@dataclasses.dataclass(frozen=True)
class CommandResult:
    command_id: str
    status: str
    description: str
    duration_seconds: float
    log_path: str | None = None
    screenshot_path: str | None = None
    reason: str | None = None


def build_suite() -> AcceptanceSuite:
    commands = (
        EvidenceCommand(
            "reset_local_dev_data",
            "Reset local SecondLoop Dev app data.",
            ("pixi", "run", "reset-local-dev-data"),
            requires_staging_reset=True,
        ),
        EvidenceCommand(
            "verify_empty_local_dev_data",
            "Verify local SecondLoop Dev app data, preferences, and secure blob are empty.",
            ("pixi", "run", "verify-empty-local-dev-data"),
            requires_staging_reset=True,
        ),
        EvidenceCommand(
            "reset_cloud_runtime_local",
            "Reset local Cloudflare runtime test resources.",
            ("pixi", "run", "reset-cloud-runtime-local"),
            cwd="server",
            requires_staging_reset=True,
        ),
        EvidenceCommand(
            "reset_cloud_runtime_staging",
            "Reset staging Cloudflare runtime test resources.",
            ("pixi", "run", "reset-cloud-runtime-staging"),
            cwd="server",
            requires_staging_reset=True,
        ),
        EvidenceCommand(
            "managed_vault_wipe_staging",
            "Wipe staging managed vault data.",
            ("pixi", "run", "managed-vault-wipe-staging"),
            cwd="server",
            requires_staging_reset=True,
        ),
        EvidenceCommand(
            "verify_empty_cloud_runtime_staging",
            "Verify staging runtime and vault snapshots are empty after reset.",
            ("pixi", "run", "verify-empty-cloud-runtime-staging"),
            cwd="server",
            requires_staging_reset=True,
        ),
        EvidenceCommand(
            "qa_assets_check",
            "Verify QA media assets exist and match expected hashes.",
            kind="qa_assets",
        ),
        EvidenceCommand(
            "server_bootstrap_cloud_runtime",
            "Build the server runtime bootstrap/reset request plan.",
            ("pixi", "run", "bootstrap-cloud-runtime-test-env"),
            cwd="server",
        ),
        EvidenceCommand(
            "server_cloud_runtime_automation",
            "Run server runtime protocol, provider, artifact, and state tests.",
            ("pixi", "run", "cloud-runtime-automation-test"),
            cwd="server",
        ),
        EvidenceCommand(
            "server_export_cloud_runtime_artifacts",
            "Export server runtime transcript/state/approval/provider evidence bundle.",
            ("pixi", "run", "export-cloud-runtime-test-artifacts"),
            cwd="server",
        ),
        EvidenceCommand(
            "app_cloud_runtime_automation",
            "Run app runtime contract, selector, and model tests.",
            ("pixi", "run", "cloud-runtime-automation-test"),
        ),
        EvidenceCommand(
            "app_runtime_first_semantics",
            "Run app chat and quick-capture runtime-first regression tests.",
            (
                "pixi",
                "run",
                "flutter",
                "test",
                "test/quick_capture_runtime_first_semantics_test.dart "
                "test/quick_capture_test.dart "
                "test/agent_conversation_test.dart "
                "test/agent_conversation_runtime_state_source_test.dart "
                "test/agent_task_runtime_state_source_test.dart "
                "test/memory_page_runtime_state_source_test.dart "
                "test/runtime_secretary_app_service_authority_test.dart",
            ),
        ),
        EvidenceCommand(
            "app_cloud_runtime_scenarios",
            "Run app protocol scenario tests for approvals, reminders, media, web, and safety.",
            ("pixi", "run", "cloud-runtime-scenarios-test"),
        ),
        EvidenceCommand(
            "app_cloud_runtime_automation_smoke",
            "Run desktop app smoke test that clicks managed pro and self-managed runtime entries.",
            ("pixi", "run", "cloud-runtime-automation-smoke"),
            requires_desktop_integration=True,
        ),
        EvidenceCommand(
            "app_cloud_runtime_integration_scenarios",
            "Run managed pro desktop integration scenario wrappers against the app shell.",
            (
                "pixi",
                "run",
                "cloud-runtime-integration-scenarios-test",
                *MANAGED_PRO_INTEGRATION_WRAPPERS,
            ),
            requires_desktop_integration=True,
        ),
        EvidenceCommand(
            "app_live_managed_pro_chat_acceptance",
            "Run live managed pro chat acceptance with a real test account through app runtime interfaces.",
            ("pixi", "run", "cloud-runtime-live-managed-pro-chat-acceptance"),
            kind="live_account",
            requires_desktop_integration=True,
        ),
        EvidenceCommand(
            "acceptance_report",
            "Generate final managed pro acceptance JSON and Markdown evidence report.",
            kind="report",
        ),
    )

    cases = (
        AcceptanceCase(
            "QA-SETUP-00",
            "Clear local and staging managed pro data",
            (
                "server_bootstrap_cloud_runtime",
                "reset_local_dev_data",
                "reset_cloud_runtime_local",
                "reset_cloud_runtime_staging",
                "managed_vault_wipe_staging",
                "verify_empty_cloud_runtime_staging",
                "verify_empty_local_dev_data",
            ),
            ("Remote staging reset is guarded by --include-staging-reset.",),
        ),
        AcceptanceCase(
            "QA-CHAT-01",
            "Create an ordinary task",
            (
                "app_live_managed_pro_chat_acceptance",
                "app_runtime_first_semantics",
                "server_cloud_runtime_automation",
            ),
        ),
        AcceptanceCase(
            "QA-CHAT-02",
            "Task mutation requires approval and does not mark done early",
            (
                "app_live_managed_pro_chat_acceptance",
                "app_cloud_runtime_scenarios",
                "app_cloud_runtime_integration_scenarios",
                "server_cloud_runtime_automation",
            ),
        ),
        AcceptanceCase(
            "QA-CHAT-03",
            "Multiple memories stay split",
            (
                "app_cloud_runtime_scenarios",
                "app_cloud_runtime_integration_scenarios",
                "server_cloud_runtime_automation",
            ),
        ),
        AcceptanceCase(
            "QA-CHAT-05A",
            "Search skill automated precheck",
            (
                "app_live_managed_pro_chat_acceptance",
                "app_cloud_runtime_scenarios",
                "app_cloud_runtime_integration_scenarios",
                "app_runtime_first_semantics",
                "server_cloud_runtime_automation",
            ),
            (
                "Runtime/model-gateway logs must show web research tool use and "
                "LLM skill_result_response postprocess before the final reply.",
            ),
        ),
        AcceptanceCase(
            "QA-CHAT-05B",
            "Real app first-turn web research with citations",
            (
                "app_live_managed_pro_chat_acceptance",
                "app_cloud_runtime_scenarios",
                "app_cloud_runtime_integration_scenarios",
                "server_cloud_runtime_automation",
            ),
        ),
        AcceptanceCase(
            "QA-CHAT-05C",
            "Follow-up keeps the searched Apple launch context",
            (
                "app_live_managed_pro_chat_acceptance",
                "server_cloud_runtime_automation",
            ),
            (
                "Continuity evidence must include recent-turn context, not only "
                "the first search response.",
            ),
        ),
        AcceptanceCase(
            "QA-CHAT-05D",
            "Search skill acceptance evidence is captured",
            (
                "app_live_managed_pro_chat_acceptance",
                "server_export_cloud_runtime_artifacts",
                "acceptance_report",
            ),
        ),
        AcceptanceCase(
            "QA-CHAT-05",
            "Current fact search and follow-up acceptance",
            (
                "app_live_managed_pro_chat_acceptance",
                "app_cloud_runtime_scenarios",
                "server_cloud_runtime_automation",
                "server_export_cloud_runtime_artifacts",
                "acceptance_report",
            ),
            ("Do not pass this umbrella case unless QA-CHAT-05A-D pass.",),
        ),
        AcceptanceCase(
            "QA-REM-01",
            "Missing birthday returns clarification",
            (
                "app_cloud_runtime_scenarios",
                "server_cloud_runtime_automation",
            ),
        ),
        AcceptanceCase(
            "QA-REM-02",
            "Birthday answer creates separate memory and recurring reminder candidates",
            (
                "app_cloud_runtime_scenarios",
                "server_cloud_runtime_automation",
            ),
        ),
        AcceptanceCase(
            "QA-REM-03",
            "Approved recurring reminder is enabled with next fire date",
            (
                "app_cloud_runtime_scenarios",
                "server_cloud_runtime_automation",
            ),
        ),
        AcceptanceCase(
            "QA-TASK-REL-01",
            "Relative task reference mutates the latest task",
            (
                "app_live_managed_pro_chat_acceptance",
                "app_runtime_first_semantics",
                "server_cloud_runtime_automation",
            ),
        ),
        AcceptanceCase(
            "QA-TASK-REL-02",
            "Ambiguous relative task reference asks for clarification",
            (
                "app_runtime_first_semantics",
                "server_cloud_runtime_automation",
            ),
        ),
        AcceptanceCase(
            "QA-EXT-01",
            "Unconfigured email cannot pretend to send",
            (
                "app_runtime_first_semantics",
                "app_cloud_runtime_scenarios",
                "server_cloud_runtime_automation",
            ),
        ),
        AcceptanceCase(
            "QA-EXT-02",
            "Configured email requires send approval",
            (
                "app_cloud_runtime_scenarios",
                "server_cloud_runtime_automation",
            ),
            ("External mailbox inspection is replaced by approval/tool-call protocol evidence.",),
        ),
        AcceptanceCase(
            "QA-EXT-03",
            "Calendar event creation requires approval",
            (
                "app_cloud_runtime_scenarios",
                "server_cloud_runtime_automation",
            ),
            ("External calendar inspection is replaced by approval/tool-call protocol evidence.",),
        ),
        AcceptanceCase(
            "QA-FILE-01",
            "Image OCR and summary",
            (
                "qa_assets_check",
                "app_cloud_runtime_scenarios",
                "server_cloud_runtime_automation",
            ),
        ),
        AcceptanceCase(
            "QA-FILE-02",
            "PDF OCR and expiry date extraction",
            (
                "qa_assets_check",
                "app_cloud_runtime_scenarios",
                "server_cloud_runtime_automation",
            ),
        ),
        AcceptanceCase(
            "QA-FILE-03",
            "Audio transcript and action items",
            (
                "qa_assets_check",
                "app_cloud_runtime_scenarios",
                "server_cloud_runtime_automation",
            ),
        ),
        AcceptanceCase(
            "QA-SAFE-01",
            "Ticket purchase request is refused",
            (
                "app_cloud_runtime_scenarios",
                "server_cloud_runtime_automation",
            ),
        ),
        AcceptanceCase(
            "QA-SAFE-02",
            "Local shell/file deletion request is refused",
            (
                "app_cloud_runtime_scenarios",
                "server_cloud_runtime_automation",
            ),
        ),
    )
    return AcceptanceSuite(commands=commands, cases=cases)


def run_acceptance(
    *,
    dry_run: bool = False,
    include_staging_reset: bool = False,
    include_desktop_integration: bool = True,
    output_dir: Path | None = None,
) -> dict[str, object]:
    app_root = _app_root()
    workspace_root = app_root.parent
    server_root = _server_root()
    artifact_dir = output_dir or _default_output_dir(app_root)
    logs_dir = artifact_dir / "logs"
    logs_dir.mkdir(parents=True, exist_ok=True)

    suite = build_suite()
    selected_command_ids = _selected_command_ids(suite)
    command_results: dict[str, CommandResult] = {}

    for command in suite.commands:
        if command.command_id not in selected_command_ids:
            continue
        result = _run_command(
            command,
            app_root=app_root,
            server_root=server_root,
            workspace_root=workspace_root,
            logs_dir=logs_dir,
            dry_run=dry_run,
            include_staging_reset=include_staging_reset,
            include_desktop_integration=include_desktop_integration,
        )
        command_results[command.command_id] = result

    case_results = _evaluate_cases(suite, command_results)
    overall_status = _overall_status(
        str(result["status"]) for result in case_results.values()
    )
    payload = {
        "schema_version": 1,
        "mode": "managed_pro",
        "generated_at": datetime.now(timezone.utc).isoformat(),
        "workspace_root": str(workspace_root),
        "app_commit": _git_short_head(app_root),
        "server_commit": (
            _git_short_head(server_root)
            if server_root is not None and server_root.exists()
            else None
        ),
        "overall_status": overall_status,
        "commands": {
            command_id: dataclasses.asdict(result)
            for command_id, result in command_results.items()
        },
        "cases": case_results,
    }
    _write_reports(artifact_dir, payload, suite)
    if not dry_run:
        print(f"Managed pro acceptance report: {artifact_dir}")
        print(f"Overall status: {overall_status}")
    return payload


def _selected_command_ids(suite: AcceptanceSuite) -> set[str]:
    command_ids: set[str] = set()
    for case in suite.cases:
        command_ids.update(case.evidence_ids)
    return command_ids


def _run_command(
    command: EvidenceCommand,
    *,
    app_root: Path,
    server_root: Path | None,
    workspace_root: Path,
    logs_dir: Path,
    dry_run: bool,
    include_staging_reset: bool,
    include_desktop_integration: bool,
) -> CommandResult:
    start = time.monotonic()
    if command.requires_staging_reset and not include_staging_reset:
        return CommandResult(
            command_id=command.command_id,
            status="BLOCKED",
            description=command.description,
            duration_seconds=0.0,
            reason="staging reset was not enabled; rerun with --include-staging-reset",
        )
    if command.requires_desktop_integration and not include_desktop_integration:
        return CommandResult(
            command_id=command.command_id,
            status="BLOCKED",
            description=command.description,
            duration_seconds=0.0,
            reason="desktop integration was disabled",
        )
    if dry_run:
        return CommandResult(
            command_id=command.command_id,
            status="PASS",
            description=command.description,
            duration_seconds=0.0,
            reason="dry run",
        )
    if command.kind == "qa_assets":
        return _run_asset_check(command, app_root, start)
    if command.kind == "live_account":
        return _run_live_account_command(command, app_root, logs_dir, start)
    if command.kind == "report":
        return CommandResult(
            command_id=command.command_id,
            status="PASS",
            description=command.description,
            duration_seconds=_duration(start),
        )

    if command.cwd == "server" and server_root is None:
        return CommandResult(
            command_id=command.command_id,
            status="BLOCKED",
            description=command.description,
            duration_seconds=_duration(start),
            reason="server root not configured; set SECONDLOOP_SERVER_ROOT",
        )
    if command.cwd == "server" and not server_root.is_dir():
        return CommandResult(
            command_id=command.command_id,
            status="BLOCKED",
            description=command.description,
            duration_seconds=_duration(start),
            reason=f"server root not found: {server_root}",
        )
    cwd = app_root if command.cwd == "app" else server_root
    log_path = logs_dir / f"{command.command_id}.log"
    status = _run_process(command.argv, cwd=cwd, log_path=log_path)
    screenshot_path = None
    if status != "PASS":
        screenshot_path = _capture_failure_screenshot(logs_dir, command.command_id)
    return CommandResult(
        command_id=command.command_id,
        status=status,
        description=command.description,
        duration_seconds=_duration(start),
        log_path=str(log_path),
        screenshot_path=screenshot_path,
    )


def _run_process(argv: Iterable[str], *, cwd: Path, log_path: Path) -> str:
    print(f"acceptance: running {' '.join(argv)}", flush=True)
    env = os.environ.copy()
    process = subprocess.Popen(
        tuple(argv),
        cwd=str(cwd),
        env=env,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        bufsize=1,
    )
    with log_path.open("w", encoding="utf-8") as log_file:
        assert process.stdout is not None
        for line in process.stdout:
            sys.stdout.write(line)
            log_file.write(line)
    return "PASS" if process.wait() == 0 else "FAIL"


def _run_live_account_command(
    command: EvidenceCommand,
    app_root: Path,
    logs_dir: Path,
    start: float,
) -> CommandResult:
    missing = _missing_live_managed_pro_env(app_root)
    if missing:
        return CommandResult(
            command_id=command.command_id,
            status="BLOCKED",
            description=command.description,
            duration_seconds=_duration(start),
            reason="missing live managed pro env: " + ", ".join(missing),
        )
    log_path = logs_dir / f"{command.command_id}.log"
    status = _run_process(command.argv, cwd=app_root, log_path=log_path)
    screenshot_path = None
    if status != "PASS":
        screenshot_path = _capture_failure_screenshot(logs_dir, command.command_id)
    return CommandResult(
        command_id=command.command_id,
        status=status,
        description=command.description,
        duration_seconds=_duration(start),
        log_path=str(log_path),
        screenshot_path=screenshot_path,
    )


def _missing_live_managed_pro_env(app_root: Path) -> list[str]:
    values = _combined_env_with_dotenv(app_root)
    missing: list[str] = []
    if values.get(LIVE_MANAGED_PRO_ENABLE_KEY, "").strip() != "1":
        missing.append(f"{LIVE_MANAGED_PRO_ENABLE_KEY}=1")
    for key in LIVE_MANAGED_PRO_REQUIRED_KEYS:
        if key == LIVE_MANAGED_PRO_ENABLE_KEY:
            continue
        if not values.get(key, "").strip():
            missing.append(key)
    if not _resolve_cloud_gateway_base_url(values):
        missing.append(
            "SECONDLOOP_CLOUD_GATEWAY_BASE_URL_STAGING/PROD via SECONDLOOP_CLOUD_ENV"
        )
    return missing


def _combined_env_with_dotenv(app_root: Path) -> dict[str, str]:
    values = _read_dotenv(app_root / ".env.local")
    values.update(os.environ)
    return values


def _read_dotenv(path: Path) -> dict[str, str]:
    if not path.is_file():
        return {}
    values: dict[str, str] = {}
    for raw_line in path.read_text(encoding="utf-8").splitlines():
        line = raw_line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, value = line.split("=", 1)
        key = key.strip()
        if not key:
            continue
        values[key] = value.strip().strip("\"'")
    return values


def _resolve_cloud_gateway_base_url(values: dict[str, str]) -> str:
    direct = values.get("SECONDLOOP_CLOUD_GATEWAY_BASE_URL", "").strip()
    if direct:
        return direct
    cloud_env = values.get("SECONDLOOP_CLOUD_ENV", "").strip().lower()
    if cloud_env in ("staging", "stage"):
        return values.get("SECONDLOOP_CLOUD_GATEWAY_BASE_URL_STAGING", "").strip()
    if cloud_env in ("prod", "production"):
        return values.get("SECONDLOOP_CLOUD_GATEWAY_BASE_URL_PROD", "").strip()
    return ""


def _run_asset_check(
    command: EvidenceCommand,
    app_root: Path,
    start: float,
) -> CommandResult:
    asset_dir = app_root / "docs" / "qa-assets"
    missing: list[str] = []
    mismatched: list[str] = []
    invalid_type: list[str] = []
    for filename, expected_md5 in ASSET_MD5.items():
        path = asset_dir / filename
        if not path.is_file():
            missing.append(filename)
            continue
        digest = hashlib.md5(path.read_bytes()).hexdigest()
        if digest != expected_md5:
            mismatched.append(f"{filename}:{digest}")
        if not _asset_header_matches(filename, path):
            invalid_type.append(filename)
    failures = []
    if missing:
        failures.append(f"missing={','.join(missing)}")
    if mismatched:
        failures.append(f"md5={','.join(mismatched)}")
    if invalid_type:
        failures.append(f"type={','.join(invalid_type)}")
    return CommandResult(
        command_id=command.command_id,
        status="FAIL" if failures else "PASS",
        description=command.description,
        duration_seconds=_duration(start),
        reason="; ".join(failures) if failures else None,
    )


def _asset_header_matches(filename: str, path: Path) -> bool:
    data = path.read_bytes()[:16]
    if filename.endswith(".png"):
        return data.startswith(b"\x89PNG\r\n\x1a\n")
    if filename.endswith(".pdf"):
        return data.startswith(b"%PDF")
    if filename.endswith(".m4a"):
        return b"ftyp" in data
    return True


def _evaluate_cases(
    suite: AcceptanceSuite,
    command_results: dict[str, CommandResult],
) -> dict[str, dict[str, object]]:
    cases: dict[str, dict[str, object]] = {}
    for case in suite.cases:
        evidence = [command_results[evidence_id] for evidence_id in case.evidence_ids]
        status = _overall_status(result.status for result in evidence)
        cases[case.case_id] = {
            "title": case.title,
            "status": status,
            "evidence_ids": list(case.evidence_ids),
            "notes": list(case.notes),
        }
    return cases


def _overall_status(statuses: Iterable[str]) -> str:
    values = list(statuses)
    if any(status == "FAIL" for status in values):
        return "FAIL"
    if any(status == "BLOCKED" for status in values):
        return "BLOCKED"
    return "PASS"


def _write_reports(
    artifact_dir: Path,
    payload: dict[str, object],
    suite: AcceptanceSuite,
) -> None:
    json_path = artifact_dir / "managed_pro_acceptance_report.json"
    markdown_path = artifact_dir / "managed_pro_acceptance_report.md"
    json_path.write_text(
        json.dumps(payload, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )
    markdown_path.write_text(_render_markdown(payload, suite), encoding="utf-8")


def _render_markdown(
    payload: dict[str, object],
    suite: AcceptanceSuite,
) -> str:
    cases = payload["cases"]
    commands = payload["commands"]
    assert isinstance(cases, dict)
    assert isinstance(commands, dict)
    lines = [
        "# Managed Pro Acceptance Report",
        "",
        f"- Overall status: `{payload['overall_status']}`",
        f"- Generated at: `{payload['generated_at']}`",
        f"- App commit: `{payload['app_commit']}`",
        f"- Server commit: `{payload['server_commit']}`",
        "",
        "## Runbook Cases",
        "",
        "| Case | Status | Evidence |",
        "| --- | --- | --- |",
    ]
    for case in suite.cases:
        result = cases[case.case_id]
        assert isinstance(result, dict)
        evidence = ", ".join(f"`{item}`" for item in case.evidence_ids)
        lines.append(f"| `{case.case_id}` | `{result['status']}` | {evidence} |")
    lines.extend([
        "",
        "## Evidence Commands",
        "",
        "| Command | Status | Log | Screenshot |",
        "| --- | --- | --- | --- |",
    ])
    for command in suite.commands:
        raw = commands.get(command.command_id)
        if not isinstance(raw, dict):
            continue
        log_path = raw.get("log_path") or ""
        screenshot_path = raw.get("screenshot_path") or ""
        lines.append(
            f"| `{command.command_id}` | `{raw['status']}` | `{log_path}` | `{screenshot_path}` |"
        )
    lines.append("")
    return "\n".join(lines)


def _capture_failure_screenshot(logs_dir: Path, command_id: str) -> str | None:
    if platform.system() != "Darwin" or shutil.which("screencapture") is None:
        return None
    screenshot_path = logs_dir / f"{command_id}.failure.png"
    subprocess.run(
        ("screencapture", "-x", str(screenshot_path)),
        check=False,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )
    return str(screenshot_path) if screenshot_path.exists() else None


def _app_root() -> Path:
    return Path(__file__).resolve().parents[1]


def _server_root() -> Path | None:
    override = os.environ.get("SECONDLOOP_SERVER_ROOT")
    if override:
        return Path(override).resolve()
    return None


def _default_output_dir(app_root: Path) -> Path:
    timestamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    return app_root / "build" / "managed_pro_acceptance" / timestamp


def _git_short_head(repo_root: Path) -> str | None:
    try:
        result = subprocess.run(
            ("git", "rev-parse", "--short", "HEAD"),
            cwd=str(repo_root),
            check=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL,
            text=True,
        )
        return result.stdout.strip()
    except (OSError, subprocess.CalledProcessError):
        return None


def _duration(start: float) -> float:
    return round(time.monotonic() - start, 3)


def _parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Run the managed pro acceptance suite and write evidence reports.",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Generate the command/case report without executing commands.",
    )
    parser.add_argument(
        "--include-staging-reset",
        action="store_true",
        help="Run destructive local/staging reset commands from QA-SETUP-00.",
    )
    parser.add_argument(
        "--skip-desktop-integration",
        action="store_true",
        help="Skip macOS desktop integration tests and mark dependent cases blocked.",
    )
    parser.add_argument(
        "--output-dir",
        type=Path,
        help="Directory for reports and logs. Defaults to build/managed_pro_acceptance/<timestamp>.",
    )
    return parser.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    args = _parse_args(argv or sys.argv[1:])
    result = run_acceptance(
        dry_run=args.dry_run,
        include_staging_reset=args.include_staging_reset,
        include_desktop_integration=not args.skip_desktop_integration,
        output_dir=args.output_dir,
    )
    return 0 if result["overall_status"] == "PASS" else 1


if __name__ == "__main__":
    raise SystemExit(main())
