#!/usr/bin/env bash
set -euo pipefail

repo_root="$(git rev-parse --show-toplevel 2>/dev/null || true)"
if [[ -z "${repo_root}" ]]; then
  exit 0
fi

cd "${repo_root}"
source "${repo_root}/scripts/pre_commit_common.sh"

worktree_cache_key="$(printf '%s\n' "${repo_root}" | cksum | awk '{print $1}')"
clippy_log="$(mktemp -t secondloop_rust_clippy.XXXXXX.log)"
nextest_log="$(mktemp -t secondloop_rust_nextest.XXXXXX.log)"
clippy_target_dir="${repo_root}/.tool/cache/rust-ci-clippy-target-${worktree_cache_key}"
nextest_target_dir="${repo_root}/.tool/cache/rust-ci-nextest-target-${worktree_cache_key}"
clippy_pid=""
nextest_pid=""

cleanup() {
  local pid

  for pid in "${clippy_pid:-}" "${nextest_pid:-}"; do
    if [[ -n "${pid}" ]] && kill -0 "${pid}" 2>/dev/null; then
      kill "${pid}" 2>/dev/null || true
      wait "${pid}" 2>/dev/null || true
    fi
  done

  rm -f "${clippy_log}" "${nextest_log}" 2>/dev/null || true
}
trap cleanup EXIT INT TERM

mkdir -p "${clippy_target_dir}" "${nextest_target_dir}"

echo "ci: starting Rust clippy..." >&2
env CARGO_TARGET_DIR="${clippy_target_dir}" \
  bash .githooks/pre-commit --check --rust --ci --skip-tests >"${clippy_log}" 2>&1 &
clippy_pid=$!

echo "ci: starting Rust nextest..." >&2
env CARGO_TARGET_DIR="${nextest_target_dir}" \
  bash scripts/run_rust_ci_nextest.sh >"${nextest_log}" 2>&1 &
nextest_pid=$!

status=0
wait "${clippy_pid}" || status=$?
cat "${clippy_log}"

nextest_status=0
wait "${nextest_pid}" || nextest_status=$?
cat "${nextest_log}"

if [[ ${nextest_status} -ne 0 ]]; then
  status=${nextest_status}
fi

exit "${status}"
