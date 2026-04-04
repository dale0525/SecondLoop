#!/usr/bin/env bash
set -euo pipefail

die() {
  echo "select-flutter-tests: $*" >&2
  exit 1
}

repo_root=""
shard_index=""
shard_count=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo-root)
      repo_root="${2:-}"
      shift 2
      ;;
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

[[ -n "${repo_root}" ]] || die "--repo-root is required"
[[ -n "${shard_index}" ]] || die "--shard-index is required"
[[ -n "${shard_count}" ]] || die "--shard-count is required"
[[ "${shard_count}" =~ ^[0-9]+$ ]] || die "shard-count must be a positive integer"
[[ "${shard_index}" =~ ^[0-9]+$ ]] || die "shard-index must be a non-negative integer"
(( shard_count > 0 )) || die "shard-count must be greater than 0"
(( shard_index >= 0 && shard_index < shard_count )) || die "shard-index must be between 0 and shard-count - 1"

cd "${repo_root}"

unit_search_roots=()
if [[ -d "test" ]]; then
  unit_search_roots+=("test")
fi

integration_search_roots=()
if [[ -d "integration_test" ]]; then
  integration_search_roots+=("integration_test")
fi

if [[ ${#unit_search_roots[@]} -eq 0 && ${#integration_search_roots[@]} -eq 0 ]]; then
  exit 0
fi

if [[ ${#unit_search_roots[@]} -ne 0 ]]; then
  find "${unit_search_roots[@]}" -type f -name '*_test.dart' | LC_ALL=C sort | awk -v shard_count="${shard_count}" -v shard_index="${shard_index}" '
    ((NR - 1) % shard_count) == shard_index {
      print $0
    }
  '
fi

# Desktop integration tests target a single host device, so keep them on one shard.
if [[ ${shard_index} -eq 0 && ${#integration_search_roots[@]} -ne 0 ]]; then
  find "${integration_search_roots[@]}" -type f -name '*_test.dart' | LC_ALL=C sort
fi
