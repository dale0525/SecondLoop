#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<USAGE
Usage: $0 --input-file <file> --output-dir <dir> [--part-size-mb <int>]

Split a large runtime asset into <=N MB parts (default 95MB) and emit checksums.
USAGE
}

input_file=''
output_dir=''
part_size_mb='95'

while [[ $# -gt 0 ]]; do
  case "$1" in
    --input-file)
      input_file="${2:-}"
      shift 2
      ;;
    --output-dir)
      output_dir="${2:-}"
      shift 2
      ;;
    --part-size-mb)
      part_size_mb="${2:-}"
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

if [[ -z "$input_file" || -z "$output_dir" ]]; then
  usage >&2
  exit 2
fi
if [[ ! -f "$input_file" ]]; then
  echo "Input file not found: $input_file" >&2
  exit 1
fi
if ! [[ "$part_size_mb" =~ ^[0-9]+$ ]]; then
  echo "part-size-mb must be an integer" >&2
  exit 2
fi

mkdir -p "$output_dir"
base_name="$(basename "$input_file")"
full_sha_file="$output_dir/${base_name}.sha256"
parts_list_file="$output_dir/${base_name}.parts.txt"
parts_sha_file="$output_dir/${base_name}.parts.sha256"

rm -f "$output_dir/${base_name}.part"[0-9][0-9] "$full_sha_file" "$parts_list_file" "$parts_sha_file"

split -b "${part_size_mb}m" -d -a 2 "$input_file" "$output_dir/${base_name}.part"

sha256_cmd() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | awk '{print $1}'
  else
    shasum -a 256 "$1" | awk '{print $1}'
  fi
}

full_sha="$(sha256_cmd "$input_file")"
printf '%s  %s\n' "$full_sha" "$base_name" > "$full_sha_file"

: > "$parts_list_file"
: > "$parts_sha_file"
for part in "$output_dir/${base_name}.part"[0-9][0-9]; do
  [[ -f "$part" ]] || continue
  part_base="$(basename "$part")"
  part_sha="$(sha256_cmd "$part")"
  printf '%s\n' "$part_base" >> "$parts_list_file"
  printf '%s  %s\n' "$part_sha" "$part_base" >> "$parts_sha_file"
done

part_count="$(wc -l < "$parts_list_file" | tr -d ' ')"
echo "Split complete: $part_count parts"
