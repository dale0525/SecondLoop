from __future__ import annotations

import http.client
from pathlib import Path
import threading
import tempfile
import unittest

from http.server import ThreadingHTTPServer

from tools.windows_https_update_server import (
    UpdateFeedHandler,
    ensure_server_root_is_complete,
    resolve_request_path,
)


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

    def test_api_latest_returns_raw_manifest_bytes(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            downloads = root / "downloads"
            downloads.mkdir()
            expected = b'{"version":"1.0.1"}\n'
            (downloads / "latest.json").write_bytes(expected)

            status, body = self._request(root, "/api/releases/latest")

            self.assertEqual(status, 200)
            self.assertEqual(body, expected)

    def test_server_root_validation_requires_manifest_signature(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            downloads = root / "downloads"
            downloads.mkdir()
            (downloads / "latest.json").write_text("{}", encoding="utf-8")

            with self.assertRaises(FileNotFoundError):
                ensure_server_root_is_complete(root)

    def test_non_whitelisted_root_path_is_forbidden(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            downloads = root / "downloads"
            downloads.mkdir()
            (root / "secret.txt").write_text("secret", encoding="utf-8")

            status, _ = self._request(root, "/secret.txt")

            self.assertEqual(status, 403)

    def test_release_page_route_uses_configured_app_name(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            downloads = root / "downloads"
            downloads.mkdir()

            status, body = self._request(root, "/releases/v1.0.1", app_name="SecondLoop")

            self.assertEqual(status, 200)
            self.assertIn(b"SecondLoop v1.0.1", body)
            self.assertNotIn(b"SecondLoop Dev v1.0.1", body)

    def _request(self, root: Path, path: str, app_name: str = "SecondLoop Dev") -> tuple[int, bytes]:
        status, _, body = self._request_with_method(root, "GET", path, app_name=app_name)
        return status, body

    def test_release_page_head_route_matches_get_status_without_directory_fallback(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            downloads = root / "downloads"
            downloads.mkdir()

            status, headers, body = self._request_with_method(
                root,
                "HEAD",
                "/releases/v1.0.1",
            )

            self.assertEqual(status, 200)
            self.assertEqual(body, b"")
            self.assertEqual(headers.get("Content-Type"), "text/html; charset=utf-8")

    def _request_with_method(
        self,
        root: Path,
        method: str,
        path: str,
        app_name: str = "SecondLoop Dev",
    ) -> tuple[int, dict[str, str], bytes]:
        server = ThreadingHTTPServer(("127.0.0.1", 0), UpdateFeedHandler)
        server.root_dir = str(root)  # type: ignore[attr-defined]
        server.app_name = app_name  # type: ignore[attr-defined]
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        try:
            connection = http.client.HTTPConnection(
                server.server_address[0],
                server.server_address[1],
                timeout=5,
            )
            try:
                connection.request(method, path)
                response = connection.getresponse()
                body = response.read()
                headers = {name: value for name, value in response.getheaders()}
                return response.status, headers, body
            finally:
                connection.close()
        finally:
            server.shutdown()
            server.server_close()
            thread.join(timeout=5)


if __name__ == "__main__":
    unittest.main()
