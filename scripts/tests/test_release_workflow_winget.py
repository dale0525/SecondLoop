from __future__ import annotations

from pathlib import Path
import subprocess
import sys
import tempfile
import unittest


class ReleaseWorkflowWingetTests(unittest.TestCase):
    def _workflow_text(self) -> str:
        workflow_path = Path(__file__).resolve().parents[2] / ".github/workflows/release.yml"
        return workflow_path.read_text(encoding="utf-8")

    def _publish_winget_script_text(self) -> str:
        script_path = Path(__file__).resolve().parents[2] / "scripts/publish_winget_manifest.sh"
        return script_path.read_text(encoding="utf-8")

    def _generate_winget_script_text(self) -> str:
        script_path = Path(__file__).resolve().parents[2] / "scripts/generate_winget_manifests.py"
        return script_path.read_text(encoding="utf-8")

    def test_release_workflow_generates_winget_manifests(self) -> None:
        workflow_text = self._workflow_text()

        self.assertIn("Generate WinGet manifests", workflow_text)
        self.assertIn("scripts/generate_winget_manifests.py", workflow_text)
        self.assertIn('installer_path="dist/SecondLoop-win.msi"', workflow_text)
        self.assertIn('metadata_path="dist/SecondLoop-win.metadata.json"', workflow_text)
        self.assertIn("--installer-metadata-path", workflow_text)
        self.assertNotIn("find dist -maxdepth 1 -type f -iname '*.msi'", workflow_text)
        self.assertIn("dist/SecondLoop-win.msi", workflow_text)
        self.assertIn("dist/*Setup*.exe", workflow_text)
        self.assertIn("Using installer for WinGet manifest", workflow_text)
        self.assertIn("SecondLoop.SecondLoop", workflow_text)
        self.assertIn("dist/winget-manifests", workflow_text)
        self.assertIn("SecondLoop-winget-manifests-${GITHUB_REF_NAME}.zip", workflow_text)

    def test_windows_release_publishes_msi_checksum_asset(self) -> None:
        workflow_text = self._workflow_text()

        self.assertIn('SecondLoop-win.msi.sha256', workflow_text)
        self.assertIn('dist/SecondLoop-win.msi.sha256', workflow_text)

    def test_release_workflow_publishes_winget_manifest_bundle(self) -> None:
        workflow_text = self._workflow_text()

        self.assertIn("dist/SecondLoop-winget-manifests-*.zip", workflow_text)

    def test_release_workflow_publishes_winget_pr_to_winget_pkgs(self) -> None:
        workflow_text = self._workflow_text()

        self.assertIn("publish_winget_manifest:", workflow_text)
        self.assertIn("WINGET_PKGS_TOKEN", workflow_text)
        self.assertIn("microsoft/winget-pkgs", workflow_text)
        self.assertIn("scripts/publish_winget_manifest.sh", workflow_text)
        self.assertIn("WINGET_AUTO_AGREE_CLA", workflow_text)
        self.assertIn("WINGET_CLA_COMPANY", workflow_text)
        self.assertIn('--auto-agree-cla="${WINGET_AUTO_AGREE_CLA}"', workflow_text)
        self.assertIn('--cla-company "${WINGET_CLA_COMPANY}"', workflow_text)

    def test_publish_winget_manifest_script_stages_then_checks_cached_diff(self) -> None:
        script_text = self._publish_winget_script_text()

        self.assertIn('git add "${target_rel_dir}"', script_text)
        self.assertIn("git diff --cached --quiet", script_text)

    def test_publish_winget_manifest_script_requires_msi_installer(self) -> None:
        script_text = self._publish_winget_script_text()

        self.assertIn('--pattern "SecondLoop-win.msi"', script_text)
        self.assertIn('--pattern "SecondLoop-win.metadata.json"', script_text)
        self.assertIn("Selected WinGet installer asset", script_text)
        self.assertIn("Selected WinGet installer metadata asset", script_text)
        self.assertIn('installer_path="${release_dir}/SecondLoop-win.msi"', script_text)
        self.assertIn('metadata_path="${release_dir}/SecondLoop-win.metadata.json"', script_text)
        self.assertIn("--installer-metadata-path", script_text)
        self.assertNotIn("*Setup*.exe", script_text)
        self.assertIn("No MSI installer asset found in release assets", script_text)
        self.assertIn("No installer metadata asset found in release assets", script_text)

    def test_publish_winget_manifest_script_can_post_cla_agreement_comment(self) -> None:
        script_text = self._publish_winget_script_text()

        self.assertIn("compose_cla_agreement_body", script_text)
        self.assertIn("has_cla_prompt_comment", script_text)
        self.assertIn("Contributor License Agreement", script_text)
        self.assertIn("microsoft-github-policy-service[bot]", script_text)
        self.assertIn("Skipping CLA auto-agreement", script_text)
        self.assertIn("@microsoft-github-policy-service agree", script_text)
        self.assertIn("gh pr comment", script_text)
        self.assertIn("--auto-agree-cla", script_text)
        self.assertIn("--cla-company", script_text)

    def test_publish_winget_manifest_script_resolves_upstream_default_branch(self) -> None:
        script_text = self._publish_winget_script_text()

        self.assertIn("resolve_upstream_default_branch", script_text)
        self.assertIn("defaultBranchRef", script_text)
        self.assertIn('upstream_default_branch="$(resolve_upstream_default_branch)"', script_text)
        self.assertIn('git fetch upstream "${upstream_default_branch}" --depth=1', script_text)
        self.assertIn('--base "${upstream_default_branch}"', script_text)
        self.assertNotIn("git fetch upstream master --depth=1", script_text)

    def test_publish_winget_manifest_script_uses_update_pr_title(self) -> None:
        script_text = self._publish_winget_script_text()

        self.assertIn('--title "Update: ${package_id} version ${version}"', script_text)
        self.assertNotIn('--title "Add ${package_id} version ${version}"', script_text)

    def test_publish_winget_manifest_script_polls_for_cla_prompt(self) -> None:
        script_text = self._publish_winget_script_text()

        self.assertIn("wait_for_cla_prompt_comment", script_text)
        self.assertIn("WINGET_CLA_WAIT_ATTEMPTS", script_text)
        self.assertIn("WINGET_CLA_WAIT_SECONDS", script_text)
        self.assertIn("sleep", script_text)
        self.assertIn("Timed out waiting for CLA prompt", script_text)

    def test_release_workflow_exports_windows_msi_metadata_for_winget(self) -> None:
        workflow_text = self._workflow_text()

        self.assertIn("scripts/export_windows_msi_metadata.ps1", workflow_text)
        self.assertIn("--installer-metadata-path", workflow_text)

    def test_publish_winget_manifest_script_passes_installer_metadata_to_generator(self) -> None:
        script_text = self._publish_winget_script_text()

        self.assertIn("SecondLoop-win.metadata.json", script_text)
        self.assertIn("--installer-metadata-path", script_text)

    def test_release_workflow_validates_winget_manifest_before_external_publish(self) -> None:
        workflow_text = self._workflow_text()
        validate_script_text = (
            Path(__file__).resolve().parents[2] / "scripts/validate_winget_manifest.ps1"
        ).read_text(encoding="utf-8")

        self.assertIn("validate_winget_manifest:", workflow_text)
        self.assertIn("scripts/validate_winget_manifest.ps1", workflow_text)
        self.assertIn("winget validate --manifest", validate_script_text)
        self.assertIn("$resolvedManifestDir", validate_script_text)
        self.assertNotIn(
            "& winget validate --manifest $installerManifest.FullName",
            validate_script_text,
        )
        self.assertIn("needs: [publish, validate_winget_manifest]", workflow_text)

    def test_release_workflow_writes_separate_release_and_winget_status_summaries(self) -> None:
        workflow_text = self._workflow_text()

        self.assertIn("GITHUB_STEP_SUMMARY", workflow_text)
        self.assertIn("GitHub Release published", workflow_text)
        self.assertIn("WinGet manifest validation", workflow_text)
        self.assertIn("WinGet upstream PR publication", workflow_text)

    def test_release_checklist_documents_manual_windows_sandbox_validation(self) -> None:
        checklist_text = (
            Path(__file__).resolve().parents[2] / "RELEASE_CHECKLIST.md"
        ).read_text(encoding="utf-8")

        self.assertIn("SandboxTest.ps1", checklist_text)
        self.assertIn("self-hosted", checklist_text)
        self.assertIn("manual", checklist_text)

    def test_generate_winget_manifest_script_uses_manifest_schema_1_10(self) -> None:
        script_text = self._generate_winget_script_text()

        self.assertIn('MANIFEST_VERSION = "1.10.0"', script_text)
        self.assertNotIn("ManifestVersion: 1.9.0", script_text)

    def test_generate_winget_manifest_script_declares_vcredist_dependency(self) -> None:
        script_text = self._generate_winget_script_text()

        self.assertIn("Dependencies:", script_text)
        self.assertIn("PackageDependencies:", script_text)
        self.assertIn("Microsoft.VCRedist.2015+.x64", script_text)

    def test_generate_winget_manifest_script_infers_installer_type_from_extension(self) -> None:
        script_text = self._generate_winget_script_text()

        self.assertIn("def infer_installer_type", script_text)
        self.assertIn('if suffix == ".exe"', script_text)
        self.assertIn('if suffix == ".msi"', script_text)

    def test_generate_winget_manifest_script_emits_schema_headers(self) -> None:
        script_path = (
            Path(__file__).resolve().parents[2] / "scripts/generate_winget_manifests.py"
        )
        with tempfile.TemporaryDirectory() as tmp_dir:
            tmp_root = Path(tmp_dir)
            installer_path = tmp_root / "SecondLoop-win-Setup.exe"
            installer_path.write_bytes(b"test-installer")
            output_dir = tmp_root / "out"

            subprocess.run(
                [
                    sys.executable,
                    str(script_path),
                    "--release-tag",
                    "v1.20.0",
                    "--repo",
                    "dale0525/SecondLoop",
                    "--installer-path",
                    str(installer_path),
                    "--output-dir",
                    str(output_dir),
                    "--package-identifier",
                    "SecondLoop.SecondLoop",
                ],
                check=True,
                capture_output=True,
                text=True,
            )

            version_manifest = (output_dir / "SecondLoop.SecondLoop.yaml").read_text(
                encoding="utf-8"
            )
            installer_manifest = (
                output_dir / "SecondLoop.SecondLoop.installer.yaml"
            ).read_text(encoding="utf-8")
            locale_manifest = (
                output_dir / "SecondLoop.SecondLoop.locale.en-US.yaml"
            ).read_text(encoding="utf-8")

            self.assertTrue(
                version_manifest.startswith(
                    "# yaml-language-server: $schema=https://aka.ms/winget-manifest.version.1.10.0.schema.json"
                )
            )
            self.assertTrue(
                installer_manifest.startswith(
                    "# yaml-language-server: $schema=https://aka.ms/winget-manifest.installer.1.10.0.schema.json"
                )
            )
            self.assertIn("InstallerType: exe", installer_manifest)
            self.assertIn("Scope: user", installer_manifest)
            self.assertIn("InstallerSwitches:", installer_manifest)
            self.assertIn("Silent: --silent", installer_manifest)
            self.assertIn("Dependencies:", installer_manifest)
            self.assertIn("Microsoft.VCRedist.2015+.x64", installer_manifest)
            self.assertTrue(
                locale_manifest.startswith(
                    "# yaml-language-server: $schema=https://aka.ms/winget-manifest.defaultLocale.1.10.0.schema.json"
                )
            )

    def test_generate_winget_manifest_script_emits_msi_installer_without_exe_switches(self) -> None:
        script_path = (
            Path(__file__).resolve().parents[2] / "scripts/generate_winget_manifests.py"
        )
        with tempfile.TemporaryDirectory() as tmp_dir:
            tmp_root = Path(tmp_dir)
            installer_path = tmp_root / "SecondLoop-win.msi"
            installer_path.write_bytes(b"test-installer")
            output_dir = tmp_root / "out"

            subprocess.run(
                [
                    sys.executable,
                    str(script_path),
                    "--release-tag",
                    "v1.20.0",
                    "--repo",
                    "dale0525/SecondLoop",
                    "--installer-path",
                    str(installer_path),
                    "--output-dir",
                    str(output_dir),
                    "--package-identifier",
                    "SecondLoop.SecondLoop",
                ],
                check=True,
                capture_output=True,
                text=True,
            )

            installer_manifest = (
                output_dir / "SecondLoop.SecondLoop.installer.yaml"
            ).read_text(encoding="utf-8")

            self.assertIn("InstallerType: msi", installer_manifest)
            self.assertNotIn("Scope: user", installer_manifest)
            self.assertIn("Dependencies:", installer_manifest)
            self.assertIn("Microsoft.VCRedist.2015+.x64", installer_manifest)
            self.assertIn("InstallModes:", installer_manifest)
            self.assertIn("- silent", installer_manifest)
            self.assertIn("- silentWithProgress", installer_manifest)
            self.assertNotIn("- interactive", installer_manifest)
            self.assertIn("InstallerSwitches:", installer_manifest)
            self.assertIn("Custom: SECONDLOOP_LAUNCH_AFTER_INSTALL=0", installer_manifest)
            self.assertNotIn("Silent: --silent", installer_manifest)


if __name__ == "__main__":
    unittest.main()
