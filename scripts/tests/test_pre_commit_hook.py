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

    def test_install_git_hooks_configures_post_checkout_and_post_merge(self) -> None:
        script = INSTALL_GIT_HOOKS_SCRIPT.read_text(encoding="utf-8")

        self.assertIn(".githooks/post-checkout", script)
        self.assertIn(".githooks/post-merge", script)


if __name__ == "__main__":
    unittest.main()
