from __future__ import annotations

from pathlib import Path
import subprocess
import sys
import tempfile
import tomllib
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

    def _publish_homebrew_script_text(self) -> str:
        script_path = Path(__file__).resolve().parents[2] / "scripts/publish_homebrew_cask.sh"
        return script_path.read_text(encoding="utf-8")

    def _publish_winget_script_text(self) -> str:
        script_path = Path(__file__).resolve().parents[2] / "scripts/publish_winget_manifest.sh"
        return script_path.read_text(encoding="utf-8")

    def _generate_winget_script_text(self) -> str:
        script_path = Path(__file__).resolve().parents[2] / "scripts/generate_winget_manifests.py"
        return script_path.read_text(encoding="utf-8")

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

    def test_release_workflow_runs_flutter_pub_get_before_android_rustup_patch_step(self) -> None:
        workflow_text = self._workflow_text()

        pub_get_idx = workflow_text.find("      - run: flutter pub get")
        setup_idx = workflow_text.find("      - name: Setup Rustup for Android build")

        self.assertNotEqual(-1, pub_get_idx)
        self.assertNotEqual(-1, setup_idx)
        self.assertLess(pub_get_idx, setup_idx)

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

    def test_windows_and_linux_whisper_dependency_enable_vulkan_backend(self) -> None:
        cargo_path = Path(__file__).resolve().parents[2] / "rust/Cargo.toml"
        with cargo_path.open("rb") as fh:
            cargo_config = tomllib.load(fh)

        target_config = cargo_config["target"]
        windows_dep = target_config['cfg(target_os = "windows")']["dependencies"]["whisper-rs"]
        linux_dep = target_config['cfg(target_os = "linux")']["dependencies"]["whisper-rs"]

        self.assertEqual(windows_dep.get("features"), ["vulkan"])
        self.assertEqual(linux_dep.get("features"), ["vulkan"])

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

    def test_desktop_release_prunes_non_target_ffmpeg_assets_before_build(self) -> None:
        workflow_text = self._workflow_text()

        self.assertIn("name: Prune non-target FFmpeg assets (windows)", workflow_text)
        self.assertIn("name: Prune non-target FFmpeg assets (macos)", workflow_text)
        self.assertIn("name: Prune non-target FFmpeg assets (linux)", workflow_text)

        self.assertIn("$removeDirs = @('macos', 'linux')", workflow_text)
        self.assertIn('rm -rf assets/bin/ffmpeg/windows assets/bin/ffmpeg/linux', workflow_text)
        self.assertIn('rm -rf assets/bin/ffmpeg/windows assets/bin/ffmpeg/macos', workflow_text)

        windows_prune_idx = workflow_text.find("name: Prune non-target FFmpeg assets (windows)")
        windows_build_idx = workflow_text.find("flutter build windows --release -v @buildArgs @defines")
        self.assertNotEqual(-1, windows_prune_idx)
        self.assertNotEqual(-1, windows_build_idx)
        self.assertLess(windows_prune_idx, windows_build_idx)

        macos_prune_idx = workflow_text.find("name: Prune non-target FFmpeg assets (macos)")
        macos_build_idx = workflow_text.find("flutter build macos --release --config-only")
        self.assertNotEqual(-1, macos_prune_idx)
        self.assertNotEqual(-1, macos_build_idx)
        self.assertLess(macos_prune_idx, macos_build_idx)

        linux_prune_idx = workflow_text.find("name: Prune non-target FFmpeg assets (linux)")
        linux_build_idx = workflow_text.find("flutter build linux --release")
        self.assertNotEqual(-1, linux_prune_idx)
        self.assertNotEqual(-1, linux_build_idx)
        self.assertLess(linux_prune_idx, linux_build_idx)

    def test_windows_release_packages_and_uploads_velopack_artifacts(self) -> None:
        workflow_text = self._workflow_text()

        self.assertNotIn("name: Package MSI", workflow_text)
        self.assertIn("name: Package Velopack", workflow_text)
        self.assertIn("scripts/package_windows_velopack.ps1", workflow_text)
        self.assertIn("-SkipBuild", workflow_text)
        self.assertIn("-OutputPath dist", workflow_text)
        self.assertIn("Velopack setup not found", workflow_text)
        self.assertIn("Velopack releases metadata not found", workflow_text)
        self.assertIn("Velopack assets metadata not found", workflow_text)
        self.assertIn("Velopack nupkg not found", workflow_text)
        self.assertIn("dist/*Setup*.exe", workflow_text)
        self.assertIn("dist/releases.*.json", workflow_text)
        self.assertIn("dist/assets.*.json", workflow_text)
        self.assertIn("dist/*.nupkg", workflow_text)
        self.assertNotIn("dist/*.msi", workflow_text)

    def test_windows_velopack_script_keeps_dotnet_output_out_of_vpk_path(self) -> None:
        script_text = (Path(__file__).resolve().parents[2] / "scripts/package_windows_velopack.ps1").read_text(encoding="utf-8")

        self.assertIn("$dotnetOutput = & dotnet @args 2>&1", script_text)
        self.assertIn("$dotnetExitCode = $LASTEXITCODE", script_text)
        self.assertIn("foreach ($line in $dotnetOutput)", script_text)
        self.assertIn("if ($dotnetExitCode -ne 0)", script_text)

    def test_windows_velopack_script_sets_pack_title(self) -> None:
        script_text = (Path(__file__).resolve().parents[2] / "scripts/package_windows_velopack.ps1").read_text(encoding="utf-8")

        self.assertIn("'--packTitle', 'SecondLoop'", script_text)

    def test_windows_velopack_script_sets_pack_icon_and_checks_metadata_outputs(self) -> None:
        script_text = (Path(__file__).resolve().parents[2] / "scripts/package_windows_velopack.ps1").read_text(encoding="utf-8")

        self.assertIn("'--icon', $packIconPath", script_text)
        self.assertIn('"releases.$Channel.json"', script_text)
        self.assertIn('"assets.$Channel.json"', script_text)

    def test_windows_release_publishes_setup_checksum_asset(self) -> None:
        workflow_text = self._workflow_text()

        self.assertIn("SecondLoop-win-Setup.exe.sha256", workflow_text)
        self.assertIn("dist/*Setup*.exe.sha256", workflow_text)

    def test_release_workflow_generates_winget_manifests(self) -> None:
        workflow_text = self._workflow_text()

        self.assertIn("Generate WinGet manifests", workflow_text)
        self.assertIn("scripts/generate_winget_manifests.py", workflow_text)
        self.assertIn("SecondLoop.SecondLoop", workflow_text)
        self.assertIn("dist/winget-manifests", workflow_text)
        self.assertIn("SecondLoop-winget-manifests-${GITHUB_REF_NAME}.zip", workflow_text)

    def test_release_workflow_publishes_winget_manifest_bundle(self) -> None:
        workflow_text = self._workflow_text()

        self.assertIn("dist/SecondLoop-winget-manifests-*.zip", workflow_text)

    def test_release_workflow_publishes_homebrew_cask_to_external_tap(self) -> None:
        workflow_text = self._workflow_text()

        self.assertIn("publish_homebrew_cask:", workflow_text)
        self.assertIn("HOMEBREW_TAP_TOKEN", workflow_text)
        self.assertIn("SecondLoopHomebrew", workflow_text)
        self.assertIn("scripts/publish_homebrew_cask.sh", workflow_text)

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

    def test_publish_homebrew_cask_script_stages_then_checks_cached_diff(self) -> None:
        script_text = self._publish_homebrew_script_text()

        self.assertIn("git add Casks/secondloop.rb", script_text)
        self.assertIn("git diff --cached --quiet -- Casks/secondloop.rb", script_text)

    def test_publish_winget_manifest_script_stages_then_checks_cached_diff(self) -> None:
        script_text = self._publish_winget_script_text()

        self.assertIn('git add "${target_rel_dir}"', script_text)
        self.assertIn("git diff --cached --quiet", script_text)

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

    def test_generate_winget_manifest_script_uses_manifest_schema_1_10(self) -> None:
        script_text = self._generate_winget_script_text()

        self.assertIn('MANIFEST_VERSION = "1.10.0"', script_text)
        self.assertNotIn("ManifestVersion: 1.9.0", script_text)

    def test_generate_winget_manifest_script_declares_vcredist_dependency(self) -> None:
        script_text = self._generate_winget_script_text()

        self.assertIn("Dependencies:", script_text)
        self.assertIn("PackageDependencies:", script_text)
        self.assertIn("Microsoft.VCRedist.2015+.x64", script_text)

    def test_generate_winget_manifest_script_sets_user_scope(self) -> None:
        script_text = self._generate_winget_script_text()

        self.assertIn("Scope: user", script_text)

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
            self.assertTrue(
                locale_manifest.startswith(
                    "# yaml-language-server: $schema=https://aka.ms/winget-manifest.defaultLocale.1.10.0.schema.json"
                )
            )



if __name__ == "__main__":
    unittest.main()
