# Implementation Plan

## Checklist

- [x] Validate current worker contract changes with focused Flutter tests.
- [x] Deploy the updated self-managed local QA worker to Cloudflare.
- [x] Clear only the QA runtime state needed to re-run the affected case.
- [x] Re-run SM-REM-01 through the App with Computer Use.
- [x] Approve memory and recurring reminder candidates in the App.
- [x] Confirm runtime state contains active birthday memory and approved
      recurring reminder rule.
- [x] Continue the remaining QA cases in `docs/qa/self-managed-local-qa.md`.
- [x] For each new failure, identify whether the failing layer is worker
      contract, App UI, provider availability, connector authorization, or live
      external dependency.
- [x] Run focused tests after each code fix and a broader changed-files gate
      before wrap-up.

## Validation Commands

```bash
pixi run fmt
pixi run flutter test test/tools/self_managed_runtime_deploy_runner_test.dart
pixi run verify-changed
```

## Risk Notes

- Do not print provider keys or Cloudflare authorization tokens.
- Avoid duplicate sends in the Flutter input box; verify text is present once
  before clicking send.
- Worker-only changes need Cloudflare redeploy, not App rebuild.
- If Cloudflare OAuth is requested again, stop and wait for the user.
- Email/calendar live-send proof remains pending until the test connectors are
  authorized; local approval/draft contracts passed without side effects.
