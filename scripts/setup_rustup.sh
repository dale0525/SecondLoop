#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WHISPER_PATCH_APPLIED=0

resolve_rust_toolchain() {
  local toolchain_file="$ROOT_DIR/rust-toolchain.toml"
  if [[ -f "$toolchain_file" ]]; then
    awk -F'"' '/^channel[[:space:]]*=/ {print $2; exit}' "$toolchain_file"
  fi
}

prefetch_android_cargo_dependencies() {
  local toolchain="$1"

  if ! rustup run "$toolchain" cargo fetch --manifest-path "$ROOT_DIR/rust/Cargo.toml" \
    --target aarch64-linux-android \
    --target armv7-linux-androideabi \
    --target i686-linux-android \
    --target x86_64-linux-android >/dev/null 2>&1
  then
    echo "setup-rustup: warning: cargo fetch failed; continuing without prefetch" >&2
  fi
}

patch_whisper_rs_sys_build_script() {
  local registry_root="$CARGO_HOME/registry/src"
  if [[ ! -d "$registry_root" ]]; then
    return 0
  fi

  local build_rs_files=()
  while IFS= read -r -d '' file; do
    build_rs_files+=("$file")
  done < <(find "$registry_root" -type f -path '*/whisper-rs-sys-0.14.1/build.rs' -print0 2>/dev/null)

  if [[ ${#build_rs_files[@]} -eq 0 ]]; then
    echo "setup-rustup: whisper-rs-sys-0.14.1/build.rs not found in cargo registry" >&2
    return 0
  fi

  local build_rs
  local patched_count=0
  local already_count=0
  for build_rs in "${build_rs_files[@]}"; do
    local patch_state
    patch_state="$(python3 - "$build_rs" <<'PY_PATCH_WHISPER_RS_SYS'
import pathlib
import sys

path = pathlib.Path(sys.argv[1])
text = path.read_text(encoding='utf-8')
needle = 'if cfg!(target_os = "macos") || cfg!(feature = "openblas") {'
replacement = 'if target.contains("apple-darwin") || cfg!(feature = "openblas") {'

if replacement in text:
    print('already')
elif needle in text:
    path.write_text(text.replace(needle, replacement, 1), encoding='utf-8')
    print('patched')
else:
    print('unexpected')
PY_PATCH_WHISPER_RS_SYS
)"

    case "$patch_state" in
      patched)
        patched_count=$((patched_count + 1))
        WHISPER_PATCH_APPLIED=1
        echo "setup-rustup: patched whisper-rs-sys for Android cross-compile (${build_rs})"
        ;;
      already)
        already_count=$((already_count + 1))
        ;;
      *)
        echo "setup-rustup: warning: unexpected whisper-rs-sys build.rs content (${build_rs})" >&2
        ;;
    esac
  done

  if [[ "$patched_count" -eq 0 && "$already_count" -gt 0 ]]; then
    echo "setup-rustup: whisper-rs-sys patch already applied"
  fi
}

purge_stale_whisper_rs_sys_build_cache() {
  local build_root="$ROOT_DIR/build/secondloop_rust/build"
  if [[ ! -d "$build_root" ]]; then
    return 0
  fi

  local removed=0
  while IFS= read -r -d '' cache_dir; do
    rm -rf "$cache_dir"
    removed=$((removed + 1))
  done < <(find "$build_root" -type d -name 'whisper-rs-sys-*' -print0 2>/dev/null)

  if [[ "$removed" -gt 0 ]]; then
    echo "setup-rustup: cleared stale whisper-rs-sys build cache entries: ${removed}"
  fi
}

if ! command -v curl >/dev/null 2>&1; then
  echo "Missing dependency: curl" >&2
  exit 1
fi

os="$(uname -s)"
arch="$(uname -m)"

case "$os" in
  Darwin)
    case "$arch" in
      arm64|aarch64) rustup_target="aarch64-apple-darwin" ;;
      x86_64) rustup_target="x86_64-apple-darwin" ;;
      *)
        echo "Unsupported architecture for rustup-init on macOS: $arch" >&2
        exit 1
        ;;
    esac
    ;;
  Linux)
    case "$arch" in
      x86_64) rustup_target="x86_64-unknown-linux-gnu" ;;
      arm64|aarch64) rustup_target="aarch64-unknown-linux-gnu" ;;
      *)
        echo "Unsupported architecture for rustup-init on Linux: $arch" >&2
        exit 1
        ;;
    esac
    ;;
  *)
    echo "Unsupported OS for rustup-init: $os" >&2
    exit 1
    ;;
esac

export CARGO_HOME="${CARGO_HOME:-"$ROOT_DIR/.tool/cargo"}"
export RUSTUP_HOME="${RUSTUP_HOME:-"$ROOT_DIR/.tool/rustup"}"

mkdir -p "$CARGO_HOME" "$RUSTUP_HOME"

resolved_rust_toolchain="$(resolve_rust_toolchain || true)"
rust_toolchain="${RUSTUP_TOOLCHAIN:-${resolved_rust_toolchain:-stable}}"
export RUSTUP_TOOLCHAIN="$rust_toolchain"

rustup_bin="$CARGO_HOME/bin/rustup"
if [[ -x "$rustup_bin" ]]; then
  echo "rustup already installed: $rustup_bin"
else
  download_dir="$ROOT_DIR/.tool/cache/rustup"
  mkdir -p "$download_dir"

  rustup_init="$download_dir/rustup-init-$rustup_target"
  update_root="${RUSTUP_UPDATE_ROOT:-https://static.rust-lang.org/rustup}"
  url="${update_root}/dist/${rustup_target}/rustup-init"

  if [[ ! -f "$rustup_init" ]]; then
    echo "Downloading rustup-init: $url"
    if ! curl -fsSL "$url" -o "$rustup_init"; then
      fallback_url="https://rsproxy.cn/rustup/dist/${rustup_target}/rustup-init"
      echo "Retrying rustup-init download via rsproxy: $fallback_url"
      curl -fsSL "$fallback_url" -o "$rustup_init"
    fi
    chmod +x "$rustup_init"
  fi

  echo "Installing rustup into: $CARGO_HOME (RUSTUP_HOME=$RUSTUP_HOME)"
  "$rustup_init" -y --no-modify-path --profile minimal --default-toolchain "$rust_toolchain"
fi

export PATH="$CARGO_HOME/bin:$PATH"

rustup toolchain install "$rust_toolchain" --profile minimal

echo "Installing Android Rust targets ($rust_toolchain)…"
rustup target add --toolchain "$rust_toolchain" \
  aarch64-linux-android \
  armv7-linux-androideabi \
  i686-linux-android \
  x86_64-linux-android

prefetch_android_cargo_dependencies "$rust_toolchain"
patch_whisper_rs_sys_build_script
if [[ "$WHISPER_PATCH_APPLIED" -eq 1 ]]; then
  purge_stale_whisper_rs_sys_build_cache
fi

echo "rustup ready: $(command -v rustup)"
