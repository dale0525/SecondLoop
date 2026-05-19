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
  --remote <name>        Git remote name for compatibility (default: origin)
  --repo <owner/repo>    Accepted for compatibility; no runtime lookup is done

Checks:
  1) Linux plugin lock pins:
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

require_cmd python3

args=("$@")
while [[ ${#args[@]} -gt 0 ]]; do
  case "${args[0]}" in
    -h|--help)
      usage
      exit 0
      ;;
    --remote|--repo)
      if [[ ${#args[@]} -lt 2 ]]; then
        die "${args[0]} requires a value"
      fi
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
content = Path("pubspec.lock").read_text(encoding="utf-8")
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
echo "release-preflight: app-only checks passed"
