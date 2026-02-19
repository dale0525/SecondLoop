#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SDK_ROOT="${ANDROID_SDK_ROOT:-"$ROOT_DIR/.tool/android-sdk"}"
ANDROID_USER_HOME="${ANDROID_USER_HOME:-"$ROOT_DIR/.tool/android"}"
ANDROID_AVD_HOME="${ANDROID_AVD_HOME:-"$ANDROID_USER_HOME/avd"}"

ANDROID_API_LEVEL="${SECONDLOOP_ANDROID_API_LEVEL:-34}"
ANDROID_AVD_NAME="${SECONDLOOP_ANDROID_AVD_NAME:-secondloop_api34}"

system_image_arch="${SECONDLOOP_ANDROID_IMAGE_ARCH:-}"
if [[ -z "$system_image_arch" ]]; then
  case "$(uname -m)" in
    arm64|aarch64)
      system_image_arch="arm64-v8a"
      ;;
    *)
      system_image_arch="x86_64"
      ;;
  esac
fi

system_image_package="system-images;android-${ANDROID_API_LEVEL};google_apis;${system_image_arch}"

sdkmanager="$SDK_ROOT/cmdline-tools/latest/bin/sdkmanager"
avdmanager="$SDK_ROOT/cmdline-tools/latest/bin/avdmanager"
emulator_bin="$SDK_ROOT/emulator/emulator"
adb_bin="$SDK_ROOT/platform-tools/adb"

has_connected_android_device() {
  local devices_json
  devices_json="$(bash "$ROOT_DIR/scripts/flutter_with_defines.sh" devices --machine 2>/dev/null || true)"
  if [[ -z "$devices_json" ]]; then
    return 1
  fi

  if ! DEVICES_JSON="$devices_json" python - <<'PY'; then
import json
import os
import sys

raw = os.environ.get("DEVICES_JSON", "").strip()
if not raw:
    raise SystemExit(1)

try:
    devices = json.loads(raw)
except json.JSONDecodeError:
    raise SystemExit(1)

for device in devices:
    target_platform = str(device.get("targetPlatform", ""))
    if target_platform.startswith("android"):
        raise SystemExit(0)

raise SystemExit(1)
PY
    return 1
  fi

  return 0
}

ensure_emulator_components() {
  if [[ ! -x "$sdkmanager" ]]; then
    echo "sdkmanager not found at $sdkmanager" >&2
    exit 1
  fi

  echo "No Android device detected. Installing Android emulator components..."
  (
    set +o pipefail
    yes | "$sdkmanager" --sdk_root="$SDK_ROOT" --licenses >/dev/null
  )

  "$sdkmanager" --sdk_root="$SDK_ROOT" --install \
    "emulator" \
    "$system_image_package"
}

ensure_avd() {
  if [[ ! -x "$avdmanager" ]]; then
    echo "avdmanager not found at $avdmanager" >&2
    exit 1
  fi

  if [[ ! -x "$emulator_bin" ]]; then
    echo "Android emulator binary not found at $emulator_bin" >&2
    exit 1
  fi

  mkdir -p "$ANDROID_AVD_HOME"

  if "$emulator_bin" -list-avds | grep -Fxq "$ANDROID_AVD_NAME"; then
    echo "Using existing Android AVD: $ANDROID_AVD_NAME"
    return 0
  fi

  echo "Creating Android AVD: $ANDROID_AVD_NAME"
  echo "no" | "$avdmanager" create avd \
    --force \
    --name "$ANDROID_AVD_NAME" \
    --package "$system_image_package" \
    --device "pixel_7"
}

wait_for_emulator_boot() {
  local timeout_seconds=360
  local elapsed=0

  while (( elapsed < timeout_seconds )); do
    local serial
    serial="$("$adb_bin" devices | awk 'NR > 1 && $1 ~ /^emulator-/ && $2 == "device" {print $1; exit}')"
    if [[ -n "$serial" ]]; then
      local boot_completed
      boot_completed="$("$adb_bin" -s "$serial" shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')"
      if [[ "$boot_completed" == "1" ]]; then
        echo "Android emulator boot completed: $serial"
        return 0
      fi
    fi

    sleep 2
    ((elapsed += 2))
  done

  echo "Timed out waiting for Android emulator boot completion." >&2
  return 1
}

start_emulator_if_needed() {
  if [[ ! -x "$adb_bin" ]]; then
    echo "adb not found at $adb_bin" >&2
    exit 1
  fi

  if "$adb_bin" devices | awk 'NR > 1 && $1 ~ /^emulator-/ && $2 == "device" {found = 1} END {exit(found ? 0 : 1)}'; then
    echo "Android emulator is already running."
    return 0
  fi

  local emulator_log
  emulator_log="$ROOT_DIR/.tool/android/emulator-${ANDROID_AVD_NAME}.log"
  mkdir -p "$(dirname "$emulator_log")"

  echo "Starting Android emulator: $ANDROID_AVD_NAME"
  "$emulator_bin" -avd "$ANDROID_AVD_NAME" -no-snapshot-load -no-boot-anim >"$emulator_log" 2>&1 &

  wait_for_emulator_boot || {
    echo "Emulator log: $emulator_log" >&2
    return 1
  }
}

run_flutter_android() {
  if [[ "$#" -eq 0 ]]; then
    exec bash "$ROOT_DIR/scripts/flutter_with_defines.sh" run -d android
  fi

  exec bash "$ROOT_DIR/scripts/flutter_with_defines.sh" "$@"
}

if has_connected_android_device; then
  echo "Detected connected Android device. Running Flutter app..."
  run_flutter_android "$@"
fi

ensure_emulator_components
ensure_avd
start_emulator_if_needed

if ! has_connected_android_device; then
  echo "Android device is still unavailable after emulator setup." >&2
  exit 1
fi

echo "Android device is ready. Running Flutter app..."
run_flutter_android "$@"
