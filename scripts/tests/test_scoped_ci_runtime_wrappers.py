from __future__ import annotations

from pathlib import Path
import os
import shutil
import stat
import subprocess
import tempfile
import unittest


REPO_ROOT = Path(__file__).resolve().parents[2]
PRE_COMMIT_COMMON = REPO_ROOT / "scripts/pre_commit_common.sh"
RUN_FLUTTER_CI_LOCAL = REPO_ROOT / "scripts/run_flutter_ci_local.sh"
RUN_FLUTTER_TEST_SHARD = REPO_ROOT / "scripts/run_flutter_test_shard.sh"
RUN_FLUTTER_WEB_CI_LOCAL = REPO_ROOT / "scripts/run_flutter_web_ci_local.sh"
RUN_I18N_REFRESH = REPO_ROOT / "scripts/run_i18n_refresh.sh"
RUN_RUST_CI_NEXTEST = REPO_ROOT / "scripts/run_rust_ci_nextest.sh"
RUN_RUST_BUILDER_PACKAGE_TESTS = REPO_ROOT / "scripts/run_rust_builder_package_tests.sh"
SELECT_FLUTTER_TEST_TARGETS = REPO_ROOT / "scripts/select_flutter_test_targets.sh"


def _resolve_git_bash() -> str | None:
    bash_from_path = shutil.which("bash.exe") or shutil.which("bash")
    normalized_bash = bash_from_path.lower() if bash_from_path else ""
    if bash_from_path and all(
        marker not in normalized_bash for marker in ("system32", "windowsapps")
    ):
        return bash_from_path

    git_from_path = shutil.which("git.exe") or shutil.which("git")
    if git_from_path:
        git_root = Path(git_from_path).resolve().parent.parent
        for relative in ("bin/bash.exe", "usr/bin/bash.exe"):
            candidate = git_root / relative
            if candidate.exists():
                return str(candidate)

    for candidate in [
        Path("C:/Program Files/Git/bin/bash.exe"),
        Path("C:/Program Files/Git/usr/bin/bash.exe"),
        Path("C:/Program Files (x86)/Git/bin/bash.exe"),
        Path("C:/Program Files (x86)/Git/usr/bin/bash.exe"),
    ]:
        if candidate.exists():
            return str(candidate)

    return None


BASH_BIN = _resolve_git_bash()
TRUE_BIN = shutil.which("true") or "true"


@unittest.skipUnless(BASH_BIN, "bash is required")
@unittest.skipUnless(shutil.which("git"), "git is required")
class ScopedCiRuntimeWrapperBehaviorTests(unittest.TestCase):
    def _run(
        self,
        args: list[str],
        *,
        cwd: Path,
        input_text: str | None = None,
        env: dict[str, str] | None = None,
    ) -> subprocess.CompletedProcess[str]:
        resolved_args = list(args)
        if resolved_args and resolved_args[0] == "bash":
            resolved_args[0] = BASH_BIN or "bash"
        return subprocess.run(
            resolved_args,
            cwd=cwd,
            input=input_text,
            check=False,
            capture_output=True,
            text=True,
            env=env,
        )

    def _make_executable(self, path: Path) -> None:
        path.chmod(path.stat().st_mode | stat.S_IXUSR)

    def _init_repo(self, repo_root: Path, default_branch: str) -> None:
        self._run(["git", "init", "-b", default_branch], cwd=repo_root)
        self._run(["git", "config", "user.name", "Test User"], cwd=repo_root)
        self._run(["git", "config", "user.email", "test@example.com"], cwd=repo_root)

    def _commit_all(self, repo_root: Path, message: str) -> None:
        self._run(["git", "add", "-A"], cwd=repo_root)
        result = self._run(["git", "commit", "-m", message], cwd=repo_root)
        self.assertEqual(result.returncode, 0, msg=result.stderr)

    def test_rust_builder_package_tests_run_pub_get_before_dart_test(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            repo_root = Path(temp_dir)
            self._init_repo(repo_root, "main")

            scripts_dir = repo_root / "scripts"
            rust_builder_test_dir = repo_root / "rust_builder/cargokit/build_tool/test"
            rust_builder_package_dir = repo_root / "rust_builder/cargokit/build_tool"
            fake_bin_dir = repo_root / "fake-bin"
            scripts_dir.mkdir(parents=True, exist_ok=True)
            rust_builder_test_dir.mkdir(parents=True, exist_ok=True)
            fake_bin_dir.mkdir(parents=True, exist_ok=True)

            (rust_builder_package_dir / "pubspec.yaml").write_text(
                "name: build_tool\n",
                encoding="utf-8",
            )
            (rust_builder_test_dir / "builder_sqlite_cleanup_test.dart").write_text(
                "// stub\n",
                encoding="utf-8",
            )

            (scripts_dir / "run_rust_builder_package_tests.sh").write_text(
                RUN_RUST_BUILDER_PACKAGE_TESTS.read_text(encoding="utf-8"),
                encoding="utf-8",
            )
            self._make_executable(scripts_dir / "run_rust_builder_package_tests.sh")

            (scripts_dir / "pre_commit_common.sh").write_text(
                "\n".join(
                    [
                        "die() {",
                        "  echo \"pre-commit: $*\" >&2",
                        "  exit 1",
                        "}",
                        "",
                        f"resolve_dart_bin() {{ printf '%s\\n' \"{(fake_bin_dir / 'dart').as_posix()}\"; }}",
                        "run_dart_tool() {",
                        "  local dart_bin",
                        "  dart_bin=\"$(resolve_dart_bin)\"",
                        "  env -u GIT_DIR -u GIT_WORK_TREE -u GIT_INDEX_FILE \"${dart_bin}\" \"$@\"",
                        "}",
                        "run_with_periodic_status() {",
                        "  local _label=\"$1\"",
                        "  shift",
                        "  \"$@\"",
                        "}",
                    ]
                )
                + "\n",
                encoding="utf-8",
            )

            (fake_bin_dir / "dart").write_text(
                "\n".join(
                    [
                        "#!/usr/bin/env bash",
                        "set -euo pipefail",
                        'repo_root="$(git rev-parse --show-toplevel)"',
                        'if [[ "$1" == "pub" && "${2:-}" == "get" ]]; then',
                        '  printf \'pub-get\\n\' >> "${repo_root}/dart.log"',
                        '  printf \'ok\\n\' > "${repo_root}/rust_builder/cargokit/build_tool/.packages-ready"',
                        "  exit 0",
                        "fi",
                        'if [[ "$1" == "test" ]]; then',
                        '  if [[ ! -f "${repo_root}/rust_builder/cargokit/build_tool/.packages-ready" ]]; then',
                        '    echo missing-pub-get >&2',
                        "    exit 7",
                        "  fi",
                        '  printf \'test\\n\' >> "${repo_root}/dart.log"',
                        "  exit 0",
                        "fi",
                        "exit 0",
                    ]
                )
                + "\n",
                encoding="utf-8",
            )
            self._make_executable(fake_bin_dir / "dart")

            self._commit_all(repo_root, "fixture")

            result = self._run(
                ["bash", "scripts/run_rust_builder_package_tests.sh"],
                cwd=repo_root,
            )

            self.assertEqual(result.returncode, 0, msg=result.stdout + result.stderr)
            self.assertEqual(
                (repo_root / "dart.log").read_text(encoding="utf-8").splitlines(),
                ["pub-get", "test"],
            )

    def test_rust_builder_package_tests_honor_explicit_dart_bin_override(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            repo_root = Path(temp_dir)
            self._init_repo(repo_root, "main")

            scripts_dir = repo_root / "scripts"
            rust_builder_package_dir = repo_root / "rust_builder/cargokit/build_tool"
            fake_bin_dir = repo_root / "fake-bin"
            scripts_dir.mkdir(parents=True, exist_ok=True)
            rust_builder_package_dir.mkdir(parents=True, exist_ok=True)
            fake_bin_dir.mkdir(parents=True, exist_ok=True)

            (rust_builder_package_dir / "pubspec.yaml").write_text(
                "name: build_tool\n",
                encoding="utf-8",
            )

            (scripts_dir / "run_rust_builder_package_tests.sh").write_text(
                RUN_RUST_BUILDER_PACKAGE_TESTS.read_text(encoding="utf-8"),
                encoding="utf-8",
            )
            self._make_executable(scripts_dir / "run_rust_builder_package_tests.sh")

            (scripts_dir / "pre_commit_common.sh").write_text(
                PRE_COMMIT_COMMON.read_text(encoding="utf-8")
                + "\n"
                + "is_windows_env() {\n"
                + "  return 1\n"
                + "}\n",
                encoding="utf-8",
            )

            (fake_bin_dir / "dart").write_text(
                "\n".join(
                    [
                        "#!/usr/bin/env bash",
                        "set -euo pipefail",
                        f'printf \'%s\\n\' "$*" >> "{(repo_root / "dart.log").as_posix()}"',
                    ]
                )
                + "\n",
                encoding="utf-8",
            )
            self._make_executable(fake_bin_dir / "dart")

            self._commit_all(repo_root, "fixture")

            result = subprocess.run(
                [BASH_BIN or "bash", "scripts/run_rust_builder_package_tests.sh"],
                cwd=repo_root,
                check=False,
                capture_output=True,
                text=True,
                timeout=5,
                env={
                    **os.environ,
                    "SECONDLOOP_DART_BIN": (fake_bin_dir / "dart").as_posix(),
                    "PATH": f"/usr/bin:/bin:{fake_bin_dir.as_posix()}",
                },
            )

            self.assertEqual(result.returncode, 0, msg=result.stdout + result.stderr)
            if (repo_root / "dart.log").exists():
                self.assertEqual(
                    (repo_root / "dart.log").read_text(encoding="utf-8").splitlines(),
                    ["pub get", "test"],
                )

    def test_rust_nextest_wrapper_finds_project_managed_cargo_nextest_plugin(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            repo_root = Path(temp_dir)
            self._init_repo(repo_root, "main")

            scripts_dir = repo_root / "scripts"
            tool_cargo_bin_dir = repo_root / ".tool/cargo/bin"
            pixi_bin_dir = repo_root / ".pixi/envs/default/bin"
            scripts_dir.mkdir(parents=True, exist_ok=True)
            tool_cargo_bin_dir.mkdir(parents=True, exist_ok=True)
            pixi_bin_dir.mkdir(parents=True, exist_ok=True)

            (scripts_dir / "run_rust_ci_nextest.sh").write_text(
                RUN_RUST_CI_NEXTEST.read_text(encoding="utf-8"),
                encoding="utf-8",
            )
            self._make_executable(scripts_dir / "run_rust_ci_nextest.sh")

            (scripts_dir / "pre_commit_common.sh").write_text(
                PRE_COMMIT_COMMON.read_text(encoding="utf-8")
                + "\n"
                + "is_windows_env() {\n"
                + "  return 1\n"
                + "}\n",
                encoding="utf-8",
            )

            (tool_cargo_bin_dir / "cargo").write_text(
                "\n".join(
                    [
                        "#!/usr/bin/env bash",
                        "set -euo pipefail",
                        'repo_root="$(git rev-parse --show-toplevel)"',
                        'printf \'%s\\n\' \"$*\" >> "${repo_root}/cargo.log"',
                        'if [[ "${1:-}" == "nextest" ]]; then',
                        '  if ! command -v cargo-nextest >/dev/null 2>&1; then',
                        "    echo 'error: no such command: `nextest`' >&2",
                        "    exit 101",
                        "  fi",
                        '  exec cargo-nextest "${@:2}"',
                        "fi",
                        'if [[ "${1:-}" == "test" && "${*: -1}" == "--doc" ]]; then',
                        "  exit 0",
                        "fi",
                        "exit 0",
                    ]
                )
                + "\n",
                encoding="utf-8",
            )
            self._make_executable(tool_cargo_bin_dir / "cargo")

            (pixi_bin_dir / "cargo-nextest").write_text(
                "\n".join(
                    [
                        "#!/usr/bin/env bash",
                        "set -euo pipefail",
                        f'printf \'%s\\n\' \"$*\" >> "{(repo_root / "nextest.log").as_posix()}"',
                    ]
                )
                + "\n",
                encoding="utf-8",
            )
            self._make_executable(pixi_bin_dir / "cargo-nextest")

            self._commit_all(repo_root, "fixture")

            result = subprocess.run(
                [BASH_BIN or "bash", "scripts/run_rust_ci_nextest.sh"],
                cwd=repo_root,
                check=False,
                capture_output=True,
                text=True,
                timeout=5,
                env={
                    **os.environ,
                    "PATH": "/usr/bin:/bin",
                },
            )

            self.assertEqual(result.returncode, 0, msg=result.stdout + result.stderr)
            if (repo_root / "cargo.log").exists():
                self.assertIn(
                    "test --manifest-path rust/Cargo.toml --doc",
                    (repo_root / "cargo.log").read_text(encoding="utf-8"),
                )
            if (repo_root / "nextest.log").exists():
                self.assertIn(
                    "run --manifest-path rust/Cargo.toml --all-features",
                    (repo_root / "nextest.log").read_text(encoding="utf-8"),
                )

    def test_flutter_test_shard_fails_when_selector_script_fails(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            repo_root = Path(temp_dir)
            self._init_repo(repo_root, "main")

            scripts_dir = repo_root / "scripts"
            lib_i18n_dir = repo_root / "lib/i18n"
            scripts_dir.mkdir(parents=True, exist_ok=True)
            lib_i18n_dir.mkdir(parents=True, exist_ok=True)
            (lib_i18n_dir / "strings.g.dart").write_text("// generated\n", encoding="utf-8")

            shard_script = scripts_dir / "run_flutter_test_shard.sh"
            shard_script.write_text(
                RUN_FLUTTER_TEST_SHARD.read_text(encoding="utf-8"),
                encoding="utf-8",
            )
            self._make_executable(shard_script)

            (scripts_dir / "pre_commit_common.sh").write_text(
                "\n".join(
                    [
                        "die() {",
                        "  echo \"pre-commit: $*\" >&2",
                        "  exit 1",
                        "}",
                        "",
                        "resolve_flutter_bin() {",
                        f"  printf '%s\\n' {TRUE_BIN}",
                        "}",
                        "",
                        "run_with_periodic_status() {",
                        "  local _label=\"$1\"",
                        "  shift",
                        "  \"$@\"",
                        "}",
                        "",
                        "run_flutter_tool() {",
                        "  return 0",
                        "}",
                    ]
                )
                + "\n",
                encoding="utf-8",
            )

            (scripts_dir / "select_flutter_test_targets.sh").write_text(
                "#!/usr/bin/env bash\nset -euo pipefail\necho selector-failed >&2\nexit 9\n",
                encoding="utf-8",
            )
            self._make_executable(scripts_dir / "select_flutter_test_targets.sh")

            result = self._run(
                [
                    "bash",
                    "scripts/run_flutter_test_shard.sh",
                    "--shard-index",
                    "0",
                    "--shard-count",
                    "1",
                ],
                cwd=repo_root,
                env={
                    **os.environ,
                    "SECONDLOOP_ENABLE_MACOS_INTEGRATION_TESTS": "1",
                },
            )

            self.assertNotEqual(result.returncode, 0)
            self.assertIn("failed to select test targets", result.stderr)

    def test_flutter_test_shard_splits_unit_and_integration_targets(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            repo_root = Path(temp_dir)
            self._init_repo(repo_root, "main")

            scripts_dir = repo_root / "scripts"
            lib_i18n_dir = repo_root / "lib/i18n"
            fake_bin_dir = repo_root / "fake-bin"
            scripts_dir.mkdir(parents=True, exist_ok=True)
            lib_i18n_dir.mkdir(parents=True, exist_ok=True)
            fake_bin_dir.mkdir(parents=True, exist_ok=True)
            (lib_i18n_dir / "strings.g.dart").write_text("// generated\n", encoding="utf-8")

            shard_script = scripts_dir / "run_flutter_test_shard.sh"
            shard_script.write_text(
                RUN_FLUTTER_TEST_SHARD.read_text(encoding="utf-8"),
                encoding="utf-8",
            )
            self._make_executable(shard_script)

            (scripts_dir / "pre_commit_common.sh").write_text(
                "\n".join(
                    [
                        "die() {",
                        "  echo \"pre-commit: $*\" >&2",
                        "  exit 1",
                        "}",
                        "",
                        f"resolve_flutter_bin() {{ printf '%s\\n' \"{(fake_bin_dir / 'flutter').as_posix()}\"; }}",
                        "",
                        "resolve_default_flutter_test_device() {",
                        "  printf '%s\\n' macos",
                        "}",
                        "",
                        "run_with_periodic_status() {",
                        "  local _label=\"$1\"",
                        "  shift",
                        "  \"$@\"",
                        "}",
                        "",
                        "run_flutter_tool() {",
                        "  local flutter_bin",
                        "  flutter_bin=\"$(resolve_flutter_bin)\"",
                        "  env -u GIT_DIR -u GIT_WORK_TREE -u GIT_INDEX_FILE \"${flutter_bin}\" \"$@\"",
                        "}",
                        "",
                        "is_windows_env() {",
                        "  return 1",
                        "}",
                        "",
                        "make_precommit_temp_dir() {",
                        "  mktemp -d",
                        "}",
                    ]
                )
                + "\n",
                encoding="utf-8",
            )

            (scripts_dir / "select_flutter_test_targets.sh").write_text(
                (
                    "#!/usr/bin/env bash\n"
                    "set -euo pipefail\n"
                    "printf 'test/unit_a_test.dart\\n"
                    "integration_test/app_flow_test.dart\\n"
                    "integration_test/second_flow_test.dart\\n'"
                ),
                encoding="utf-8",
            )
            self._make_executable(scripts_dir / "select_flutter_test_targets.sh")

            (fake_bin_dir / "flutter").write_text(
                "\n".join(
                    [
                        "#!/usr/bin/env bash",
                        "set -euo pipefail",
                        'repo_root="$(git rev-parse --show-toplevel)"',
                        "saw_unit=0",
                        "saw_integration=0",
                        "for arg in \"$@\"; do",
                        '  case "${arg}" in',
                        '    test/*_test.dart) saw_unit=1 ;;',
                        '    integration_test/*_test.dart) saw_integration=1 ;;',
                        "  esac",
                        "done",
                        'if [[ "${saw_unit}" == "1" && "${saw_integration}" == "1" ]]; then',
                        "  echo mixed-test-kinds >&2",
                        "  exit 21",
                        "fi",
                        'printf \'%s\\n\' \"$*\" >> "${repo_root}/flutter.log"',
                    ]
                )
                + "\n",
                encoding="utf-8",
            )
            self._make_executable(fake_bin_dir / "flutter")

            result = self._run(
                [
                    "bash",
                    "scripts/run_flutter_test_shard.sh",
                    "--shard-index",
                    "0",
                    "--shard-count",
                    "1",
                ],
                cwd=repo_root,
                env={
                    **os.environ,
                    "SECONDLOOP_ENABLE_MACOS_INTEGRATION_TESTS": "1",
                },
            )

            self.assertEqual(result.returncode, 0, msg=result.stdout + result.stderr)
            self.assertEqual(
                (repo_root / "flutter.log").read_text(encoding="utf-8").splitlines(),
                [
                    "test --concurrency=1 test/unit_a_test.dart",
                    "test -d macos --concurrency=1 integration_test/app_flow_test.dart",
                    "test -d macos --concurrency=1 integration_test/second_flow_test.dart",
                ],
            )

    def test_flutter_test_shard_skips_macos_integration_targets_by_default(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            repo_root = Path(temp_dir)
            self._init_repo(repo_root, "main")

            scripts_dir = repo_root / "scripts"
            lib_i18n_dir = repo_root / "lib/i18n"
            fake_bin_dir = repo_root / "fake-bin"
            scripts_dir.mkdir(parents=True, exist_ok=True)
            lib_i18n_dir.mkdir(parents=True, exist_ok=True)
            fake_bin_dir.mkdir(parents=True, exist_ok=True)
            (lib_i18n_dir / "strings.g.dart").write_text("// generated\n", encoding="utf-8")

            shard_script = scripts_dir / "run_flutter_test_shard.sh"
            shard_script.write_text(
                RUN_FLUTTER_TEST_SHARD.read_text(encoding="utf-8"),
                encoding="utf-8",
            )
            self._make_executable(shard_script)

            (scripts_dir / "pre_commit_common.sh").write_text(
                "\n".join(
                    [
                        "die() {",
                        "  echo \"pre-commit: $*\" >&2",
                        "  exit 1",
                        "}",
                        "",
                        f"resolve_flutter_bin() {{ printf '%s\\n' \"{(fake_bin_dir / 'flutter').as_posix()}\"; }}",
                        "",
                        "resolve_default_flutter_test_device() {",
                        "  printf '%s\\n' macos",
                        "}",
                        "",
                        "run_with_periodic_status() {",
                        "  local _label=\"$1\"",
                        "  shift",
                        "  \"$@\"",
                        "}",
                        "",
                        "run_flutter_tool() {",
                        "  local flutter_bin",
                        "  flutter_bin=\"$(resolve_flutter_bin)\"",
                        "  env -u GIT_DIR -u GIT_WORK_TREE -u GIT_INDEX_FILE \"${flutter_bin}\" \"$@\"",
                        "}",
                        "",
                        "is_windows_env() {",
                        "  return 1",
                        "}",
                        "",
                        "make_precommit_temp_dir() {",
                        "  mktemp -d",
                        "}",
                    ]
                )
                + "\n",
                encoding="utf-8",
            )

            (scripts_dir / "select_flutter_test_targets.sh").write_text(
                (
                    "#!/usr/bin/env bash\n"
                    "set -euo pipefail\n"
                    "printf 'test/unit_a_test.dart\\n'\n"
                    "printf 'integration_test/app_flow_test.dart\\n'"
                ),
                encoding="utf-8",
            )
            self._make_executable(scripts_dir / "select_flutter_test_targets.sh")

            (fake_bin_dir / "flutter").write_text(
                "\n".join(
                    [
                        "#!/usr/bin/env bash",
                        "set -euo pipefail",
                        'repo_root="$(git rev-parse --show-toplevel)"',
                        'printf \'%s\\n\' \"$*\" >> "${repo_root}/flutter.log"',
                    ]
                )
                + "\n",
                encoding="utf-8",
            )
            self._make_executable(fake_bin_dir / "flutter")

            result = self._run(
                [
                    "bash",
                    "scripts/run_flutter_test_shard.sh",
                    "--shard-index",
                    "0",
                    "--shard-count",
                    "1",
                ],
                cwd=repo_root,
            )

            self.assertEqual(result.returncode, 0, msg=result.stdout + result.stderr)
            self.assertIn(
                "skipping macOS integration tests by default",
                result.stderr,
            )
            self.assertEqual(
                (repo_root / "flutter.log").read_text(encoding="utf-8").splitlines(),
                ["test --concurrency=1 test/unit_a_test.dart"],
            )

    def test_flutter_test_shard_wraps_linux_integration_targets_with_xvfb(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            repo_root = Path(temp_dir)
            self._init_repo(repo_root, "main")

            scripts_dir = repo_root / "scripts"
            lib_i18n_dir = repo_root / "lib/i18n"
            fake_bin_dir = repo_root / "fake-bin"
            scripts_dir.mkdir(parents=True, exist_ok=True)
            lib_i18n_dir.mkdir(parents=True, exist_ok=True)
            fake_bin_dir.mkdir(parents=True, exist_ok=True)
            (lib_i18n_dir / "strings.g.dart").write_text("// generated\n", encoding="utf-8")

            shard_script = scripts_dir / "run_flutter_test_shard.sh"
            shard_script.write_text(
                RUN_FLUTTER_TEST_SHARD.read_text(encoding="utf-8"),
                encoding="utf-8",
            )
            self._make_executable(shard_script)

            (scripts_dir / "pre_commit_common.sh").write_text(
                "\n".join(
                    [
                        "die() {",
                        "  echo \"pre-commit: $*\" >&2",
                        "  exit 1",
                        "}",
                        "",
                        f"resolve_flutter_bin() {{ printf '%s\\n' \"{(fake_bin_dir / 'flutter').as_posix()}\"; }}",
                        "",
                        "resolve_default_flutter_test_device() {",
                        "  printf '%s\\n' linux",
                        "}",
                        "",
                        "run_with_periodic_status() {",
                        "  local _label=\"$1\"",
                        "  shift",
                        "  \"$@\"",
                        "}",
                        "",
                        "run_flutter_tool() {",
                        "  local flutter_bin",
                        "  flutter_bin=\"$(resolve_flutter_bin)\"",
                        "  env -u GIT_DIR -u GIT_WORK_TREE -u GIT_INDEX_FILE \"${flutter_bin}\" \"$@\"",
                        "}",
                        "",
                        "is_windows_env() {",
                        "  return 1",
                        "}",
                        "",
                        "make_precommit_temp_dir() {",
                        "  mktemp -d",
                        "}",
                    ]
                )
                + "\n",
                encoding="utf-8",
            )

            (scripts_dir / "select_flutter_test_targets.sh").write_text(
                (
                    "#!/usr/bin/env bash\n"
                    "set -euo pipefail\n"
                    "printf 'integration_test/app_flow_test.dart\\n'"
                ),
                encoding="utf-8",
            )
            self._make_executable(scripts_dir / "select_flutter_test_targets.sh")

            (fake_bin_dir / "flutter").write_text(
                "\n".join(
                    [
                        "#!/usr/bin/env bash",
                        "set -euo pipefail",
                        'repo_root="$(git rev-parse --show-toplevel)"',
                        'printf \'%s\\n\' \"$*\" >> \"${repo_root}/flutter.log\"',
                    ]
                )
                + "\n",
                encoding="utf-8",
            )
            self._make_executable(fake_bin_dir / "flutter")

            (fake_bin_dir / "xvfb-run").write_text(
                "\n".join(
                    [
                        "#!/usr/bin/env bash",
                        "set -euo pipefail",
                        'repo_root="$(git rev-parse --show-toplevel)"',
                        "while [[ $# -gt 0 && \"$1\" == -* ]]; do",
                        "  shift",
                        "done",
                        'printf \'%s\\n\' \"$*\" >> \"${repo_root}/xvfb.log\"',
                        'exec \"$@\"',
                    ]
                )
                + "\n",
                encoding="utf-8",
            )
            self._make_executable(fake_bin_dir / "xvfb-run")

            result = subprocess.run(
                [
                    BASH_BIN or "bash",
                    "scripts/run_flutter_test_shard.sh",
                    "--shard-index",
                    "0",
                    "--shard-count",
                    "1",
                ],
                cwd=repo_root,
                check=False,
                capture_output=True,
                text=True,
                env={
                    **os.environ,
                    "PATH": f"{fake_bin_dir}{os.pathsep}{os.environ.get('PATH', '')}",
                },
            )

            self.assertEqual(result.returncode, 0, msg=result.stdout + result.stderr)
            self.assertEqual(
                (repo_root / "xvfb.log").read_text(encoding="utf-8").splitlines(),
                [
                    f"{(fake_bin_dir / 'flutter').as_posix()} test -d linux --concurrency=1 integration_test/app_flow_test.dart",
                ],
            )
            self.assertEqual(
                (repo_root / "flutter.log").read_text(encoding="utf-8").splitlines(),
                [
                    "test -d linux --concurrency=1 integration_test/app_flow_test.dart",
                ],
            )

    def test_flutter_test_shard_uses_dev_app_id_defaults_for_macos_integration_when_enabled(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            repo_root = Path(temp_dir)
            self._init_repo(repo_root, "main")

            scripts_dir = repo_root / "scripts"
            lib_i18n_dir = repo_root / "lib/i18n"
            fake_bin_dir = repo_root / "fake-bin"
            scripts_dir.mkdir(parents=True, exist_ok=True)
            lib_i18n_dir.mkdir(parents=True, exist_ok=True)
            fake_bin_dir.mkdir(parents=True, exist_ok=True)
            (lib_i18n_dir / "strings.g.dart").write_text("// generated\n", encoding="utf-8")

            shard_script = scripts_dir / "run_flutter_test_shard.sh"
            shard_script.write_text(
                RUN_FLUTTER_TEST_SHARD.read_text(encoding="utf-8"),
                encoding="utf-8",
            )
            self._make_executable(shard_script)

            (scripts_dir / "pre_commit_common.sh").write_text(
                "\n".join(
                    [
                        "die() {",
                        "  echo \"pre-commit: $*\" >&2",
                        "  exit 1",
                        "}",
                        "",
                        f"resolve_flutter_bin() {{ printf '%s\\n' \"{(fake_bin_dir / 'flutter').as_posix()}\"; }}",
                        "",
                        "resolve_default_flutter_test_device() {",
                        "  printf '%s\\n' macos",
                        "}",
                        "",
                        "run_with_periodic_status() {",
                        "  local _label=\"$1\"",
                        "  shift",
                        "  \"$@\"",
                        "}",
                        "",
                        "run_flutter_tool() {",
                        "  local flutter_bin",
                        "  flutter_bin=\"$(resolve_flutter_bin)\"",
                        "  env -u GIT_DIR -u GIT_WORK_TREE -u GIT_INDEX_FILE \"${flutter_bin}\" \"$@\"",
                        "}",
                        "",
                        "is_windows_env() {",
                        "  return 1",
                        "}",
                        "",
                        "make_precommit_temp_dir() {",
                        "  mktemp -d",
                        "}",
                    ]
                )
                + "\n",
                encoding="utf-8",
            )

            (scripts_dir / "select_flutter_test_targets.sh").write_text(
                (
                    "#!/usr/bin/env bash\n"
                    "set -euo pipefail\n"
                    "printf 'integration_test/app_flow_test.dart\\n'"
                ),
                encoding="utf-8",
            )
            self._make_executable(scripts_dir / "select_flutter_test_targets.sh")

            (fake_bin_dir / "flutter").write_text(
                "\n".join(
                    [
                        "#!/usr/bin/env bash",
                        "set -euo pipefail",
                        'repo_root="$(git rev-parse --show-toplevel)"',
                        (
                            'printf \'%s|%s|%s|%s\\n\' '
                            '"${SECONDLOOP_APP_ID-}" "${SECONDLOOP_APP_NAME-}" "$(command -v xcrun)" "$*" '
                            '>> "${repo_root}/flutter.log"'
                        ),
                    ]
                )
                + "\n",
                encoding="utf-8",
            )
            self._make_executable(fake_bin_dir / "flutter")

            result = self._run(
                [
                    "bash",
                    "scripts/run_flutter_test_shard.sh",
                    "--shard-index",
                    "0",
                    "--shard-count",
                    "1",
                ],
                cwd=repo_root,
                env={
                    **os.environ,
                    "SECONDLOOP_ENABLE_MACOS_INTEGRATION_TESTS": "1",
                },
            )

            self.assertEqual(result.returncode, 0, msg=result.stdout + result.stderr)
            lines = (repo_root / "flutter.log").read_text(encoding="utf-8").splitlines()
            self.assertEqual(len(lines), 1)
            self.assertRegex(
                lines[0],
                (
                    r"^com\.secondloop\.secondloopdev\|SecondLoop Dev\|"
                    r".*/secondloop_xcrun\.[^/]+/xcrun\|"
                    r"test -d macos --concurrency=1 integration_test/app_flow_test\.dart$"
                ),
            )

    def test_local_flutter_ci_stops_shards_early_when_gate_fails(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            repo_root = Path(temp_dir)
            self._init_repo(repo_root, "main")

            scripts_dir = repo_root / "scripts"
            hooks_dir = repo_root / ".githooks"
            lib_i18n_dir = repo_root / "lib/i18n"
            test_dir = repo_root / "test"
            scripts_dir.mkdir(parents=True, exist_ok=True)
            hooks_dir.mkdir(parents=True, exist_ok=True)
            lib_i18n_dir.mkdir(parents=True, exist_ok=True)
            test_dir.mkdir(parents=True, exist_ok=True)
            (test_dir / "sample_test.dart").write_text("// stub\n", encoding="utf-8")

            (scripts_dir / "run_flutter_ci_local.sh").write_text(
                RUN_FLUTTER_CI_LOCAL.read_text(encoding="utf-8"),
                encoding="utf-8",
            )
            self._make_executable(scripts_dir / "run_flutter_ci_local.sh")

            (scripts_dir / "pre_commit_common.sh").write_text(
                "\n".join(
                    [
                        "die() {",
                        "  echo \"pre-commit: $*\" >&2",
                        "  exit 1",
                        "}",
                        "",
                        "resolve_dart_bin() {",
                        f"  printf '%s\\n' {TRUE_BIN}",
                        "}",
                        "",
                        "resolve_flutter_bin() {",
                        f"  printf '%s\\n' {TRUE_BIN}",
                        "}",
                        "",
                        "run_with_periodic_status() {",
                        "  local _label=\"$1\"",
                        "  shift",
                        "  \"$@\"",
                        "}",
                        "",
                        "run_flutter_tool() {",
                        "  local flutter_bin",
                        "  flutter_bin=\"$(resolve_flutter_bin)\"",
                        "  env -u GIT_DIR -u GIT_WORK_TREE -u GIT_INDEX_FILE \"${flutter_bin}\" \"$@\"",
                        "}",
                        "",
                        "is_windows_env() {",
                        "  return 1",
                        "}",
                        "",
                        "make_precommit_temp_dir() {",
                        "  mktemp -d",
                        "}",
                    ]
                )
                + "\n",
                encoding="utf-8",
            )

            (scripts_dir / "run_i18n_refresh.sh").write_text(
                "#!/usr/bin/env bash\nset -euo pipefail\nrepo_root=\"$(git rev-parse --show-toplevel)\"\nmkdir -p \"${repo_root}/lib/i18n\"\nprintf '// generated\\n' > \"${repo_root}/lib/i18n/strings.g.dart\"\n",
                encoding="utf-8",
            )
            self._make_executable(scripts_dir / "run_i18n_refresh.sh")

            (scripts_dir / "run_flutter_test_shard.sh").write_text(
                "\n".join(
                    [
                        "#!/usr/bin/env bash",
                        "set -euo pipefail",
                        "sleep 30",
                    ]
                )
                + "\n",
                encoding="utf-8",
            )
            self._make_executable(scripts_dir / "run_flutter_test_shard.sh")

            (hooks_dir / "pre-commit").write_text(
                "#!/usr/bin/env bash\nset -euo pipefail\necho gate-failed >&2\nexit 2\n",
                encoding="utf-8",
            )
            self._make_executable(hooks_dir / "pre-commit")

            self._commit_all(repo_root, "fixture")

            result = subprocess.run(
                [BASH_BIN or "bash", "scripts/run_flutter_ci_local.sh"],
                cwd=repo_root,
                check=False,
                capture_output=True,
                text=True,
                timeout=15,
                env={
                    **os.environ,
                    "SECONDLOOP_LOCAL_FLUTTER_TEST_SHARDS": "2",
                },
            )

            self.assertNotEqual(result.returncode, 0)
            self.assertIn("gate-failed", result.stdout + result.stderr)

    def test_local_flutter_ci_uses_repo_managed_fvm_toolchain_inside_temp_worktrees(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            repo_root = Path(temp_dir)
            self._init_repo(repo_root, "main")

            scripts_dir = repo_root / "scripts"
            hooks_dir = repo_root / ".githooks"
            test_dir = repo_root / "test"
            fvm_bin_dir = repo_root / ".fvm/flutter_sdk/bin"
            scripts_dir.mkdir(parents=True, exist_ok=True)
            hooks_dir.mkdir(parents=True, exist_ok=True)
            test_dir.mkdir(parents=True, exist_ok=True)
            fvm_bin_dir.mkdir(parents=True, exist_ok=True)
            (repo_root / ".gitignore").write_text(".fvm/flutter_sdk\n", encoding="utf-8")

            (test_dir / "sample_test.dart").write_text("// stub\n", encoding="utf-8")

            for source, destination in [
                (PRE_COMMIT_COMMON, scripts_dir / "pre_commit_common.sh"),
                (RUN_FLUTTER_CI_LOCAL, scripts_dir / "run_flutter_ci_local.sh"),
                (RUN_FLUTTER_TEST_SHARD, scripts_dir / "run_flutter_test_shard.sh"),
                (RUN_I18N_REFRESH, scripts_dir / "run_i18n_refresh.sh"),
                (SELECT_FLUTTER_TEST_TARGETS, scripts_dir / "select_flutter_test_targets.sh"),
            ]:
                destination.write_text(source.read_text(encoding="utf-8"), encoding="utf-8")
                self._make_executable(destination)
            (scripts_dir / "pre_commit_common.sh").write_text(
                (scripts_dir / "pre_commit_common.sh").read_text(encoding="utf-8")
                + "\n"
                + "is_windows_env() {\n"
                + "  return 1\n"
                + "}\n",
                encoding="utf-8",
            )

            (fvm_bin_dir / "dart").write_text(
                "\n".join(
                    [
                        "#!/usr/bin/env bash",
                        "set -euo pipefail",
                        'repo_root="$(git rev-parse --show-toplevel)"',
                        f'printf \'%s|%s\\n\' "$repo_root" "$*" >> "{(repo_root / ".git/dart-invocations.log").as_posix()}"',
                        'mkdir -p "${repo_root}/lib/i18n"',
                        'printf \'// generated by fake dart\\n\' > "${repo_root}/lib/i18n/strings.g.dart"',
                    ]
                )
                + "\n",
                encoding="utf-8",
            )
            self._make_executable(fvm_bin_dir / "dart")

            (fvm_bin_dir / "flutter").write_text(
                "\n".join(
                    [
                        "#!/usr/bin/env bash",
                        "set -euo pipefail",
                        'repo_root="$(git rev-parse --show-toplevel)"',
                        f'printf \'%s|%s\\n\' "$repo_root" "$*" >> "{(repo_root / ".git/flutter-invocations.log").as_posix()}"',
                    ]
                )
                + "\n",
                encoding="utf-8",
            )
            self._make_executable(fvm_bin_dir / "flutter")

            (hooks_dir / "pre-commit").write_text(
                "#!/usr/bin/env bash\nset -euo pipefail\nexit 0\n",
                encoding="utf-8",
            )
            self._make_executable(hooks_dir / "pre-commit")

            self._commit_all(repo_root, "fixture")

            result = subprocess.run(
                [BASH_BIN or "bash", "scripts/run_flutter_ci_local.sh"],
                cwd=repo_root,
                check=False,
                capture_output=True,
                text=True,
                env={
                    **os.environ,
                    "PATH": "/usr/bin:/bin",
                    "SECONDLOOP_LOCAL_FLUTTER_TEST_SHARDS": "2",
                },
            )

            self.assertEqual(result.returncode, 0, msg=result.stdout + result.stderr)

            if (repo_root / ".git/dart-invocations.log").exists():
                dart_invocations = (repo_root / ".git/dart-invocations.log").read_text(
                    encoding="utf-8"
                ).splitlines()
                self.assertTrue(dart_invocations)
                self.assertTrue(
                    all(not line.startswith(f"{repo_root.as_posix()}|") for line in dart_invocations)
                )

            if (repo_root / ".git/flutter-invocations.log").exists():
                flutter_invocations = (
                    repo_root / ".git/flutter-invocations.log"
                ).read_text(encoding="utf-8").splitlines()
                self.assertGreaterEqual(len(flutter_invocations), 3)
                self.assertTrue(any(line.endswith("|pub get") for line in flutter_invocations))
                self.assertTrue(any("test --concurrency=1 test/sample_test.dart" in line for line in flutter_invocations))
                self.assertTrue(
                    all(not line.startswith(f"{repo_root.as_posix()}|") for line in flutter_invocations)
                )
            self.assertFalse((repo_root / "lib/i18n/strings.g.dart").exists())

    def test_flutter_test_shard_accepts_explicit_flutter_bin_override(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            repo_root = Path(temp_dir)
            self._init_repo(repo_root, "main")

            scripts_dir = repo_root / "scripts"
            test_dir = repo_root / "test"
            scripts_dir.mkdir(parents=True, exist_ok=True)
            test_dir.mkdir(parents=True, exist_ok=True)
            (repo_root / ".gitignore").write_text(".fvm/flutter_sdk\n", encoding="utf-8")

            for source, destination in [
                (PRE_COMMIT_COMMON, scripts_dir / "pre_commit_common.sh"),
                (RUN_FLUTTER_TEST_SHARD, scripts_dir / "run_flutter_test_shard.sh"),
                (SELECT_FLUTTER_TEST_TARGETS, scripts_dir / "select_flutter_test_targets.sh"),
            ]:
                destination.write_text(source.read_text(encoding="utf-8"), encoding="utf-8")
                self._make_executable(destination)
            (scripts_dir / "pre_commit_common.sh").write_text(
                (scripts_dir / "pre_commit_common.sh").read_text(encoding="utf-8")
                + "\n"
                + "is_windows_env() {\n"
                + "  return 1\n"
                + "}\n",
                encoding="utf-8",
            )

            (repo_root / "lib/i18n").mkdir(parents=True, exist_ok=True)
            (repo_root / "lib/i18n/strings.g.dart").write_text(
                "// generated\n",
                encoding="utf-8",
            )
            (test_dir / "sample_test.dart").write_text("// stub\n", encoding="utf-8")

            override_bin = repo_root / "fake-bin/flutter"
            override_log = repo_root / "flutter-override.log"
            override_bin.parent.mkdir(parents=True, exist_ok=True)
            override_bin.write_text(
                "\n".join(
                    [
                        "#!/usr/bin/env bash",
                        "set -euo pipefail",
                        f'printf \'%s\\n\' "$*" > "{override_log.as_posix()}"',
                    ]
                )
                + "\n",
                encoding="utf-8",
            )
            self._make_executable(override_bin)

            self._commit_all(repo_root, "fixture")

            worktree_parent = Path(tempfile.mkdtemp(prefix="secondloop-shard-worktree-"))
            worktree_root = worktree_parent / "checkout"
            add_worktree = self._run(
                ["git", "worktree", "add", "--detach", worktree_root.as_posix(), "HEAD"],
                cwd=repo_root,
            )
            self.assertEqual(add_worktree.returncode, 0, msg=add_worktree.stderr)

            try:
                result = subprocess.run(
                    [
                        BASH_BIN or "bash",
                        "scripts/run_flutter_test_shard.sh",
                        "--shard-index",
                        "0",
                        "--shard-count",
                        "1",
                    ],
                    cwd=worktree_root,
                    check=False,
                    capture_output=True,
                    text=True,
                    timeout=3,
                    env={
                        **os.environ,
                        "PATH": "/usr/bin:/bin",
                        "SECONDLOOP_FLUTTER_BIN": override_bin.as_posix(),
                    },
                )
            finally:
                shutil.rmtree(worktree_parent, ignore_errors=True)

            self.assertEqual(result.returncode, 0, msg=result.stdout + result.stderr)
            if override_log.exists():
                self.assertIn(
                    "test --concurrency=1 test/sample_test.dart",
                    override_log.read_text(encoding="utf-8"),
                )

    def test_local_flutter_web_ci_runs_smoke_tests_and_build_in_temp_worktree(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            repo_root = Path(temp_dir)
            self._init_repo(repo_root, "main")

            scripts_dir = repo_root / "scripts"
            test_web_dir = repo_root / "test/web_app"
            fvm_bin_dir = repo_root / ".fvm/flutter_sdk/bin"
            scripts_dir.mkdir(parents=True, exist_ok=True)
            test_web_dir.mkdir(parents=True, exist_ok=True)
            fvm_bin_dir.mkdir(parents=True, exist_ok=True)
            (repo_root / ".gitignore").write_text(".fvm/flutter_sdk\n", encoding="utf-8")

            for source, destination in [
                (PRE_COMMIT_COMMON, scripts_dir / "pre_commit_common.sh"),
                (RUN_FLUTTER_WEB_CI_LOCAL, scripts_dir / "run_flutter_web_ci_local.sh"),
            ]:
                destination.write_text(source.read_text(encoding="utf-8"), encoding="utf-8")
                self._make_executable(destination)

            (test_web_dir / "web_app_gate_test.dart").write_text("// stub\n", encoding="utf-8")
            (test_web_dir / "web_app_service_http_test.dart").write_text("// stub\n", encoding="utf-8")

            (fvm_bin_dir / "dart").write_text(
                "#!/usr/bin/env bash\nset -euo pipefail\nexit 0\n",
                encoding="utf-8",
            )
            self._make_executable(fvm_bin_dir / "dart")

            (fvm_bin_dir / "flutter").write_text(
                "\n".join(
                    [
                        "#!/usr/bin/env bash",
                        "set -euo pipefail",
                        'repo_root="$(git rev-parse --show-toplevel)"',
                        f'printf \'%s|%s\\n\' "$repo_root" "$*" >> "{(repo_root / ".git/flutter-web.log").as_posix()}"',
                        'if [[ "$1" == "pub" && "${2:-}" == "get" ]]; then',
                        '  mkdir -p "${repo_root}/.dart_tool"',
                        '  printf \'{}\\n\' > "${repo_root}/.dart_tool/package_config.json"',
                        "fi",
                    ]
                )
                + "\n",
                encoding="utf-8",
            )
            self._make_executable(fvm_bin_dir / "flutter")

            (scripts_dir / "run_i18n_refresh.sh").write_text(
                "\n".join(
                    [
                        "#!/usr/bin/env bash",
                        "set -euo pipefail",
                        'repo_root="$(git rev-parse --show-toplevel)"',
                        'mkdir -p "${repo_root}/lib/i18n"',
                        'printf \'// generated\\n\' > "${repo_root}/lib/i18n/strings.g.dart"',
                        f'printf \'%s\\n\' "${{repo_root}}" >> "{(repo_root / ".git/flutter-web-i18n.log").as_posix()}"',
                    ]
                )
                + "\n",
                encoding="utf-8",
            )
            self._make_executable(scripts_dir / "run_i18n_refresh.sh")

            self._commit_all(repo_root, "fixture")

            result = subprocess.run(
                [BASH_BIN or "bash", "scripts/run_flutter_web_ci_local.sh"],
                cwd=repo_root,
                check=False,
                capture_output=True,
                text=True,
                env={
                    **os.environ,
                    "PATH": "/usr/bin:/bin",
                },
            )

            self.assertEqual(result.returncode, 0, msg=result.stdout + result.stderr)

            if (repo_root / ".git/flutter-web.log").exists():
                flutter_invocations = (repo_root / ".git/flutter-web.log").read_text(
                    encoding="utf-8"
                ).splitlines()
                self.assertTrue(any(line.endswith("|pub get") for line in flutter_invocations))
                self.assertTrue(
                    any(
                        "test test/web_app/web_app_gate_test.dart test/web_app/web_app_service_http_test.dart"
                        in line
                        for line in flutter_invocations
                    )
                )
                self.assertTrue(any("build web --base-href /app/" in line for line in flutter_invocations))
                self.assertTrue(all(not line.startswith(f"{repo_root.as_posix()}|") for line in flutter_invocations))
            if (repo_root / ".git/flutter-web-i18n.log").exists():
                i18n_invocations = (repo_root / ".git/flutter-web-i18n.log").read_text(
                    encoding="utf-8"
                ).splitlines()
                self.assertTrue(all(path != repo_root.as_posix() for path in i18n_invocations))
            self.assertFalse((repo_root / "lib/i18n/strings.g.dart").exists())


if __name__ == "__main__":
    unittest.main()
