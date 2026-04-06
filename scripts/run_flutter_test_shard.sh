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

if is_windows_env; then
  resolve_cargo_bin || cargo_missing_message
  resolve_libclang_path || libclang_missing_message
  resolve_vulkan_sdk_root || vulkan_sdk_missing_message
  ensure_windows_short_build_paths
fi

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
  run_with_periodic_status \
    "flutter test shard ${shard_index}/${shard_count} (unit)" \
    run_flutter_tool test --concurrency=1 "${unit_test_targets[@]}"
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
