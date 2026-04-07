from __future__ import annotations

import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest


class GenerateWingetManifestMetadataTests(unittest.TestCase):
    def test_create_windows_msi_script_uses_public_secondloop_manufacturer_by_default(self) -> None:
        script_text = (
            Path(__file__).resolve().parents[2] / 'scripts/create_windows_msi.ps1'
        ).read_text(encoding='utf-8')

        self.assertIn("[string]$Manufacturer = 'SecondLoop'", script_text)

    def test_package_windows_msi_script_uses_public_secondloop_manufacturer_by_default(self) -> None:
        script_text = (
            Path(__file__).resolve().parents[2] / 'scripts/package_windows_msi.ps1'
        ).read_text(encoding='utf-8')

        self.assertIn("[string]$Manufacturer = 'SecondLoop'", script_text)
        self.assertNotIn("[string]$Manufacturer = 'SecondLoop Contributors'", script_text)

    def test_export_windows_msi_metadata_script_normalizes_com_property_scalars(self) -> None:
        script_text = (
            Path(__file__).resolve().parents[2]
            / 'scripts/export_windows_msi_metadata.ps1'
        ).read_text(encoding='utf-8')

        self.assertIn('StringData(1)', script_text)
        self.assertIn('$null = $view.Execute()', script_text)
        self.assertNotIn('  $view.Execute()', script_text)
        self.assertNotIn('return $record.StringData(1)', script_text)

    def test_generate_winget_manifest_script_emits_msi_arp_fields_from_metadata_json(self) -> None:
        script_path = (
            Path(__file__).resolve().parents[2] / 'scripts/generate_winget_manifests.py'
        )
        with tempfile.TemporaryDirectory() as tmp_dir:
            tmp_root = Path(tmp_dir)
            installer_path = tmp_root / 'SecondLoop-win.msi'
            installer_path.write_bytes(b'test-installer')
            metadata_path = tmp_root / 'installer-metadata.json'
            metadata_path.write_text(
                json.dumps(
                    {
                        'packageName': 'SecondLoop',
                        'publisher': 'SecondLoop',
                        'productCode': '{11111111-1111-1111-1111-111111111111}',
                        'upgradeCode': '{22222222-2222-2222-2222-222222222222}',
                        'packageVersion': '1.20.0',
                        'installerType': 'msi',
                    }
                ),
                encoding='utf-8',
            )
            output_dir = tmp_root / 'out'

            subprocess.run(
                [
                    sys.executable,
                    str(script_path),
                    '--release-tag',
                    'v1.20.0',
                    '--repo',
                    'dale0525/SecondLoop',
                    '--installer-path',
                    str(installer_path),
                    '--installer-metadata-path',
                    str(metadata_path),
                    '--output-dir',
                    str(output_dir),
                    '--package-identifier',
                    'SecondLoop.SecondLoop',
                ],
                check=True,
                capture_output=True,
                text=True,
            )

            installer_manifest = (
                output_dir / 'SecondLoop.SecondLoop.installer.yaml'
            ).read_text(encoding='utf-8')
            locale_manifest = (
                output_dir / 'SecondLoop.SecondLoop.locale.en-US.yaml'
            ).read_text(encoding='utf-8')

            self.assertIn(
                "ProductCode: '{11111111-1111-1111-1111-111111111111}'",
                installer_manifest,
            )
            self.assertIn('AppsAndFeaturesEntries:', installer_manifest)
            self.assertIn('DisplayName: SecondLoop', installer_manifest)
            self.assertIn('Publisher: SecondLoop', installer_manifest)
            self.assertIn(
                "UpgradeCode: '{22222222-2222-2222-2222-222222222222}'",
                installer_manifest,
            )
            self.assertIn('Publisher: SecondLoop', locale_manifest)
            self.assertIn('PackageName: SecondLoop', locale_manifest)

    def test_generate_winget_manifest_script_emits_vcredist_dependency_for_msi(self) -> None:
        script_path = (
            Path(__file__).resolve().parents[2] / 'scripts/generate_winget_manifests.py'
        )
        with tempfile.TemporaryDirectory() as tmp_dir:
            tmp_root = Path(tmp_dir)
            installer_path = tmp_root / 'SecondLoop-win.msi'
            installer_path.write_bytes(b'test-installer')
            output_dir = tmp_root / 'out'

            subprocess.run(
                [
                    sys.executable,
                    str(script_path),
                    '--release-tag',
                    'v1.20.0',
                    '--repo',
                    'dale0525/SecondLoop',
                    '--installer-path',
                    str(installer_path),
                    '--output-dir',
                    str(output_dir),
                    '--package-identifier',
                    'SecondLoop.SecondLoop',
                ],
                check=True,
                capture_output=True,
                text=True,
            )

            installer_manifest = (
                output_dir / 'SecondLoop.SecondLoop.installer.yaml'
            ).read_text(encoding='utf-8')

            self.assertIn('Dependencies:', installer_manifest)
            self.assertIn('PackageDependencies:', installer_manifest)
            self.assertIn('Microsoft.VCRedist.2015+.x64', installer_manifest)


if __name__ == '__main__':
    unittest.main()
