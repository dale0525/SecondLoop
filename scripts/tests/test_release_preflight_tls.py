from __future__ import annotations

from pathlib import Path
import unittest


class ReleasePreflightTests(unittest.TestCase):
    def _script_text(self) -> str:
        script_path = Path(__file__).resolve().parents[2] / "scripts/release_preflight.sh"
        return script_path.read_text(encoding="utf-8")

    def test_preflight_no_longer_downloads_desktop_runtime_payloads(self) -> None:
        script_text = self._script_text()

        self.assertNotIn("RELEASE_PREFLIGHT_INSECURE_SKIP_VERIFY", script_text)
        self.assertNotIn("--insecure-skip-verify", script_text)
        self.assertNotIn("ssl._create_unverified_context()", script_text)
        self.assertNotIn("desktop-runtime", script_text)
        self.assertNotIn("resolved_runtime_tag", script_text)
        self.assertIn("file_selector_linux", script_text)
        self.assertIn("url_launcher_linux", script_text)


if __name__ == "__main__":
    unittest.main()
