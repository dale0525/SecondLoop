#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "${script_dir}/.." && pwd)"
cd "${repo_root}"

usage() {
  cat <<'EOF'
Usage:
  bash scripts/release_preflight.sh [options]

Options:
  --remote <name>        Git remote name for repo discovery (default: origin)
  --repo <owner/repo>    Override GitHub repo slug
  --runtime-tag <tag>    Use specific runtime tag (desktop-runtime-vX.Y.Z[.W])
  --insecure-skip-verify Skip TLS cert verification for runtime payload download (local troubleshooting only)

Checks:
  1) Latest desktop runtime release payload completeness:
     linux/x64, windows/x64, macos/x64, macos/arm64
  2) Linux plugin lock pins:
     - file_selector_linux == 0.9.2+1
     - url_launcher_linux == 3.1.1
EOF
}

die() {
  echo "release-preflight: $*" >&2
  exit 1
}

require_cmd() {
  local cmd="$1"
  command -v "${cmd}" >/dev/null 2>&1 || die "Missing required command: ${cmd}"
}

require_cmd git
require_cmd python3

if ! command -v gh >/dev/null 2>&1 && ! command -v curl >/dev/null 2>&1; then
  die "Missing required command: gh or curl"
fi

fetch_releases_json() {
  local repo_slug="$1"
  local out_file="$2"
  local tmp_file="${out_file}.tmp.$$"

  local token
  token="${GH_TOKEN:-${GITHUB_TOKEN:-}}"

  if command -v gh >/dev/null 2>&1; then
    local gh_args=(
      api
      -H
      "Accept: application/vnd.github+json"
      "/repos/${repo_slug}/releases?per_page=100"
    )
    if [[ -n "${token}" ]]; then
      if GH_TOKEN="${token}" gh "${gh_args[@]}" > "${tmp_file}" 2>/dev/null; then
        if [[ -s "${tmp_file}" ]]; then
          mv "${tmp_file}" "${out_file}"
          return 0
        fi
      fi
    else
      if gh "${gh_args[@]}" > "${tmp_file}" 2>/dev/null; then
        if [[ -s "${tmp_file}" ]]; then
          mv "${tmp_file}" "${out_file}"
          return 0
        fi
      fi
    fi
    rm -f "${tmp_file}"
  fi

  if command -v curl >/dev/null 2>&1; then
    local url="https://api.github.com/repos/${repo_slug}/releases?per_page=100"
    local curl_args=(
      --fail
      --silent
      --show-error
      --location
      --retry
      3
      --connect-timeout
      15
      --max-time
      60
      -H
      "User-Agent: secondloop-release-preflight"
      -H
      "Accept: application/vnd.github+json"
    )
    if [[ -n "${token}" ]]; then
      curl_args+=( -H "Authorization: Bearer ${token}" )
    fi
    if curl "${curl_args[@]}" "${url}" > "${tmp_file}"; then
      if [[ -s "${tmp_file}" ]]; then
        mv "${tmp_file}" "${out_file}"
        return 0
      fi
    fi
    rm -f "${tmp_file}"
  fi

  rm -f "${tmp_file}"
  return 1
}

remote="origin"
repo="${SECONDLOOP_GITHUB_REPO:-}"
runtime_tag="${SECONDLOOP_DESKTOP_RUNTIME_TAG:-}"
insecure_skip_verify="${RELEASE_PREFLIGHT_INSECURE_SKIP_VERIFY:-0}"

normalize_bool() {
  local raw
  raw="$(printf '%s' "${1:-}" | tr '[:upper:]' '[:lower:]')"
  case "${raw}" in
    1|true|yes|on)
      echo "1"
      ;;
    *)
      echo "0"
      ;;
  esac
}

insecure_skip_verify="$(normalize_bool "${insecure_skip_verify}")"

args=("$@")
while [[ ${#args[@]} -gt 0 ]]; do
  case "${args[0]}" in
    -h|--help)
      usage
      exit 0
      ;;
    --remote)
      if [[ ${#args[@]} -lt 2 ]]; then
        die "--remote requires a value"
      fi
      remote="${args[1]}"
      args=("${args[@]:2}")
      ;;
    --repo)
      if [[ ${#args[@]} -lt 2 ]]; then
        die "--repo requires a value"
      fi
      repo="${args[1]}"
      args=("${args[@]:2}")
      ;;
    --runtime-tag)
      if [[ ${#args[@]} -lt 2 ]]; then
        die "--runtime-tag requires a value"
      fi
      runtime_tag="${args[1]}"
      args=("${args[@]:2}")
      ;;
    --insecure-skip-verify)
      insecure_skip_verify="1"
      args=("${args[@]:1}")
      ;;
    --*)
      die "Unknown option: ${args[0]}"
      ;;
    *)
      die "Unexpected argument: ${args[0]}"
      ;;
  esac
done

if [[ -z "${repo}" ]]; then
  repo="${GITHUB_REPOSITORY:-}"
fi

if [[ -z "${repo}" ]]; then
  remote_url="$(git config --get "remote.${remote}.url" || true)"
  if [[ -z "${remote_url}" ]]; then
    die "Cannot resolve repository slug from remote '${remote}'."
  fi
  repo="$(python3 - "${remote_url}" <<'PY'
import re
import sys

url = sys.argv[1].strip()
match = re.search(r'github\.com[:/](.+?)(?:\.git)?$', url)
if not match:
    raise SystemExit('')
print(match.group(1))
PY
)"
fi

if [[ -z "${repo}" ]]; then
  die "Cannot resolve repository slug. Pass --repo owner/repo."
fi

release_api_payload="$(mktemp)"
trap 'rm -f "${release_api_payload}"' EXIT

if ! fetch_releases_json "${repo}" "${release_api_payload}"; then
  die "cannot fetch releases for ${repo} (try setting GH_TOKEN/GITHUB_TOKEN or running gh auth login)"
fi

if [[ ! -s "${release_api_payload}" ]]; then
  die "cannot fetch releases for ${repo}: empty API response"
fi

if [[ "${insecure_skip_verify}" == "1" ]]; then
  echo "release-preflight: WARNING insecure TLS mode enabled for runtime payload checks"
fi

python3 - "${repo}" "${runtime_tag}" "${release_api_payload}" "${insecure_skip_verify}" <<'PY'
import hashlib
import json
import os
import pathlib
import re
import ssl
import sys
import tarfile
import tempfile
import urllib.error
import urllib.request


def fail(message: str) -> None:
    print(f"release-preflight: {message}", file=sys.stderr)
    raise SystemExit(1)


def runtime_headers() -> dict[str, str]:
    headers = {
        "User-Agent": "secondloop-release-preflight",
        "Accept": "application/octet-stream",
    }
    token = os.environ.get("GH_TOKEN") or os.environ.get("GITHUB_TOKEN")
    if token and token.strip():
        headers["Authorization"] = f"Bearer {token.strip()}"
    return headers


def download_asset_text(asset: dict, *, runtime_ssl_context: ssl.SSLContext | None, timeout: int = 120) -> str:
    url = str(asset.get("browser_download_url", "")).strip()
    if not url:
        raise RuntimeError(f"asset missing browser_download_url: {asset.get('name')}")

    request = urllib.request.Request(url, headers=runtime_headers())
    try:
        with urllib.request.urlopen(request, timeout=timeout, context=runtime_ssl_context) as response:
            return response.read().decode("utf-8")
    except urllib.error.HTTPError as exc:
        raise RuntimeError(
            f"HTTP {exc.code} when downloading asset {asset.get('name')}"
        ) from exc
    except Exception as exc:
        raise RuntimeError(f"cannot download asset {asset.get('name')}: {exc}") from exc


def stream_asset(asset: dict, sink, digest, *, runtime_ssl_context: ssl.SSLContext | None) -> None:
    url = str(asset.get("browser_download_url", "")).strip()
    if not url:
        raise RuntimeError(f"asset missing browser_download_url: {asset.get('name')}")

    request = urllib.request.Request(url, headers=runtime_headers())
    try:
        with urllib.request.urlopen(request, timeout=300, context=runtime_ssl_context) as response:
            while True:
                chunk = response.read(1024 * 1024)
                if not chunk:
                    break
                digest.update(chunk)
                sink.write(chunk)
    except urllib.error.HTTPError as exc:
        raise RuntimeError(
            f"HTTP {exc.code} when downloading asset {asset.get('name')}"
        ) from exc
    except Exception as exc:
        raise RuntimeError(f"cannot download asset {asset.get('name')}: {exc}") from exc


def first_sha_token(raw: str) -> str:
    token = raw.strip().split()[0] if raw.strip() else ""
    if not token:
        raise RuntimeError("empty sha256 content")
    return token


def has_platform_runtime_lib(file_names: set[str], platform: str) -> bool:
    lowered = {name.lower() for name in file_names}
    if platform == "windows":
        return any(name.startswith("onnxruntime") and name.endswith(".dll") for name in lowered)
    if platform == "macos":
        return any(
            name.startswith("libonnxruntime")
            and ".dylib" in name
            and "providers_shared" not in name
            for name in lowered
        )
    if platform == "linux":
        return any(
            name.startswith("libonnxruntime")
            and ".so" in name
            and "providers_shared" not in name
            for name in lowered
        )
    raise RuntimeError(f"unsupported platform: {platform}")


def inspect_archive_payload(archive_path: pathlib.Path) -> set[str]:
    basenames = set()
    try:
        with tarfile.open(archive_path, "r:gz") as handle:
            for member in handle.getmembers():
                if member.isfile():
                    basenames.add(pathlib.PurePosixPath(member.name).name)
    except Exception as exc:
        raise RuntimeError(f"cannot inspect runtime archive {archive_path.name}: {exc}") from exc
    return basenames


def validate_target_payload(
    *,
    platform: str,
    arch: str,
    runtime_version: str,
    assets_by_name: dict[str, dict],
    det_aliases: set[str],
    cls_aliases: set[str],
    rec_aliases: set[str],
    runtime_ssl_context: ssl.SSLContext | None,
) -> None:
    archive_base = f"desktop-runtime-{platform}-{arch}-{runtime_version}.tar.gz"
    parts_list_name = archive_base + ".parts.txt"
    sha_name = archive_base + ".sha256"

    parts_list_asset = assets_by_name.get(parts_list_name)
    sha_asset = assets_by_name.get(sha_name)
    if parts_list_asset is None:
        raise RuntimeError(f"missing {parts_list_name}")
    if sha_asset is None:
        raise RuntimeError(f"missing {sha_name}")

    parts_raw = download_asset_text(parts_list_asset, runtime_ssl_context=runtime_ssl_context)
    part_names = [line.strip() for line in parts_raw.splitlines() if line.strip()]
    if not part_names:
        raise RuntimeError(f"part list is empty: {parts_list_name}")

    missing_parts = [name for name in part_names if name not in assets_by_name]
    if missing_parts:
        raise RuntimeError(
            f"part list references missing assets: {', '.join(missing_parts)}"
        )

    expected_sha = first_sha_token(download_asset_text(sha_asset, runtime_ssl_context=runtime_ssl_context))

    with tempfile.TemporaryDirectory(prefix=f"runtime-{platform}-{arch}-") as temp_dir:
        archive_path = pathlib.Path(temp_dir) / archive_base
        digest = hashlib.sha256()
        with archive_path.open("wb") as sink:
            for part_name in part_names:
                stream_asset(assets_by_name[part_name], sink, digest, runtime_ssl_context=runtime_ssl_context)
        actual_sha = digest.hexdigest()
        if actual_sha.lower() != expected_sha.lower():
            raise RuntimeError(
                "sha256 mismatch for assembled archive "
                f"(expected={expected_sha} actual={actual_sha})"
            )

        basenames = inspect_archive_payload(archive_path)

    missing_sections = []
    if not (basenames & det_aliases):
        missing_sections.append("DET model")
    if not (basenames & cls_aliases):
        missing_sections.append("CLS model")
    if not (basenames & rec_aliases):
        missing_sections.append("REC model")
    if not has_platform_runtime_lib(basenames, platform):
        missing_sections.append("ONNX Runtime dynamic library")

    if missing_sections:
        raise RuntimeError(
            "runtime payload missing required files: " + ", ".join(missing_sections)
        )


repo = sys.argv[1].strip()
configured_runtime_tag = sys.argv[2].strip()
payload_path = sys.argv[3].strip()
configured_insecure_skip_verify = sys.argv[4].strip().lower() in {"1", "true", "yes", "on"}
runtime_ssl_context = ssl._create_unverified_context() if configured_insecure_skip_verify else None

try:
    with open(payload_path, "r", encoding="utf-8") as handle:
        releases = json.load(handle)
except Exception as exc:
    fail(f"cannot parse GitHub releases payload for {repo}: {exc}")

if not isinstance(releases, list):
    if isinstance(releases, dict) and "message" in releases:
        fail(f"GitHub API error for {repo}: {releases.get('message')}")
    fail(f"unexpected GitHub releases response type: {type(releases).__name__}")

runtime_release = None

if configured_runtime_tag:
    if not re.match(r"^desktop-runtime-v[0-9]+\.[0-9]+\.[0-9]+(\.[0-9]+)?$", configured_runtime_tag):
        fail(
            "invalid runtime tag "
            f"'{configured_runtime_tag}'. Expected desktop-runtime-vX.Y.Z(.W)"
        )
    for item in releases:
        if not isinstance(item, dict):
            continue
        if str(item.get("tag_name", "")) == configured_runtime_tag:
            runtime_release = item
            break
    if runtime_release is None:
        fail(
            f"runtime tag '{configured_runtime_tag}' was not found in {repo} releases"
        )
else:
    for item in releases:
        if not isinstance(item, dict):
            continue
        if item.get("draft") is True or item.get("prerelease") is True:
            continue
        tag_name = str(item.get("tag_name", ""))
        if tag_name.startswith("desktop-runtime-v"):
            runtime_release = item
            break

if runtime_release is None:
    fail(
        "cannot find any stable desktop runtime release tag "
        "(desktop-runtime-vX.Y.Z)"
    )

runtime_tag = str(runtime_release.get("tag_name", "")).strip()
runtime_version = runtime_tag.replace("desktop-runtime-", "", 1)
assets = runtime_release.get("assets", [])
if not isinstance(assets, list):
    assets = []

assets_by_name = {}
for asset in assets:
    if not isinstance(asset, dict):
        continue
    name = str(asset.get("name", "")).strip()
    if name:
        assets_by_name[name] = asset

asset_names = set(assets_by_name.keys())

required_targets = [
    ("linux", "x64"),
    ("windows", "x64"),
    ("macos", "x64"),
    ("macos", "arm64"),
]

missing = []
for platform, arch in required_targets:
    base = f"desktop-runtime-{platform}-{arch}-{runtime_version}.tar.gz"
    required = [
        base + ".parts.txt",
        base + ".sha256",
    ]

    missing_for_target = [name for name in required if name not in asset_names]

    has_any_part = any(
        name.startswith(base + ".part") and re.match(rf"^{re.escape(base)}\.part[0-9]+$", name)
        for name in asset_names
    )
    if not has_any_part:
        missing_for_target.append(base + ".partXX")

    if missing_for_target:
        missing.append((platform, arch, missing_for_target))

if missing:
    lines = [
        f"runtime release '{runtime_tag}' is incomplete for app release:",
    ]
    for platform, arch, names in missing:
        lines.append(f"  - {platform}/{arch}: missing {', '.join(names)}")
    fail("\n".join(lines))

det_aliases = {
    "ch_PP-OCRv5_mobile_det.onnx",
    "ch_PP-OCRv4_det_infer.onnx",
    "ch_PP-OCRv3_det_infer.onnx",
}
cls_aliases = {
    "ch_ppocr_mobile_v2.0_cls_infer.onnx",
}
rec_aliases = {
    "ch_PP-OCRv5_rec_mobile_infer.onnx",
    "ch_PP-OCRv5_mobile_rec.onnx",
    "ch_PP-OCRv4_rec_infer.onnx",
    "ch_PP-OCRv3_rec_infer.onnx",
    "latin_PP-OCRv3_rec_infer.onnx",
    "arabic_PP-OCRv3_rec_infer.onnx",
    "cyrillic_PP-OCRv3_rec_infer.onnx",
    "devanagari_PP-OCRv3_rec_infer.onnx",
    "japan_PP-OCRv3_rec_infer.onnx",
    "korean_PP-OCRv3_rec_infer.onnx",
    "chinese_cht_PP-OCRv3_rec_infer.onnx",
}

payload_errors = []
for platform, arch in required_targets:
    try:
        validate_target_payload(
            platform=platform,
            arch=arch,
            runtime_version=runtime_version,
            assets_by_name=assets_by_name,
            det_aliases=det_aliases,
            cls_aliases=cls_aliases,
            rec_aliases=rec_aliases,
            runtime_ssl_context=runtime_ssl_context,
        )
    except RuntimeError as exc:
        payload_errors.append(f"  - {platform}/{arch}: {exc}")

if payload_errors:
    lines = [
        f"runtime release '{runtime_tag}' payload validation failed:",
        *payload_errors,
    ]
    fail("\n".join(lines))

print(f"release-preflight: runtime assets ready -> {runtime_tag}")
print(f"release-preflight: resolved_runtime_tag={runtime_tag}")
PY

read_locked_pubspec_version() {
  local package_name="$1"
  python3 - "${package_name}" <<'PY'
import re
import sys
from pathlib import Path

package_name = sys.argv[1]
pattern = re.compile(
    rf"\n  {re.escape(package_name)}:\n(?:    .*\n)*?    version: \"([^\"]+)\"",
    re.MULTILINE,
)
content = Path('pubspec.lock').read_text(encoding='utf-8')
match = pattern.search(content)
if not match:
    print("")
    raise SystemExit(0)
print(match.group(1))
PY
}

locked_file_selector_linux_version="$(read_locked_pubspec_version file_selector_linux)"
if [[ -z "${locked_file_selector_linux_version}" ]]; then
  die "cannot find file_selector_linux version in pubspec.lock"
fi
if [[ "${locked_file_selector_linux_version}" != "0.9.2+1" ]]; then
  die "file_selector_linux must stay pinned to 0.9.2+1 (current lock: ${locked_file_selector_linux_version})"
fi
echo "release-preflight: file_selector_linux lock pin OK (${locked_file_selector_linux_version})"

locked_url_launcher_linux_version="$(read_locked_pubspec_version url_launcher_linux)"
if [[ -z "${locked_url_launcher_linux_version}" ]]; then
  die "cannot find url_launcher_linux version in pubspec.lock"
fi
if [[ "${locked_url_launcher_linux_version}" != "3.1.1" ]]; then
  die "url_launcher_linux must stay pinned to 3.1.1 for current Linux compatibility baseline (current lock: ${locked_url_launcher_linux_version})"
fi
echo "release-preflight: url_launcher_linux lock pin OK (${locked_url_launcher_linux_version})"
echo "release-preflight: all checks passed"
