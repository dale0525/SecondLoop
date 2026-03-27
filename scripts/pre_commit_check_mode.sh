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

  if (( scope_flutter )); then
    ensure_i18n_generated
    if [[ ${i18n_generated_now} -eq 0 ]]; then
      run_i18n_refresh
    fi
    run_i18n_analyze

    if ! bash scripts/check_no_python_runtime.sh; then
      echo "" >&2
      echo "pre-commit: python runtime guard failed." >&2
      echo "Fix locally with: bash scripts/check_no_python_runtime.sh" >&2
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
