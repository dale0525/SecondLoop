from __future__ import annotations

from pathlib import Path
import os
import shutil
import stat
import subprocess
import tempfile
import unittest


REPO_ROOT = Path(__file__).resolve().parents[2]
PRE_PUSH_HOOK = REPO_ROOT / ".githooks/pre-push"
PRE_COMMIT_COMMON = REPO_ROOT / "scripts/pre_commit_common.sh"
RUN_FLUTTER_CI_LOCAL = REPO_ROOT / "scripts/run_flutter_ci_local.sh"
RUN_FLUTTER_TEST_SHARD = REPO_ROOT / "scripts/run_flutter_test_shard.sh"
RUN_I18N_REFRESH = REPO_ROOT / "scripts/run_i18n_refresh.sh"
RUN_RUST_BUILDER_PACKAGE_TESTS = REPO_ROOT / "scripts/run_rust_builder_package_tests.sh"
SELECT_FLUTTER_TEST_TARGETS = REPO_ROOT / "scripts/select_flutter_test_targets.sh"


@unittest.skipUnless(shutil.which("bash"), "bash is required")
@unittest.skipUnless(shutil.which("git"), "git is required")
class ScopedCiScriptBehaviorTests(unittest.TestCase):
    def _run(self, args: list[str], *, cwd: Path, input_text: str | None = None) -> subprocess.CompletedProcess[str]:
        return subprocess.run(
            args,
            cwd=cwd,
            input=input_text,
            check=False,
            capture_output=True,
            text=True,
        )

    def _make_executable(self, path: Path) -> None:
        path.chmod(path.stat().st_mode | stat.S_IXUSR)

    def _init_repo(self, repo_root: Path, default_branch: str) -> None:
        self._run(["git", "init", "-b", default_branch], cwd=repo_root)
        self._run(["git", "config", "user.name", "Test User"], cwd=repo_root)
        self._run(["git", "config", "user.email", "test@example.com"], cwd=repo_root)

    def _commit_file(self, repo_root: Path, relative_path: str, contents: str, message: str) -> None:
        target = repo_root / relative_path
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text(contents, encoding="utf-8")
        self._run(["git", "add", relative_path], cwd=repo_root)
        result = self._run(["git", "commit", "-m", message], cwd=repo_root)
        self.assertEqual(result.returncode, 0, msg=result.stderr)

    def _commit_all(self, repo_root: Path, message: str) -> None:
        self._run(["git", "add", "-A"], cwd=repo_root)
        result = self._run(["git", "commit", "-m", message], cwd=repo_root)
        self.assertEqual(result.returncode, 0, msg=result.stderr)

    def _write_pre_push_fixture_scripts(self, repo_root: Path) -> None:
        scripts_dir = repo_root / "scripts"
        hooks_dir = repo_root / ".githooks"
        scripts_dir.mkdir(parents=True, exist_ok=True)
        hooks_dir.mkdir(parents=True, exist_ok=True)

        hook_path = hooks_dir / "pre-push"
        hook_path.write_text(PRE_PUSH_HOOK.read_text(encoding="utf-8"), encoding="utf-8")
        self._make_executable(hook_path)

        for relative_path, marker in [
            ("scripts/run_full_ci_parallel.sh", "full"),
            ("scripts/run_python_tooling_checks.sh", "tooling"),
        ]:
            script_path = repo_root / relative_path
            script_path.write_text(
                "\n".join(
                    [
                        "#!/usr/bin/env bash",
                        "set -euo pipefail",
                        f"printf '%s\\n' '{marker}' >> \"{repo_root / 'hook.log'}\"",
                    ]
                )
                + "\n",
                encoding="utf-8",
            )
            self._make_executable(script_path)

    def test_pre_push_uses_local_main_merge_base_when_origin_main_is_missing(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            repo_root = Path(temp_dir)
            self._init_repo(repo_root, "main")
            self._write_pre_push_fixture_scripts(repo_root)

            self._commit_file(repo_root, "README.md", "base\n", "base")

            result = self._run(["git", "checkout", "-b", "feature"], cwd=repo_root)
            self.assertEqual(result.returncode, 0, msg=result.stderr)

            self._commit_file(repo_root, "lib/app.dart", "void main() {}\n", "app change")
            self._commit_file(repo_root, "tools/helper.py", "print('tooling')\n", "tooling change")

            head_sha = self._run(["git", "rev-parse", "HEAD"], cwd=repo_root)
            self.assertEqual(head_sha.returncode, 0, msg=head_sha.stderr)

            result = self._run(
                ["bash", ".githooks/pre-push"],
                cwd=repo_root,
                input_text=f"refs/heads/feature {head_sha.stdout.strip()} refs/heads/feature {'0' * 40}\n",
            )

            self.assertEqual(result.returncode, 0, msg=result.stderr)
            self.assertEqual((repo_root / "hook.log").read_text(encoding="utf-8").strip(), "full")

    def test_pre_push_falls_back_to_full_verification_without_any_main_reference(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            repo_root = Path(temp_dir)
            self._init_repo(repo_root, "trunk")
            self._write_pre_push_fixture_scripts(repo_root)

            self._commit_file(repo_root, "README.md", "base\n", "base")

            result = self._run(["git", "checkout", "-b", "feature"], cwd=repo_root)
            self.assertEqual(result.returncode, 0, msg=result.stderr)

            self._commit_file(repo_root, "lib/app.dart", "void main() {}\n", "app change")
            self._commit_file(repo_root, "tools/helper.py", "print('tooling')\n", "tooling change")

            head_sha = self._run(["git", "rev-parse", "HEAD"], cwd=repo_root)
            self.assertEqual(head_sha.returncode, 0, msg=head_sha.stderr)

            result = self._run(
                ["bash", ".githooks/pre-push"],
                cwd=repo_root,
                input_text=f"refs/heads/feature {head_sha.stdout.strip()} refs/heads/feature {'0' * 40}\n",
            )

            self.assertEqual(result.returncode, 0, msg=result.stderr)
            self.assertEqual((repo_root / "hook.log").read_text(encoding="utf-8").strip(), "full")

    def test_pre_push_runs_full_verification_for_third_party_flutter_dependency_changes(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            repo_root = Path(temp_dir)
            self._init_repo(repo_root, "main")
            self._write_pre_push_fixture_scripts(repo_root)

            self._commit_file(repo_root, "README.md", "base\n", "base")

            result = self._run(["git", "checkout", "-b", "feature"], cwd=repo_root)
            self.assertEqual(result.returncode, 0, msg=result.stderr)

            self._commit_file(
                repo_root,
                "third_party/just_audio_windows_patched/lib/src/helper.dart",
                "void helper() {}\n",
                "third party change",
            )

            head_sha = self._run(["git", "rev-parse", "HEAD"], cwd=repo_root)
            self.assertEqual(head_sha.returncode, 0, msg=head_sha.stderr)

            result = self._run(
                ["bash", ".githooks/pre-push"],
                cwd=repo_root,
                input_text=f"refs/heads/feature {head_sha.stdout.strip()} refs/heads/feature {'0' * 40}\n",
            )

            self.assertEqual(result.returncode, 0, msg=result.stderr)
            self.assertEqual((repo_root / "hook.log").read_text(encoding="utf-8").strip(), "full")

    def test_pre_push_runs_full_verification_for_flutter_asset_changes(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            repo_root = Path(temp_dir)
            self._init_repo(repo_root, "main")
            self._write_pre_push_fixture_scripts(repo_root)

            self._commit_file(repo_root, "README.md", "base\n", "base")

            result = self._run(["git", "checkout", "-b", "feature"], cwd=repo_root)
            self.assertEqual(result.returncode, 0, msg=result.stderr)

            self._commit_file(
                repo_root,
                "assets/icon/app_icon.png",
                "png-stub\n",
                "asset change",
            )

            head_sha = self._run(["git", "rev-parse", "HEAD"], cwd=repo_root)
            self.assertEqual(head_sha.returncode, 0, msg=head_sha.stderr)

            result = self._run(
                ["bash", ".githooks/pre-push"],
                cwd=repo_root,
                input_text=f"refs/heads/feature {head_sha.stdout.strip()} refs/heads/feature {'0' * 40}\n",
            )

            self.assertEqual(result.returncode, 0, msg=result.stderr)
            self.assertEqual((repo_root / "hook.log").read_text(encoding="utf-8").strip(), "full")

    def test_pre_push_skips_verification_for_delete_only_updates(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            repo_root = Path(temp_dir)
            self._init_repo(repo_root, "main")
            self._write_pre_push_fixture_scripts(repo_root)

            self._commit_file(repo_root, "README.md", "base\n", "base")

            remote_sha = self._run(["git", "rev-parse", "HEAD"], cwd=repo_root)
            self.assertEqual(remote_sha.returncode, 0, msg=remote_sha.stderr)

            result = self._run(
                ["bash", ".githooks/pre-push"],
                cwd=repo_root,
                input_text=f"(delete) {'0' * 40} refs/heads/feature {remote_sha.stdout.strip()}\n",
            )

            self.assertEqual(result.returncode, 0, msg=result.stderr)
            self.assertFalse((repo_root / "hook.log").exists(), msg=result.stderr)
            self.assertIn("delete-only push detected", result.stderr)

    def test_pre_push_skips_verification_when_pushed_range_has_no_file_changes(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            repo_root = Path(temp_dir)
            self._init_repo(repo_root, "main")
            self._write_pre_push_fixture_scripts(repo_root)

            self._commit_file(repo_root, "README.md", "base\n", "base")

            result = self._run(["git", "checkout", "-b", "feature"], cwd=repo_root)
            self.assertEqual(result.returncode, 0, msg=result.stderr)

            self._commit_file(repo_root, "README.md", "branch change\n", "branch change")
            feature_remote_sha = self._run(["git", "rev-parse", "HEAD"], cwd=repo_root)
            self.assertEqual(feature_remote_sha.returncode, 0, msg=feature_remote_sha.stderr)

            result = self._run(["git", "commit", "--allow-empty", "-m", "empty"], cwd=repo_root)
            self.assertEqual(result.returncode, 0, msg=result.stderr)

            head_sha = self._run(["git", "rev-parse", "HEAD"], cwd=repo_root)
            self.assertEqual(head_sha.returncode, 0, msg=head_sha.stderr)

            result = self._run(
                ["bash", ".githooks/pre-push"],
                cwd=repo_root,
                input_text=(
                    f"refs/heads/feature {head_sha.stdout.strip()} "
                    f"refs/heads/feature {feature_remote_sha.stdout.strip()}\n"
                ),
            )

            self.assertEqual(result.returncode, 0, msg=result.stderr)
            self.assertFalse((repo_root / "hook.log").exists(), msg=result.stderr)
            self.assertIn("no file changes in pushed range", result.stderr)

    def test_pre_push_runs_tooling_checks_only_for_covered_python_tools(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            repo_root = Path(temp_dir)
            self._init_repo(repo_root, "main")
            self._write_pre_push_fixture_scripts(repo_root)

            self._commit_file(repo_root, "README.md", "base\n", "base")

            result = self._run(["git", "checkout", "-b", "feature"], cwd=repo_root)
            self.assertEqual(result.returncode, 0, msg=result.stderr)

            self._commit_file(
                repo_root,
                "tools/check_icon_corners.py",
                "print('tooling')\n",
                "tooling change",
            )

            head_sha = self._run(["git", "rev-parse", "HEAD"], cwd=repo_root)
            self.assertEqual(head_sha.returncode, 0, msg=head_sha.stderr)

            result = self._run(
                ["bash", ".githooks/pre-push"],
                cwd=repo_root,
                input_text=f"refs/heads/feature {head_sha.stdout.strip()} refs/heads/feature {'0' * 40}\n",
            )

            self.assertEqual(result.returncode, 0, msg=result.stderr)
            self.assertEqual((repo_root / "hook.log").read_text(encoding="utf-8").strip(), "tooling")

    def test_pre_push_runs_full_verification_for_uncovered_python_tools(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            repo_root = Path(temp_dir)
            self._init_repo(repo_root, "main")
            self._write_pre_push_fixture_scripts(repo_root)

            self._commit_file(repo_root, "README.md", "base\n", "base")

            result = self._run(["git", "checkout", "-b", "feature"], cwd=repo_root)
            self.assertEqual(result.returncode, 0, msg=result.stderr)

            self._commit_file(
                repo_root,
                "tools/helper.py",
                "print('uncovered tooling')\n",
                "tooling change",
            )

            head_sha = self._run(["git", "rev-parse", "HEAD"], cwd=repo_root)
            self.assertEqual(head_sha.returncode, 0, msg=head_sha.stderr)

            result = self._run(
                ["bash", ".githooks/pre-push"],
                cwd=repo_root,
                input_text=f"refs/heads/feature {head_sha.stdout.strip()} refs/heads/feature {'0' * 40}\n",
            )

            self.assertEqual(result.returncode, 0, msg=result.stderr)
            self.assertEqual((repo_root / "hook.log").read_text(encoding="utf-8").strip(), "full")

    def test_local_flutter_ci_prepares_i18n_once_in_temp_worktree_before_parallel_shards(self) -> None:
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

            for source, destination in [
                (RUN_FLUTTER_CI_LOCAL, scripts_dir / "run_flutter_ci_local.sh"),
            ]:
                destination.write_text(source.read_text(encoding="utf-8"), encoding="utf-8")
                self._make_executable(destination)

            (scripts_dir / "pre_commit_common.sh").write_text(
                "\n".join(
                    [
                        "die() {",
                        "  echo \"pre-commit: $*\" >&2",
                        "  exit 1",
                        "}",
                        "",
                        "resolve_dart_bin() {",
                        "  printf '%s\\n' /bin/true",
                        "}",
                        "",
                        "resolve_flutter_bin() {",
                        "  printf '%s\\n' /bin/true",
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

            (scripts_dir / "run_i18n_refresh.sh").write_text(
                "\n".join(
                    [
                        "#!/usr/bin/env bash",
                        "set -euo pipefail",
                        "repo_root=\"$(git rev-parse --show-toplevel)\"",
                        "common_dir=\"$(git rev-parse --git-common-dir)\"",
                        "count_file=\"${common_dir}/i18n-refresh-count.txt\"",
                        "count=0",
                        "if [[ -f \"${count_file}\" ]]; then",
                        "  count=\"$(cat \"${count_file}\")\"",
                        "fi",
                        "count=$((count + 1))",
                        "printf '%s\\n' \"${count}\" > \"${count_file}\"",
                        "mkdir -p \"${repo_root}/lib/i18n\"",
                        "printf '// generated from %s\\n' \"${repo_root}\" > \"${repo_root}/lib/i18n/strings.g.dart\"",
                    ]
                )
                + "\n",
                encoding="utf-8",
            )
            self._make_executable(scripts_dir / "run_i18n_refresh.sh")

            (scripts_dir / "run_flutter_test_shard.sh").write_text(
                "\n".join(
                    [
                        "#!/usr/bin/env bash",
                        "set -euo pipefail",
                        "repo_root=\"$(git rev-parse --show-toplevel)\"",
                        "common_dir=\"$(git rev-parse --git-common-dir)\"",
                        "printf '%s\\n' \"${repo_root}\" >> \"${common_dir}/shard-roots.log\"",
                        "cat \"${repo_root}/lib/i18n/strings.g.dart\" >> \"${common_dir}/shard-strings.log\"",
                    ]
                )
                + "\n",
                encoding="utf-8",
            )
            self._make_executable(scripts_dir / "run_flutter_test_shard.sh")

            (hooks_dir / "pre-commit").write_text(
                "#!/usr/bin/env bash\nset -euo pipefail\nexit 0\n",
                encoding="utf-8",
            )
            self._make_executable(hooks_dir / "pre-commit")

            self._commit_all(repo_root, "fixture")

            result = subprocess.run(
                ["bash", "scripts/run_flutter_ci_local.sh"],
                cwd=repo_root,
                check=False,
                capture_output=True,
                text=True,
                env={
                    **os.environ,
                    "SECONDLOOP_LOCAL_FLUTTER_TEST_SHARDS": "3",
                },
            )

            self.assertEqual(result.returncode, 0, msg=result.stderr)
            self.assertEqual(
                (repo_root / ".git/i18n-refresh-count.txt").read_text(encoding="utf-8").strip(),
                "1",
            )
            shard_roots = (repo_root / ".git/shard-roots.log").read_text(encoding="utf-8").splitlines()
            self.assertEqual(len(shard_roots), 3)
            self.assertNotIn(repo_root.as_posix(), shard_roots)
            self.assertEqual(
                (repo_root / ".git/shard-strings.log").read_text(encoding="utf-8").count("// generated from "),
                3,
            )
            self.assertFalse((lib_i18n_dir / "strings.g.dart").exists())

    def test_local_flutter_ci_syncs_dirty_workspace_state_into_parallel_shards(self) -> None:
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

            (test_dir / "sample_test.dart").write_text("base\n", encoding="utf-8")

            for source, destination in [
                (RUN_FLUTTER_CI_LOCAL, scripts_dir / "run_flutter_ci_local.sh"),
            ]:
                destination.write_text(source.read_text(encoding="utf-8"), encoding="utf-8")
                self._make_executable(destination)

            (scripts_dir / "pre_commit_common.sh").write_text(
                "\n".join(
                    [
                        "die() {",
                        "  echo \"pre-commit: $*\" >&2",
                        "  exit 1",
                        "}",
                        "",
                        "resolve_dart_bin() {",
                        "  printf '%s\\n' /bin/true",
                        "}",
                        "",
                        "resolve_flutter_bin() {",
                        "  printf '%s\\n' /bin/true",
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

            (scripts_dir / "run_i18n_refresh.sh").write_text(
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
                encoding="utf-8",
            )
            self._make_executable(scripts_dir / "run_i18n_refresh.sh")

            (scripts_dir / "run_flutter_test_shard.sh").write_text(
                "\n".join(
                    [
                        "#!/usr/bin/env bash",
                        "set -euo pipefail",
                        "repo_root=\"$(git rev-parse --show-toplevel)\"",
                        "common_dir=\"$(git rev-parse --git-common-dir)\"",
                        "cat \"${repo_root}/test/sample_test.dart\" > \"${common_dir}/sample-seen.txt\"",
                        "if [[ -f \"${repo_root}/test/new_test.dart\" ]]; then",
                        "  printf 'present\\n' > \"${common_dir}/new-test-seen.txt\"",
                        "fi",
                    ]
                )
                + "\n",
                encoding="utf-8",
            )
            self._make_executable(scripts_dir / "run_flutter_test_shard.sh")

            (hooks_dir / "pre-commit").write_text(
                "#!/usr/bin/env bash\nset -euo pipefail\nexit 0\n",
                encoding="utf-8",
            )
            self._make_executable(hooks_dir / "pre-commit")

            self._commit_all(repo_root, "fixture")

            (test_dir / "sample_test.dart").write_text("dirty\n", encoding="utf-8")
            (test_dir / "new_test.dart").write_text("new test\n", encoding="utf-8")

            result = subprocess.run(
                ["bash", "scripts/run_flutter_ci_local.sh"],
                cwd=repo_root,
                check=False,
                capture_output=True,
                text=True,
                env={
                    **os.environ,
                    "SECONDLOOP_LOCAL_FLUTTER_TEST_SHARDS": "1",
                },
            )

            self.assertEqual(result.returncode, 0, msg=result.stdout + result.stderr)
            self.assertEqual((repo_root / ".git/sample-seen.txt").read_text(encoding="utf-8"), "dirty\n")
            self.assertEqual((repo_root / ".git/new-test-seen.txt").read_text(encoding="utf-8"), "present\n")

    def test_local_flutter_ci_keeps_existing_repo_i18n_outputs_unchanged(self) -> None:
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
            (lib_i18n_dir / "strings.g.dart").write_text("// stale\n", encoding="utf-8")

            for source, destination in [
                (RUN_FLUTTER_CI_LOCAL, scripts_dir / "run_flutter_ci_local.sh"),
            ]:
                destination.write_text(source.read_text(encoding="utf-8"), encoding="utf-8")
                self._make_executable(destination)

            (scripts_dir / "pre_commit_common.sh").write_text(
                "\n".join(
                    [
                        "die() {",
                        "  echo \"pre-commit: $*\" >&2",
                        "  exit 1",
                        "}",
                        "",
                        "resolve_dart_bin() {",
                        "  printf '%s\\n' /bin/true",
                        "}",
                        "",
                        "resolve_flutter_bin() {",
                        "  printf '%s\\n' /bin/true",
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

            (scripts_dir / "run_i18n_refresh.sh").write_text(
                "\n".join(
                    [
                        "#!/usr/bin/env bash",
                        "set -euo pipefail",
                        "repo_root=\"$(git rev-parse --show-toplevel)\"",
                        "common_dir=\"$(git rev-parse --git-common-dir)\"",
                        "count_file=\"${common_dir}/i18n-refresh-count.txt\"",
                        "count=0",
                        "if [[ -f \"${count_file}\" ]]; then",
                        "  count=\"$(cat \"${count_file}\")\"",
                        "fi",
                        "count=$((count + 1))",
                        "printf '%s\\n' \"${count}\" > \"${count_file}\"",
                        "printf '// refreshed\\n' > \"${repo_root}/lib/i18n/strings.g.dart\"",
                    ]
                )
                + "\n",
                encoding="utf-8",
            )
            self._make_executable(scripts_dir / "run_i18n_refresh.sh")

            (scripts_dir / "run_flutter_test_shard.sh").write_text(
                "#!/usr/bin/env bash\nset -euo pipefail\ncat \"$(git rev-parse --show-toplevel)/lib/i18n/strings.g.dart\" >/dev/null\n",
                encoding="utf-8",
            )
            self._make_executable(scripts_dir / "run_flutter_test_shard.sh")

            (hooks_dir / "pre-commit").write_text(
                "#!/usr/bin/env bash\nset -euo pipefail\nexit 0\n",
                encoding="utf-8",
            )
            self._make_executable(hooks_dir / "pre-commit")

            self._commit_all(repo_root, "fixture")

            result = subprocess.run(
                ["bash", "scripts/run_flutter_ci_local.sh"],
                cwd=repo_root,
                check=False,
                capture_output=True,
                text=True,
                env={
                    **os.environ,
                    "SECONDLOOP_LOCAL_FLUTTER_TEST_SHARDS": "1",
                },
            )

            self.assertEqual(result.returncode, 0, msg=result.stderr)
            self.assertEqual(
                (repo_root / ".git/i18n-refresh-count.txt").read_text(encoding="utf-8").strip(),
                "1",
            )
            self.assertEqual(
                (lib_i18n_dir / "strings.g.dart").read_text(encoding="utf-8"),
                "// stale\n",
            )

    def test_local_flutter_ci_runs_pub_get_once_before_preparing_and_sharding(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            repo_root = Path(temp_dir)
            self._init_repo(repo_root, "main")

            scripts_dir = repo_root / "scripts"
            hooks_dir = repo_root / ".githooks"
            test_dir = repo_root / "test"
            fake_bin_dir = repo_root / "fake-bin"
            scripts_dir.mkdir(parents=True, exist_ok=True)
            hooks_dir.mkdir(parents=True, exist_ok=True)
            test_dir.mkdir(parents=True, exist_ok=True)
            fake_bin_dir.mkdir(parents=True, exist_ok=True)

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
                        f"resolve_dart_bin() {{ printf '%s\\n' \"{(fake_bin_dir / 'dart').as_posix()}\"; }}",
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
                    ]
                )
                + "\n",
                encoding="utf-8",
            )

            common_dir_expr = "$(git rev-parse --git-common-dir)"
            (fake_bin_dir / "flutter").write_text(
                "\n".join(
                    [
                        "#!/usr/bin/env bash",
                        "set -euo pipefail",
                        'repo_root="$(git rev-parse --show-toplevel)"',
                        f'common_dir="{common_dir_expr}"',
                        'printf \'%s|%s\\n\' "$repo_root" "$*" >> "${common_dir}/flutter.log"',
                        'if [[ "$1" == "pub" && "${2:-}" == "get" ]]; then',
                        '  mkdir -p "${repo_root}/.dart_tool"',
                        '  printf \'{}\\n\' > "${repo_root}/.dart_tool/package_config.json"',
                        '  printf \'plugins\\n\' > "${repo_root}/.flutter-plugins-dependencies"',
                        "  exit 0",
                        "fi",
                        "exit 0",
                    ]
                )
                + "\n",
                encoding="utf-8",
            )
            self._make_executable(fake_bin_dir / "flutter")

            (fake_bin_dir / "dart").write_text(
                "#!/usr/bin/env bash\nset -euo pipefail\nexit 0\n",
                encoding="utf-8",
            )
            self._make_executable(fake_bin_dir / "dart")

            (scripts_dir / "run_i18n_refresh.sh").write_text(
                "\n".join(
                    [
                        "#!/usr/bin/env bash",
                        "set -euo pipefail",
                        'repo_root="$(git rev-parse --show-toplevel)"',
                        'common_dir="$(git rev-parse --git-common-dir)"',
                        'if [[ ! -f "${repo_root}/.dart_tool/package_config.json" ]]; then',
                        '  echo missing-package-config >&2',
                        "  exit 9",
                        "fi",
                        'mkdir -p "${repo_root}/lib/i18n"',
                        'printf \'// generated\\n\' > "${repo_root}/lib/i18n/strings.g.dart"',
                        'printf \'refresh:%s\\n\' "${repo_root}" >> "${common_dir}/package-config.log"',
                    ]
                )
                + "\n",
                encoding="utf-8",
            )
            self._make_executable(scripts_dir / "run_i18n_refresh.sh")

            (scripts_dir / "run_flutter_test_shard.sh").write_text(
                "\n".join(
                    [
                        "#!/usr/bin/env bash",
                        "set -euo pipefail",
                        'repo_root="$(git rev-parse --show-toplevel)"',
                        'common_dir="$(git rev-parse --git-common-dir)"',
                        'if [[ ! -f "${repo_root}/.dart_tool/package_config.json" ]]; then',
                        '  echo missing-package-config >&2',
                        "  exit 11",
                        "fi",
                        'printf \'shard:%s\\n\' "${repo_root}" >> "${common_dir}/package-config.log"',
                    ]
                )
                + "\n",
                encoding="utf-8",
            )
            self._make_executable(scripts_dir / "run_flutter_test_shard.sh")

            (hooks_dir / "pre-commit").write_text(
                "#!/usr/bin/env bash\nset -euo pipefail\nexit 0\n",
                encoding="utf-8",
            )
            self._make_executable(hooks_dir / "pre-commit")

            self._commit_all(repo_root, "fixture")

            result = subprocess.run(
                ["bash", "scripts/run_flutter_ci_local.sh"],
                cwd=repo_root,
                check=False,
                capture_output=True,
                text=True,
                env={
                    **os.environ,
                    "SECONDLOOP_LOCAL_FLUTTER_TEST_SHARDS": "2",
                },
            )

            self.assertEqual(result.returncode, 0, msg=result.stdout + result.stderr)
            flutter_log = (repo_root / ".git/flutter.log").read_text(encoding="utf-8").splitlines()
            self.assertEqual(sum("|pub get" in line for line in flutter_log), 1)
            package_config_log = (repo_root / ".git/package-config.log").read_text(encoding="utf-8").splitlines()
            self.assertEqual(len([line for line in package_config_log if line.startswith("refresh:")]), 1)
            self.assertEqual(len([line for line in package_config_log if line.startswith("shard:")]), 2)
