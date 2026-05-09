#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
scenario_dir="${repo_root}/integration_test/scenarios"

if (( $# > 0 )); then
  scenario_files=()
  for arg in "$@"; do
    if [[ "${arg}" = /* ]]; then
      scenario_files+=("${arg}")
    else
      scenario_files+=("${repo_root}/${arg}")
    fi
  done
else
  shopt -s nullglob
  scenario_files=("${scenario_dir}"/*_test.dart)
  shopt -u nullglob

  if (( ${#scenario_files[@]} == 0 )); then
    echo "SecondLoop: no integration scenario files found under ${scenario_dir}" >&2
    exit 1
  fi

  IFS=$'\n' scenario_files=($(printf '%s\n' "${scenario_files[@]}" | sort))
  unset IFS
fi

for scenario_file in "${scenario_files[@]}"; do
  relative_path="${scenario_file#"${repo_root}/"}"
  echo "SecondLoop: running ${relative_path}" >&2
  bash "${repo_root}/scripts/flutter_with_defines.sh" test -d macos "${relative_path}"
done
