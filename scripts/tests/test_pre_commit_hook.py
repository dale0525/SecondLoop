from __future__ import annotations

from pathlib import Path
import shutil
import subprocess
import tempfile
import textwrap
import unittest


REPO_ROOT = Path(__file__).resolve().parents[2]
PRE_COMMIT_HOOK = REPO_ROOT / ".githooks/pre-commit"
INSTALL_GIT_HOOKS_SCRIPT = REPO_ROOT / "scripts/install_git_hooks.sh"


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

        script = PRE_COMMIT_HOOK.read_text(encoding="utf-8")
        start = script.index("append_unique_path() {")
        end = script.index("if (( check_mode )); then")
        functions = script[start:end].strip()

        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            (root / "lib/core/cloud").mkdir(parents=True, exist_ok=True)
            (root / "test/core/cloud").mkdir(parents=True, exist_ok=True)
            (root / "test/cloud_account").mkdir(parents=True, exist_ok=True)

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

            staged_literal = " ".join(f'"{path}"' for path in staged_files)
            bash_script = textwrap.dedent(
                f"""
                set -euo pipefail
                export PATH="{Path(rg).parent.as_posix()}:$PATH"
                cd "{root.as_posix()}"
                {functions}
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

        return [line.strip().replace('\\', '/') for line in result.stdout.splitlines() if line.strip()]

    def test_pre_commit_hook_supports_pixi_windows_cargo_path(self) -> None:
        script = PRE_COMMIT_HOOK.read_text(encoding="utf-8")

        self.assertIn(".pixi/envs/default/Library/bin/cargo.exe", script)
        self.assertIn(".pixi/envs/default/bin/cargo", script)

    def test_pre_commit_hook_resolves_windows_libclang_path(self) -> None:
        script = PRE_COMMIT_HOOK.read_text(encoding="utf-8")

        self.assertIn(".pixi/envs/default/Library/bin", script)
        self.assertIn("libclang-*.dll", script)
        self.assertIn(".tool/libclang", script)
        self.assertIn("LIBCLANG_PATH", script)

    def test_pre_commit_hook_resolves_windows_vulkan_sdk_path(self) -> None:
        script = PRE_COMMIT_HOOK.read_text(encoding="utf-8")

        self.assertIn(".tool/vulkan-sdk", script)
        self.assertIn("1.4.309.0", script)
        self.assertIn("VULKAN_SDK", script)
        self.assertIn("vulkan-1.lib", script)
        self.assertIn("CARGO_TARGET_DIR", script)
        self.assertIn("CARGOKIT_TARGET_TEMP_DIR", script)
        self.assertIn("CARGOKIT_TOOL_TEMP_DIR", script)
        self.assertIn("CMAKE_GENERATOR", script)
        self.assertIn("Ninja", script)

    def test_pre_commit_hook_refreshes_i18n_when_locale_sources_change(self) -> None:
        script = PRE_COMMIT_HOOK.read_text(encoding="utf-8")

        self.assertIn("scripts/run_i18n_refresh.sh", script)
        self.assertIn("slang.yaml", script)
        self.assertIn(".i18n.json", script)

    def test_pre_commit_hook_refreshes_i18n_when_locale_sources_are_deleted(self) -> None:
        script = PRE_COMMIT_HOOK.read_text(encoding="utf-8")

        self.assertIn("--diff-filter=ACMRD", script)

    def test_pre_commit_hook_skips_deleted_dart_files_during_formatting(self) -> None:
        script = PRE_COMMIT_HOOK.read_text(encoding="utf-8")

        self.assertIn('if [[ "${file}" == *.dart && -f "${file}" ]]; then', script)

    def test_pre_commit_hook_regenerates_missing_i18n_outputs_before_flutter_checks(self) -> None:
        script = PRE_COMMIT_HOOK.read_text(encoding="utf-8")

        self.assertIn('ensure_i18n_generated()', script)
        self.assertIn('lib/i18n/strings.g.dart missing; regenerating i18n outputs.', script)
        self.assertIn('if [[ -f "lib/i18n/strings.g.dart" ]]; then', script)

    def test_pre_commit_hook_check_mode_avoids_double_i18n_refresh_when_outputs_were_missing(self) -> None:
        script = PRE_COMMIT_HOOK.read_text(encoding="utf-8")

        self.assertIn('i18n_generated_now=0', script)
        self.assertIn('if [[ ${i18n_generated_now} -eq 0 ]]; then', script)

    def test_pre_commit_hook_stages_generated_i18n_outputs_in_normal_commit_flow(self) -> None:
        script = PRE_COMMIT_HOOK.read_text(encoding="utf-8")

        self.assertIn('if [[ ${i18n_generated_now} -ne 0 ]]; then', script)
        self.assertIn('git add -- lib/i18n/strings.g.dart', script)

    def test_pre_commit_hook_only_runs_i18n_analyze_for_i18n_source_changes(self) -> None:
        script = PRE_COMMIT_HOOK.read_text(encoding="utf-8")

        self.assertIn('if [[ ${run_i18n_refresh_needed} -ne 0 ]]; then', script)
        self.assertIn('run_i18n_analyze', script)

    def test_pre_commit_hook_targets_related_flutter_tests_for_lib_changes(self) -> None:
        script = PRE_COMMIT_HOOK.read_text(encoding="utf-8")

        self.assertIn('lib/*.dart | lib/**/*.dart)', script)
        self.assertIn('package_import="package:secondloop/${file#lib/}"', script)
        self.assertIn('rg -l --fixed-strings "${package_import}" test integration_test', script)
        self.assertIn('while IFS= read -r candidate; do', script)
        self.assertIn('done < <(collect_related_flutter_tests_for_lib_file "${file}")', script)
        self.assertNotIn('mapfile -t related_targets', script)
        self.assertNotIn('readarray -t related_targets', script)
        self.assertIn('if [[ ${#flutter_test_targets[@]} -eq 0 ]]; then', script)
        self.assertIn('run_flutter_tool test --concurrency=1', script)

    def test_pre_commit_hook_only_targets_staged_test_files(self) -> None:
        script = PRE_COMMIT_HOOK.read_text(encoding="utf-8")

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

    def test_pre_commit_hook_warns_when_i18n_refresh_stages_additional_locale_files(self) -> None:
        script = PRE_COMMIT_HOOK.read_text(encoding="utf-8")

        self.assertIn('git diff --name-only -- lib/i18n', script)
        self.assertIn('pre-commit: auto-staged i18n refresh changes:', script)

    def test_pre_commit_hook_quotes_pixi_cargo_fmt_suggestion(self) -> None:
        script = PRE_COMMIT_HOOK.read_text(encoding="utf-8")

        self.assertIn(
            r'echo "Fix locally with: pixi run cargo fmt \"--manifest-path rust/Cargo.toml --all\"" >&2',
            script,
        )

    def test_pre_commit_hook_supports_windows_local_fvm_batch_wrappers(self) -> None:
        script = PRE_COMMIT_HOOK.read_text(encoding="utf-8")

        self.assertIn(".fvm/flutter_sdk/bin/dart.bat", script)
        self.assertIn(".fvm/flutter_sdk/bin/flutter.bat", script)
        self.assertIn("scripts/run_fvm_tool.ps1", script)

    def test_install_git_hooks_configures_post_checkout_and_post_merge(self) -> None:
        script = INSTALL_GIT_HOOKS_SCRIPT.read_text(encoding="utf-8")

        self.assertIn(".githooks/post-checkout", script)
        self.assertIn(".githooks/post-merge", script)


if __name__ == "__main__":
    unittest.main()
