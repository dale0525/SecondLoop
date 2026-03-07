from __future__ import annotations

from pathlib import Path
import unittest


REPO_ROOT = Path(__file__).resolve().parents[2]


class UpdateI18nCopyTests(unittest.TestCase):
    def test_windows_update_copy_references_manual_msi_flow_not_velopack(self) -> None:
        targets = [
            REPO_ROOT / "lib/i18n/strings_en.i18n.json",
            REPO_ROOT / "lib/i18n/strings_zh_CN.i18n.json",
            REPO_ROOT / "lib/i18n/strings.g.dart",
        ]

        for target in targets:
            text = target.read_text(encoding="utf-8")
            self.assertIn("MSI", text, f"{target} should mention MSI manual flow")
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


if __name__ == "__main__":
    unittest.main()
