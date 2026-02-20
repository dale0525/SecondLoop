from __future__ import annotations

from pathlib import Path
import tomllib
import unittest


REPO_ROOT = Path(__file__).resolve().parents[2]
PIXI_TOML = REPO_ROOT / "pixi.toml"
ANDROID_RUN_SCRIPT = REPO_ROOT / "scripts/run_android_with_auto_emulator.sh"
RUN_WITH_ANDROID_ENV_SCRIPT = REPO_ROOT / "scripts/run_with_android_env.sh"
SETUP_RUSTUP_SCRIPT = REPO_ROOT / "scripts/setup_rustup.sh"


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

    def test_auto_emulator_script_exports_android_avd_home(self) -> None:
        script = ANDROID_RUN_SCRIPT.read_text(encoding="utf-8")

        self.assertIn("export ANDROID_AVD_HOME", script)

    def test_auto_emulator_device_detection_uses_adb_not_flutter_devices(self) -> None:
        script = ANDROID_RUN_SCRIPT.read_text(encoding="utf-8")

        self.assertNotIn('flutter_with_defines.sh" devices --machine', script)

    def test_auto_emulator_script_runs_flutter_with_detected_device_serial(self) -> None:
        script = ANDROID_RUN_SCRIPT.read_text(encoding="utf-8")

        self.assertIn("first_android_device_serial", script)
        self.assertIn('run -d "$device_serial"', script)

    def test_run_with_android_env_unsets_host_toolchain_vars(self) -> None:
        script = RUN_WITH_ANDROID_ENV_SCRIPT.read_text(encoding="utf-8")

        self.assertIn("for polluted_var in", script)
        self.assertIn("CMAKE_ARGS", script)
        self.assertIn("SDKROOT", script)
        self.assertIn('unset "$polluted_var"', script)

    def test_run_with_android_env_exports_ndk_toolchain_for_cmake(self) -> None:
        script = RUN_WITH_ANDROID_ENV_SCRIPT.read_text(encoding="utf-8")

        self.assertIn("ANDROID_NDK_ROOT", script)
        self.assertIn("CMAKE_TOOLCHAIN_FILE", script)
        self.assertIn("android.toolchain.cmake", script)
        self.assertIn("CMAKE_GENERATOR", script)
        self.assertIn("Ninja", script)

    def test_setup_rustup_prefetches_android_cargo_dependencies(self) -> None:
        script = SETUP_RUSTUP_SCRIPT.read_text(encoding="utf-8")

        self.assertIn('cargo fetch --manifest-path "$ROOT_DIR/rust/Cargo.toml"', script)
        self.assertIn('--target armv7-linux-androideabi', script)
        self.assertIn('--target aarch64-linux-android', script)

    def test_setup_rustup_patches_whisper_rs_sys_cross_compile_link_logic(self) -> None:
        script = SETUP_RUSTUP_SCRIPT.read_text(encoding="utf-8")

        self.assertIn('whisper-rs-sys-0.14.1/build.rs', script)
        self.assertIn('target.contains("apple-darwin")', script)
        self.assertIn('cfg!(feature = "openblas")', script)


if __name__ == "__main__":
    unittest.main()
