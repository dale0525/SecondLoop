from __future__ import annotations

import http.client
from pathlib import Path
import threading
import tempfile
import unittest

from http.server import ThreadingHTTPServer

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

    def test_api_latest_returns_404_when_manifest_is_missing(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            downloads = root / "downloads"
            downloads.mkdir()

            status, _ = self._request(root, "/api/releases/latest")

            self.assertEqual(status, 404)

    def test_api_latest_returns_500_for_invalid_manifest_json(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            downloads = root / "downloads"
            downloads.mkdir()
            (downloads / "latest.json").write_text("{invalid", encoding="utf-8")

            status, _ = self._request(root, "/api/releases/latest")

            self.assertEqual(status, 500)

    def _request(self, root: Path, path: str) -> tuple[int, bytes]:
        server = ThreadingHTTPServer(("127.0.0.1", 0), UpdateFeedHandler)
        server.root_dir = str(root)  # type: ignore[attr-defined]
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        try:
            connection = http.client.HTTPConnection(
                server.server_address[0],
                server.server_address[1],
                timeout=5,
            )
            try:
                connection.request("GET", path)
                response = connection.getresponse()
                body = response.read()
                return response.status, body
            finally:
                connection.close()
        finally:
            server.shutdown()
            server.server_close()
            thread.join(timeout=5)


if __name__ == "__main__":
    unittest.main()
