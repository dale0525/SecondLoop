#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage: publish_homebrew_cask.sh --tap-repo <owner/repo> --source-repo <owner/repo> --release-tag <vX.Y.Z> --token <github-token>

Downloads the macOS checksum asset from a release, updates Casks/secondloop.rb in the tap
repository, then commits and pushes the update when content changes.
USAGE
}

tap_repo=''
source_repo=''
release_tag=''
tap_token=''

while [[ $# -gt 0 ]]; do
  case "$1" in
    --tap-repo)
      tap_repo="${2:-}"
      shift 2
      ;;
    --source-repo)
      source_repo="${2:-}"
      shift 2
      ;;
    --release-tag)
      release_tag="${2:-}"
      shift 2
      ;;
    --token)
      tap_token="${2:-}"
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

if [[ -z "${tap_repo}" || -z "${source_repo}" || -z "${release_tag}" || -z "${tap_token}" ]]; then
  usage >&2
  exit 2
fi

if ! command -v gh >/dev/null 2>&1; then
  echo "gh CLI is required" >&2
  exit 1
fi

if ! command -v git >/dev/null 2>&1; then
  echo "git is required" >&2
  exit 1
fi

if [[ ! "${release_tag}" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "Invalid release tag: ${release_tag}. Expected vX.Y.Z" >&2
  exit 1
fi

version="${release_tag#v}"
tmp_root="$(mktemp -d)"
checksum_dir="${tmp_root}/release"
tap_dir="${tmp_root}/tap"

cleanup() {
  rm -rf "${tmp_root}"
}
trap cleanup EXIT

mkdir -p "${checksum_dir}"

gh release download "${release_tag}" \
  --repo "${source_repo}" \
  --pattern "SecondLoop-macos-*.dmg.sha256" \
  --dir "${checksum_dir}"

checksum_file="$(find "${checksum_dir}" -maxdepth 1 -type f -name '*.dmg.sha256' | head -n 1)"
if [[ -z "${checksum_file}" ]]; then
  echo "No macOS checksum asset found for tag ${release_tag}" >&2
  exit 1
fi

checksum_line="$(head -n 1 "${checksum_file}")"
dmg_sha="$(awk '{print $1}' <<<"${checksum_line}")"
dmg_name="$(awk '{print $2}' <<<"${checksum_line}")"
dmg_name="${dmg_name#\*}"
if [[ -z "${dmg_name}" ]]; then
  dmg_name="$(basename "${checksum_file}" .sha256)"
fi

if [[ -z "${dmg_sha}" ]]; then
  echo "Failed to parse sha256 from ${checksum_file}" >&2
  exit 1
fi

git clone "https://x-access-token:${tap_token}@github.com/${tap_repo}.git" "${tap_dir}"
mkdir -p "${tap_dir}/Casks"

cask_file="${tap_dir}/Casks/secondloop.rb"
cat >"${cask_file}" <<CASK
cask "secondloop" do
  version "${version}"
  sha256 "${dmg_sha}"

  url "https://github.com/${source_repo}/releases/download/${release_tag}/${dmg_name}",
      verified: "github.com/${source_repo}/"
  name "SecondLoop"
  desc "Local-first personal AI assistant with long-term memory"
  homepage "https://secondloop.app"

  auto_updates true
  app "SecondLoop.app"

  uninstall quit: "com.secondloop.secondloop"

  zap trash: [
    "~/Library/Application Support/secondloop",
    "~/Library/Preferences/com.secondloop.secondloop.plist",
    "~/Library/Saved Application State/com.secondloop.secondloop.savedState",
  ]
end
CASK

pushd "${tap_dir}" >/dev/null
git add Casks/secondloop.rb
if git diff --cached --quiet -- Casks/secondloop.rb; then
  echo "No Homebrew cask change for ${release_tag}"
  popd >/dev/null
  exit 0
fi

git config user.name "${GITHUB_ACTOR:-github-actions[bot]}"
git config user.email "${GITHUB_ACTOR:-github-actions[bot]}@users.noreply.github.com"
git commit -m "chore(cask): update secondloop ${release_tag}"
git push origin HEAD
popd >/dev/null

echo "Published Homebrew cask to ${tap_repo} for ${release_tag}"
