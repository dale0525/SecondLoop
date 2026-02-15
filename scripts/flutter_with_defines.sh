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

should_sanitize_macos_module_cache() {
  local arg
  local expects_device_id=0

  for arg in "${all_args[@]}"; do
    if (( expects_device_id == 1 )); then
      if [[ "${arg}" == "macos" ]]; then
        return 0
      fi
      expects_device_id=0
    fi

    case "${arg}" in
      macos|--device-id=macos|-dmacos)
        return 0
        ;;
      -d|--device-id)
        expects_device_id=1
        ;;
    esac
  done

  return 1
}

maybe_clear_macos_module_cache_conflict() {
  if [[ "$(uname -s)" != "Darwin" ]]; then
    return 0
  fi

  if ! should_sanitize_macos_module_cache; then
    return 0
  fi

  local module_cache_root="${repo_root}/build/macos/ModuleCache.noindex"
  if [[ ! -d "${module_cache_root}" ]]; then
    return 0
  fi

  local cache_dir
  local has_conflict=0

  shopt -s nullglob
  for cache_dir in "${module_cache_root}"/*; do
    [[ -d "${cache_dir}" ]] || continue
    local flutter_modules=("${cache_dir}"/FlutterMacOS-*.pcm)
    if (( ${#flutter_modules[@]} > 1 )); then
      has_conflict=1
      break
    fi
  done
  shopt -u nullglob

  if (( has_conflict == 0 )); then
    return 0
  fi

  echo "SecondLoop: detected conflicting FlutterMacOS module cache; removing ${module_cache_root}" >&2
  rm -rf "${module_cache_root}"
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

maybe_clear_macos_module_cache_conflict

if (( ${#defines[@]} > 0 )); then
  exec dart pub global run fvm:main flutter "$@" "${defines[@]}"
fi

exec dart pub global run fvm:main flutter "$@"
