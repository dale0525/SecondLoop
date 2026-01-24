#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

dotenv_file="${repo_root}/.env.local"
if [[ -f "${dotenv_file}" ]]; then
  set -a
  # shellcheck disable=SC1090
  source "${dotenv_file}"
  set +a
fi

all_args=("$@")

has_dart_define() {
  local key="$1"
  local arg
  for arg in "${all_args[@]}"; do
    case "${arg}" in
      --dart-define=${key}=*) return 0 ;;
    esac
  done
  return 1
}

if [[ "${SECONDLOOP_CLOUD_GATEWAY_BASE_URL+set}" == "set" ]]; then
  cat >&2 <<'EOF'
SecondLoop: do not set SECONDLOOP_CLOUD_GATEWAY_BASE_URL in `.env.local`.
Use:
- SECONDLOOP_CLOUD_ENV=staging|prod
- SECONDLOOP_CLOUD_GATEWAY_BASE_URL_STAGING=...
- SECONDLOOP_CLOUD_GATEWAY_BASE_URL_PROD=...
EOF
  exit 1
fi

if [[ "${SECONDLOOP_MANAGED_VAULT_BASE_URL+set}" == "set" ]]; then
  cat >&2 <<'EOF'
SecondLoop: do not set SECONDLOOP_MANAGED_VAULT_BASE_URL in `.env.local`.
Use:
- SECONDLOOP_CLOUD_ENV=staging|prod
- SECONDLOOP_MANAGED_VAULT_BASE_URL_STAGING=...
- SECONDLOOP_MANAGED_VAULT_BASE_URL_PROD=...
EOF
  exit 1
fi

cloud_gateway_base_url=''
managed_vault_base_url=''
cloud_env="${SECONDLOOP_CLOUD_ENV-}"
if [[ -n "${cloud_env}" ]]; then
  cloud_env_lc="$(printf '%s' "${cloud_env}" | tr '[:upper:]' '[:lower:]')"
  case "${cloud_env_lc}" in
    staging|stage)
      cloud_gateway_base_url="${SECONDLOOP_CLOUD_GATEWAY_BASE_URL_STAGING-}"
      managed_vault_base_url="${SECONDLOOP_MANAGED_VAULT_BASE_URL_STAGING-}"
      ;;
    prod|production)
      cloud_gateway_base_url="${SECONDLOOP_CLOUD_GATEWAY_BASE_URL_PROD-}"
      managed_vault_base_url="${SECONDLOOP_MANAGED_VAULT_BASE_URL_PROD-}"
      ;;
  esac
fi

defines=()
maybe_define_value() {
  local key="$1"
  local value="$2"
  if has_dart_define "${key}"; then
    return 0
  fi
  if [[ -z "${value}" ]]; then
    return 0
  fi
  defines+=("--dart-define=${key}=${value}")
}

maybe_define() {
  local key="$1"
  maybe_define_value "${key}" "${!key-}"
}

maybe_define SECONDLOOP_FIREBASE_WEB_API_KEY
maybe_define_value SECONDLOOP_CLOUD_GATEWAY_BASE_URL "${cloud_gateway_base_url}"
maybe_define_value SECONDLOOP_MANAGED_VAULT_BASE_URL "${managed_vault_base_url}"

if [[ -z "${SECONDLOOP_FIREBASE_WEB_API_KEY-}" && ! -f "${dotenv_file}" ]]; then
  cat >&2 <<'EOF'
SecondLoop: missing SECONDLOOP_FIREBASE_WEB_API_KEY.
- Copy `.env.example` to `.env.local`
- Fill in `SECONDLOOP_FIREBASE_WEB_API_KEY=...`
EOF
fi

exec dart pub global run fvm:main flutter "$@" "${defines[@]}"
