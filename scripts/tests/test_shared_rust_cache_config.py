from __future__ import annotations

from pathlib import Path
import shutil
import subprocess
import tempfile
import tomllib
import unittest


REPO_ROOT = Path(__file__).resolve().parents[2]
PIXI_TOML = REPO_ROOT / "pixi.toml"
CLEAN_UNUSED_CACHE_SCRIPT = REPO_ROOT / "scripts/clean_unused_cache.sh"


def _cksum_key(path: Path) -> str:
    result = subprocess.run(
        ["/bin/sh", "-c", "cksum | awk '{print $1}'"],
        input=f"{path.resolve()}\n",
        text=True,
        capture_output=True,
        check=True,
    )
    return result.stdout.strip()


class SharedRustCacheConfigTests(unittest.TestCase):
    def _load_pixi_config(self) -> dict[str, object]:
        with PIXI_TOML.open("rb") as fh:
            return tomllib.load(fh)

    def test_unix_activation_env_sets_shared_cargo_target_dir(self) -> None:
        pixi_config = self._load_pixi_config()

        unix_env = pixi_config["target"]["unix"]["activation"]["env"]

        self.assertEqual(
            unix_env["CARGO_TARGET_DIR"],
            "$PIXI_PROJECT_ROOT/.tool/cache/rust-dev-target",
        )

    def test_unix_activation_env_sets_shared_cargokit_temp_dirs(self) -> None:
        pixi_config = self._load_pixi_config()

        unix_env = pixi_config["target"]["unix"]["activation"]["env"]

        self.assertEqual(
            unix_env["CARGOKIT_TARGET_TEMP_DIR"],
            "$PIXI_PROJECT_ROOT/.tool/cache/cargokit-target-temp",
        )
        self.assertEqual(
            unix_env["CARGOKIT_TOOL_TEMP_DIR"],
            "$PIXI_PROJECT_ROOT/.tool/cache/cargokit-target-temp/tool",
        )

    def test_clean_unused_cache_task_uses_dedicated_script(self) -> None:
        pixi_config = self._load_pixi_config()

        self.assertEqual(
            pixi_config["tasks"]["clean-unused-cache"],
            "bash scripts/clean_unused_cache.sh",
        )


@unittest.skipUnless(shutil.which("bash"), "bash is required")
@unittest.skipUnless(shutil.which("git"), "git is required")
class CleanUnusedCacheScriptTests(unittest.TestCase):
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
        self._run(["git", "add", "README.md"], cwd=self.primary_dir)
        self._run(["git", "commit", "-m", "init"], cwd=self.primary_dir)
        self._run(
            ["git", "worktree", "add", "-b", "test-worktree", str(self.worktree_dir), "HEAD"],
            cwd=self.primary_dir,
        )

        common_dir = self._run(
            ["git", "rev-parse", "--git-common-dir"],
            cwd=self.primary_dir,
        ).stdout.strip()
        self.shared_cache = (self.primary_dir / common_dir).resolve() / "secondloop-shared/.tool/cache"
        self.shared_cache.mkdir(parents=True, exist_ok=True)

    def _run(self, cmd: list[str], cwd: Path) -> subprocess.CompletedProcess[str]:
        return subprocess.run(cmd, cwd=cwd, check=True, capture_output=True, text=True)

    def _run_script(self) -> subprocess.CompletedProcess[str]:
        return subprocess.run(
            ["bash", str(CLEAN_UNUSED_CACHE_SCRIPT)],
            cwd=self.worktree_dir,
            check=True,
            capture_output=True,
            text=True,
        )

    def test_script_prunes_stale_shared_rust_ci_target_dirs(self) -> None:
        active_key = _cksum_key(self.worktree_dir)
        active_dir = self.shared_cache / f"rust-ci-target-{active_key}"
        stale_dir = self.shared_cache / "rust-ci-target-999999999"
        active_dir.mkdir(parents=True, exist_ok=True)
        stale_dir.mkdir(parents=True, exist_ok=True)

        result = self._run_script()

        self.assertTrue(active_dir.exists())
        self.assertFalse(stale_dir.exists())
        self.assertIn("Removing stale shared Rust CI cache", result.stdout)


if __name__ == "__main__":
    unittest.main()
