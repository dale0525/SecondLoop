#!/usr/bin/env python3
from __future__ import annotations

import os
from pathlib import Path, PureWindowsPath
import platform
import shutil
import subprocess
import sys
from typing import Callable, Mapping, Sequence


DEV_BUNDLE_ID = "com.secondloop.secondloopdev"
WINDOWS_COMPANY_NAME = "com.secondloop"
WINDOWS_PRODUCT_NAME = "SecondLoop Dev"
MACOS_FLUTTER_SECURE_STORAGE_SERVICE = "flutter_secure_storage_service"
MACOS_SECURE_BLOB_ACCOUNT = "sync_config_blob_json_v1"

CommandRunner = Callable[[Sequence[str]], subprocess.CompletedProcess[str]]


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


def path_absent_or_empty(target: Path | str) -> bool:
    target_path = Path(target)
    if not target_path.exists():
        return True
    if target_path.is_file():
        return target_path.stat().st_size == 0
    return not any(target_path.iterdir())


def resolve_macos_preferences_file(
    bundle_id: str,
    env: Mapping[str, str] | None = None,
) -> str:
    env_map = dict(os.environ if env is None else env)
    home = env_map.get("HOME", "").strip()
    if not home:
        raise RuntimeError("HOME is not set")
    return str(Path(home) / "Library" / "Preferences" / f"{bundle_id}.plist")


def _default_command_runner(args: Sequence[str]) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        list(args),
        check=False,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        text=True,
    )


def delete_macos_preferences(
    bundle_id: str = DEV_BUNDLE_ID,
    env: Mapping[str, str] | None = None,
    runner: CommandRunner = _default_command_runner,
) -> bool:
    removed = False

    defaults = shutil.which("defaults")
    if defaults is not None:
        result = runner([defaults, "delete", bundle_id])
        removed = result.returncode == 0 or removed

    prefs_path = Path(resolve_macos_preferences_file(bundle_id, env))
    if prefs_path.exists():
        prefs_path.unlink()
        removed = True

    return removed


def delete_macos_secure_storage_blob(
    account: str = MACOS_SECURE_BLOB_ACCOUNT,
    service: str = MACOS_FLUTTER_SECURE_STORAGE_SERVICE,
    runner: CommandRunner = _default_command_runner,
) -> bool:
    security = shutil.which("security")
    if security is None:
        return False

    removed = False
    for _ in range(10):
        result = runner(
            [
                security,
                "delete-generic-password",
                "-a",
                account,
                "-s",
                service,
            ],
        )
        if result.returncode != 0:
            break
        removed = True
    return removed


def macos_preferences_exist(
    bundle_id: str = DEV_BUNDLE_ID,
    env: Mapping[str, str] | None = None,
    runner: CommandRunner = _default_command_runner,
) -> bool:
    prefs_path = Path(resolve_macos_preferences_file(bundle_id, env))
    if prefs_path.exists() and prefs_path.stat().st_size > 0:
        return True

    defaults = shutil.which("defaults")
    if defaults is None:
        return False
    result = runner([defaults, "read", bundle_id])
    return result.returncode == 0


def macos_secure_storage_blob_exists(
    account: str = MACOS_SECURE_BLOB_ACCOUNT,
    service: str = MACOS_FLUTTER_SECURE_STORAGE_SERVICE,
    runner: CommandRunner = _default_command_runner,
) -> bool:
    security = shutil.which("security")
    if security is None:
        return False
    result = runner(
        [
            security,
            "find-generic-password",
            "-a",
            account,
            "-s",
            service,
        ],
    )
    return result.returncode == 0


def verify_empty_local_dev_data(
    platform_name: str,
    env: Mapping[str, str] | None = None,
    runner: CommandRunner = _default_command_runner,
) -> list[tuple[str, bool, str]]:
    app_data_dir = Path(resolve_app_data_dir(platform_name, env))
    checks: list[tuple[str, bool, str]] = [
        ("app_data", path_absent_or_empty(app_data_dir), str(app_data_dir)),
    ]

    if platform_name.strip().lower() == "darwin":
        prefs_path = resolve_macos_preferences_file(DEV_BUNDLE_ID, env)
        checks.append(
            (
                "preferences",
                not macos_preferences_exist(env=env, runner=runner),
                prefs_path,
            )
        )
        checks.append(
            (
                "secure_blob",
                not macos_secure_storage_blob_exists(runner=runner),
                MACOS_SECURE_BLOB_ACCOUNT,
            )
        )

    return checks


def _print_check_results(checks: Sequence[tuple[str, bool, str]]) -> None:
    for category, ok, target in checks:
        state = "empty" if ok else "not_empty"
        print(f"{category}: {state}: {target}")


def main() -> int:
    verify_only = "--verify-empty" in sys.argv[1:]
    platform_name = platform.system()

    if verify_only:
        checks = verify_empty_local_dev_data(platform_name)
        _print_check_results(checks)
        if all(ok for _, ok, _ in checks):
            return 0
        return 2

    target_dir = Path(resolve_app_data_dir(platform_name))
    removed = delete_app_data_dir(target_dir)

    if removed:
        print(f"app_data: removed: {target_dir}")
    else:
        print(f"app_data: not_found: {target_dir}")

    if platform_name.strip().lower() == "darwin":
        prefs_removed = delete_macos_preferences()
        secure_removed = delete_macos_secure_storage_blob()

        prefs_path = resolve_macos_preferences_file(DEV_BUNDLE_ID)
        if prefs_removed:
            print(f"preferences: removed: {prefs_path}")
        else:
            print(f"preferences: not_found: {prefs_path}")

        if secure_removed:
            print(f"secure_blob: removed: {MACOS_SECURE_BLOB_ACCOUNT}")
        else:
            print(f"secure_blob: not_found: {MACOS_SECURE_BLOB_ACCOUNT}")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
