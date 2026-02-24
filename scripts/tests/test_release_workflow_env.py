from __future__ import annotations

from pathlib import Path
import unittest


class ReleaseWorkflowEnvTests(unittest.TestCase):
    def _publish_env_keys(self) -> set[str]:
        workflow_path = Path(__file__).resolve().parents[2] / ".github/workflows/release.yml"
        lines = workflow_path.read_text(encoding="utf-8").splitlines()

        in_publish = False
        in_env = False
        keys: set[str] = set()

        for line in lines:
            if not in_publish:
                if line.startswith("  publish:"):
                    in_publish = True
                continue

            if in_publish and line.startswith("  ") and not line.startswith("    "):
                break

            if not in_env:
                if line.startswith("    env:"):
                    in_env = True
                continue

            if line.startswith("      "):
                stripped = line.strip()
                if not stripped or stripped.startswith("#"):
                    continue
                key, sep, _value = stripped.partition(":")
                if sep:
                    keys.add(key.strip())
                continue

            if line.startswith("    "):
                break

        return keys

    def _workflow_text(self) -> str:
        workflow_path = Path(__file__).resolve().parents[2] / ".github/workflows/release.yml"
        return workflow_path.read_text(encoding="utf-8")

    def _macos_dmg_script_text(self) -> str:
        script_path = Path(__file__).resolve().parents[2] / "scripts/package_macos_dmg.sh"
        return script_path.read_text(encoding="utf-8")

    def _cargokit_cmake_text(self) -> str:
        cmake_path = Path(__file__).resolve().parents[2] / "rust_builder/cargokit/cmake/cargokit.cmake"
        return cmake_path.read_text(encoding="utf-8")

    def test_publish_job_forwards_extended_llm_env(self) -> None:
        env_keys = self._publish_env_keys()
        self.assertIn("RELEASE_LLM_API_KEY", env_keys)
        self.assertIn("RELEASE_LLM_MODEL", env_keys)
        self.assertIn("RELEASE_LLM_BASE_URL", env_keys)

        self.assertIn("RELEASE_LLM_ENDPOINT", env_keys)
        self.assertIn("RELEASE_LLM_AUTH_HEADER", env_keys)
        self.assertIn("RELEASE_LLM_AUTH_SCHEME", env_keys)

    def test_release_workflow_does_not_publish_msi_helper_script(self) -> None:
        workflow_text = self._workflow_text()

        self.assertNotIn("Install-SecondLoop-MSI.ps1", workflow_text)

    def test_macos_release_uses_packaging_script(self) -> None:
        workflow_text = self._workflow_text()

        self.assertIn("bash scripts/package_macos_dmg.sh", workflow_text)
        self.assertIn('--app "${app}"', workflow_text)
        self.assertIn('--output "${dmg_path}"', workflow_text)

    def test_macos_packaging_script_has_drag_to_applications_layout(self) -> None:
        script_text = self._macos_dmg_script_text()

        self.assertIn('ln -s "/Applications" "${stage_dir}/Applications"', script_text)
        self.assertIn("Drag SecondLoop to Applications", script_text)
        self.assertIn(
            'set background picture of opts to file ".background:dmg-background.png"',
            script_text,
        )
        self.assertIn('set position of item "Applications"', script_text)

    def test_macos_release_publishes_dmg_checksums(self) -> None:
        workflow_text = self._workflow_text()

        self.assertIn('shasum -a 256 "${dmg_name}" > "${dmg_name}.sha256"', workflow_text)
        self.assertIn('dist/*.dmg.sha256', workflow_text)

    def test_release_notes_include_unsigned_macos_and_build_provenance_guidance(self) -> None:
        workflow_text = self._workflow_text()

        self.assertIn('## macOS Installation Note (Unsigned DMG)', workflow_text)
        self.assertIn('## Build Provenance', workflow_text)
        self.assertIn('actions/runs/${GITHUB_RUN_ID}', workflow_text)

    def test_release_workflow_installs_vulkan_sdk_for_linux_and_windows(self) -> None:
        workflow_text = self._workflow_text()

        self.assertIn("windows:\n    needs: preflight", workflow_text)
        self.assertIn("linux:\n    needs: preflight", workflow_text)
        self.assertGreaterEqual(workflow_text.count("humbletim/install-vulkan-sdk@v1.2"), 2)
        self.assertIn("version: 1.4.309.0", workflow_text)

    def test_release_workflow_installs_linux_vulkan_linker_package(self) -> None:
        workflow_text = self._workflow_text()

        self.assertIn("libvulkan-dev", workflow_text)

    def test_release_workflow_installs_android_ndk(self) -> None:
        workflow_text = self._workflow_text()

        self.assertIn("name: Install Android NDK", workflow_text)
        self.assertIn('flutter_gradle="${FLUTTER_ROOT}/packages/flutter_tools/gradle/src/main/groovy/flutter.groovy"', workflow_text)
        self.assertIn('flutter_ndk_version="$(sed -nE', workflow_text)
        self.assertIn('ndkVersion[[:space:]]*=[[:space:]]*', workflow_text)
        self.assertIn('/\\1/p', workflow_text)
        self.assertIn('ndk_package="ndk;${flutter_ndk_version}"', workflow_text)
        self.assertIn('"${sdkmanager}" --sdk_root="${sdk_root}" --install "${ndk_package}"', workflow_text)

    def test_release_workflow_persists_android_ndk_root_for_later_steps(self) -> None:
        workflow_text = self._workflow_text()

        self.assertIn('ndk_root="${sdk_root}/ndk/${flutter_ndk_version}"', workflow_text)
        self.assertIn('echo "SECONDLOOP_ANDROID_NDK_ROOT=${ndk_root}" >> "${GITHUB_ENV}"', workflow_text)

    def test_release_workflow_builds_android_release_for_arm_and_arm64(self) -> None:
        workflow_text = self._workflow_text()

        self.assertNotIn('export SECONDLOOP_ANDROID_TARGET_PLATFORMS="android-arm64"', workflow_text)
        self.assertIn('bash scripts/build_android_release_apk.sh "${build_args[@]}" "${defines[@]}"', workflow_text)

    def test_release_workflow_sets_bindgen_clang_args_for_android_targets(self) -> None:
        workflow_text = self._workflow_text()

        self.assertIn('ndk_sysroot="${SECONDLOOP_ANDROID_NDK_ROOT}/toolchains/llvm/prebuilt/linux-x86_64/sysroot"', workflow_text)
        self.assertIn('export BINDGEN_EXTRA_CLANG_ARGS="--sysroot=${ndk_sysroot}"', workflow_text)
        self.assertIn('export BINDGEN_EXTRA_CLANG_ARGS_armv7_linux_androideabi="--sysroot=${ndk_sysroot} --target=armv7a-linux-androideabi23"', workflow_text)
        self.assertIn('export BINDGEN_EXTRA_CLANG_ARGS_aarch64_linux_android="--sysroot=${ndk_sysroot} --target=aarch64-linux-android23"', workflow_text)

    def test_release_workflow_runs_android_rustup_setup_before_build(self) -> None:
        workflow_text = self._workflow_text()

        setup_idx = workflow_text.find('bash scripts/setup_rustup.sh')
        build_idx = workflow_text.find('bash scripts/build_android_release_apk.sh')

        self.assertNotEqual(-1, setup_idx)
        self.assertNotEqual(-1, build_idx)
        self.assertLess(setup_idx, build_idx)

    def test_release_workflow_uses_short_subst_drive_for_windows_build(self) -> None:
        workflow_text = self._workflow_text()

        self.assertIn('$workspaceParent = Split-Path -Parent $Env:GITHUB_WORKSPACE', workflow_text)
        self.assertIn('$workspaceLeaf = Split-Path -Leaf $Env:GITHUB_WORKSPACE', workflow_text)
        self.assertIn('subst W: $workspaceParent', workflow_text)
        self.assertIn('$shortWorkspacePath = "W:\\$workspaceLeaf"', workflow_text)
        self.assertIn('Push-Location $shortWorkspacePath', workflow_text)
        self.assertNotIn('Push-Location "W:\\"', workflow_text)
        self.assertIn("subst W: /d", workflow_text)

    def test_windows_build_sets_short_cargokit_temp_paths(self) -> None:
        workflow_text = self._workflow_text()

        self.assertIn("$Env:CARGOKIT_TARGET_TEMP_DIR = 'W:\\ck'", workflow_text)
        self.assertIn("$Env:CARGOKIT_TOOL_TEMP_DIR = 'W:\\ck\\tool'", workflow_text)

    def test_cargokit_cmake_allows_temp_dir_env_overrides(self) -> None:
        cmake_text = self._cargokit_cmake_text()

        self.assertIn('$ENV{CARGOKIT_TARGET_TEMP_DIR}', cmake_text)
        self.assertIn('$ENV{CARGOKIT_TOOL_TEMP_DIR}', cmake_text)
        self.assertIn('string(REPLACE', cmake_text)
        self.assertIn('CARGOKIT_TEMP_DIR "${CARGOKIT_TEMP_DIR}")', cmake_text)
        self.assertIn('CARGOKIT_TOOL_TEMP_DIR "${CARGOKIT_TOOL_TEMP_DIR}")', cmake_text)
        self.assertNotIn('file(TO_CMAKE_PATH', cmake_text)
        self.assertIn('CARGOKIT_TOOL_TEMP_DIR=${CARGOKIT_TOOL_TEMP_DIR}', cmake_text)

    def test_android_ndk_install_handles_yes_pipefail(self) -> None:
        workflow_text = self._workflow_text()

        self.assertIn('set +o pipefail', workflow_text)
        self.assertIn('set -o pipefail', workflow_text)

    def test_windows_build_step_fails_on_flutter_build_error(self) -> None:
        workflow_text = self._workflow_text()

        self.assertIn('if ($LASTEXITCODE -ne 0)', workflow_text)
        self.assertIn('throw "flutter build windows failed with exit code $LASTEXITCODE"', workflow_text)

    def test_windows_whisper_dependency_enables_vulkan_backend(self) -> None:
        cargo_text = (Path(__file__).resolve().parents[2] / 'rust/Cargo.toml').read_text(encoding='utf-8')

        self.assertIn('[target.\'cfg(any(target_os = "windows", target_os = "linux"))\'.dependencies]', cargo_text)
        self.assertIn('whisper-rs = { version = "0.15.1", default-features = false, features = ["vulkan"] }', cargo_text)

    def test_windows_build_sets_ninja_generator_for_rust_cmake(self) -> None:
        workflow_text = self._workflow_text()

        self.assertIn('$Env:CMAKE_GENERATOR = "Ninja"', workflow_text)

    def test_windows_build_enables_verbose_flutter_output(self) -> None:
        workflow_text = self._workflow_text()

        self.assertIn('flutter build windows --release -v @buildArgs @defines', workflow_text)

    def test_windows_release_uses_repo_setup_ffmpeg_script(self) -> None:
        workflow_text = self._workflow_text()

        self.assertIn('powershell -NoProfile -ExecutionPolicy Bypass -File scripts/setup_ffmpeg_windows.ps1', workflow_text)
        self.assertIn('dart run tools/prepare_bundled_ffmpeg.dart --platform=windows', workflow_text)
        self.assertNotIn('choco install ffmpeg --yes --no-progress', workflow_text)
        self.assertNotIn('--source-bin "C:\\ProgramData\\chocolatey\\bin\\ffmpeg.exe"', workflow_text)

    def test_windows_release_packages_and_uploads_velopack_artifacts(self) -> None:
        workflow_text = self._workflow_text()

        self.assertIn("name: Package Velopack", workflow_text)
        self.assertIn("scripts/package_windows_velopack.ps1", workflow_text)
        self.assertIn("-SkipBuild", workflow_text)
        self.assertIn("-OutputPath dist", workflow_text)
        self.assertIn("Velopack setup not found", workflow_text)
        self.assertIn("Velopack RELEASES not found", workflow_text)
        self.assertIn("Velopack nupkg not found", workflow_text)
        self.assertIn("dist/*Setup*.exe", workflow_text)
        self.assertIn("dist/*RELEASES*", workflow_text)
        self.assertIn("dist/*.nupkg", workflow_text)
        self.assertIn("dist/*.msi", workflow_text)

    def test_windows_velopack_script_keeps_dotnet_output_out_of_vpk_path(self) -> None:
        script_text = (Path(__file__).resolve().parents[2] / "scripts/package_windows_velopack.ps1").read_text(encoding="utf-8")

        self.assertIn("$dotnetOutput = & dotnet @args 2>&1", script_text)
        self.assertIn("$dotnetExitCode = $LASTEXITCODE", script_text)
        self.assertIn("foreach ($line in $dotnetOutput)", script_text)
        self.assertIn("if ($dotnetExitCode -ne 0)", script_text)



if __name__ == "__main__":
    unittest.main()
