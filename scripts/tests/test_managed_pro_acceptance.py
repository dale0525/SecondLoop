import json
import os
import shlex
import tempfile
import unittest
from pathlib import Path
from unittest import mock

from scripts import managed_pro_acceptance


class ManagedProAcceptanceTests(unittest.TestCase):
    def test_desktop_integration_wrappers_cover_managed_pro_scenarios(self):
        app_root = Path(__file__).resolve().parents[2]
        expected_wrappers = {
            "external_tool_block_test.dart",
            "formal_task_mutation_approval_test.dart",
            "high_cost_confirmation_test.dart",
            "managed_pro_bootstrap_test.dart",
            "memory_approval_test.dart",
            "plan_draft_generation_test.dart",
            "provider_failure_and_recovery_test.dart",
            "recurring_reminder_rule_test.dart",
            "reminder_approval_test.dart",
            "runtime_mode_selection_test.dart",
            "time_driven_reminder_test.dart",
            "working_set_summary_test.dart",
            "email_calendar_protocol_tools_test.dart",
            "media_pipeline_runtime_test.dart",
            "web_research_citations_test.dart",
        }

        wrapper_dir = app_root / "integration_test" / "scenarios"

        self.assertEqual(
            {path.name for path in wrapper_dir.glob("*_test.dart")},
            expected_wrappers | {"self_managed_setup_flow_test.dart"},
        )

    def test_acceptance_runner_invokes_only_managed_pro_integration_wrappers(self):
        suite = managed_pro_acceptance.build_suite()
        command = next(
            item
            for item in suite.commands
            if item.command_id == "app_cloud_runtime_integration_scenarios"
        )

        wrapper_args = [
            item
            for item in command.argv
            if item.startswith("integration_test/scenarios/")
        ]

        self.assertEqual(
            set(wrapper_args),
            {
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
            },
        )
        self.assertNotIn(
            "integration_test/scenarios/self_managed_setup_flow_test.dart",
            command.argv,
        )

    def test_runbook_managed_pro_cases_are_fully_mapped(self):
        expected_case_ids = {
            "QA-SETUP-00",
            "QA-CHAT-01",
            "QA-CHAT-02",
            "QA-CHAT-03",
            "QA-CHAT-05A",
            "QA-CHAT-05B",
            "QA-CHAT-05C",
            "QA-CHAT-05D",
            "QA-CHAT-05",
            "QA-REM-01",
            "QA-REM-02",
            "QA-REM-03",
            "QA-TASK-REL-01",
            "QA-TASK-REL-02",
            "QA-FILE-01",
            "QA-FILE-02",
            "QA-FILE-03",
            "QA-EXT-01",
            "QA-EXT-02",
            "QA-EXT-03",
            "QA-SAFE-01",
            "QA-SAFE-02",
        }

        suite = managed_pro_acceptance.build_suite()

        self.assertEqual(
            {case.case_id for case in suite.cases},
            expected_case_ids,
        )
        for case in suite.cases:
            self.assertGreater(
                len(case.evidence_ids),
                0,
                f"{case.case_id} must have at least one evidence command",
            )

    def test_acceptance_runner_references_existing_app_tests(self):
        app_root = Path(__file__).resolve().parents[2]
        suite = managed_pro_acceptance.build_suite()
        command = next(
            item
            for item in suite.commands
            if item.command_id == "app_runtime_first_semantics"
        )
        command_tokens = [
            token
            for argument in command.argv
            for token in shlex.split(argument)
        ]
        test_paths = [
            token
            for token in command_tokens
            if token.startswith("test/") and token.endswith("_test.dart")
        ]

        self.assertGreater(len(test_paths), 0)
        self.assertEqual(
            [path for path in test_paths if not (app_root / path).is_file()],
            [],
        )

    def test_chat_cases_require_live_managed_pro_account_evidence(self):
        suite = managed_pro_acceptance.build_suite()
        cases = {case.case_id: case for case in suite.cases}

        self.assertIn(
            "app_live_managed_pro_chat_acceptance",
            cases["QA-CHAT-01"].evidence_ids,
        )
        self.assertIn(
            "app_live_managed_pro_chat_acceptance",
            cases["QA-CHAT-02"].evidence_ids,
        )

    def test_live_account_command_blocks_without_credentials(self):
        suite = managed_pro_acceptance.build_suite()
        command = next(
            item
            for item in suite.commands
            if item.command_id == "app_live_managed_pro_chat_acceptance"
        )

        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            app_root = root / "SecondLoop"
            server_root = root / "SecondLoopServer"
            logs_dir = root / "logs"
            app_root.mkdir()
            server_root.mkdir()
            logs_dir.mkdir()
            with mock.patch.dict(os.environ, {}, clear=True):
                result = managed_pro_acceptance._run_command(
                    command,
                    app_root=app_root,
                    server_root=server_root,
                    workspace_root=root,
                    logs_dir=logs_dir,
                    dry_run=False,
                    include_staging_reset=True,
                    include_desktop_integration=True,
                )

        self.assertEqual(result.status, "BLOCKED")
        self.assertIn("SECONDLOOP_LIVE_MANAGED_PRO_ACCEPTANCE", result.reason)

    def test_dry_run_writes_machine_and_human_readable_reports(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            output_dir = Path(temp_dir)

            result = managed_pro_acceptance.run_acceptance(
                dry_run=True,
                include_staging_reset=True,
                include_desktop_integration=True,
                output_dir=output_dir,
            )

            json_report = output_dir / "managed_pro_acceptance_report.json"
            markdown_report = output_dir / "managed_pro_acceptance_report.md"
            self.assertTrue(json_report.is_file())
            self.assertTrue(markdown_report.is_file())

            payload = json.loads(json_report.read_text(encoding="utf-8"))
            self.assertEqual(payload["mode"], "managed_pro")
            self.assertEqual(payload["overall_status"], "PASS")
            self.assertIn("QA-CHAT-01", payload["cases"])
            self.assertIn("QA-CHAT-05D", payload["cases"])
            self.assertIn("server_cloud_runtime_automation", payload["commands"])

    def test_overall_status_fails_when_any_case_fails(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            output_dir = Path(temp_dir)

            def fake_run_command(command, **_kwargs):
                status = (
                    "FAIL"
                    if command.command_id == "app_live_managed_pro_chat_acceptance"
                    else "PASS"
                )
                return managed_pro_acceptance.CommandResult(
                    command_id=command.command_id,
                    status=status,
                    description=command.description,
                    duration_seconds=0.0,
                )

            with mock.patch.object(
                managed_pro_acceptance,
                "_run_command",
                side_effect=fake_run_command,
            ):
                result = managed_pro_acceptance.run_acceptance(
                    dry_run=False,
                    include_staging_reset=True,
                    include_desktop_integration=True,
                    output_dir=output_dir,
                )

        self.assertEqual(result["overall_status"], "FAIL")
        self.assertEqual(result["cases"]["QA-CHAT-01"]["status"], "FAIL")


if __name__ == "__main__":
    unittest.main()
