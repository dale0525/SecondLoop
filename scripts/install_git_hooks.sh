#!/usr/bin/env bash
set -euo pipefail

die() {
  echo "install-git-hooks: $*" >&2
  exit 1
}

require_cmd() {
  local cmd="$1"
  command -v "${cmd}" >/dev/null 2>&1 || die "Missing required command: ${cmd}"
}

require_cmd git

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${repo_root}"

if [[ ! -d ".githooks" ]]; then
  die "Missing .githooks/ directory"
fi

if [[ ! -f ".githooks/pre-commit" ]]; then
  die "Missing .githooks/pre-commit"
fi

if [[ ! -f ".githooks/pre-push" ]]; then
  die "Missing .githooks/pre-push"
fi

git config core.hooksPath .githooks
chmod +x .githooks/pre-commit
chmod +x .githooks/pre-push

echo "install-git-hooks: configured core.hooksPath=.githooks"
