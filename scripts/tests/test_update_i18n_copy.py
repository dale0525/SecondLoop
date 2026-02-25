from __future__ import annotations

from pathlib import Path
import unittest


REPO_ROOT = Path(__file__).resolve().parents[2]


class UpdateI18nCopyTests(unittest.TestCase):
    def test_windows_update_copy_does_not_reference_msi(self) -> None:
        targets = [
            REPO_ROOT / "lib/i18n/strings_en.i18n.json",
            REPO_ROOT / "lib/i18n/strings_zh_CN.i18n.json",
            REPO_ROOT / "lib/i18n/strings.g.dart",
        ]

        for target in targets:
            text = target.read_text(encoding="utf-8")
            self.assertNotIn("MSI", text, f"{target} still contains MSI copy")


if __name__ == "__main__":
    unittest.main()
