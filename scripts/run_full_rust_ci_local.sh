#!/usr/bin/env bash
set -euo pipefail

repo_root="$(git rev-parse --show-toplevel 2>/dev/null || true)"
if [[ -z "${repo_root}" ]]; then
  exit 0
fi

cd "${repo_root}"
source "${repo_root}/scripts/pre_commit_common.sh"

worktree_cache_key="$(printf '%s\n' "${repo_root}" | cksum | awk '{print $1}')"
if is_windows_env; then
  ensure_windows_short_build_paths
  rust_target_root="${CARGO_TARGET_DIR%/}"
  rust_target_dir="${rust_target_root}/rust-ci-${worktree_cache_key}"
else
  rust_target_dir="${repo_root}/.tool/cache/rust-ci-target-${worktree_cache_key}"
fi

mkdir -p "${rust_target_dir}"

echo "ci: starting Rust gate..." >&2
if env CARGO_TARGET_DIR="${rust_target_dir}" \
  bash .githooks/pre-commit --check --rust --ci --skip-tests; then
  :
else
  status=$?
  exit "${status}"
fi

echo "ci: Rust gate passed; starting Rust nextest..." >&2
if env CARGO_TARGET_DIR="${rust_target_dir}" bash scripts/run_rust_ci_nextest.sh; then
  :
else
  status=$?
  exit "${status}"
fi
