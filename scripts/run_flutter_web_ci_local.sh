#!/usr/bin/env bash
set -euo pipefail

repo_root="$(git rev-parse --show-toplevel 2>/dev/null || true)"
if [[ -z "${repo_root}" ]]; then
  exit 0
fi

cd "${repo_root}"
source "${repo_root}/scripts/pre_commit_common.sh"

dart_bin="$(resolve_dart_bin)" || die "Missing 'dart'. Install Flutter (recommended: \`pixi run setup-flutter\`) or add Dart to PATH."
flutter_bin="$(resolve_flutter_bin)" || die "Missing 'flutter'. Install Flutter (recommended: \`pixi run setup-flutter\`) or add Flutter to PATH."

web_ci_temp_root="$(mktemp -d -t secondloop_flutter_web_ci.XXXXXX)"
web_worktree=""

cleanup() {
  if [[ -n "${web_worktree}" && -d "${web_worktree}" ]]; then
    git worktree remove --force "${web_worktree}" >/dev/null 2>&1 || rm -rf "${web_worktree}" 2>/dev/null || true
  fi

  rm -rf "${web_ci_temp_root}" 2>/dev/null || true
}
trap cleanup EXIT INT TERM

sync_workspace_state_into_worktree() {
  local destination_root="$1"
  local file

  if ! git diff --quiet HEAD --; then
    if ! git diff --binary --relative HEAD -- | git -C "${destination_root}" apply --allow-empty --binary; then
      die "failed to sync tracked workspace changes into ${destination_root}"
    fi
  fi

  while IFS= read -r -d '' file; do
    [[ -n "${file}" ]] || continue
    mkdir -p "${destination_root}/$(dirname "${file}")"
    rm -rf "${destination_root}/${file}"
    cp -PR "${repo_root}/${file}" "${destination_root}/${file}"
  done < <(git ls-files --others --exclude-standard -z)
}

web_worktree="${web_ci_temp_root}/web"
if ! git worktree add --detach "${web_worktree}" HEAD >/dev/null 2>&1; then
  die "failed to create temporary Flutter web worktree"
fi

sync_workspace_state_into_worktree "${web_worktree}"

(
  cd "${web_worktree}"
  export SECONDLOOP_DART_BIN="${dart_bin}"
  export SECONDLOOP_FLUTTER_BIN="${flutter_bin}"
  export SECONDLOOP_I18N_DART_BIN="${dart_bin}"
  export SECONDLOOP_I18N_FLUTTER_BIN="${flutter_bin}"

  run_with_periodic_status "flutter pub get (web worktree)" run_flutter_tool pub get
  run_with_periodic_status "flutter web i18n refresh" bash scripts/run_i18n_refresh.sh
  run_with_periodic_status \
    "flutter web smoke tests" \
    run_flutter_tool test test/web_app/web_app_gate_test.dart test/web_app/web_app_service_http_test.dart
  run_with_periodic_status \
    "flutter build web" \
    env MSYS2_ARG_CONV_EXCL='*' run_flutter_tool build web --base-href /app/
)
