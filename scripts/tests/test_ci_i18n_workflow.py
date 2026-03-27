from __future__ import annotations

from pathlib import Path
import unittest


REPO_ROOT = Path(__file__).resolve().parents[2]
CI_WORKFLOW = REPO_ROOT / ".github/workflows/ci.yml"


class CiI18nWorkflowTests(unittest.TestCase):
    def test_flutter_ci_relies_on_pre_commit_for_i18n_checks(self) -> None:
        if not CI_WORKFLOW.exists():
            self.skipTest(f"CI workflow not found at {CI_WORKFLOW}")

        workflow = CI_WORKFLOW.read_text(encoding="utf-8")

        self.assertIn(
            'bash scripts/verify_full.sh --flutter',
            workflow,
            'CI workflow must delegate Flutter i18n checks to the pre-commit hook',
        )
        self.assertIn(
            'bash scripts/verify_full.sh --rust',
            workflow,
            'CI workflow must delegate Rust full verification through the shared full-check script',
        )
        self.assertIn(
            'name: Full Flutter verification',
            workflow,
            'CI should describe the shared full verification gate clearly',
        )
        self.assertIn(
            'name: Full Rust verification',
            workflow,
            'CI should describe the shared full verification gate clearly',
        )
        self.assertNotIn(
            'name: Refresh i18n generated files',
            workflow,
            'CI workflow should not run a duplicate standalone i18n refresh step',
        )
        self.assertNotIn(
            'name: Analyze i18n keys',
            workflow,
            'CI workflow should not run a duplicate standalone i18n analyze step',
        )


if __name__ == "__main__":
    unittest.main()
