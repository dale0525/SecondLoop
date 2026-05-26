# Implementation Plan

1. Add uninstall request/result models next to existing self-managed setup
   models.
2. Add a `SelfManagedRuntimeUninstallRunner` beside the deploy runner.
3. Extend `LocalRuntimeHelperProcess` and `SelfManagedSetupController` with an
   uninstall path that validates Cloudflare credentials, calls helper uninstall,
   and clears saved runtime metadata only after success.
4. Extend `tools/self_managed_runtime_helper.dart` with a
   `runSelfManagedRuntimeUninstallHelper` function and optional action routing
   in `main`.
5. Add a ready-state uninstall entry and confirmation dialog to the
   self-managed setup UI.
6. Add focused helper/runner tests for validation, secret non-leakage, progress
   events, and structured output.
7. Add controller/widget tests for successful uninstall, missing manual
   credentials, confirmation, and connection clearing.
8. Run targeted `pixi` verification:

```bash
pixi run flutter test test/tools/self_managed_runtime_helper_test.dart test/tools/self_managed_runtime_deploy_runner_test.dart
pixi run flutter test test/local_runtime_helper_process_test.dart test/self_managed_setup_controller_test.dart test/self_managed_setup_page_test.dart
```

9. Add a local desktop helper process bridge with a JSONL event protocol.
10. Add Cloudflare REST automation for local-QA runtime deployment and
   uninstall.
11. Run `pixi run verify-changed` if the focused tests pass and runtime permits.

## Review Gates

- Do not store Cloudflare management tokens in models that represent persisted
  runtime connection metadata.
- Do not duplicate resource names; read them from
  `buildSelfManagedRuntimeResourcePlan()`.
- Preserve the existing deploy helper JSON output.
- Keep `lib/features/settings/self_managed_setup_page.dart` under 1000 lines;
  place new leaf UI in the existing section/card split.
- Do not claim the local-QA runtime is the final production runtime artifact.
  Its purpose is real Cloudflare deploy/uninstall hand testing until the shared
  runtime package is available in this repo.
