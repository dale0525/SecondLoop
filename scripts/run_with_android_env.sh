#!/usr/bin/env bash
set -euo pipefail

if [[ "$#" -eq 0 ]]; then
  echo "Usage: bash scripts/run_with_android_env.sh <command> [args...]" >&2
  exit 1
fi

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TOOL_ROOT="$(cd "$ROOT_DIR/.tool" && pwd -P)"

export CARGO_HOME="${CARGO_HOME:-"$TOOL_ROOT/cargo"}"
export RUSTUP_HOME="${RUSTUP_HOME:-"$TOOL_ROOT/rustup"}"
export ANDROID_SDK_ROOT="${ANDROID_SDK_ROOT:-"$TOOL_ROOT/android-sdk"}"
export ANDROID_HOME="${ANDROID_HOME:-"$ANDROID_SDK_ROOT"}"
export ANDROID_USER_HOME="${ANDROID_USER_HOME:-"$TOOL_ROOT/android"}"
export GRADLE_USER_HOME="${GRADLE_USER_HOME:-"$TOOL_ROOT/gradle"}"

exec "$@"
