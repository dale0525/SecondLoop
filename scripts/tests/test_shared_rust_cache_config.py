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
        self.shared_root = (self.primary_dir / common_dir).resolve() / "secondloop-shared"
        self.shared_tool = self.shared_root / ".tool"
        self.shared_cache = self.shared_tool / "cache"
        self.shared_tool.mkdir(parents=True, exist_ok=True)
        self.shared_cache.mkdir(parents=True, exist_ok=True)
        (self.worktree_dir / ".tool").symlink_to(self.shared_tool, target_is_directory=True)

        self.tmpdir_root = root / "tmpdir"
        self.tmpdir_root.mkdir(parents=True, exist_ok=True)

    def _run(self, cmd: list[str], cwd: Path) -> subprocess.CompletedProcess[str]:
        return subprocess.run(cmd, cwd=cwd, check=True, capture_output=True, text=True)

    def _run_script(
        self,
        *,
        extra_env: dict[str, str] | None = None,
    ) -> subprocess.CompletedProcess[str]:
        env = dict(subprocess.os.environ)
        env["TMPDIR"] = f"{self.tmpdir_root}{subprocess.os.sep}"
        if extra_env:
            env.update(extra_env)
        return subprocess.run(
            ["bash", str(CLEAN_UNUSED_CACHE_SCRIPT)],
            cwd=self.worktree_dir,
            check=True,
            capture_output=True,
            text=True,
            env=env,
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

    def test_script_adds_default_conservative_cleanup_targets(self) -> None:
        build_dir = self.worktree_dir / "build"
        dart_tool_dir = self.worktree_dir / ".dart_tool"
        wasm_probe_dir = self.shared_tool / "wasm-pack-probe.ABC123"
        shared_log = self.shared_cache / "run-android-cn-verbose.log"
        shared_txt = self.shared_cache / "adb-logcat-smoke.txt"
        secondloop_log = self.tmpdir_root / "secondloop_ci_flutter.XXXXXX.log.demo"
        secondloop_batch_log = self.tmpdir_root / "secondloop_flutter_batch_0_1.XXXXXX.log.demo"
        flutter_tools_dir = self.tmpdir_root / "flutter_tools.demo123"
        alamofire_tmp = self.tmpdir_root / "Alamofire_CFNetworkDownload_demo.tmp"

        for path in (build_dir, dart_tool_dir, wasm_probe_dir, flutter_tools_dir):
            path.mkdir(parents=True, exist_ok=True)
            (path / "marker.txt").write_text("marker\n", encoding="utf-8")

        for path in (shared_log, shared_txt, secondloop_log, secondloop_batch_log, alamofire_tmp):
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text("temp\n", encoding="utf-8")

        result = self._run_script()

        self.assertFalse(build_dir.exists())
        self.assertFalse(dart_tool_dir.exists())
        self.assertFalse(wasm_probe_dir.exists())
        self.assertFalse(shared_log.exists())
        self.assertFalse(shared_txt.exists())
        self.assertFalse(secondloop_log.exists())
        self.assertFalse(secondloop_batch_log.exists())
        self.assertFalse(flutter_tools_dir.exists())
        self.assertFalse(alamofire_tmp.exists())
        self.assertIn("Running conservative cleanup", result.stdout)

    def test_script_slims_rust_target_without_removing_debug_outputs(self) -> None:
        cargo_target_dir = self.shared_cache / "rust-dev-target"
        debug_dir = cargo_target_dir / "debug"
        release_dir = cargo_target_dir / "release"
        doc_dir = cargo_target_dir / "doc"
        package_dir = cargo_target_dir / "package"
        tmp_dir = cargo_target_dir / "tmp"

        for path in (debug_dir, release_dir, doc_dir, package_dir, tmp_dir):
            path.mkdir(parents=True, exist_ok=True)
            (path / "artifact.txt").write_text("artifact\n", encoding="utf-8")

        result = self._run_script(extra_env={"CARGO_TARGET_DIR": str(cargo_target_dir)})

        self.assertTrue(debug_dir.exists())
        self.assertFalse(release_dir.exists())
        self.assertFalse(doc_dir.exists())
        self.assertFalse(package_dir.exists())
        self.assertFalse(tmp_dir.exists())
        self.assertIn("Slimming Rust target caches", result.stdout)

    def test_script_keeps_high_cost_shared_tool_dirs(self) -> None:
        protected_dirs = [
            self.shared_root / ".pixi-envs" / "lock-hash" / "default",
            self.shared_tool / "gradle" / "caches",
            self.shared_tool / "fvm" / "versions" / "3.22.3",
            self.shared_tool / "android-sdk" / "platform-tools",
        ]

        for path in protected_dirs:
            path.mkdir(parents=True, exist_ok=True)
            (path / "marker.txt").write_text("keep\n", encoding="utf-8")

        self._run_script()

        for path in protected_dirs:
            self.assertTrue(path.exists(), f"expected protected path to remain: {path}")


if __name__ == "__main__":
    unittest.main()
