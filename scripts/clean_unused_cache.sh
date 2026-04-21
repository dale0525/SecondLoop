#!/usr/bin/env bash
set -euo pipefail

repo_root="$(git rev-parse --show-toplevel 2>/dev/null || true)"
if [[ -z "${repo_root}" ]]; then
  exit 0
fi

cd "${repo_root}"

cleaned=0

mark_cleaned() {
  cleaned=1
}

remove_path_if_exists() {
  local path="$1"
  if [[ ! -e "${path}" ]]; then
    return 0
  fi

  rm -rf "${path}"
  mark_cleaned
}

remove_named_entries() {
  local root_dir="$1"
  shift

  if [[ ! -d "${root_dir}" ]]; then
    return 0
  fi

  local resolved_root
  resolved_root="$(cd "${root_dir}" 2>/dev/null && pwd -P)"
  if [[ -z "${resolved_root}" || ! -d "${resolved_root}" ]]; then
    return 0
  fi

  local pattern
  for pattern in "$@"; do
    while IFS= read -r -d "" matched_path; do
      rm -rf "${matched_path}"
      mark_cleaned
    done < <(find "${resolved_root}" -maxdepth 1 -mindepth 1 -name "${pattern}" -print0 2>/dev/null || true)
  done
}

remove_target_extras() {
  local target_dir="$1"
  if [[ ! -d "${target_dir}" ]]; then
    return 0
  fi

  remove_path_if_exists "${target_dir}/release"
  remove_path_if_exists "${target_dir}/doc"
  remove_path_if_exists "${target_dir}/package"
  remove_path_if_exists "${target_dir}/tmp"

  while IFS= read -r -d "" nested_target_dir; do
    rm -rf "${nested_target_dir}"
    mark_cleaned
  done < <(
    find "${target_dir}" -mindepth 2 -maxdepth 2 -type d \
      \( -name release -o -name doc -o -name package -o -name tmp \) \
      -print0 2>/dev/null || true
  )
}

echo "Running existing cache cleanup..."

while IFS= read -r -d "" cache_tag; do
  remove_target_extras "${cache_tag%/CACHEDIR.TAG}"
done < <(find . -type f -path "*/target/CACHEDIR.TAG" -print0)

if [[ -n "${CARGO_TARGET_DIR:-}" ]]; then
  remove_target_extras "${CARGO_TARGET_DIR}"
fi

while IFS= read -r -d "" pycache_dir; do
  rm -rf "${pycache_dir}"
  mark_cleaned
done < <(find ./tools -type d -name "__pycache__" -print0 2>/dev/null || true)

while IFS= read -r -d "" gradle_cold_dir; do
  rm -rf "${gradle_cold_dir}"
  mark_cleaned
done < <(find .tool -maxdepth 1 -mindepth 1 -type d -name "gradle-cold-*" -print0 2>/dev/null || true)

while IFS= read -r -d "" tool_cache_dir; do
  rm -rf "${tool_cache_dir}"
  mark_cleaned
done < <(find .tool/cache -maxdepth 1 -mindepth 1 -type d \( -name android -o -name rustup \) -print0 2>/dev/null || true)

echo "Running conservative cleanup..."

remove_path_if_exists "${repo_root}/build"
remove_path_if_exists "${repo_root}/.dart_tool"
remove_named_entries "${repo_root}/.tool" "wasm-pack-probe.*"
remove_named_entries "${repo_root}/.tool/cache" "*.log" "*.txt"

tmpdir_root="${TMPDIR:-}"
if [[ -n "${tmpdir_root}" && -d "${tmpdir_root}" ]]; then
  remove_named_entries "${tmpdir_root}" \
    "secondloop_*log*" \
    "secondloop_ci_*log*" \
    "flutter_tools.*" \
    "Alamofire_CFNetworkDownload_*.tmp"
fi

echo "Slimming Rust target caches..."

common_dir_raw="$(git -C "${repo_root}" rev-parse --git-common-dir 2>/dev/null || true)"
if [[ -n "${common_dir_raw}" ]]; then
  if [[ "${common_dir_raw}" == /* ]]; then
    common_dir="${common_dir_raw}"
  else
    common_dir="${repo_root}/${common_dir_raw}"
  fi
  common_dir="$(cd "${common_dir}" && pwd)"
  shared_cache_dir="${common_dir}/secondloop-shared/.tool/cache"

  if [[ -d "${shared_cache_dir}" ]]; then
    active_keys_file="$(mktemp)"
    trap 'rm -f "${active_keys_file}"' EXIT

    git -C "${repo_root}" worktree list --porcelain \
      | awk '/^worktree / { print substr($0, 10) }' \
      | while IFS= read -r worktree_path; do
        printf '%s\n' "${worktree_path}" | cksum | awk '{print $1}' >> "${active_keys_file}"
      done

    while IFS= read -r -d "" cache_dir; do
      cache_name="$(basename "${cache_dir}")"
      cache_key="${cache_name#rust-ci-target-}"
      if ! grep -Fqx "${cache_key}" "${active_keys_file}"; then
        mark_cleaned
        echo "Removing stale shared Rust CI cache: ${cache_dir}"
        rm -rf "${cache_dir}"
      fi
    done < <(find "${shared_cache_dir}" -maxdepth 1 -mindepth 1 -type d -name "rust-ci-target-*" -print0 2>/dev/null)

    rm -f "${active_keys_file}"
    trap - EXIT
  fi
fi

if [[ "${cleaned}" -eq 0 ]]; then
  echo "No existing cache, conservative cleanup target, or shared Rust CI cache needed cleanup under ${repo_root}"
fi
