from __future__ import annotations

import argparse
import json
import ssl
from http import HTTPStatus
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path


class UpdateFeedHandler(SimpleHTTPRequestHandler):
    server_version = "SecondLoopUpdateServer/1.0"

    @property
    def root_dir(self) -> Path:
        return Path(self.server.root_dir)  # type: ignore[attr-defined]

    @property
    def downloads_dir(self) -> Path:
        return self.root_dir / "downloads"

    @property
    def latest_json_path(self) -> Path:
        return self.downloads_dir / "latest.json"

    def translate_path(self, path: str) -> str:
        normalized = path.split("?", 1)[0].split("#", 1)[0]
        if normalized.startswith("/downloads/"):
            relative = normalized.removeprefix("/downloads/")
            return str((self.downloads_dir / relative).resolve())
        if normalized in {"", "/"}:
            return str(self.root_dir.resolve())
        return str((self.root_dir / normalized.lstrip("/")).resolve())

    def do_GET(self) -> None:
        normalized = self.path.split("?", 1)[0].split("#", 1)[0]
        if normalized == "/api/releases/latest":
            payload = json.loads(self.latest_json_path.read_text(encoding="utf-8"))
            body = json.dumps(payload, indent=2).encode("utf-8")
            self.send_response(HTTPStatus.OK)
            self.send_header("Content-Type", "application/json; charset=utf-8")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)
            return

        if normalized.startswith("/releases/"):
            release_name = normalized.removeprefix("/releases/") or "latest"
            body = (
                "<html><body><h1>SecondLoop Dev "
                f"{release_name}</h1></body></html>"
            ).encode("utf-8")
            self.send_response(HTTPStatus.OK)
            self.send_header("Content-Type", "text/html; charset=utf-8")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)
            return

        super().do_GET()


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Serve a local HTTPS update feed for Windows auto-update smoke tests.",
    )
    parser.add_argument("--root", required=True, help="Root directory containing downloads/latest.json")
    parser.add_argument("--cert", required=True, help="TLS certificate PEM path")
    parser.add_argument("--key", required=True, help="TLS private key path")
    parser.add_argument("--host", default="localhost", help="Bind host")
    parser.add_argument("--port", type=int, default=8443, help="Bind port")
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    root = Path(args.root).resolve()
    cert_path = Path(args.cert).resolve()
    key_path = Path(args.key).resolve()

    downloads_dir = root / "downloads"
    latest_json = downloads_dir / "latest.json"
    if not latest_json.exists():
        raise FileNotFoundError(f"Missing latest.json: {latest_json}")

    server = ThreadingHTTPServer((args.host, args.port), UpdateFeedHandler)
    server.root_dir = str(root)  # type: ignore[attr-defined]

    context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
    context.load_cert_chain(certfile=str(cert_path), keyfile=str(key_path))
    server.socket = context.wrap_socket(server.socket, server_side=True)

    print(
        f"HTTPS update server listening on https://{args.host}:{args.port}",
        flush=True,
    )
    server.serve_forever()


if __name__ == "__main__":
    main()
