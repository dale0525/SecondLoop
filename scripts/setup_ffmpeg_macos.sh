#!/usr/bin/env bash
set -euo pipefail

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "setup-ffmpeg-macos: skipped (host is not macOS)"
  exit 0
fi

repo_root="${PWD}"
target_dir="${repo_root}/.tool/ffmpeg/macos"
target_bin="${target_dir}/ffmpeg"
download_url="${SECONDLOOP_FFMPEG_MACOS_URL:-https://evermeet.cx/ffmpeg/getrelease/ffmpeg/zip}"

if [[ -x "${target_bin}" ]] && "${target_bin}" -version >/dev/null 2>&1; then
  echo "setup-ffmpeg-macos: using existing ${target_bin}"
  exit 0
fi

if ! command -v curl >/dev/null 2>&1; then
  echo "setup-ffmpeg-macos: curl is required" >&2
  exit 1
fi

if ! command -v unzip >/dev/null 2>&1; then
  echo "setup-ffmpeg-macos: unzip is required" >&2
  exit 1
fi

tmp_dir="$(mktemp -d "${TMPDIR:-/tmp}/secondloop-ffmpeg-XXXXXX")"
cleanup() {
  rm -rf "${tmp_dir}"
}
trap cleanup EXIT

archive_path="${tmp_dir}/ffmpeg.zip"
echo "setup-ffmpeg-macos: downloading static ffmpeg"
curl \
  --fail \
  --location \
  --silent \
  --show-error \
  --retry 3 \
  --output "${archive_path}" \
  "${download_url}"

unzip -q "${archive_path}" -d "${tmp_dir}"

if [[ ! -f "${tmp_dir}/ffmpeg" ]]; then
  echo "setup-ffmpeg-macos: ffmpeg binary not found in downloaded archive" >&2
  exit 1
fi

mkdir -p "${target_dir}"
install -m 0755 "${tmp_dir}/ffmpeg" "${target_bin}"

if ! "${target_bin}" -version >/dev/null 2>&1; then
  echo "setup-ffmpeg-macos: downloaded ffmpeg failed verification" >&2
  exit 1
fi

echo "setup-ffmpeg-macos: ready at ${target_bin}"
