#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage:
  prepare_desktop_runtime_payload.sh --output-dir <dir> [options]

Options:
  --output-dir <dir>            Destination runtime payload directory (required)
  --source-dir <dir>            Copy payload from an existing directory first
  --rapidocr-version <version>  rapidocr_onnxruntime version (default: 1.2.3)
  --no-download                 Fail instead of downloading when models are missing
  -h, --help                    Show help

Behavior:
  - If output dir already has required OCR model files, keeps existing payload.
  - Otherwise downloads rapidocr_onnxruntime wheel and extracts model files into
    "<output-dir>/models/".
USAGE
}

die() {
  echo "prepare-desktop-runtime-payload: $*" >&2
  exit 1
}

require_cmd() {
  local cmd="$1"
  command -v "${cmd}" >/dev/null 2>&1 || die "Missing required command: ${cmd}"
}

has_any_model_alias() {
  local dir="$1"
  shift
  local alias
  for alias in "$@"; do
    if find "$dir" -type f -name "$alias" -print -quit 2>/dev/null | grep -q .; then
      return 0
    fi
  done
  return 1
}

has_required_models() {
  local dir="$1"
  if [[ ! -d "$dir" ]]; then
    return 1
  fi

  local det_aliases=(
    "ch_PP-OCRv5_mobile_det.onnx"
    "ch_PP-OCRv4_det_infer.onnx"
    "ch_PP-OCRv3_det_infer.onnx"
  )
  local cls_aliases=(
    "ch_ppocr_mobile_v2.0_cls_infer.onnx"
  )
  local rec_aliases=(
    "ch_PP-OCRv4_rec_infer.onnx"
    "ch_PP-OCRv3_rec_infer.onnx"
    "latin_PP-OCRv3_rec_infer.onnx"
    "arabic_PP-OCRv3_rec_infer.onnx"
    "cyrillic_PP-OCRv3_rec_infer.onnx"
    "devanagari_PP-OCRv3_rec_infer.onnx"
    "japan_PP-OCRv3_rec_infer.onnx"
    "korean_PP-OCRv3_rec_infer.onnx"
    "chinese_cht_PP-OCRv3_rec_infer.onnx"
  )

  has_any_model_alias "$dir" "${det_aliases[@]}" &&
    has_any_model_alias "$dir" "${cls_aliases[@]}" &&
    has_any_model_alias "$dir" "${rec_aliases[@]}"
}

output_dir=''
source_dir=''
rapidocr_version="${RAPIDOCR_ONNXRUNTIME_VERSION:-1.2.3}"
allow_download=1

while [[ $# -gt 0 ]]; do
  case "$1" in
    --output-dir)
      output_dir="${2:-}"
      shift 2
      ;;
    --source-dir)
      source_dir="${2:-}"
      shift 2
      ;;
    --rapidocr-version)
      rapidocr_version="${2:-}"
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

require_cmd python3

mkdir -p "$output_dir"

if [[ -n "$source_dir" ]]; then
  if [[ ! -d "$source_dir" ]]; then
    die "source dir not found: $source_dir"
  fi
  rm -rf "$output_dir"
  mkdir -p "$output_dir"
  cp -R "$source_dir"/. "$output_dir"/
fi

if has_required_models "$output_dir"; then
  echo "prepare-desktop-runtime-payload: using existing payload in $output_dir"
else
  if [[ "$allow_download" -eq 0 ]]; then
    die "required OCR model files missing in $output_dir and --no-download is set"
  fi

  temp_dir="$(mktemp -d)"
  trap 'rm -rf "$temp_dir"' EXIT

  echo "prepare-desktop-runtime-payload: downloading rapidocr_onnxruntime==${rapidocr_version}"
  python3 -m pip download "rapidocr_onnxruntime==${rapidocr_version}" --no-deps -d "$temp_dir"

  wheel="$(ls "$temp_dir"/rapidocr_onnxruntime-*.whl 2>/dev/null | head -n 1 || true)"
  if [[ -z "$wheel" ]]; then
    die "unable to locate downloaded wheel in $temp_dir"
  fi

  python3 - "$wheel" "$output_dir" <<'PY'
import os
import sys
import zipfile

wheel_path = sys.argv[1]
output_dir = sys.argv[2]
models_prefix = "rapidocr_onnxruntime/models/"
models_out = os.path.join(output_dir, "models")
os.makedirs(models_out, exist_ok=True)

count = 0
with zipfile.ZipFile(wheel_path) as zf:
    for name in zf.namelist():
        if not name.startswith(models_prefix) or name.endswith("/"):
            continue
        relative = name[len(models_prefix):]
        if not relative:
            continue
        out_path = os.path.join(models_out, relative)
        os.makedirs(os.path.dirname(out_path), exist_ok=True)
        with zf.open(name) as src, open(out_path, "wb") as dst:
            dst.write(src.read())
        count += 1

if count == 0:
    raise SystemExit("no model files extracted from wheel")
print(f"extracted_models={count}")
PY
fi

if ! has_required_models "$output_dir"; then
  die "payload prepared but required OCR model files are still missing in $output_dir"
fi

generated_at_utc="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
cat > "$output_dir/README.runtime.txt" <<EOF
desktop-runtime-payload
generated_at_utc=${generated_at_utc}
source=${source_dir:-rapidocr_onnxruntime==${rapidocr_version}}
EOF

echo "prepare-desktop-runtime-payload: ready -> $output_dir"
