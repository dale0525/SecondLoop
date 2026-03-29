from __future__ import annotations

from pathlib import Path
import unittest


REPO_ROOT = Path(__file__).resolve().parents[2]
PIXI_TOML = REPO_ROOT / "pixi.toml"
CONTRIBUTING = REPO_ROOT / "CONTRIBUTING.md"
RUN_BASH_PS1 = REPO_ROOT / "scripts/run_bash.ps1"


class VerificationScriptsTests(unittest.TestCase):
    def test_pixi_ci_documents_shared_full_verification_entrypoint(self) -> None:
        pixi = PIXI_TOML.read_text(encoding="utf-8")

        self.assertIn("scripts/verify_full.sh", pixi)

    def test_windows_pixi_ci_uses_powershell_bash_launcher(self) -> None:
        pixi = PIXI_TOML.read_text(encoding="utf-8")

        self.assertTrue(RUN_BASH_PS1.exists())
        self.assertIn(
            'ci = "powershell -NoProfile -ExecutionPolicy Bypass -File scripts/run_bash.ps1 scripts/verify_full.sh"',
            pixi,
        )

    def test_contributing_documents_fast_commit_and_full_push_flow(self) -> None:
        contributing = CONTRIBUTING.read_text(encoding="utf-8")

        self.assertIn("fast pre-commit + full pre-push verification", contributing)
        self.assertIn("same scope as `pre-push` / CI", contributing)
        self.assertIn("Check-only local gate", contributing)

    def test_check_mode_does_not_refresh_i18n_outputs(self) -> None:
        check_mode = (REPO_ROOT / "scripts/pre_commit_check_mode.sh").read_text(
            encoding="utf-8"
        )

        self.assertIn("run_i18n_refresh_in_temp_copy", check_mode)
        self.assertIn("git diff --no-index --exit-code --", check_mode)
        self.assertIn('"${repo_root}/lib/i18n"', check_mode)
        self.assertIn('"${temp_repo}/lib/i18n"', check_mode)
        self.assertIn('lib/i18n/strings.g.dart is missing', check_mode)
        self.assertIn('SECONDLOOP_I18N_DART_BIN', check_mode)
        self.assertIn('SECONDLOOP_I18N_FLUTTER_BIN', check_mode)
        self.assertIn('package_config.json', check_mode)
        self.assertNotIn('cp -R "${repo_root}/.dart_tool"', check_mode)
        self.assertIn('Fix locally with: pixi run ci', check_mode)
        self.assertNotIn("ensure_i18n_generated", check_mode)

    def test_check_mode_disables_worktree_writes_for_tooling_setup(self) -> None:
        check_mode = (REPO_ROOT / "scripts/pre_commit_check_mode.sh").read_text(
            encoding="utf-8"
        )
        pre_commit = (REPO_ROOT / ".githooks/pre-commit").read_text(
            encoding="utf-8"
        )
        common = (REPO_ROOT / "scripts/pre_commit_common.sh").read_text(
            encoding="utf-8"
        )

        self.assertIn('SECONDLOOP_PRECOMMIT_ALLOW_WORKTREE_WRITES=0', check_mode)
        self.assertIn('precommit_allow_worktree_writes=0', check_mode)
        self.assertIn(
            'if (( check_mode )); then\n  export SECONDLOOP_PRECOMMIT_ALLOW_WORKTREE_WRITES=0\nfi',
            pre_commit,
        )
        self.assertIn('precommit_allow_worktree_writes', common)
        self.assertIn('mktemp -d -t secondloop_libclang', common)

    def test_check_mode_temp_i18n_copy_includes_local_path_dependencies(self) -> None:
        check_mode = (REPO_ROOT / "scripts/pre_commit_check_mode.sh").read_text(
            encoding="utf-8"
        )

        self.assertIn("copy_local_path_dependencies_to_temp_repo", check_mode)
        self.assertIn('cp -R "${repo_root}/${normalized_path}"', check_mode)
        self.assertIn('path:', (REPO_ROOT / "pubspec.yaml").read_text(encoding="utf-8"))

    def test_verify_changed_uses_non_mutating_check_mode(self) -> None:
        verify_changed = (REPO_ROOT / "scripts/verify_changed.sh").read_text(
            encoding="utf-8"
        )

        self.assertIn("bash .githooks/pre-commit --check", verify_changed)

    def test_windows_pixi_install_hooks_uses_powershell_bash_launcher(self) -> None:
        pixi = PIXI_TOML.read_text(encoding="utf-8")

        self.assertTrue(RUN_BASH_PS1.exists())
        self.assertIn("scripts/run_bash.ps1 scripts/install_git_hooks.sh", pixi)


if __name__ == "__main__":
    unittest.main()
