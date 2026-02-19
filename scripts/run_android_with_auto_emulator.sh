#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SDK_ROOT="${ANDROID_SDK_ROOT:-"$ROOT_DIR/.tool/android-sdk"}"
ANDROID_USER_HOME="${ANDROID_USER_HOME:-"$ROOT_DIR/.tool/android"}"
ANDROID_AVD_HOME="${ANDROID_AVD_HOME:-"$ANDROID_USER_HOME/avd"}"

export ANDROID_USER_HOME
export ANDROID_AVD_HOME

ANDROID_API_LEVEL="${SECONDLOOP_ANDROID_API_LEVEL:-34}"
ANDROID_AVD_NAME="${SECONDLOOP_ANDROID_AVD_NAME:-secondloop_api34}"
ANDROID_APP_ID="${SECONDLOOP_ANDROID_APP_ID:-com.secondloop.secondloop}"

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
  if [[ ! -x "$adb_bin" ]]; then
    return 1
  fi

  "$adb_bin" start-server >/dev/null 2>&1 || true

  "$adb_bin" devices | awk 'NR > 1 && $2 == "device" {found = 1} END {exit(found ? 0 : 1)}'
}


first_android_device_serial() {
  if [[ ! -x "$adb_bin" ]]; then
    return 1
  fi

  "$adb_bin" devices | awk 'NR > 1 && $2 == "device" {print $1; exit}'
}

clear_stale_flutter_runtime_cache() {
  local device_serial="$1"

  if [[ -z "$ANDROID_APP_ID" ]]; then
    return 0
  fi

  if ! "$adb_bin" -s "$device_serial" shell pm path "$ANDROID_APP_ID" >/dev/null 2>&1; then
    return 0
  fi

  if "$adb_bin" -s "$device_serial" shell "run-as $ANDROID_APP_ID sh -c 'rm -rf app_flutter cache code_cache'" >/dev/null 2>&1; then
    echo "Cleared stale Flutter runtime cache for $ANDROID_APP_ID on $device_serial"
  fi
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
    local device_serial
    device_serial="$(first_android_device_serial)"
    if [[ -z "$device_serial" ]]; then
      echo "Could not determine Android device serial from adb." >&2
      exit 1
    fi

    clear_stale_flutter_runtime_cache "$device_serial"

    exec bash "$ROOT_DIR/scripts/flutter_with_defines.sh" run -d "$device_serial"
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
