from __future__ import annotations

from pathlib import Path
import unittest


class WindowsMsiInstallFlowTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.repo_root = Path(__file__).resolve().parents[2]

    def _read_repo_file(self, relative_path: str) -> str:
        return (self.repo_root / relative_path).read_text(encoding="utf-8")

    def _extract_function_body(self, script: str, function_name: str) -> str:
        marker = f"function {function_name}"
        start = script.find(marker)
        self.assertNotEqual(start, -1, f"{function_name} not found")

        brace_start = script.find("{", start)
        self.assertNotEqual(brace_start, -1, f"{function_name} body not found")

        depth = 0
        for index in range(brace_start, len(script)):
            char = script[index]
            if char == "{":
                depth += 1
            elif char == "}":
                depth -= 1
                if depth == 0:
                    return script[brace_start + 1 : index]

        self.fail(f"{function_name} body was not closed")

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
        self.assertIn("$componentRegistryKey = \"$ProductRegistryKey\\Installer\\Components\"", script)
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

    def test_create_windows_msi_does_not_purge_user_data_on_standard_uninstall(self) -> None:
        script = self._read_repo_file("scripts/create_windows_msi.ps1")

        self.assertNotIn("SECONDLOOP_APPDATA_CLEANUP_PATH", script)
        self.assertNotIn("SECONDLOOP_LOCALAPPDATA_CLEANUP_PATH", script)
        self.assertNotIn("RemoveSecondLoopAppData", script)
        self.assertNotIn("RemoveSecondLoopLocalAppData", script)
        self.assertNotIn("RemoveFolderEx", script)

    def test_create_windows_msi_uses_product_specific_registry_cleanup_keys(self) -> None:
        script = self._read_repo_file("scripts/create_windows_msi.ps1")

        self.assertIn("function Get-SafeRegistryKeyName", script)
        self.assertIn(
            "$safeProductRegistryKeyName = Get-SafeRegistryKeyName -Value $ProductName",
            script,
        )
        self.assertIn(
            "$productRegistryKey = \"Software\\SecondLoop\\$safeProductRegistryKeyName\"",
            script,
        )
        self.assertIn("ProductRegistryKey", script)
        self.assertIn("$componentRegistryKey = \"$ProductRegistryKey\\Installer\\Components\"", script)
        self.assertNotIn("$productRegistryKey = \"Software\\SecondLoop\\$ProductName\"", script)
        self.assertNotIn("Software\\SecondLoop\\Installer\\Components", script)
        self.assertNotIn("$shortcutRegKey = 'Software\\SecondLoop'", script)

    def test_create_windows_msi_persists_install_location_for_registry_matching(self) -> None:
        script = self._read_repo_file("scripts/create_windows_msi.ps1")

        self.assertIn(
            '<SetProperty Id="ARPINSTALLLOCATION" Value="[INSTALLFOLDER]" After="CostFinalize" Sequence="execute" />',
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
        self.assertIn("Join-Path 'Programs' $safeDirectoryName", helper_script)
        self.assertIn("$safeFileName = Get-SafePathComponent -Value $FileName", helper_script)
        self.assertIn("CloseMainWindow", helper_script)
        self.assertIn("Stop-Process -Id", helper_script)

    def test_uninstall_script_removes_residual_files_shortcuts_and_user_data(self) -> None:
        script = self._read_repo_file("scripts/uninstall_windows_msi.ps1")

        self.assertIn("[switch]$KeepUserData", script)
        self.assertIn("function Remove-UninstallResidue", script)
        self.assertIn("Remove-UninstallResidue @cleanupArgs", script)
        self.assertIn("function Get-InstallResidueDirectories", script)
        self.assertIn("Join-Path 'Programs' $safeInstallDirName", script)
        self.assertIn("Start Menu\\Programs' $safeProductName", script)
        self.assertIn("Join-Path 'com.secondloop' $safeProductName", script)
        self.assertIn("Get-ApplicationDataDirectories", script)
        self.assertIn("Get-ApplicationCacheDirectories", script)
        self.assertIn("if (-not $KeepUserData)", script)

    def test_uninstall_script_removes_user_data_by_directory_without_redundant_state_files(self) -> None:
        script = self._read_repo_file("scripts/uninstall_windows_msi.ps1")
        body = self._extract_function_body(script, "Remove-UninstallResidue")

        self.assertIn("foreach ($path in $appDataDirectories)", body)
        self.assertIn("foreach ($path in $appCacheDirectories)", body)
        self.assertNotIn("Get-ApplicationStateFiles", script)
        self.assertNotIn("shared_preferences.json", script)
        self.assertNotIn("flutter_secure_storage.dat", script)

    def test_uninstall_script_removes_residual_registry_entries_safely(self) -> None:
        script = self._read_repo_file("scripts/uninstall_windows_msi.ps1")

        self.assertIn("[string]$CompanyName = 'com.secondloop'", script)
        self.assertIn("[string]$AppId = ''", script)
        self.assertIn("function Remove-ResidualUninstallRegistryEntries", script)
        self.assertIn("function Remove-RegistryTreeIfEmpty", script)
        self.assertIn("Remove-RegistryTreeIfEmpty -RegistryPath 'HKCU:\\Software\\SecondLoop\\Installer'", script)
        self.assertIn("Remove-RegistryTreeIfEmpty -RegistryPath 'HKCU:\\Software\\SecondLoop'", script)
        self.assertIn("ProductCode", script)
        self.assertIn("InstallLocation", script)

    def test_uninstall_script_uses_allowlisted_install_location_for_cleanup(self) -> None:
        script = self._read_repo_file("scripts/uninstall_windows_msi.ps1")

        self.assertIn("function Test-IsPathEqualOrChild", script)
        self.assertIn("function Resolve-SafeInstallLocation", script)
        self.assertIn(
            "Resolve-SafeInstallLocation -InstallLocation $entryInstallLocation -ExpectedInstallLocation $expectedInstallLocationPath",
            script,
        )
        self.assertNotIn("$selectedInstallLocation = $entryInstallLocation", script)

    def test_uninstall_script_does_not_match_registry_entries_by_display_name_only(self) -> None:
        script = self._read_repo_file("scripts/uninstall_windows_msi.ps1")
        body = self._extract_function_body(script, "Test-RegistryEntryMatchesProduct")

        self.assertIn("Test-RegistryEntryHasSafeInstallLocation", body)
        self.assertIn("Resolve-ProductCode -Entry $Entry", body)
        self.assertIn("Test-RegistryEntryHasLegacyProductIdentity", body)
        self.assertIn("$hasLegacyProductIdentity = Test-RegistryEntryHasLegacyProductIdentity", body)
        self.assertIn("$hasSafeInstallLocation -and $hasLegacyProductIdentity", body)
        self.assertNotIn("if ($hasSafeInstallLocation) {\n    return $true\n  }", body)
        self.assertNotIn("$displayName -eq $ProductName -or", body)
        self.assertNotIn("$displayName -eq $ProductName", body)
        self.assertNotIn("if ($displayName -eq $ProductName) {\n    return $true\n  }", body)

        matching_entries_start = script.find("$matchingEntries = @(")
        self.assertNotEqual(matching_entries_start, -1, "matching entries block not found")
        matching_entries_end = script.find("\n)\n\n$selectedEntry", matching_entries_start)
        self.assertNotEqual(matching_entries_end, -1, "matching entries block was not closed")
        matching_entries_body = script[matching_entries_start:matching_entries_end]
        self.assertIn("Test-RegistryEntryMatchesProduct", matching_entries_body)
        self.assertIn("-Entry $_", matching_entries_body)
        self.assertIn("-ProductName $ProductName", matching_entries_body)
        self.assertIn("-Publisher $Publisher", matching_entries_body)
        self.assertNotIn("$displayName -eq $ProductName", matching_entries_body)

    def test_uninstall_script_supports_legacy_msi_entries_without_install_location_safely(self) -> None:
        script = self._read_repo_file("scripts/uninstall_windows_msi.ps1")
        body = self._extract_function_body(
            script,
            "Test-RegistryEntryHasLegacyProductIdentity",
        )

        self.assertIn("[string]$Publisher = 'SecondLoop'", script)
        self.assertIn("$displayName = Get-StringValue $Entry.DisplayName", body)
        self.assertIn("$entryPublisher = Get-StringValue $Entry.Publisher", body)
        self.assertIn("$entryProductCode = Resolve-ProductCode -Entry $Entry", body)
        self.assertIn("$displayName -ne $ProductName", body)
        self.assertIn("$entryPublisher -ne $Publisher", body)
        self.assertIn("[string]::IsNullOrWhiteSpace($entryProductCode)", body)

    def test_uninstall_script_residual_registry_cleanup_requires_product_identity(self) -> None:
        script = self._read_repo_file("scripts/uninstall_windows_msi.ps1")
        body = self._extract_function_body(script, "Remove-ResidualUninstallRegistryEntries")
        matcher_body = self._extract_function_body(script, "Test-RegistryEntryMatchesResidualCleanup")

        self.assertIn("ProductCode", body)
        self.assertIn("ExpectedInstallLocation", body)
        self.assertIn("ProductName", body)
        self.assertIn("Publisher", body)
        self.assertIn("Test-RegistryEntryMatchesResidualCleanup", body)
        self.assertIn("-ProductName $ProductName", body)
        self.assertIn("-Publisher $Publisher", body)
        self.assertNotIn("$displayName", body)
        self.assertIn("Test-RegistryEntryHasSafeInstallLocation", matcher_body)
        self.assertIn("Test-RegistryEntryHasLegacyProductIdentity", matcher_body)
        self.assertIn("$hasSafeInstallLocation -and $hasLegacyProductIdentity", matcher_body)

    def test_uninstall_script_removes_shared_registry_parent_only_when_empty(self) -> None:
        script = self._read_repo_file("scripts/uninstall_windows_msi.ps1")

        self.assertIn("function Test-RegistryTreeHasChildrenOrValues", script)
        self.assertIn("function Remove-RegistryTreeIfEmpty", script)
        self.assertIn(
            "Remove-RegistryTreeIfEmpty -RegistryPath 'HKCU:\\Software\\SecondLoop'",
            script,
        )
        self.assertNotIn("Test-AnySecondLoopInstallRemaining", script)

    def test_uninstall_script_removes_empty_application_data_parent_directories(self) -> None:
        script = self._read_repo_file("scripts/uninstall_windows_msi.ps1")

        self.assertIn("function Remove-EmptyDirectoryIfEmpty", script)
        self.assertIn("function Remove-EmptyApplicationDataParents", script)
        self.assertIn(
            "Remove-EmptyApplicationDataParents -ApplicationDirectories $appDataDirectories",
            script,
        )
        self.assertIn(
            "Remove-EmptyApplicationDataParents -ApplicationDirectories $appCacheDirectories",
            script,
        )

    def test_uninstall_script_fails_when_installed_entry_has_no_product_code(self) -> None:
        script = self._read_repo_file("scripts/uninstall_windows_msi.ps1")

        self.assertIn(
            "throw \"Unable to resolve MSI product code for '$ProductName'. UninstallString=$($selectedEntry.UninstallString)\"",
            script,
        )
        self.assertNotIn("Skipped msiexec.exe because no MSI product code was available", script)
        self.assertIn("Residual cleanup completed for missing package", script)

    def test_uninstall_script_preserves_user_data_when_package_entry_is_missing(self) -> None:
        script = self._read_repo_file("scripts/uninstall_windows_msi.ps1")

        self.assertIn("[switch]$ForceResidualUserDataCleanup", script)
        self.assertIn("$canRemoveUserData = $selectedEntry -or $ForceResidualUserDataCleanup", script)
        self.assertIn("if ($KeepUserData -or -not $canRemoveUserData)", script)
        self.assertIn("$cleanupArgs.KeepUserData = $true", script)

    def test_uninstall_script_sanitizes_user_controlled_path_components(self) -> None:
        script = self._read_repo_file("scripts/uninstall_windows_msi.ps1")
        storage_body = self._extract_function_body(script, "Get-AppStorageRelativePath")
        install_body = self._extract_function_body(script, "Get-InstallResidueDirectories")
        data_body = self._extract_function_body(script, "Get-ApplicationDataDirectories")
        cache_body = self._extract_function_body(script, "Get-ApplicationCacheDirectories")

        self.assertIn("$safeProductName = Get-SafeDirectoryName -Value $ResolvedProductName", storage_body)
        self.assertIn("Join-Path 'com.secondloop' $safeProductName", storage_body)
        self.assertNotIn("return \"com.secondloop\\$ResolvedProductName\"", storage_body)
        self.assertIn("$safeInstallDirName = Get-SafeDirectoryName -Value $InstallDirName", install_body)
        self.assertIn("$safeProductName = Get-SafeDirectoryName -Value $ProductName", install_body)
        self.assertIn("$safeAppId = Get-SafeDirectoryName -Value $AppId", install_body)
        self.assertIn("$safeAppId = Get-SafeDirectoryName -Value $AppId", data_body)
        self.assertIn("$safeAppId = Get-SafeDirectoryName -Value $AppId", cache_body)

    def test_run_windows_script_uses_local_fvm_runner_for_flutter_and_dart_commands(self) -> None:
        script = self._read_repo_file("scripts/run_windows.ps1")

        self.assertIn("run_fvm_tool.ps1", script)
        self.assertIn("-Tool flutter -Command pub get", script)
        self.assertNotIn("-Tool dart -Command run tools/prepare_desktop_runtime.dart", script)
        self.assertNotIn("-Tool dart -Command run tools/sync_desktop_runtime_to_appdir.dart", script)
        self.assertIn("-Tool flutter -Command run -d windows", script)
        self.assertNotIn("dart pub global run fvm:main flutter run -d windows", script)

    def test_package_windows_msi_script_uses_local_fvm_runner_for_flutter_and_dart_commands(self) -> None:
        script = self._read_repo_file("scripts/package_windows_msi.ps1")

        self.assertIn("run_fvm_tool.ps1", script)
        self.assertIn("-Tool flutter -Command pub get", script)
        self.assertNotIn("-Tool dart -Command run tools/prepare_desktop_runtime.dart", script)
        self.assertNotIn("-Tool dart -Command run tools/sync_desktop_runtime_to_appdir.dart", script)
        self.assertIn("-Tool flutter -Command build windows --release", script)
        self.assertNotIn("dart pub global run fvm:main flutter pub get", script)


if __name__ == "__main__":
    unittest.main()
