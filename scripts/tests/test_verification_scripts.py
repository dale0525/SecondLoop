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
        self.assertNotIn("ensure_i18n_generated", check_mode)

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
