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
  --onnxruntime-version <ver>   ONNX Runtime version (default: 1.23.0)
  --platform <name>             Runtime platform (linux|macos|windows)
  --arch <name>                 Runtime arch (x64|arm64)
  --no-download                 Fail instead of downloading when models are missing
  -h, --help                    Show help

Behavior:
  - Ensures required OCR model files + ONNX Runtime dynamic library are present.
  - Downloads rapidocr_onnxruntime wheel for model files when needed.
  - Downloads ONNX Runtime archive for the target platform/arch when needed.
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

normalize_platform() {
  local raw="$1"
  local lower
  lower="$(printf '%s' "$raw" | tr '[:upper:]' '[:lower:]')"
  case "$lower" in
    linux|ubuntu)
      echo "linux"
      ;;
    macos|mac|darwin|osx)
      echo "macos"
      ;;
    windows|win)
      echo "windows"
      ;;
    *)
      return 1
      ;;
  esac
}

normalize_arch() {
  local raw="$1"
  local lower
  lower="$(printf '%s' "$raw" | tr '[:upper:]' '[:lower:]')"
  case "$lower" in
    x64|amd64|x86_64)
      echo "x64"
      ;;
    arm64|aarch64)
      echo "arm64"
      ;;
    *)
      return 1
      ;;
  esac
}

detect_host_platform() {
  local os
  os="$(uname -s 2>/dev/null || echo unknown)"
  local lower
  lower="$(printf '%s' "$os" | tr '[:upper:]' '[:lower:]')"
  case "$lower" in
    linux*)
      echo "linux"
      ;;
    darwin*)
      echo "macos"
      ;;
    msys*|mingw*|cygwin*)
      echo "windows"
      ;;
    *)
      die "Unsupported host platform for auto-detection: ${os}"
      ;;
  esac
}

detect_host_arch() {
  local arch
  arch="$(uname -m 2>/dev/null || echo unknown)"
  local lower
  lower="$(printf '%s' "$arch" | tr '[:upper:]' '[:lower:]')"
  case "$lower" in
    x86_64|amd64)
      echo "x64"
      ;;
    arm64|aarch64)
      echo "arm64"
      ;;
    *)
      die "Unsupported host arch for auto-detection: ${arch}"
      ;;
  esac
}

onnxruntime_main_lib_name() {
  local platform="$1"
  case "$platform" in
    linux)
      echo "libonnxruntime.so"
      ;;
    macos)
      echo "libonnxruntime.dylib"
      ;;
    windows)
      echo "onnxruntime.dll"
      ;;
    *)
      return 1
      ;;
  esac
}

has_onnxruntime_lib() {
  local dir="$1"
  local platform="$2"
  local runtime_dir="$dir/onnxruntime"
  if [[ ! -d "$runtime_dir" ]]; then
    return 1
  fi

  local main_lib
  main_lib="$(onnxruntime_main_lib_name "$platform")"
  if [[ -f "$runtime_dir/$main_lib" ]]; then
    return 0
  fi

  case "$platform" in
    linux)
      find "$runtime_dir" -type f -name 'libonnxruntime.so*' -print -quit | grep -q .
      ;;
    macos)
      find "$runtime_dir" -type f -name 'libonnxruntime*.dylib*' -print -quit | grep -q .
      ;;
    windows)
      find "$runtime_dir" -type f -iname 'onnxruntime*.dll' -print -quit | grep -q .
      ;;
    *)
      return 1
      ;;
  esac
}

onnxruntime_archive_name() {
  local platform="$1"
  local arch="$2"
  local version="$3"

  case "$platform/$arch" in
    linux/x64)
      echo "onnxruntime-linux-x64-${version}.tgz"
      ;;
    linux/arm64)
      echo "onnxruntime-linux-aarch64-${version}.tgz"
      ;;
    macos/x64)
      echo "onnxruntime-osx-x86_64-${version}.tgz"
      ;;
    macos/arm64)
      echo "onnxruntime-osx-arm64-${version}.tgz"
      ;;
    windows/x64)
      echo "onnxruntime-win-x64-${version}.zip"
      ;;
    *)
      die "Unsupported ONNX Runtime target: ${platform}/${arch}"
      ;;
  esac
}

ensure_onnxruntime_main_lib() {
  local runtime_dir="$1"
  local platform="$2"
  local main_lib
  main_lib="$(onnxruntime_main_lib_name "$platform")"
  local main_path="$runtime_dir/$main_lib"

  if [[ -f "$main_path" ]]; then
    return 0
  fi

  local candidate=''
  case "$platform" in
    linux)
      candidate="$(find "$runtime_dir" -type f -name 'libonnxruntime.so*' ! -name '*providers_shared*' -print | sort | head -n1 || true)"
      ;;
    macos)
      candidate="$(find "$runtime_dir" -type f -name 'libonnxruntime*.dylib*' ! -name '*providers_shared*' -print | sort | head -n1 || true)"
      ;;
    windows)
      candidate="$(find "$runtime_dir" -type f -iname 'onnxruntime*.dll' ! -iname 'onnxruntime_providers_shared.dll' -print | sort | head -n1 || true)"
      ;;
  esac

  if [[ -n "$candidate" ]]; then
    cp "$candidate" "$main_path"
  fi

  [[ -f "$main_path" ]]
}

has_required_payload() {
  local dir="$1"
  local platform="$2"
  has_required_models "$dir" && has_onnxruntime_lib "$dir" "$platform"
}

output_dir=''
source_dir=''
rapidocr_version="${RAPIDOCR_ONNXRUNTIME_VERSION:-1.2.3}"
onnxruntime_version="${ONNXRUNTIME_VERSION:-1.23.0}"
platform="${DESKTOP_RUNTIME_PLATFORM:-}"
arch="${DESKTOP_RUNTIME_ARCH:-}"
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
    --onnxruntime-version)
      onnxruntime_version="${2:-}"
      shift 2
      ;;
    --platform)
      platform="${2:-}"
      shift 2
      ;;
    --arch)
      arch="${2:-}"
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

if [[ -z "$platform" ]]; then
  platform="$(detect_host_platform)"
fi
if ! platform="$(normalize_platform "$platform")"; then
  die "Unsupported platform: $platform"
fi

if [[ -z "$arch" ]]; then
  arch="$(detect_host_arch)"
fi
if ! arch="$(normalize_arch "$arch")"; then
  die "Unsupported arch: $arch"
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

if has_required_payload "$output_dir" "$platform"; then
  echo "prepare-desktop-runtime-payload: using existing payload in $output_dir"
else
  if [[ "$allow_download" -eq 0 ]]; then
    die "required runtime payload missing in $output_dir and --no-download is set"
  fi

  temp_dir="$(mktemp -d)"
  trap 'rm -rf "$temp_dir"' EXIT

  if ! has_required_models "$output_dir"; then
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

  if ! has_onnxruntime_lib "$output_dir" "$platform"; then
    local_archive="$(onnxruntime_archive_name "$platform" "$arch" "$onnxruntime_version")"
    archive_url="https://github.com/microsoft/onnxruntime/releases/download/v${onnxruntime_version}/${local_archive}"
    archive_path="$temp_dir/$local_archive"
    runtime_dir="$output_dir/onnxruntime"

    echo "prepare-desktop-runtime-payload: downloading onnxruntime ${onnxruntime_version} (${platform}/${arch})"
    python3 - "$archive_url" "$archive_path" <<'PY'
import pathlib
import shutil
import sys
import urllib.request

url = sys.argv[1]
dest = pathlib.Path(sys.argv[2])
dest.parent.mkdir(parents=True, exist_ok=True)

with urllib.request.urlopen(url) as resp, open(dest, "wb") as out:
    shutil.copyfileobj(resp, out)
PY

    python3 - "$archive_path" "$runtime_dir" "$platform" <<'PY'
import os
import sys
import tarfile
import zipfile

archive = sys.argv[1]
runtime_dir = sys.argv[2]
platform = sys.argv[3]

os.makedirs(runtime_dir, exist_ok=True)

def extract_file(readable, destination):
    os.makedirs(os.path.dirname(destination), exist_ok=True)
    with open(destination, "wb") as out:
        out.write(readable.read())

count = 0
if archive.endswith(".zip"):
    with zipfile.ZipFile(archive) as zf:
        for name in zf.namelist():
            if name.endswith("/") or "/lib/" not in name:
                continue
            base = os.path.basename(name)
            if not base:
                continue
            if not base.lower().endswith(".dll"):
                continue
            with zf.open(name) as src:
                extract_file(src, os.path.join(runtime_dir, base))
                count += 1
else:
    with tarfile.open(archive, "r:gz") as tf:
        for member in tf.getmembers():
            if not member.isfile():
                continue
            name = member.name
            if "/lib/" not in name:
                continue
            base = os.path.basename(name)
            if not base:
                continue
            lower = base.lower()
            if not lower.startswith("libonnxruntime"):
                continue
            if ".dylib" not in lower and ".so" not in lower:
                continue
            src = tf.extractfile(member)
            if src is None:
                continue
            with src:
                extract_file(src, os.path.join(runtime_dir, base))
                count += 1

if count == 0:
    raise SystemExit(f"no onnxruntime libraries extracted for platform={platform}")
print(f"extracted_onnxruntime_libs={count}")
PY

    if ! ensure_onnxruntime_main_lib "$runtime_dir" "$platform"; then
      die "main onnxruntime library missing in $runtime_dir for ${platform}/${arch}"
    fi
  fi
fi

if ! has_required_payload "$output_dir" "$platform"; then
  die "payload prepared but required runtime files are still missing in $output_dir"
fi

generated_at_utc="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
cat > "$output_dir/README.runtime.txt" <<EOF
desktop-runtime-payload
generated_at_utc=${generated_at_utc}
source=${source_dir:-rapidocr_onnxruntime==${rapidocr_version}}
platform=${platform}
arch=${arch}
onnxruntime=${onnxruntime_version}
EOF

echo "prepare-desktop-runtime-payload: ready -> $output_dir"
