#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${repo_root}"

is_windows_env() {
  local uname_value
  uname_value="$(uname -s 2>/dev/null || true)"
  case "${uname_value}" in
    MINGW* | MSYS* | CYGWIN*) return 0 ;;
  esac

  [[ "${OS:-}" == "Windows_NT" ]]
}

resolve_powershell_bin() {
  local candidate
  for candidate in powershell.exe pwsh.exe powershell pwsh; do
    if command -v "${candidate}" >/dev/null 2>&1; then
      command -v "${candidate}"
      return 0
    fi
  done

  return 1
}

to_native_windows_path() {
  local path="$1"
  if command -v cygpath >/dev/null 2>&1; then
    cygpath -aw "${path}" 2>/dev/null && return 0
  fi

  printf '%s\n' "${path}"
}

resolve_flutter_bin() {
  if [[ -x "${repo_root}/.fvm/flutter_sdk/bin/flutter" ]]; then
    printf '%s\n' "${repo_root}/.fvm/flutter_sdk/bin/flutter"
    return 0
  fi

  if is_windows_env && [[ -f "${repo_root}/.fvm/flutter_sdk/bin/flutter.bat" ]]; then
    printf '%s\n' "${repo_root}/.fvm/flutter_sdk/bin/flutter.bat"
    return 0
  fi

  if command -v flutter >/dev/null 2>&1; then
    command -v flutter
    return 0
  fi

  if is_windows_env && command -v flutter.bat >/dev/null 2>&1; then
    command -v flutter.bat
    return 0
  fi

  echo "run_i18n_analyze: Missing 'flutter'. Install Flutter (recommended: pixi run setup-flutter) or add Flutter to PATH." >&2
  exit 1
}

run_windows_batch_tool() {
  local tool_name="$1"
  local tool_bin="$2"
  shift 2

  local powershell_bin
  powershell_bin="$(resolve_powershell_bin)" || {
    echo "run_i18n_analyze: Missing PowerShell. Install PowerShell or add Flutter shell shims to PATH." >&2
    exit 1
  }

  local script_path
  script_path="$(to_native_windows_path "${repo_root}/scripts/run_fvm_tool.ps1")"
  local native_tool_path
  native_tool_path="$(to_native_windows_path "${tool_bin}")"

  env -u GIT_DIR -u GIT_WORK_TREE -u GIT_INDEX_FILE \
    "${powershell_bin}" \
    -NoProfile \
    -ExecutionPolicy Bypass \
    -File "${script_path}" \
    -Tool "${tool_name}" \
    -ToolPath "${native_tool_path}" \
    -Command "$@"
}

run_flutter() {
  local flutter_bin
  flutter_bin="$(resolve_flutter_bin)"

  if [[ "${flutter_bin}" == *.bat || "${flutter_bin}" == *.cmd ]]; then
    run_windows_batch_tool flutter "${flutter_bin}" "$@"
    return $?
  fi

  env -u GIT_DIR -u GIT_WORK_TREE -u GIT_INDEX_FILE "${flutter_bin}" "$@"
}

mkdir -p .dart_tool/slang
run_flutter pub run slang analyze --full --outdir=.dart_tool/slang
