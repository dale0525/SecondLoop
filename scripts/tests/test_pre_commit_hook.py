from __future__ import annotations

from pathlib import Path
import shutil
import subprocess
import tempfile
import textwrap
import unittest


REPO_ROOT = Path(__file__).resolve().parents[2]
PRE_COMMIT_HOOK = REPO_ROOT / ".githooks/pre-commit"
PRE_PUSH_HOOK = REPO_ROOT / ".githooks/pre-push"
VERIFY_CHANGED_SCRIPT = REPO_ROOT / "scripts/verify_changed.sh"
VERIFY_FULL_SCRIPT = REPO_ROOT / "scripts/verify_full.sh"
PRE_COMMIT_CHECK_MODE_SCRIPT = REPO_ROOT / "scripts/pre_commit_check_mode.sh"
PRE_COMMIT_COMMIT_MODE_SCRIPT = REPO_ROOT / "scripts/pre_commit_commit_mode.sh"
PRE_COMMIT_COMMON_SCRIPT = REPO_ROOT / "scripts/pre_commit_common.sh"
INSTALL_GIT_HOOKS_SCRIPT = REPO_ROOT / "scripts/install_git_hooks.sh"
RUN_BASH_PS1 = REPO_ROOT / "scripts/run_bash.ps1"


class PreCommitHookTests(unittest.TestCase):
    def _resolve_bash(self) -> str | None:
        bash = shutil.which("bash")
        if bash is not None and Path(bash).name.lower() == "bash.exe":
            bash_path = Path(bash)
            if "system32" not in bash_path.as_posix().lower():
                return bash

        git = shutil.which("git")
        if git is None:
            return bash

        git_bash = Path(git).resolve().parents[1] / "bin" / "bash.exe"
        if git_bash.exists():
            return str(git_bash)

        return bash

    def _run_collect_targeted_flutter_tests(self, staged_files: list[str]) -> list[str]:
        bash = self._resolve_bash()
        if bash is None:
            self.skipTest("bash is required to execute pre-commit hook function tests")
        rg = shutil.which("rg")
        if rg is None:
            self.skipTest("rg is required to execute pre-commit hook function tests")

        functions = PRE_COMMIT_COMMON_SCRIPT.read_text(encoding="utf-8").strip()

        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            helper_script = root / "pre_commit_common.sh"
            (root / "lib/core/cloud").mkdir(parents=True, exist_ok=True)
            (root / "test/core/cloud").mkdir(parents=True, exist_ok=True)
            (root / "test/cloud_account").mkdir(parents=True, exist_ok=True)
            helper_script.write_text(functions + "\n", encoding="utf-8")

            (root / "lib/core/cloud/firebase_identity_toolkit.dart").write_text(
                "void stub() {}\n",
                encoding="utf-8",
            )
            (root / "test/core/cloud/firebase_identity_toolkit_test.dart").write_text(
                textwrap.dedent(
                    """
                    import 'package:flutter_test/flutter_test.dart';

                    void main() {
                      test('mirror test', () {});
                    }
                    """
                ).strip()
                + "\n",
                encoding="utf-8",
            )
            (root / "test/cloud_account/firebase_identity_toolkit_usage_test.dart").write_text(
                textwrap.dedent(
                    """
                    import 'package:flutter_test/flutter_test.dart';
                    import 'package:secondloop/core/cloud/firebase_identity_toolkit.dart';

                    void main() {
                      test('package import usage', () {});
                    }
                    """
                ).strip()
                + "\n",
                encoding="utf-8",
            )

            (root / "test/support").mkdir(parents=True, exist_ok=True)
            (root / "test/support/firebase_identity_toolkit_test_support.dart").write_text(
                textwrap.dedent(
                    """
                    import 'package:secondloop/core/cloud/firebase_identity_toolkit.dart';

                    void helper() {
                      stub();
                    }
                    """
                ).strip()
                + "\n",
                encoding="utf-8",
            )

            staged_literal = " ".join(f'"{path}"' for path in staged_files)
            bash_script = textwrap.dedent(
                f"""
                set -euo pipefail
                export PATH="{Path(rg).parent.as_posix()}:$PATH"
                cd "{root.as_posix()}"
                repo_root="{root.as_posix()}"
                source "{helper_script.as_posix()}"
                staged_files=({staged_literal})
                collect_targeted_flutter_tests
                """
            )
            result = subprocess.run(
                [bash, "-lc", bash_script],
                check=True,
                capture_output=True,
                text=True,
            )

        filtered_lines = []
        for line in result.stdout.splitlines():
            stripped = line.strip().replace('\\', '/')
            if not stripped:
                continue
            if stripped.startswith('\x1b['):
                continue
            filtered_lines.append(stripped)

        return filtered_lines

    def test_pre_commit_hook_refreshes_i18n_when_locale_sources_change(self) -> None:
        script = PRE_COMMIT_COMMON_SCRIPT.read_text(encoding="utf-8")

        self.assertIn("scripts/run_i18n_refresh.sh", script)
        self.assertIn("slang.yaml", script)
        self.assertIn(".i18n.json", script)

    def test_pre_commit_hook_refreshes_i18n_when_locale_sources_are_deleted(self) -> None:
        script = PRE_COMMIT_COMMIT_MODE_SCRIPT.read_text(encoding="utf-8")

        self.assertIn("--diff-filter=ACMRD", script)

    def test_pre_commit_hook_skips_deleted_dart_files_during_formatting(self) -> None:
        script = PRE_COMMIT_COMMIT_MODE_SCRIPT.read_text(encoding="utf-8")

        self.assertIn('if [[ "${file}" == *.dart ]]; then', script)
        self.assertIn('if [[ -f "${file}" ]]; then', script)

    def test_pre_commit_hook_regenerates_missing_i18n_outputs_before_flutter_checks(self) -> None:
        script = PRE_COMMIT_COMMON_SCRIPT.read_text(encoding="utf-8")

        self.assertIn('ensure_i18n_generated()', script)
        self.assertIn('lib/i18n/strings.g.dart missing; regenerating i18n outputs.', script)
        self.assertIn('if [[ -f "lib/i18n/strings.g.dart" ]]; then', script)

    def test_pre_commit_hook_check_mode_avoids_double_i18n_refresh_when_outputs_were_missing(self) -> None:
        script = PRE_COMMIT_HOOK.read_text(encoding="utf-8") + "\n" + PRE_COMMIT_CHECK_MODE_SCRIPT.read_text(encoding="utf-8")

        self.assertIn('i18n_generated_now=0', script)
        self.assertNotIn('if [[ ${i18n_generated_now} -eq 0 ]]; then', script)
        self.assertIn('run_i18n_refresh_in_temp_copy', script)
        self.assertIn('ensure_temp_i18n_strings_for_analysis', script)
        self.assertIn('git diff --no-index --exit-code --', script)
        self.assertIn('"${repo_root}/lib/i18n"', script)
        self.assertIn('"${i18n_temp_repo}/lib/i18n"', script)
        self.assertNotIn('git diff --exit-code -- lib/i18n', script)

    def test_pre_commit_hook_stages_generated_i18n_outputs_in_normal_commit_flow(self) -> None:
        script = PRE_COMMIT_COMMIT_MODE_SCRIPT.read_text(encoding="utf-8")

        self.assertIn('if [[ ${i18n_generated_now} -ne 0 ]]; then', script)
        self.assertIn('git add -- lib/i18n/strings.g.dart', script)

    def test_pre_commit_hook_only_runs_i18n_analyze_for_i18n_source_changes(self) -> None:
        script = PRE_COMMIT_COMMIT_MODE_SCRIPT.read_text(encoding="utf-8")

        self.assertIn('if [[ ${run_i18n_refresh_needed} -ne 0 ]]; then', script)
        self.assertIn('run_i18n_analyze', script)

    def test_pre_commit_hook_targets_related_flutter_tests_for_lib_changes(self) -> None:
        script = PRE_COMMIT_COMMON_SCRIPT.read_text(encoding="utf-8") + "\n" + PRE_COMMIT_COMMIT_MODE_SCRIPT.read_text(encoding="utf-8")

        self.assertIn('lib/*.dart | lib/**/*.dart)', script)
        self.assertIn('package_import="package:secondloop/${file#lib/}"', script)
        self.assertIn('if ! command -v rg >/dev/null 2>&1; then', script)
        self.assertIn('rg -l --fixed-strings --glob', script)
        self.assertIn("' *_test.dart'".replace(' ', ''), script.replace(' ', ''))
        self.assertIn('"${package_import}" test integration_test', script)
        self.assertIn('while IFS= read -r candidate; do', script)
        self.assertIn('done < <(collect_related_flutter_tests_for_lib_file "${file}")', script)
        self.assertNotIn('mapfile -t related_targets', script)
        self.assertNotIn('readarray -t related_targets', script)
        self.assertIn('collect_targeted_flutter_tests()', script)

    def test_pre_commit_hook_runs_full_flutter_test_when_targets_cannot_be_mapped(self) -> None:
        script = PRE_COMMIT_COMMON_SCRIPT.read_text(encoding="utf-8") + "\n" + PRE_COMMIT_COMMIT_MODE_SCRIPT.read_text(encoding="utf-8")

        self.assertIn('if ! command -v rg >/dev/null 2>&1; then', script)
        self.assertIn('saw_unmapped_lib_change=1', script)
        self.assertIn('printf \'%s\\n\' "__FULL_SUITE__"', script)
        self.assertNotIn('run_flutter_tool test --concurrency=1', script)

    def test_pre_commit_hook_no_longer_runs_flutter_tests_in_normal_commit_flow(self) -> None:
        normal_commit_flow = PRE_COMMIT_COMMIT_MODE_SCRIPT.read_text(encoding="utf-8")

        self.assertNotIn('run_flutter_tool test --concurrency=1', normal_commit_flow)

    def test_pre_push_hook_runs_scoped_verification_by_default(self) -> None:
        script = PRE_PUSH_HOOK.read_text(encoding="utf-8")

        self.assertIn('bash scripts/run_full_ci_parallel.sh', script)
        self.assertIn('bash scripts/run_python_tooling_checks.sh', script)
        self.assertIn('tooling-scoped changes detected', script)
        self.assertIn('running full verification for pushed changes', script)
        self.assertIn('delete-only push detected', script)
        self.assertIn('scripts/tests/**/*.py', script)
        self.assertIn('tools/**/*.py', script)
        self.assertIn('is_gate_script_file()', script)

    def test_verify_changed_script_delegates_to_pre_commit_check_mode(self) -> None:
        script = VERIFY_CHANGED_SCRIPT.read_text(encoding="utf-8")

        self.assertIn('bash .githooks/pre-commit --check "$@"', script)
        self.assertIn(
            'powershell -NoProfile -ExecutionPolicy Bypass -File scripts/run_bash.ps1 .githooks/pre-commit --check "$@"',
            script,
        )
        self.assertNotIn('--check --ci', script)

    def test_verify_full_script_delegates_to_pre_commit_check_ci_mode(self) -> None:
        script = VERIFY_FULL_SCRIPT.read_text(encoding="utf-8")

        self.assertIn('bash .githooks/pre-commit --check --ci "$@"', script)
        self.assertIn(
            'powershell -NoProfile -ExecutionPolicy Bypass -File scripts/run_bash.ps1 .githooks/pre-commit --check --ci "$@"',
            script,
        )

    def test_pre_commit_hook_supports_skip_tests_in_check_mode(self) -> None:
        script = PRE_COMMIT_HOOK.read_text(encoding="utf-8")

        self.assertIn('--skip-tests', script)

    def test_pre_commit_common_exposes_periodic_progress_helper(self) -> None:
        common = PRE_COMMIT_COMMON_SCRIPT.read_text(encoding="utf-8")

        self.assertIn('run_with_periodic_status()', common)
        self.assertIn('SECONDLOOP_PRECOMMIT_PROGRESS_INTERVAL', common)
        self.assertIn('pre-commit: still running ${label}...', common)

    def test_pre_commit_check_mode_wraps_long_ci_steps_with_progress(self) -> None:
        check_mode = PRE_COMMIT_CHECK_MODE_SCRIPT.read_text(encoding="utf-8")

        self.assertIn(
            'run_with_periodic_status "flutter test" run_flutter_tool test --concurrency=1',
            check_mode,
        )

    def test_pre_commit_hook_delegates_check_mode_to_dedicated_script(self) -> None:
        script = PRE_COMMIT_HOOK.read_text(encoding="utf-8")

        self.assertIn('source "${repo_root}/scripts/pre_commit_check_mode.sh"', script)

    def test_pre_commit_hook_delegates_commit_mode_to_dedicated_script(self) -> None:
        script = PRE_COMMIT_HOOK.read_text(encoding="utf-8")

        self.assertIn('source "${repo_root}/scripts/pre_commit_commit_mode.sh"', script)

    def test_pre_commit_hook_only_targets_staged_test_files(self) -> None:
        script = PRE_COMMIT_COMMON_SCRIPT.read_text(encoding="utf-8") + "\n" + PRE_COMMIT_COMMIT_MODE_SCRIPT.read_text(encoding="utf-8")

        self.assertIn(
            'test/*_test.dart | test/**/*_test.dart | integration_test/*_test.dart | integration_test/**/*_test.dart)',
            script,
        )
        self.assertNotIn('base_name="$(basename "${file}" .dart)_test.dart"', script)
        self.assertNotIn('find test integration_test -type f -name "${base_name}"', script)

    def test_pre_commit_hook_includes_mirror_test_for_staged_lib_change(self) -> None:
        targets = self._run_collect_targeted_flutter_tests(
            ["lib/core/cloud/firebase_identity_toolkit.dart"]
        )

        self.assertEqual(
            targets,
            [
                "test/core/cloud/firebase_identity_toolkit_test.dart",
                "test/cloud_account/firebase_identity_toolkit_usage_test.dart",
            ],
        )


    def test_pre_commit_hook_excludes_support_dart_helpers_from_targeted_tests(
        self,
    ) -> None:
        targets = self._run_collect_targeted_flutter_tests(
            ["lib/core/cloud/firebase_identity_toolkit.dart"]
        )

        self.assertNotIn(
            "test/support/firebase_identity_toolkit_test_support.dart", targets
        )

    def test_pre_commit_hook_falls_back_to_full_flutter_suite_for_unmapped_lib_change(
        self,
    ) -> None:
        targets = self._run_collect_targeted_flutter_tests(
            ["lib/core/cloud/new_service.dart"]
        )

        self.assertEqual(targets, ["__FULL_SUITE__"])

    def test_pre_commit_hook_warns_when_i18n_refresh_stages_additional_locale_files(self) -> None:
        script = PRE_COMMIT_COMMON_SCRIPT.read_text(encoding="utf-8")

        self.assertIn('git diff --name-only -- lib/i18n', script)
        self.assertIn('pre-commit: auto-staged i18n refresh changes:', script)

    def test_pre_commit_hook_treats_deleted_dart_files_as_flutter_changes(self) -> None:
        script = PRE_COMMIT_COMMIT_MODE_SCRIPT.read_text(encoding="utf-8")

        self.assertIn('[[ "${file}" == *.dart ]]', script)
        self.assertNotIn('[[ "${file}" == *.dart && -f "${file}" ]]', script)

    def test_pre_commit_hook_falls_back_to_full_suite_for_deleted_lib_file(self) -> None:
        targets = self._run_collect_targeted_flutter_tests(
            ["lib/core/cloud/firebase_identity_toolkit.dart"]
        )

        self.assertNotEqual(targets, [])
        self.assertNotEqual(targets, ["__FULL_SUITE__"])

        script = PRE_COMMIT_COMMON_SCRIPT.read_text(encoding="utf-8")
        self.assertIn('if [[ ! -f "${file}" ]]; then', script)
        self.assertIn('printf \'%s\\n\' "__FULL_SUITE__"', script)

    def test_pre_commit_hook_supports_windows_local_fvm_batch_wrappers(self) -> None:
        script = PRE_COMMIT_HOOK.read_text(encoding="utf-8")

        self.assertIn('source "${repo_root}/scripts/pre_commit_common.sh"', script)
        self.assertNotIn(".fvm/flutter_sdk/bin/dart.bat", script)
        self.assertNotIn(".fvm/flutter_sdk/bin/flutter.bat", script)

    def test_pre_commit_common_recovers_from_pub_advisory_cache_crash(self) -> None:
        script = PRE_COMMIT_COMMON_SCRIPT.read_text(encoding="utf-8")

        self.assertIn("resolve_pub_cache_root()", script)
        self.assertIn("resolve_pub_log_path()", script)
        self.assertIn("pub_log_slice_mentions_advisory_cache_crash()", script)
        self.assertIn("clear_pub_advisory_cache()", script)
        self.assertIn("run_with_pub_advisory_cache_retry()", script)
        self.assertIn("HostedSource._getAdvisories.readAdvisoriesFromCache", script)
        self.assertIn("find \"${hosted_root}\" -type f -path '*/.cache/*-advisories.json'", script)
        self.assertIn("cleared pub advisory cache", script)

    def test_commit_mode_restores_flutter_package_config_after_stash(self) -> None:
        script = PRE_COMMIT_COMMON_SCRIPT.read_text(
            encoding="utf-8"
        ) + "\n" + PRE_COMMIT_COMMIT_MODE_SCRIPT.read_text(encoding="utf-8")

        self.assertIn('package_config_path="${repo_root}/.dart_tool/package_config.json"', script)
        self.assertIn('if [[ ! -f "${package_config_path}" ]]; then', script)
        self.assertIn('run_flutter_tool pub get', script)

    def test_commit_mode_auto_stages_pubspec_lock_after_restoring_package_config(self) -> None:
        script = PRE_COMMIT_COMMON_SCRIPT.read_text(
            encoding="utf-8"
        ) + "\n" + PRE_COMMIT_COMMIT_MODE_SCRIPT.read_text(encoding="utf-8")

        self.assertIn('git diff --quiet -- pubspec.lock', script)
        self.assertIn('git add -- pubspec.lock', script)

    def test_windows_pre_commit_prefers_batch_flutter_and_dart_wrappers(self) -> None:
        script = PRE_COMMIT_COMMON_SCRIPT.read_text(encoding="utf-8")

        flutter_bat_idx = script.find(
            'if is_windows_env && [[ -f "${repo_root}/.fvm/flutter_sdk/bin/flutter.bat" ]]; then'
        )
        flutter_shell_idx = script.find(
            'if [[ -x "${repo_root}/.fvm/flutter_sdk/bin/flutter" ]]; then'
        )
        dart_bat_idx = script.find(
            'if is_windows_env && [[ -f "${repo_root}/.fvm/flutter_sdk/bin/dart.bat" ]]; then'
        )
        dart_shell_idx = script.find(
            'if [[ -x "${repo_root}/.fvm/flutter_sdk/bin/dart" ]]; then'
        )

        self.assertNotEqual(-1, flutter_bat_idx)
        self.assertNotEqual(-1, flutter_shell_idx)
        self.assertLess(flutter_bat_idx, flutter_shell_idx)
        self.assertNotEqual(-1, dart_bat_idx)
        self.assertNotEqual(-1, dart_shell_idx)
        self.assertLess(dart_bat_idx, dart_shell_idx)

    def test_windows_pre_commit_forwards_current_working_directory_to_batch_runner(self) -> None:
        script = PRE_COMMIT_COMMON_SCRIPT.read_text(encoding="utf-8")

        self.assertIn('native_working_dir="$(to_native_windows_path "$(pwd)")"', script)
        self.assertIn('-WorkingDirectory "${native_working_dir}"', script)

    def test_install_git_hooks_configures_post_checkout_and_post_merge(self) -> None:
        script = INSTALL_GIT_HOOKS_SCRIPT.read_text(encoding="utf-8")

        self.assertIn(".githooks/post-checkout", script)
        self.assertIn(".githooks/post-merge", script)

    def test_windows_bash_launcher_exists_for_local_hook_entrypoints(self) -> None:
        self.assertTrue(RUN_BASH_PS1.exists())


if __name__ == "__main__":
    unittest.main()
