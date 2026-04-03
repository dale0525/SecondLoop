#!/usr/bin/env bash
set -euo pipefail

repo_root="$(git rev-parse --show-toplevel 2>/dev/null || true)"
if [[ -z "${repo_root}" ]]; then
  exit 0
fi

cd "${repo_root}"
source "${repo_root}/scripts/pre_commit_common.sh"

resolve_cargo_bin >/dev/null || cargo_missing_message
resolve_libclang_path >/dev/null || libclang_missing_message
resolve_vulkan_sdk_root >/dev/null || vulkan_sdk_missing_message
ensure_windows_short_build_paths

export CARGO_INCREMENTAL="${CARGO_INCREMENTAL:-0}"
export CARGO_PROFILE_DEV_DEBUG="${CARGO_PROFILE_DEV_DEBUG:-0}"
export CARGO_PROFILE_TEST_DEBUG="${CARGO_PROFILE_TEST_DEBUG:-0}"
export RUSTFLAGS="${RUSTFLAGS:--C debuginfo=0}"

if ! run_with_periodic_status "rust nextest" "${cargo_bin}" nextest run --manifest-path rust/Cargo.toml --all-features; then
  echo "" >&2
  echo "pre-commit: rust nextest failed." >&2
  echo "Fix locally with: pixi run rust-nextest" >&2
  exit 1
fi

if ! run_with_periodic_status "rust doctests" "${cargo_bin}" test --manifest-path rust/Cargo.toml --doc; then
  echo "" >&2
  echo "pre-commit: rust doctests failed." >&2
  echo "Fix locally with: pixi run cargo test \"--manifest-path rust/Cargo.toml --doc\"" >&2
  exit 1
fi
