from __future__ import annotations

from pathlib import Path
import unittest


REPO_ROOT = Path(__file__).resolve().parents[2]


class UpdateI18nCopyTests(unittest.TestCase):
    def test_update_copy_avoids_setup_installer_wording(self) -> None:
        targets = sorted((REPO_ROOT / "lib/i18n").glob("*.i18n.json"))

        for target in targets:
            text = target.read_text(encoding="utf-8")
            self.assertNotIn("Velopack", text, f"{target} still contains Velopack copy")
            self.assertNotIn(
                "Setup installer",
                text,
                f"{target} still contains Setup installer copy",
            )
            self.assertNotIn(
                "SecondLoop-win-Setup.exe",
                text,
                f"{target} still contains Setup.exe copy",
            )

    def test_update_copy_mentions_in_app_auto_update_or_manual_fallback(self) -> None:
        targets = sorted((REPO_ROOT / "lib/i18n").glob("*.i18n.json"))

        expected_phrases = [
            "auto-update and restart",
            "应用内更新",
            "manual download",
            "手动下载安装",
        ]

        matching_targets = [
            target
            for target in targets
            if any(phrase in target.read_text(encoding="utf-8") for phrase in expected_phrases)
        ]
        self.assertTrue(
            matching_targets,
            "expected locale source files to mention in-app update or manual fallback",
        )


if __name__ == "__main__":
    unittest.main()
