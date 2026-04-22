#!/usr/bin/env python3
from __future__ import annotations

import os
from pathlib import Path, PureWindowsPath
import platform
import shutil
import sys
from typing import Mapping


DEV_BUNDLE_ID = "com.secondloop.secondloopdev"
WINDOWS_COMPANY_NAME = "com.secondloop"
WINDOWS_PRODUCT_NAME = "SecondLoop Dev"


def resolve_app_data_dir(
    platform_name: str,
    env: Mapping[str, str] | None = None,
) -> str:
    env_map = dict(os.environ if env is None else env)
    normalized_platform = platform_name.strip().lower()

    if normalized_platform == "darwin":
        home = env_map.get("HOME", "").strip()
        if not home:
            raise RuntimeError("HOME is not set")
        return str(Path(home) / "Library" / "Application Support" / DEV_BUNDLE_ID)

    if normalized_platform == "linux":
        xdg_data_home = env_map.get("XDG_DATA_HOME", "").strip()
        if xdg_data_home:
            return str(Path(xdg_data_home) / DEV_BUNDLE_ID)
        home = env_map.get("HOME", "").strip()
        if not home:
            raise RuntimeError("HOME is not set")
        return str(Path(home) / ".local" / "share" / DEV_BUNDLE_ID)

    if normalized_platform == "windows":
        appdata = env_map.get("APPDATA", "").strip()
        if not appdata:
            raise RuntimeError("APPDATA is not set")
        return str(
            PureWindowsPath(appdata) / WINDOWS_COMPANY_NAME / WINDOWS_PRODUCT_NAME
        )

    raise RuntimeError(f"Unsupported desktop platform: {platform_name}")


def delete_app_data_dir(target_dir: Path | str) -> bool:
    target_path = Path(target_dir)
    if not target_path.exists():
        return False

    shutil.rmtree(target_path)
    return True


def main() -> int:
    target_dir = Path(resolve_app_data_dir(platform.system()))
    removed = delete_app_data_dir(target_dir)

    if removed:
        print(f"Removed local dev app data: {target_dir}")
    else:
        print(f"Local dev app data not found: {target_dir}")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
