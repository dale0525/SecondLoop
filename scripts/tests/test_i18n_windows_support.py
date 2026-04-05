from __future__ import annotations

from pathlib import Path
import unittest


REPO_ROOT = Path(__file__).resolve().parents[2]
I18N_REFRESH_SCRIPT = REPO_ROOT / "scripts/run_i18n_refresh.sh"
I18N_ANALYZE_SCRIPT = REPO_ROOT / "scripts/run_i18n_analyze.sh"
WINDOWS_FVM_TOOL_RUNNER_SCRIPT = REPO_ROOT / "scripts/run_fvm_tool.ps1"
GITIGNORE_FILE = REPO_ROOT / ".gitignore"


class I18nWindowsSupportTests(unittest.TestCase):
    def test_refresh_script_supports_windows_local_dart_batch_wrappers(self) -> None:
        script = I18N_REFRESH_SCRIPT.read_text(encoding="utf-8")

        self.assertIn(".fvm/flutter_sdk/bin/dart.bat", script)
        self.assertNotIn(".fvm/flutter_sdk/bin/flutter.bat", script)
        self.assertIn("scripts/run_fvm_tool.ps1", script)

    def test_refresh_script_uses_dart_run_slang_commands(self) -> None:
        script = I18N_REFRESH_SCRIPT.read_text(encoding="utf-8")

        self.assertIn("run_dart run slang:normalize\n", script)
        self.assertIn("run_dart run slang\n", script)
        self.assertNotIn("run_flutter pub run slang normalize", script)
        self.assertNotIn("run_flutter pub run slang", script)

    def test_refresh_script_does_not_keep_unused_flutter_helpers(self) -> None:
        script = I18N_REFRESH_SCRIPT.read_text(encoding="utf-8")

        self.assertNotIn("resolve_flutter_bin()", script)
        self.assertNotIn("run_flutter()", script)

    def test_analyze_script_supports_windows_local_fvm_batch_wrappers(self) -> None:
        script = I18N_ANALYZE_SCRIPT.read_text(encoding="utf-8")

        self.assertIn(".fvm/flutter_sdk/bin/flutter.bat", script)
        self.assertIn("scripts/run_fvm_tool.ps1", script)

    def test_i18n_scripts_forward_the_current_working_directory_on_windows(self) -> None:
        refresh_script = I18N_REFRESH_SCRIPT.read_text(encoding="utf-8")
        analyze_script = I18N_ANALYZE_SCRIPT.read_text(encoding="utf-8")
        runner_script = WINDOWS_FVM_TOOL_RUNNER_SCRIPT.read_text(encoding="utf-8")

        self.assertIn('-WorkingDirectory "${native_working_dir}"', refresh_script)
        self.assertIn('-WorkingDirectory "${native_working_dir}"', analyze_script)
        self.assertIn("[string]$WorkingDirectory = ''", runner_script)
        self.assertIn("Set-Location $WorkingDirectory", runner_script)

    def test_gitignore_excludes_temporary_desktop_runtime_directories(self) -> None:
        gitignore = GITIGNORE_FILE.read_text(encoding="utf-8")

        self.assertIn("assets/ocr/desktop_runtime.tmp-*/", gitignore)


if __name__ == "__main__":
    unittest.main()
