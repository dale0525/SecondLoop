from __future__ import annotations

from pathlib import Path
import tomllib
import unittest


PIXI_TOML = Path(__file__).resolve().parents[2] / "pixi.toml"


class PixiWindowsTasksTests(unittest.TestCase):
    def test_run_windows_does_not_depend_on_bootstrap_shared_worktree_env(self) -> None:
        with PIXI_TOML.open("rb") as fh:
            pixi_config = tomllib.load(fh)

        win_tasks = pixi_config["target"]["win-64"]["tasks"]
        run_windows_task = win_tasks["run-windows"]
        dependencies = run_windows_task.get("depends-on", [])

        self.assertNotIn("bootstrap-shared-worktree-env", dependencies)


if __name__ == "__main__":
    unittest.main()
