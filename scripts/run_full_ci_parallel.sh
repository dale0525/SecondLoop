#!/usr/bin/env bash
set -euo pipefail

repo_root="$(git rev-parse --show-toplevel 2>/dev/null || true)"
if [[ -z "${repo_root}" ]]; then
  exit 0
fi

cd "${repo_root}"

flutter_log=""
rust_log=""
flutter_pid=""
rust_pid=""

cleanup() {
  local pid
  for pid in "${flutter_pid:-}" "${rust_pid:-}"; do
    if [[ -n "${pid}" ]] && kill -0 "${pid}" 2>/dev/null; then
      kill "${pid}" 2>/dev/null || true
      wait "${pid}" 2>/dev/null || true
    fi
  done

  [[ -n "${flutter_log}" ]] && rm -f "${flutter_log}" 2>/dev/null || true
  [[ -n "${rust_log}" ]] && rm -f "${rust_log}" 2>/dev/null || true
}
trap cleanup EXIT

flutter_log="$(mktemp -t secondloop_ci_flutter.XXXXXX.log)"
rust_log="$(mktemp -t secondloop_ci_rust.XXXXXX.log)"

echo "ci: starting Flutter verification..." >&2
bash scripts/verify_full.sh --flutter >"${flutter_log}" 2>&1 &
flutter_pid=$!

echo "ci: starting Rust verification..." >&2
bash scripts/run_full_rust_ci_local.sh >"${rust_log}" 2>&1 &
rust_pid=$!

flutter_status=0
rust_status=0

wait "${flutter_pid}" || flutter_status=$?
echo "ci: Flutter verification finished with status ${flutter_status}" >&2
cat "${flutter_log}"

wait "${rust_pid}" || rust_status=$?
echo "ci: Rust verification finished with status ${rust_status}" >&2
cat "${rust_log}"

if [[ ${flutter_status} -ne 0 || ${rust_status} -ne 0 ]]; then
  exit 1
fi
