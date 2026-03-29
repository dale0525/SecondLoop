staged_files=()
while IFS= read -r file; do
  staged_files+=("${file}")
done < <(git diff --cached --name-only --diff-filter=ACMRD)

if [[ ${#staged_files[@]} -eq 0 ]]; then
  exit 0
fi

dart_files=()
run_rust_fmt=0
run_flutter_checks=0
run_i18n_refresh_needed=0
for file in "${staged_files[@]}"; do
  if [[ "${file}" == *.dart ]]; then
    if [[ -f "${file}" ]]; then
      dart_files+=("${file}")
    fi
    run_flutter_checks=1
    continue
  fi

  case "${file}" in
    analysis_options.yaml | pubspec.yaml | pubspec.lock)
      run_flutter_checks=1
      ;;
  esac

  if is_i18n_source_file "${file}"; then
    run_flutter_checks=1
    run_i18n_refresh_needed=1
  fi

  case "${file}" in
    rust/*) run_rust_fmt=1 ;;
  esac
done

if [[ ${#dart_files[@]} -eq 0 && ${run_flutter_checks} -eq 0 && ${run_rust_fmt} -eq 0 && ${run_i18n_refresh_needed} -eq 0 ]]; then
  exit 0
fi

if [[ ${#dart_files[@]} -ne 0 || ${run_flutter_checks} -ne 0 || ${run_i18n_refresh_needed} -ne 0 ]]; then
  resolve_dart_bin >/dev/null || die "Missing 'dart'. Install Flutter (recommended: \`pixi run setup-flutter\`) or add Dart to PATH."
fi

if [[ ${run_flutter_checks} -ne 0 ]]; then
  resolve_flutter_bin >/dev/null || die "Missing 'flutter'. Install Flutter (recommended: \`pixi run setup-flutter\`) or add Flutter to PATH."
fi

cargo_bin=""
if [[ ${run_rust_fmt} -ne 0 ]]; then
  if ! resolve_cargo_bin; then
    cargo_missing_message
  fi

  if ! resolve_libclang_path; then
    libclang_missing_message
  fi

  if ! resolve_vulkan_sdk_root; then
    vulkan_sdk_missing_message
  fi

  ensure_windows_short_build_paths
fi

stashed=0
cleanup() {
  if (( stashed )); then
    if ! git stash pop -q; then
      trap - EXIT
      echo "pre-commit: Failed to restore unstaged changes from stash. Resolve conflicts and re-run commit." >&2
      echo "pre-commit: Inspect saved changes with: git stash list --date=local" >&2
      echo "pre-commit: Recover manually with: git stash show -p stash@{0}" >&2
      exit 1
    fi
  fi
}
trap cleanup EXIT

if ! git diff --quiet || [[ -n "$(git ls-files --others --exclude-standard)" ]]; then
  git stash push -k -u -q -m "pre-commit(worktree)"
  stashed=1
fi

if [[ ${run_i18n_refresh_needed} -ne 0 ]]; then
  run_i18n_refresh
  warn_auto_staged_i18n_refresh_changes
  git add -- lib/i18n
fi

if [[ ${run_flutter_checks} -ne 0 || ${#dart_files[@]} -ne 0 || ${run_i18n_refresh_needed} -ne 0 ]]; then
  ensure_i18n_generated
  if [[ ${i18n_generated_now} -ne 0 ]]; then
    git add -- lib/i18n/strings.g.dart
  fi
fi

if [[ ${#dart_files[@]} -ne 0 ]]; then
  run_dart_tool format "${dart_files[@]}"
  git add -- "${dart_files[@]}"
fi

if [[ ${run_rust_fmt} -ne 0 ]]; then
  if ! "${cargo_bin}" fmt --manifest-path rust/Cargo.toml --all; then
    echo "" >&2
    echo "pre-commit: rustfmt failed." >&2
    echo "Fix locally with: pixi run cargo fmt \"--manifest-path rust/Cargo.toml --all\"" >&2
    exit 1
  fi
  git add -u -- rust
fi

if [[ ${run_flutter_checks} -ne 0 ]]; then
  flutter_test_targets=()
  while IFS= read -r file; do
    [[ -n "${file}" ]] || continue
    flutter_test_targets+=("${file}")
  done < <(collect_targeted_flutter_tests)

  if [[ ${run_i18n_refresh_needed} -ne 0 ]]; then
    run_i18n_analyze
  fi

  if ! run_flutter_tool analyze; then
    echo "" >&2
    echo "pre-commit: flutter analyze failed." >&2
    echo "Fix locally with: pixi run flutter analyze" >&2
    exit 1
  fi

  if [[ ${#flutter_test_targets[@]} -ne 0 ]]; then
    if [[ ${#flutter_test_targets[@]} -eq 1 && "${flutter_test_targets[0]}" == "__FULL_SUITE__" ]]; then
      flutter_test_targets=()
    fi

    if ! run_flutter_tool test --concurrency=1 "${flutter_test_targets[@]}"; then
      echo "" >&2
      echo "pre-commit: flutter test failed." >&2
      if [[ ${#flutter_test_targets[@]} -eq 0 ]]; then
        echo "Fix locally with: pixi run flutter test" >&2
      else
        echo "Fix locally with: pixi run flutter test \"${flutter_test_targets[*]}\"" >&2
      fi
      exit 1
    fi
  else
    echo "pre-commit: skipping Flutter tests (no targeted tests found for staged lib changes)." >&2
    echo "Run full verification with: git push or pixi run ci" >&2
  fi
fi
