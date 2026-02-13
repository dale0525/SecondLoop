#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: bash scripts/bootstrap_shared_worktree_env.sh [--dry-run] [--skip-pixi-envs] [--skip-fvm-sdk-link] [--skip-env-local-link] [--skip-android-key-link]

Bootstrap shared caches for a git worktree checkout.

By default this links these paths for worktree reuse:
- .tool (to git-common-dir shared storage)
- .pixi/envs (bucketed by pixi.lock hash, under git-common-dir shared storage)
- .fvm/flutter_sdk (to primary worktree when available)
- .env.local (to primary worktree when available)
- android/key.properties (to primary worktree when available)
- android/app/upload-keystore.jks (to primary worktree when available)

Options:
  --dry-run         Print actions without changing files.
  --skip-pixi-envs      Keep .pixi/envs untouched.
  --skip-fvm-sdk-link   Keep .fvm/flutter_sdk untouched.
  --skip-env-local-link Keep .env.local untouched.
  --skip-android-key-link Keep Android signing files untouched.
  -h, --help        Show this help message.
EOF
}

dry_run=0
skip_pixi_envs=0
skip_fvm_sdk_link=0
skip_env_local_link=0
skip_android_key_link=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --)
      shift
      ;;
    --dry-run)
      dry_run=1
      shift
      ;;
    --skip-pixi-envs)
      skip_pixi_envs=1
      shift
      ;;
    --skip-fvm-sdk-link)
      skip_fvm_sdk_link=1
      shift
      ;;
    --skip-env-local-link)
      skip_env_local_link=1
      shift
      ;;
    --skip-android-key-link)
      skip_android_key_link=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

run_cmd() {
  if [[ "$dry_run" -eq 1 ]]; then
    printf '[dry-run]'
    printf ' %q' "$@"
    printf '\n'
    return 0
  fi
  "$@"
}

dir_has_contents() {
  local dir_path="$1"
  [[ -d "$dir_path" ]] && [[ -n "$(find "$dir_path" -mindepth 1 -print -quit 2>/dev/null || true)" ]]
}

hash_file() {
  local file_path="$1"
  if command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$file_path" | awk '{print $1}'
    return 0
  fi

  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$file_path" | awk '{print $1}'
    return 0
  fi

  echo "Missing dependency: shasum or sha256sum" >&2
  exit 1
}

resolve_primary_worktree_root() {
  local primary_root
  primary_root="$(cd "${common_dir}/.." 2>/dev/null && pwd)" || return 1
  if [[ "${primary_root}" == "${repo_root}" ]]; then
    return 1
  fi

  printf '%s\n' "${primary_root}"
}

link_path_from_primary() {
  local primary_root="$1"
  local relative_path="$2"
  local label="$3"
  local primary_path="${primary_root}/${relative_path}"
  local local_path="${repo_root}/${relative_path}"

  if [[ ! -e "${primary_path}" && ! -L "${primary_path}" ]]; then
    echo "Skipping ${label} link: primary worktree has no ${relative_path} (${primary_path})"
    return 0
  fi

  run_cmd mkdir -p "$(dirname "${local_path}")"

  if [[ -L "${local_path}" ]]; then
    local current_link
    current_link="$(readlink "${local_path}")"
    if [[ "${current_link}" == "${primary_path}" ]]; then
      echo "Already linked: ${label} -> ${primary_path}"
      return 0
    fi

    echo "Updating link for ${label}"
    run_cmd rm "${local_path}"
    run_cmd ln -s "${primary_path}" "${local_path}"
    return 0
  fi

  if [[ -e "${local_path}" ]]; then
    echo "Keeping existing ${label} (not symlink): ${local_path}"
    return 0
  fi

  echo "Linking ${label} -> ${primary_path}"
  run_cmd ln -s "${primary_path}" "${local_path}"
}

link_fvm_sdk_from_primary() {
  local primary_root="$1"
  link_path_from_primary "${primary_root}" ".fvm/flutter_sdk" ".fvm/flutter_sdk"
}

link_file_from_primary() {
  local primary_root="$1"
  local relative_path="$2"
  local label="$3"
  local primary_file="${primary_root}/${relative_path}"

  if [[ ! -f "${primary_file}" ]]; then
    echo "Skipping ${label} link: primary worktree has no ${relative_path} (${primary_file})"
    return 0
  fi

  link_path_from_primary "${primary_root}" "${relative_path}" "${label}"
}

link_env_local_from_primary() {
  local primary_root="$1"
  link_file_from_primary "${primary_root}" ".env.local" ".env.local"
}

link_android_key_files_from_primary() {
  local primary_root="$1"
  link_file_from_primary "${primary_root}" "android/key.properties" "android/key.properties"
  link_file_from_primary "${primary_root}" "android/app/upload-keystore.jks" "android/app/upload-keystore.jks"
}

link_to_shared() {
  local local_path="$1"
  local shared_path="$2"
  local label="$3"

  run_cmd mkdir -p "$shared_path"
  run_cmd mkdir -p "$(dirname "$local_path")"

  if [[ -L "$local_path" ]]; then
    local current_link
    current_link="$(readlink "$local_path")"
    if [[ "$current_link" == "$shared_path" ]]; then
      echo "Already linked: $label -> $shared_path"
      return 0
    fi

    echo "Updating link for $label"
    run_cmd rm "$local_path"
    run_cmd ln -s "$shared_path" "$local_path"
    return 0
  fi

  if [[ -e "$local_path" && ! -d "$local_path" ]]; then
    echo "Expected directory for $label, got non-directory: $local_path" >&2
    exit 1
  fi

  if dir_has_contents "$local_path"; then
    echo "Migrating existing data for $label"
    if [[ "$dry_run" -eq 1 ]]; then
      printf '[dry-run]'
      printf ' %q' rsync -a "$local_path/" "$shared_path/"
      printf '\n'
    else
      rsync -a "$local_path/" "$shared_path/"
    fi
  fi

  if [[ -e "$local_path" || -L "$local_path" ]]; then
    run_cmd rm -rf "$local_path"
  fi

  echo "Linking $label -> $shared_path"
  run_cmd ln -s "$shared_path" "$local_path"
}

if ! command -v git >/dev/null 2>&1; then
  echo "Missing dependency: git" >&2
  exit 1
fi

if ! command -v rsync >/dev/null 2>&1; then
  echo "Missing dependency: rsync" >&2
  exit 1
fi

repo_root="$(git rev-parse --show-toplevel 2>/dev/null || true)"
if [[ -z "$repo_root" ]]; then
  echo "This script must run inside a git worktree checkout." >&2
  exit 1
fi

common_dir_raw="$(git -C "$repo_root" rev-parse --git-common-dir)"
if [[ "$common_dir_raw" == /* ]]; then
  common_dir="$common_dir_raw"
else
  common_dir="$repo_root/$common_dir_raw"
fi
common_dir="$(cd "$common_dir" && pwd)"

shared_root="$common_dir/secondloop-shared"
shared_tool="$shared_root/.tool"

lock_file="$repo_root/pixi.lock"
if [[ -f "$lock_file" ]]; then
  lock_hash="$(hash_file "$lock_file")"
  lock_hash="${lock_hash:0:16}"
else
  lock_hash="no-lock"
fi
shared_pixi_envs="$shared_root/.pixi-envs/$lock_hash"

echo "Repo root: $repo_root"
echo "Git common dir: $common_dir"
echo "Shared root: $shared_root"

link_to_shared "$repo_root/.tool" "$shared_tool" ".tool"
if [[ -e "$repo_root/.tools" || -L "$repo_root/.tools" ]]; then
  echo "Removing obsolete .tools path"
  run_cmd rm -rf "$repo_root/.tools"
fi

if [[ -e "$repo_root/tool" || -L "$repo_root/tool" ]]; then
  echo "Removing obsolete tool path"
  run_cmd rm -rf "$repo_root/tool"
fi

if [[ "$skip_pixi_envs" -eq 0 ]]; then
  link_to_shared "$repo_root/.pixi/envs" "$shared_pixi_envs" ".pixi/envs"
else
  echo "Skipping .pixi/envs linking (--skip-pixi-envs)."
fi

primary_root="$(resolve_primary_worktree_root || true)"

if [[ "$skip_fvm_sdk_link" -eq 0 ]]; then
  if [[ -n "${primary_root}" ]]; then
    link_fvm_sdk_from_primary "${primary_root}"
  else
    echo "Skipping .fvm/flutter_sdk link: current checkout is primary worktree."
  fi
else
  echo "Skipping .fvm/flutter_sdk linking (--skip-fvm-sdk-link)."
fi

if [[ "$skip_env_local_link" -eq 0 ]]; then
  if [[ -n "${primary_root}" ]]; then
    link_env_local_from_primary "${primary_root}"
  else
    echo "Skipping .env.local link: current checkout is primary worktree."
  fi
else
  echo "Skipping .env.local linking (--skip-env-local-link)."
fi

if [[ "$skip_android_key_link" -eq 0 ]]; then
  if [[ -n "${primary_root}" ]]; then
    link_android_key_files_from_primary "${primary_root}"
  else
    echo "Skipping Android key linking: current checkout is primary worktree."
  fi
else
  echo "Skipping Android key linking (--skip-android-key-link)."
fi

echo "Done. Shared worktree cache is ready."
