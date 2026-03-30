from __future__ import annotations

from pathlib import Path
import tempfile
import unittest

from tools.windows_https_update_server import UpdateFeedHandler, resolve_request_path


class WindowsHttpsUpdateServerPathTests(unittest.TestCase):
    def test_resolve_request_path_keeps_downloads_within_download_root(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            downloads = root / "downloads"
            downloads.mkdir()

            resolved = resolve_request_path(
                root_dir=root,
                downloads_dir=downloads,
                request_path="/downloads/latest.json",
            )

            self.assertEqual(resolved, downloads / "latest.json")

    def test_resolve_request_path_rejects_download_path_traversal(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            downloads = root / "downloads"
            downloads.mkdir()

            with self.assertRaises(PermissionError):
                resolve_request_path(
                    root_dir=root,
                    downloads_dir=downloads,
                    request_path="/downloads/../../secret.txt",
                )

    def test_resolve_request_path_rejects_root_path_traversal(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            downloads = root / "downloads"
            downloads.mkdir()

            with self.assertRaises(PermissionError):
                resolve_request_path(
                    root_dir=root,
                    downloads_dir=downloads,
                    request_path="/../secret.txt",
                )

    def test_handler_exposes_api_latest_signature_path(self) -> None:
        self.assertTrue(hasattr(UpdateFeedHandler, "api_latest_signature_path"))


if __name__ == "__main__":
    unittest.main()
