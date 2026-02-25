from __future__ import annotations

from pathlib import Path
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


class PixiWindowsTasksTests(unittest.TestCase):
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

    def test_windows_msi_script_prepares_libclang_for_bindgen(self) -> None:
        script = WINDOWS_MSI_SCRIPT.read_text(encoding="utf-8")

        self.assertIn("setup_windows_libclang.ps1", script)

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

    def test_platform_whisper_dependency_configuration(self) -> None:
        cargo_config = self._load_rust_cargo_config()
        target_config = cargo_config["target"]

        windows_deps = target_config['cfg(target_os = "windows")']["dependencies"]
        windows_whisper_dep = windows_deps["whisper-rs"]

        self.assertEqual(windows_whisper_dep.get("features"), ["vulkan"])

        linux_deps = target_config['cfg(target_os = "linux")']["dependencies"]
        linux_whisper_dep = linux_deps["whisper-rs"]

        self.assertEqual(linux_whisper_dep.get("features"), ["vulkan"])


if __name__ == "__main__":
    unittest.main()
