#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SDK_ROOT="${ANDROID_SDK_ROOT:-"$ROOT_DIR/.tool/android-sdk"}"

if ! command -v curl >/dev/null 2>&1; then
  echo "Missing dependency: curl" >&2
  exit 1
fi

if ! command -v unzip >/dev/null 2>&1; then
  echo "Missing dependency: unzip" >&2
  exit 1
fi

if ! command -v java >/dev/null 2>&1; then
  echo "Missing dependency: java (install via pixi: openjdk=17.*)" >&2
  exit 1
fi

java_version_line="$(java -version 2>&1 | head -n 1 || true)"
java_version_str="$(java -version 2>&1 | awk -F\" '/version/ {print $2; exit}' || true)"
if [[ -z "$java_version_str" ]]; then
  echo "Could not determine Java version from: $java_version_line" >&2
  exit 1
fi

java_major="${java_version_str%%.*}"
if [[ "$java_major" == "1" ]]; then
  java_major="$(echo "$java_version_str" | cut -d. -f2)"
fi
if [[ -z "$java_major" ]]; then
  echo "Could not determine Java major version from: $java_version_line" >&2
  exit 1
fi

if [[ "$java_major" -lt 17 ]]; then
  echo "Java 17+ is required for Android sdkmanager; found: $java_version_line" >&2
  exit 1
fi

os="$(uname -s)"
case "$os" in
  Darwin) sdk_os="mac" ;;
  Linux) sdk_os="linux" ;;
  *)
    echo "Unsupported OS for Android commandline-tools: $os" >&2
    exit 1
    ;;
esac

cmdline_tools_rev="11076708"
zip_name="commandlinetools-${sdk_os}-${cmdline_tools_rev}_latest.zip"
zip_url="https://dl.google.com/android/repository/${zip_name}"

download_dir="$ROOT_DIR/.tool/cache/android"
zip_path="$download_dir/$zip_name"

mkdir -p "$download_dir"
mkdir -p "$SDK_ROOT"

if [[ ! -f "$zip_path" ]]; then
  echo "Downloading Android commandline-tools: $zip_url"
  curl -fsSL "$zip_url" -o "$zip_path"
fi

sdkmanager="$SDK_ROOT/cmdline-tools/latest/bin/sdkmanager"
if [[ ! -x "$sdkmanager" ]]; then
  echo "Installing Android commandline-tools into: $SDK_ROOT/cmdline-tools/latest"
  rm -rf "$SDK_ROOT/cmdline-tools"
  mkdir -p "$SDK_ROOT/cmdline-tools/latest"

  tmp_dir="$(mktemp -d)"
  trap 'rm -rf "$tmp_dir"' EXIT
  unzip -q "$zip_path" -d "$tmp_dir"

  if [[ ! -d "$tmp_dir/cmdline-tools" ]]; then
    echo "Unexpected zip layout: missing cmdline-tools directory" >&2
    exit 1
  fi

  cp -R "$tmp_dir/cmdline-tools/"* "$SDK_ROOT/cmdline-tools/latest/"
fi

sdkmanager="$SDK_ROOT/cmdline-tools/latest/bin/sdkmanager"
if [[ ! -x "$sdkmanager" ]]; then
  echo "sdkmanager not found at: $sdkmanager" >&2
  exit 1
fi

echo "Accepting Android SDK licenses…"
(
  set +o pipefail
  yes | "$sdkmanager" --sdk_root="$SDK_ROOT" --licenses >/dev/null
)

echo "Installing Android SDK packages into: $SDK_ROOT"
"$sdkmanager" --sdk_root="$SDK_ROOT" --install \
  "platform-tools" \
  "platforms;android-34" \
  "platforms;android-33" \
  "build-tools;34.0.0" \
  "build-tools;33.0.2" \
  "ndk;23.1.7779620"

echo "Android SDK ready: $SDK_ROOT"
