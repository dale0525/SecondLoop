from __future__ import annotations

from pathlib import Path
import unittest


class ReleasePreflightTlsTests(unittest.TestCase):
    def _script_text(self) -> str:
        script_path = Path(__file__).resolve().parents[2] / "scripts/release_preflight.sh"
        return script_path.read_text(encoding="utf-8")

    def test_preflight_supports_insecure_tls_opt_in(self) -> None:
        script_text = self._script_text()

        self.assertIn("RELEASE_PREFLIGHT_INSECURE_SKIP_VERIFY", script_text)
        self.assertIn("--insecure-skip-verify", script_text)
        self.assertIn("ssl._create_unverified_context()", script_text)


if __name__ == "__main__":
    unittest.main()
