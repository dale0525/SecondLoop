from __future__ import annotations

import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import tomllib
import unittest


REPO_ROOT = Path(__file__).resolve().parents[2]
PIXI_TOML = REPO_ROOT / "pixi.toml"
RUST_CARGO_TOML = REPO_ROOT / "rust/Cargo.toml"
WINDOWS_BOOTSTRAP_SCRIPT = REPO_ROOT / "scripts/bootstrap_shared_worktree_env.ps1"
WINDOWS_VELOPACK_SCRIPT = REPO_ROOT / "scripts/package_windows_velopack.ps1"
WINDOWS_MSI_SCRIPT = REPO_ROOT / "scripts/package_windows_msi.ps1"
WINDOWS_LIBCLANG_SETUP_SCRIPT = REPO_ROOT / "scripts/setup_windows_libclang.ps1"
WINDOWS_VULKAN_SETUP_SCRIPT = REPO_ROOT / "scripts/setup_windows_vulkan_sdk.ps1"
WINDOWS_FVM_TOOL_RUNNER_SCRIPT = REPO_ROOT / "scripts/run_fvm_tool.ps1"
WINDOWS_UNINSTALL_MSI_SCRIPT = REPO_ROOT / "scripts/uninstall_windows_msi.ps1"
WINDOWS_SETUP_FLUTTER_SCRIPT = REPO_ROOT / "scripts/setup_flutter_windows.ps1"
WINDOWS_SHORT_WORKSPACE_SCRIPT = REPO_ROOT / "scripts/use_windows_short_workspace.ps1"
WINDOWS_CARGOKIT_BUILD_TOOL = REPO_ROOT / "rust_builder/cargokit/run_build_tool.cmd"


class PixiWindowsTasksTests(unittest.TestCase):
    def _write_windows_tool_args_file(self, path: Path, *args: str) -> None:
        path.write_bytes(b"\0".join(arg.encode("utf-8") for arg in args) + b"\0")

    def _load_pixi_config(self) -> dict[str, object]:
        with PIXI_TOML.open("rb") as fh:
            return tomllib.load(fh)

    def _load_win_tasks(self) -> dict[str, object]:
        pixi_config = self._load_pixi_config()

        return pixi_config["target"]["win-64"]["tasks"]

    def _load_win_dependencies(self) -> dict[str, object]:
        pixi_config = self._load_pixi_config()

        return pixi_config["target"]["win-64"].get("dependencies", {})

    def _load_rust_cargo_config(self) -> dict[str, object]:
        with RUST_CARGO_TOML.open("rb") as fh:
            return tomllib.load(fh)

    def test_windows_bootstrap_task_uses_powershell_script(self) -> None:
        win_tasks = self._load_win_tasks()

        bootstrap_task = win_tasks["bootstrap-shared-worktree-env"]
        self.assertIsInstance(bootstrap_task, str)
        self.assertIn("scripts/bootstrap_shared_worktree_env.ps1", bootstrap_task)

    def test_windows_setup_flutter_task_uses_powershell_script(self) -> None:
        win_tasks = self._load_win_tasks()

        setup_flutter_task = win_tasks["setup-flutter"]

        self.assertIsInstance(setup_flutter_task, str)
        self.assertIn("scripts/setup_flutter_windows.ps1", setup_flutter_task)
        self.assertNotIn("dart pub global run fvm:main flutter pub get", setup_flutter_task)

    def test_run_windows_depends_on_bootstrap_shared_worktree_env(self) -> None:
        win_tasks = self._load_win_tasks()

        run_windows_task = win_tasks["run-windows"]
        dependencies = run_windows_task.get("depends-on", [])

        self.assertIn("bootstrap-shared-worktree-env", dependencies)

    def test_run_windows_defaults_to_flutter_run_flow(self) -> None:
        win_tasks = self._load_win_tasks()

        run_windows_task = win_tasks["run-windows"]
        command = run_windows_task.get("cmd", "")

        self.assertIn("scripts/run_windows.ps1", command)
        self.assertIn("-UseFlutterRun", command)

    def test_package_windows_msi_task_removed(self) -> None:
        win_tasks = self._load_win_tasks()

        self.assertNotIn("package-windows-msi", win_tasks)
        self.assertNotIn("run-windows-msi", win_tasks)

    def test_package_windows_velopack_task_exists_and_matches_dependencies(self) -> None:
        win_tasks = self._load_win_tasks()

        velopack_task = win_tasks["package-windows-velopack"]
        run_windows_task = win_tasks["run-windows"]

        self.assertEqual(
            velopack_task.get("depends-on", []),
            run_windows_task.get("depends-on", []),
        )
        self.assertIn("scripts/package_windows_velopack.ps1", velopack_task.get("cmd", ""))

    def test_windows_dev_msi_task_reuses_windows_bootstrap_dependencies(self) -> None:
        win_tasks = self._load_win_tasks()

        msi_dev_task = win_tasks["msi-dev"]
        run_windows_task = win_tasks["run-windows"]

        self.assertEqual(
            msi_dev_task.get("depends-on", []),
            run_windows_task.get("depends-on", []),
        )
        self.assertIn("scripts/run_windows.ps1", msi_dev_task.get("cmd", ""))
        self.assertNotIn("-UseFlutterRun", msi_dev_task.get("cmd", ""))

    def test_windows_uninstall_dev_msi_task_uses_dedicated_uninstall_script(self) -> None:
        win_tasks = self._load_win_tasks()

        uninstall_task = win_tasks["uninstall-dev-msi"]
        command = uninstall_task.get("cmd", "")

        self.assertIn("scripts/uninstall_windows_msi.ps1", command)
        self.assertIn("SecondLoop Dev", command)

    def test_windows_bootstrap_script_links_shared_tool_and_pixi_envs(self) -> None:
        script = WINDOWS_BOOTSTRAP_SCRIPT.read_text(encoding="utf-8")

        self.assertIn("Link-DirectoryToShared -LocalPath (Join-Path $repoRoot '.tool')", script)
        self.assertIn("Link-DirectoryToShared -LocalPath (Join-Path $repoRoot '.pixi/envs')", script)

    def test_windows_dependencies_keep_libclang_without_vulkan_header_overrides(self) -> None:
        dependencies = self._load_win_dependencies()

        self.assertIn("libclang", dependencies)
        self.assertIn("dotnet-sdk", dependencies)
        self.assertIn("dotnet-aspnetcore", dependencies)
        self.assertNotIn("vulkan-headers", dependencies)
        self.assertNotIn("libvulkan-loader", dependencies)
        self.assertNotIn("shaderc", dependencies)

    def test_windows_velopack_script_prepares_libclang_for_bindgen(self) -> None:
        script = WINDOWS_VELOPACK_SCRIPT.read_text(encoding="utf-8")

        self.assertIn("setup_windows_libclang.ps1", script)

    def test_windows_velopack_skip_build_does_not_require_libclang_setup(self) -> None:
        script = WINDOWS_VELOPACK_SCRIPT.read_text(encoding="utf-8")

        skip_build_guard = script.find("if (-not $SkipBuild)")
        setup_idx = script.find("setup_windows_libclang.ps1")

        self.assertNotEqual(-1, skip_build_guard)
        self.assertNotEqual(-1, setup_idx)
        self.assertGreater(setup_idx, skip_build_guard)

    def test_windows_msi_script_prepares_libclang_for_bindgen(self) -> None:
        script = WINDOWS_MSI_SCRIPT.read_text(encoding="utf-8")

        self.assertIn("setup_windows_libclang.ps1", script)

    def test_run_windows_script_prunes_stale_rust_artifacts_before_flutter_run(self) -> None:
        script = (REPO_ROOT / "scripts/run_windows.ps1").read_text(encoding="utf-8")

        self.assertIn("Get-LatestRustSourceWriteTimeUtc", script)
        self.assertIn("Remove-StaleWindowsRustArtifacts", script)
        self.assertIn("Stale Rust artifacts detected", script)
        self.assertIn("before flutter run", script)

    def test_run_windows_script_sets_frb_native_lib_dir_to_debug_runner(self) -> None:
        script = (REPO_ROOT / "scripts/run_windows.ps1").read_text(encoding="utf-8")

        self.assertIn("FRB_DART_LOAD_EXTERNAL_LIBRARY_NATIVE_LIB_DIR", script)
        self.assertIn("build/windows/x64/runner/Debug", script)

    def test_windows_libclang_setup_script_handles_versioned_libclang_dll(self) -> None:
        script = WINDOWS_LIBCLANG_SETUP_SCRIPT.read_text(encoding="utf-8")

        self.assertIn("libclang-*.dll", script)
        self.assertIn("LIBCLANG_PATH", script)
        self.assertIn("VULKAN_SDK", script)
        self.assertIn("SECONDLOOP_WINDOWS_VULKAN_SDK_ROOT", script)
        self.assertIn("1.4.309.0", script)
        self.assertIn("VkPhysicalDeviceCooperativeMatrixFeaturesKHR", script)
        self.assertIn("CARGOKIT_TARGET_TEMP_DIR", script)
        self.assertIn("CARGOKIT_TOOL_TEMP_DIR", script)
        self.assertIn("CMAKE_GENERATOR", script)
        self.assertIn("setup_windows_vulkan_sdk.ps1", script)
        self.assertIn("whisper-rs-sys", script)
        self.assertIn("CMakeCache.txt", script)

    def test_windows_vulkan_setup_script_installs_ci_compatible_sdk_to_project_tools(self) -> None:
        self.assertTrue(WINDOWS_VULKAN_SETUP_SCRIPT.exists())

        script = WINDOWS_VULKAN_SETUP_SCRIPT.read_text(encoding="utf-8")

        self.assertIn("VulkanSDK-$Version-Installer.exe", script)
        self.assertIn("1.4.309.0", script)
        self.assertIn("Join-Path (Join-Path (Join-Path $repoRootPath '.tool') 'vulkan-sdk') $Version", script)
        self.assertNotIn(".tools", script)
        self.assertIn("7z", script)
        self.assertIn("VkPhysicalDeviceCooperativeMatrixFeaturesKHR", script)
        self.assertIn('${installerFileName}?Human=true', script)

    def test_platform_whisper_dependency_configuration(self) -> None:
        cargo_config = self._load_rust_cargo_config()
        target_config = cargo_config["target"]

        windows_deps = target_config['cfg(target_os = "windows")']["dependencies"]
        windows_whisper_dep = windows_deps["whisper-rs"]

        self.assertNotIn("features", windows_whisper_dep)

        linux_deps = target_config['cfg(target_os = "linux")']["dependencies"]
        linux_whisper_dep = linux_deps["whisper-rs"]

        self.assertEqual(linux_whisper_dep.get("features"), ["vulkan"])

    def test_windows_flutter_task_uses_direct_fvm_tool_runner(self) -> None:
        win_tasks = self._load_win_tasks()

        flutter_task = win_tasks["flutter"]
        command = flutter_task.get("cmd", "")

        self.assertIn("scripts/run_fvm_tool.ps1 -Tool flutter", command)
        self.assertNotIn("dart pub global run fvm:main flutter", command)

    def test_windows_dart_task_uses_direct_fvm_tool_runner(self) -> None:
        win_tasks = self._load_win_tasks()

        dart_task = win_tasks["dart"]
        command = dart_task.get("cmd", "")

        self.assertIn("scripts/run_fvm_tool.ps1 -Tool dart", command)
        self.assertNotIn("dart pub global run fvm:main dart", command)

    def test_windows_fvm_tool_runner_uses_local_fvm_batch_wrappers(self) -> None:
        self.assertTrue(WINDOWS_FVM_TOOL_RUNNER_SCRIPT.exists())

        script = WINDOWS_FVM_TOOL_RUNNER_SCRIPT.read_text(encoding="utf-8")

        self.assertIn(".fvm", script)
        self.assertIn("flutter.bat", script)
        self.assertIn("dart.bat", script)
        self.assertIn("ValueFromRemainingArguments", script)
        self.assertIn("[string]$ArgumentsFile = ''", script)
        self.assertIn("Read-ArgumentFile", script)
        self.assertIn("& $toolPath @resolvedCommand", script)
        self.assertIn("exit $LASTEXITCODE", script)

    def test_windows_fvm_tool_runner_checks_tool_path_before_resolve_path(self) -> None:
        script = WINDOWS_FVM_TOOL_RUNNER_SCRIPT.read_text(encoding="utf-8")

        self.assertIn("Test-Path $ToolPath", script)
        self.assertIn("Resolve-Path $ToolPath", script)
        self.assertLess(
            script.index("Test-Path $ToolPath"),
            script.index("Resolve-Path $ToolPath"),
        )

    def test_windows_cargokit_build_tool_prepares_dart_tool_in_temp_workspace(self) -> None:
        script = WINDOWS_CARGOKIT_BUILD_TOOL.read_text(encoding="utf-8")

        self.assertIn("if not exist .dart_tool (", script)
        self.assertIn("mkdir .dart_tool", script)

    def test_windows_velopack_script_uses_short_workspace_helper_and_full_project_dir(self) -> None:
        self.assertTrue(WINDOWS_SHORT_WORKSPACE_SCRIPT.exists())

        helper_script = WINDOWS_SHORT_WORKSPACE_SCRIPT.read_text(encoding="utf-8")
        velopack_script = WINDOWS_VELOPACK_SCRIPT.read_text(encoding="utf-8")

        self.assertIn("cmd /c subst", helper_script)
        self.assertIn('$shortProjectDir = "$shortDriveRoot$workspaceLeaf"', helper_script)
        self.assertIn("Set-Item -Path Env:PROJECT_DIR -Value $shortProjectDir", helper_script)
        self.assertNotIn("Set-Item -Path Env:PROJECT_DIR -Value $shortDriveRoot", helper_script)
        self.assertIn("use_windows_short_workspace.ps1", velopack_script)
        self.assertIn("Invoke-InWindowsShortWorkspace", velopack_script)

    def test_windows_short_workspace_helper_avoids_destructive_subst_cleanup(self) -> None:
        script = WINDOWS_SHORT_WORKSPACE_SCRIPT.read_text(encoding="utf-8")

        self.assertIn("Get-AvailableShortWorkspaceDrive", script)
        self.assertIn("Get-PSDrive -PSProvider FileSystem", script)
        self.assertIn("New-ShortWorkspaceLease", script)
        self.assertIn("Remove-ShortWorkspaceLease", script)
        self.assertIn("secondloop_short_workspace_refs", script)
        self.assertIn("OwnsMapping", script)
        self.assertIn("if ((Test-Path -LiteralPath $Lease.OwnerPath -PathType Leaf) -and $remainingLeases.Count -eq 0)", script)
        self.assertIn("$DriveLetter = $env:SECONDLOOP_SHORT_WORKSPACE_DRIVE", script)
        self.assertIn("if ($resolvedRepoRoot -like \"$substDrive\\*\")", script)
        self.assertNotIn("cmd /c subst $substDrive /d > $null 2>&1\n      cmd /c subst $substDrive \"$workspaceParent\"", script)
        self.assertIn("$mappingAttempts = 0", script)
        self.assertIn("Failed to map a short workspace drive to $workspaceParent after $mappingAttempts attempts", script)
        self.assertIn("$pathVisibilityAttempts = 20", script)
        self.assertIn("Short workspace path not found after drive mapping", script)

    def test_windows_velopack_script_propagates_required_build_environment(self) -> None:
        script = WINDOWS_VELOPACK_SCRIPT.read_text(encoding="utf-8")

        self.assertIn("DOTNET_ROOT", script)
        self.assertIn("FLUTTER_ROOT", script)
        self.assertIn("LIBCLANG_PATH", script)
        self.assertIn("VULKAN_SDK", script)
        self.assertIn("CARGOKIT_TARGET_TEMP_DIR", script)
        self.assertIn("CARGOKIT_TOOL_TEMP_DIR", script)
        self.assertIn("run_fvm_tool.ps1", script)

    def test_windows_velopack_script_propagates_app_identity_to_dart_defines(self) -> None:
        script = WINDOWS_VELOPACK_SCRIPT.read_text(encoding="utf-8")

        self.assertIn("if ($PackId)", script)
        self.assertIn('Set-Item -Path Env:SECONDLOOP_APP_ID -Value $PackId', script)
        self.assertIn("--dart-define=SECONDLOOP_APP_ID=", script)

    def test_windows_velopack_script_can_forward_http_update_override_define(self) -> None:
        script = WINDOWS_VELOPACK_SCRIPT.read_text(encoding="utf-8")

        self.assertIn("SECONDLOOP_ALLOW_HTTP_UPDATE_URIS", script)
        self.assertIn("--dart-define=SECONDLOOP_ALLOW_HTTP_UPDATE_URIS=", script)

    def test_windows_velopack_script_adds_project_cargo_bin_to_path(self) -> None:
        script = WINDOWS_VELOPACK_SCRIPT.read_text(encoding="utf-8")

        self.assertIn(".pixi/envs/default/Library/bin", script)
        self.assertIn("cargo.exe", script)
        self.assertIn("rustup.exe", script)

    def test_windows_velopack_script_prefers_project_dotnet_sdk(self) -> None:
        script = WINDOWS_VELOPACK_SCRIPT.read_text(encoding="utf-8")

        self.assertIn(".pixi/envs/default/dotnet", script)
        self.assertIn("dotnet.exe", script)
        self.assertIn("DOTNET_MULTILEVEL_LOOKUP", script)

    def test_windows_velopack_script_accepts_existing_flutter_root_before_local_fvm(self) -> None:
        script = WINDOWS_VELOPACK_SCRIPT.read_text(encoding="utf-8")

        self.assertIn('if (-not [string]::IsNullOrWhiteSpace($env:FLUTTER_ROOT))', script)
        self.assertIn('Test-Path -LiteralPath $env:FLUTTER_ROOT -PathType Container', script)
        self.assertIn("Join-Path $repoRootPath '.fvm/flutter_sdk'", script)

    def test_windows_setup_flutter_script_exports_flutter_root_and_checks_environment(self) -> None:
        script = WINDOWS_SETUP_FLUTTER_SCRIPT.read_text(encoding="utf-8")

        self.assertIn("Set-Item -Path Env:FLUTTER_ROOT", script)
        self.assertIn("Get-Command dart", script)
        self.assertIn("pixi install", script)
        self.assertIn("pixi run setup-flutter", script)
        self.assertIn("Invoke-InWindowsShortWorkspace", script)

    def test_windows_uninstall_msi_script_uses_registry_install_metadata(self) -> None:
        self.assertTrue(WINDOWS_UNINSTALL_MSI_SCRIPT.exists())

        script = WINDOWS_UNINSTALL_MSI_SCRIPT.read_text(encoding="utf-8")

        self.assertIn("[string]$ProductName = 'SecondLoop Dev'", script)
        self.assertIn("[string]$InstallDirName = 'SecondLoop Dev'", script)
        self.assertIn("HKCU:\\Software\\Microsoft\\Windows\\CurrentVersion\\Uninstall", script)
        self.assertIn("HKLM:\\Software\\Microsoft\\Windows\\CurrentVersion\\Uninstall", script)
        self.assertIn("UninstallString", script)
        self.assertIn("InstallLocation", script)
        self.assertIn("msiexec.exe", script)
        self.assertIn("/x", script)

    def test_windows_setup_flutter_script_uses_local_fvm_sdk_after_install(self) -> None:
        self.assertTrue(WINDOWS_SETUP_FLUTTER_SCRIPT.exists())

        script = WINDOWS_SETUP_FLUTTER_SCRIPT.read_text(encoding="utf-8")

        self.assertIn("core.longpaths true", script)
        self.assertIn("Env:PUB_CACHE", script)
        self.assertIn("Env:FVM_HOME", script)
        self.assertIn(".tool/pub-cache", script)
        self.assertIn(".tool/fvm", script)
        self.assertIn("dart pub global activate --no-executables fvm 2.4.1", script)
        self.assertIn(".fvm/flutter_sdk/bin/flutter.bat", script)
        self.assertIn("pub", script)
        self.assertIn("get", script)
        self.assertIn("exit $LASTEXITCODE", script)

    def test_windows_run_fvm_tool_script_uses_short_workspace_helper_for_execution(self) -> None:
        script = WINDOWS_FVM_TOOL_RUNNER_SCRIPT.read_text(encoding="utf-8")

        self.assertIn("use_windows_short_workspace.ps1", script)
        self.assertIn("Invoke-InWindowsShortWorkspace", script)

    @unittest.skipUnless(os.name == "nt", "Windows-only short workspace behavior")
    def test_windows_run_fvm_tool_maps_repo_relative_working_directory_into_short_workspace(self) -> None:
        powershell = shutil.which("powershell.exe") or shutil.which("powershell")
        if powershell is None:
            self.skipTest("PowerShell is required to verify Windows tool runner")

        tool_output_dir = Path(tempfile.mkdtemp(prefix="secondloop_run_fvm_tool_"))
        fake_tool = tool_output_dir / "fake_tool.cmd"
        output_file = tool_output_dir / "cwd.txt"
        args_file = tool_output_dir / "args.bin"
        working_dir = REPO_ROOT / "scripts"

        fake_tool.write_text(
            "@echo off\n"
            "setlocal\n"
            "if /I \"%~1\"==\"record\" (\n"
            "  > \"%~2\" echo CD=%CD%\n"
            "  >> \"%~2\" echo PROJECT_DIR=%PROJECT_DIR%\n"
            "  exit /b 0\n"
            ")\n"
            "exit /b 1\n",
            encoding="utf-8",
        )
        self._write_windows_tool_args_file(args_file, "record", str(output_file))

        try:
            subprocess.run(
                [
                    powershell,
                    "-NoProfile",
                    "-ExecutionPolicy",
                    "Bypass",
                    "-File",
                    str(WINDOWS_FVM_TOOL_RUNNER_SCRIPT),
                    "-Tool",
                    "dart",
                    "-ToolPath",
                    str(fake_tool),
                    "-WorkingDirectory",
                    str(working_dir),
                    "-ArgumentsFile",
                    str(args_file),
                ],
                check=True,
                cwd=REPO_ROOT,
            )
            lines = output_file.read_text(encoding="utf-8").splitlines()
        finally:
            fake_tool.unlink(missing_ok=True)
            output_file.unlink(missing_ok=True)
            args_file.unlink(missing_ok=True)
            tool_output_dir.rmdir()

        recorded = dict(
            line.split("=", 1)
            for line in lines
            if "=" in line
        )
        recorded_cwd = recorded["CD"]
        recorded_project_dir = recorded["PROJECT_DIR"]

        self.assertTrue(recorded_project_dir)
        self.assertTrue(
            recorded_cwd.lower().startswith(recorded_project_dir.lower()),
            msg=f"expected {recorded_cwd!r} to stay inside short workspace {recorded_project_dir!r}",
        )
        self.assertTrue(
            recorded_cwd.lower().endswith("\\scripts"),
            msg=f"expected repo-relative working directory suffix to be preserved, got {recorded_cwd!r}",
        )
        self.assertNotEqual(str(working_dir).lower(), recorded_cwd.lower())

    @unittest.skipUnless(os.name == "nt", "Windows-only argument forwarding behavior")
    def test_windows_run_fvm_tool_preserves_dash_prefixed_command_arguments(self) -> None:
        powershell = shutil.which("powershell.exe") or shutil.which("powershell")
        if powershell is None:
            self.skipTest("PowerShell is required to verify Windows tool runner")

        tool_output_dir = Path(tempfile.mkdtemp(prefix="secondloop_run_fvm_tool_args_"))
        fake_tool = tool_output_dir / "fake_tool.cmd"
        output_file = tool_output_dir / "args.txt"
        args_file = tool_output_dir / "args.bin"

        fake_tool.write_text(
            "@echo off\n"
            "setlocal\n"
            "> \"%~1\" echo STAR=%*\n"
            ">> \"%~1\" echo ONE=%1\n"
            ">> \"%~1\" echo TWO=%2\n"
            ">> \"%~1\" echo THREE=%3\n"
            ">> \"%~1\" echo FOUR=%4\n"
            ">> \"%~1\" echo FIVE=%5\n"
            "exit /b 0\n",
            encoding="utf-8",
        )
        self._write_windows_tool_args_file(
            args_file,
            str(output_file),
            "test",
            "-d",
            "windows",
            "--concurrency=1",
            "integration_test/simple_test.dart",
        )

        try:
            subprocess.run(
                [
                    powershell,
                    "-NoProfile",
                    "-ExecutionPolicy",
                    "Bypass",
                    "-File",
                    str(WINDOWS_FVM_TOOL_RUNNER_SCRIPT),
                    "-Tool",
                    "flutter",
                    "-ToolPath",
                    str(fake_tool),
                    "-ArgumentsFile",
                    str(args_file),
                ],
                check=True,
                cwd=REPO_ROOT,
            )
            lines = output_file.read_text(encoding="utf-8").splitlines()
        finally:
            fake_tool.unlink(missing_ok=True)
            output_file.unlink(missing_ok=True)
            args_file.unlink(missing_ok=True)
            tool_output_dir.rmdir()

        recorded = dict(
            line.split("=", 1)
            for line in lines
            if "=" in line
        )

        self.assertIn("-d windows --concurrency=1 integration_test/simple_test.dart", recorded["STAR"])
        self.assertEqual(recorded["TWO"], "test")
        self.assertEqual(recorded["THREE"], "-d")
        self.assertEqual(recorded["FOUR"], "windows")
        self.assertEqual(recorded["FIVE"], "--concurrency")

    def test_prepare_ffmpeg_windows_script_uses_direct_fvm_dart_runner(self) -> None:
        script = (REPO_ROOT / "scripts/prepare_ffmpeg_windows.ps1").read_text(encoding="utf-8")

        self.assertIn("run_fvm_tool.ps1", script)
        self.assertIn("-Tool dart", script)
        self.assertIn("-Command run", script)
        self.assertNotIn("dart pub global run fvm:main dart run", script)



    def test_gitignore_ignores_generated_windows_ffmpeg_zip(self) -> None:
        gitignore = (REPO_ROOT / ".gitignore").read_text(encoding="utf-8")

        self.assertIn("assets/bin/ffmpeg/windows/ffmpeg.zip", gitignore)

if __name__ == "__main__":
    unittest.main()
