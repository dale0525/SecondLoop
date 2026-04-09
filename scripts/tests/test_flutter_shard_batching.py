from __future__ import annotations

from pathlib import Path
import os
import shutil
import stat
import subprocess
import tempfile
import unittest


REPO_ROOT = Path(__file__).resolve().parents[2]
RUN_FLUTTER_TEST_SHARD = REPO_ROOT / "scripts/run_flutter_test_shard.sh"


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


@unittest.skipUnless(BASH_BIN, "bash is required")
@unittest.skipUnless(shutil.which("git"), "git is required")
class FlutterShardBatchingTests(unittest.TestCase):
    def _run(
        self,
        args: list[str],
        *,
        cwd: Path,
        env: dict[str, str] | None = None,
    ) -> subprocess.CompletedProcess[str]:
        resolved_args = list(args)
        if resolved_args and resolved_args[0] == "bash":
            resolved_args[0] = BASH_BIN or "bash"
        return subprocess.run(
            resolved_args,
            cwd=cwd,
            check=False,
            capture_output=True,
            text=True,
            env=env,
        )

    def _make_executable(self, path: Path) -> None:
        path.chmod(path.stat().st_mode | stat.S_IXUSR)

    def _init_repo(self, repo_root: Path) -> None:
        self._run(["git", "init", "-b", "main"], cwd=repo_root)
        self._run(["git", "config", "user.name", "Test User"], cwd=repo_root)
        self._run(["git", "config", "user.email", "test@example.com"], cwd=repo_root)

    def test_flutter_test_shard_honors_batch_target_limit_override(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            repo_root = Path(temp_dir)
            self._init_repo(repo_root)

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
                    "test/unit_b_test.dart\\n"
                    "test/unit_c_test.dart\\n'"
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
                    "SECONDLOOP_FLUTTER_TEST_MAX_BATCH_TARGETS": "2",
                },
            )

            self.assertEqual(result.returncode, 0, msg=result.stdout + result.stderr)
            self.assertEqual(
                (repo_root / "flutter.log").read_text(encoding="utf-8").splitlines(),
                [
                    "test --concurrency=1 test/unit_a_test.dart test/unit_b_test.dart",
                    "test --concurrency=1 test/unit_c_test.dart",
                ],
            )
