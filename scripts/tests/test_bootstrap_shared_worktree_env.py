from __future__ import annotations

from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest


SCRIPT_PATH = Path(__file__).resolve().parents[1] / "bootstrap_shared_worktree_env.sh"


@unittest.skipUnless(shutil.which("bash"), "bash is required")
@unittest.skipUnless(shutil.which("git"), "git is required")
@unittest.skipUnless(shutil.which("rsync"), "rsync is required")
class BootstrapSharedWorktreeEnvTests(unittest.TestCase):
    def setUp(self) -> None:
        self._tempdir = tempfile.TemporaryDirectory()
        self.addCleanup(self._tempdir.cleanup)

        root = Path(self._tempdir.name)
        self.primary_dir = root / "primary"
        self.worktree_dir = root / "worktree"

        self.primary_dir.mkdir(parents=True, exist_ok=True)

        self._run(["git", "init"], cwd=self.primary_dir)
        self._run(["git", "config", "user.email", "tests@example.com"], cwd=self.primary_dir)
        self._run(["git", "config", "user.name", "SecondLoop Tests"], cwd=self.primary_dir)

        (self.primary_dir / "README.md").write_text("test\n", encoding="utf-8")
        (self.primary_dir / "pixi.lock").write_text("lock\n", encoding="utf-8")

        self._run(["git", "add", "README.md", "pixi.lock"], cwd=self.primary_dir)
        self._run(["git", "commit", "-m", "init"], cwd=self.primary_dir)

        self._create_primary_signing_files()
        self._create_primary_flutter_sdk_link()

        self._run(
            ["git", "worktree", "add", "-b", "test-worktree", str(self.worktree_dir), "HEAD"],
            cwd=self.primary_dir,
        )

    def _run(self, cmd: list[str], cwd: Path) -> subprocess.CompletedProcess[str]:
        return subprocess.run(cmd, cwd=cwd, check=True, capture_output=True, text=True)

    def _run_bootstrap(self, extra_args: list[str] | None = None) -> subprocess.CompletedProcess[str]:
        args = ["bash", str(SCRIPT_PATH)]
        if extra_args:
            args.extend(extra_args)

        return self._run(args, cwd=self.worktree_dir)

    def _run_bootstrap_dry_run(self, extra_args: list[str] | None = None) -> str:
        args = ["--dry-run"]
        if extra_args:
            args.extend(extra_args)

        result = self._run_bootstrap(args)
        return result.stdout

    def _create_primary_signing_files(self) -> None:
        (self.primary_dir / ".env.local").write_text("SECONDLOOP_TEST=1\n", encoding="utf-8")

        android_dir = self.primary_dir / "android"
        app_dir = android_dir / "app"
        app_dir.mkdir(parents=True, exist_ok=True)

        (android_dir / "key.properties").write_text(
            "storeFile=app/upload-keystore.jks\n",
            encoding="utf-8",
        )
        (app_dir / "upload-keystore.jks").write_bytes(b"fake-keystore")

    def _create_primary_flutter_sdk_link(self) -> None:
        sdk_dir = self.primary_dir / ".tool" / "fvm" / "versions" / "3.22.3"
        sdk_dir.mkdir(parents=True, exist_ok=True)

        fvm_dir = self.primary_dir / ".fvm"
        fvm_dir.mkdir(parents=True, exist_ok=True)

        flutter_sdk_link = fvm_dir / "flutter_sdk"
        flutter_sdk_link.symlink_to(sdk_dir)

    def test_dry_run_links_android_signing_files_from_primary_worktree(self) -> None:
        output = self._run_bootstrap_dry_run()

        self.assertIn("Linking android/key.properties ->", output)
        self.assertIn("Linking android/app/upload-keystore.jks ->", output)

    def test_skip_android_key_link_flag_disables_android_signing_file_links(self) -> None:
        output = self._run_bootstrap_dry_run(["--skip-android-key-link"])

        self.assertIn("Skipping Android key linking (--skip-android-key-link).", output)
        self.assertNotIn("Linking android/key.properties ->", output)
        self.assertNotIn("Linking android/app/upload-keystore.jks ->", output)

    def test_dry_run_links_fvm_flutter_sdk_from_primary_worktree(self) -> None:
        output = self._run_bootstrap_dry_run()

        self.assertIn("Linking .fvm/flutter_sdk ->", output)

    def test_bootstrap_links_fvm_flutter_sdk_from_primary_worktree(self) -> None:
        self._run_bootstrap()

        flutter_sdk_link = self.worktree_dir / ".fvm" / "flutter_sdk"
        self.assertTrue(flutter_sdk_link.is_symlink())
        self.assertEqual(
            flutter_sdk_link.resolve(),
            (self.primary_dir / ".tool" / "fvm" / "versions" / "3.22.3").resolve(),
        )

    def test_skip_fvm_sdk_link_flag_disables_fvm_flutter_sdk_link(self) -> None:
        output = self._run_bootstrap_dry_run(["--skip-fvm-sdk-link"])

        self.assertIn("Skipping .fvm/flutter_sdk linking (--skip-fvm-sdk-link).", output)
        self.assertNotIn("Linking .fvm/flutter_sdk ->", output)


if __name__ == "__main__":
    unittest.main()
