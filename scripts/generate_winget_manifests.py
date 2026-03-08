#!/usr/bin/env python3
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
from textwrap import dedent

MANIFEST_VERSION = "1.10.0"


def compute_sha256_upper(path: Path) -> str:
    hasher = hashlib.sha256()
    with path.open("rb") as file_obj:
        for chunk in iter(lambda: file_obj.read(1024 * 1024), b""):
            hasher.update(chunk)
    return hasher.hexdigest().upper()


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Generate WinGet manifests for the current release.",
    )
    parser.add_argument("--release-tag", required=True, help="Release tag (vX.Y.Z)")
    parser.add_argument("--repo", required=True, help="Source repo (owner/name)")
    parser.add_argument(
        "--installer-path",
        required=True,
        help="Path to the Windows installer asset (.exe or .msi)",
    )
    parser.add_argument(
        "--installer-metadata-path",
        default="",
        help="Optional path to installer metadata JSON exported from the packaged installer",
    )
    parser.add_argument(
        "--output-dir",
        required=True,
        help="Directory where manifest yaml files will be written",
    )
    parser.add_argument(
        "--package-identifier",
        default="SecondLoop.SecondLoop",
        help="WinGet package identifier",
    )
    parser.add_argument(
        "--package-name",
        default="SecondLoop",
        help="WinGet package display name",
    )
    parser.add_argument(
        "--publisher",
        default="SecondLoop",
        help="WinGet publisher name",
    )
    parser.add_argument(
        "--publisher-url",
        default="https://secondloop.app",
        help="Publisher URL",
    )
    parser.add_argument(
        "--package-url",
        default="https://secondloop.app",
        help="Package homepage URL",
    )
    parser.add_argument(
        "--short-description",
        default="Local-first personal AI assistant with long-term memory.",
        help="Short package description",
    )
    return parser.parse_args()


def ensure_release_tag(tag: str) -> str:
    if not tag.startswith("v"):
        raise ValueError("release tag must start with 'v', for example v1.2.3")
    return tag[1:]


def write_manifest(path: Path, content: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(content, encoding="utf-8")


def schema_header(manifest_type: str) -> str:
    return (
        "# yaml-language-server: "
        f"$schema=https://aka.ms/winget-manifest.{manifest_type}.{MANIFEST_VERSION}.schema.json"
    )


def yaml_single_quoted(value: str) -> str:
    return "'" + value.replace("'", "''") + "'"


def infer_installer_type(installer_path: Path) -> str:
    suffix = installer_path.suffix.lower()
    if suffix == ".exe":
        return "exe"
    if suffix == ".msi":
        return "msi"

    raise ValueError(
        f"unsupported installer extension: {installer_path.name}. expected .exe or .msi",
    )


def load_installer_metadata(metadata_path: str) -> dict[str, str]:
    if not metadata_path:
        return {}

    resolved_path = Path(metadata_path).resolve()
    if not resolved_path.is_file():
        raise FileNotFoundError(f"installer metadata json not found: {resolved_path}")

    payload = json.loads(resolved_path.read_text(encoding="utf-8"))
    if not isinstance(payload, dict):
        raise ValueError("installer metadata json must contain an object at the root")

    normalized: dict[str, str] = {}
    for key, value in payload.items():
        if value is None:
            continue
        normalized[str(key)] = str(value)
    return normalized


def main() -> int:
    args = parse_args()
    version = ensure_release_tag(args.release_tag)
    installer_path = Path(args.installer_path).resolve()
    if not installer_path.is_file():
        raise FileNotFoundError(f"installer not found: {installer_path}")
    installer_type = infer_installer_type(installer_path)
    installer_metadata = load_installer_metadata(args.installer_metadata_path)

    metadata_installer_type = installer_metadata.get("installerType", "")
    if metadata_installer_type and metadata_installer_type != installer_type:
        raise ValueError(
            "installer metadata type does not match installer extension: "
            f"{metadata_installer_type} != {installer_type}",
        )

    package_name = installer_metadata.get("packageName", args.package_name)
    publisher = installer_metadata.get("publisher", args.publisher)
    product_code = installer_metadata.get("productCode", "")
    upgrade_code = installer_metadata.get("upgradeCode", "")
    display_version = installer_metadata.get("packageVersion", "")

    installer_sha = compute_sha256_upper(installer_path)
    installer_name = installer_path.name
    installer_url = (
        f"https://github.com/{args.repo}/releases/download/{args.release_tag}/{installer_name}"
    )
    release_notes_url = (
        f"https://github.com/{args.repo}/releases/tag/{args.release_tag}"
    )
    output_dir = Path(args.output_dir).resolve()

    version_manifest = dedent(
        f"""\
        {schema_header("version")}

        PackageIdentifier: {args.package_identifier}
        PackageVersion: {version}
        DefaultLocale: en-US
        ManifestType: version
        ManifestVersion: {MANIFEST_VERSION}
        """
    )

    installer_manifest_parts = [
        schema_header("installer"),
        "",
        f"PackageIdentifier: {args.package_identifier}",
        f"PackageVersion: {version}",
        f"InstallerType: {installer_type}",
        "UpgradeBehavior: install",
    ]
    if installer_type == "exe":
        installer_manifest_parts.extend(
            [
                "Scope: user",
                "InstallModes:",
                "  - interactive",
                "  - silent",
                "  - silentWithProgress",
                "InstallerSwitches:",
                "  Silent: --silent",
                "  SilentWithProgress: --silent",
                "Dependencies:",
                "  PackageDependencies:",
                "    - PackageIdentifier: Microsoft.VCRedist.2015+.x64",
            ],
        )
    if installer_type == "msi":
        installer_manifest_parts.extend(
            [
                "InstallModes:",
                "  - silent",
                "  - silentWithProgress",
                "InstallerSwitches:",
                "  Custom: SECONDLOOP_LAUNCH_AFTER_INSTALL=0",
            ],
        )
        if product_code:
            installer_manifest_parts.append(
                f"ProductCode: {yaml_single_quoted(product_code)}"
            )
        if any((package_name, publisher, product_code, upgrade_code)):
            installer_manifest_parts.extend(
                [
                    "AppsAndFeaturesEntries:",
                    f"  - DisplayName: {package_name}",
                ],
            )
            if display_version and display_version != version:
                installer_manifest_parts.append(
                    f"    DisplayVersion: {display_version}",
                )
            if publisher:
                installer_manifest_parts.append(f"    Publisher: {publisher}")
            if product_code:
                installer_manifest_parts.append(
                    f"    ProductCode: {yaml_single_quoted(product_code)}"
                )
            if upgrade_code:
                installer_manifest_parts.append(
                    f"    UpgradeCode: {yaml_single_quoted(upgrade_code)}"
                )
            installer_manifest_parts.append(f"    InstallerType: {installer_type}")
    installer_manifest_parts.extend(
        [
            "Installers:",
            "  - Architecture: x64",
            f"    InstallerUrl: {installer_url}",
            f"    InstallerSha256: {installer_sha}",
            "    InstallerLocale: en-US",
            "ManifestType: installer",
            f"ManifestVersion: {MANIFEST_VERSION}",
            "",
        ],
    )
    installer_manifest = "\n".join(installer_manifest_parts)

    locale_manifest = dedent(
        f"""\
        {schema_header("defaultLocale")}

        PackageIdentifier: {args.package_identifier}
        PackageVersion: {version}
        PackageLocale: en-US
        Publisher: {publisher}
        PublisherUrl: {args.publisher_url}
        PublisherSupportUrl: https://github.com/{args.repo}/issues
        Author: {publisher}
        PackageName: {package_name}
        PackageUrl: {args.package_url}
        License: Apache-2.0
        LicenseUrl: https://github.com/{args.repo}/blob/main/LICENSE
        ShortDescription: {args.short_description}
        Description: SecondLoop helps you capture, remember, and act with a local-first workflow.
        Moniker: secondloop
        Tags:
          - ai
          - notes
          - productivity
        ReleaseNotesUrl: {release_notes_url}
        ManifestType: defaultLocale
        ManifestVersion: {MANIFEST_VERSION}
        """
    )

    write_manifest(output_dir / f"{args.package_identifier}.yaml", version_manifest)
    write_manifest(
        output_dir / f"{args.package_identifier}.installer.yaml",
        installer_manifest,
    )
    write_manifest(
        output_dir / f"{args.package_identifier}.locale.en-US.yaml",
        locale_manifest,
    )

    print(f"Generated WinGet manifests at: {output_dir}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
