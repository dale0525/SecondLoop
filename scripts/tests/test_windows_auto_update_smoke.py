from __future__ import annotations

from pathlib import Path
import unittest


REPO_ROOT = Path(__file__).resolve().parents[2]
SMOKE_SCRIPT = REPO_ROOT / "scripts/windows_auto_update_smoke.ps1"
HTTPS_SERVER = REPO_ROOT / "tools/windows_https_update_server.py"


class WindowsAutoUpdateSmokeTests(unittest.TestCase):
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
