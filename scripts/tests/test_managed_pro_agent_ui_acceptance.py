from __future__ import annotations

from pathlib import Path
import re
import tomllib
import unittest


REPO_ROOT = Path(__file__).resolve().parents[2]
PIXI_TOML = REPO_ROOT / "pixi.toml"
RUNNER = REPO_ROOT / "scripts/run_managed_pro_agent_ui_acceptance.sh"
INTEGRATION_TEST = REPO_ROOT / "integration_test/managed_pro_agent_ui_acceptance_test.dart"


class ManagedProAgentUiAcceptanceTests(unittest.TestCase):
    def _load_pixi_config(self) -> dict[str, object]:
        with PIXI_TOML.open("rb") as fh:
            return tomllib.load(fh)

    def test_macos_pixi_task_runs_managed_pro_agent_ui_acceptance(self) -> None:
        pixi_config = self._load_pixi_config()
        task = pixi_config["target"]["osx-arm64"]["tasks"][
            "managed-pro-agent-ui-acceptance"
        ]

        self.assertEqual(task["cmd"], "bash scripts/run_managed_pro_agent_ui_acceptance.sh")
        self.assertIn("bootstrap-shared-worktree-env", task["depends-on"])
        self.assertIn("setup-flutter", task["depends-on"])
        self.assertIn("init-env", task["depends-on"])

    def test_runner_uses_secondloop_dev_and_writes_acceptance_artifacts(self) -> None:
        script = RUNNER.read_text(encoding="utf-8")

        self.assertIn("SECONDLOOP_APP_ID=com.secondloop.secondloopdev", script)
        self.assertIn("SECONDLOOP_APP_NAME='SecondLoop Dev'", script)
        self.assertIn("build/managed_pro_acceptance", script)
        self.assertIn("SECONDLOOP_MANAGED_PRO_ACCEPTANCE_OUTPUT_DIR", script)
        self.assertIn("source .env.local", script)
        self.assertIn("SECONDLOOP_MANAGED_PRO_EMAIL", script)
        self.assertIn("SECONDLOOP_MANAGED_PRO_PASSWORD", script)
        self.assertIn("SECONDLOOP_LIVE_MANAGED_PRO_EMAIL", script)
        self.assertIn("SECONDLOOP_LIVE_MANAGED_PRO_PASSWORD", script)
        self.assertIn("missing required ${name}", script)
        self.assertIn("require_env SECONDLOOP_MANAGED_PRO_EMAIL", script)
        self.assertIn("require_env SECONDLOOP_MANAGED_PRO_PASSWORD", script)
        self.assertIn("scripts/flutter_with_defines.sh test", script)
        self.assertNotIn("--concurrency=1", script)
        self.assertIn("integration_test/managed_pro_agent_ui_acceptance_test.dart", script)

    def test_acceptance_test_uses_app_ui_interactions_and_screenshots(self) -> None:
        source = INTEGRATION_TEST.read_text(encoding="utf-8")

        self.assertIn("IntegrationTestWidgetsFlutterBinding", source)
        self.assertIn("CloudAuthScope", source)
        self.assertIn("CloudAuthControllerImpl", source)
        self.assertIn("FirebaseIdentityToolkitHttp", source)
        self.assertIn("SECONDLOOP_MANAGED_PRO_EMAIL", source)
        self.assertIn("SECONDLOOP_MANAGED_PRO_PASSWORD", source)
        self.assertIn("SECONDLOOP_LIVE_MANAGED_PRO_EMAIL", source)
        self.assertIn("SECONDLOOP_LIVE_MANAGED_PRO_PASSWORD", source)
        self.assertIn("tester.enterText", source)
        self.assertIn("cloud_sign_in", source)
        self.assertIn("managedProSignIn", source)
        self.assertIn("RepaintBoundary", source)
        self.assertIn("RenderRepaintBoundary", source)
        self.assertIn("toImage", source)
        self.assertIn("ImageByteFormat.png", source)
        self.assertNotIn("takeScreenshot", source)
        self.assertNotIn("endOfFrame", source)
        self.assertIn("tester.tap", source)
        self.assertIn("AppShell", source)
        self.assertIsNone(re.search(r"\d{6,}@qq\.com", source))
        self.assertNotIn("SECONDLOOP_MANAGED_PRO_PASSWORD='", source)
        self.assertNotIn('SECONDLOOP_MANAGED_PRO_PASSWORD="', source)


if __name__ == "__main__":
    unittest.main()
