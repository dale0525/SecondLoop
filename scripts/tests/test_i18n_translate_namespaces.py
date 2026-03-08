from __future__ import annotations

from importlib.util import module_from_spec, spec_from_file_location
from pathlib import Path
from tempfile import TemporaryDirectory
import unittest


REPO_ROOT = Path(__file__).resolve().parents[2]
MODULE_PATH = REPO_ROOT / "tools/i18n_translate.py"
SPEC = spec_from_file_location("i18n_translate", MODULE_PATH)
assert SPEC and SPEC.loader
MODULE = module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)


class I18nTranslateNamespacesTests(unittest.TestCase):
    def test_discovers_namespace_pairs_for_directory_mode(self) -> None:
        with TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            (root / "attachments_en.i18n.json").write_text("{}\n", encoding="utf-8")
            (root / "attachments_zh_CN.i18n.json").write_text("{}\n", encoding="utf-8")
            (root / "settings_en.i18n.json").write_text("{}\n", encoding="utf-8")
            (root / "settings_zh_CN.i18n.json").write_text("{}\n", encoding="utf-8")

            pairs = MODULE.discover_translation_pairs(root)

        relative_pairs = {(source.name, target.name) for source, target in pairs}
        self.assertEqual(
            relative_pairs,
            {
                ("attachments_en.i18n.json", "attachments_zh_CN.i18n.json"),
                ("settings_en.i18n.json", "settings_zh_CN.i18n.json"),
            },
        )


if __name__ == "__main__":
    unittest.main()
