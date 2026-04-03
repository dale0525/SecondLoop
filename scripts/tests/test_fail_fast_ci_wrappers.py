from __future__ import annotations

from pathlib import Path
import os
import shutil
import stat
import subprocess
import tempfile
import time
import unittest


REPO_ROOT = Path(__file__).resolve().parents[2]
RUN_FULL_CI_PARALLEL = REPO_ROOT / "scripts/run_full_ci_parallel.sh"
RUN_FULL_RUST_CI_LOCAL = REPO_ROOT / "scripts/run_full_rust_ci_local.sh"
RUN_FLUTTER_CI_LOCAL = REPO_ROOT / "scripts/run_flutter_ci_local.sh"
RUN_PYTHON_TOOLING_CHECKS = REPO_ROOT / "scripts/run_python_tooling_checks.sh"


@unittest.skipUnless(shutil.which("bash"), "bash is required")
@unittest.skipUnless(shutil.which("git"), "git is required")
class FailFastCiWrapperTests(unittest.TestCase):
    def _run(
        self,
        args: list[str],
        *,
        cwd: Path,
        env: dict[str, str] | None = None,
        timeout: float | None = None,
    ) -> subprocess.CompletedProcess[str]:
        return subprocess.run(
            args,
            cwd=cwd,
            check=False,
            capture_output=True,
            text=True,
            env=env,
            timeout=timeout,
        )

    def _make_executable(self, path: Path) -> None:
        path.chmod(path.stat().st_mode | stat.S_IXUSR)

    def _init_repo(self, repo_root: Path) -> None:
        self._run(["git", "init", "-b", "main"], cwd=repo_root)
        self._run(["git", "config", "user.name", "Test User"], cwd=repo_root)
        self._run(["git", "config", "user.email", "test@example.com"], cwd=repo_root)

    def _commit_all(self, repo_root: Path, message: str) -> None:
        self._run(["git", "add", "-A"], cwd=repo_root)
        result = self._run(["git", "commit", "-m", message], cwd=repo_root)
        self.assertEqual(result.returncode, 0, msg=result.stderr)

    def _write_script(self, path: Path, contents: str) -> None:
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(contents, encoding="utf-8")
        self._make_executable(path)

    def test_parallel_ci_wrapper_stops_other_scopes_after_first_failure(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            repo_root = Path(temp_dir)
            self._init_repo(repo_root)

            scripts_dir = repo_root / "scripts"
            marker_dir = repo_root / "markers"
            marker_dir.mkdir(parents=True, exist_ok=True)

            self._write_script(
                scripts_dir / "run_full_ci_parallel.sh",
                RUN_FULL_CI_PARALLEL.read_text(encoding="utf-8"),
            )
            self._write_script(
                scripts_dir / "run_flutter_ci_local.sh",
                "\n".join(
                    [
                        "#!/usr/bin/env bash",
                        "set -euo pipefail",
                        "echo failing-flutter",
                        "exit 23",
                    ]
                )
                + "\n",
            )
            for relative_path, marker_name in [
                ("scripts/run_full_rust_ci_local.sh", "rust-cancelled"),
                ("scripts/run_python_tooling_checks.sh", "python-cancelled"),
            ]:
                self._write_script(
                    repo_root / relative_path,
                    "\n".join(
                        [
                            "#!/usr/bin/env bash",
                            "set -euo pipefail",
                            f"marker_file=\"{(marker_dir / marker_name).as_posix()}\"",
                            "cleanup() {",
                            "  printf 'cancelled\\n' > \"${marker_file}\"",
                            "  exit 0",
                            "}",
                            "trap cleanup TERM INT",
                            "sleep 30 &",
                            "wait $!",
                        ]
                    )
                    + "\n",
                )

            self._commit_all(repo_root, "fixture")

            start = time.monotonic()
            result = self._run(
                ["bash", "scripts/run_full_ci_parallel.sh"],
                cwd=repo_root,
                timeout=5,
            )
            elapsed = time.monotonic() - start

            self.assertNotEqual(result.returncode, 0, msg=result.stdout + result.stderr)
            self.assertLess(elapsed, 5, msg=result.stdout + result.stderr)
            self.assertTrue((marker_dir / "rust-cancelled").exists(), msg=result.stdout + result.stderr)
            self.assertTrue((marker_dir / "python-cancelled").exists(), msg=result.stdout + result.stderr)
            self.assertIn("failing-flutter", result.stdout)

    def test_local_rust_ci_wrapper_does_not_start_nextest_after_gate_failure(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            repo_root = Path(temp_dir)
            self._init_repo(repo_root)

            scripts_dir = repo_root / "scripts"
            hooks_dir = repo_root / ".githooks"
            marker_dir = repo_root / "markers"
            marker_dir.mkdir(parents=True, exist_ok=True)

            self._write_script(
                scripts_dir / "run_full_rust_ci_local.sh",
                RUN_FULL_RUST_CI_LOCAL.read_text(encoding="utf-8"),
            )
            self._write_script(
                hooks_dir / "pre-commit",
                "\n".join(
                    [
                        "#!/usr/bin/env bash",
                        "set -euo pipefail",
                        "echo failing-clippy",
                        "exit 17",
                    ]
                )
                + "\n",
            )
            self._write_script(
                scripts_dir / "pre_commit_common.sh",
                "#!/usr/bin/env bash\nset -euo pipefail\n",
            )
            self._write_script(
                scripts_dir / "run_rust_ci_nextest.sh",
                "\n".join(
                    [
                        "#!/usr/bin/env bash",
                        "set -euo pipefail",
                        f"printf 'started\\n' > \"{(marker_dir / 'nextest-started').as_posix()}\"",
                    ]
                )
                + "\n",
            )

            self._commit_all(repo_root, "fixture")

            start = time.monotonic()
            result = self._run(
                ["bash", "scripts/run_full_rust_ci_local.sh"],
                cwd=repo_root,
                timeout=5,
            )
            elapsed = time.monotonic() - start

            self.assertNotEqual(result.returncode, 0, msg=result.stdout + result.stderr)
            self.assertLess(elapsed, 5, msg=result.stdout + result.stderr)
            self.assertFalse((marker_dir / "nextest-started").exists(), msg=result.stdout + result.stderr)
            self.assertIn("failing-clippy", result.stdout)

    def test_local_rust_ci_wrapper_keeps_rustfmt_in_gate_while_skipping_duplicate_tests(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            repo_root = Path(temp_dir)
            self._init_repo(repo_root)

            scripts_dir = repo_root / "scripts"
            hooks_dir = repo_root / ".githooks"
            marker_dir = repo_root / "markers"
            marker_dir.mkdir(parents=True, exist_ok=True)

            self._write_script(
                scripts_dir / "run_full_rust_ci_local.sh",
                RUN_FULL_RUST_CI_LOCAL.read_text(encoding="utf-8"),
            )
            self._write_script(
                hooks_dir / "pre-commit",
                "\n".join(
                    [
                        "#!/usr/bin/env bash",
                        "set -euo pipefail",
                        f"printf '%s\\n' \"$*\" > \"{(marker_dir / 'gate-args.txt').as_posix()}\"",
                    ]
                )
                + "\n",
            )
            self._write_script(
                scripts_dir / "pre_commit_common.sh",
                "#!/usr/bin/env bash\nset -euo pipefail\n",
            )
            self._write_script(
                scripts_dir / "run_rust_ci_nextest.sh",
                "\n".join(
                    [
                        "#!/usr/bin/env bash",
                        "set -euo pipefail",
                        f"printf 'started\\n' > \"{(marker_dir / 'nextest-started').as_posix()}\"",
                    ]
                )
                + "\n",
            )

            self._commit_all(repo_root, "fixture")

            result = self._run(
                ["bash", "scripts/run_full_rust_ci_local.sh"],
                cwd=repo_root,
                timeout=5,
            )

            self.assertEqual(result.returncode, 0, msg=result.stdout + result.stderr)
            self.assertTrue((marker_dir / "nextest-started").exists(), msg=result.stdout + result.stderr)

            gate_args = (marker_dir / "gate-args.txt").read_text(encoding="utf-8")
            self.assertIn("--check --rust --ci --skip-tests", gate_args)
            self.assertNotIn("--clippy-only", gate_args)

    def test_local_flutter_ci_wrapper_stops_remaining_shards_after_first_failure(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            repo_root = Path(temp_dir)
            self._init_repo(repo_root)

            scripts_dir = repo_root / "scripts"
            hooks_dir = repo_root / ".githooks"
            marker_dir = repo_root / "markers"
            test_dir = repo_root / "test"
            lib_i18n_dir = repo_root / "lib/i18n"
            marker_dir.mkdir(parents=True, exist_ok=True)
            test_dir.mkdir(parents=True, exist_ok=True)
            lib_i18n_dir.mkdir(parents=True, exist_ok=True)
            (test_dir / "sample_test.dart").write_text("// stub\n", encoding="utf-8")

            self._write_script(
                scripts_dir / "run_flutter_ci_local.sh",
                RUN_FLUTTER_CI_LOCAL.read_text(encoding="utf-8"),
            )
            self._write_script(
                scripts_dir / "pre_commit_common.sh",
                "\n".join(
                    [
                        "#!/usr/bin/env bash",
                        "set -euo pipefail",
                        "die() {",
                        "  echo \"pre-commit: $*\" >&2",
                        "  exit 1",
                        "}",
                        "resolve_dart_bin() {",
                        "  printf '%s\\n' /bin/true",
                        "}",
                        "resolve_flutter_bin() {",
                        "  printf '%s\\n' /bin/true",
                        "}",
                        "run_with_periodic_status() {",
                        "  local _label=\"$1\"",
                        "  shift",
                        "  \"$@\"",
                        "}",
                        "run_flutter_tool() {",
                        "  return 0",
                        "}",
                    ]
                )
                + "\n",
            )
            self._write_script(
                scripts_dir / "run_i18n_refresh.sh",
                "\n".join(
                    [
                        "#!/usr/bin/env bash",
                        "set -euo pipefail",
                        "repo_root=\"$(git rev-parse --show-toplevel)\"",
                        "mkdir -p \"${repo_root}/lib/i18n\"",
                        "printf '// generated\\n' > \"${repo_root}/lib/i18n/strings.g.dart\"",
                    ]
                )
                + "\n",
            )
            self._write_script(
                scripts_dir / "run_flutter_test_shard.sh",
                "\n".join(
                    [
                        "#!/usr/bin/env bash",
                        "set -euo pipefail",
                        "shard_index=''",
                        "while [[ $# -gt 0 ]]; do",
                        "  case \"$1\" in",
                        "    --shard-index)",
                        "      shard_index=\"$2\"",
                        "      shift 2",
                        "      ;;",
                        "    --shard-count)",
                        "      shift 2",
                        "      ;;",
                        "    *)",
                        "      shift",
                        "      ;;",
                        "  esac",
                        "done",
                        "if [[ \"${shard_index}\" == \"0\" ]]; then",
                        "  echo failing-shard-0",
                        "  exit 19",
                        "fi",
                        f"completion_file=\"{(marker_dir / 'flutter-shard-completed').as_posix()}\"",
                        "cleanup() {",
                        "  exit 0",
                        "}",
                        "trap cleanup TERM INT",
                        "sleep 30 &",
                        "wait $!",
                        "printf 'completed\\n' > \"${completion_file}\"",
                    ]
                )
                + "\n",
            )
            self._write_script(
                hooks_dir / "pre-commit",
                "#!/usr/bin/env bash\nset -euo pipefail\nexit 0\n",
            )

            self._commit_all(repo_root, "fixture")

            start = time.monotonic()
            result = self._run(
                ["bash", "scripts/run_flutter_ci_local.sh"],
                cwd=repo_root,
                timeout=5,
                env={
                    **os.environ,
                    "SECONDLOOP_LOCAL_FLUTTER_TEST_SHARDS": "2",
                },
            )
            elapsed = time.monotonic() - start

            self.assertNotEqual(result.returncode, 0, msg=result.stdout + result.stderr)
            self.assertLess(elapsed, 5, msg=result.stdout + result.stderr)
            self.assertFalse((marker_dir / "flutter-shard-completed").exists(), msg=result.stdout + result.stderr)
            self.assertIn("failing-shard-0", result.stdout)
            self.assertIn("cancelling Flutter shard 1/2 after shard 0 failure", result.stderr)

    def test_python_tooling_wrapper_strips_git_hook_environment(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            repo_root = Path(temp_dir)
            self._init_repo(repo_root)

            scripts_dir = repo_root / "scripts"
            marker_dir = repo_root / "markers"
            marker_dir.mkdir(parents=True, exist_ok=True)

            self._write_script(
                scripts_dir / "run_python_tooling_checks.sh",
                RUN_PYTHON_TOOLING_CHECKS.read_text(encoding="utf-8"),
            )
            self._write_script(
                scripts_dir / "pre_commit_common.sh",
                "\n".join(
                    [
                        "#!/usr/bin/env bash",
                        "set -euo pipefail",
                        "die() {",
                        "  echo \"pre-commit: $*\" >&2",
                        "  exit 1",
                        "}",
                        f"resolve_python_bin() {{ printf '%s\\n' \"{(repo_root / 'fake-python').as_posix()}\"; }}",
                        "run_with_periodic_status() {",
                        "  local _label=\"$1\"",
                        "  shift",
                        "  \"$@\"",
                        "}",
                    ]
                )
                + "\n",
            )
            self._write_script(
                repo_root / "fake-python",
                "\n".join(
                    [
                        "#!/usr/bin/env bash",
                        "set -euo pipefail",
                        f"marker_file=\"{(marker_dir / 'git-env.txt').as_posix()}\"",
                        "printf 'GIT_DIR=%s\\n' \"${GIT_DIR:-}\" > \"${marker_file}\"",
                        "printf 'GIT_WORK_TREE=%s\\n' \"${GIT_WORK_TREE:-}\" >> \"${marker_file}\"",
                        "printf 'GIT_INDEX_FILE=%s\\n' \"${GIT_INDEX_FILE:-}\" >> \"${marker_file}\"",
                        "printf 'GIT_COMMON_DIR=%s\\n' \"${GIT_COMMON_DIR:-}\" >> \"${marker_file}\"",
                    ]
                )
                + "\n",
            )

            self._commit_all(repo_root, "fixture")
            git_dir = self._run(["git", "rev-parse", "--git-dir"], cwd=repo_root)
            self.assertEqual(git_dir.returncode, 0, msg=git_dir.stderr)
            git_common_dir = self._run(["git", "rev-parse", "--git-common-dir"], cwd=repo_root)
            self.assertEqual(git_common_dir.returncode, 0, msg=git_common_dir.stderr)

            result = self._run(
                ["bash", "scripts/run_python_tooling_checks.sh"],
                cwd=repo_root,
                env={
                    **os.environ,
                    "GIT_DIR": git_dir.stdout.strip(),
                    "GIT_WORK_TREE": repo_root.as_posix(),
                    "GIT_INDEX_FILE": "/tmp/hook-index",
                    "GIT_COMMON_DIR": git_common_dir.stdout.strip(),
                },
            )

            self.assertEqual(result.returncode, 0, msg=result.stdout + result.stderr)
            env_log = (marker_dir / "git-env.txt").read_text(encoding="utf-8")
            self.assertEqual(
                env_log,
                "GIT_DIR=\nGIT_WORK_TREE=\nGIT_INDEX_FILE=\nGIT_COMMON_DIR=\n",
            )


if __name__ == "__main__":
    unittest.main()
