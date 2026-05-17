die() {
  echo "pre-commit: $*" >&2
  exit 1
}

run_with_periodic_status() {
  local label="$1"
  shift

  local interval="${SECONDLOOP_PRECOMMIT_PROGRESS_INTERVAL:-60}"
  local command_pid watcher_pid status

  echo "pre-commit: starting ${label}..." >&2

  "$@" &
  command_pid=$!
  watcher_pid=""

  (
    local sleep_pid=""

    cleanup_watcher() {
      if [[ -n "${sleep_pid}" ]] && kill -0 "${sleep_pid}" 2>/dev/null; then
        kill "${sleep_pid}" 2>/dev/null || true
        wait "${sleep_pid}" 2>/dev/null || true
      fi
      exit 0
    }

    trap cleanup_watcher TERM INT

    while kill -0 "${command_pid}" 2>/dev/null; do
      sleep "${interval}" &
      sleep_pid=$!
      wait "${sleep_pid}" 2>/dev/null || exit 0
      sleep_pid=""
      if ! kill -0 "${command_pid}" 2>/dev/null; then
        exit 0
      fi
      echo "pre-commit: still running ${label}..." >&2
    done
  ) &
  watcher_pid=$!

  wait "${command_pid}"
  status=$?

  if [[ -n "${watcher_pid}" ]]; then
    kill "${watcher_pid}" 2>/dev/null || true
    wait "${watcher_pid}" 2>/dev/null || true
  fi

  return "${status}"
}

precommit_allow_worktree_writes="${SECONDLOOP_PRECOMMIT_ALLOW_WORKTREE_WRITES:-1}"

prepend_path() {
  local dir="$1"
  local normalized_dir="$dir"

  if command -v cygpath >/dev/null 2>&1; then
    normalized_dir="$(cygpath -u "${dir}" 2>/dev/null || echo "${dir}")"
  fi

  export PATH="${normalized_dir}:${PATH}"
}

is_windows_env() {
  local uname_value
  uname_value="$(uname -s 2>/dev/null || true)"
  case "${uname_value}" in
    MINGW* | MSYS* | CYGWIN*) return 0 ;;
  esac

  [[ "${OS:-}" == "Windows_NT" ]]
}

resolve_default_flutter_test_device() {
  if [[ -n "${SECONDLOOP_FLUTTER_TEST_DEVICE_ID:-}" ]]; then
    printf '%s\n' "${SECONDLOOP_FLUTTER_TEST_DEVICE_ID}"
    return 0
  fi

  if is_windows_env; then
    printf '%s\n' "windows"
    return 0
  fi

  case "$(uname -s 2>/dev/null || true)" in
    Darwin)
      printf '%s\n' "macos"
      return 0
      ;;
    Linux)
      printf '%s\n' "linux"
      return 0
      ;;
  esac

  return 1
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

resolve_precommit_temp_root() {
  local temp_root="${SECONDLOOP_PRECOMMIT_TEMP_ROOT:-}"
  local git_common_dir=""

  if [[ -n "${temp_root}" ]]; then
    if command -v cygpath >/dev/null 2>&1; then
      cygpath -u "${temp_root}" 2>/dev/null && return 0
    fi
    printf '%s\n' "${temp_root}"
    return 0
  fi

  if is_windows_env; then
    git_common_dir="$(git rev-parse --git-common-dir 2>/dev/null || true)"
    if [[ -n "${git_common_dir}" ]]; then
      if command -v cygpath >/dev/null 2>&1; then
        git_common_dir="$(cygpath -u "${git_common_dir}" 2>/dev/null || echo "${git_common_dir}")"
      fi
      printf '%s\n' "${git_common_dir}/secondloop-precommit-tmp"
      return 0
    fi

    printf '%s\n' "${repo_root}/.tool/tmp"
    return 0
  fi

  if [[ -z "${temp_root}" ]]; then
    temp_root="${TMPDIR:-${TMP:-${TEMP:-}}}"
  fi

  if [[ -n "${temp_root}" ]]; then
    if command -v cygpath >/dev/null 2>&1; then
      cygpath -u "${temp_root}" 2>/dev/null && return 0
    fi
    printf '%s\n' "${temp_root}"
    return 0
  fi

  printf '%s\n' "/tmp"
}

make_precommit_temp_dir() {
  local prefix="$1"
  local temp_root
  temp_root="$(resolve_precommit_temp_root)"
  mkdir -p "${temp_root}"
  mktemp -d -p "${temp_root}" "${prefix}.XXXXXX"
}

make_precommit_short_path_dir() {
  make_precommit_temp_dir "$1"
}

resolve_dart_bin() {
  if [[ -n "${SECONDLOOP_DART_BIN:-}" ]]; then
    printf '%s\n' "${SECONDLOOP_DART_BIN}"
    return 0
  fi

  if is_windows_env && [[ -f "${repo_root}/.fvm/flutter_sdk/bin/dart.bat" ]]; then
    printf '%s\n' "${repo_root}/.fvm/flutter_sdk/bin/dart.bat"
    return 0
  fi

  if [[ -x "${repo_root}/.fvm/flutter_sdk/bin/dart" ]]; then
    printf '%s\n' "${repo_root}/.fvm/flutter_sdk/bin/dart"
    return 0
  fi

  if is_windows_env && command -v dart.bat >/dev/null 2>&1; then
    command -v dart.bat
    return 0
  fi

  if command -v dart >/dev/null 2>&1; then
    command -v dart
    return 0
  fi

  return 1
}

resolve_pub_cache_root() {
  if [[ -n "${PUB_CACHE:-}" ]]; then
    printf '%s\n' "${PUB_CACHE}"
    return 0
  fi

  if is_windows_env; then
    if [[ -n "${LOCALAPPDATA:-}" ]]; then
      printf '%s\n' "${LOCALAPPDATA}/Pub/Cache"
      return 0
    fi
    if [[ -n "${APPDATA:-}" ]]; then
      printf '%s\n' "${APPDATA}/Pub/Cache"
      return 0
    fi
  fi

  if [[ -n "${HOME:-}" ]]; then
    printf '%s\n' "${HOME}/.pub-cache"
    return 0
  fi

  return 1
}

resolve_pub_log_path() {
  local pub_cache_root
  pub_cache_root="$(resolve_pub_cache_root)" || return 1
  printf '%s\n' "${pub_cache_root}/log/pub_log.txt"
}

pub_log_slice_mentions_advisory_cache_crash() {
  local log_path="$1"
  local start_offset="${2:-0}"
  local log_chunk=""

  [[ -f "${log_path}" ]] || return 1

  if [[ "${start_offset}" =~ ^[0-9]+$ ]] && (( start_offset > 0 )); then
    log_chunk="$(tail -c "+$((start_offset + 1))" "${log_path}" 2>/dev/null || cat "${log_path}" 2>/dev/null || true)"
  else
    log_chunk="$(cat "${log_path}" 2>/dev/null || true)"
  fi

  [[ "${log_chunk}" == *"HostedSource._getAdvisories.readAdvisoriesFromCache"* ]]
}

clear_pub_advisory_cache() {
  local pub_cache_root="$1"
  local hosted_root="${pub_cache_root}/hosted"

  [[ -d "${hosted_root}" ]] || return 0

  find "${hosted_root}" -type f -path '*/.cache/*-advisories.json' -exec rm -f {} + 2>/dev/null || true
}

run_with_pub_advisory_cache_retry() {
  local tool_label="$1"
  shift

  local pub_log_path=""
  local pub_log_size_before=0
  local pub_cache_root=""
  local status=0

  pub_log_path="$(resolve_pub_log_path 2>/dev/null || true)"
  if [[ -n "${pub_log_path}" && -f "${pub_log_path}" ]]; then
    pub_log_size_before="$(wc -c < "${pub_log_path}" 2>/dev/null || echo 0)"
    pub_log_size_before="${pub_log_size_before//[!0-9]/}"
    [[ -n "${pub_log_size_before}" ]] || pub_log_size_before=0
  fi

  if "$@"; then
    return 0
  fi
  status=$?

  if [[ -z "${pub_log_path}" ]] || ! pub_log_slice_mentions_advisory_cache_crash "${pub_log_path}" "${pub_log_size_before}"; then
    return "${status}"
  fi

  pub_cache_root="$(resolve_pub_cache_root 2>/dev/null || true)"
  if [[ -z "${pub_cache_root}" ]]; then
    return "${status}"
  fi

  echo "pre-commit: cleared pub advisory cache after ${tool_label} hit a known pub crash; retrying once." >&2
  clear_pub_advisory_cache "${pub_cache_root}"
  "$@"
}

resolve_flutter_bin() {
  if [[ -n "${SECONDLOOP_FLUTTER_BIN:-}" ]]; then
    printf '%s\n' "${SECONDLOOP_FLUTTER_BIN}"
    return 0
  fi

  if is_windows_env && [[ -f "${repo_root}/.fvm/flutter_sdk/bin/flutter.bat" ]]; then
    printf '%s\n' "${repo_root}/.fvm/flutter_sdk/bin/flutter.bat"
    return 0
  fi

  if [[ -x "${repo_root}/.fvm/flutter_sdk/bin/flutter" ]]; then
    printf '%s\n' "${repo_root}/.fvm/flutter_sdk/bin/flutter"
    return 0
  fi

  if is_windows_env && command -v flutter.bat >/dev/null 2>&1; then
    command -v flutter.bat
    return 0
  fi

  if command -v flutter >/dev/null 2>&1; then
    command -v flutter
    return 0
  fi

  return 1
}

resolve_python_bin() {
  local candidate
  local python_candidates=(
    "${repo_root}/.pixi/envs/default/bin/python"
    "${repo_root}/.pixi/envs/default/python.exe"
    "${repo_root}/.pixi/envs/default/bin/python3"
  )

  for candidate in "${python_candidates[@]}"; do
    if [[ -x "${candidate}" ]]; then
      printf '%s\n' "${candidate}"
      return 0
    fi
  done

  return 1
}

run_windows_batch_tool() {
  local tool_name="$1"
  local tool_bin="$2"
  shift 2
  local args_dir=""
  local args_file=""
  local arg=""

  local powershell_bin
  powershell_bin="$(resolve_powershell_bin)" || die "Missing PowerShell. Install PowerShell or add Flutter/Dart shell shims to PATH."

  local script_path
  script_path="$(to_native_windows_path "${repo_root}/scripts/run_fvm_tool.ps1")"
  local native_tool_path
  native_tool_path="$(to_native_windows_path "${tool_bin}")"
  local native_working_dir
  native_working_dir="$(to_native_windows_path "$(pwd)")"
  args_dir="$(make_precommit_temp_dir secondloop_tool_args)"
  args_file="${args_dir}/argv.txt"
  : > "${args_file}"
  for arg in "$@"; do
    printf '%s\0' "${arg}" >> "${args_file}"
  done
  local native_args_file
  native_args_file="$(to_native_windows_path "${args_file}")"

  env -u GIT_DIR -u GIT_WORK_TREE -u GIT_INDEX_FILE \
    "${powershell_bin}" \
    -NoProfile \
    -ExecutionPolicy Bypass \
    -File "${script_path}" \
    -Tool "${tool_name}" \
    -ToolPath "${native_tool_path}" \
    -WorkingDirectory "${native_working_dir}" \
    -ArgumentsFile "${native_args_file}"
  local status=$?
  rm -rf "${args_dir}" 2>/dev/null || true
  return "${status}"
}

run_dart_tool() {
  local dart_bin
  dart_bin="$(resolve_dart_bin)" || die "Missing 'dart'. Install Flutter (recommended: \`pixi run setup-flutter\`) or add Dart to PATH."

  if [[ "${dart_bin}" == *.bat || "${dart_bin}" == *.cmd ]]; then
    run_with_pub_advisory_cache_retry "dart $*" run_windows_batch_tool dart "${dart_bin}" "$@"
    return $?
  fi

  run_with_pub_advisory_cache_retry "dart $*" env -u GIT_DIR -u GIT_WORK_TREE -u GIT_INDEX_FILE "${dart_bin}" "$@"
}

run_flutter_tool() {
  local flutter_bin
  flutter_bin="$(resolve_flutter_bin)" || die "Missing 'flutter'. Install Flutter (recommended: \`pixi run setup-flutter\`) or add Flutter to PATH."

  if [[ "${flutter_bin}" == *.bat || "${flutter_bin}" == *.cmd ]]; then
    run_with_pub_advisory_cache_retry "flutter $*" run_windows_batch_tool flutter "${flutter_bin}" "$@"
    return $?
  fi

  run_with_pub_advisory_cache_retry "flutter $*" env -u GIT_DIR -u GIT_WORK_TREE -u GIT_INDEX_FILE "${flutter_bin}" "$@"
}

ensure_flutter_package_config() {
  local package_config_path="${repo_root}/.dart_tool/package_config.json"
  if [[ ! -f "${package_config_path}" ]]; then
    echo "pre-commit: restoring Flutter package config after stash..." >&2
    if ! run_flutter_tool pub get; then
      echo "" >&2
      echo "pre-commit: flutter pub get failed." >&2
      echo "Fix locally with: pixi run flutter pub get" >&2
      exit 1
    fi
  fi
}

stage_restored_flutter_dependency_outputs() {
  if [[ ! -f "${repo_root}/pubspec.lock" ]]; then
    return 0
  fi

  if git diff --quiet -- pubspec.lock; then
    return 0
  fi

  echo "pre-commit: auto-staged pubspec.lock after restoring Flutter package config." >&2
  git add -- pubspec.lock
}

is_i18n_source_file() {
  local path="$1"
  case "${path}" in
    slang.yaml | lib/i18n/*.i18n.json) return 0 ;;
    *) return 1 ;;
  esac
}

was_originally_staged_file() {
  local path="$1"
  local staged_file
  for staged_file in "${staged_files[@]}"; do
    if [[ "${staged_file}" == "${path}" ]]; then
      return 0
    fi
  done
  return 1
}

warn_auto_staged_i18n_refresh_changes() {
  local file
  local auto_staged_i18n_files=()

  while IFS= read -r file; do
    [[ -n "${file}" ]] || continue
    is_i18n_source_file "${file}" || continue
    was_originally_staged_file "${file}" && continue
    auto_staged_i18n_files+=("${file}")
  done < <(git diff --name-only -- lib/i18n)

  if [[ ${#auto_staged_i18n_files[@]} -eq 0 ]]; then
    return 0
  fi

  echo "pre-commit: auto-staged i18n refresh changes:" >&2
  printf '  %s\n' "${auto_staged_i18n_files[@]}" >&2
}

run_i18n_refresh() {
  if ! run_with_pub_advisory_cache_retry "i18n refresh" bash scripts/run_i18n_refresh.sh; then
    echo "" >&2
    echo "pre-commit: i18n refresh failed." >&2
    echo "Fix locally with: pixi run i18n-refresh" >&2
    exit 1
  fi
}

run_i18n_analyze() {
  if ! run_with_pub_advisory_cache_retry "i18n analyze" bash scripts/run_i18n_analyze.sh; then
    echo "" >&2
    echo "pre-commit: i18n analyze failed." >&2
    echo "Fix locally with: pixi run i18n-analyze" >&2
    exit 1
  fi
}

ensure_i18n_generated() {
  i18n_generated_now=0

  if [[ -f "lib/i18n/strings.g.dart" ]]; then
    return 0
  fi

  echo "pre-commit: lib/i18n/strings.g.dart missing; regenerating i18n outputs." >&2
  run_i18n_refresh
  i18n_generated_now=1
}

append_unique_path() {
  local candidate="$1"
  shift

  local existing
  for existing in "$@"; do
    if [[ "${existing}" == "${candidate}" ]]; then
      return 1
    fi
  done

  return 0
}

collect_related_flutter_tests_for_lib_file() {
  local file="$1"
  local package_import="package:secondloop/${file#lib/}"
  local match

  if ! command -v rg >/dev/null 2>&1; then
    return 0
  fi

  match="test/${file#lib/}"
  match="${match%.dart}_test.dart"
  if [[ -f "${match}" ]]; then
    printf '%s\n' "${match}"
  fi

  while IFS= read -r match; do
    [[ -n "${match}" && -f "${match}" ]] || continue
    printf '%s\n' "${match}"
  done < <(rg -l --fixed-strings --glob '*_test.dart' "${package_import}" test integration_test 2>/dev/null || true)
}

collect_targeted_flutter_tests() {
  local file
  local targets=()
  local saw_unmapped_lib_change=0
  local related_targets=()
  local candidate

  for file in "${staged_files[@]}"; do
    case "${file}" in
      lib/*.dart | lib/**/*.dart)
        if ! command -v rg >/dev/null 2>&1; then
          saw_unmapped_lib_change=1
          break
        fi
        if [[ ! -f "${file}" ]]; then
          saw_unmapped_lib_change=1
          break
        fi
        related_targets=()
        while IFS= read -r candidate; do
          [[ -n "${candidate}" ]] || continue
          related_targets+=("${candidate}")
        done < <(collect_related_flutter_tests_for_lib_file "${file}")
        if [[ ${#related_targets[@]} -eq 0 ]]; then
          saw_unmapped_lib_change=1
          break
        fi
        for candidate in "${related_targets[@]}"; do
          if append_unique_path "${candidate}" "${targets[@]-}"; then
            targets+=("${candidate}")
          fi
        done
        ;;
      test/*_test.dart | test/**/*_test.dart | integration_test/*_test.dart | integration_test/**/*_test.dart)
        if [[ -f "${file}" ]] && append_unique_path "${file}" "${targets[@]-}"; then
          targets+=("${file}")
        fi
        ;;
    esac
  done

  if [[ ${saw_unmapped_lib_change} -ne 0 ]]; then
    printf '%s\n' "__FULL_SUITE__"
    return 0
  fi

  printf '%s\n' "${targets[@]}"
}
