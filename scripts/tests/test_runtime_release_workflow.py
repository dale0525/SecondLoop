from __future__ import annotations

from pathlib import Path
import re
import unittest


REPO_ROOT = Path(__file__).resolve().parents[2]
DESKTOP_RUNTIME_WORKFLOW = REPO_ROOT / ".github/workflows/desktop-runtime-release.yml"
DESKTOP_PACKAGE_WORKFLOW = REPO_ROOT / ".github/workflows/desktop-package.yml"
RELEASE_WORKFLOW = REPO_ROOT / ".github/workflows/release.yml"
RELEASE_RUNTIME_SCRIPT = REPO_ROOT / "scripts/release_runtime_tag.sh"
DESKTOP_RUNTIME_SCRIPTS = [
    REPO_ROOT / "scripts/assemble_desktop_runtime.sh",
    REPO_ROOT / "scripts/build_desktop_runtime.sh",
    REPO_ROOT / "scripts/prepare_desktop_runtime_payload.sh",
    REPO_ROOT / "scripts/prepare_mobile_runtime_payload.sh",
]
DESKTOP_RUNTIME_TOOLS = [
    REPO_ROOT / "tools/prepare_desktop_runtime.dart",
    REPO_ROOT / "tools/prepare_desktop_runtime_hash_lib.dart",
    REPO_ROOT / "tools/sync_desktop_runtime_to_appdir.dart",
]


class RuntimeReleaseWorkflowTests(unittest.TestCase):
    def _release_workflow_text(self) -> str:
        return RELEASE_WORKFLOW.read_text(encoding="utf-8")

    def _extract_release_publish_step(self, workflow_text: str) -> str:
        publish_step_start = "- name: Publish GitHub Release"
        publish_step_end = "- name: Summarize GitHub Release publication"

        self.assertIn(publish_step_start, workflow_text)
        publish_step = workflow_text.split(publish_step_start, maxsplit=1)[1]

        self.assertIn(publish_step_end, publish_step)
        return publish_step.split(publish_step_end, maxsplit=1)[0]

    def test_desktop_runtime_release_workflow_is_removed(self) -> None:
        self.assertFalse(DESKTOP_RUNTIME_WORKFLOW.exists())

    def test_desktop_package_workflow_is_removed(self) -> None:
        self.assertFalse(DESKTOP_PACKAGE_WORKFLOW.exists())

    def test_runtime_tag_helper_is_removed(self) -> None:
        self.assertFalse(RELEASE_RUNTIME_SCRIPT.exists())

    def test_desktop_runtime_payload_scripts_are_removed(self) -> None:
        for script in DESKTOP_RUNTIME_SCRIPTS:
            with self.subTest(script=script.relative_to(REPO_ROOT)):
                self.assertFalse(script.exists())

    def test_desktop_runtime_tools_are_removed(self) -> None:
        for tool in DESKTOP_RUNTIME_TOOLS:
            with self.subTest(tool=tool.relative_to(REPO_ROOT)):
                self.assertFalse(tool.exists())

    def test_release_workflow_has_no_ios_publish_job(self) -> None:
        workflow_text = self._release_workflow_text()

        self.assertIsNone(re.search(r"^  ios:\s*$", workflow_text, flags=re.MULTILINE))

    def test_release_workflow_windows_publish_path_includes_msi_and_velopack(self) -> None:
        workflow_text = self._release_workflow_text()

        self.assertIn("name: Package MSI", workflow_text)
        self.assertIn("name: Package Velopack", workflow_text)
        self.assertIn("dist/SecondLoop-win.msi", workflow_text)
        self.assertIn("dist/*.nupkg", workflow_text)
        self.assertIn("scripts/package_windows_velopack.ps1", workflow_text)

    def test_release_workflow_publishes_latest_manifest_assets(self) -> None:
        workflow_text = self._release_workflow_text()

        self.assertIn("tools/generate_update_manifest.dart", workflow_text)
        self.assertIn("dist/latest.json", workflow_text)
        self.assertIn("dist/latest.json.sig", workflow_text)
        self.assertIn("SecondLoop-macos-${safe_ref_name}.app.tar.gz", workflow_text)
        self.assertIn('[armeabi-v7a]="build/app/outputs/flutter-apk/app-armeabi-v7a-release.apk"', workflow_text)
        self.assertIn('[arm64-v8a]="build/app/outputs/flutter-apk/app-arm64-v8a-release.apk"', workflow_text)
        self.assertIn('[universal]="build/app/outputs/flutter-apk/app-release.apk"', workflow_text)
        self.assertIn('dist/SecondLoop-android-${abi}-${safe_ref_name}.apk', workflow_text)

    def test_release_workflow_limits_linux_tarball_publish_glob(self) -> None:
        workflow_text = self._release_workflow_text()
        publish_step = self._extract_release_publish_step(workflow_text)

        self.assertIn("dist/SecondLoop-linux-*.tar.gz", publish_step)
        self.assertNotIn("dist/*.tar.gz", publish_step)

    def test_release_workflow_publish_step_extraction_fails_with_assertion(self) -> None:
        workflow_text = "name: Release\n  publish:\n    steps:\n      - name: Something Else\n"

        with self.assertRaisesRegex(AssertionError, "Publish GitHub Release"):
            self._extract_release_publish_step(workflow_text)

    def test_release_workflow_publish_step_extraction_fails_when_end_sentinel_missing(self) -> None:
        workflow_text = (
            "- name: Publish GitHub Release\n"
            "      files: |\n"
            "        dist/SecondLoop-linux-*.tar.gz\n"
            "- name: Some Other Step\n"
        )

        with self.assertRaisesRegex(AssertionError, "Summarize GitHub Release publication"):
            self._extract_release_publish_step(workflow_text)


if __name__ == "__main__":
    unittest.main()
