#!/usr/bin/env bash
set -euo pipefail

repo_root="$(git rev-parse --show-toplevel 2>/dev/null || true)"
if [[ -z "${repo_root}" ]]; then
  exit 0
fi

cd "${repo_root}"
source "${repo_root}/scripts/pre_commit_common.sh"

python_bin="$(resolve_python_bin)" || die "Missing project-managed Python at .pixi/envs/default. Run \`pixi install\`."

run_with_periodic_status \
  "python tooling tests" \
  env \
  -u GIT_DIR \
  -u GIT_WORK_TREE \
  -u GIT_INDEX_FILE \
  -u GIT_COMMON_DIR \
  -u GIT_PREFIX \
  "${python_bin}" -m unittest discover -s scripts/tests -p 'test_*.py'
