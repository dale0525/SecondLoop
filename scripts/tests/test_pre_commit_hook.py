from __future__ import annotations

from pathlib import Path
import unittest


REPO_ROOT = Path(__file__).resolve().parents[2]
PRE_COMMIT_HOOK = REPO_ROOT / ".githooks/pre-commit"
INSTALL_GIT_HOOKS_SCRIPT = REPO_ROOT / "scripts/install_git_hooks.sh"


class PreCommitHookTests(unittest.TestCase):
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

    def test_pre_commit_hook_only_runs_i18n_analyze_for_i18n_source_changes(self) -> None:
        script = PRE_COMMIT_HOOK.read_text(encoding="utf-8")

        self.assertIn('if [[ ${run_i18n_refresh_needed} -ne 0 ]]; then', script)
        self.assertIn('run_i18n_analyze', script)

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
