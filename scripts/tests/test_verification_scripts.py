from __future__ import annotations

from pathlib import Path
import unittest


REPO_ROOT = Path(__file__).resolve().parents[2]
PIXI_TOML = REPO_ROOT / "pixi.toml"
CONTRIBUTING = REPO_ROOT / "CONTRIBUTING.md"
RUN_BASH_PS1 = REPO_ROOT / "scripts/run_bash.ps1"


class VerificationScriptsTests(unittest.TestCase):
    def test_pixi_ci_documents_shared_full_verification_entrypoint(self) -> None:
        pixi = PIXI_TOML.read_text(encoding="utf-8")

        self.assertIn("scripts/run_full_ci_parallel.sh", pixi)

    def test_windows_pixi_ci_uses_powershell_bash_launcher(self) -> None:
        pixi = PIXI_TOML.read_text(encoding="utf-8")

        self.assertTrue(RUN_BASH_PS1.exists())
        self.assertIn(
            'ci = "powershell -NoProfile -ExecutionPolicy Bypass -File scripts/run_bash.ps1 scripts/run_full_ci_parallel.sh"',
            pixi,
        )

    def test_pixi_verify_changed_documents_shared_check_only_entrypoint(self) -> None:
        pixi = PIXI_TOML.read_text(encoding="utf-8")

        self.assertIn('verify-changed = "bash scripts/verify_changed.sh"', pixi)
        self.assertIn(
            'verify-changed = "powershell -NoProfile -ExecutionPolicy Bypass -File scripts/run_bash.ps1 scripts/verify_changed.sh"',
            pixi,
        )

    def test_contributing_documents_fast_commit_and_full_push_flow(self) -> None:
        contributing = CONTRIBUTING.read_text(encoding="utf-8")

        self.assertIn("fast pre-commit + scoped pre-push verification", contributing)
        self.assertIn("same scope as `pre-push` / CI", contributing)
        self.assertIn("Check-only local gate", contributing)
        self.assertIn("`pixi run verify-changed`", contributing)
        self.assertIn("`pixi run ci`", contributing)
        self.assertIn("run in parallel locally", contributing)
        self.assertIn("scoped pre-push", contributing)
        self.assertIn("Tooling-scoped script / Python changes", contributing)
        self.assertIn("maintenance scripts under `scripts/*`", contributing)

    def test_parallel_ci_wrapper_runs_flutter_and_web_scopes(self) -> None:
        script = (REPO_ROOT / "scripts/run_full_ci_parallel.sh").read_text(
            encoding="utf-8"
        )

        self.assertIn('bash scripts/run_flutter_ci_local.sh', script)
        self.assertIn('bash scripts/run_flutter_web_ci_local.sh', script)
        self.assertIn('ci: starting Flutter verification...', script)
        self.assertIn('ci: starting Web verification...', script)

    def test_parallel_ci_wrapper_runs_python_tooling_scope(self) -> None:
        script = (REPO_ROOT / "scripts/run_full_ci_parallel.sh").read_text(
            encoding="utf-8"
        )

        self.assertIn('bash scripts/run_python_tooling_checks.sh', script)
        self.assertIn('ci: starting Python tooling verification...', script)

    def test_parallel_ci_wrapper_runs_web_scope(self) -> None:
        script = (REPO_ROOT / "scripts/run_full_ci_parallel.sh").read_text(
            encoding="utf-8"
        )

        self.assertIn('bash scripts/run_flutter_web_ci_local.sh', script)
        self.assertIn('ci: starting Web verification...', script)

    def test_parallel_ci_wrapper_emits_logs_as_each_scope_finishes(self) -> None:
        script = (REPO_ROOT / "scripts/run_full_ci_parallel.sh").read_text(
            encoding="utf-8"
        )

        self.assertIn('handle_finished_job()', script)
        self.assertIn('cancel_remaining_jobs()', script)
        self.assertIn('remaining_jobs=', script)
        self.assertIn('wait "${job_pid}"', script)
        self.assertNotIn('wait "${flutter_pid}"', script)

    def test_parallel_ci_wrapper_cancels_other_scopes_after_first_failure(self) -> None:
        script = (REPO_ROOT / "scripts/run_full_ci_parallel.sh").read_text(
            encoding="utf-8"
        )

        self.assertIn('overall_status=0', script)
        self.assertIn('cancelling ${name} verification after ${failed_job} failure', script)

    def test_local_flutter_ci_wrapper_runs_gate_and_shards(self) -> None:
        script = (REPO_ROOT / "scripts/run_flutter_ci_local.sh").read_text(
            encoding="utf-8"
        )

        self.assertIn('bash .githooks/pre-commit --check --flutter', script)
        self.assertNotIn('bash .githooks/pre-commit --check --flutter --skip-tests', script)
        self.assertIn('SECONDLOOP_LOCAL_FLUTTER_TEST_SHARDS', script)
        self.assertIn('bash scripts/run_flutter_test_shard.sh', script)

    def test_local_flutter_ci_wrapper_prepares_i18n_outputs_before_shards(self) -> None:
        script = (REPO_ROOT / "scripts/run_flutter_ci_local.sh").read_text(
            encoding="utf-8"
        )

        self.assertIn('echo "ci: preparing i18n outputs in a temporary Flutter worktree..." >&2', script)
        self.assertIn('git worktree add --detach', script)
        self.assertIn('copy_prepared_i18n_tree()', script)
        self.assertIn('run_flutter_tool pub get', script)
        self.assertIn('copy_prepared_flutter_tool_state()', script)
        self.assertIn('bash scripts/run_i18n_refresh.sh', script)
        self.assertIn('create_flutter_worktree "shard-${shard_index}"', script)
        self.assertNotIn('shard_worktree="${prepared_worktree}"', script)
        self.assertIn('flutter pub get (Flutter shard ${shard_index}/${flutter_shards})', script)
        self.assertIn('elif is_windows_env; then', script)
        self.assertIn('flutter_shards=2', script)
        self.assertIn('export SECONDLOOP_SHORT_WORKSPACE_DRIVE="${SECONDLOOP_SHORT_WORKSPACE_DRIVE:-Y}"', script)

    def test_local_flutter_ci_wrapper_syncs_workspace_state_into_temp_worktrees(self) -> None:
        script = (REPO_ROOT / "scripts/run_flutter_ci_local.sh").read_text(
            encoding="utf-8"
        )

        self.assertIn('sync_workspace_state_into_worktree()', script)
        self.assertIn('git diff --binary --relative HEAD', script)
        self.assertIn('git ls-files --others --exclude-standard -z', script)

    def test_local_flutter_ci_wrapper_cleanup_reaps_gate_and_shards(self) -> None:
        script = (REPO_ROOT / "scripts/run_flutter_ci_local.sh").read_text(
            encoding="utf-8"
        )

        self.assertIn('for pid in "${flutter_gate_pid:-}" "${flutter_test_pids[@]-}"; do', script)
        self.assertIn("trap cleanup EXIT INT TERM", script)
        self.assertIn('cancel_remaining_shards()', script)
        self.assertIn('overall_status=0', script)
        self.assertIn('print_log_if_present()', script)
        self.assertIn('cat "${log_path}" 2>/dev/null || true', script)

    def test_flutter_test_shard_requires_prepared_i18n_outputs(self) -> None:
        script = (REPO_ROOT / "scripts/run_flutter_test_shard.sh").read_text(
            encoding="utf-8"
        )

        self.assertIn('lib/i18n/strings.g.dart is required before running shards', script)
        self.assertNotIn('failed to regenerate lib/i18n/strings.g.dart', script)

    def test_flutter_test_shard_uses_xvfb_for_linux_integration_targets(self) -> None:
        script = (REPO_ROOT / "scripts/run_flutter_test_shard.sh").read_text(
            encoding="utf-8"
        )

        self.assertIn("run_flutter_unit_tests_in_batches()", script)
        self.assertIn(
            'local max_batch_chars="${SECONDLOOP_FLUTTER_TEST_MAX_BATCH_CHARS:-1000000}"',
            script,
        )
        self.assertIn(
            'local max_batch_targets="${SECONDLOOP_FLUTTER_TEST_MAX_BATCH_TARGETS:-1000000}"',
            script,
        )
        self.assertIn(
            'max_batch_chars="${SECONDLOOP_FLUTTER_TEST_MAX_BATCH_CHARS:-6000}"',
            script,
        )
        self.assertIn(
            'max_batch_targets="${SECONDLOOP_FLUTTER_TEST_MAX_BATCH_TARGETS:-48}"',
            script,
        )
        self.assertIn('SECONDLOOP_FLUTTER_TEST_MAX_BATCH_CHARS', script)
        self.assertIn('SECONDLOOP_FLUTTER_TEST_MAX_BATCH_TARGETS', script)
        self.assertIn('if [[ "${integration_test_device}" == "linux" ]]; then', script)
        self.assertIn('xvfb-run -a', script)

    def test_local_flutter_ci_sets_default_batch_target_limit(self) -> None:
        script = (REPO_ROOT / "scripts/run_flutter_ci_local.sh").read_text(
            encoding="utf-8"
        )

        self.assertIn(
            'export SECONDLOOP_FLUTTER_TEST_MAX_BATCH_TARGETS="${SECONDLOOP_FLUTTER_TEST_MAX_BATCH_TARGETS:-48}"',
            script,
        )

    def test_local_flutter_web_ci_wrapper_disables_git_bash_path_rewriting_for_base_href(self) -> None:
        script = (REPO_ROOT / "scripts/run_flutter_web_ci_local.sh").read_text(
            encoding="utf-8"
        )

        self.assertIn("MSYS2_ARG_CONV_EXCL='*' run_with_periodic_status", script)
        self.assertIn("run_flutter_tool build web --base-href /app/", script)

    def test_windows_smoke_tests_resolve_powershell_portably(self) -> None:
        script = (REPO_ROOT / "scripts/tests/test_windows_auto_update_smoke.py").read_text(
            encoding="utf-8"
        )

        self.assertIn('import shutil', script)
        self.assertIn('shutil.which', script)
        self.assertIn('self.skipTest', script)
        self.assertIn('pwsh', script)

    def test_check_mode_does_not_refresh_i18n_outputs(self) -> None:
        check_mode = (REPO_ROOT / "scripts/pre_commit_check_mode.sh").read_text(
            encoding="utf-8"
        )

        self.assertIn("run_i18n_refresh_in_temp_copy", check_mode)
        self.assertIn("git diff --no-index --exit-code --", check_mode)
        self.assertIn('"${repo_root}/lib/i18n"', check_mode)
        self.assertIn('"${i18n_temp_repo}/lib/i18n"', check_mode)
        self.assertIn("ensure_temp_i18n_strings_for_analysis", check_mode)
        self.assertIn('cp "${i18n_temp_repo}/lib/i18n/strings.g.dart"', check_mode)
        self.assertNotIn('lib/i18n/strings.g.dart is missing', check_mode)
        self.assertIn('SECONDLOOP_I18N_DART_BIN', check_mode)
        self.assertIn('SECONDLOOP_I18N_FLUTTER_BIN', check_mode)
        self.assertIn('package_config.json', check_mode)
        self.assertNotIn('cp -R "${repo_root}/.dart_tool"', check_mode)
        self.assertIn('Fix locally with: pixi run ci', check_mode)
        self.assertNotIn("ensure_i18n_generated", check_mode)

    def test_check_mode_disables_worktree_writes_for_tooling_setup(self) -> None:
        check_mode = (REPO_ROOT / "scripts/pre_commit_check_mode.sh").read_text(
            encoding="utf-8"
        )
        pre_commit = (REPO_ROOT / ".githooks/pre-commit").read_text(
            encoding="utf-8"
        )
        common = (REPO_ROOT / "scripts/pre_commit_common.sh").read_text(
            encoding="utf-8"
        )

        self.assertIn('SECONDLOOP_PRECOMMIT_ALLOW_WORKTREE_WRITES=0', check_mode)
        self.assertIn('precommit_allow_worktree_writes=0', check_mode)
        self.assertIn(
            'if (( check_mode )); then\n  export SECONDLOOP_PRECOMMIT_ALLOW_WORKTREE_WRITES=0\nfi',
            pre_commit,
        )
        self.assertIn('precommit_allow_worktree_writes', common)

    def test_check_mode_temp_i18n_copy_includes_local_path_dependencies(self) -> None:
        check_mode = (REPO_ROOT / "scripts/pre_commit_check_mode.sh").read_text(
            encoding="utf-8"
        )

        self.assertIn("copy_local_path_dependencies_to_temp_repo", check_mode)
        self.assertIn('cp -R "${repo_root}/${normalized_path}"', check_mode)
        self.assertIn("pending_pubspecs", check_mode)
        self.assertIn('"${i18n_temp_repo}/${normalized_path}/pubspec.yaml"', check_mode)
        self.assertIn('path:', (REPO_ROOT / "pubspec.yaml").read_text(encoding="utf-8"))

    def test_check_mode_temp_i18n_copy_includes_dependency_overrides_path_dependencies(self) -> None:
        check_mode = (REPO_ROOT / "scripts/pre_commit_check_mode.sh").read_text(
            encoding="utf-8"
        )

        self.assertIn("extract_local_path_dependencies_from_pubspec", check_mode)
        self.assertIn("dependency_overrides", (REPO_ROOT / "pubspec.yaml").read_text(encoding="utf-8"))
        self.assertIn("third_party/flutter_local_notifications_windows_patched", (REPO_ROOT / "pubspec.yaml").read_text(encoding="utf-8"))
        self.assertIn("third_party/just_audio_windows_patched", (REPO_ROOT / "pubspec.yaml").read_text(encoding="utf-8"))

    def test_verify_changed_uses_non_mutating_check_mode(self) -> None:
        verify_changed = (REPO_ROOT / "scripts/verify_changed.sh").read_text(
            encoding="utf-8"
        )

        self.assertIn("bash .githooks/pre-commit --check", verify_changed)
        self.assertIn(
            "powershell -NoProfile -ExecutionPolicy Bypass -File scripts/run_bash.ps1 .githooks/pre-commit --check",
            verify_changed,
        )

    def test_windows_pixi_install_hooks_uses_powershell_bash_launcher(self) -> None:
        pixi = PIXI_TOML.read_text(encoding="utf-8")

        self.assertTrue(RUN_BASH_PS1.exists())
        self.assertIn("scripts/run_bash.ps1 scripts/install_git_hooks.sh", pixi)

    def test_ci_workflow_scoped_filters_cover_i18n_lockfiles_and_tool_dart(self) -> None:
        workflow = (REPO_ROOT / ".github/workflows/ci.yml").read_text(
            encoding="utf-8"
        )

        self.assertIn('              - "slang.yaml"', workflow)
        self.assertIn('              - "pixi.lock"', workflow)
        self.assertIn('              - "tools/*.dart"', workflow)
        self.assertIn('              - "third_party/**"', workflow)
        self.assertIn('              - "assets/**"', workflow)
        self.assertIn('              - ".github/workflows/ci.yml"', workflow)

    def test_ci_workflow_tooling_python_filter_covers_git_hooks(self) -> None:
        workflow = (REPO_ROOT / ".github/workflows/ci.yml").read_text(
            encoding="utf-8"
        )

        tooling_section = workflow.split("            tooling_python:\n", maxsplit=1)[1]
        tooling_section = tooling_section.split("            flutter:\n", maxsplit=1)[0]

        self.assertIn('              - ".githooks/**"', tooling_section)
        self.assertIn('              - "tools/check_icon_corners.py"', tooling_section)
        self.assertIn('              - "tools/round_icon.py"', tooling_section)
        self.assertIn('              - "tools/week11_gateway_smoke.py"', tooling_section)
        self.assertIn('              - "tools/**/*.py"', tooling_section)

    def test_ci_workflow_uses_pixi_for_tooling_jobs(self) -> None:
        workflow = (REPO_ROOT / ".github/workflows/ci.yml").read_text(
            encoding="utf-8"
        )

        self.assertIn("run: pixi run tooling-test", workflow)
        self.assertNotIn("run: bash scripts/run_python_tooling_checks.sh", workflow)

    def test_ci_workflow_treats_all_workflow_changes_as_full_scope_inputs(self) -> None:
        workflow = (REPO_ROOT / ".github/workflows/ci.yml").read_text(
            encoding="utf-8"
        )

        for start, end in [
            ("            tooling_python:\n", "            flutter:\n"),
            ("            flutter:\n", "            web:\n"),
            ("            web:\n", "\n  python-tooling:\n"),
        ]:
            section = workflow.split(start, maxsplit=1)[1]
            section = section.split(end, maxsplit=1)[0]
            self.assertTrue(
                '              - ".github/workflows/**"' in section
                or '              - ".github/workflows/web-build.yml"' in section,
                msg=f"workflow paths missing from section starting {start!r}",
            )

    def test_ci_workflow_web_filter_avoids_generic_script_changes(self) -> None:
        workflow = (REPO_ROOT / ".github/workflows/ci.yml").read_text(
            encoding="utf-8"
        )

        web_section = workflow.split("            web:\n", maxsplit=1)[1]
        web_section = web_section.split("\n\n  python-tooling:\n", maxsplit=1)[0]

        self.assertNotIn('              - "scripts/**"', web_section)

    def test_web_build_workflow_paths_cover_i18n_and_lockfiles(self) -> None:
        workflow = (REPO_ROOT / ".github/workflows/web-build.yml").read_text(
            encoding="utf-8"
        )

        self.assertIn('      - "slang.yaml"', workflow)
        self.assertIn('      - "pixi.lock"', workflow)
        self.assertIn('      - "pixi.toml"', workflow)
        self.assertIn('      - "third_party/**"', workflow)
        self.assertIn('      - "assets/**"', workflow)
        self.assertIn('      - "scripts/check_no_python_runtime.sh"', workflow)
        self.assertNotIn('      - "scripts/**"', workflow)

    def test_web_build_workflow_dispatches_site_deploys_after_main_pushes(self) -> None:
        workflow = (REPO_ROOT / ".github/workflows/web-build.yml").read_text(
            encoding="utf-8"
        )

        self.assertIn("github.event_name == 'push'", workflow)
        self.assertIn("github.ref_name == 'main'", workflow)
        self.assertIn("secondloop_web_release_published", workflow)
        self.assertIn('gh api "repos/$SITE_REPO/dispatches"', workflow)

    def test_pixi_adds_tooling_entrypoint(self) -> None:
        pixi = PIXI_TOML.read_text(encoding="utf-8")

        self.assertIn('tooling-test = "bash scripts/run_python_tooling_checks.sh"', pixi)

    def test_ci_workflow_serializes_flutter_gate_before_expensive_jobs(self) -> None:
        workflow = (REPO_ROOT / ".github/workflows/ci.yml").read_text(
            encoding="utf-8"
        )

        flutter_gate_section = workflow.split("  flutter-gate:\n", maxsplit=1)[1]
        flutter_gate_section = flutter_gate_section.split("\n\n  flutter-tests:\n", maxsplit=1)[0]
        flutter_tests_section = workflow.split("  flutter-tests:\n", maxsplit=1)[1]
        flutter_tests_section = flutter_tests_section.split("\n\n  flutter-web:\n", maxsplit=1)[0]
        flutter_web_section = workflow.split("  flutter-web:\n", maxsplit=1)[1]

        self.assertIn(
            "if: needs.changes.outputs.flutter == 'true' || needs.changes.outputs.web == 'true'",
            flutter_gate_section,
        )
        self.assertIn("needs: [changes, flutter-gate]", flutter_tests_section)
        self.assertIn("needs: [changes, flutter-gate]", flutter_web_section)

    def test_ci_workflow_flutter_test_matrix_uses_fail_fast(self) -> None:
        workflow = (REPO_ROOT / ".github/workflows/ci.yml").read_text(
            encoding="utf-8"
        )

        flutter_tests_section = workflow.split("  flutter-tests:\n", maxsplit=1)[1]
        flutter_tests_section = flutter_tests_section.split("\n\n  flutter-web:\n", maxsplit=1)[0]

        self.assertNotIn("fail-fast: false", flutter_tests_section)

    def test_ci_workflow_flutter_tests_install_linux_desktop_dependencies(self) -> None:
        workflow = (REPO_ROOT / ".github/workflows/ci.yml").read_text(
            encoding="utf-8"
        )

        flutter_tests_section = workflow.split("  flutter-tests:\n", maxsplit=1)[1]
        flutter_tests_section = flutter_tests_section.split("\n\n  flutter-web:\n", maxsplit=1)[0]

        self.assertIn("Install Linux desktop dependencies", flutter_tests_section)
        self.assertIn("libgtk-3-dev", flutter_tests_section)
        self.assertIn("libsecret-1-dev", flutter_tests_section)
        self.assertIn("libkeybinder-3.0-dev", flutter_tests_section)
        self.assertIn("pkg-config", flutter_tests_section)
        self.assertIn("xvfb", flutter_tests_section)

    def test_pre_commit_common_resolve_python_bin_requires_executable_candidates(self) -> None:
        common = (REPO_ROOT / "scripts/pre_commit_common.sh").read_text(
            encoding="utf-8"
        )

        self.assertIn('if [[ -x "${candidate}" ]]; then', common)
        self.assertNotIn('if [[ -x "${candidate}" || -f "${candidate}" ]]; then', common)

    def test_windows_bash_launcher_prefers_project_managed_bash_candidates(self) -> None:
        launcher = RUN_BASH_PS1.read_text(encoding="utf-8")

        self.assertIn('.pixi/envs/default/Library/bin/bash.exe', launcher)
        self.assertIn('.pixi/envs/default/bin/bash.exe', launcher)
        self.assertIn('.tool/git/bin/bash.exe', launcher)


if __name__ == "__main__":
    unittest.main()
