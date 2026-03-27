from __future__ import annotations

from pathlib import Path
import unittest


REPO_ROOT = Path(__file__).resolve().parents[2]
PIXI_TOML = REPO_ROOT / "pixi.toml"
CONTRIBUTING = REPO_ROOT / "CONTRIBUTING.md"


class VerificationScriptsTests(unittest.TestCase):
    def test_pixi_ci_documents_shared_full_verification_entrypoint(self) -> None:
        pixi = PIXI_TOML.read_text(encoding="utf-8")

        self.assertIn("scripts/verify_full.sh", pixi)

    def test_contributing_documents_fast_commit_and_full_push_flow(self) -> None:
        contributing = CONTRIBUTING.read_text(encoding="utf-8")

        self.assertIn("fast pre-commit + full pre-push verification", contributing)
        self.assertIn("same scope as `pre-push` / CI", contributing)


if __name__ == "__main__":
    unittest.main()
