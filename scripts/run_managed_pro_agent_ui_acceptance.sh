#!/usr/bin/env bash
set -euo pipefail

repo_root="$(git rev-parse --show-toplevel)"
cd "${repo_root}"

if [[ -f .env.local ]]; then
  set -a
  # shellcheck disable=SC1091
  source .env.local
  set +a
fi

timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
output_dir="${SECONDLOOP_MANAGED_PRO_ACCEPTANCE_OUTPUT_DIR:-build/managed_pro_acceptance/${timestamp}}"
device_id="${SECONDLOOP_FLUTTER_TEST_DEVICE_ID:-macos}"

mkdir -p "${output_dir}/logs"

require_env() {
  local name="$1"
  if [[ -z "${!name:-}" ]]; then
    echo "managed-pro-agent-ui-acceptance: missing required ${name}" >&2
    exit 1
  fi
}

if [[ -z "${SECONDLOOP_MANAGED_PRO_EMAIL:-}" && -n "${SECONDLOOP_LIVE_MANAGED_PRO_EMAIL:-}" ]]; then
  export SECONDLOOP_MANAGED_PRO_EMAIL="${SECONDLOOP_LIVE_MANAGED_PRO_EMAIL}"
fi
if [[ -z "${SECONDLOOP_MANAGED_PRO_PASSWORD:-}" && -n "${SECONDLOOP_LIVE_MANAGED_PRO_PASSWORD:-}" ]]; then
  export SECONDLOOP_MANAGED_PRO_PASSWORD="${SECONDLOOP_LIVE_MANAGED_PRO_PASSWORD}"
fi

require_env SECONDLOOP_MANAGED_PRO_EMAIL
require_env SECONDLOOP_MANAGED_PRO_PASSWORD

export SECONDLOOP_APP_ID=com.secondloop.secondloopdev
export SECONDLOOP_APP_NAME='SecondLoop Dev'
export SECONDLOOP_MANAGED_PRO_ACCEPTANCE_OUTPUT_DIR="${output_dir}"

{
  echo "SecondLoop managed pro agent UI acceptance"
  echo "timestamp=${timestamp}"
  echo "device_id=${device_id}"
  echo "app_id=${SECONDLOOP_APP_ID}"
  echo "app_name=${SECONDLOOP_APP_NAME}"
  echo "managed_pro_email=${SECONDLOOP_MANAGED_PRO_EMAIL:+provided}"
  echo "managed_pro_password=${SECONDLOOP_MANAGED_PRO_PASSWORD:+provided}"
} >"${output_dir}/environment.txt"

env -u AR -u CC -u CFLAGS -u CPPFLAGS -u CXX -u CXXFLAGS -u LD -u LDFLAGS \
  -u NM -u RANLIB -u SDKROOT -u STRIP \
  LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8 \
  bash scripts/flutter_with_defines.sh test \
  -d "${device_id}" \
  integration_test/managed_pro_agent_ui_acceptance_test.dart \
  2>&1 | tee "${output_dir}/logs/flutter-test.log"
