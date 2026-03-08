#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${repo_root}"

resolve_flutter_bin() {
  if [[ -x "${repo_root}/.fvm/flutter_sdk/bin/flutter" ]]; then
    printf '%s\n' "${repo_root}/.fvm/flutter_sdk/bin/flutter"
    return 0
  fi

  if command -v flutter >/dev/null 2>&1; then
    command -v flutter
    return 0
  fi

  echo "run_i18n_analyze: Missing 'flutter'. Install Flutter (recommended: pixi run setup-flutter) or add Flutter to PATH." >&2
  exit 1
}

mkdir -p .dart_tool/slang
flutter_bin="$(resolve_flutter_bin)"
env -u GIT_DIR -u GIT_WORK_TREE -u GIT_INDEX_FILE "${flutter_bin}" pub run slang analyze --full --exit-if-changed --outdir=.dart_tool/slang
