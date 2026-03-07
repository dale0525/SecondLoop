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
cla_wait_attempts="${WINGET_CLA_WAIT_ATTEMPTS:-6}"
cla_wait_seconds="${WINGET_CLA_WAIT_SECONDS:-10}"

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

normalize_positive_int() {
  local raw="${1:-}"
  if [[ ! "${raw}" =~ ^[0-9]+$ ]]; then
    echo "Invalid integer value: ${raw}" >&2
    exit 1
  fi
  printf '%s' "${raw}"
}

append_step_summary() {
  if [[ -z "${GITHUB_STEP_SUMMARY:-}" ]]; then
    return 0
  fi

  printf '%s\n' "$1" >> "${GITHUB_STEP_SUMMARY}"
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
cla_wait_attempts="$(normalize_positive_int "${cla_wait_attempts}")"
cla_wait_seconds="$(normalize_positive_int "${cla_wait_seconds}")"

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

resolve_upstream_default_branch() {
  local resolved_branch
  resolved_branch="$(
    gh repo view "${upstream_repo}" --json defaultBranchRef --jq '.defaultBranchRef.name // empty' 2>/dev/null || true
  )"
  if [[ -z "${resolved_branch}" ]]; then
    resolved_branch="$(gh api "repos/${upstream_repo}" --jq '.default_branch // empty' 2>/dev/null || true)"
  fi
  if [[ -z "${resolved_branch}" ]]; then
    resolved_branch='master'
    echo "Falling back to upstream default branch master for ${upstream_repo}." >&2
  fi

  printf '%s' "${resolved_branch}"
}

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

wait_for_cla_prompt_comment() {
  local pr_number="$1"
  local attempt

  for (( attempt = 1; attempt <= cla_wait_attempts; attempt++ )); do
    if has_cla_prompt_comment "${pr_number}"; then
      echo "Detected CLA prompt on PR #${pr_number}."
      return 0
    fi

    if (( attempt < cla_wait_attempts )); then
      echo "CLA prompt not found on PR #${pr_number} yet (attempt ${attempt}/${cla_wait_attempts}); sleeping ${cla_wait_seconds}s before retry."
      sleep "${cla_wait_seconds}"
    fi
  done

  echo "Timed out waiting for CLA prompt on PR #${pr_number} after ${cla_wait_attempts} attempts."
  return 1
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
  if ! wait_for_cla_prompt_comment "${pr_number}"; then
    echo "Skipping CLA auto-agreement on PR #${pr_number}: no CLA prompt from microsoft-github-policy-service[bot]."
    append_step_summary "- CLA auto-agreement: skipped (no prompt detected for PR #${pr_number})"
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
    append_step_summary "- CLA auto-agreement: already present on PR #${pr_number}"
    return 0
  fi

  gh pr comment "${pr_ref}" --repo "${upstream_repo}" --body "${agreement_body}" >/dev/null
  echo "Posted CLA agreement comment on PR #${pr_number}."
  append_step_summary "- CLA auto-agreement: posted on PR #${pr_number}"
}

if ! gh repo view "${fork_repo}" >/dev/null 2>&1; then
  echo "Fork repo not found or inaccessible: ${fork_repo}" >&2
  echo "Create a fork of ${upstream_repo} first, then set WINGET_PKGS_FORK_REPO." >&2
  exit 1
fi

upstream_default_branch="$(resolve_upstream_default_branch)"
echo "Using upstream default branch: ${upstream_default_branch}"

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
  --pattern "SecondLoop-win.msi" \
  --pattern "SecondLoop-win.metadata.json" \
  --dir "${release_dir}"

installer_path="${release_dir}/SecondLoop-win.msi"
if [[ ! -f "${installer_path}" ]]; then
  echo "No MSI installer asset found in release assets for ${release_tag}: ${installer_path}" >&2
  exit 1
fi
metadata_path="${release_dir}/SecondLoop-win.metadata.json"
if [[ ! -f "${metadata_path}" ]]; then
  echo "No installer metadata asset found in release assets for ${release_tag}: ${metadata_path}" >&2
  exit 1
fi
echo "Selected WinGet installer asset: ${installer_path}"
echo "Selected WinGet installer metadata asset: ${metadata_path}"

python3 scripts/generate_winget_manifests.py \
  --release-tag "${release_tag}" \
  --repo "${source_repo}" \
  --installer-path "${installer_path}" \
  --installer-metadata-path "${metadata_path}" \
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
git fetch upstream "${upstream_default_branch}" --depth=1

branch_name="secondloop-${version}"
git checkout -B "${branch_name}" "upstream/${upstream_default_branch}"

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
    --base "${upstream_default_branch}" \
    --state open \
    --json url \
    --jq '.[0].url // empty'
)"

if [[ -n "${existing_pr_url}" ]]; then
  echo "Existing PR already open: ${existing_pr_url}"
  append_step_summary "### WinGet publication details"
  append_step_summary "- Upstream default branch: ${upstream_default_branch}"
  append_step_summary "- WinGet upstream PR publication: already open (${existing_pr_url})"
  maybe_post_cla_agreement "${existing_pr_url}"
  exit 0
fi

created_pr_url="$(
gh pr create \
  --repo "${upstream_repo}" \
  --base "${upstream_default_branch}" \
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
append_step_summary "### WinGet publication details"
append_step_summary "- Upstream default branch: ${upstream_default_branch}"
append_step_summary "- WinGet upstream PR publication: created (${created_pr_url})"
maybe_post_cla_agreement "${created_pr_url}"
