from __future__ import annotations

from pathlib import Path
import unittest


REPO_ROOT = Path(__file__).resolve().parents[2]
I18N_REFRESH_SCRIPT = REPO_ROOT / "scripts/run_i18n_refresh.sh"
I18N_ANALYZE_SCRIPT = REPO_ROOT / "scripts/run_i18n_analyze.sh"


class I18nWindowsSupportTests(unittest.TestCase):
    def test_refresh_script_supports_windows_local_fvm_batch_wrappers(self) -> None:
        script = I18N_REFRESH_SCRIPT.read_text(encoding="utf-8")

        self.assertIn(".fvm/flutter_sdk/bin/dart.bat", script)
        self.assertIn(".fvm/flutter_sdk/bin/flutter.bat", script)
        self.assertIn("scripts/run_fvm_tool.ps1", script)

    def test_refresh_script_uses_dart_run_slang_commands(self) -> None:
        script = I18N_REFRESH_SCRIPT.read_text(encoding="utf-8")

        self.assertIn("run_dart run slang:normalize", script)
        self.assertIn("run_dart run slang", script)
        self.assertNotIn("run_flutter pub run slang normalize", script)
        self.assertNotIn("run_flutter pub run slang", script)

    def test_analyze_script_supports_windows_local_fvm_batch_wrappers(self) -> None:
        script = I18N_ANALYZE_SCRIPT.read_text(encoding="utf-8")

        self.assertIn(".fvm/flutter_sdk/bin/flutter.bat", script)
        self.assertIn("scripts/run_fvm_tool.ps1", script)


if __name__ == "__main__":
    unittest.main()
