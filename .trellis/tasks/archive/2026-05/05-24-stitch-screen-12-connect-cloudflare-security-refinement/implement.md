# Stitch Screen 12 Implementation Plan

## Scope

Implement `Setup: Connect Cloudflare (Security Refinement)` as the first
self-managed setup step, preserving existing screen 11 provider-secret and
capability-verification work.

## Steps

1. Activate this Trellis task and keep existing screen 11 working-tree changes
   intact.
2. Extend setup models with a typed Cloudflare authorization method:
   OAuth helper unavailable/degraded state, manual account id, and manual API
   token as session-only setup input.
3. Update helper/deploy runner tests so manual token data is passed only to the
   setup helper and is not saved in `RuntimeConnectionStore`.
4. Rework `SelfManagedSetupPage` and settings setup sections so the first
   viewport matches Stitch screen 12: centered transactional card,
   `Infrastructure Connection`, 1-of-4 progress, Cloudflare integration info,
   OAuth button, advanced manual form, `Cancel Setup`, `Verify Connection`, and
   safety footer.
5. Preserve access to provider secret and capability sections below the first
   screen or as the next setup step so screen 11 functionality remains real.
6. Add focused widget coverage for narrow mobile, manifest width `780`, and
   desktop width, plus manual validation error tests for missing manual account
   id/token.
7. Run focused tests, `pixi run verify-changed`, `git diff --check`, and manual
   Computer Use review at `780` width.

## Validation Commands

```bash
pixi run flutter test test/self_managed_setup_page_test.dart test/self_managed_setup_controller_test.dart test/local_runtime_helper_process_test.dart test/tools/self_managed_runtime_deploy_runner_test.dart test/scenarios/self_managed_setup_flow_test.dart
pixi run verify-changed
git diff --check
```

## Rollback

If the screen 12 layout destabilizes screen 11 behavior, revert only the new
screen 12 changes and keep the prior self-managed setup controller validation
work intact.
