from __future__ import annotations

from importlib.util import module_from_spec, spec_from_file_location
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest
from unittest.mock import patch


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

    def test_resolve_macos_preferences_file_uses_bundle_id(self) -> None:
        module = _load_module()

        resolved = module.resolve_macos_preferences_file(
            "com.secondloop.secondloopdev",
            {"HOME": "/Users/dev"},
        )

        self.assertEqual(
            resolved,
            "/Users/dev/Library/Preferences/com.secondloop.secondloopdev.plist",
        )

    def test_delete_macos_preferences_removes_plist_and_defaults_domain(self) -> None:
        module = _load_module()
        calls: list[list[str]] = []

        temp_dir = Path(tempfile.mkdtemp())
        self.addCleanup(shutil.rmtree, temp_dir, ignore_errors=True)
        prefs_dir = temp_dir / "Library" / "Preferences"
        prefs_dir.mkdir(parents=True)
        prefs_file = prefs_dir / "com.secondloop.secondloopdev.plist"
        prefs_file.write_text("{}", encoding="utf-8")

        def runner(args: list[str]) -> subprocess.CompletedProcess[str]:
            calls.append(list(args))
            return subprocess.CompletedProcess(args=args, returncode=0)

        with patch.object(module.shutil, "which", return_value="/usr/bin/defaults"):
            removed = module.delete_macos_preferences(
                env={"HOME": str(temp_dir)},
                runner=runner,
            )

        self.assertTrue(removed)
        self.assertFalse(prefs_file.exists())
        self.assertEqual(
            calls,
            [["/usr/bin/defaults", "delete", "com.secondloop.secondloopdev"]],
        )

    def test_delete_macos_secure_storage_blob_deletes_until_missing(self) -> None:
        module = _load_module()
        calls: list[list[str]] = []
        returncodes = [0, 0, 44]

        def runner(args: list[str]) -> subprocess.CompletedProcess[str]:
            calls.append(list(args))
            return subprocess.CompletedProcess(
                args=args,
                returncode=returncodes.pop(0),
            )

        with patch.object(module.shutil, "which", return_value="/usr/bin/security"):
            removed = module.delete_macos_secure_storage_blob(runner=runner)

        self.assertTrue(removed)
        self.assertEqual(len(calls), 3)
        self.assertEqual(
            calls[0],
            [
                "/usr/bin/security",
                "delete-generic-password",
                "-a",
                "sync_config_blob_json_v1",
                "-s",
                "flutter_secure_storage_service",
            ],
        )

    def test_verify_empty_local_dev_data_reports_macos_categories(self) -> None:
        module = _load_module()
        calls: list[list[str]] = []

        temp_dir = Path(tempfile.mkdtemp())
        self.addCleanup(shutil.rmtree, temp_dir, ignore_errors=True)

        def runner(args: list[str]) -> subprocess.CompletedProcess[str]:
            calls.append(list(args))
            return subprocess.CompletedProcess(args=args, returncode=44)

        with patch.object(module.shutil, "which") as which:
            which.side_effect = lambda name: f"/usr/bin/{name}"
            checks = module.verify_empty_local_dev_data(
                "Darwin",
                env={"HOME": str(temp_dir)},
                runner=runner,
            )

        self.assertEqual(
            checks,
            [
                (
                    "app_data",
                    True,
                    str(
                        temp_dir
                        / "Library"
                        / "Application Support"
                        / "com.secondloop.secondloopdev"
                    ),
                ),
                (
                    "preferences",
                    True,
                    str(
                        temp_dir
                        / "Library"
                        / "Preferences"
                        / "com.secondloop.secondloopdev.plist"
                    ),
                ),
                ("secure_blob", True, "sync_config_blob_json_v1"),
            ],
        )
        self.assertEqual(
            calls,
            [
                ["/usr/bin/defaults", "read", "com.secondloop.secondloopdev"],
                [
                    "/usr/bin/security",
                    "find-generic-password",
                    "-a",
                    "sync_config_blob_json_v1",
                    "-s",
                    "flutter_secure_storage_service",
                ],
            ],
        )

    def test_verify_empty_local_dev_data_detects_non_empty_app_data(self) -> None:
        module = _load_module()

        temp_dir = Path(tempfile.mkdtemp())
        self.addCleanup(shutil.rmtree, temp_dir, ignore_errors=True)
        app_data = (
            temp_dir
            / "Library"
            / "Application Support"
            / "com.secondloop.secondloopdev"
        )
        app_data.mkdir(parents=True)
        (app_data / "state.json").write_text("{}", encoding="utf-8")

        with patch.object(module.shutil, "which", return_value=None):
            checks = module.verify_empty_local_dev_data(
                "Darwin",
                env={"HOME": str(temp_dir)},
            )

        self.assertEqual(checks[0][0], "app_data")
        self.assertFalse(checks[0][1])


if __name__ == "__main__":
    unittest.main()
