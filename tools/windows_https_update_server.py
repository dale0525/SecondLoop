from __future__ import annotations

import argparse
import ssl
from http import HTTPStatus
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path


def resolve_request_path(
    *,
    root_dir: Path,
    downloads_dir: Path,
    request_path: str,
) -> Path:
    normalized = request_path.split("?", 1)[0].split("#", 1)[0]
    if normalized in {"/downloads", "/downloads/"}:
        resolved = downloads_dir.resolve()
        allowed_root = downloads_dir.resolve()
    elif normalized.startswith("/downloads/"):
        relative = normalized.removeprefix("/downloads/")
        resolved = (downloads_dir / relative).resolve()
        allowed_root = downloads_dir.resolve()
    elif normalized in {"", "/"}:
        raise PermissionError(f"Request path is not whitelisted: {request_path}")
    elif normalized.startswith("/releases/"):
        resolved = root_dir.resolve()
        allowed_root = root_dir.resolve()
    else:
        raise PermissionError(f"Request path is not whitelisted: {request_path}")

    try:
        resolved.relative_to(allowed_root)
    except ValueError as error:
        raise PermissionError(
            f"Request path escapes allowed root: {request_path}",
        ) from error

    return resolved


def ensure_server_root_is_complete(root_dir: Path) -> None:
    downloads_dir = root_dir / "downloads"
    latest_json = downloads_dir / "latest.json"
    latest_signature = downloads_dir / "latest.json.sig"
    if not latest_json.exists():
        raise FileNotFoundError(f"Missing latest.json: {latest_json}")
    if not latest_signature.exists():
        raise FileNotFoundError(f"Missing latest.json.sig: {latest_signature}")


class UpdateFeedHandler(SimpleHTTPRequestHandler):
    server_version = "SecondLoopUpdateServer/1.0"

    def _write_body(
        self,
        *,
        status: HTTPStatus,
        body: bytes,
        content_type: str,
    ) -> None:
        self.send_response(status)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    @property
    def root_dir(self) -> Path:
        return Path(self.server.root_dir)  # type: ignore[attr-defined]

    @property
    def downloads_dir(self) -> Path:
        return self.root_dir / "downloads"

    @property
    def latest_json_path(self) -> Path:
        return self.downloads_dir / "latest.json"

    @property
    def api_latest_signature_path(self) -> Path:
        return self.downloads_dir / "latest.json.sig"

    def translate_path(self, path: str) -> str:
        try:
            return str(
                resolve_request_path(
                    root_dir=self.root_dir,
                    downloads_dir=self.downloads_dir,
                    request_path=path,
                ),
            )
        except PermissionError:
            return str(self.root_dir / "__forbidden__")

    def do_GET(self) -> None:
        normalized = self.path.split("?", 1)[0].split("#", 1)[0]
        if normalized == "/api/releases/latest":
            try:
                body = self.latest_json_path.read_bytes()
            except FileNotFoundError:
                self.send_error(HTTPStatus.NOT_FOUND, "Missing latest.json")
                return
            self._write_body(
                status=HTTPStatus.OK,
                body=body,
                content_type="application/json; charset=utf-8",
            )
            return

        if normalized == "/api/releases/latest.sig":
            try:
                body = self.api_latest_signature_path.read_bytes()
            except FileNotFoundError:
                self.send_error(HTTPStatus.NOT_FOUND, "Missing latest.json.sig")
                return

            self._write_body(
                status=HTTPStatus.OK,
                body=body,
                content_type="text/plain; charset=utf-8",
            )
            return

        if normalized.startswith("/releases/"):
            release_name = normalized.removeprefix("/releases/") or "latest"
            body = (
                "<html><body><h1>SecondLoop Dev "
                f"{release_name}</h1></body></html>"
            ).encode("utf-8")
            self._write_body(
                status=HTTPStatus.OK,
                body=body,
                content_type="text/html; charset=utf-8",
            )
            return

        try:
            resolve_request_path(
                root_dir=self.root_dir,
                downloads_dir=self.downloads_dir,
                request_path=self.path,
            )
        except PermissionError:
            self.send_error(HTTPStatus.FORBIDDEN)
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

    ensure_server_root_is_complete(root)

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
