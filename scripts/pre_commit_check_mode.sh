export SECONDLOOP_PRECOMMIT_ALLOW_WORKTREE_WRITES=0

  if (( scope_flutter == 0 && scope_rust == 0 )); then
    scope_flutter=1
    scope_rust=1
  fi

  if (( scope_flutter )); then
    resolve_dart_bin >/dev/null || die "Missing 'dart'. Install Flutter (recommended: \`pixi run setup-flutter\`) or add Dart to PATH."
    resolve_flutter_bin >/dev/null || die "Missing 'flutter'. Install Flutter (recommended: \`pixi run setup-flutter\`) or add Flutter to PATH."
  fi

  cargo_bin=""
  if (( scope_rust )); then
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

  run_i18n_refresh_in_temp_copy() {
    local temp_root temp_repo dart_bin flutter_bin package_config_dir
    temp_root="$(mktemp -d 2>/dev/null || mktemp -d -t secondloop_i18n_check)"
    temp_repo="${temp_root}/repo"
    dart_bin="$(resolve_dart_bin)"
    flutter_bin="$(resolve_flutter_bin)"
    package_config_dir="${repo_root}/.dart_tool/package_config.json"

    cleanup_temp_i18n_copy() {
      rm -rf "${temp_root}" 2>/dev/null || true
    }

    trap cleanup_temp_i18n_copy RETURN

    mkdir -p "${temp_repo}/lib"
    cp "${repo_root}/pubspec.yaml" "${temp_repo}/pubspec.yaml"
    if [[ -f "${repo_root}/pubspec.lock" ]]; then
      cp "${repo_root}/pubspec.lock" "${temp_repo}/pubspec.lock"
    fi
    cp "${repo_root}/slang.yaml" "${temp_repo}/slang.yaml"
    cp -R "${repo_root}/lib/i18n" "${temp_repo}/lib/"
    if [[ -f "${package_config_dir}" ]]; then
      mkdir -p "${temp_repo}/.dart_tool"
      cp "${package_config_dir}" "${temp_repo}/.dart_tool/package_config.json"
    fi
    cp -R "${repo_root}/scripts" "${temp_repo}/"

    (
      cd "${temp_repo}"
      export SECONDLOOP_I18N_DART_BIN="${dart_bin}"
      export SECONDLOOP_I18N_FLUTTER_BIN="${flutter_bin}"
      bash scripts/run_i18n_refresh.sh >/dev/null
    )

    git diff --no-index --exit-code -- \
      "${repo_root}/lib/i18n" \
      "${temp_repo}/lib/i18n" >/dev/null
  }

  if (( scope_flutter )); then
    if [[ ! -f "lib/i18n/strings.g.dart" ]]; then
      echo "pre-commit: lib/i18n/strings.g.dart is missing." >&2
      echo "Fix locally with: pixi run i18n-refresh" >&2
      exit 1
    fi
    run_i18n_analyze

    if ! run_i18n_refresh_in_temp_copy; then
      echo "" >&2
      echo "pre-commit: i18n generated files differ from refreshed outputs." >&2
      echo "Fix locally with: pixi run i18n-refresh" >&2
      exit 1
    fi

    if ! bash scripts/check_no_python_runtime.sh; then
      echo "" >&2
      echo "pre-commit: python runtime guard failed." >&2
      echo "Fix locally with: pixi run ci" >&2
      exit 1
    fi

    if ! run_dart_tool format --output=none lib test rust_builder integration_test test_driver --set-exit-if-changed; then
      echo "" >&2
      echo "pre-commit: Formatting required." >&2
      echo "Fix locally with:" >&2
      echo "  dart format lib test rust_builder integration_test test_driver" >&2
      echo "Or (recommended):" >&2
      echo "  pixi run fmt" >&2
      exit 1
    fi

    if ! run_flutter_tool analyze; then
      echo "" >&2
      echo "pre-commit: flutter analyze failed." >&2
      echo "Fix locally with: pixi run flutter analyze" >&2
      exit 1
    fi

    if (( ci_mode )); then
      if ! run_flutter_tool test --concurrency=1; then
        echo "" >&2
        echo "pre-commit: flutter test failed." >&2
        echo "Fix locally with: pixi run flutter test" >&2
        exit 1
      fi
    fi
  fi

  if (( scope_rust )); then
    if ! "${cargo_bin}" fmt --manifest-path rust/Cargo.toml --all -- --check; then
      echo "" >&2
      echo "pre-commit: rustfmt failed." >&2
      echo "Fix locally with: pixi run cargo fmt \"--manifest-path rust/Cargo.toml --all\"" >&2
      exit 1
    fi

    if (( ci_mode )); then
      if ! "${cargo_bin}" clippy --manifest-path rust/Cargo.toml --all-targets --all-features -- -D warnings; then
        echo "" >&2
        echo "pre-commit: rust clippy failed." >&2
        echo "Fix locally with: pixi run cargo clippy \"--all-targets --all-features -- -D warnings\"" >&2
        exit 1
      fi

      if ! "${cargo_bin}" test --manifest-path rust/Cargo.toml --all; then
        echo "" >&2
        echo "pre-commit: rust tests failed." >&2
        echo "Fix locally with: pixi run cargo test" >&2
        exit 1
      fi
    fi
  fi

  exit
