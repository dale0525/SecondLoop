#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<USAGE
Usage: $0 --parts-dir <dir> --base-name <name> --output-file <file> [--sha256-file <file>]

Assemble split release assets into one archive and optionally verify SHA256.
USAGE
}

parts_dir=''
base_name=''
output_file=''
sha256_file=''

while [[ $# -gt 0 ]]; do
  case "$1" in
    --parts-dir)
      parts_dir="${2:-}"
      shift 2
      ;;
    --base-name)
      base_name="${2:-}"
      shift 2
      ;;
    --output-file)
      output_file="${2:-}"
      shift 2
      ;;
    --sha256-file)
      sha256_file="${2:-}"
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

if [[ -z "$parts_dir" || -z "$base_name" || -z "$output_file" ]]; then
  usage >&2
  exit 2
fi

parts=()
while IFS= read -r part; do
  parts+=("$part")
done < <(ls "$parts_dir/${base_name}.part"[0-9][0-9] 2>/dev/null | sort)

if [[ "${#parts[@]}" -eq 0 ]]; then
  echo "No parts found for base: $base_name" >&2
  exit 1
fi

mkdir -p "$(dirname "$output_file")"
rm -f "$output_file"
for part in "${parts[@]}"; do
  cat "$part" >> "$output_file"
done

sha256_cmd() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | awk '{print $1}'
  else
    shasum -a 256 "$1" | awk '{print $1}'
  fi
}

if [[ -n "$sha256_file" ]]; then
  if [[ ! -f "$sha256_file" ]]; then
    echo "SHA256 file not found: $sha256_file" >&2
    exit 1
  fi
  expected_sha="$(awk '{print $1}' "$sha256_file" | head -n1)"
  actual_sha="$(sha256_cmd "$output_file")"
  if [[ "$expected_sha" != "$actual_sha" ]]; then
    echo "SHA256 mismatch: expected=$expected_sha actual=$actual_sha" >&2
    exit 1
  fi
  echo "SHA256 verified: $actual_sha"
fi

echo "Assembled runtime archive: $output_file"
