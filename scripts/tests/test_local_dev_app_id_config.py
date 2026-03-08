from __future__ import annotations

from pathlib import Path
import tomllib
import unittest


REPO_ROOT = Path(__file__).resolve().parents[2]
PIXI_TOML = REPO_ROOT / "pixi.toml"
FLUTTER_WITH_DEFINES_SCRIPT = REPO_ROOT / "scripts/flutter_with_defines.sh"
IOS_INFO_PLIST = REPO_ROOT / "ios/Runner/Info.plist"
IOS_APP_DELEGATE = REPO_ROOT / "ios/Runner/AppDelegate.swift"
IOS_PROJECT = REPO_ROOT / "ios/Runner.xcodeproj/project.pbxproj"
MACOS_APP_INFO = REPO_ROOT / "macos/Runner/Configs/AppInfo.xcconfig"
LINUX_CMAKE = REPO_ROOT / "linux/CMakeLists.txt"
BACKGROUND_SYNC_DART = REPO_ROOT / "lib/core/sync/background_sync.dart"
NOTIFICATION_SCHEDULER_DART = (
    REPO_ROOT / "lib/core/notifications/review_reminder_notification_scheduler.dart"
)
SYNC_DESKTOP_RUNTIME_TOOL = REPO_ROOT / "tools/sync_desktop_runtime_to_appdir.dart"
RUN_WINDOWS_SCRIPT = REPO_ROOT / "scripts/run_windows.ps1"
WINDOWS_CMAKE = REPO_ROOT / "windows/runner/CMakeLists.txt"
WINDOWS_MAIN = REPO_ROOT / "windows/runner/main.cpp"
WINDOWS_RUNNER_RC = REPO_ROOT / "windows/runner/Runner.rc"


class LocalDevAppIdConfigTests(unittest.TestCase):
    def _load_pixi_config(self) -> dict[str, object]:
        with PIXI_TOML.open("rb") as fh:
            return tomllib.load(fh)

    def test_run_macos_task_exports_dev_app_id(self) -> None:
        pixi_config = self._load_pixi_config()

        run_macos = pixi_config["target"]["osx-arm64"]["tasks"]["run-macos"]
        command = run_macos.get("cmd", "")

        self.assertIn("export SECONDLOOP_APP_ID=com.secondloop.secondloopdev", command)

    def test_run_macos_task_exports_dev_app_name(self) -> None:
        pixi_config = self._load_pixi_config()

        run_macos = pixi_config["target"]["osx-arm64"]["tasks"]["run-macos"]
        command = run_macos.get("cmd", "")

        self.assertIn("SECONDLOOP_APP_NAME='SecondLoop Dev'", command)

    def test_run_linux_task_exports_dev_app_id(self) -> None:
        pixi_config = self._load_pixi_config()

        run_linux = pixi_config["target"]["linux-64"]["tasks"]["run-linux"]
        command = run_linux.get("cmd", "")

        self.assertIn("export SECONDLOOP_APP_ID=com.secondloop.secondloopdev", command)

    def test_run_linux_task_exports_dev_app_name(self) -> None:
        pixi_config = self._load_pixi_config()

        run_linux = pixi_config["target"]["linux-64"]["tasks"]["run-linux"]
        command = run_linux.get("cmd", "")

        self.assertIn("SECONDLOOP_APP_NAME='SecondLoop Dev'", command)

    def test_flutter_with_defines_supports_secondloop_app_id_define(self) -> None:
        script = FLUTTER_WITH_DEFINES_SCRIPT.read_text(encoding="utf-8")

        self.assertIn("maybe_define SECONDLOOP_APP_ID", script)

    def test_ios_bg_task_identifier_is_derived_from_bundle_id(self) -> None:
        info_plist = IOS_INFO_PLIST.read_text(encoding="utf-8")

        self.assertIn("$(PRODUCT_BUNDLE_IDENTIFIER).backgroundSync", info_plist)

    def test_ios_info_plist_supports_secondloop_app_name_override(self) -> None:
        info_plist = IOS_INFO_PLIST.read_text(encoding="utf-8")

        self.assertIn('$(SECONDLOOP_APP_NAME:default=SecondLoop)', info_plist)

    def test_ios_project_bundle_id_supports_secondloop_app_id_override(self) -> None:
        project = IOS_PROJECT.read_text(encoding="utf-8")

        self.assertIn(
            'PRODUCT_BUNDLE_IDENTIFIER = "$(SECONDLOOP_APP_ID:default=com.secondloop.secondloop)";',
            project,
        )

    def test_ios_app_delegate_uses_dynamic_bg_task_identifier(self) -> None:
        app_delegate = IOS_APP_DELEGATE.read_text(encoding="utf-8")

        self.assertIn("Bundle.main.bundleIdentifier", app_delegate)
        self.assertIn(".backgroundSync", app_delegate)

    def test_macos_bundle_id_supports_secondloop_app_id_override(self) -> None:
        app_info = MACOS_APP_INFO.read_text(encoding="utf-8")

        self.assertIn(
            "PRODUCT_BUNDLE_IDENTIFIER = $(SECONDLOOP_APP_ID:default=com.secondloop.secondloop)",
            app_info,
        )

    def test_macos_product_name_supports_secondloop_app_name_override(self) -> None:
        app_info = MACOS_APP_INFO.read_text(encoding="utf-8")

        self.assertIn(
            "PRODUCT_NAME = $(SECONDLOOP_APP_NAME:default=SecondLoop)",
            app_info,
        )

    def test_linux_application_id_supports_secondloop_app_id_override(self) -> None:
        cmake_file = LINUX_CMAKE.read_text(encoding="utf-8")

        self.assertIn('$ENV{SECONDLOOP_APP_ID}', cmake_file)

    def test_linux_application_name_supports_secondloop_app_name_override(self) -> None:
        cmake_file = LINUX_CMAKE.read_text(encoding="utf-8")

        self.assertIn('$ENV{SECONDLOOP_APP_NAME}', cmake_file)
        self.assertIn('add_definitions(-DSECONDLOOP_APP_NAME=', cmake_file)
        self.assertIn('${SECONDLOOP_APP_NAME}', cmake_file)

    def test_background_sync_task_id_uses_secondloop_app_id_define(self) -> None:
        background_sync = BACKGROUND_SYNC_DART.read_text(encoding="utf-8")

        self.assertIn('String.fromEnvironment(', background_sync)
        self.assertIn('SECONDLOOP_APP_ID', background_sync)

    def test_windows_notification_aumid_uses_secondloop_app_id_define(self) -> None:
        notification_scheduler = NOTIFICATION_SCHEDULER_DART.read_text(encoding="utf-8")

        self.assertIn('String.fromEnvironment(', notification_scheduler)
        self.assertIn('SECONDLOOP_APP_ID', notification_scheduler)

    def test_run_windows_script_passes_secondloop_app_id_dart_define(self) -> None:
        script = RUN_WINDOWS_SCRIPT.read_text(encoding="utf-8")

        self.assertIn("SECONDLOOP_APP_ID", script)
        self.assertIn("--dart-define=SECONDLOOP_APP_ID=", script)

    def test_windows_script_defaults_dev_app_name(self) -> None:
        script = RUN_WINDOWS_SCRIPT.read_text(encoding="utf-8")

        self.assertIn("SECONDLOOP_APP_NAME", script)
        self.assertIn("SecondLoop Dev", script)
        self.assertIn("--dart-define=SECONDLOOP_APP_NAME=", script)

    def test_windows_window_title_supports_secondloop_app_name_override(self) -> None:
        cmake_file = WINDOWS_CMAKE.read_text(encoding="utf-8")
        main_file = WINDOWS_MAIN.read_text(encoding="utf-8")

        self.assertIn('$ENV{SECONDLOOP_APP_NAME}', cmake_file)
        self.assertIn('set(SECONDLOOP_APP_NAME "SecondLoop Dev")', cmake_file)
        self.assertIn('SECONDLOOP_WINDOW_TITLE', cmake_file)
        self.assertIn('window.Create(SECONDLOOP_WINDOW_TITLE, origin, size)', main_file)

    def test_windows_runner_rc_uses_build_time_metadata_macros(self) -> None:
        runner_rc = WINDOWS_RUNNER_RC.read_text(encoding="utf-8")

        self.assertIn('VALUE "CompanyName", SECONDLOOP_COMPANY_NAME "\\0"', runner_rc)
        self.assertIn(
            'VALUE "FileDescription", SECONDLOOP_FILE_DESCRIPTION "\\0"',
            runner_rc,
        )
        self.assertIn('VALUE "ProductName", SECONDLOOP_PRODUCT_NAME "\\0"', runner_rc)

    def test_sync_desktop_runtime_tool_reads_secondloop_app_id_from_env(self) -> None:
        tool = SYNC_DESKTOP_RUNTIME_TOOL.read_text(encoding="utf-8")

        self.assertIn("Platform.environment['SECONDLOOP_APP_ID']", tool)

    def test_sync_desktop_runtime_tool_reads_secondloop_app_name_from_env(self) -> None:
        tool = SYNC_DESKTOP_RUNTIME_TOOL.read_text(encoding="utf-8")

        self.assertIn("Platform.environment['SECONDLOOP_APP_NAME']", tool)


if __name__ == "__main__":
    unittest.main()
