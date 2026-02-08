#!/usr/bin/env bash
set -euo pipefail

repo_root="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
cd "${repo_root}"

fail=0

echo "[check] desktop runtime must not invoke python/pip at runtime"

# Dart runtime paths (desktop OCR/PDF pipeline and related runtime managers).
dart_paths=(
  "lib/features/attachments"
  "lib/features/media_backup"
  "lib/core/content_enrichment"
)

# Rust runtime paths.
rust_paths=(
  "rust/src/desktop_media"
  "rust/src/api"
)

search_matches() {
  local pattern="$1"
  shift
  if command -v rg >/dev/null 2>&1; then
    rg -n --pcre2 "$pattern" "$@"
  else
    grep -R -n -P -- "$pattern" "$@"
  fi
}

if search_matches \
  "Process\\.(run|start)\\(\\s*['\\\"]\\s*(python|python3|pip|pip3)\\b" \
  "${dart_paths[@]}"; then
  echo "[error] direct python/pip Process invocation found in Dart runtime paths" >&2
  fail=1
fi

if search_matches \
  "Process\\.(run|start)\\([^\\)]*pythonExecutable" \
  "${dart_paths[@]}"; then
  echo "[error] pythonExecutable-based Process invocation found in Dart runtime paths" >&2
  fail=1
fi

if search_matches \
  "Command::new\\(\\s*['\\\"]\\s*(python|python3|pip|pip3)\\b" \
  "${rust_paths[@]}"; then
  echo "[error] direct python/pip command invocation found in Rust runtime paths" >&2
  fail=1
fi

if (( fail != 0 )); then
  echo "[fail] python runtime guard failed" >&2
  exit 1
fi

echo "[ok] no python runtime process invocation detected"
