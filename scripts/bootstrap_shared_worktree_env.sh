#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: bash scripts/bootstrap_shared_worktree_env.sh [--dry-run] [--skip-pixi-envs]

Bootstrap shared caches for a git worktree checkout.

By default this links these paths to the git-common-dir shared storage:
- .tool
- .pixi/envs (bucketed by pixi.lock hash)

Options:
  --dry-run         Print actions without changing files.
  --skip-pixi-envs Keep .pixi/envs untouched.
  -h, --help        Show this help message.
EOF
}

dry_run=0
skip_pixi_envs=0

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

echo "Done. Shared worktree cache is ready."
