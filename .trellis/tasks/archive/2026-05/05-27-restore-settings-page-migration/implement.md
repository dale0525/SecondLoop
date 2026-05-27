# Implementation Plan: Restore Settings Page Migration

## Preconditions

- User confirmed the IA choice: migrated app-level settings go in a new first
  `General` tab.
- A Stitch Settings `General` design artifact exists:
  `projects/5004109454348309607/screens/3de1ffbf59494fd1a342825c9bf12ff0`.
- The assistant manually visually audited the Stitch artifact and recorded that
  it has no extra visible `General` feature elements and no missing required
  migrated settings.
- User has already approved continuing after the Stitch design gate.
- Then run:
  `python3 ./.trellis/scripts/task.py start 05-27-restore-settings-page-migration`

## Ordered Checklist

- [x] Re-check current task and working tree.
  - `python3 ./.trellis/scripts/task.py current --source`
  - `git status --short --untracked-files=all`

- [x] Complete the Stitch design gate.
  - Edit or variant the existing `Settings (Production HTML)` Stitch screen to
    add the selected `General` tab.
  - Inspect the resulting screenshot manually.
  - Record the design screen id and visual audit outcome in Trellis artifacts.

- [x] Load pre-development context.
  - Read `trellis-before-dev`.
  - Load frontend/backend specs referenced in `implement.jsonl`.

- [x] Add or update focused tests first.
  - Extend `test/settings_agent_tabs_test.dart` or add a sibling settings
    migration test.
  - Cover General tab row presence and tab ordering.
  - Cover language persistence.
  - Cover review reminder fallback persistence.
  - Cover update badge rendering.
  - Cover desktop capability gating for desktop-only rows.

- [x] Implement the General settings surface.
  - Add `general` to `AgentSettingsTab`.
  - Add a General tab before Account if the IA is approved.
  - Move top appearance controls into the General tab or otherwise avoid a
    duplicate theme row.
  - Build sections with `SettingsSection`, `SettingsRow`, `SettingsSwitchRow`,
    `SettingsActionBar` only where actions need buttons.

- [x] Reuse or extract legacy behavior safely.
  - Language label, language dialog, and locale persistence.
  - Review reminder in-app fallback load / toggle / error recovery.
  - Actions review time display and `showTimePicker` persistence.
  - Desktop boot toggles and Quick Capture hotkey display/edit behavior.
  - About, welcome guide, and diagnostics navigation.
  - Keep extracted helpers private or feature-local unless they are genuinely
    shared by both old and new settings surfaces.

- [x] Preserve platform gating.
  - `debugShowsAppearancePreferences(...)` behavior for theme appearance if
    still relevant.
  - `supportsDesktopBootSettings` for desktop startup rows.
  - `supportsDesktopHotkey` for Quick Capture hotkey rows.
  - Cloud-session/web constraints for About/update or other unsupported flows.

- [x] Pixel/visual alignment pass.
  - Compare against `test/goldens/agent_mvp/actual/settings_*_desktop.png`.
  - Confirm desktop and mobile widths do not overflow long text or trailing
    values.
  - Keep density consistent with existing Stitch settings screens.

- [x] Run focused verification.
  - `pixi run flutter test test/settings_agent_tabs_test.dart`
  - Add any new focused test file to the command.

- [x] Run final verification.
  - `pixi run dart format <changed Dart files>`
  - `pixi run verify-changed`
  - `wc -l <touched Dart files>`
  - `git status --short --untracked-files=all`

## Risky Files / Rollback Points

- `lib/features/settings/agent_settings_page.dart`: main production settings
  surface and tab ownership.
- `lib/features/settings/settings_page.dart`: legacy behavior source; avoid
  destabilizing it while extracting shared helpers.
- `lib/features/settings/settings_page_build.dart`: keep legacy settings usable
  until the migration is verified.
- `lib/i18n/settings_*.i18n.json`: touch only if new labels are needed.

## Review Gates

- Gate 1: user confirms the IA and approves planning artifacts.
- Gate 2: focused widget tests pass before visual QA.
- Gate 3: visual/manual QA confirms row density and no overflow.
- Gate 4: `pixi run verify-changed` passes before completion is reported.

## Execution Notes

- Stitch design gate passed on screen
  `projects/5004109454348309607/screens/3de1ffbf59494fd1a342825c9bf12ff0`.
- Manual visual audit re-confirmed the Stitch design includes the required
  General controls and excludes unrelated Account / Connection / Permissions /
  Memory / Activity functionality from the General tab.
- Added `AgentGeneralSettingsPanel` and shared
  `settings_general_helpers.dart` for language and Quick Capture hotkey logic.
- Focused verification passed:
  `pixi run flutter test test/settings_agent_tabs_test.dart`.
- Final verification passed:
  `pixi run verify-changed`.
- Touched Dart files are below the 1000-line source limit.
