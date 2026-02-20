#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
backup_root="${repo_root}/.tool/cache/android-release-apk-assets/$$"

assets_to_prune=(
  "assets/ocr/desktop_runtime"
  "assets/bin/ffmpeg/macos"
  "assets/bin/ffmpeg/linux"
  "assets/bin/ffmpeg/windows"
)

placeholder_files=(
  "assets/icon/tray_icon.png"
  "assets/icon/tray_icon.ico"
)

placeholder_png_base64='iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+X2ioAAAAASUVORK5CYII='
placeholder_ico_base64='AAABAAEAEBAAAAAAIABWAAAAFgAAAIlQTkcNChoKAAAADUlIRFIAAAAQAAAAEAgGAAAAH/P/YQAAAB1JREFUeJxj/M/A8J+BAsBEieZRA0YNGDVgMBkAAFhtAh71zM+iAAAAAElFTkSuQmCC'

moved_paths=()

restore_assets() {
  local exit_code="$?"

  for (( index=${#moved_paths[@]}-1; index>=0; index-- )); do
    local relative_path="${moved_paths[index]}"
    local source_path="${repo_root}/${relative_path}"
    local backup_path="${backup_root}/${relative_path}"

    rm -rf "${source_path}"
    if [[ -e "${backup_path}" || -L "${backup_path}" ]]; then
      mkdir -p "$(dirname "${source_path}")"
      mv "${backup_path}" "${source_path}"
    fi
  done

  rm -rf "${backup_root}"
  exit "${exit_code}"
}

trap restore_assets EXIT

mkdir -p "${backup_root}"

for relative_path in "${assets_to_prune[@]}"; do
  source_path="${repo_root}/${relative_path}"
  backup_path="${backup_root}/${relative_path}"

  if [[ ! -e "${source_path}" && ! -L "${source_path}" ]]; then
    continue
  fi

  mkdir -p "$(dirname "${backup_path}")"
  mv "${source_path}" "${backup_path}"

  mkdir -p "${source_path}"
  touch "${source_path}/.gitkeep"

  if [[ "${relative_path}" == "assets/ocr/desktop_runtime" ]]; then
    mkdir -p "${source_path}/models" "${source_path}/onnxruntime" "${source_path}/whisper"
    touch "${source_path}/models/.gitkeep"
    touch "${source_path}/onnxruntime/.gitkeep"
    touch "${source_path}/whisper/.gitkeep"
  fi

  moved_paths+=("${relative_path}")
  echo "android-release-apk: pruned ${relative_path}"
done

for relative_path in "${placeholder_files[@]}"; do
  source_path="${repo_root}/${relative_path}"
  backup_path="${backup_root}/${relative_path}"

  if [[ ! -e "${source_path}" && ! -L "${source_path}" ]]; then
    continue
  fi

  mkdir -p "$(dirname "${backup_path}")"
  mv "${source_path}" "${backup_path}"

  mkdir -p "$(dirname "${source_path}")"

  placeholder_base64="${placeholder_png_base64}"
  if [[ "${relative_path}" == *.ico ]]; then
    placeholder_base64="${placeholder_ico_base64}"
  fi

  printf '%s' "${placeholder_base64}" | base64 --decode > "${source_path}"

  moved_paths+=("${relative_path}")
  echo "android-release-apk: replaced ${relative_path} with tiny placeholder"
done

bash "${repo_root}/scripts/flutter_with_defines.sh" \
  build apk --release --target-platform android-arm,android-arm64 "$@"
