#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

clear_pub_advisories_cache() {
  local -a cache_roots=()

  if [[ -n "${PUB_CACHE:-}" ]]; then
    cache_roots+=("${PUB_CACHE}")
  fi
  cache_roots+=("${repo_root}/.tool/pub-cache")
  if [[ -n "${HOME:-}" ]]; then
    cache_roots+=("${HOME}/.pub-cache")
  fi

  local cache_root
  for cache_root in "${cache_roots[@]}"; do
    if [[ -z "${cache_root}" || ! -d "${cache_root}/hosted" ]]; then
      continue
    fi
    find "${cache_root}/hosted" \
      -path "*/.cache/*-advisories.json" \
      -type f \
      -delete 2>/dev/null || true
  done
}

run_flutter_pub_get() {
  local project_flutter="${repo_root}/.fvm/flutter_sdk/bin/flutter"

  if [[ -x "${project_flutter}" ]]; then
    "${project_flutter}" pub get "$@"
    return $?
  fi

  dart pub global run fvm:main flutter pub get "$@"
}

clear_pub_advisories_cache

if run_flutter_pub_get "$@"; then
  exit 0
fi

echo "SecondLoop: flutter pub get failed; clearing hosted pub advisories cache and retrying once." >&2
clear_pub_advisories_cache
run_flutter_pub_get "$@"
