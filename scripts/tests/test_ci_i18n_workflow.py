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
            'bash .githooks/pre-commit --check --flutter --skip-tests',
            workflow,
            'CI workflow must delegate Flutter i18n checks to the shared pre-commit engine',
        )
        self.assertIn(
            'bash scripts/run_flutter_test_shard.sh',
            workflow,
            'CI workflow must run Flutter test shards explicitly',
        )
        self.assertIn(
            'name: Flutter gate',
            workflow,
            'CI should describe the shared Flutter gate clearly',
        )
        self.assertIn(
            'name: Python tooling checks',
            workflow,
            'CI should run a lightweight tooling-only job for script changes',
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

    def test_ci_changes_filters_include_shared_verification_scripts(self) -> None:
        if not CI_WORKFLOW.exists():
            self.skipTest(f"CI workflow not found at {CI_WORKFLOW}")

        workflow = CI_WORKFLOW.read_text(encoding="utf-8")

        self.assertIn('"scripts/**"', workflow)
        self.assertIn('"!scripts/tests/**"', workflow)
        self.assertIn('"tools/**/*.py"', workflow)


if __name__ == "__main__":
    unittest.main()
