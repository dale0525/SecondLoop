#!/usr/bin/env bash
set -euo pipefail

repo_root="$(git rev-parse --show-toplevel 2>/dev/null || true)"
if [[ -z "${repo_root}" ]]; then
  exit 0
fi

cd "${repo_root}"

if [[ "$(uname -s 2>/dev/null || echo unknown)" == MINGW* || "$(uname -s 2>/dev/null || echo unknown)" == MSYS* || "$(uname -s 2>/dev/null || echo unknown)" == CYGWIN* ]]; then
  powershell -NoProfile -ExecutionPolicy Bypass -File scripts/run_bash.ps1 .githooks/pre-commit --check "$@"
else
  bash .githooks/pre-commit --check "$@"
fi
