#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage: publish_winget_manifest.sh --release-tag <vX.Y.Z> --source-repo <owner/repo> --fork-repo <owner/repo> --token <github-token> [--upstream-repo <owner/repo>] [--package-id <id>] [--auto-agree-cla[=true|false]] [--cla-company <name>]

Generate WinGet manifests for the given release and open a PR against microsoft/winget-pkgs.
USAGE
}

release_tag=''
source_repo=''
fork_repo=''
token=''
upstream_repo='microsoft/winget-pkgs'
package_id='SecondLoop.SecondLoop'
auto_agree_cla="${WINGET_AUTO_AGREE_CLA:-false}"
cla_company="${WINGET_CLA_COMPANY:-}"

normalize_bool() {
  local raw="${1:-}"
  local lowered
  lowered="$(tr '[:upper:]' '[:lower:]' <<<"${raw}")"
  case "${lowered}" in
    1|true|yes|on)
      echo "true"
      ;;
    0|false|no|off|'')
      echo "false"
      ;;
    *)
      echo "Invalid boolean value: ${raw}" >&2
      exit 1
      ;;
  esac
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --release-tag)
      release_tag="${2:-}"
      shift 2
      ;;
    --source-repo)
      source_repo="${2:-}"
      shift 2
      ;;
    --fork-repo)
      fork_repo="${2:-}"
      shift 2
      ;;
    --token)
      token="${2:-}"
      shift 2
      ;;
    --upstream-repo)
      upstream_repo="${2:-}"
      shift 2
      ;;
    --package-id)
      package_id="${2:-}"
      shift 2
      ;;
    --auto-agree-cla)
      auto_agree_cla='true'
      shift
      ;;
    --auto-agree-cla=*)
      auto_agree_cla="${1#*=}"
      shift
      ;;
    --cla-company)
      cla_company="${2:-}"
      shift 2
      ;;
    --cla-company=*)
      cla_company="${1#*=}"
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

if [[ -z "${release_tag}" || -z "${source_repo}" || -z "${fork_repo}" || -z "${token}" ]]; then
  usage >&2
  exit 2
fi
auto_agree_cla="$(normalize_bool "${auto_agree_cla}")"

if [[ ! "${release_tag}" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "Invalid release tag: ${release_tag}. Expected vX.Y.Z" >&2
  exit 1
fi

if ! command -v gh >/dev/null 2>&1; then
  echo "gh CLI is required" >&2
  exit 1
fi
if ! command -v git >/dev/null 2>&1; then
  echo "git is required" >&2
  exit 1
fi
if ! command -v python3 >/dev/null 2>&1; then
  echo "python3 is required" >&2
  exit 1
fi

export GH_TOKEN="${token}"

compose_cla_agreement_body() {
  if [[ -n "${cla_company}" ]]; then
    printf '@microsoft-github-policy-service agree company="%s"' "${cla_company}"
    return
  fi
  printf '@microsoft-github-policy-service agree'
}

has_cla_prompt_comment() {
  local pr_number="$1"
  local cla_prompt
  cla_prompt="$(
    gh api "repos/${upstream_repo}/issues/${pr_number}/comments?per_page=100" \
      --jq '.[] | select(.user.login == "microsoft-github-policy-service[bot]") | .body' |
      grep -F "Contributor License Agreement" || true
  )"
  [[ -n "${cla_prompt}" ]]
}

maybe_post_cla_agreement() {
  local pr_ref="$1"
  local agreement_body
  agreement_body="$(compose_cla_agreement_body)"

  if [[ "${auto_agree_cla}" != "true" ]]; then
    echo "Automatic CLA agreement is disabled. If prompted, comment on ${pr_ref}: ${agreement_body}"
    return 0
  fi

  local pr_number
  pr_number="$(gh pr view "${pr_ref}" --repo "${upstream_repo}" --json number --jq '.number')"
  if ! has_cla_prompt_comment "${pr_number}"; then
    echo "Skipping CLA auto-agreement on PR #${pr_number}: no CLA prompt from microsoft-github-policy-service[bot]."
    return 0
  fi

  local current_login
  current_login="$(gh api user --jq '.login')"
  local existing_comment
  existing_comment="$(
    gh api "repos/${upstream_repo}/issues/${pr_number}/comments?per_page=100" \
      --jq ".[] | select(.user.login == \"${current_login}\") | .body" |
      grep -Fx "${agreement_body}" || true
  )"
  if [[ -n "${existing_comment}" ]]; then
    echo "CLA agreement comment already exists on PR #${pr_number}."
    return 0
  fi

  gh pr comment "${pr_ref}" --repo "${upstream_repo}" --body "${agreement_body}" >/dev/null
  echo "Posted CLA agreement comment on PR #${pr_number}."
}

if ! gh repo view "${fork_repo}" >/dev/null 2>&1; then
  echo "Fork repo not found or inaccessible: ${fork_repo}" >&2
  echo "Create a fork of ${upstream_repo} first, then set WINGET_PKGS_FORK_REPO." >&2
  exit 1
fi

version="${release_tag#v}"
tmp_root="$(mktemp -d)"
release_dir="${tmp_root}/release"
manifest_dir="${tmp_root}/manifest"
fork_dir="${tmp_root}/winget-fork"

cleanup() {
  rm -rf "${tmp_root}"
}
trap cleanup EXIT

mkdir -p "${release_dir}" "${manifest_dir}"

gh release download "${release_tag}" \
  --repo "${source_repo}" \
  --pattern "*Setup*.exe" \
  --dir "${release_dir}"

setup_exe="$(find "${release_dir}" -maxdepth 1 -type f -iname '*setup*.exe' | head -n 1)"
if [[ -z "${setup_exe}" ]]; then
  echo "No setup exe found in release assets for ${release_tag}" >&2
  exit 1
fi

python3 scripts/generate_winget_manifests.py \
  --release-tag "${release_tag}" \
  --repo "${source_repo}" \
  --installer-path "${setup_exe}" \
  --output-dir "${manifest_dir}" \
  --package-identifier "${package_id}" \
  --package-name "SecondLoop" \
  --publisher "SecondLoop"

package_path="${package_id//./\/}"
first_letter="$(tr '[:upper:]' '[:lower:]' <<<"${package_id:0:1}")"
target_rel_dir="manifests/${first_letter}/${package_path}/${version}"

git clone "https://x-access-token:${token}@github.com/${fork_repo}.git" "${fork_dir}"
pushd "${fork_dir}" >/dev/null
git remote add upstream "https://github.com/${upstream_repo}.git"
git fetch upstream master --depth=1

branch_name="secondloop-${version}"
git checkout -B "${branch_name}" upstream/master

mkdir -p "${target_rel_dir}"
cp -f "${manifest_dir}/"*.yaml "${target_rel_dir}/"

git add "${target_rel_dir}"
if git diff --cached --quiet; then
  echo "No winget manifest changes for ${release_tag}"
  popd >/dev/null
  exit 0
fi

git config user.name "${GITHUB_ACTOR:-github-actions[bot]}"
git config user.email "${GITHUB_ACTOR:-github-actions[bot]}@users.noreply.github.com"
git commit -m "Add ${package_id} version ${version}"
git push "https://x-access-token:${token}@github.com/${fork_repo}.git" "${branch_name}:${branch_name}" --force
popd >/dev/null

fork_owner="${fork_repo%%/*}"
existing_pr_url="$(
  gh pr list \
    --repo "${upstream_repo}" \
    --head "${fork_owner}:${branch_name}" \
    --base master \
    --state open \
    --json url \
    --jq '.[0].url // empty'
)"

if [[ -n "${existing_pr_url}" ]]; then
  echo "Existing PR already open: ${existing_pr_url}"
  maybe_post_cla_agreement "${existing_pr_url}"
  exit 0
fi

created_pr_url="$(
gh pr create \
  --repo "${upstream_repo}" \
  --base master \
  --head "${fork_owner}:${branch_name}" \
  --title "Add ${package_id} version ${version}" \
  --body "## Summary

- Add WinGet manifests for ${package_id} ${version}
- Source release: https://github.com/${source_repo}/releases/tag/${release_tag}

## Validation

- Installer URL and SHA256 were generated from GitHub release assets
- Manifest files were produced by scripts/generate_winget_manifests.py"
)"

echo "Opened WinGet PR for ${package_id} ${version}: ${created_pr_url}"
maybe_post_cla_agreement "${created_pr_url}"
