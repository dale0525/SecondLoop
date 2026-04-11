#!/usr/bin/env bash
set -euo pipefail

repo_root="$(git rev-parse --show-toplevel 2>/dev/null || true)"
if [[ -z "${repo_root}" ]]; then
  exit 0
fi

cd "${repo_root}"

cleaned=0

remove_target_extras() {
  local target_dir="$1"
  if [[ ! -d "${target_dir}" ]]; then
    return 0
  fi

  cleaned=1
  rm -rf "${target_dir}/release" "${target_dir}/doc" "${target_dir}/package"
  find "${target_dir}" -mindepth 2 -maxdepth 2 -type d \( -name release -o -name doc -o -name package \) -prune -exec rm -rf {} +
}

while IFS= read -r -d "" cache_tag; do
  remove_target_extras "${cache_tag%/CACHEDIR.TAG}"
done < <(find . -type f -path "*/target/CACHEDIR.TAG" -print0)

if [[ -n "${CARGO_TARGET_DIR:-}" ]]; then
  remove_target_extras "${CARGO_TARGET_DIR}"
fi

while IFS= read -r -d "" pycache_dir; do
  cleaned=1
  rm -rf "${pycache_dir}"
done < <(find ./tools -type d -name "__pycache__" -print0 2>/dev/null || true)

while IFS= read -r -d "" gradle_cold_dir; do
  cleaned=1
  rm -rf "${gradle_cold_dir}"
done < <(find .tool -maxdepth 1 -mindepth 1 -type d -name "gradle-cold-*" -print0 2>/dev/null || true)

while IFS= read -r -d "" tool_cache_dir; do
  cleaned=1
  rm -rf "${tool_cache_dir}"
done < <(find .tool/cache -maxdepth 1 -mindepth 1 -type d \( -name android -o -name rustup \) -print0 2>/dev/null || true)

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
        cleaned=1
        echo "Removing stale shared Rust CI cache: ${cache_dir}"
        rm -rf "${cache_dir}"
      fi
    done < <(find "${shared_cache_dir}" -maxdepth 1 -mindepth 1 -type d -name "rust-ci-target-*" -print0 2>/dev/null)

    rm -f "${active_keys_file}"
    trap - EXIT
  fi
fi

if [[ "${cleaned}" -eq 0 ]]; then
  echo "No unused cache found under ${repo_root} or shared Rust CI cache"
fi
