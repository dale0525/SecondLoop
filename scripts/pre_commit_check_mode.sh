export SECONDLOOP_PRECOMMIT_ALLOW_WORKTREE_WRITES=0
precommit_allow_worktree_writes=0

i18n_temp_root=""
i18n_temp_repo=""
i18n_temp_repo_prepared=0
temp_generated_i18n_strings_path=""

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

  cleanup_temp_i18n_artifacts() {
    if [[ -n "${temp_generated_i18n_strings_path}" ]]; then
      rm -f "${temp_generated_i18n_strings_path}" 2>/dev/null || true
    fi
    if [[ -n "${i18n_temp_root}" ]]; then
      rm -rf "${i18n_temp_root}" 2>/dev/null || true
    fi
  }

  prepare_i18n_temp_copy() {
    local dart_bin flutter_bin package_config_dir
    if [[ ${i18n_temp_repo_prepared} -eq 1 && -d "${i18n_temp_repo}" ]]; then
      return 0
    fi

    i18n_temp_root="$(mktemp -d 2>/dev/null || mktemp -d -t secondloop_i18n_check)"
    i18n_temp_repo="${i18n_temp_root}/repo"
    dart_bin="$(resolve_dart_bin)"
    flutter_bin="$(resolve_flutter_bin)"
    package_config_dir="${repo_root}/.dart_tool/package_config.json"

    extract_local_path_dependencies_from_pubspec() {
      local pubspec_path="$1"

      [[ -f "${pubspec_path}" ]] || return 0

      awk '
        /^[[:space:]]*(dependencies|dev_dependencies|dependency_overrides):[[:space:]]*$/ {
          in_section=1
          next
        }
        /^[^[:space:]]/ {
          in_section=0
        }
        in_section && /^[[:space:]]+path:[[:space:]]*/ {
          line=$0
          sub(/^[[:space:]]+path:[[:space:]]*/, "", line)
          sub(/[[:space:]]+#.*$/, "", line)
          gsub(/^["'"'"'" ]+|["'"'"'" ]+$/, "", line)
          if (length(line) > 0) {
            print line
          }
        }
      ' "${pubspec_path}"
    }

    append_pending_pubspec() {
      local candidate="$1"
      local existing

      for existing in "${pending_pubspecs[@]}"; do
        if [[ "${existing}" == "${candidate}" ]]; then
          return 0
        fi
      done
      for existing in "${processed_pubspecs[@]}"; do
        if [[ "${existing}" == "${candidate}" ]]; then
          return 0
        fi
      done

      pending_pubspecs+=("${candidate}")
    }

    copy_local_path_dependencies_to_temp_repo() {
      local current_pubspec current_pubspec_dir relative_path resolved_path normalized_path destination_parent dependency_pubspec
      local pending_pubspecs=("${repo_root}/pubspec.yaml")
      local processed_pubspecs=()

      while [[ ${#pending_pubspecs[@]} -gt 0 ]]; do
        current_pubspec="${pending_pubspecs[0]}"
        pending_pubspecs=("${pending_pubspecs[@]:1}")
        processed_pubspecs+=("${current_pubspec}")
        current_pubspec_dir="$(dirname "${current_pubspec}")"

        while IFS= read -r relative_path; do
          [[ -n "${relative_path}" ]] || continue

          resolved_path="$(
            cd "${current_pubspec_dir}" &&
              cd "${relative_path}" 2>/dev/null &&
              pwd -P
          )"
          [[ -n "${resolved_path}" ]] || continue

          case "${resolved_path}" in
            "${repo_root}"/*) ;;
            *) continue ;;
          esac

          normalized_path="${resolved_path#${repo_root}/}"
          normalized_path="${normalized_path%/}"
          if [[ -z "${normalized_path}" || ! -e "${repo_root}/${normalized_path}" ]]; then
            continue
          fi

          destination_parent="${i18n_temp_repo}/$(dirname "${normalized_path}")"
          mkdir -p "${destination_parent}"
          if [[ ! -e "${i18n_temp_repo}/${normalized_path}" ]]; then
            cp -R "${repo_root}/${normalized_path}" "${destination_parent}/"
          fi

          dependency_pubspec="${i18n_temp_repo}/${normalized_path}/pubspec.yaml"
          if [[ -f "${dependency_pubspec}" ]]; then
            append_pending_pubspec "${dependency_pubspec}"
          fi
        done < <(extract_local_path_dependencies_from_pubspec "${current_pubspec}")
      done
    }

    mkdir -p "${i18n_temp_repo}/lib"
    cp "${repo_root}/pubspec.yaml" "${i18n_temp_repo}/pubspec.yaml"
    if [[ -f "${repo_root}/pubspec.lock" ]]; then
      cp "${repo_root}/pubspec.lock" "${i18n_temp_repo}/pubspec.lock"
    fi
    cp "${repo_root}/slang.yaml" "${i18n_temp_repo}/slang.yaml"
    cp -R "${repo_root}/lib/i18n" "${i18n_temp_repo}/lib/"
    copy_local_path_dependencies_to_temp_repo
    if [[ -f "${package_config_dir}" ]]; then
      mkdir -p "${i18n_temp_repo}/.dart_tool"
      cp "${package_config_dir}" "${i18n_temp_repo}/.dart_tool/package_config.json"
    fi
    cp -R "${repo_root}/scripts" "${i18n_temp_repo}/"

    (
      cd "${i18n_temp_repo}"
      export SECONDLOOP_I18N_DART_BIN="${dart_bin}"
      export SECONDLOOP_I18N_FLUTTER_BIN="${flutter_bin}"
      bash scripts/run_i18n_refresh.sh >/dev/null 2>&1
    )

    i18n_temp_repo_prepared=1
  }

  run_i18n_refresh_in_temp_copy() {
    prepare_i18n_temp_copy

    git diff --no-index --exit-code -- \
      "${repo_root}/lib/i18n" \
      "${i18n_temp_repo}/lib/i18n" >/dev/null
  }

  ensure_temp_i18n_strings_for_analysis() {
    if [[ -f "${repo_root}/lib/i18n/strings.g.dart" ]]; then
      return 0
    fi

    prepare_i18n_temp_copy
    temp_generated_i18n_strings_path="${repo_root}/lib/i18n/strings.g.dart"
    cp "${i18n_temp_repo}/lib/i18n/strings.g.dart" "${temp_generated_i18n_strings_path}"
  }

  trap cleanup_temp_i18n_artifacts EXIT

  if (( scope_flutter )); then
    ensure_temp_i18n_strings_for_analysis
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
