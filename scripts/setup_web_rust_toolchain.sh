#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LLVM_SOURCE_ROOT="${SECONDLOOP_WEB_LLVM_SOURCE_ROOT:-$ROOT_DIR}"
TOOL_BIN_DIR="$ROOT_DIR/.tool/bin"
export CARGO_HOME="$ROOT_DIR/.tool/cargo-home"
export RUSTUP_HOME="$ROOT_DIR/.tool/rustup-home"
export PATH="$CARGO_HOME/bin:$PATH"

seed_shared_web_toolchain_if_available() {
  local source_tool_root="${LLVM_SOURCE_ROOT}/.tool"

  if [[ "${LLVM_SOURCE_ROOT}" == "${ROOT_DIR}" ]]; then
    return 0
  fi

  if [[ ! -x "${source_tool_root}/cargo-home/bin/rustup" || ! -d "${source_tool_root}/rustup-home" ]]; then
    return 0
  fi

  rm -rf "$CARGO_HOME" "$RUSTUP_HOME"
  ln -s "${source_tool_root}/cargo-home" "$CARGO_HOME"
  ln -s "${source_tool_root}/rustup-home" "$RUSTUP_HOME"
}

mkdir -p "$TOOL_BIN_DIR"
seed_shared_web_toolchain_if_available
mkdir -p "$CARGO_HOME" "$RUSTUP_HOME"

resolve_rustup_init_url() {
  local os arch
  os="$(uname -s)"
  arch="$(uname -m)"

  case "$os" in
    Darwin)
      case "$arch" in
        arm64|aarch64) echo "https://static.rust-lang.org/rustup/dist/aarch64-apple-darwin/rustup-init" ;;
        x86_64) echo "https://static.rust-lang.org/rustup/dist/x86_64-apple-darwin/rustup-init" ;;
        *) echo "unsupported architecture for rustup-init on macOS: $arch" >&2; return 1 ;;
      esac
      ;;
    Linux)
      case "$arch" in
        x86_64) echo "https://static.rust-lang.org/rustup/dist/x86_64-unknown-linux-gnu/rustup-init" ;;
        arm64|aarch64) echo "https://static.rust-lang.org/rustup/dist/aarch64-unknown-linux-gnu/rustup-init" ;;
        *) echo "unsupported architecture for rustup-init on Linux: $arch" >&2; return 1 ;;
      esac
      ;;
    *)
      echo "unsupported OS for rustup-init: $os" >&2
      return 1
      ;;
  esac
}

sha256_file_hex() {
  local file_path="$1"

  if command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$file_path" | awk '{print $1}'
    return 0
  fi

  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$file_path" | awk '{print $1}'
    return 0
  fi

  if command -v openssl >/dev/null 2>&1; then
    openssl dgst -sha256 "$file_path" | awk '{print $NF}'
    return 0
  fi

  echo "no sha256 tool available to verify $file_path" >&2
  return 1
}

download_file() {
  local url="$1"
  local output_path="$2"
  curl --fail --show-error --location "$url" -o "$output_path"
}

verify_downloaded_sha256() {
  local file_path="$1"
  local checksum_url="$2"
  local checksum_path="${file_path}.sha256"
  local expected actual

  download_file "$checksum_url" "$checksum_path"
  expected="$(awk '{print $1}' "$checksum_path" | tr -d '\r\n')"
  if [[ -z "$expected" ]]; then
    echo "missing sha256 checksum for $file_path" >&2
    return 1
  fi

  actual="$(sha256_file_hex "$file_path")"
  if [[ "$actual" != "$expected" ]]; then
    echo "sha256 mismatch for $file_path" >&2
    echo "expected: $expected" >&2
    echo "actual:   $actual" >&2
    return 1
  fi
}

install_local_rustup_if_needed() {
  if [[ -x "$CARGO_HOME/bin/rustup" ]]; then
    return 0
  fi

  local rustup_init="$TOOL_BIN_DIR/rustup-init"
  local rustup_url
  rustup_url="$(resolve_rustup_init_url)"
  download_file "$rustup_url" "$rustup_init"
  verify_downloaded_sha256 "$rustup_init" "${rustup_url}.sha256"
  chmod +x "$rustup_init"
  RUSTUP_INIT_SKIP_PATH_CHECK=yes \
    "$rustup_init" -y --profile minimal --default-toolchain 1.85.1 --no-modify-path
}

ensure_toolchain() {
  local toolchain="$1"
  if ! "$CARGO_HOME/bin/rustup" toolchain list | grep -q "^${toolchain}"; then
    "$CARGO_HOME/bin/rustup" toolchain install "$toolchain" --profile minimal
  fi
}

ensure_target() {
  local toolchain="$1"
  "$CARGO_HOME/bin/rustup" target add --toolchain "$toolchain" wasm32-unknown-unknown >/dev/null
}

ensure_component() {
  local toolchain="$1"
  local component="$2"
  "$CARGO_HOME/bin/rustup" component add --toolchain "$toolchain" "$component" >/dev/null
}

install_wasm_pack_if_needed() {
  if [[ -x "$CARGO_HOME/bin/wasm-pack" ]]; then
    return 0
  fi
  "$CARGO_HOME/bin/rustup" run nightly cargo install wasm-pack --locked
}

first_executable_path() {
  local candidate
  for candidate in "$@"; do
    [[ -n "${candidate}" ]] || continue
    [[ -x "${candidate}" ]] || continue
    printf '%s\n' "${candidate}"
    return 0
  done

  return 1
}

link_wasm_toolchain_bins_if_available() {
  local clang21_path clangxx21_path llvm_ar_path llvm_ranlib_path

  clang21_path="$(
    first_executable_path \
      "${CONDA_PREFIX:-}/bin/clang" \
      "${CONDA_PREFIX:-}/bin/clang-21" \
      "${LLVM_SOURCE_ROOT}/.pixi/envs/default/bin/clang" \
      "${LLVM_SOURCE_ROOT}/.pixi/envs/default/bin/clang-21" \
      "${ROOT_DIR}/.pixi/envs/default/bin/clang" \
      "${ROOT_DIR}/.pixi/envs/default/bin/clang-21" \
      "${ROOT_DIR}/.tool/bin/clang" \
      "${ROOT_DIR}/.tool/bin/clang-21" \
      "$(command -v clang 2>/dev/null || true)" \
      "$(command -v clang-21 2>/dev/null || true)"
  )" || clang21_path=""
  clangxx21_path="$(
    first_executable_path \
      "${CONDA_PREFIX:-}/bin/clang++" \
      "${CONDA_PREFIX:-}/bin/clang++-21" \
      "${LLVM_SOURCE_ROOT}/.pixi/envs/default/bin/clang++" \
      "${LLVM_SOURCE_ROOT}/.pixi/envs/default/bin/clang++-21" \
      "${ROOT_DIR}/.pixi/envs/default/bin/clang++" \
      "${ROOT_DIR}/.pixi/envs/default/bin/clang++-21" \
      "${ROOT_DIR}/.tool/bin/clang++" \
      "${ROOT_DIR}/.tool/bin/clang++-21" \
      "$(command -v clang++ 2>/dev/null || true)" \
      "$(command -v clang++-21 2>/dev/null || true)"
  )" || clangxx21_path=""
  llvm_ar_path="$(
    first_executable_path \
      "${CONDA_PREFIX:-}/bin/llvm-ar" \
      "${LLVM_SOURCE_ROOT}/.pixi/envs/default/bin/llvm-ar" \
      "${ROOT_DIR}/.pixi/envs/default/bin/llvm-ar" \
      "${ROOT_DIR}/.tool/bin/llvm-ar" \
      "$(command -v llvm-ar 2>/dev/null || true)"
  )" || llvm_ar_path=""
  llvm_ranlib_path="$(
    first_executable_path \
      "${CONDA_PREFIX:-}/bin/llvm-ranlib" \
      "${LLVM_SOURCE_ROOT}/.pixi/envs/default/bin/llvm-ranlib" \
      "${ROOT_DIR}/.pixi/envs/default/bin/llvm-ranlib" \
      "${ROOT_DIR}/.tool/bin/llvm-ranlib" \
      "$(command -v llvm-ranlib 2>/dev/null || true)"
  )" || llvm_ranlib_path=""

  [[ -n "${clang21_path}" ]] && ln -sf "${clang21_path}" "$TOOL_BIN_DIR/clang"
  [[ -n "${clangxx21_path}" ]] && ln -sf "${clangxx21_path}" "$TOOL_BIN_DIR/clang++"
  [[ -n "${llvm_ar_path}" ]] && ln -sf "${llvm_ar_path}" "$TOOL_BIN_DIR/llvm-ar"
  [[ -n "${llvm_ranlib_path}" ]] && ln -sf "${llvm_ranlib_path}" "$TOOL_BIN_DIR/llvm-ranlib"

  return 0
}

resolve_stable_toolchain_name() {
  local os arch
  os="$(uname -s)"
  arch="$(uname -m)"

  case "$os" in
    Darwin)
      case "$arch" in
        arm64|aarch64) echo "1.85.1-aarch64-apple-darwin" ;;
        x86_64) echo "1.85.1-x86_64-apple-darwin" ;;
        *) echo "unsupported architecture for stable Rust toolchain on macOS: $arch" >&2; return 1 ;;
      esac
      ;;
    Linux)
      case "$arch" in
        x86_64) echo "1.85.1-x86_64-unknown-linux-gnu" ;;
        arm64|aarch64) echo "1.85.1-aarch64-unknown-linux-gnu" ;;
        *) echo "unsupported architecture for stable Rust toolchain on Linux: $arch" >&2; return 1 ;;
      esac
      ;;
    *)
      echo "unsupported OS for stable Rust toolchain: $os" >&2
      return 1
      ;;
  esac
}

install_local_rustup_if_needed
stable_toolchain="$(resolve_stable_toolchain_name)"
ensure_toolchain "$stable_toolchain"
ensure_toolchain "nightly"
ensure_target "$stable_toolchain"
ensure_target "nightly"
ensure_component "nightly" "rust-src"
install_wasm_pack_if_needed
link_wasm_toolchain_bins_if_available
