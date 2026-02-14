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
            '<Custom Action="LaunchApplication" After="InstallFinalize">SECONDLOOP_LAUNCH_AFTER_INSTALL = "1" AND NOT Installed AND UILevel >= 5</Custom>',
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


if __name__ == "__main__":
    unittest.main()
