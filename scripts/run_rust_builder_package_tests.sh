#!/usr/bin/env bash
set -euo pipefail

repo_root="$(git rev-parse --show-toplevel 2>/dev/null || true)"
if [[ -z "${repo_root}" ]]; then
  exit 0
fi

cd "${repo_root}"
source "${repo_root}/scripts/pre_commit_common.sh"

package_root="${repo_root}/rust_builder/cargokit/build_tool"
[[ -f "${package_root}/pubspec.yaml" ]] || die "Missing rust_builder build_tool package at ${package_root}."

resolve_dart_bin >/dev/null || die "Missing 'dart'. Install Flutter (recommended: \`pixi run setup-flutter\`) or add Dart to PATH."

(
  cd "${package_root}"
  run_with_periodic_status "rust builder pub get" run_dart_tool pub get
  run_with_periodic_status "rust builder tests" run_dart_tool test
)
