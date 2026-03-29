from __future__ import annotations

from pathlib import Path
import subprocess
import unittest


REPO_ROOT = Path(__file__).resolve().parents[2]
SMOKE_SCRIPT = REPO_ROOT / "scripts/windows_auto_update_smoke.ps1"
HTTPS_SERVER = REPO_ROOT / "tools/windows_https_update_server.py"


class WindowsAutoUpdateSmokeTests(unittest.TestCase):
    def test_smoke_script_parses_as_valid_powershell(self) -> None:
        command = [
            "powershell.exe",
            "-NoProfile",
            "-Command",
            (
                "$errors = $null; "
                "[System.Management.Automation.Language.Parser]::ParseFile("
                f"'{SMOKE_SCRIPT}', [ref]$null, [ref]$errors) | Out-Null; "
                "if ($errors.Count -gt 0) { "
                "  $errors | ForEach-Object { Write-Error $_.Message }; "
                "  exit 1 "
                "}"
            ),
        ]

        completed = subprocess.run(command, capture_output=True, text=True, check=False)

        self.assertEqual(
            0,
            completed.returncode,
            msg=(completed.stdout + completed.stderr).strip(),
        )

    def test_smoke_script_parameterizes_installed_exe_name_and_process_name(self) -> None:
        script = SMOKE_SCRIPT.read_text(encoding="utf-8")

        self.assertIn("[string]$ExeName = 'secondloop.exe'", script)
        self.assertIn("function Get-InstalledProcessName", script)
        self.assertIn("[System.IO.Path]::GetFileNameWithoutExtension($ExeName)", script)
        self.assertNotIn("Get-Process -Name 'secondloop'", script)

    def test_smoke_script_targets_exact_channel_versioned_full_package(self) -> None:
        script = SMOKE_SCRIPT.read_text(encoding="utf-8")

        self.assertIn("function Get-ExpectedFullPackageFileName", script)
        self.assertIn("return \"$PackId-$versionName-$Channel-full.nupkg\"", script)
        self.assertIn(
            "$expectedPackageFileName = Get-ExpectedFullPackageFileName -VersionValue $NewVersion",
            script,
        )

    def test_smoke_script_uses_dotnet_sha256_for_powershell_compatibility(self) -> None:
        script = SMOKE_SCRIPT.read_text(encoding="utf-8")

        self.assertIn("[System.Security.Cryptography.SHA256]::Create()", script)
        self.assertNotIn("Get-FileHash", script)

    def test_smoke_script_requires_unambiguous_setup_executable(self) -> None:
        script = SMOKE_SCRIPT.read_text(encoding="utf-8")

        self.assertIn("function Get-SetupExecutable", script)
        self.assertIn("$setupCandidates.Count -eq 0", script)
        self.assertIn("$setupCandidates.Count -gt 1", script)
        self.assertIn("Get-SetupExecutable -OutputDir $v1Output", script)

    def test_smoke_script_rechecks_running_process_after_stabilization_delay(self) -> None:
        script = SMOKE_SCRIPT.read_text(encoding="utf-8")

        self.assertIn("function Get-RunningInstalledProcesses", script)
        self.assertIn("$matching = @(Get-RunningInstalledProcesses)", script)
        self.assertIn("$stableMatching = @(Get-RunningInstalledProcesses)", script)

    def test_smoke_script_uses_manifest_driven_stage_then_restart_flow(self) -> None:
        self.assertTrue(SMOKE_SCRIPT.exists())

        script = SMOKE_SCRIPT.read_text(encoding="utf-8")

        self.assertIn("1.0.0+1", script)
        self.assertIn("1.0.1+1", script)
        self.assertIn("latest.json", script)
        self.assertIn("/api/releases/latest", script)
        self.assertIn("com.secondloop.secondloopdev", script)
        self.assertIn("Wait-ForStagedPackage", script)
        self.assertIn("Wait-ForRunningInstalledProcess", script)
        self.assertIn("Get-FullPackage", script)
        self.assertIn("tools/windows_https_update_server.py", script)
        self.assertNotIn("'--package', $packageFile.FullName", script)
        self.assertNotIn("Start-ObservedProcess -FilePath $updateExe", script)

    def test_https_server_exposes_latest_release_endpoint(self) -> None:
        self.assertTrue(HTTPS_SERVER.exists())

        server = HTTPS_SERVER.read_text(encoding="utf-8")

        self.assertIn("/api/releases/latest", server)
        self.assertIn("ThreadingHTTPServer", server)
        self.assertIn("ssl", server)
        self.assertIn("latest.json", server)


if __name__ == "__main__":
    unittest.main()
