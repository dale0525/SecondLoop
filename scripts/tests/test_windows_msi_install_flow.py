from __future__ import annotations

from pathlib import Path
import unittest


class WindowsMsiInstallFlowTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.repo_root = Path(__file__).resolve().parents[2]

    def _read_repo_file(self, relative_path: str) -> str:
        return (self.repo_root / relative_path).read_text(encoding="utf-8")

    def test_create_windows_msi_defines_auto_launch_custom_action(self) -> None:
        script = self._read_repo_file("scripts/create_windows_msi.ps1")

        self.assertIn('Property Id="SECONDLOOP_LAUNCH_AFTER_INSTALL" Value="1"', script)
        self.assertIn(
            '<CustomAction Id="SetLaunchApplicationTarget" Property="WixShellExecTarget" Value="[INSTALLFOLDER]secondloop.exe" />',
            script,
        )
        self.assertIn(
            '<CustomAction Id="LaunchApplication" BinaryKey="WixCA" DllEntry="WixShellExec" Return="check" Impersonate="yes" />',
            script,
        )
        self.assertIn(
            '<Custom Action="SetLaunchApplicationTarget" After="InstallFinalize">SECONDLOOP_LAUNCH_AFTER_INSTALL = "1" AND NOT Installed AND UILevel >= 3</Custom>',
            script,
        )
        self.assertIn(
            '<Custom Action="LaunchApplication" After="SetLaunchApplicationTarget">SECONDLOOP_LAUNCH_AFTER_INSTALL = "1" AND NOT Installed AND UILevel >= 3</Custom>',
            script,
        )
        self.assertNotIn('CustomAction Id="LaunchApplication" Directory="INSTALLFOLDER"', script)

    def test_create_windows_msi_closes_running_app_gracefully_before_uninstall(self) -> None:
        script = self._read_repo_file("scripts/create_windows_msi.ps1")

        self.assertIn("[switch]$DisableCloseApplication", script)
        self.assertIn(
            '<Wix xmlns="http://schemas.microsoft.com/wix/2006/wi" xmlns:util="http://schemas.microsoft.com/wix/UtilExtension">',
            script,
        )
        self.assertIn("$closeApplicationBlock = if ($DisableCloseApplication)", script)
        self.assertIn("__CLOSE_APPLICATION_BLOCK__", script)
        self.assertIn(
            '<util:CloseApplication Id="CloseSecondLoopOnUninstall" Target="secondloop.exe" CloseMessage="yes" RebootPrompt="no" TerminateProcess="0" Timeout="5">REMOVE~="ALL"</util:CloseApplication>',
            script,
        )
        self.assertNotIn("taskkill.exe /F /T /IM secondloop.exe", script)

    def test_create_windows_msi_applies_per_user_harvest_fixes_with_targeted_ice_policy(self) -> None:
        script = self._read_repo_file("scripts/create_windows_msi.ps1")

        self.assertIn("function Convert-HarvestToPerUserCompliant", script)
        self.assertIn("Software\\SecondLoop\\Installer\\Components", script)
        self.assertIn("RemoveFolder", script)
        self.assertIn("KeyPath', 'no'", script)
        self.assertIn("'-sice:ICE60'", script)
        self.assertIn("'-sice:ICE91'", script)
        self.assertNotIn("'-sice:ICE38'", script)
        self.assertNotIn("'-sice:ICE64'", script)
        self.assertGreaterEqual(script.count("WixUtilExtension"), 2)

    def test_create_windows_msi_guards_against_dist_as_source(self) -> None:
        script = self._read_repo_file("scripts/create_windows_msi.ps1")

        self.assertIn("function Assert-ValidSourceDirectory", script)
        self.assertIn("SourceDir points to dist output", script)
        self.assertIn("build/windows/x64/runner/Release", script)
        self.assertIn("Assert-ValidSourceDirectory -ResolvedSourceDir $resolvedSourceDir", script)

    def test_create_windows_msi_allows_same_version_major_upgrades_for_reruns(self) -> None:
        script = self._read_repo_file("scripts/create_windows_msi.ps1")

        self.assertIn(
            '<MajorUpgrade AllowSameVersionUpgrades="yes" DowngradeErrorMessage="A newer version of [ProductName] is already installed." />',
            script,
        )

    def test_install_script_can_disable_msi_auto_launch_for_manual_launch_mode(self) -> None:
        script = self._read_repo_file("scripts/install_windows_msi.ps1")

        self.assertIn("if ($LaunchAfterInstall)", script)
        self.assertIn("'SECONDLOOP_LAUNCH_AFTER_INSTALL=0'", script)
        self.assertIn("[string]$InstallDirName = 'SecondLoop'", script)
        self.assertIn("[string]$ExecutableName = 'secondloop.exe'", script)
        self.assertIn("[int]$LaunchProbeTimeoutSeconds = 15", script)
        self.assertIn("Start-Sleep -Milliseconds 500", script)
        self.assertIn(
            "Get-ChildItem -Path $programsRoot -Filter $Executable -File -Recurse -ErrorAction SilentlyContinue",
            script,
        )

    def test_run_windows_msi_uses_dedicated_dev_upgrade_identity(self) -> None:
        script = self._read_repo_file("scripts/run_windows.ps1")

        self.assertIn("$devProductName = 'SecondLoop Dev'", script)
        self.assertIn("$devUpgradeCode = 'A8A3E3A2-3C6E-4D9D-BD70-82D59F8CF0B2'", script)
        self.assertIn("-DisableCloseApplication", script)
        self.assertIn("-ProductName $devProductName", script)
        self.assertIn("-UpgradeCode $devUpgradeCode", script)

    def test_package_windows_msi_keeps_close_application_enabled_by_default(self) -> None:
        script = self._read_repo_file("scripts/package_windows_msi.ps1")

        self.assertIn("[switch]$DisableCloseApplication", script)
        self.assertIn("if ($DisableCloseApplication)", script)
        self.assertIn("$createArgs.DisableCloseApplication = $true", script)

    def test_run_windows_and_uninstall_scripts_close_only_dev_install_path(self) -> None:
        run_script = self._read_repo_file("scripts/run_windows.ps1")
        uninstall_script = self._read_repo_file("scripts/uninstall_windows_msi.ps1")
        helper_script = self._read_repo_file("scripts/stop_windows_installed_app.ps1")

        self.assertIn("stop_windows_installed_app.ps1", run_script)
        self.assertIn("-InstallDirName $devProductName", run_script)
        self.assertIn("stop_windows_installed_app.ps1", uninstall_script)
        self.assertIn("[string]$InstallDirName = 'SecondLoop Dev'", uninstall_script)
        self.assertIn("Programs\\$DirectoryName\\$FileName", helper_script)
        self.assertIn("CloseMainWindow", helper_script)
        self.assertIn("Stop-Process -Id", helper_script)

    def test_run_windows_script_uses_local_fvm_runner_for_flutter_and_dart_commands(self) -> None:
        script = self._read_repo_file("scripts/run_windows.ps1")

        self.assertIn("run_fvm_tool.ps1", script)
        self.assertIn("-Tool flutter -Command pub get", script)
        self.assertIn("-Tool dart -Command run tools/prepare_desktop_runtime.dart", script)
        self.assertIn("-Tool dart -Command run tools/sync_desktop_runtime_to_appdir.dart", script)
        self.assertIn("-Tool flutter -Command run -d windows", script)
        self.assertNotIn("dart pub global run fvm:main flutter run -d windows", script)

    def test_package_windows_msi_script_uses_local_fvm_runner_for_flutter_and_dart_commands(self) -> None:
        script = self._read_repo_file("scripts/package_windows_msi.ps1")

        self.assertIn("run_fvm_tool.ps1", script)
        self.assertIn("-Tool flutter -Command pub get", script)
        self.assertIn("-Tool dart -Command run tools/prepare_desktop_runtime.dart", script)
        self.assertIn("-Tool dart -Command run tools/sync_desktop_runtime_to_appdir.dart", script)
        self.assertIn("-Tool flutter -Command build windows --release", script)
        self.assertNotIn("dart pub global run fvm:main flutter pub get", script)


if __name__ == "__main__":
    unittest.main()
