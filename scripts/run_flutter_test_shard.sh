#!/usr/bin/env bash
set -euo pipefail

die() {
  echo "flutter-test-shard: $*" >&2
  exit 1
}

repo_root="$(git rev-parse --show-toplevel 2>/dev/null || true)"
if [[ -z "${repo_root}" ]]; then
  exit 0
fi

macos_xcrun_wrapper_dir=""

cleanup() {
  if [[ -n "${macos_xcrun_wrapper_dir}" ]]; then
    rm -rf "${macos_xcrun_wrapper_dir}" 2>/dev/null || true
  fi
}
trap cleanup EXIT

shard_index=""
shard_count=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --shard-index)
      shard_index="${2:-}"
      shift 2
      ;;
    --shard-count)
      shard_count="${2:-}"
      shift 2
      ;;
    *)
      die "unknown argument: $1"
      ;;
  esac
done

[[ -n "${shard_index}" ]] || die "--shard-index is required"
[[ -n "${shard_count}" ]] || die "--shard-count is required"

cd "${repo_root}"
source "${repo_root}/scripts/pre_commit_common.sh"

create_macos_xcrun_wrapper() {
  local wrapper_dir
  wrapper_dir="$(mktemp -d -t secondloop_xcrun.XXXXXX)" ||
    die "failed to create temporary xcrun wrapper"
  cat > "${wrapper_dir}/xcrun" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

if [[ "${1:-}" == "xcodebuild" ]]; then
  shift
  exec /usr/bin/xcrun xcodebuild -allowProvisioningUpdates "$@"
fi

exec /usr/bin/xcrun "$@"
EOF
  chmod +x "${wrapper_dir}/xcrun" || die "failed to mark temporary xcrun wrapper as executable"
  printf '%s\n' "${wrapper_dir}"
}

run_linux_integration_test() {
  local integration_test_device="$1"
  local target="$2"
  local flutter_bin

  flutter_bin="$(resolve_flutter_bin)" || die "Missing 'flutter'. Install Flutter (recommended: \`pixi run setup-flutter\`) or add Flutter to PATH."
  command -v xvfb-run >/dev/null 2>&1 ||
    die "xvfb-run is required for Linux integration tests. Install xvfb or add xvfb-run to PATH."

  env -u GIT_DIR -u GIT_WORK_TREE -u GIT_INDEX_FILE \
    xvfb-run -a --server-args="-screen 0 1280x720x24" \
    "${flutter_bin}" test -d "${integration_test_device}" --concurrency=1 "${target}"
}

run_flutter_unit_tests_in_batches() {
  local batch_index=1
  local batch_chars=0
  local max_batch_chars="${SECONDLOOP_FLUTTER_TEST_MAX_BATCH_CHARS:-1000000}"
  local max_batch_targets="${SECONDLOOP_FLUTTER_TEST_MAX_BATCH_TARGETS:-1000000}"
  local max_retry_attempts="${SECONDLOOP_FLUTTER_TEST_RETRY_ATTEMPTS:-2}"
  local target
  local target_chars
  local -a batch_targets=()

  if is_windows_env; then
    # flutter.bat ultimately runs through cmd.exe, which still enforces a small
    # command-line limit even though our PowerShell wrapper passes args safely.
    max_batch_chars="${SECONDLOOP_FLUTTER_TEST_MAX_BATCH_CHARS:-6000}"
    max_batch_targets="${SECONDLOOP_FLUTTER_TEST_MAX_BATCH_TARGETS:-48}"
  fi

  [[ "${max_batch_chars}" =~ ^[0-9]+$ ]] ||
    die "SECONDLOOP_FLUTTER_TEST_MAX_BATCH_CHARS must be a positive integer"
  [[ "${max_batch_targets}" =~ ^[0-9]+$ ]] ||
    die "SECONDLOOP_FLUTTER_TEST_MAX_BATCH_TARGETS must be a positive integer"
  (( max_batch_chars > 0 )) ||
    die "SECONDLOOP_FLUTTER_TEST_MAX_BATCH_CHARS must be greater than 0"
  (( max_batch_targets > 0 )) ||
    die "SECONDLOOP_FLUTTER_TEST_MAX_BATCH_TARGETS must be greater than 0"
  [[ "${max_retry_attempts}" =~ ^[0-9]+$ ]] ||
    die "SECONDLOOP_FLUTTER_TEST_RETRY_ATTEMPTS must be a positive integer"
  (( max_retry_attempts > 0 )) ||
    die "SECONDLOOP_FLUTTER_TEST_RETRY_ATTEMPTS must be greater than 0"

  is_retryable_flutter_test_failure() {
    local log_path="$1"
    grep -Fq "the Dart compiler exited unexpectedly" "${log_path}" || \
      grep -Fq "TestDeviceException(Shell subprocess crashed with SIGTERM (-15).)" "${log_path}"
  }

  run_retryable_batch() {
    local current_batch_index="$1"
    shift

    local attempt=1
    local batch_log
    local status

    while true; do
      batch_log="$(mktemp -t "secondloop_flutter_batch_${shard_index}_${current_batch_index}.XXXXXX.log")"
      if run_with_periodic_status \
        "flutter test shard ${shard_index}/${shard_count} (unit batch ${current_batch_index})" \
        run_flutter_tool test --concurrency=1 "$@" >"${batch_log}" 2>&1; then
        cat "${batch_log}"
        rm -f "${batch_log}"
        return 0
      fi

      status=$?
      if (( attempt < max_retry_attempts )) && is_retryable_flutter_test_failure "${batch_log}"; then
        echo \
          "flutter-test-shard: retrying unit batch ${current_batch_index} after transient Dart compiler failure (${attempt}/${max_retry_attempts})" \
          >&2
        rm -f "${batch_log}"
        attempt=$((attempt + 1))
        sleep 1
        continue
      fi

      cat "${batch_log}"
      rm -f "${batch_log}"
      return "${status}"
    done
  }

  run_batch() {
    local current_batch_index="$1"
    shift
    run_retryable_batch "${current_batch_index}" "$@"
  }

  for target in "$@"; do
    target_chars=$(( ${#target} + 1 ))
    if (( ${#batch_targets[@]} > 0 )) && \
      (( ${#batch_targets[@]} >= max_batch_targets || batch_chars + target_chars > max_batch_chars )); then
      run_batch "${batch_index}" "${batch_targets[@]}"
      batch_targets=()
      batch_chars=0
      batch_index=$((batch_index + 1))
    fi

    batch_targets+=("${target}")
    batch_chars=$((batch_chars + target_chars))
  done

  if (( ${#batch_targets[@]} > 0 )); then
    run_batch "${batch_index}" "${batch_targets[@]}"
  fi
}

if [[ ! -f "${repo_root}/lib/i18n/strings.g.dart" ]]; then
  die "lib/i18n/strings.g.dart is required before running shards. Run \`pixi run i18n-refresh\` or use scripts/run_flutter_ci_local.sh."
fi

selector_output=""
if ! selector_output="$(bash scripts/select_flutter_test_targets.sh --repo-root "${repo_root}" --shard-index "${shard_index}" --shard-count "${shard_count}")"; then
  die "failed to select test targets for shard ${shard_index}/${shard_count}"
fi

test_targets=()
while IFS= read -r target; do
  [[ -n "${target}" ]] || continue
  test_targets+=("${target}")
done <<< "${selector_output}"

if [[ ${#test_targets[@]} -eq 0 ]]; then
  echo "flutter-test-shard: no tests assigned to shard ${shard_index}/${shard_count}" >&2
  exit 0
fi

resolve_flutter_bin >/dev/null || die "Missing 'flutter'. Install Flutter (recommended: \`pixi run setup-flutter\`) or add Flutter to PATH."

unit_test_targets=()
integration_test_targets=()

for target in "${test_targets[@]}"; do
  case "${target}" in
    integration_test/*) integration_test_targets+=("${target}") ;;
    *) unit_test_targets+=("${target}") ;;
  esac
done

if [[ ${#unit_test_targets[@]} -ne 0 ]]; then
  run_flutter_unit_tests_in_batches "${unit_test_targets[@]}"
fi

if [[ ${#integration_test_targets[@]} -ne 0 ]]; then
  integration_test_device="$(resolve_default_flutter_test_device)" ||
    die "unable to determine a default Flutter integration test device. Set SECONDLOOP_FLUTTER_TEST_DEVICE_ID."
  if [[ "${integration_test_device}" == "macos" ]]; then
    if [[ "${SECONDLOOP_ENABLE_MACOS_INTEGRATION_TESTS:-0}" != "1" ]]; then
      echo \
        "flutter-test-shard: skipping macOS integration tests by default; set SECONDLOOP_ENABLE_MACOS_INTEGRATION_TESTS=1 to run them locally." \
        >&2
      exit 0
    fi
    # Local desktop runs use the dev app identity and allow Xcode to refresh provisioning data.
    export SECONDLOOP_APP_ID="${SECONDLOOP_APP_ID:-com.secondloop.secondloopdev}"
    export SECONDLOOP_APP_NAME="${SECONDLOOP_APP_NAME:-SecondLoop Dev}"
    macos_xcrun_wrapper_dir="$(create_macos_xcrun_wrapper)"
    export PATH="${macos_xcrun_wrapper_dir}:${PATH}"
  fi
  for target in "${integration_test_targets[@]}"; do
    if [[ "${integration_test_device}" == "linux" ]]; then
      run_with_periodic_status \
        "flutter test shard ${shard_index}/${shard_count} (integration: ${target})" \
        run_linux_integration_test "${integration_test_device}" "${target}"
    else
      run_with_periodic_status \
        "flutter test shard ${shard_index}/${shard_count} (integration: ${target})" \
        run_flutter_tool test -d "${integration_test_device}" --concurrency=1 "${target}"
    fi
  done
fi
