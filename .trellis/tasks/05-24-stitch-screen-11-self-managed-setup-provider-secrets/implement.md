# Implementation plan

## Checklist

1. Activate the existing screen 11 task after this plan exists.
2. Read `trellis-before-dev` and relevant frontend specs before file edits.
3. Refactor `SelfManagedSetupPage` to match Stitch screen shell:
   - compact top bar;
   - mobile-width content;
   - fixed bottom Back / Run checks / Continue actions;
   - real action wiring through the existing setup helper path.
4. Refactor `SelfManagedSetupSections` into screen 11 sections:
   - setup progress rail;
   - provider secret segmented selector and obscured key input;
   - Cloudflare authorization safety cards;
   - capability verification rows backed by controller verification state;
   - runtime manifest card backed by controller manifest state.
5. Update or add focused tests:
   - existing setup flow still saves ready manifest;
   - failed side-effect discipline keeps Continue disabled and shows retry state;
   - responsive widget smoke at narrow mobile, `780` width, and desktop width;
   - helper-unavailable or failed verification appears as a degraded state.
6. Run formatting and focused validation:
   - `pixi run dart format lib/features/settings/self_managed_setup_page.dart lib/features/settings/self_managed_setup_sections.dart test/self_managed_setup_page_test.dart`
   - `pixi run flutter test test/self_managed_setup_page_test.dart test/self_managed_setup_controller_test.dart test/scenarios/self_managed_setup_flow_test.dart`
   - `pixi run flutter analyze`
   - `pixi run verify-changed`
   - `git diff --check`
7. Start the macOS app and perform Computer Use review at manifest width (`780`) for screen 11.
8. Record final mapping, feature completion, modified files, validation results, and residual differences.

## Risk points

- The production default helper is unavailable, so manual live self-managed deployment must be reported as `live QA pending` / not manually tested unless real Cloudflare/provider credentials are used.
- `CloudRuntimeManifest` has no vault-binding field yet. Do not hardcode a fake persistent value; display an honest pending/degraded value when the manifest lacks that detail.
- Existing settings routes and welcome flow expect `SelfManagedSetupPage` to be directly constructible, so constructor compatibility must be preserved.
