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
            '<CustomAction Id="LaunchApplication" Directory="INSTALLFOLDER" ExeCommand="secondloop.exe" Return="asyncNoWait" Impersonate="yes" />',
            script,
        )
        self.assertIn(
            '<Custom Action="LaunchApplication" After="InstallFinalize">SECONDLOOP_LAUNCH_AFTER_INSTALL = "1" AND NOT Installed AND UILevel >= 3</Custom>',
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
        self.assertIn("-ProductName $devProductName", script)
        self.assertIn("-UpgradeCode $devUpgradeCode", script)


if __name__ == "__main__":
    unittest.main()
