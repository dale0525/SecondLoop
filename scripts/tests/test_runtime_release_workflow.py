from __future__ import annotations

from pathlib import Path
import re
import unittest


REPO_ROOT = Path(__file__).resolve().parents[2]
DESKTOP_RUNTIME_WORKFLOW = REPO_ROOT / ".github/workflows/desktop-runtime-release.yml"
RELEASE_WORKFLOW = REPO_ROOT / ".github/workflows/release.yml"
RELEASE_RUNTIME_SCRIPT = REPO_ROOT / "scripts/release_runtime_tag.sh"


class RuntimeReleaseWorkflowTests(unittest.TestCase):
    def _desktop_runtime_workflow_text(self) -> str:
        return DESKTOP_RUNTIME_WORKFLOW.read_text(encoding="utf-8")

    def _release_workflow_text(self) -> str:
        return RELEASE_WORKFLOW.read_text(encoding="utf-8")

    def _release_runtime_script_text(self) -> str:
        return RELEASE_RUNTIME_SCRIPT.read_text(encoding="utf-8")

    def test_runtime_release_workflow_includes_mobile_runtime_job(self) -> None:
        workflow_text = self._desktop_runtime_workflow_text()

        self.assertIn("build-mobile-runtime-tag:", workflow_text)
        self.assertIn("scripts/prepare_mobile_runtime_payload.sh", workflow_text)
        self.assertIn("mobile-runtime-whisper-${runtime_version}.tar.gz", workflow_text)

    def test_release_runtime_usage_mentions_desktop_and_mobile_resources(self) -> None:
        script_text = self._release_runtime_script_text()

        self.assertIn("desktop + mobile runtime", script_text)

    def test_release_workflow_has_no_ios_publish_job(self) -> None:
        workflow_text = self._release_workflow_text()

        self.assertIsNone(re.search(r"^  ios:\s*$", workflow_text, flags=re.MULTILINE))


if __name__ == "__main__":
    unittest.main()
