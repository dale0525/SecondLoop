#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<USAGE
Usage: $0 --platform <platform> --arch <arch> --input-dir <dir> --output-dir <dir> [--version <version>]

Build a platform runtime archive and emit SHA256 metadata.
USAGE
}

platform=''
arch=''
input_dir=''
output_dir=''
version=''

while [[ $# -gt 0 ]]; do
  case "$1" in
    --platform)
      platform="${2:-}"
      shift 2
      ;;
    --arch)
      arch="${2:-}"
      shift 2
      ;;
    --input-dir)
      input_dir="${2:-}"
      shift 2
      ;;
    --output-dir)
      output_dir="${2:-}"
      shift 2
      ;;
    --version)
      version="${2:-}"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

if [[ -z "$platform" || -z "$arch" || -z "$input_dir" || -z "$output_dir" ]]; then
  usage >&2
  exit 2
fi

if [[ ! -d "$input_dir" ]]; then
  echo "Input directory does not exist: $input_dir" >&2
  exit 1
fi

python3 - "$input_dir" "$platform" <<'PY'
import pathlib
import sys


def fail(message: str) -> None:
    print(f"build-desktop-runtime: {message}", file=sys.stderr)
    raise SystemExit(1)


root = pathlib.Path(sys.argv[1]).resolve()
platform = sys.argv[2].strip().lower()
if not root.is_dir():
    fail(f"input directory does not exist: {root}")

all_files = {
    path.name
    for path in root.rglob("*")
    if path.is_file()
}

det_aliases = {
    "ch_PP-OCRv5_mobile_det.onnx",
    "ch_PP-OCRv4_det_infer.onnx",
    "ch_PP-OCRv3_det_infer.onnx",
}
cls_aliases = {
    "ch_ppocr_mobile_v2.0_cls_infer.onnx",
}
rec_aliases = {
    "ch_PP-OCRv5_rec_mobile_infer.onnx",
    "ch_PP-OCRv5_mobile_rec.onnx",
    "ch_PP-OCRv4_rec_infer.onnx",
    "ch_PP-OCRv3_rec_infer.onnx",
    "latin_PP-OCRv3_rec_infer.onnx",
    "arabic_PP-OCRv3_rec_infer.onnx",
    "cyrillic_PP-OCRv3_rec_infer.onnx",
    "devanagari_PP-OCRv3_rec_infer.onnx",
    "japan_PP-OCRv3_rec_infer.onnx",
    "korean_PP-OCRv3_rec_infer.onnx",
    "chinese_cht_PP-OCRv3_rec_infer.onnx",
}

if platform == "windows":
    has_onnxruntime = any(
        name.lower().startswith("onnxruntime") and name.lower().endswith(".dll")
        for name in all_files
    )
elif platform == "macos":
    has_onnxruntime = any(
        name.startswith("libonnxruntime") and ".dylib" in name
        for name in all_files
    )
elif platform == "linux":
    has_onnxruntime = any(
        name.startswith("libonnxruntime") and ".so" in name
        for name in all_files
    )
else:
    fail(f"unsupported platform: {platform}")

missing_sections = []
if not (all_files & det_aliases):
    missing_sections.append("DET model")
if not (all_files & cls_aliases):
    missing_sections.append("CLS model")
if not (all_files & rec_aliases):
    missing_sections.append("REC model")
if not has_onnxruntime:
    missing_sections.append("ONNX Runtime dynamic library")

if missing_sections:
    fail(
        "runtime payload missing required files in "
        f"{root}: {', '.join(missing_sections)}"
    )
PY

if [[ -z "$version" ]]; then
  version="$(date -u +%Y%m%d%H%M%S)"
fi

mkdir -p "$output_dir"
archive_name="desktop-runtime-${platform}-${arch}-${version}.tar.gz"
archive_path="$output_dir/$archive_name"
manifest_path="$output_dir/${archive_name}.manifest.json"
sha_path="$output_dir/${archive_name}.sha256"

rm -f "$archive_path" "$manifest_path" "$sha_path"
tar -C "$input_dir" -czf "$archive_path" .

sha256_cmd() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | awk '{print $1}'
  else
    shasum -a 256 "$1" | awk '{print $1}'
  fi
}

archive_sha="$(sha256_cmd "$archive_path")"
archive_size="$(wc -c < "$archive_path" | tr -d ' ')"

printf '%s  %s\n' "$archive_sha" "$archive_name" > "$sha_path"

cat > "$manifest_path" <<JSON
{
  "runtime": "desktop_media",
  "platform": "$platform",
  "arch": "$arch",
  "version": "$version",
  "archive": "$archive_name",
  "bytes": $archive_size,
  "sha256": "$archive_sha"
}
JSON

echo "Built runtime archive: $archive_path"
echo "SHA256: $archive_sha"
