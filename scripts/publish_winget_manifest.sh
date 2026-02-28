#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage: publish_winget_manifest.sh --release-tag <vX.Y.Z> --source-repo <owner/repo> --fork-repo <owner/repo> --token <github-token> [--upstream-repo <owner/repo>] [--package-id <id>]

Generate WinGet manifests for the given release and open a PR against microsoft/winget-pkgs.
USAGE
}

release_tag=''
source_repo=''
fork_repo=''
token=''
upstream_repo='microsoft/winget-pkgs'
package_id='SecondLoop.SecondLoop'

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

if git diff --quiet; then
  echo "No winget manifest changes for ${release_tag}"
  popd >/dev/null
  exit 0
fi

git config user.name "${GITHUB_ACTOR:-github-actions[bot]}"
git config user.email "${GITHUB_ACTOR:-github-actions[bot]}@users.noreply.github.com"
git add "${target_rel_dir}"
git commit -m "Add ${package_id} version ${version}"
git push "https://x-access-token:${token}@github.com/${fork_repo}.git" "${branch_name}:${branch_name}" --force
popd >/dev/null

fork_owner="${fork_repo%%/*}"
existing_pr_number="$(
  gh pr list \
    --repo "${upstream_repo}" \
    --head "${fork_owner}:${branch_name}" \
    --base master \
    --state open \
    --json number \
    --jq '.[0].number // empty'
)"

if [[ -n "${existing_pr_number}" ]]; then
  echo "Existing PR already open: #${existing_pr_number}"
  exit 0
fi

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

echo "Opened WinGet PR for ${package_id} ${version}"
