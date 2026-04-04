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

cargo_missing_message() {
  die "Missing 'cargo'. Install Rust in the project environment (recommended: \`pixi install\`) or add cargo to PATH."
}

libclang_missing_message() {
  die "Missing 'libclang'. Install Windows toolchain deps (recommended: \`pixi install\`) or run \`powershell -NoProfile -ExecutionPolicy Bypass -File scripts/setup_windows_libclang.ps1\`."
}

vulkan_sdk_missing_message() {
  die "Missing Vulkan SDK. Install Windows toolchain deps (recommended: \`pixi install\`) or run \`powershell -NoProfile -ExecutionPolicy Bypass -File scripts/setup_windows_vulkan_sdk.ps1\`."
}

prepend_path() {
  local dir="$1"
  local normalized_dir="$dir"

  if command -v cygpath >/dev/null 2>&1; then
    normalized_dir="$(cygpath -u "${dir}" 2>/dev/null || echo "${dir}")"
  fi

  export PATH="${normalized_dir}:${PATH}"
}

resolve_cargo_bin() {
  if [[ -n "${SECONDLOOP_CARGO_BIN:-}" ]]; then
    cargo_bin="${SECONDLOOP_CARGO_BIN}"
    prepend_path "$(dirname "${cargo_bin}")"
    return 0
  fi

  local candidate
  local cargo_candidates=(
    "${repo_root}/.tool/cargo/bin/cargo"
    "${repo_root}/.tool/cargo/bin/cargo.exe"
    "${repo_root}/.pixi/envs/default/bin/cargo"
    "${repo_root}/.pixi/envs/default/bin/cargo.exe"
    "${repo_root}/.pixi/envs/default/Library/bin/cargo"
    "${repo_root}/.pixi/envs/default/Library/bin/cargo.exe"
  )

  for candidate in "${cargo_candidates[@]}"; do
    if [[ -x "${candidate}" ]]; then
      cargo_bin="${candidate}"
      prepend_path "$(dirname "${candidate}")"
      return 0
    fi
  done

  if command -v cargo >/dev/null 2>&1; then
    cargo_bin="$(command -v cargo)"
    return 0
  fi

  return 1
}

resolve_cargo_plugin_bin() {
  local plugin_name="$1"
  local candidate
  local plugin_candidates=(
    "${repo_root}/.tool/cargo/bin/${plugin_name}"
    "${repo_root}/.tool/cargo/bin/${plugin_name}.exe"
    "${repo_root}/.pixi/envs/default/bin/${plugin_name}"
    "${repo_root}/.pixi/envs/default/bin/${plugin_name}.exe"
    "${repo_root}/.pixi/envs/default/Library/bin/${plugin_name}"
    "${repo_root}/.pixi/envs/default/Library/bin/${plugin_name}.exe"
  )

  for candidate in "${plugin_candidates[@]}"; do
    if [[ -x "${candidate}" ]]; then
      prepend_path "$(dirname "${candidate}")"
      printf '%s\n' "${candidate}"
      return 0
    fi
  done

  if command -v "${plugin_name}" >/dev/null 2>&1; then
    command -v "${plugin_name}"
    return 0
  fi

  return 1
}

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

resolve_dart_bin() {
  if [[ -n "${SECONDLOOP_DART_BIN:-}" ]]; then
    printf '%s\n' "${SECONDLOOP_DART_BIN}"
    return 0
  fi

  if [[ -x "${repo_root}/.fvm/flutter_sdk/bin/dart" ]]; then
    printf '%s\n' "${repo_root}/.fvm/flutter_sdk/bin/dart"
    return 0
  fi

  if is_windows_env && [[ -f "${repo_root}/.fvm/flutter_sdk/bin/dart.bat" ]]; then
    printf '%s\n' "${repo_root}/.fvm/flutter_sdk/bin/dart.bat"
    return 0
  fi

  if command -v dart >/dev/null 2>&1; then
    command -v dart
    return 0
  fi

  if is_windows_env && command -v dart.bat >/dev/null 2>&1; then
    command -v dart.bat
    return 0
  fi

  return 1
}

resolve_flutter_bin() {
  if [[ -n "${SECONDLOOP_FLUTTER_BIN:-}" ]]; then
    printf '%s\n' "${SECONDLOOP_FLUTTER_BIN}"
    return 0
  fi

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
    if [[ -x "${candidate}" || -f "${candidate}" ]]; then
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

  local powershell_bin
  powershell_bin="$(resolve_powershell_bin)" || die "Missing PowerShell. Install PowerShell or add Flutter/Dart shell shims to PATH."

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

run_dart_tool() {
  local dart_bin
  dart_bin="$(resolve_dart_bin)" || die "Missing 'dart'. Install Flutter (recommended: \`pixi run setup-flutter\`) or add Dart to PATH."

  if [[ "${dart_bin}" == *.bat || "${dart_bin}" == *.cmd ]]; then
    run_windows_batch_tool dart "${dart_bin}" "$@"
    return $?
  fi

  env -u GIT_DIR -u GIT_WORK_TREE -u GIT_INDEX_FILE "${dart_bin}" "$@"
}

run_flutter_tool() {
  local flutter_bin
  flutter_bin="$(resolve_flutter_bin)" || die "Missing 'flutter'. Install Flutter (recommended: \`pixi run setup-flutter\`) or add Flutter to PATH."

  if [[ "${flutter_bin}" == *.bat || "${flutter_bin}" == *.cmd ]]; then
    run_windows_batch_tool flutter "${flutter_bin}" "$@"
    return $?
  fi

  env -u GIT_DIR -u GIT_WORK_TREE -u GIT_INDEX_FILE "${flutter_bin}" "$@"
}

resolve_libclang_path() {
  if ! is_windows_env; then
    return 0
  fi

  local candidate
  local libclang_candidates=()

  if [[ -n "${LIBCLANG_PATH:-}" ]]; then
    if [[ -d "${LIBCLANG_PATH}" ]]; then
      libclang_candidates+=("${LIBCLANG_PATH}")
    elif [[ -f "${LIBCLANG_PATH}" ]]; then
      libclang_candidates+=("$(dirname "${LIBCLANG_PATH}")")
    fi
  fi

  if [[ -n "${CONDA_PREFIX:-}" ]]; then
    libclang_candidates+=("${CONDA_PREFIX}/Library/bin")
    libclang_candidates+=("${CONDA_PREFIX}/bin")
  fi

  libclang_candidates+=("${repo_root}/.tool/libclang")
  libclang_candidates+=("${repo_root}/.tool/libclang/bin")
  libclang_candidates+=("${repo_root}/.pixi/envs/default/Library/bin")
  libclang_candidates+=("${repo_root}/.pixi/envs/default/bin")

  for candidate in "${libclang_candidates[@]}"; do
    [[ -d "${candidate}" ]] || continue

    if [[ -f "${candidate}/libclang.dll" || -f "${candidate}/clang.dll" ]]; then
      export LIBCLANG_PATH="${candidate}"
      prepend_path "${candidate}"
      return 0
    fi

    shopt -s nullglob
    local versioned_libclang_dlls=("${candidate}"/libclang-*.dll)
    shopt -u nullglob
    if (( ${#versioned_libclang_dlls[@]} > 0 )); then
      local shim_dir="${repo_root}/.tool/libclang"
      if [[ "${precommit_allow_worktree_writes}" != "1" ]]; then
        shim_dir="$(mktemp -d 2>/dev/null || mktemp -d -t secondloop_libclang)"
      else
        mkdir -p "${shim_dir}"
      fi
      cp -f "${versioned_libclang_dlls[0]}" "${shim_dir}/libclang.dll"
      export LIBCLANG_PATH="${shim_dir}"
      prepend_path "${shim_dir}"
      return 0
    fi
  done

  return 1
}

has_vulkan_sdk_layout() {
  local root="$1"
  local include_candidates=(
    "${root}/Include/vulkan/vulkan.h"
    "${root}/include/vulkan/vulkan.h"
  )
  local lib_candidates=(
    "${root}/Lib/vulkan-1.lib"
    "${root}/lib/vulkan-1.lib"
  )

  local include_ok=1
  local candidate
  for candidate in "${include_candidates[@]}"; do
    if [[ -f "${candidate}" ]]; then
      include_ok=0
      break
    fi
  done

  local lib_ok=1
  for candidate in "${lib_candidates[@]}"; do
    if [[ -f "${candidate}" ]]; then
      lib_ok=0
      break
    fi
  done

  [[ ${include_ok} -eq 0 && ${lib_ok} -eq 0 ]]
}

resolve_vulkan_sdk_root() {
  if ! is_windows_env; then
    return 0
  fi

  local candidate
  local vulkan_candidates=()

  if [[ -n "${SECONDLOOP_WINDOWS_VULKAN_SDK_ROOT:-}" ]]; then
    vulkan_candidates+=("${SECONDLOOP_WINDOWS_VULKAN_SDK_ROOT}")
  fi

  if [[ -n "${VULKAN_SDK:-}" ]]; then
    vulkan_candidates+=("${VULKAN_SDK}")
  fi

  local project_vulkan_root="${repo_root}/.tool/vulkan-sdk"
  if [[ -d "${project_vulkan_root}" ]]; then
    vulkan_candidates+=("${project_vulkan_root}/1.4.309.0")
    shopt -s nullglob
    local project_vulkan_versions=("${project_vulkan_root}"/*)
    shopt -u nullglob
    if (( ${#project_vulkan_versions[@]} > 0 )); then
      vulkan_candidates+=("${project_vulkan_versions[@]}")
    fi
  fi

  vulkan_candidates+=("C:/VulkanSDK/1.4.309.0")
  vulkan_candidates+=("C:/Program Files/VulkanSDK/1.4.309.0")

  for candidate in "${vulkan_candidates[@]}"; do
    [[ -d "${candidate}" ]] || continue
    if ! has_vulkan_sdk_layout "${candidate}"; then
      continue
    fi

    export VULKAN_SDK="${candidate}"
    export SECONDLOOP_WINDOWS_VULKAN_SDK_ROOT="${candidate}"
    prepend_path "${candidate}/Bin"
    prepend_path "${candidate}/bin"
    prepend_path "${candidate}/Library/bin"
    return 0
  done

  return 1
}

ensure_windows_short_build_paths() {
  if ! is_windows_env; then
    return 0
  fi

  local drive_prefix=""
  local short_temp_root=""
  if [[ "${repo_root}" =~ ^/([a-zA-Z])(/|$) ]]; then
    drive_prefix="/${BASH_REMATCH[1]}"
  fi

  if [[ -n "${drive_prefix}" ]]; then
    short_temp_root="${drive_prefix}/stmp"
  else
    short_temp_root="${repo_root}/.tool/stmp"
  fi
  mkdir -p "${short_temp_root}"

  if [[ -z "${CARGO_TARGET_DIR:-}" ]]; then
    if [[ -n "${drive_prefix}" ]]; then
      export CARGO_TARGET_DIR="${drive_prefix}/ct"
    elif [[ -n "${short_temp_root}" ]]; then
      export CARGO_TARGET_DIR="${repo_root}/.tool/ct"
    elif [[ "${precommit_allow_worktree_writes}" != "1" ]]; then
      export CARGO_TARGET_DIR="$(mktemp -d 2>/dev/null || mktemp -d -t secondloop_ct)"
    else
      export CARGO_TARGET_DIR="${repo_root}/.tool/ct"
    fi
    mkdir -p "${CARGO_TARGET_DIR}"
  fi

  if [[ -z "${CARGOKIT_TARGET_TEMP_DIR:-}" ]]; then
    if [[ -n "${drive_prefix}" ]]; then
      export CARGOKIT_TARGET_TEMP_DIR="${drive_prefix}/ck"
    elif [[ -n "${short_temp_root}" ]]; then
      export CARGOKIT_TARGET_TEMP_DIR="${repo_root}/.tool/ck"
    elif [[ "${precommit_allow_worktree_writes}" != "1" ]]; then
      export CARGOKIT_TARGET_TEMP_DIR="$(mktemp -d 2>/dev/null || mktemp -d -t secondloop_ck)"
    else
      export CARGOKIT_TARGET_TEMP_DIR="${repo_root}/.tool/ck"
    fi
    mkdir -p "${CARGOKIT_TARGET_TEMP_DIR}"
  fi

  if [[ -z "${CARGOKIT_TOOL_TEMP_DIR:-}" ]]; then
    export CARGOKIT_TOOL_TEMP_DIR="${CARGOKIT_TARGET_TEMP_DIR}/tool"
    mkdir -p "${CARGOKIT_TOOL_TEMP_DIR}"
  fi

  export TMPDIR="${short_temp_root}"
  export TMP="${short_temp_root}"
  export TEMP="${short_temp_root}"

  export CMAKE_GENERATOR="Ninja"
  unset CMAKE_GENERATOR_INSTANCE || true
  unset CMAKE_GENERATOR_TOOLSET || true
  unset CMAKE_GENERATOR_PLATFORM || true
  unset HOST_CMAKE_GENERATOR_INSTANCE || true
  unset HOST_CMAKE_GENERATOR_TOOLSET || true
  unset HOST_CMAKE_GENERATOR_PLATFORM || true
  unset CMAKE_GENERATOR_INSTANCE_x86_64_pc_windows_msvc || true
  unset CMAKE_GENERATOR_TOOLSET_x86_64_pc_windows_msvc || true
  unset CMAKE_GENERATOR_PLATFORM_x86_64_pc_windows_msvc || true

  shopt -s nullglob
  local whisper_build_dirs=("${CARGO_TARGET_DIR}"/debug/build/whisper-rs-sys-*)
  shopt -u nullglob
  local whisper_dir
  for whisper_dir in "${whisper_build_dirs[@]}"; do
    rm -rf "${whisper_dir}" 2>/dev/null || true
  done
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
  if ! bash scripts/run_i18n_refresh.sh; then
    echo "" >&2
    echo "pre-commit: i18n refresh failed." >&2
    echo "Fix locally with: pixi run i18n-refresh" >&2
    exit 1
  fi
}

run_i18n_analyze() {
  if ! bash scripts/run_i18n_analyze.sh; then
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
