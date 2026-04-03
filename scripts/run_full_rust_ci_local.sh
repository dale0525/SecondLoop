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
clippy_done=0
nextest_done=0
overall_status=0

cancel_remaining_job() {
  local failed_job="$1"
  local pid name

  for pid_var in clippy_pid nextest_pid; do
    pid="${!pid_var:-}"
    [[ -n "${pid}" ]] || continue
    if ! kill -0 "${pid}" 2>/dev/null; then
      continue
    fi

    case "${pid_var}" in
      clippy_pid) name="Rust clippy" ;;
      nextest_pid) name="Rust nextest" ;;
      *) name="${pid_var}" ;;
    esac

    if [[ "${name}" == "${failed_job}" ]]; then
      continue
    fi

    echo "ci: cancelling ${name} after ${failed_job} failure..." >&2
    kill "${pid}" 2>/dev/null || true
  done
}

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

handle_finished_job() {
  local job_name="$1"
  local job_pid="$2"
  local job_log="$3"

  local status=0
  wait "${job_pid}" || status=$?
  echo "ci: ${job_name} finished with status ${status}" >&2
  cat "${job_log}"

  if [[ ${status} -ne 0 && ${overall_status} -eq 0 ]]; then
    overall_status="${status}"
    cancel_remaining_job "${job_name}"
  fi
}

remaining_jobs=2
while [[ ${remaining_jobs} -gt 0 ]]; do
  if [[ ${clippy_done} -eq 0 ]] && ! kill -0 "${clippy_pid}" 2>/dev/null; then
    handle_finished_job "Rust clippy" "${clippy_pid}" "${clippy_log}"
    clippy_done=1
    remaining_jobs=$((remaining_jobs - 1))
    continue
  fi

  if [[ ${nextest_done} -eq 0 ]] && ! kill -0 "${nextest_pid}" 2>/dev/null; then
    handle_finished_job "Rust nextest" "${nextest_pid}" "${nextest_log}"
    nextest_done=1
    remaining_jobs=$((remaining_jobs - 1))
    continue
  fi

  sleep 1
done

if [[ ${overall_status} -ne 0 ]]; then
  exit "${overall_status}"
fi
