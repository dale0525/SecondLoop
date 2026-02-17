#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage:
  prepare_desktop_runtime_payload.sh --output-dir <dir> [options]

Options:
  --output-dir <dir>            Destination runtime payload directory (required)
  --source-dir <dir>            Copy payload from an existing directory first
  --model-source <name>         OCR model source: modelscope-v5|rapidocr-wheel (default: modelscope-v5)
  --modelscope-version <tag>    Modelscope RapidOCR tag for v5 downloads (default: v3.6.0)
  --rapidocr-version <version>  rapidocr_onnxruntime version (default: 1.4.4)
  --onnxruntime-version <ver>   ONNX Runtime version (default: 1.23.0)
  --platform <name>             Runtime platform (linux|macos|windows)
  --arch <name>                 Runtime arch (x64|arm64)
  --whisper-model <name>        Whisper payload model: base|none (default: base)
  --whisper-base-url <url>      Base URL for whisper model downloads
  --no-whisper                  Disable whisper model payload download/check
  --no-download                 Fail instead of downloading when models are missing
  -h, --help                    Show help

Behavior:
  - Ensures required OCR model files + ONNX Runtime dynamic library are present.
  - Downloads OCR models from the selected source when needed.
  - Downloads ONNX Runtime archive for the target platform/arch when needed.
  - Ensures whisper base model payload is included unless --no-whisper is used.
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
    "ch_PP-OCRv5_rec_mobile_infer.onnx"
    "ch_PP-OCRv5_mobile_rec.onnx"
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

normalize_model_source() {
  local raw="$1"
  local lower
  lower="$(printf '%s' "$raw" | tr '[:upper:]' '[:lower:]')"
  case "$lower" in
    modelscope-v5|modelscope_ppocrv5|ppocrv5|v5)
      echo "modelscope-v5"
      ;;
    rapidocr-wheel|rapidocr|wheel)
      echo "rapidocr-wheel"
      ;;
    *)
      return 1
      ;;
  esac
}

normalize_whisper_model() {
  local raw="$1"
  local lower
  lower="$(printf '%s' "$raw" | tr '[:upper:]' '[:lower:]')"
  case "$lower" in
    base)
      echo "base"
      ;;
    none|off|disabled)
      echo "none"
      ;;
    *)
      return 1
      ;;
  esac
}

whisper_model_filename() {
  local model="$1"
  case "$model" in
    base)
      echo "ggml-base.bin"
      ;;
    none)
      echo ""
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

has_whisper_model_payload() {
  local dir="$1"
  local model="$2"
  if [[ "$model" == "none" ]]; then
    return 0
  fi

  local model_file=''
  model_file="$(whisper_model_filename "$model")"
  if [[ -z "$model_file" ]]; then
    return 1
  fi

  local whisper_file="$dir/whisper/$model_file"
  [[ -s "$whisper_file" ]]
}

download_whisper_model_payload() {
  local output_dir="$1"
  local model="$2"
  local whisper_base_url="$3"

  if [[ "$model" == "none" ]]; then
    return 0
  fi

  local model_file=''
  model_file="$(whisper_model_filename "$model")"
  if [[ -z "$model_file" ]]; then
    die "unsupported whisper model: $model"
  fi

  local target_dir="$output_dir/whisper"
  local target_file="$target_dir/$model_file"
  local download_url="${whisper_base_url%/}/$model_file"

  mkdir -p "$target_dir"
  echo "prepare-desktop-runtime-payload: downloading whisper model ${model} from ${download_url}"
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

download_rapidocr_wheel_models() {
  local output_dir="$1"
  local rapidocr_version="$2"
  local temp_dir="$3"
  local pip_log="$temp_dir/pip_download.log"

  echo "prepare-desktop-runtime-payload: downloading rapidocr_onnxruntime==${rapidocr_version}"
  local download_ok=0
  if python3 -m pip download "rapidocr_onnxruntime==${rapidocr_version}" --no-deps -d "$temp_dir" >"$pip_log" 2>&1; then
    cat "$pip_log"
    download_ok=1
  else
    local pyver=''
    for pyver in 312 311 310; do
      if python3 -m pip download "rapidocr_onnxruntime==${rapidocr_version}" --no-deps --python-version "$pyver" -d "$temp_dir" >"$pip_log" 2>&1; then
        echo "prepare-desktop-runtime-payload: retrying rapidocr download with --python-version=${pyver}"
        cat "$pip_log"
        download_ok=1
        break
      fi
    done
  fi
  if [[ "$download_ok" -eq 0 ]]; then
    if [[ -f "$pip_log" ]]; then
      cat "$pip_log" >&2
    fi
    die "unable to download rapidocr_onnxruntime==${rapidocr_version}"
  fi

  local wheel=''
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
}

download_modelscope_v5_models() {
  local output_dir="$1"
  local modelscope_version="$2"

  echo "prepare-desktop-runtime-payload: downloading modelscope PP-OCRv5 models (${modelscope_version})"
  python3 - "$output_dir" "$modelscope_version" <<'PY'
import hashlib
import os
import pathlib
import shutil
import sys
import urllib.request

output_dir = pathlib.Path(sys.argv[1])
modelscope_version = (sys.argv[2] or "v3.6.0").strip() or "v3.6.0"
models_out = output_dir / "models"
models_out.mkdir(parents=True, exist_ok=True)
base = f"https://www.modelscope.cn/models/RapidAI/RapidOCR/resolve/{modelscope_version}"

targets = [
    (
        "ch_PP-OCRv5_mobile_det.onnx",
        f"{base}/onnx/PP-OCRv5/det/ch_PP-OCRv5_mobile_det.onnx",
        "4d97c44a20d30a81aad087d6a396b08f786c4635742afc391f6621f5c6ae78ae",
    ),
    (
        "ch_PP-OCRv5_rec_mobile_infer.onnx",
        f"{base}/onnx/PP-OCRv5/rec/ch_PP-OCRv5_rec_mobile_infer.onnx",
        "5825fc7ebf84ae7a412be049820b4d86d77620f204a041697b0494669b1742c5",
    ),
    (
        "ch_ppocr_mobile_v2.0_cls_infer.onnx",
        f"{base}/onnx/PP-OCRv4/cls/ch_ppocr_mobile_v2.0_cls_infer.onnx",
        "e47acedf663230f8863ff1ab0e64dd2d82b838fceb5957146dab185a89d6215c",
    ),
]

def sha256_file(path: pathlib.Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        while True:
            chunk = handle.read(1024 * 1024)
            if not chunk:
                break
            digest.update(chunk)
    return digest.hexdigest()

downloaded = 0
for file_name, url, expected_sha in targets:
    destination = models_out / file_name
    if destination.is_file():
        if sha256_file(destination).lower() == expected_sha.lower():
            continue

    temp_download = destination.with_name(f".{file_name}.download")
    with urllib.request.urlopen(url, timeout=120) as response, temp_download.open("wb") as output:
        shutil.copyfileobj(response, output)

    actual_sha = sha256_file(temp_download)
    if actual_sha.lower() != expected_sha.lower():
        try:
            temp_download.unlink()
        except FileNotFoundError:
            pass
        raise SystemExit(
            f"sha256 mismatch for {file_name}: expected={expected_sha} actual={actual_sha}"
        )

    temp_download.replace(destination)
    downloaded += 1

print(f"extracted_models={len(targets)}")
print(f"downloaded_models={downloaded}")
PY

  local rec_model="$output_dir/models/ch_PP-OCRv5_rec_mobile_infer.onnx"
  local rec_alias="$output_dir/models/ch_PP-OCRv5_mobile_rec.onnx"
  if [[ -f "$rec_model" && ! -f "$rec_alias" ]]; then
    cp "$rec_model" "$rec_alias"
  fi
}

output_dir=''
source_dir=''
model_source="${DESKTOP_RUNTIME_MODEL_SOURCE:-modelscope-v5}"
modelscope_version="${DESKTOP_RUNTIME_MODELSCOPE_VERSION:-v3.6.0}"
rapidocr_version="${RAPIDOCR_ONNXRUNTIME_VERSION:-1.4.4}"
onnxruntime_version="${ONNXRUNTIME_VERSION:-1.23.0}"
whisper_model="${DESKTOP_RUNTIME_WHISPER_MODEL:-base}"
whisper_base_url="${DESKTOP_RUNTIME_WHISPER_BASE_URL:-https://huggingface.co/ggerganov/whisper.cpp/resolve/main}"
platform="${DESKTOP_RUNTIME_PLATFORM:-}"
arch="${DESKTOP_RUNTIME_ARCH:-}"
allow_download=1
runtime_source='existing_payload'

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
    --model-source)
      model_source="${2:-}"
      shift 2
      ;;
    --modelscope-version)
      modelscope_version="${2:-}"
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
    --whisper-model)
      whisper_model="${2:-}"
      shift 2
      ;;
    --whisper-base-url)
      whisper_base_url="${2:-}"
      shift 2
      ;;
    --no-whisper)
      whisper_model='none'
      shift
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

if ! model_source="$(normalize_model_source "$model_source")"; then
  die "Unsupported model source: $model_source"
fi

if ! whisper_model="$(normalize_whisper_model "$whisper_model")"; then
  die "Unsupported whisper model: $whisper_model"
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
  runtime_source="source_dir:${source_dir}"
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
    case "$model_source" in
      modelscope-v5)
        download_modelscope_v5_models "$output_dir" "$modelscope_version"
        runtime_source="modelscope-v5@${modelscope_version}"
        ;;
      rapidocr-wheel)
        download_rapidocr_wheel_models "$output_dir" "$rapidocr_version" "$temp_dir"
        runtime_source="rapidocr_onnxruntime==${rapidocr_version}"
        ;;
      *)
        die "unsupported model source: ${model_source}"
        ;;
    esac
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

if ! has_whisper_model_payload "$output_dir" "$whisper_model"; then
  if [[ "$allow_download" -eq 0 ]]; then
    die "whisper model payload missing in $output_dir and --no-download is set"
  fi
  download_whisper_model_payload "$output_dir" "$whisper_model" "$whisper_base_url"
fi

if ! has_whisper_model_payload "$output_dir" "$whisper_model"; then
  die "whisper model payload missing after preparation in $output_dir"
fi

if ! has_required_payload "$output_dir" "$platform"; then
  die "payload prepared but required runtime files are still missing in $output_dir"
fi

generated_at_utc="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
cat > "$output_dir/README.runtime.txt" <<EOF
desktop-runtime-payload
generated_at_utc=${generated_at_utc}
source=${runtime_source}
model_source=${model_source}
modelscope_version=${modelscope_version}
rapidocr_version=${rapidocr_version}
platform=${platform}
arch=${arch}
onnxruntime=${onnxruntime_version}
whisper_model=${whisper_model}
whisper_base_url=${whisper_base_url}
EOF

echo "prepare-desktop-runtime-payload: ready -> $output_dir"
