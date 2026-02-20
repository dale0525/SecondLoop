#!/usr/bin/env bash
set -euo pipefail

if [[ "$#" -eq 0 ]]; then
  echo "Usage: bash scripts/run_with_android_env.sh <command> [args...]" >&2
  exit 1
fi

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TOOL_ROOT="$(cd "$ROOT_DIR/.tool" && pwd -P)"

resolve_rust_toolchain() {
  local toolchain_file="$ROOT_DIR/rust-toolchain.toml"
  if [[ -f "$toolchain_file" ]]; then
    awk -F'"' '/^channel[[:space:]]*=/ {print $2; exit}' "$toolchain_file"
  fi
}

sanitize_android_build_env() {
  local polluted_var
  for polluted_var in \
    AR CC CFLAGS CPPFLAGS CXX CXXFLAGS LD LDFLAGS NM RANLIB STRIP SDKROOT \
    MACOSX_DEPLOYMENT_TARGET \
    CMAKE_ARGS CMAKE_PREFIX_PATH CMAKE_OSX_SYSROOT CMAKE_OSX_ARCHITECTURES CMAKE_OSX_DEPLOYMENT_TARGET
  do
    unset "$polluted_var" || true
  done
}

resolve_android_ndk_root() {
  if [[ -n "${ANDROID_NDK_ROOT:-}" && -d "${ANDROID_NDK_ROOT}" ]]; then
    echo "${ANDROID_NDK_ROOT}"
    return 0
  fi

  if [[ -n "${ANDROID_NDK_HOME:-}" && -d "${ANDROID_NDK_HOME}" ]]; then
    echo "${ANDROID_NDK_HOME}"
    return 0
  fi

  if [[ -n "${ANDROID_NDK:-}" && -d "${ANDROID_NDK}" ]]; then
    echo "${ANDROID_NDK}"
    return 0
  fi

  local ndk_parent="$ANDROID_SDK_ROOT/ndk"
  if [[ ! -d "$ndk_parent" ]]; then
    return 1
  fi

  local discovered=''
  discovered="$(find "$ndk_parent" -mindepth 1 -maxdepth 1 -type d | sort -V | tail -n1 || true)"
  if [[ -z "$discovered" ]]; then
    return 1
  fi

  echo "$discovered"
}

resolve_ndk_sysroot() {
  local ndk_root="$1"
  local prebuilt_dir="$ndk_root/toolchains/llvm/prebuilt"
  if [[ ! -d "$prebuilt_dir" ]]; then
    return 1
  fi

  local preferred=''
  for candidate in "darwin-x86_64" "darwin-arm64" "linux-x86_64"; do
    if [[ -d "$prebuilt_dir/$candidate/sysroot" ]]; then
      preferred="$prebuilt_dir/$candidate/sysroot"
      break
    fi
  done

  if [[ -z "$preferred" ]]; then
    preferred="$(find "$prebuilt_dir" -mindepth 2 -maxdepth 2 -type d -name sysroot | sort | head -n1 || true)"
  fi

  if [[ -z "$preferred" || ! -d "$preferred" ]]; then
    return 1
  fi

  echo "$preferred"
}

export CARGO_HOME="${CARGO_HOME:-"$TOOL_ROOT/cargo"}"
export RUSTUP_HOME="${RUSTUP_HOME:-"$TOOL_ROOT/rustup"}"
export PATH="$CARGO_HOME/bin:$PATH"

resolved_rust_toolchain="$(resolve_rust_toolchain || true)"
export RUSTUP_TOOLCHAIN="${RUSTUP_TOOLCHAIN:-${resolved_rust_toolchain:-stable}}"

export ANDROID_SDK_ROOT="${ANDROID_SDK_ROOT:-"$TOOL_ROOT/android-sdk"}"
export ANDROID_HOME="${ANDROID_HOME:-"$ANDROID_SDK_ROOT"}"
export ANDROID_USER_HOME="${ANDROID_USER_HOME:-"$TOOL_ROOT/android"}"
export GRADLE_USER_HOME="${GRADLE_USER_HOME:-"$TOOL_ROOT/gradle"}"

sanitize_android_build_env

resolved_ndk_root="$(resolve_android_ndk_root || true)"
if [[ -n "$resolved_ndk_root" ]]; then
  export ANDROID_NDK_ROOT="$resolved_ndk_root"
  export ANDROID_NDK_HOME="$resolved_ndk_root"
  export ANDROID_NDK="$resolved_ndk_root"

  toolchain_file="$resolved_ndk_root/build/cmake/android.toolchain.cmake"
  if [[ -f "$toolchain_file" ]]; then
    export CMAKE_TOOLCHAIN_FILE="$toolchain_file"
  fi

  resolved_ndk_sysroot="$(resolve_ndk_sysroot "$resolved_ndk_root" || true)"
  if [[ -n "$resolved_ndk_sysroot" ]]; then
    export BINDGEN_EXTRA_CLANG_ARGS="${BINDGEN_EXTRA_CLANG_ARGS:-"--sysroot=${resolved_ndk_sysroot}"}"
  fi
fi

if command -v ninja >/dev/null 2>&1; then
  export CMAKE_GENERATOR="${CMAKE_GENERATOR:-Ninja}"
  export CMAKE_MAKE_PROGRAM="${CMAKE_MAKE_PROGRAM:-$(command -v ninja)}"
fi

exec "$@"
