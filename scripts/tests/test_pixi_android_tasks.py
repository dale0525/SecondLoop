from __future__ import annotations

from pathlib import Path
import tomllib
import unittest


REPO_ROOT = Path(__file__).resolve().parents[2]
PIXI_TOML = REPO_ROOT / "pixi.toml"
ANDROID_RUN_SCRIPT = REPO_ROOT / "scripts/run_android_with_auto_emulator.sh"


class PixiAndroidTasksTests(unittest.TestCase):
    def _load_tasks(self) -> dict[str, object]:
        with PIXI_TOML.open("rb") as fh:
            pixi_config = tomllib.load(fh)

        return pixi_config["tasks"]

    def test_run_android_task_uses_auto_emulator_script(self) -> None:
        tasks = self._load_tasks()

        run_android_task = tasks["run-android"]
        command = run_android_task.get("cmd", "")

        self.assertIn("scripts/run_android_with_auto_emulator.sh", command)

    def test_run_android_cn_task_uses_auto_emulator_script(self) -> None:
        tasks = self._load_tasks()

        run_android_task = tasks["run-android-cn"]
        command = run_android_task.get("cmd", "")

        self.assertIn("scripts/run_android_with_auto_emulator.sh", command)

    def test_auto_emulator_script_checks_for_existing_android_devices(self) -> None:
        script = ANDROID_RUN_SCRIPT.read_text(encoding="utf-8")

        self.assertIn("has_connected_android_device", script)
        self.assertIn("No Android device detected", script)

    def test_auto_emulator_script_installs_emulator_and_system_image(self) -> None:
        script = ANDROID_RUN_SCRIPT.read_text(encoding="utf-8")

        self.assertIn('"emulator"', script)
        self.assertIn('"system-images;android-${ANDROID_API_LEVEL};google_apis;', script)


if __name__ == "__main__":
    unittest.main()
