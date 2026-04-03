#!/usr/bin/env bash
set -euo pipefail

repo_root="$(git rev-parse --show-toplevel 2>/dev/null || true)"
if [[ -z "${repo_root}" ]]; then
  exit 0
fi

cd "${repo_root}"
source "${repo_root}/scripts/pre_commit_common.sh"

resolve_cargo_bin >/dev/null || cargo_missing_message
resolve_libclang_path >/dev/null || libclang_missing_message
resolve_vulkan_sdk_root >/dev/null || vulkan_sdk_missing_message
ensure_windows_short_build_paths

export CARGO_INCREMENTAL="${CARGO_INCREMENTAL:-0}"
export CARGO_PROFILE_DEV_DEBUG="${CARGO_PROFILE_DEV_DEBUG:-0}"
export CARGO_PROFILE_TEST_DEBUG="${CARGO_PROFILE_TEST_DEBUG:-0}"
export RUSTFLAGS="${RUSTFLAGS:--C debuginfo=0}"

python_bin=""
for candidate in \
  "${repo_root}/.pixi/envs/default/bin/python" \
  "${repo_root}/.pixi/envs/default/python.exe"; do
  if [[ -f "${candidate}" ]]; then
    python_bin="${candidate}"
    break
  fi
done

if [[ -z "${python_bin}" ]]; then
  die "Missing project-managed Python at .pixi/envs/default. Run \`pixi install\`."
fi

if ! "${cargo_bin}" fmt --manifest-path rust/Cargo.toml --all -- --check; then
  echo "" >&2
  echo "pre-commit: rustfmt failed." >&2
  echo "Fix locally with: pixi run cargo fmt \"--manifest-path rust/Cargo.toml --all\"" >&2
  exit 1
fi

if ! run_with_periodic_status "rust clippy" "${cargo_bin}" clippy --manifest-path rust/Cargo.toml --all-targets --all-features -- -D warnings; then
  echo "" >&2
  echo "pre-commit: rust clippy failed." >&2
  echo "Fix locally with: pixi run cargo clippy \"--all-targets --all-features -- -D warnings\"" >&2
  exit 1
fi

jsonl_path="$(mktemp -t secondloop_rust_tests.XXXXXX.jsonl)"
trap 'rm -f "${jsonl_path}" 2>/dev/null || true' EXIT

echo "pre-commit: compiling Rust test binaries once for parallel execution..." >&2
if ! run_with_periodic_status "rust test compile" bash -lc '"$1" test --manifest-path rust/Cargo.toml --all --no-run --message-format=json > "$2"' _ "${cargo_bin}" "${jsonl_path}"; then
  echo "" >&2
  echo "pre-commit: rust test compilation failed." >&2
  echo "Fix locally with: pixi run cargo test" >&2
  exit 1
fi

rust_test_jobs="${SECONDLOOP_LOCAL_RUST_TEST_JOBS:-2}"
rust_test_max_binaries="${SECONDLOOP_LOCAL_RUST_TEST_MAX_BINARIES:-0}"

echo "pre-commit: running Rust test binaries in parallel (jobs=${rust_test_jobs})..." >&2
if ! run_with_periodic_status "rust tests" "${python_bin}" scripts/run_rust_test_binaries_parallel.py --jsonl "${jsonl_path}" --jobs "${rust_test_jobs}" --max-binaries "${rust_test_max_binaries}"; then
  echo "" >&2
  echo "pre-commit: rust tests failed." >&2
  echo "Fix locally with: pixi run cargo test" >&2
  exit 1
fi
