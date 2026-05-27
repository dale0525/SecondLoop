# Restore settings page migration

## Goal

Restore the settings that still only exist in the legacy `SettingsPage` into the
production app-shell settings surface (`AgentSettingsPage`) so users can manage
language, app-level reminder times, desktop behavior, support/about/update, and
related general preferences from the new Settings tab.

The user value is simple: the new Settings tab should be the complete settings
home, not a partial redesign that hides important controls behind older or
less-discoverable entry points.

## Confirmed Facts

- The production app shell Settings tab is wired through
  `lib/app/app_shell_default_pages_shared.dart` and returns
  `AgentSettingsPage`.
- `AgentSettingsPage` currently renders:
  - a top appearance section with `SettingsThemeModeRow`;
  - five tabs: Account, Connection, Permissions, Memory, Activity;
  - Account, Connection, Memory, and Activity panels delegated to existing
    settings pages/panels;
  - a very small Permissions panel with one informational row.
- The legacy `SettingsPage` still contains app-level controls that are missing
  from `AgentSettingsPage`:
  - language override / system language selection;
  - About page and update badge / update flow;
  - reopen welcome guide;
  - diagnostics;
  - review reminder in-app fallback toggle;
  - morning review time, day-end review time, weekly review time;
  - desktop start-with-system, silent startup, keep-running-in-background;
  - desktop Quick Capture hotkey editing;
  - debug reset rows in debug builds.
- The underlying persistence and flows already exist:
  - `locale_prefs.dart` for app language;
  - `ActionsSettingsStore` for review reminder times;
  - `ReviewReminderInAppFallbackPrefs` for in-app reminder fallback;
  - `DesktopBootPrefs` and `DesktopQuickCaptureHotkeyPrefs` for desktop app
    behavior;
  - `AboutPage`, `DiagnosticsPage`, and `WelcomePage` for support flows.
- Existing settings UI primitives are in `settings_ui.dart`, and project specs
  say new settings work should reuse `SettingsSection`, `SettingsRow`,
  `SettingsSwitchRow`, `SettingsPageShell`, and `SettingsThemeModeRow`.
- Existing Stitch / golden settings references use a dense operational layout:
  `Settings` heading, horizontal tabs, 1px bordered white surfaces, compact
  Inter-like typography, restrained blue active states, and domain tabs for
  Account / Connection / Permissions / Memory / Activity.
- A Stitch Settings `General` design artifact now exists in project
  `5004109454348309607`: screen
  `3de1ffbf59494fd1a342825c9bf12ff0`, titled
  `Settings: General (Final Production Refinement)`.
  This is the implementation reference, alongside the existing approved
  settings screenshots for desktop/mobile density.
- The user approved the recommended IA: migrated app-level controls should live
  in a new first `General` tab.
- The user explicitly requires a Stitch design artifact before implementation.
  The artifact must be suitable for pixel-level restoration, and the assistant
  manually visually audited the final artifact before coding:
  - no extra visible feature elements were introduced in the `General` tab;
  - no required migrated settings are missing;
  - layout, density, and styling match the existing settings design;
  - the mobile tab row is horizontally scrollable, so the screenshot crops
    later tabs at the right edge while the HTML still contains the complete tab
    inventory.
- Touched non-document Dart files must remain under 1000 lines.
- Verification must use `pixi`.

## Requirements

- Add the missing legacy settings to the new production settings surface without
  removing existing Account / Connection / Permissions / Memory / Activity
  responsibilities.
- Add a new first tab named `General` and put migrated app-level settings there.
- Before implementation starts, create or edit a Stitch Settings design artifact
  that shows the approved `General` tab and can be used as the visual reference
  for pixel-level native Flutter implementation.
- Before implementation starts, manually audit the Stitch artifact against the
  required settings inventory and record the result in task planning notes.
- Preserve existing persistence keys, behavior, navigation, dialogs, busy-state
  guards, platform capability gating, and test-facing keys wherever practical.
- Reuse existing settings primitives and shared helper logic instead of
  copy-pasting large chunks from `SettingsPage`.
- Keep language selection available with the same choices: system, English,
  Simplified Chinese.
- Keep theme mode selection available and functional.
- Keep About / updates discoverable from the new Settings tab, including the
  existing update badge signal.
- Keep review reminder settings available:
  in-app fallback, morning time, day-end time, weekly review time.
- Keep desktop-only settings gated by platform capabilities:
  start with system, silent startup, keep running in background, and Quick
  Capture hotkey.
- Keep support actions available:
  reopen welcome guide and diagnostics.
- Preserve cloud-session/web capability behavior where legacy settings were
  intentionally hidden or unsupported.
- Match the existing Stitch/golden settings visual language closely on desktop
  and mobile: tab density, row rhythm, surfaces, typography scale, icons, and
  no decorative gradients or marketing layout.
- Add widget tests that prove the migrated settings are present and functional
  in `AgentSettingsPage`.
- Update i18n strings only if the chosen IA requires new user-facing labels.

## Acceptance Criteria

- [ ] `AgentSettingsPage` exposes language selection, and selecting a language
      persists through `setLocaleOverride(...)`.
- [ ] `AgentSettingsPage` exposes About / update entry; when
      `UpdateBadgePrefs` has a latest tag, an update badge is visible on the new
      settings surface.
- [ ] `AgentSettingsPage` exposes review reminder in-app fallback and persists
      changes through `ReviewReminderInAppFallbackPrefs`.
- [ ] `AgentSettingsPage` exposes morning review, day-end review, and weekly
      review times, with the current stored times shown in the row trailing
      values.
- [ ] `AgentSettingsPage` exposes desktop boot settings only when
      `AppPlatformCapabilities.supportsDesktopBootSettings` is true and
      persists each toggle through `DesktopBootPrefs`.
- [ ] `AgentSettingsPage` exposes Quick Capture hotkey only when
      `supportsDesktopHotkey` is true and keeps the existing edit dialog path.
- [ ] Reopen welcome guide and diagnostics are reachable from the new settings
      surface using inherited-scope-safe navigation.
- [ ] Existing Account / Connection / Permissions / Memory / Activity tests keep
      passing, with updated expectations only where the new General IA changes
      tab ordering or shared settings placement.
- [ ] Focused widget tests cover the migrated settings on the new surface,
      including at least one persistence path and platform capability gating.
- [ ] Visual structure is checked against current settings goldens / Stitch
      references on desktop and mobile; rows do not overflow and the page keeps
      the existing operational style.
- [ ] A Stitch Settings `General` design artifact exists and has been manually
      audited before implementation starts.
- [ ] The manual audit confirms the Stitch design contains exactly the approved
      required controls: theme, language, in-app reminders, three reminder
      times, desktop boot settings, Quick Capture hotkey, About/update, reopen
      welcome guide, and diagnostics.
- [ ] The manual audit confirms the Stitch design excludes unrelated feature
      controls such as runtime mode, billing/security, memory controls,
      permission tables, activity timeline, media annotation, sync, reset/debug,
      or new product functionality from the `General` tab.
- [ ] No touched non-document Dart file exceeds 1000 lines after changes.
- [ ] `pixi run verify-changed` passes before the task is reported complete.

## Out Of Scope

- Replacing the app shell navigation model.
- Reworking subscription, billing, update download/install logic, cloud runtime
  mode, diagnostics data collection, or reminder scheduling semantics.
- Adding new reminder kinds or changing default reminder times.
- Recreating every historical Stitch settings screen. This task should restore
  missing settings into the new native Flutter surface.
- Redesigning the whole settings taxonomy beyond the minimum IA needed to make
  migrated settings discoverable.

## Open Questions

- None blocking planning. Implementation must still wait for the required
  Stitch artifact and manual visual audit.

## Notes

- Keep `prd.md` focused on requirements, constraints, and acceptance criteria.
- Lightweight tasks can remain PRD-only.
- For complex tasks, add `design.md` for technical design and `implement.md` for execution planning before `task.py start`.
