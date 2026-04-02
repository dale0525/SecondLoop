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
flutter_done=0
rust_done=0
flutter_status=0
rust_status=0

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

handle_finished_job() {
  local job_name="$1"
  local job_pid="$2"
  local job_log="$3"
  local job_status_var="$4"

  local status=0
  wait "${job_pid}" || status=$?
  printf -v "${job_status_var}" '%s' "${status}"
  echo "ci: ${job_name} verification finished with status ${status}" >&2
  cat "${job_log}"
}

remaining_jobs=2
while [[ ${remaining_jobs} -gt 0 ]]; do
  if [[ ${flutter_done} -eq 0 ]] && ! kill -0 "${flutter_pid}" 2>/dev/null; then
    handle_finished_job "Flutter" "${flutter_pid}" "${flutter_log}" flutter_status
    flutter_done=1
    remaining_jobs=$((remaining_jobs - 1))
    continue
  fi

  if [[ ${rust_done} -eq 0 ]] && ! kill -0 "${rust_pid}" 2>/dev/null; then
    handle_finished_job "Rust" "${rust_pid}" "${rust_log}" rust_status
    rust_done=1
    remaining_jobs=$((remaining_jobs - 1))
    continue
  fi

  sleep 1
done

if [[ ${flutter_status} -ne 0 || ${rust_status} -ne 0 ]]; then
  exit 1
fi
