#!/usr/bin/env bash
set -euo pipefail

repo_root="$(git rev-parse --show-toplevel)"
cd "${repo_root}"

dart pub global run fvm:main flutter build web --base-href /app/
dart pub global run fvm:main dart run tools/sync_web_build_rust_pkg.dart
dart pub global run fvm:main flutter pub run tools/prune_web_build_ffmpeg.dart

exec python tools/serve_web_build_with_headers.py \
  --root build/web \
  --base-path /app \
  --port "${SECONDLOOP_WEB_PREVIEW_PORT:-4173}"
