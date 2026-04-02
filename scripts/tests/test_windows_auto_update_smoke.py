from __future__ import annotations

from pathlib import Path
import shutil
import subprocess
import unittest


REPO_ROOT = Path(__file__).resolve().parents[2]
SMOKE_SCRIPT = REPO_ROOT / "scripts/windows_auto_update_smoke.ps1"
HTTPS_SERVER = REPO_ROOT / "tools/windows_https_update_server.py"


class WindowsAutoUpdateSmokeTests(unittest.TestCase):
    def _find_powershell(self) -> str:
        for candidate in ("pwsh", "powershell.exe", "powershell"):
            resolved = shutil.which(candidate)
            if resolved:
                return resolved
        self.skipTest("PowerShell is not available in PATH")

    def test_smoke_script_parses_as_valid_powershell(self) -> None:
        powershell = self._find_powershell()
        command = [
            powershell,
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

    def test_smoke_script_parameterizes_app_name_with_pack_id_default(self) -> None:
        script = SMOKE_SCRIPT.read_text(encoding="utf-8")

        self.assertIn("[string]$AppName = ''", script)
        self.assertIn("function Get-DefaultAppName", script)
        self.assertIn("$env:SECONDLOOP_APP_NAME = $AppName", script)
        self.assertNotIn("$env:SECONDLOOP_APP_NAME = 'SecondLoop Dev'", script)

    def test_smoke_script_targets_exact_channel_versioned_full_package(self) -> None:
        script = SMOKE_SCRIPT.read_text(encoding="utf-8")

        self.assertIn("function Get-ExpectedFullPackageFileName", script)
        self.assertIn("$legacyPackageName = \"$PackId-$versionName-full.nupkg\"", script)
        self.assertIn("if ($Channel -eq 'win')", script)
        self.assertIn(
            "$expectedPackageFileName = Get-ExpectedFullPackageFileName -VersionValue $NewVersion",
            script,
        )

    def test_smoke_script_uses_dotnet_sha256_for_powershell_compatibility(self) -> None:
        script = SMOKE_SCRIPT.read_text(encoding="utf-8")

        self.assertIn("[System.Security.Cryptography.SHA256]::Create()", script)
        self.assertNotIn("Get-FileHash", script)

    def test_smoke_script_writes_pubspec_without_utf8_bom(self) -> None:
        script = SMOKE_SCRIPT.read_text(encoding="utf-8")

        self.assertIn("function Write-Utf8NoBomFile", script)
        self.assertIn("System.Text.UTF8Encoding($false)", script)
        self.assertNotIn("Set-Content -LiteralPath $PubspecPath -Value $updated -Encoding utf8", script)

    def test_smoke_script_restores_pubspec_only_in_finally(self) -> None:
        script = SMOKE_SCRIPT.read_text(encoding="utf-8")

        self.assertEqual(
            1,
            script.count("Write-Utf8NoBomFile -Path $pubspecPath -Content $originalPubspec"),
        )

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

    def test_smoke_script_waits_for_installed_version_without_build_metadata(self) -> None:
        script = SMOKE_SCRIPT.read_text(encoding="utf-8")

        self.assertIn("$expectedVersionName = Get-VersionName $ExpectedVersion", script)
        self.assertIn("if ($currentVersion -eq $expectedVersionName)", script)
        self.assertIn(
            'throw "Timed out waiting for installed version $expectedVersionName. Current=$(Get-InstalledVersion)"',
            script,
        )

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
        self.assertIn("'--windows-app-id', $PackId", script)
        self.assertIn("'--windows-channel', $Channel", script)
        self.assertIn("'--app-name', $AppName", script)
        self.assertNotIn("'--package', $packageFile.FullName", script)
        self.assertNotIn("Start-ObservedProcess -FilePath $updateExe", script)

    def test_smoke_script_accepts_staged_package_by_exact_name_without_hash_match(self) -> None:
        script = SMOKE_SCRIPT.read_text(encoding="utf-8")

        self.assertIn("function Wait-ForStagedPackage", script)
        self.assertNotIn("[string]$ExpectedSha256", script)
        self.assertNotIn("Get-FileSha256Hex -PathValue $candidate", script)
        self.assertIn(
            "$stagedPackage = Wait-ForStagedPackage -ExpectedFileName $expectedPackageFile.Name",
            script,
        )

    def test_smoke_script_restores_certificate_trust_and_signing_env(self) -> None:
        script = SMOKE_SCRIPT.read_text(encoding="utf-8")

        self.assertIn("function Remove-TrustedCertificateByThumbprint", script)
        self.assertIn("Remove-TrustedCertificateByThumbprint -Thumbprint $trustedCertificateThumbprint", script)
        self.assertIn("SECONDLOOP_UPDATE_SIGNING_PRIVATE_KEY", script)
        self.assertIn("Set-Item -Path Env:SECONDLOOP_UPDATE_PUBLIC_KEY -Value $originalUpdatePublicKey", script)

    def test_smoke_script_restores_temporary_update_environment_variables(self) -> None:
        script = SMOKE_SCRIPT.read_text(encoding="utf-8")

        self.assertIn(
            "$hadOriginalReleaseApiOrigin = Test-Path Env:SECONDLOOP_RELEASE_API_ORIGIN",
            script,
        )
        self.assertIn("$hadOriginalAppId = Test-Path Env:SECONDLOOP_APP_ID", script)
        self.assertIn("$hadOriginalAppName = Test-Path Env:SECONDLOOP_APP_NAME", script)
        self.assertIn(
            "Set-Item -Path Env:SECONDLOOP_RELEASE_API_ORIGIN -Value $originalReleaseApiOrigin",
            script,
        )
        self.assertIn(
            "Remove-Item Env:SECONDLOOP_RELEASE_API_ORIGIN -ErrorAction SilentlyContinue",
            script,
        )
        self.assertIn("Set-Item -Path Env:SECONDLOOP_APP_ID -Value $originalAppId", script)
        self.assertIn(
            "Remove-Item Env:SECONDLOOP_APP_ID -ErrorAction SilentlyContinue",
            script,
        )
        self.assertIn(
            "Set-Item -Path Env:SECONDLOOP_APP_NAME -Value $originalAppName",
            script,
        )
        self.assertIn(
            "Remove-Item Env:SECONDLOOP_APP_NAME -ErrorAction SilentlyContinue",
            script,
        )

    def test_smoke_script_rejects_skip_certificate_trust_mode(self) -> None:
        script = SMOKE_SCRIPT.read_text(encoding="utf-8")

        self.assertIn("SkipCertificateTrust cannot be used", script)
        self.assertNotIn("Skipping localhost certificate trust step.", script)

    def test_smoke_script_generates_and_uses_temporary_manifest_signing_keys(self) -> None:
        script = SMOKE_SCRIPT.read_text(encoding="utf-8")

        self.assertIn("tools/generate_update_signing_keypair.dart", script)
        self.assertIn("$env:SECONDLOOP_UPDATE_SIGNING_PRIVATE_KEY", script)
        self.assertIn("$env:SECONDLOOP_UPDATE_PUBLIC_KEY", script)
        self.assertIn("'--signing-private-key'", script)

    def test_smoke_script_requires_pixi_managed_python(self) -> None:
        script = SMOKE_SCRIPT.read_text(encoding="utf-8")

        self.assertIn(".pixi/envs/default/python.exe", script)
        self.assertNotIn("Get-Command python", script)

    def test_smoke_script_only_cleans_up_certificate_when_it_imported_it(self) -> None:
        script = SMOKE_SCRIPT.read_text(encoding="utf-8")

        self.assertIn("function Test-CertificateTrustedInCurrentUserRoot", script)
        self.assertIn("$certificateTrustAddedByScript = $false", script)
        self.assertIn("$wasCertificateTrustedBefore = Test-CertificateTrustedInCurrentUserRoot", script)
        self.assertIn("$certificateTrustAddedByScript = -not $wasCertificateTrustedBefore", script)
        self.assertIn("if ($certificateTrustAddedByScript) {", script)

    def test_smoke_script_fails_fast_when_https_server_exits_early(self) -> None:
        script = SMOKE_SCRIPT.read_text(encoding="utf-8")

        self.assertIn("HTTPS update server exited early.", script)
        self.assertIn("$process.HasExited", script)

    def test_https_server_exposes_latest_release_endpoint(self) -> None:
        self.assertTrue(HTTPS_SERVER.exists())

        server = HTTPS_SERVER.read_text(encoding="utf-8")

        self.assertIn("/api/releases/latest", server)
        self.assertIn("ThreadingHTTPServer", server)
        self.assertIn("ssl", server)
        self.assertIn("latest.json", server)
        self.assertIn('normalized in {"/downloads", "/downloads/"}', server)


if __name__ == "__main__":
    unittest.main()
