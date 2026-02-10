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

Checks:
  1) Latest desktop runtime release payload completeness:
     linux/x64, windows/x64, macos/x64, macos/arm64
  2) Linux plugin lock pin: file_selector_linux == 0.9.2+1
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

remote="origin"
repo="${SECONDLOOP_GITHUB_REPO:-}"
runtime_tag="${SECONDLOOP_DESKTOP_RUNTIME_TAG:-}"

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

python3 - "${repo}" "${runtime_tag}" <<'PY'
import json
import os
import re
import sys
import urllib.request


def fail(message: str) -> None:
    print(f"release-preflight: {message}", file=sys.stderr)
    raise SystemExit(1)


repo = sys.argv[1].strip()
configured_runtime_tag = sys.argv[2].strip()

request = urllib.request.Request(
    f"https://api.github.com/repos/{repo}/releases?per_page=100",
    headers={"User-Agent": "secondloop-release-preflight"},
)
token = (os.getenv("GH_TOKEN") or os.getenv("GITHUB_TOKEN") or "").strip()
if token:
    request.add_header("Authorization", f"Bearer {token}")

try:
    with urllib.request.urlopen(request, timeout=30) as response:
        releases = json.loads(response.read().decode("utf-8"))
except Exception as exc:
    fail(f"cannot fetch releases for {repo}: {exc}")

if not isinstance(releases, list):
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
asset_names = {
    str(asset.get("name", "")).strip()
    for asset in assets
    if isinstance(asset, dict)
}

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

print(f"release-preflight: runtime assets ready -> {runtime_tag}")
PY

locked_file_selector_linux_version="$(python3 - <<'PY'
import re
import sys
from pathlib import Path

content = Path('pubspec.lock').read_text(encoding='utf-8')
match = re.search(
    r"\n  file_selector_linux:\n(?:    .*\n)*?    version: \"([^\"]+)\"",
    content,
)
if not match:
    print("")
    raise SystemExit(0)
print(match.group(1))
PY
)"

if [[ -z "${locked_file_selector_linux_version}" ]]; then
  die "cannot find file_selector_linux version in pubspec.lock"
fi

if [[ "${locked_file_selector_linux_version}" != "0.9.2+1" ]]; then
  die "file_selector_linux must stay pinned to 0.9.2+1 (current lock: ${locked_file_selector_linux_version})"
fi

echo "release-preflight: file_selector_linux lock pin OK (${locked_file_selector_linux_version})"
echo "release-preflight: all checks passed"
