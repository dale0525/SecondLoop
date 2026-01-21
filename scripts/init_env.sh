#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
src="${repo_root}/.env.example"
dst="${repo_root}/.env.local"

if [[ -f "${dst}" ]]; then
  echo "SecondLoop: ${dst} already exists."
  exit 0
fi

if [[ ! -f "${src}" ]]; then
  echo "SecondLoop: missing ${src}" >&2
  exit 1
fi

cp "${src}" "${dst}"
echo "SecondLoop: created ${dst}. Edit it to configure Cloud keys."
