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
  for target in "${integration_test_targets[@]}"; do
    run_with_periodic_status \
      "flutter test shard ${shard_index}/${shard_count} (integration: ${target})" \
      run_flutter_tool test -d "${integration_test_device}" --concurrency=1 "${target}"
  done
fi
