#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage:
  prepare_mobile_runtime_payload.sh --output-dir <dir> [options]

Options:
  --output-dir <dir>        Destination mobile runtime payload directory (required)
  --whisper-models <list>   Comma-separated whisper models (default: tiny)
  --whisper-base-url <url>  Base URL for whisper model downloads
  --no-download             Fail when files are missing instead of downloading
  -h, --help                Show help

Behavior:
  - Ensures requested whisper model files exist under <output-dir>/whisper.
  - Downloads missing model files from <whisper-base-url> unless --no-download.
  - Writes README.mobile_runtime.txt metadata for release packaging.
USAGE
}

die() {
  echo "prepare-mobile-runtime-payload: $*" >&2
  exit 1
}

require_cmd() {
  local cmd="$1"
  command -v "${cmd}" >/dev/null 2>&1 || die "Missing required command: ${cmd}"
}

trim_spaces() {
  local value="$1"
  value="${value#"${value%%[![:space:]]*}"}"
  value="${value%"${value##*[![:space:]]}"}"
  printf '%s' "$value"
}

normalize_whisper_model() {
  local raw="$1"
  local lower
  lower="$(printf '%s' "$raw" | tr '[:upper:]' '[:lower:]')"
  case "$lower" in
    tiny|base|small|medium|large-v3|large-v3-turbo)
      echo "$lower"
      ;;
    *)
      return 1
      ;;
  esac
}

whisper_model_filename() {
  local model="$1"
  case "$model" in
    tiny)
      echo "ggml-tiny.bin"
      ;;
    base)
      echo "ggml-base.bin"
      ;;
    small)
      echo "ggml-small.bin"
      ;;
    medium)
      echo "ggml-medium.bin"
      ;;
    large-v3)
      echo "ggml-large-v3.bin"
      ;;
    large-v3-turbo)
      echo "ggml-large-v3-turbo.bin"
      ;;
    *)
      return 1
      ;;
  esac
}

contains_model() {
  local needle="$1"
  shift

  local model
  for model in "$@"; do
    if [[ "$model" == "$needle" ]]; then
      return 0
    fi
  done
  return 1
}

has_whisper_model_payload() {
  local output_dir="$1"
  local model="$2"

  local model_file=''
  model_file="$(whisper_model_filename "$model")"
  [[ -s "$output_dir/whisper/$model_file" ]]
}

download_whisper_model_payload() {
  local output_dir="$1"
  local model="$2"
  local whisper_base_url="$3"

  local model_file=''
  model_file="$(whisper_model_filename "$model")"

  local target_dir="$output_dir/whisper"
  local target_file="$target_dir/$model_file"
  local download_url="${whisper_base_url%/}/$model_file"

  mkdir -p "$target_dir"
  echo "prepare-mobile-runtime-payload: downloading whisper model ${model} from ${download_url}"
  python3 - "$download_url" "$target_file" <<'PY_DOWNLOAD_WHISPER'
import pathlib
import shutil
import sys
import urllib.request

url = sys.argv[1]
dest = pathlib.Path(sys.argv[2])
temp = dest.with_suffix(dest.suffix + '.download')
dest.parent.mkdir(parents=True, exist_ok=True)

with urllib.request.urlopen(url, timeout=120) as response, temp.open('wb') as output:
    shutil.copyfileobj(response, output)

if temp.stat().st_size <= 0:
    temp.unlink(missing_ok=True)
    raise SystemExit(f'downloaded whisper model is empty: {url}')

temp.replace(dest)
print(f'whisper_model_bytes={dest.stat().st_size}')
PY_DOWNLOAD_WHISPER
}

output_dir=''
whisper_models_input="${MOBILE_RUNTIME_WHISPER_MODELS:-tiny}"
whisper_base_url="${MOBILE_RUNTIME_WHISPER_BASE_URL:-https://huggingface.co/ggerganov/whisper.cpp/resolve/main}"
allow_download=1

while [[ $# -gt 0 ]]; do
  case "$1" in
    --output-dir)
      output_dir="${2:-}"
      shift 2
      ;;
    --whisper-models)
      whisper_models_input="${2:-}"
      shift 2
      ;;
    --whisper-base-url)
      whisper_base_url="${2:-}"
      shift 2
      ;;
    --no-download)
      allow_download=0
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      die "Unknown argument: $1"
      ;;
  esac
done

if [[ -z "$output_dir" ]]; then
  usage >&2
  exit 2
fi

if [[ -z "$whisper_models_input" ]]; then
  die "--whisper-models cannot be empty"
fi

require_cmd python3

mkdir -p "$output_dir/whisper"

IFS=',' read -r -a raw_models <<< "$whisper_models_input"
declare -a models=()

for raw_model in "${raw_models[@]}"; do
  trimmed="$(trim_spaces "$raw_model")"
  if [[ -z "$trimmed" ]]; then
    continue
  fi

  if ! normalized="$(normalize_whisper_model "$trimmed")"; then
    die "Unsupported whisper model: $trimmed"
  fi

  if ! contains_model "$normalized" "${models[@]}"; then
    models+=("$normalized")
  fi
done

if [[ ${#models[@]} -eq 0 ]]; then
  die "No valid whisper models resolved from --whisper-models"
fi

for model in "${models[@]}"; do
  if has_whisper_model_payload "$output_dir" "$model"; then
    echo "prepare-mobile-runtime-payload: using existing whisper model ${model}"
    continue
  fi

  if [[ "$allow_download" -eq 0 ]]; then
    die "whisper model payload missing in $output_dir and --no-download is set"
  fi

  download_whisper_model_payload "$output_dir" "$model" "$whisper_base_url"

done

for model in "${models[@]}"; do
  if ! has_whisper_model_payload "$output_dir" "$model"; then
    die "whisper model payload missing after preparation: $model"
  fi
done

generated_at_utc="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
models_csv="$(IFS=,; echo "${models[*]}")"
cat > "$output_dir/README.mobile_runtime.txt" <<README
mobile-runtime-payload
generated_at_utc=${generated_at_utc}
whisper_models=${models_csv}
whisper_base_url=${whisper_base_url}
README

echo "prepare-mobile-runtime-payload: ready -> $output_dir"
