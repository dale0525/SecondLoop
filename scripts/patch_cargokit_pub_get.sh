#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

make_temp_file() {
  mktemp "${TMPDIR:-/tmp}/secondloop_cargokit_patch.XXXXXX"
}

insert_retry_block() {
  local source="$1"
  local target="$2"

  awk '
    function print_retry_block() {
      print "clear_pub_advisories_cache() {"
      print "  local cache_root=\"${PUB_CACHE:-}\""
      print "  if [[ -z \"$cache_root\" && -n \"${HOME:-}\" ]]; then"
      print "    cache_root=\"$HOME/.pub-cache\""
      print "  fi"
      print "  if [[ -z \"$cache_root\" || ! -d \"$cache_root/hosted\" ]]; then"
      print "    return 0"
      print "  fi"
      print "  find \"$cache_root/hosted\" -path \"*/.cache/*-advisories.json\" -type f -delete 2>/dev/null || true"
      print "}"
      print ""
      print "run_pub_get_with_retry() {"
      print "  if \"$DART\" pub get --no-precompile; then"
      print "    return 0"
      print "  fi"
      print ""
      print "  echo \"SecondLoop: dart pub get failed; clearing hosted pub advisories cache and retrying once.\" >&2"
      print "  clear_pub_advisories_cache"
      print "  \"$DART\" pub get --no-precompile"
      print "}"
    }
    {
      print
      if ($0 ~ /^[[:space:]]*DART=/) {
        seen_dart = 1
      }
      if (!inserted && seen_dart && $0 == "fi") {
        print ""
        print_retry_block()
        inserted = 1
      }
    }
    END {
      if (!inserted) {
        exit 42
      }
    }
  ' "$source" > "$target"
}

rewrite_pub_get_calls() {
  local source="$1"
  local target="$2"

  awk '
    {
      line = $0
      if (line == "run_pub_get_with_retry() {") {
        in_retry = 1
        print line
        next
      }

      if (in_retry) {
        sub(/if run_pub_get_with_retry; then/, "if \"$DART\" pub get --no-precompile; then", line)
        sub(/run_pub_get_with_retry/, "\"$DART\" pub get --no-precompile", line)
        print line
        if (line == "}") {
          in_retry = 0
        }
        next
      }

      gsub(/"\$DART" pub get --no-precompile/, "run_pub_get_with_retry", line)
      print line
    }
  ' "$source" > "$target"
}

patch_run_build_tool() {
  local script="$1"

  if [[ ! -f "$script" ]]; then
    return 0
  fi

  if ! grep -q '"\$DART" pub get --no-precompile' "$script" \
    && ! grep -q 'if run_pub_get_with_retry; then' "$script"; then
    return 0
  fi

  local inserted_file
  local patched_file
  inserted_file="$(make_temp_file)"
  patched_file="$(make_temp_file)"

  if grep -q 'run_pub_get_with_retry()' "$script"; then
    cp "$script" "$inserted_file"
  elif ! insert_retry_block "$script" "$inserted_file"; then
    rm -f "$inserted_file" "$patched_file"
    echo "SecondLoop: unable to patch Cargokit pub get retry in ${script}" >&2
    return 0
  fi

  rewrite_pub_get_calls "$inserted_file" "$patched_file"

  if ! cmp -s "$script" "$patched_file"; then
    mv "$patched_file" "$script"
    chmod +x "$script" 2>/dev/null || true
    echo "SecondLoop: patched Cargokit pub get retry in ${script}" >&2
  else
    rm -f "$patched_file"
  fi

  rm -f "$inserted_file"
}

patch_build_pod() {
  local script="$1"

  if [[ ! -f "$script" ]]; then
    return 0
  fi

  if ! grep -qx 'env' "$script"; then
    return 0
  fi

  local patched_file
  patched_file="$(make_temp_file)"
  awk '$0 != "env" { print }' "$script" > "$patched_file"

  if ! cmp -s "$script" "$patched_file"; then
    mv "$patched_file" "$script"
    chmod +x "$script" 2>/dev/null || true
    echo "SecondLoop: removed raw Cargokit env dump in ${script}" >&2
  else
    rm -f "$patched_file"
  fi
}

patch_file() {
  local file="$1"

  case "$file" in
    */cargokit/run_build_tool.sh) patch_run_build_tool "$file" ;;
    */cargokit/build_pod.sh) patch_build_pod "$file" ;;
  esac
}

patch_root() {
  local root="$1"
  local file

  if [[ -f "$root" ]]; then
    patch_file "$root"
    return 0
  fi

  if [[ ! -d "$root" ]]; then
    return 0
  fi

  while IFS= read -r -d '' file; do
    patch_file "$file"
  done < <(
    find -L "$root" \
      \( -path '*/cargokit/run_build_tool.sh' -o -path '*/cargokit/build_pod.sh' \) \
      -type f -print0 2>/dev/null || true
  )
}

main() {
  local -a roots=()
  if (( $# > 0 )); then
    roots=("$@")
  else
    roots+=("${repo_root}/rust_builder")
    roots+=("${repo_root}/macos/Flutter/ephemeral/.symlinks/plugins")
    if [[ -n "${PUB_CACHE:-}" ]]; then
      roots+=("${PUB_CACHE}/hosted/pub.dev")
    fi
    roots+=("${repo_root}/.tool/pub-cache/hosted/pub.dev")
  fi

  local root
  for root in "${roots[@]}"; do
    patch_root "$root"
  done
}

main "$@"
