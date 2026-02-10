#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  pixi run release vX.Y.Z
  pixi run release vX.Y.Z.W

Options:
  --dry-run          Print commands without running them
  --remote <name>    Git remote name (default: origin)
  --allow-dirty      Allow tagging with uncommitted changes
  --force            Move tag if it already exists (DANGEROUS)

Notes:
  - Requires current branch to be 'main' and up-to-date with <remote>/main.
  - Tag format must match: vX.Y.Z or vX.Y.Z.W (e.g. v0.1.0, v0.1.0.1).
  - This command only publishes app tags.
  - Runtime release tags are managed separately via: pixi run release-runtime vX.Y.Z[.W]
EOF
}

die() {
  echo "release: $*" >&2
  exit 1
}

require_cmd() {
  local cmd="$1"
  command -v "${cmd}" >/dev/null 2>&1 || die "Missing required command: ${cmd}"
}

require_cmd git

dry_run=0
remote="origin"
allow_dirty=0
force=0

args=("$@")
tag=""

while [[ ${#args[@]} -gt 0 ]]; do
  case "${args[0]}" in
    -h|--help)
      usage
      exit 0
      ;;
    --dry-run)
      dry_run=1
      args=("${args[@]:1}")
      ;;
    --remote)
      if [[ ${#args[@]} -lt 2 ]]; then
        die "--remote requires a value"
      fi
      remote="${args[1]}"
      args=("${args[@]:2}")
      ;;
    --allow-dirty)
      allow_dirty=1
      args=("${args[@]:1}")
      ;;
    --force)
      force=1
      args=("${args[@]:1}")
      ;;
    --*)
      die "Unknown option: ${args[0]}"
      ;;
    *)
      if [[ -n "${tag}" ]]; then
        die "Unexpected extra argument: ${args[0]}"
      fi
      tag="${args[0]}"
      args=("${args[@]:1}")
      ;;
  esac
done

if [[ -z "${tag}" ]]; then
  usage
  exit 2
fi

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "${script_dir}/.." && pwd)"
cd "${repo_root}"

if [[ ! "${tag}" =~ ^v[0-9]+\.[0-9]+\.[0-9]+(\.[0-9]+)?$ ]]; then
  die "Invalid tag '${tag}'. Expected vX.Y.Z or vX.Y.Z.W (e.g. v0.1.0, v0.1.0.1)."
fi

run() {
  if (( dry_run )); then
    printf '+'
    printf ' %q' "$@"
    printf '\n'
    return 0
  fi
  "$@"
}

if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  die "Not a git repository"
fi

branch="$(git rev-parse --abbrev-ref HEAD)"
if [[ "${branch}" != "main" ]]; then
  die "Must be on 'main' branch (current: ${branch})"
fi

if (( ! allow_dirty )); then
  if ! git diff --quiet || ! git diff --cached --quiet; then
    die "Working tree is dirty. Commit/stash changes or pass --allow-dirty."
  fi
  if [[ -n "$(git status --porcelain)" ]]; then
    die "Working tree has untracked changes. Clean it up or pass --allow-dirty."
  fi
fi

run git fetch "${remote}" --tags

run bash scripts/release_preflight.sh --remote "${remote}"

if ! git show-ref --verify --quiet "refs/remotes/${remote}/main"; then
  die "Remote '${remote}' does not have branch '${remote}/main' (did you fetch?)"
fi

head_sha="$(git rev-parse HEAD)"
remote_main_sha="$(git rev-parse "refs/remotes/${remote}/main")"
if [[ "${head_sha}" != "${remote_main_sha}" ]]; then
  die "main is not up-to-date with ${remote}/main (HEAD=${head_sha}, ${remote}/main=${remote_main_sha})"
fi

if git rev-parse -q --verify "refs/tags/${tag}" >/dev/null 2>&1; then
  if (( ! force )); then
    die "Tag '${tag}' already exists. Use --force to move it (not recommended)."
  fi
fi

if (( force )); then
  run git tag -a "${tag}" -m "Release ${tag}" -f "${head_sha}"
  run git push "${remote}" --force "${tag}"
else
  run git tag -a "${tag}" -m "Release ${tag}" "${head_sha}"
  run git push "${remote}" "${tag}"
fi

if (( dry_run )); then
  echo "release: (dry-run) would push app tag ${tag} -> ${remote} (${head_sha})"
else
  echo "release: pushed app tag ${tag} -> ${remote} (${head_sha})"
fi
