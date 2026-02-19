#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

resolve_rust_toolchain() {
  local toolchain_file="$ROOT_DIR/rust-toolchain.toml"
  if [[ -f "$toolchain_file" ]]; then
    awk -F'"' '/^channel[[:space:]]*=/ {print $2; exit}' "$toolchain_file"
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

echo "rustup ready: $(command -v rustup)"
