from __future__ import annotations

from pathlib import Path
import unittest


REPO_ROOT = Path(__file__).resolve().parents[2]
CI_WORKFLOW = REPO_ROOT / ".github/workflows/ci.yml"


class CiI18nWorkflowTests(unittest.TestCase):
    def test_flutter_ci_relies_on_pre_commit_for_i18n_checks(self) -> None:
        workflow = CI_WORKFLOW.read_text(encoding="utf-8")

        self.assertIn('bash .githooks/pre-commit --check --ci --flutter', workflow)
        self.assertNotIn('name: Refresh i18n generated files', workflow)
        self.assertNotIn('name: Analyze i18n keys', workflow)


if __name__ == "__main__":
    unittest.main()
