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

    def test_refresh_script_reuses_pre_commit_common_pub_cache_recovery(self) -> None:
        script = I18N_REFRESH_SCRIPT.read_text(encoding="utf-8")

        self.assertIn('source "${repo_root}/scripts/pre_commit_common.sh"', script)
        self.assertIn('run_with_pub_advisory_cache_retry "dart $*"', script)

    def test_analyze_script_supports_windows_local_fvm_batch_wrappers(self) -> None:
        script = I18N_ANALYZE_SCRIPT.read_text(encoding="utf-8")

        self.assertIn(".fvm/flutter_sdk/bin/flutter.bat", script)
        self.assertIn("scripts/run_fvm_tool.ps1", script)

    def test_analyze_script_reuses_pre_commit_common_helper(self) -> None:
        script = I18N_ANALYZE_SCRIPT.read_text(encoding="utf-8")

        self.assertIn('source "${repo_root}/scripts/pre_commit_common.sh"', script)

    def test_analyze_script_restores_package_config_before_running_slang(self) -> None:
        script = I18N_ANALYZE_SCRIPT.read_text(encoding="utf-8")

        self.assertIn("ensure_flutter_package_config", script)
        self.assertLess(
            script.find("ensure_flutter_package_config"),
            script.find("run_flutter_tool pub run slang analyze --full --outdir=.dart_tool/slang"),
        )

    def test_i18n_scripts_forward_the_current_working_directory_on_windows(self) -> None:
        refresh_script = I18N_REFRESH_SCRIPT.read_text(encoding="utf-8")
        analyze_script = I18N_ANALYZE_SCRIPT.read_text(encoding="utf-8")
        runner_script = WINDOWS_FVM_TOOL_RUNNER_SCRIPT.read_text(encoding="utf-8")

        self.assertIn('-WorkingDirectory "${native_working_dir}"', refresh_script)
        self.assertIn('-WorkingDirectory "${native_working_dir}"', analyze_script)
        self.assertIn("[string]$WorkingDirectory = ''", runner_script)
        self.assertIn("Resolve-ExecutionWorkingDirectory", runner_script)
        self.assertIn("Set-Location $executionWorkingDirectory", runner_script)

    def test_i18n_scripts_prefer_windows_batch_flutter_and_dart_wrappers(self) -> None:
        refresh_script = I18N_REFRESH_SCRIPT.read_text(encoding="utf-8")
        analyze_script = I18N_ANALYZE_SCRIPT.read_text(encoding="utf-8")

        self.assertLess(
            refresh_script.find(
                'if is_windows_env && [[ -f "${repo_root}/.fvm/flutter_sdk/bin/dart.bat" ]]; then'
            ),
            refresh_script.find(
                'if [[ -x "${repo_root}/.fvm/flutter_sdk/bin/dart" ]]; then'
            ),
        )
        self.assertLess(
            analyze_script.find(
                'if is_windows_env && [[ -f "${repo_root}/.fvm/flutter_sdk/bin/flutter.bat" ]]; then'
            ),
            analyze_script.find(
                'if [[ -x "${repo_root}/.fvm/flutter_sdk/bin/flutter" ]]; then'
            ),
        )

    def test_gitignore_does_not_keep_desktop_runtime_payload_exceptions(self) -> None:
        gitignore = GITIGNORE_FILE.read_text(encoding="utf-8")

        self.assertNotIn("assets/ocr/desktop_runtime", gitignore)


if __name__ == "__main__":
    unittest.main()
