#!/usr/bin/env bash
set -euo pipefail

repo_root="$(git rev-parse --show-toplevel 2>/dev/null || true)"
if [[ -z "${repo_root}" ]]; then
  exit 0
fi

cd "${repo_root}"
source "${repo_root}/scripts/pre_commit_common.sh"

dart_bin="$(resolve_dart_bin)" || die "Missing 'dart'. Install Flutter (recommended: \`pixi run setup-flutter\`) or add Dart to PATH."
flutter_bin="$(resolve_flutter_bin)" || die "Missing 'flutter'. Install Flutter (recommended: \`pixi run setup-flutter\`) or add Flutter to PATH."

flutter_gate_log="$(mktemp -t secondloop_flutter_gate.XXXXXX.log)"
flutter_ci_temp_root="$(mktemp -d -t secondloop_flutter_ci.XXXXXX)"

flutter_shards="${SECONDLOOP_LOCAL_FLUTTER_TEST_SHARDS:-4}"
[[ "${flutter_shards}" =~ ^[0-9]+$ ]] || die "SECONDLOOP_LOCAL_FLUTTER_TEST_SHARDS must be a positive integer"
(( flutter_shards > 0 )) || die "SECONDLOOP_LOCAL_FLUTTER_TEST_SHARDS must be greater than 0"

flutter_test_logs=()
flutter_test_pids=()
flutter_test_worktrees=()
prepared_worktree=""
flutter_gate_pid=""
overall_status=0

cleanup() {
  local pid worktree

  for pid in "${flutter_gate_pid:-}" "${flutter_test_pids[@]-}"; do
    if [[ -n "${pid}" ]] && kill -0 "${pid}" 2>/dev/null; then
      kill "${pid}" 2>/dev/null || true
      wait "${pid}" 2>/dev/null || true
    fi
  done

  for worktree in "${flutter_test_worktrees[@]-}"; do
    [[ -n "${worktree}" && -d "${worktree}" ]] || continue
    git worktree remove --force "${worktree}" >/dev/null 2>&1 || rm -rf "${worktree}" 2>/dev/null || true
  done

  rm -rf "${flutter_ci_temp_root}" 2>/dev/null || true
  rm -f "${flutter_gate_log}" "${flutter_test_logs[@]-}" 2>/dev/null || true
}
trap cleanup EXIT INT TERM

create_flutter_worktree() {
  local label="$1"
  local worktree_path="${flutter_ci_temp_root}/${label}"

  if ! git worktree add --detach "${worktree_path}" HEAD >/dev/null 2>&1; then
    die "failed to create temporary Flutter worktree: ${label}"
  fi

  flutter_test_worktrees+=("${worktree_path}")
  printf '%s\n' "${worktree_path}"
}

sync_workspace_state_into_worktree() {
  local destination_root="$1"
  local file

  if ! git diff --quiet HEAD --; then
    if ! git diff --binary --relative HEAD -- | git -C "${destination_root}" apply --allow-empty --binary; then
      die "failed to sync tracked workspace changes into ${destination_root}"
    fi
  fi

  while IFS= read -r -d '' file; do
    [[ -n "${file}" ]] || continue
    mkdir -p "${destination_root}/$(dirname "${file}")"
    rm -rf "${destination_root}/${file}"
    cp -PR "${repo_root}/${file}" "${destination_root}/${file}"
  done < <(git ls-files --others --exclude-standard -z)
}

copy_prepared_i18n_tree() {
  local destination_root="$1"

  rm -rf "${destination_root}/lib/i18n"
  mkdir -p "${destination_root}/lib"
  cp -R "${prepared_worktree}/lib/i18n" "${destination_root}/lib/"
}

copy_prepared_flutter_tool_state() {
  local destination_root="$1"
  local relative_path

  for relative_path in .dart_tool .flutter-plugins .flutter-plugins-dependencies; do
    rm -rf "${destination_root}/${relative_path}"
    [[ -e "${prepared_worktree}/${relative_path}" ]] || continue
    mkdir -p "${destination_root}/$(dirname "${relative_path}")"
    cp -R "${prepared_worktree}/${relative_path}" "${destination_root}/${relative_path}"
  done
}

echo "ci: starting Flutter gate..." >&2
bash .githooks/pre-commit --check --flutter >"${flutter_gate_log}" 2>&1 &
flutter_gate_pid=$!

echo "ci: preparing i18n outputs in a temporary Flutter worktree..." >&2
prepared_worktree="$(create_flutter_worktree "prepared-shard-0")"
sync_workspace_state_into_worktree "${prepared_worktree}"
if ! (
  cd "${prepared_worktree}"
  export SECONDLOOP_FLUTTER_BIN="${flutter_bin}"
  run_with_periodic_status "flutter pub get (prepared Flutter worktree)" run_flutter_tool pub get >/dev/null
  export SECONDLOOP_I18N_DART_BIN="${dart_bin}"
  export SECONDLOOP_I18N_FLUTTER_BIN="${flutter_bin}"
  bash scripts/run_i18n_refresh.sh >/dev/null
); then
  if kill -0 "${flutter_gate_pid}" 2>/dev/null; then
    kill "${flutter_gate_pid}" 2>/dev/null || true
    wait "${flutter_gate_pid}" 2>/dev/null || true
  fi
  cat "${flutter_gate_log}" 2>/dev/null || true
  die "failed to refresh i18n outputs inside the temporary Flutter worktree"
fi

for (( shard_index = 0; shard_index < flutter_shards; shard_index++ )); do
  shard_worktree="${prepared_worktree}"
  if (( shard_index > 0 )); then
    shard_worktree="$(create_flutter_worktree "shard-${shard_index}")"
    sync_workspace_state_into_worktree "${shard_worktree}"
    copy_prepared_flutter_tool_state "${shard_worktree}"
    copy_prepared_i18n_tree "${shard_worktree}"
  fi

  log_path="$(mktemp -t "secondloop_flutter_test_${shard_index}.XXXXXX.log")"
  flutter_test_logs+=("${log_path}")
  echo "ci: starting Flutter shard ${shard_index}/${flutter_shards} in ${shard_worktree}..." >&2
  (
    cd "${shard_worktree}"
    export SECONDLOOP_FLUTTER_BIN="${flutter_bin}"
    bash scripts/run_flutter_test_shard.sh --shard-index "${shard_index}" --shard-count "${flutter_shards}"
  ) >"${log_path}" 2>&1 &
  flutter_test_pids+=("$!")
done

gate_status=0
wait "${flutter_gate_pid}" || gate_status=$?
cat "${flutter_gate_log}"

if [[ ${gate_status} -ne 0 ]]; then
  for pid in "${flutter_test_pids[@]}"; do
    if kill -0 "${pid}" 2>/dev/null; then
      kill "${pid}" 2>/dev/null || true
    fi
  done

  for index in "${!flutter_test_pids[@]}"; do
    wait "${flutter_test_pids[$index]}" 2>/dev/null || true
    cat "${flutter_test_logs[$index]}"
  done

  exit "${gate_status}"
fi

shard_done=()
for _ in "${flutter_test_pids[@]}"; do
  shard_done+=(0)
done

cancel_remaining_shards() {
  local failed_index="$1"
  local pid

  for index in "${!flutter_test_pids[@]}"; do
    if [[ "${index}" == "${failed_index}" || "${shard_done[$index]}" -ne 0 ]]; then
      continue
    fi
    pid="${flutter_test_pids[$index]}"
    if kill -0 "${pid}" 2>/dev/null; then
      echo "ci: cancelling Flutter shard ${index}/${flutter_shards} after shard ${failed_index} failure..." >&2
      kill "${pid}" 2>/dev/null || true
    fi
  done
}

remaining_shards="${#flutter_test_pids[@]}"
while [[ ${remaining_shards} -gt 0 ]]; do
  for index in "${!flutter_test_pids[@]}"; do
    if [[ "${shard_done[$index]}" -ne 0 ]]; then
      continue
    fi

    if kill -0 "${flutter_test_pids[$index]}" 2>/dev/null; then
      continue
    fi

    shard_status=0
    wait "${flutter_test_pids[$index]}" || shard_status=$?
    cat "${flutter_test_logs[$index]}"
    shard_done[index]=1
    remaining_shards=$((remaining_shards - 1))

    if [[ ${shard_status} -ne 0 && ${overall_status} -eq 0 ]]; then
      overall_status="${shard_status}"
      cancel_remaining_shards "${index}"
    fi
  done

  if [[ ${remaining_shards} -gt 0 ]]; then
    sleep 1
  fi
done

exit "${overall_status}"
