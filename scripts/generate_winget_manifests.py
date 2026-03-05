#!/usr/bin/env python3
from __future__ import annotations

import argparse
import hashlib
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


def infer_installer_type(installer_path: Path) -> str:
    suffix = installer_path.suffix.lower()
    if suffix == ".exe":
        return "exe"
    if suffix == ".msi":
        return "msi"

    raise ValueError(
        f"unsupported installer extension: {installer_path.name}. expected .exe or .msi",
    )


def main() -> int:
    args = parse_args()
    version = ensure_release_tag(args.release_tag)
    installer_path = Path(args.installer_path).resolve()
    if not installer_path.is_file():
        raise FileNotFoundError(f"installer not found: {installer_path}")
    installer_type = infer_installer_type(installer_path)

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
        "Scope: user",
        "UpgradeBehavior: install",
    ]
    if installer_type == "exe":
        installer_manifest_parts.extend(
            [
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
        Publisher: {args.publisher}
        PublisherUrl: {args.publisher_url}
        PublisherSupportUrl: https://github.com/{args.repo}/issues
        Author: {args.publisher}
        PackageName: {args.package_name}
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
