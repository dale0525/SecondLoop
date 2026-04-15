#!/usr/bin/env python3
from __future__ import annotations

import argparse
import http.server
import json
import os
import socketserver
from pathlib import Path
from urllib.parse import unquote, urlparse


def _normalize_base_path(value: str) -> str:
    stripped = value.strip() or "/"
    if not stripped.startswith("/"):
        stripped = f"/{stripped}"
    if not stripped.endswith("/"):
        stripped = f"{stripped}/"
    return stripped


class _CrossOriginPreviewHandler(http.server.SimpleHTTPRequestHandler):
    server_version = "SecondLoopWebPreview/1.0"

    def __init__(self, *args, directory: str, base_path: str, **kwargs) -> None:
        self._base_path = _normalize_base_path(base_path)
        super().__init__(*args, directory=directory, **kwargs)

    def end_headers(self) -> None:
        self.send_header("Cross-Origin-Opener-Policy", "same-origin")
        self.send_header("Cross-Origin-Embedder-Policy", "require-corp")
        super().end_headers()

    def do_GET(self) -> None:
        parsed = urlparse(self.path)
        if parsed.path == "/api/cloud/config":
            self._send_cloud_config()
            return
        if parsed.path.startswith("/api/"):
            self._send_json(
                404,
                {
                    "ok": False,
                    "error": "preview_api_not_available",
                    "path": parsed.path,
                },
            )
            return
        super().do_GET()

    def _send_cloud_config(self) -> None:
        firebase_web_api_key = os.environ.get("SECONDLOOP_FIREBASE_WEB_API_KEY", "").strip()
        cloud_gateway_base_url = (
            os.environ.get("SECONDLOOP_CLOUD_GATEWAY_BASE_URL", "").strip()
            or os.environ.get("CLOUD_GATEWAY_BASE_URL", "").strip()
        )
        managed_vault_base_url = os.environ.get(
            "SECONDLOOP_MANAGED_VAULT_BASE_URL", ""
        ).strip()

        self._send_json(
            200,
            {
                "ok": True,
                "firebase_web_api_key": firebase_web_api_key,
                "has_firebase_web_api_key": bool(firebase_web_api_key),
                "has_cloud_gateway_base_url": bool(cloud_gateway_base_url),
                "has_managed_vault_base_url": bool(managed_vault_base_url),
                "managed_vault_base_url": managed_vault_base_url,
            },
        )

    def _send_json(self, status: int, payload: dict[str, object]) -> None:
        body = json.dumps(payload).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Cache-Control", "no-store")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def translate_path(self, path: str) -> str:
        parsed = urlparse(path)
        request_path = unquote(parsed.path)
        if request_path == "/":
            request_path = self._base_path
        if request_path.startswith(self._base_path):
            request_path = request_path[len(self._base_path) :]
        else:
            request_path = ""

        candidate = Path(self.directory) / request_path
        if request_path and candidate.exists():
            return str(candidate)

        if request_path.endswith("/"):
            index_candidate = candidate / "index.html"
            if index_candidate.exists():
                return str(index_candidate)

        if "." not in Path(request_path).name:
            return str(Path(self.directory) / "index.html")
        return str(candidate)


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Serve a Flutter web build with cross-origin isolation headers.",
    )
    parser.add_argument("--root", default="build/web", help="Static web root.")
    parser.add_argument(
        "--base-path",
        default="/app",
        help="Public base path used by the built Flutter app.",
    )
    parser.add_argument("--host", default="127.0.0.1", help="Bind host.")
    parser.add_argument("--port", type=int, default=4173, help="Bind port.")
    args = parser.parse_args()

    root = Path(args.root).resolve()
    if not root.exists():
        raise SystemExit(f"web root does not exist: {root}")

    handler = lambda *handler_args, **handler_kwargs: _CrossOriginPreviewHandler(
        *handler_args,
        directory=str(root),
        base_path=args.base_path,
        **handler_kwargs,
    )

    with socketserver.ThreadingTCPServer((args.host, args.port), handler) as httpd:
        print(
            f"Serving {root} at http://{args.host}:{args.port}{_normalize_base_path(args.base_path)}"
        )
        httpd.serve_forever()


if __name__ == "__main__":
    main()
