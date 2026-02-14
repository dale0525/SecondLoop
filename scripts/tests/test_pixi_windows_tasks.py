from __future__ import annotations

from pathlib import Path
import tomllib
import unittest


REPO_ROOT = Path(__file__).resolve().parents[2]
PIXI_TOML = REPO_ROOT / "pixi.toml"
WINDOWS_BOOTSTRAP_SCRIPT = REPO_ROOT / "scripts/bootstrap_shared_worktree_env.ps1"


class PixiWindowsTasksTests(unittest.TestCase):
    def _load_win_tasks(self) -> dict[str, object]:
        with PIXI_TOML.open("rb") as fh:
            pixi_config = tomllib.load(fh)

        return pixi_config["target"]["win-64"]["tasks"]

    def test_windows_bootstrap_task_uses_powershell_script(self) -> None:
        win_tasks = self._load_win_tasks()

        bootstrap_task = win_tasks["bootstrap-shared-worktree-env"]
        self.assertIsInstance(bootstrap_task, str)
        self.assertIn("scripts/bootstrap_shared_worktree_env.ps1", bootstrap_task)

    def test_run_windows_depends_on_bootstrap_shared_worktree_env(self) -> None:
        win_tasks = self._load_win_tasks()

        run_windows_task = win_tasks["run-windows"]
        dependencies = run_windows_task.get("depends-on", [])

        self.assertIn("bootstrap-shared-worktree-env", dependencies)

    def test_package_windows_msi_depends_on_bootstrap_shared_worktree_env(self) -> None:
        win_tasks = self._load_win_tasks()

        package_windows_task = win_tasks["package-windows-msi"]
        dependencies = package_windows_task.get("depends-on", [])

        self.assertIn("bootstrap-shared-worktree-env", dependencies)

    def test_windows_bootstrap_script_links_shared_tool_and_pixi_envs(self) -> None:
        script = WINDOWS_BOOTSTRAP_SCRIPT.read_text(encoding="utf-8")

        self.assertIn("Link-DirectoryToShared -LocalPath (Join-Path $repoRoot '.tool')", script)
        self.assertIn("Link-DirectoryToShared -LocalPath (Join-Path $repoRoot '.pixi/envs')", script)


if __name__ == "__main__":
    unittest.main()
