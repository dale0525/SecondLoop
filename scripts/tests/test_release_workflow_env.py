from __future__ import annotations

import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import tomllib
import unittest


def _find_bash_executable() -> str | None:
    git_bash_candidates = [
        Path("C:/Program Files/Git/bin/bash.exe"),
        Path("C:/Program Files/Git/usr/bin/bash.exe"),
        Path("C:/Program Files (x86)/Git/bin/bash.exe"),
    ]
    for candidate in git_bash_candidates:
        if candidate.exists():
            return str(candidate)

    return shutil.which("bash")


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

    def _workflow_job_text(self, job_name: str, workflow_text: str | None = None) -> str:
        lines = (workflow_text or self._workflow_text()).splitlines()
        header = f"  {job_name}:"

        in_job = False
        section_lines: list[str] = []

        for line in lines:
            if not in_job:
                if line == header:
                    in_job = True
                    section_lines.append(line)
                continue

            normalized_line = line.rstrip()
            if not normalized_line:
                section_lines.append(line)
                continue

            if normalized_line.startswith("  #"):
                section_lines.append(line)
                continue

            if normalized_line.startswith("  ") and not normalized_line.startswith("    "):
                break

            section_lines.append(line)

        self.assertTrue(section_lines, f"missing job section: {job_name}")
        return "\n".join(section_lines) + "\n"

    def _workflow_job_step_text(self, job_name: str, step_name: str, workflow_text: str | None = None) -> str:
        lines = self._workflow_job_text(job_name, workflow_text).splitlines()
        step_header = f"      - name: {step_name}"

        in_step = False
        step_lines: list[str] = []

        for line in lines:
            if not in_step:
                if line == step_header:
                    in_step = True
                    step_lines.append(line)
                continue

            if line.startswith("      - "):
                break

            step_lines.append(line)

        self.assertTrue(step_lines, f"missing step {step_name!r} in job {job_name!r}")
        return "\n".join(step_lines) + "\n"

    def _publish_step_run_script(self, step_name: str) -> str:
        workflow_path = Path(__file__).resolve().parents[2] / ".github/workflows/release.yml"
        lines = workflow_path.read_text(encoding="utf-8").splitlines()

        in_publish = False
        in_target_step = False
        in_run_block = False
        script_lines: list[str] = []

        for line in lines:
            if not in_publish:
                if line.startswith("  publish:"):
                    in_publish = True
                continue

            if line.startswith("  ") and not line.startswith("    "):
                break

            if not in_target_step:
                if line == f"      - name: {step_name}":
                    in_target_step = True
                continue

            if not in_run_block:
                if line == "        run: |":
                    in_run_block = True
                continue

            if line.startswith("          "):
                script_lines.append(line[10:])
                continue

            break

        self.assertTrue(script_lines, f"missing run block for step: {step_name}")
        return "\n".join(script_lines) + "\n"

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

    def _release_notes_install_guidance_text(self) -> str:
        template_path = Path(__file__).resolve().parents[2] / "scripts/release_notes_install_guidance.md"
        return template_path.read_text(encoding="utf-8")

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
        guidance_text = self._release_notes_install_guidance_text()

        self.assertIn('## macOS Installation Note (Unsigned DMG)', guidance_text)
        self.assertIn('## Build Provenance', workflow_text)
        self.assertIn('actions/runs/${GITHUB_RUN_ID}', workflow_text)

    def test_release_notes_include_windows_installer_guidance(self) -> None:
        guidance_text = self._release_notes_install_guidance_text()

        self.assertIn('## Windows Installer', guidance_text)
        self.assertIn('SecondLoop-win.msi', guidance_text)
        self.assertIn('## Windows 安装包选择建议', guidance_text)
        self.assertIn('SecondLoop-win.msi.sha256', guidance_text)

    def test_release_notes_append_step_uses_utf8_template_fragment(self) -> None:
        workflow_text = self._workflow_text()

        self.assertIn('scripts/release_notes_install_guidance.md', workflow_text)

    def test_release_notes_append_step_renders_concrete_values(self) -> None:
        script_text = self._publish_step_run_script("Append install guidance and build provenance")
        bash_executable = _find_bash_executable()
        if bash_executable is None:
            self.skipTest("bash is not available in this environment")

        with tempfile.TemporaryDirectory() as tmpdir:
            temp_path = Path(tmpdir)
            dist_path = temp_path / "dist"
            dist_path.mkdir()
            notes_path = dist_path / "release-notes.md"
            notes_path.write_text("# Existing notes\n", encoding="utf-8")

            bin_path = temp_path / "bin"
            bin_path.mkdir()
            stub_commands = {
                "brew": "#!/usr/bin/env bash\nexit 0\n",
                "winget": "#!/usr/bin/env bash\nexit 0\n",
                "shasum": "#!/usr/bin/env bash\nexit 0\n",
                "SecondLoop-win.msi": "#!/usr/bin/env bash\nexit 0\n",
            }
            for command_name, command_text in stub_commands.items():
                command_path = bin_path / command_name
                command_path.write_text(command_text, encoding="utf-8")
                command_path.chmod(0o755)

            scripts_path = temp_path / "scripts"
            scripts_path.mkdir()
            template_path = scripts_path / "release_notes_install_guidance.md"
            template_path.write_text(
                self._release_notes_install_guidance_text(),
                encoding="utf-8",
            )

            (temp_path / "dmg-file").write_text("placeholder\n", encoding="utf-8")

            env = os.environ.copy()
            env.update(
                {
                    "GITHUB_SHA": "abc123def456",
                    "GITHUB_RUN_ID": "22790340272",
                    "GITHUB_REPOSITORY": "dale0525/SecondLoop",
                    "GITHUB_RUN_ATTEMPT": "7",
                    "PATH": f"{bin_path}{os.pathsep}{env.get('PATH', '')}",
                }
            )

            result = subprocess.run(
                [bash_executable, "-lc", script_text],
                capture_output=True,
                cwd=temp_path,
                env=env,
                text=True,
            )

            self.assertEqual(result.returncode, 0, msg=result.stderr)

            rendered_notes = notes_path.read_text(encoding="utf-8")
            self.assertIn("- Commit: `abc123def456`", rendered_notes)
            self.assertIn(
                "- Workflow run: [#22790340272](https://github.com/dale0525/SecondLoop/actions/runs/22790340272)",
                rendered_notes,
            )
            self.assertIn("- Workflow attempt: `7`", rendered_notes)
            self.assertRegex(
                rendered_notes,
                r"- Generated at \(UTC\): `\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z`",
            )
            self.assertIn(
                "- SHA256 checksum files are published as `*.dmg.sha256` assets.",
                rendered_notes,
            )
            self.assertIn(
                "- Verify on macOS with `shasum -a 256 -c <dmg-file>.sha256`.",
                rendered_notes,
            )
            self.assertIn(
                "- Homebrew: `brew tap dale0525/SecondLoopHomebrew && brew install --cask secondloop`",
                rendered_notes,
            )
            self.assertIn(
                "- WinGet: `winget install --id SecondLoop.SecondLoop --exact`",
                rendered_notes,
            )
            self.assertIn(
                "- Windows direct download: `SecondLoop-win.msi`.",
                rendered_notes,
            )
            self.assertIn(
                "- Future Windows updates are manual or managed by your deployment tooling.",
                rendered_notes,
            )
            self.assertIn(
                "- Windows checksum file: `SecondLoop-win.msi.sha256`.",
                rendered_notes,
            )
            self.assertNotIn("\\`", rendered_notes)

    def test_release_workflow_installs_vulkan_sdk_for_linux_and_windows(self) -> None:
        workflow_text = self._workflow_text()

        self.assertIn("windows:\n    needs: preflight", workflow_text)
        self.assertIn("linux:\n    needs: preflight", workflow_text)
        self.assertGreaterEqual(workflow_text.count("humbletim/install-vulkan-sdk@v1.2"), 2)
        self.assertIn("version: 1.4.309.0", workflow_text)

    def test_release_workflow_installs_linux_vulkan_linker_package(self) -> None:
        workflow_text = self._workflow_text()

        self.assertIn("libvulkan-dev", workflow_text)

    def test_release_workflow_exposes_github_token_for_desktop_runtime_download(self) -> None:
        workflow_text = self._workflow_text()

        self.assertGreaterEqual(workflow_text.count("GH_TOKEN: ${{ github.token }}"), 4)
        self.assertGreaterEqual(workflow_text.count("GITHUB_TOKEN: ${{ github.token }}"), 4)

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
        self.assertIn(
            'bash scripts/build_android_release_apk.sh --split-per-abi "${build_args[@]}" "${defines[@]}"',
            workflow_text,
        )
        self.assertIn(
            'bash scripts/build_android_release_apk.sh "${build_args[@]}" "${defines[@]}"',
            workflow_text,
        )
        self.assertIn('--split-per-abi', workflow_text)

    def test_release_workflow_packages_split_android_apks(self) -> None:
        workflow_text = self._workflow_text()

        self.assertIn(
            '[armeabi-v7a]="build/app/outputs/flutter-apk/app-armeabi-v7a-release.apk"',
            workflow_text,
        )
        self.assertIn(
            '[arm64-v8a]="build/app/outputs/flutter-apk/app-arm64-v8a-release.apk"',
            workflow_text,
        )
        self.assertIn(
            '[universal]="build/app/outputs/flutter-apk/app-release.apk"',
            workflow_text,
        )
        self.assertIn(
            'cp "${source_path}" "dist/SecondLoop-android-${abi}-${safe_ref_name}.apk"',
            workflow_text,
        )

    def test_release_workflow_cleans_unversioned_windows_releases_metadata_before_manifest_generation(self) -> None:
        workflow_text = self._workflow_text()

        self.assertIn('rm -f dist/releases.win.json', workflow_text)

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

    def test_workflow_job_text_matches_exact_job_headers(self) -> None:
        workflow_text = """jobs:
  metadata:
    steps:
      - run: echo android:
  android:
    runs-on: ubuntu-latest
    steps:
      - run: flutter pub get
"""

        section_text = self._workflow_job_text("android", workflow_text)

        self.assertTrue(section_text.startswith("  android:\n"))
        self.assertIn("    runs-on: ubuntu-latest", section_text)
        self.assertNotIn("echo android:", section_text)

    def test_workflow_job_text_ignores_root_level_comments_and_blank_lines_within_job(self) -> None:
        workflow_text = """jobs:
  android:
    runs-on: ubuntu-latest
  # keep android job grouped
  
    steps:
      - run: flutter pub get
  windows:
    runs-on: windows-latest
"""

        section_text = self._workflow_job_text("android", workflow_text)

        self.assertIn("    steps:", section_text)
        self.assertIn("      - run: flutter pub get", section_text)
        self.assertNotIn("  windows:", section_text)

    def test_release_workflow_refreshes_i18n_generated_files_after_pub_get_for_each_build_job(self) -> None:
        for job_name in ["android", "windows", "macos", "linux"]:
            section_text = self._workflow_job_text(job_name)
            pub_get_idx = section_text.find("run: flutter pub get")
            refresh_name_idx = section_text.find("- name: Refresh i18n generated files")
            refresh_run_idx = section_text.find("run: bash scripts/run_i18n_refresh.sh")

            self.assertNotEqual(-1, pub_get_idx, f"Missing flutter pub get in {job_name}")
            self.assertNotEqual(-1, refresh_name_idx, f"Missing i18n refresh step in {job_name}")
            self.assertNotEqual(-1, refresh_run_idx, f"Missing i18n refresh command in {job_name}")
            self.assertLess(pub_get_idx, refresh_name_idx, f"i18n refresh must run after pub get in {job_name}")
            self.assertLess(refresh_name_idx, refresh_run_idx, f"i18n refresh step body missing in {job_name}")

    def test_windows_release_refresh_i18n_step_runs_under_pwsh(self) -> None:
        step_text = self._workflow_job_step_text("windows", "Refresh i18n generated files")

        self.assertIn("        shell: pwsh", step_text)
        self.assertIn("        run: bash scripts/run_i18n_refresh.sh", step_text)

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

    def test_only_linux_whisper_dependency_enables_vulkan_backend(self) -> None:
        cargo_path = Path(__file__).resolve().parents[2] / "rust/Cargo.toml"
        with cargo_path.open("rb") as fh:
            cargo_config = tomllib.load(fh)

        target_config = cargo_config["target"]
        windows_dep = target_config['cfg(target_os = "windows")']["dependencies"]["whisper-rs"]
        linux_dep = target_config['cfg(target_os = "linux")']["dependencies"]["whisper-rs"]

        self.assertNotIn("features", windows_dep)
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
        self.assertIn("$targetFfmpeg = Join-Path $ffmpegRoot 'windows/ffmpeg.zip'", workflow_text)
        self.assertNotIn("windows/ffmpeg.exe", workflow_text)
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

    def test_windows_release_packages_and_uploads_msi_and_velopack_artifacts(self) -> None:
        workflow_text = self._workflow_text()

        self.assertIn("name: Package Velopack", workflow_text)
        self.assertIn("name: Package MSI", workflow_text)
        self.assertIn("scripts/package_windows_velopack.ps1", workflow_text)
        self.assertNotIn("powershell -NoProfile -ExecutionPolicy Bypass -File scripts/package_windows_velopack.ps1", workflow_text)
        self.assertIn("scripts/create_windows_msi.ps1", workflow_text)
        self.assertIn("OutputName = 'SecondLoop-win'", workflow_text)
        self.assertIn("OutputPath = 'dist'", workflow_text)
        self.assertIn("dist/SecondLoop-win.msi", workflow_text)
        self.assertIn("dist/SecondLoop-win.msi.sha256", workflow_text)
        self.assertIn("dist/*.nupkg", workflow_text)
        self.assertIn("dist/releases.*.json", workflow_text)
        self.assertIn("dist/assets.*.json", workflow_text)

    def test_windows_release_passes_tag_version_to_msi_packaging(self) -> None:
        workflow_text = self._workflow_text()

        self.assertIn('$Env:GITHUB_REF -like "refs/tags/v*"', workflow_text)
        self.assertIn('$msiArgs.Version = $msiVersion', workflow_text)
        self.assertIn('& scripts/create_windows_msi.ps1 @msiArgs', workflow_text)

    def test_windows_velopack_script_keeps_dotnet_output_out_of_vpk_path(self) -> None:
        script_text = (Path(__file__).resolve().parents[2] / "scripts/package_windows_velopack.ps1").read_text(encoding="utf-8")

        self.assertIn("$dotnetOutput = & dotnet @args 2>&1", script_text)
        self.assertIn("$dotnetExitCode = $LASTEXITCODE", script_text)
        self.assertIn("foreach ($line in $dotnetOutput)", script_text)
        self.assertIn("if ($dotnetExitCode -ne 0)", script_text)

    def test_windows_velopack_script_sets_pack_title(self) -> None:
        script_text = (Path(__file__).resolve().parents[2] / "scripts/package_windows_velopack.ps1").read_text(encoding="utf-8")

        self.assertIn("'--packTitle', 'SecondLoop'", script_text)

    def test_windows_velopack_script_prefers_tag_version_when_available(self) -> None:
        script_text = (Path(__file__).resolve().parents[2] / "scripts/package_windows_velopack.ps1").read_text(encoding="utf-8")

        self.assertIn('if ($env:GITHUB_REF -and $env:GITHUB_REF_NAME -and ($env:GITHUB_REF -like "refs/tags/v*"))', script_text)
        self.assertIn('return $tagCandidate', script_text)

    def test_windows_velopack_script_sets_pack_icon_and_checks_metadata_outputs(self) -> None:
        script_text = (Path(__file__).resolve().parents[2] / "scripts/package_windows_velopack.ps1").read_text(encoding="utf-8")

        self.assertIn("'--icon', $packIconPath", script_text)
        self.assertIn('"releases.$Channel.json"', script_text)
        self.assertIn('"assets.$Channel.json"', script_text)

    def test_release_workflow_generates_signed_update_manifest(self) -> None:
        workflow_text = self._workflow_text()

        self.assertIn("SECONDLOOP_UPDATE_PUBLIC_KEY", workflow_text)
        self.assertIn("SECONDLOOP_UPDATE_SIGNING_PRIVATE_KEY", workflow_text)
        self.assertIn('Missing secret SECONDLOOP_UPDATE_PUBLIC_KEY', workflow_text)
        self.assertIn("tools/generate_update_manifest.dart", workflow_text)
        self.assertIn("dist/latest.json", workflow_text)
        self.assertIn("dist/latest.json.sig", workflow_text)
        self.assertNotIn("--signing-private-key", workflow_text)

    def test_publish_job_maps_update_public_key_secret(self) -> None:
        env_keys = self._publish_env_keys()

        self.assertIn("SECONDLOOP_UPDATE_PUBLIC_KEY", env_keys)

    def test_preflight_signing_validation_only_runs_for_tag_releases(self) -> None:
        preflight_job = self._workflow_job_text("preflight")

        self.assertIn("- name: Validate release signing config", preflight_job)
        self.assertIn(
            "if: startsWith(github.ref, 'refs/tags/')\n        shell: bash\n        run: |\n          : \"${SECONDLOOP_UPDATE_PUBLIC_KEY:?Missing secret SECONDLOOP_UPDATE_PUBLIC_KEY}\"",
            preflight_job,
        )
        self.assertIn(
            '          : "${SECONDLOOP_UPDATE_SIGNING_PRIVATE_KEY:?Missing secret SECONDLOOP_UPDATE_SIGNING_PRIVATE_KEY}"',
            preflight_job,
        )

    def test_publish_validation_step_name_reflects_signing_and_llm_checks(self) -> None:
        publish_job = self._workflow_job_text("publish")

        self.assertIn("- name: Validate release publish config", publish_job)
        self.assertIn(
            '          : "${RELEASE_LLM_API_KEY:?Missing secret RELEASE_LLM_API_KEY}"',
            publish_job,
        )
        self.assertIn(
            '          : "${RELEASE_LLM_MODEL:?Missing secret RELEASE_LLM_MODEL}"',
            publish_job,
        )
        self.assertIn(
            '          : "${SECONDLOOP_UPDATE_PUBLIC_KEY:?Missing secret SECONDLOOP_UPDATE_PUBLIC_KEY}"',
            publish_job,
        )
        self.assertIn(
            '          : "${SECONDLOOP_UPDATE_SIGNING_PRIVATE_KEY:?Missing secret SECONDLOOP_UPDATE_SIGNING_PRIVATE_KEY}"',
            publish_job,
        )

    def test_release_workflow_packages_macos_managed_archive(self) -> None:
        workflow_text = self._workflow_text()

        self.assertIn("SecondLoop-macos-${safe_ref_name}.app.tar.gz", workflow_text)
        self.assertIn("dist/*.app.tar.gz.sha256", workflow_text)

    def test_windows_release_publishes_bootstrap_setup_without_checksum(self) -> None:
        workflow_text = self._workflow_text()

        self.assertIn("dist/*Setup*.exe", workflow_text)
        self.assertNotIn("SecondLoop-win-Setup.exe.sha256", workflow_text)
        self.assertNotIn("dist/*Setup*.exe.sha256", workflow_text)

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
            self.assertNotIn("Dependencies:", installer_manifest)
            self.assertIn("InstallModes:", installer_manifest)
            self.assertIn("- silent", installer_manifest)
            self.assertIn("- silentWithProgress", installer_manifest)
            self.assertNotIn("- interactive", installer_manifest)
            self.assertIn("InstallerSwitches:", installer_manifest)
            self.assertIn("Custom: SECONDLOOP_LAUNCH_AFTER_INSTALL=0", installer_manifest)
            self.assertNotIn("Silent: --silent", installer_manifest)



    def test_release_workflow_has_unique_top_level_jobs(self) -> None:
        workflow_path = Path(__file__).resolve().parents[2] / ".github/workflows/release.yml"
        lines = workflow_path.read_text(encoding="utf-8").splitlines()

        job_names: list[str] = []
        for line in lines:
            if line.startswith("  ") and line.endswith(":") and not line.startswith("    "):
                job_names.append(line.strip().rstrip(":"))

        self.assertEqual(len(job_names), len(set(job_names)), msg=f"duplicate top-level jobs: {job_names}")

if __name__ == "__main__":
    unittest.main()
