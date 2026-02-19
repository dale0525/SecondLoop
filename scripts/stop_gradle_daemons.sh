#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GRADLEW="$ROOT_DIR/android/gradlew"

if [[ ! -x "$GRADLEW" ]]; then
  exit 0
fi

(
  cd "$ROOT_DIR/android"
  "$GRADLEW" --stop >/dev/null 2>&1 || true
)
