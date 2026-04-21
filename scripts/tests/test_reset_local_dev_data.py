from __future__ import annotations

from importlib.util import module_from_spec, spec_from_file_location
from pathlib import Path
import shutil
import tempfile
import unittest


REPO_ROOT = Path(__file__).resolve().parents[2]
SCRIPT_PATH = REPO_ROOT / "scripts/reset_local_dev_data.py"


def _load_module():
    spec = spec_from_file_location("reset_local_dev_data", SCRIPT_PATH)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"Unable to load script at {SCRIPT_PATH}")
    module = module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class ResetLocalDevDataTests(unittest.TestCase):
    def test_resolve_app_data_dir_for_macos_uses_bundle_id_under_application_support(
        self,
    ) -> None:
        module = _load_module()

        resolved = module.resolve_app_data_dir("Darwin", {"HOME": "/Users/dev"})

        self.assertEqual(
            resolved,
            "/Users/dev/Library/Application Support/com.secondloop.secondloopdev",
        )

    def test_resolve_app_data_dir_for_linux_prefers_xdg_data_home(self) -> None:
        module = _load_module()

        resolved = module.resolve_app_data_dir(
            "Linux",
            {
                "XDG_DATA_HOME": "/tmp/xdg-data",
                "HOME": "/home/dev",
            },
        )

        self.assertEqual(
            resolved,
            "/tmp/xdg-data/com.secondloop.secondloopdev",
        )

    def test_resolve_app_data_dir_for_linux_falls_back_to_home_local_share(self) -> None:
        module = _load_module()

        resolved = module.resolve_app_data_dir("Linux", {"HOME": "/home/dev"})

        self.assertEqual(
            resolved,
            "/home/dev/.local/share/com.secondloop.secondloopdev",
        )

    def test_resolve_app_data_dir_for_windows_uses_company_and_dev_product(self) -> None:
        module = _load_module()

        resolved = module.resolve_app_data_dir("Windows", {"APPDATA": r"C:\Users\dev\AppData\Roaming"})

        self.assertEqual(
            resolved,
            r"C:\Users\dev\AppData\Roaming\com.secondloop\SecondLoop Dev",
        )

    def test_delete_app_data_dir_removes_existing_tree_and_reports_removed(self) -> None:
        module = _load_module()

        temp_dir = Path(tempfile.mkdtemp())
        self.addCleanup(shutil.rmtree, temp_dir, ignore_errors=True)
        target = temp_dir / "app-data"
        target.mkdir()
        (target / "state.json").write_text("{}", encoding="utf-8")

        removed = module.delete_app_data_dir(target)

        self.assertTrue(removed)
        self.assertFalse(target.exists())

    def test_delete_app_data_dir_reports_when_missing(self) -> None:
        module = _load_module()

        temp_dir = Path(tempfile.mkdtemp())
        self.addCleanup(shutil.rmtree, temp_dir, ignore_errors=True)
        target = temp_dir / "missing"

        removed = module.delete_app_data_dir(target)

        self.assertFalse(removed)


if __name__ == "__main__":
    unittest.main()
