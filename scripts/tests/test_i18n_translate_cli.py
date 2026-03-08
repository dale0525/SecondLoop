from __future__ import annotations

from contextlib import redirect_stderr
from importlib.util import module_from_spec, spec_from_file_location
import io
from pathlib import Path
import sys
import tomllib
import unittest
from unittest.mock import patch


REPO_ROOT = Path(__file__).resolve().parents[2]
MODULE_PATH = REPO_ROOT / "tools/i18n_translate.py"
PIXI_TOML = REPO_ROOT / "pixi.toml"
SPEC = spec_from_file_location("i18n_translate_cli", MODULE_PATH)
assert SPEC and SPEC.loader
MODULE = module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)


class I18nTranslateCliTests(unittest.TestCase):
    def test_pixi_i18n_translate_task_does_not_force_directory_mode(self) -> None:
        with PIXI_TOML.open("rb") as fh:
            pixi_config = tomllib.load(fh)

        translate_task = pixi_config["tasks"]["i18n-translate"]
        self.assertEqual(
            translate_task["cmd"],
            "python tools/i18n_translate.py {{ command_args }}",
        )

    def test_cli_defaults_to_directory_mode_when_no_paths_are_provided(self) -> None:
        with patch.object(sys, "argv", ["i18n_translate.py"]):
            with patch.object(MODULE, "discover_translation_pairs", return_value=[]) as discover_pairs:
                with patch.object(MODULE, "translate_pair") as translate_pair:
                    exit_code = MODULE.main()

        self.assertEqual(exit_code, 0)
        discover_pairs.assert_called_once_with(
            Path("lib/i18n"),
            source_locale="en",
            target_locale="zh_CN",
        )
        translate_pair.assert_not_called()

    def test_cli_rejects_mixing_directory_and_single_file_modes(self) -> None:
        stderr = io.StringIO()
        argv = [
            "i18n_translate.py",
            "--input-directory",
            "lib/i18n",
            "--source",
            "lib/i18n/chat_en.i18n.json",
            "--target",
            "lib/i18n/chat_zh_CN.i18n.json",
        ]

        with patch.object(sys, "argv", argv):
            with redirect_stderr(stderr):
                with self.assertRaises(SystemExit) as exc:
                    MODULE.main()

        self.assertEqual(exc.exception.code, 2)
        self.assertIn(
            "--input-directory cannot be combined with --source/--target",
            stderr.getvalue(),
        )


if __name__ == "__main__":
    unittest.main()
