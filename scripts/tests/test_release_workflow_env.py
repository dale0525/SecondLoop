from __future__ import annotations

from pathlib import Path
import unittest


class ReleaseWorkflowEnvTests(unittest.TestCase):
    def _publish_env_keys(self) -> set[str]:
        workflow_path = Path(__file__).resolve().parents[2] / ".github/workflows/release.yml"
        lines = workflow_path.read_text(encoding="utf-8").splitlines()

        in_publish = False
        in_env = False
        keys: set[str] = set()

        for line in lines:
            if not in_publish:
                if line.startswith("  publish:"):
                    in_publish = True
                continue

            if in_publish and line.startswith("  ") and not line.startswith("    "):
                break

            if not in_env:
                if line.startswith("    env:"):
                    in_env = True
                continue

            if line.startswith("      "):
                stripped = line.strip()
                if not stripped or stripped.startswith("#"):
                    continue
                key, sep, _value = stripped.partition(":")
                if sep:
                    keys.add(key.strip())
                continue

            if line.startswith("    "):
                break

        return keys

    def test_publish_job_forwards_extended_llm_env(self) -> None:
        env_keys = self._publish_env_keys()
        self.assertIn("RELEASE_LLM_API_KEY", env_keys)
        self.assertIn("RELEASE_LLM_MODEL", env_keys)
        self.assertIn("RELEASE_LLM_BASE_URL", env_keys)

        self.assertIn("RELEASE_LLM_ENDPOINT", env_keys)
        self.assertIn("RELEASE_LLM_AUTH_HEADER", env_keys)
        self.assertIn("RELEASE_LLM_AUTH_SCHEME", env_keys)


if __name__ == "__main__":
    unittest.main()
