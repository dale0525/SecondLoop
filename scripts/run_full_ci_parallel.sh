#!/usr/bin/env bash
set -euo pipefail

repo_root="$(git rev-parse --show-toplevel 2>/dev/null || true)"
if [[ -z "${repo_root}" ]]; then
  exit 0
fi

cd "${repo_root}"

flutter_log=""
web_log=""
python_log=""
flutter_pid=""
web_pid=""
python_pid=""
flutter_done=0
web_done=0
python_done=0
overall_status=0

cancel_remaining_jobs() {
  local failed_job="$1"
  local pid name

  for pid_var in flutter_pid web_pid python_pid; do
    pid="${!pid_var:-}"
    [[ -n "${pid}" ]] || continue
    if ! kill -0 "${pid}" 2>/dev/null; then
      continue
    fi

    case "${pid_var}" in
      flutter_pid) name="Flutter" ;;
      web_pid) name="Web" ;;
      python_pid) name="Python tooling" ;;
      *) name="${pid_var}" ;;
    esac

    if [[ "${name}" == "${failed_job}" ]]; then
      continue
    fi

    echo "ci: cancelling ${name} verification after ${failed_job} failure..." >&2
    kill "${pid}" 2>/dev/null || true
  done
}

cleanup() {
  local pid
  for pid in "${flutter_pid:-}" "${web_pid:-}" "${python_pid:-}"; do
    if [[ -n "${pid}" ]] && kill -0 "${pid}" 2>/dev/null; then
      kill "${pid}" 2>/dev/null || true
      wait "${pid}" 2>/dev/null || true
    fi
  done

  [[ -n "${flutter_log}" ]] && rm -f "${flutter_log}" 2>/dev/null || true
  [[ -n "${web_log}" ]] && rm -f "${web_log}" 2>/dev/null || true
  [[ -n "${python_log}" ]] && rm -f "${python_log}" 2>/dev/null || true
}
trap cleanup EXIT

flutter_log="$(mktemp -t secondloop_ci_flutter.XXXXXX.log)"
web_log="$(mktemp -t secondloop_ci_web.XXXXXX.log)"
python_log="$(mktemp -t secondloop_ci_python.XXXXXX.log)"

echo "ci: starting Flutter verification..." >&2
bash scripts/run_flutter_ci_local.sh >"${flutter_log}" 2>&1 &
flutter_pid=$!

echo "ci: starting Web verification..." >&2
bash scripts/run_flutter_web_ci_local.sh >"${web_log}" 2>&1 &
web_pid=$!

echo "ci: starting Python tooling verification..." >&2
bash scripts/run_python_tooling_checks.sh >"${python_log}" 2>&1 &
python_pid=$!

handle_finished_job() {
  local job_name="$1"
  local job_pid="$2"
  local job_log="$3"

  local status=0
  wait "${job_pid}" || status=$?
  if [[ ${status} -eq 143 && ${overall_status} -ne 0 ]]; then
    echo "ci: ${job_name} verification cancelled after ${overall_status} failure" >&2
  else
    echo "ci: ${job_name} verification finished with status ${status}" >&2
  fi
  cat "${job_log}"

  if [[ ${status} -ne 0 && ${overall_status} -eq 0 ]]; then
    overall_status="${status}"
    cancel_remaining_jobs "${job_name}"
  fi
}

remaining_jobs=3
while [[ ${remaining_jobs} -gt 0 ]]; do
  if [[ ${flutter_done} -eq 0 ]] && ! kill -0 "${flutter_pid}" 2>/dev/null; then
    handle_finished_job "Flutter" "${flutter_pid}" "${flutter_log}"
    flutter_done=1
    remaining_jobs=$((remaining_jobs - 1))
    continue
  fi

  if [[ ${web_done} -eq 0 ]] && ! kill -0 "${web_pid}" 2>/dev/null; then
    handle_finished_job "Web" "${web_pid}" "${web_log}"
    web_done=1
    remaining_jobs=$((remaining_jobs - 1))
    continue
  fi

  if [[ ${python_done} -eq 0 ]] && ! kill -0 "${python_pid}" 2>/dev/null; then
    handle_finished_job "Python tooling" "${python_pid}" "${python_log}"
    python_done=1
    remaining_jobs=$((remaining_jobs - 1))
    continue
  fi

  sleep 0.1
done

if [[ ${overall_status} -ne 0 ]]; then
  exit "${overall_status}"
fi
