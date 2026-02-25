from __future__ import annotations

from pathlib import Path
import tomllib
import unittest


REPO_ROOT = Path(__file__).resolve().parents[2]
PIXI_TOML = REPO_ROOT / "pixi.toml"
ANDROID_RUN_SCRIPT = REPO_ROOT / "scripts/run_android_with_auto_emulator.sh"
RUN_WITH_ANDROID_ENV_SCRIPT = REPO_ROOT / "scripts/run_with_android_env.sh"
SETUP_RUSTUP_SCRIPT = REPO_ROOT / "scripts/setup_rustup.sh"
ANDROID_BUILD_GRADLE = REPO_ROOT / "android/app/build.gradle"
ANDROID_MANIFEST = REPO_ROOT / "android/app/src/main/AndroidManifest.xml"
FLUTTER_WITH_DEFINES_SCRIPT = REPO_ROOT / "scripts/flutter_with_defines.sh"
BUILD_ANDROID_RELEASE_APK_SCRIPT = REPO_ROOT / "scripts/build_android_release_apk.sh"
CARGOKIT_PLUGIN_GRADLE = REPO_ROOT / "rust_builder/cargokit/gradle/plugin.gradle"


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

    def test_android_local_dev_tasks_use_dev_app_id(self) -> None:
        tasks = self._load_tasks()

        for task_name in [
            "run-android",
            "build-android-apk",
            "run-android-cn",
            "build-android-apk-cn",
        ]:
            with self.subTest(task=task_name):
                task = tasks[task_name]
                command = task.get("cmd", "")
                self.assertIn(
                    "SECONDLOOP_APP_ID=com.secondloop.secondloopdev",
                    command,
                )

    def test_android_local_dev_tasks_use_dev_app_name(self) -> None:
        tasks = self._load_tasks()

        for task_name in [
            "run-android",
            "build-android-apk",
            "run-android-cn",
            "build-android-apk-cn",
        ]:
            with self.subTest(task=task_name):
                task = tasks[task_name]
                command = task.get("cmd", "")
                self.assertIn("SECONDLOOP_APP_NAME='SecondLoop Dev'", command)

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

    def test_auto_emulator_script_defaults_to_global_app_id_override(self) -> None:
        script = ANDROID_RUN_SCRIPT.read_text(encoding="utf-8")

        self.assertIn("SECONDLOOP_APP_ID", script)
        self.assertIn("SECONDLOOP_ANDROID_APP_ID", script)

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

        self.assertIn('whisper-rs-sys-0.14*/build.rs', script)
        self.assertIn('target.contains("apple-darwin")', script)
        self.assertIn('cfg!(feature = "openblas")', script)

    def test_setup_rustup_patches_cargokit_plugins_for_new_flutter_gradle_plugin(self) -> None:
        script = SETUP_RUSTUP_SCRIPT.read_text(encoding="utf-8")

        self.assertIn(".tool/pub-cache/hosted", script)
        self.assertIn('irondash_engine_context-*/cargokit/gradle/plugin.gradle', script)
        self.assertIn('super_native_extensions-*/cargokit/gradle/plugin.gradle', script)
        self.assertIn('candidate.plugins.hasPlugin("dev.flutter.flutter-gradle-plugin")', script)
        self.assertIn('hostArch.contains("x86_64")', script)

    def test_android_gradle_application_id_supports_environment_override(self) -> None:
        gradle_file = ANDROID_BUILD_GRADLE.read_text(encoding="utf-8")

        self.assertIn('System.getenv("SECONDLOOP_APP_ID")', gradle_file)
        self.assertIn("applicationId secondloopApplicationId", gradle_file)

    def test_android_gradle_application_name_supports_dev_override(self) -> None:
        gradle_file = ANDROID_BUILD_GRADLE.read_text(encoding="utf-8")

        self.assertIn('System.getenv("SECONDLOOP_APP_NAME")', gradle_file)
        self.assertIn(
            'if (secondloopApplicationId == "com.secondloop.secondloopdev")',
            gradle_file,
        )
        self.assertIn(
            'manifestPlaceholders += [appName: secondloopApplicationName]',
            gradle_file,
        )

    def test_android_manifest_uses_app_name_placeholder(self) -> None:
        manifest_file = ANDROID_MANIFEST.read_text(encoding="utf-8")

        self.assertIn('android:label="${appName}"', manifest_file)

    def test_flutter_with_defines_falls_back_to_flutter_when_fvm_is_missing(self) -> None:
        script = FLUTTER_WITH_DEFINES_SCRIPT.read_text(encoding="utf-8")

        self.assertIn("dart pub global list", script)
        self.assertIn('command -v flutter', script)
        self.assertIn('No active package fvm', script)

    def test_android_release_script_supports_target_platform_override(self) -> None:
        script = BUILD_ANDROID_RELEASE_APK_SCRIPT.read_text(encoding="utf-8")

        self.assertIn('SECONDLOOP_ANDROID_TARGET_PLATFORMS', script)
        self.assertIn('android-arm,android-arm64', script)
        self.assertIn('--target-platform "${target_platforms}"', script)

    def test_cargokit_debug_build_does_not_force_android_x86_target(self) -> None:
        plugin_text = CARGOKIT_PLUGIN_GRADLE.read_text(encoding="utf-8")

        self.assertNotIn('platforms.add("android-x86")', plugin_text)

    def test_cargokit_debug_build_only_adds_android_x64_for_x86_hosts(self) -> None:
        plugin_text = CARGOKIT_PLUGIN_GRADLE.read_text(encoding="utf-8")

        self.assertIn('System.getProperty("os.arch", "")', plugin_text)
        self.assertIn('hostArch.contains("x86_64")', plugin_text)
        self.assertIn('hostArch.contains("amd64")', plugin_text)



if __name__ == "__main__":
    unittest.main()
