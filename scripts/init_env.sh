#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
src_example="${repo_root}/.env.example"
dst="${repo_root}/.env.local"

if [[ -f "${dst}" ]]; then
  echo "SecondLoop: ${dst} already exists."
  exit 0
fi

resolve_primary_worktree_root() {
  if ! command -v git >/dev/null 2>&1; then
    return 1
  fi

  local common_dir_raw
  common_dir_raw="$(git -C "${repo_root}" rev-parse --git-common-dir 2>/dev/null || true)"
  if [[ -z "${common_dir_raw}" ]]; then
    return 1
  fi

  local common_dir
  if [[ "${common_dir_raw}" == /* ]]; then
    common_dir="${common_dir_raw}"
  else
    common_dir="${repo_root}/${common_dir_raw}"
  fi
  common_dir="$(cd "${common_dir}" 2>/dev/null && pwd)" || return 1

  local primary_root
  primary_root="$(cd "${common_dir}/.." 2>/dev/null && pwd)" || return 1
  if [[ "${primary_root}" == "${repo_root}" ]]; then
    return 1
  fi

  printf '%s\n' "${primary_root}"
}

primary_root="$(resolve_primary_worktree_root || true)"
if [[ -n "${primary_root}" ]]; then
  primary_env="${primary_root}/.env.local"
  if [[ -f "${primary_env}" ]]; then
    cp "${primary_env}" "${dst}"
    echo "SecondLoop: copied ${dst} from ${primary_env}."
    exit 0
  fi
fi

if [[ ! -f "${src_example}" ]]; then
  echo "SecondLoop: missing ${src_example}" >&2
  exit 1
fi

cp "${src_example}" "${dst}"
echo "SecondLoop: created ${dst}. Edit it to configure Cloud keys."
