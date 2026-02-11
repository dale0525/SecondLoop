#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF_USAGE'
Usage:
  pixi run release

Options:
  --dry-run          Execute checks + tag + notes preview, but skip git tag/push
  --remote <name>    Git remote name (default: origin)
  --allow-dirty      Allow tagging with uncommitted changes
  --force            Move tag if it already exists (DANGEROUS)

Notes:
  - Requires current branch to be 'main' and up-to-date with <remote>/main.
  - Computes release tag automatically via scripts/release_ai.py.
  - Tag format is strict SemVer: vX.Y.Z.
  - Requires RELEASE_LLM_API_KEY and RELEASE_LLM_MODEL.
  - In --dry-run, local LLM calls skip TLS cert verification.
  - Loads env from .env.local when present.
  - This command only publishes app tags.
  - Runtime release tags are managed separately via: pixi run release-runtime vX.Y.Z[.W]
EOF_USAGE
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
require_cmd python3

dry_run=0
remote="origin"
allow_dirty=0
force=0

args=("$@")

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
      die "Unexpected argument: ${args[0]}. Usage: pixi run release"
      ;;
  esac
done

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "${script_dir}/.." && pwd)"
cd "${repo_root}"

dotenv_file="${repo_root}/.env.local"
if [[ -f "${dotenv_file}" ]]; then
  set -a
  # shellcheck disable=SC1090
  source "${dotenv_file}"
  set +a
fi

if [[ -z "${RELEASE_LLM_API_KEY:-}" ]]; then
  die "Missing RELEASE_LLM_API_KEY"
fi
if [[ -z "${RELEASE_LLM_MODEL:-}" ]]; then
  die "Missing RELEASE_LLM_MODEL"
fi

if (( dry_run )); then
  export RELEASE_LLM_INSECURE_SKIP_VERIFY=1
  echo "release: (dry-run) local LLM TLS certificate verification disabled"
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

run_readonly() {
  if (( dry_run )); then
    printf '+'
    printf ' %q' "$@"
    printf '\n'
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

run_readonly git fetch "${remote}" --tags
run_readonly bash scripts/release_preflight.sh --remote "${remote}"

if ! git show-ref --verify --quiet "refs/remotes/${remote}/main"; then
  die "Remote '${remote}' does not have branch '${remote}/main' (did you fetch?)"
fi

head_sha="$(git rev-parse HEAD)"
remote_main_sha="$(git rev-parse "refs/remotes/${remote}/main")"
if [[ "${head_sha}" != "${remote_main_sha}" ]]; then
  die "main is not up-to-date with ${remote}/main (HEAD=${head_sha}, ${remote}/main=${remote_main_sha})"
fi

repo_slug=""
remote_url="$(git remote get-url "${remote}" 2>/dev/null || true)"
if [[ "${remote_url}" =~ ^https://github\.com/([^/]+/[^/.]+)(\.git)?$ ]]; then
  repo_slug="${BASH_REMATCH[1]}"
elif [[ "${remote_url}" =~ ^git@github\.com:([^/]+/[^/.]+)(\.git)?$ ]]; then
  repo_slug="${BASH_REMATCH[1]}"
fi

dist_dir="dist"
facts_json="${dist_dir}/release_facts.json"
decision_json="${dist_dir}/release_version_decision.json"
tag_json="${dist_dir}/release_tag.json"
run_readonly mkdir -p "${dist_dir}"

collect_cmd=(python3 scripts/release_ai.py collect-facts --base-tag auto --head HEAD --output "${facts_json}")
if [[ -n "${repo_slug}" ]]; then
  collect_cmd+=(--repo "${repo_slug}")
fi

run_readonly "${collect_cmd[@]}"
run_readonly python3 scripts/release_ai.py decide-bump --facts "${facts_json}" --output "${decision_json}"
run_readonly python3 scripts/release_ai.py compute-tag --facts "${facts_json}" --decision "${decision_json}" --output "${tag_json}"

tag="$(python3 - <<'PY' "${tag_json}"
import json
import sys

with open(sys.argv[1], encoding='utf-8') as f:
    payload = json.load(f)

print(payload['tag'])
PY
)"

if [[ ! "${tag}" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  die "Invalid computed tag '${tag}'. Expected vX.Y.Z."
fi

if (( dry_run )); then
  echo "release: (dry-run) computed next app tag ${tag}"
fi

if (( dry_run )); then
  release_notes_locales="${RELEASE_NOTES_LOCALES:-zh-CN,en-US}"
  notes_dir="${dist_dir}/release-notes"
  notes_markdown="${dist_dir}/release-notes.md"

  run_readonly python3 scripts/release_ai.py generate-notes --facts "${facts_json}" --tag "${tag}" --locales "${release_notes_locales}" --output-dir "${notes_dir}"
  run_readonly python3 scripts/release_ai.py validate-notes --facts "${facts_json}" --tag "${tag}" --locales "${release_notes_locales}" --notes-dir "${notes_dir}"
  run_readonly python3 scripts/release_ai.py render-markdown --tag "${tag}" --locales "${release_notes_locales}" --notes-dir "${notes_dir}" --facts "${facts_json}" --output "${notes_markdown}"

  echo "release: (dry-run) generated release notes preview at ${notes_markdown} for locales: ${release_notes_locales}"
fi

if git rev-parse -q --verify "refs/tags/${tag}" >/dev/null 2>&1; then
  if (( ! force )); then
    die "Computed tag '${tag}' already exists. Use --force to move it (not recommended)."
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
