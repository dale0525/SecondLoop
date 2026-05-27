# Technical Design: Restore Settings Page Migration

## Architecture Boundary

The implementation should treat `AgentSettingsPage` as the production settings
home and `SettingsPage` as the legacy source of existing settings behavior.

Primary files:

- `lib/features/settings/agent_settings_page.dart`
- `lib/features/settings/agent_settings_models.dart`
- `lib/features/settings/settings_ui.dart`
- `lib/features/settings/settings_page.dart`
- `lib/features/settings/settings_page_build.dart`
- `lib/features/settings/settings_theme_mode_row.dart`

Supporting existing flows:

- `lib/i18n/locale_prefs.dart`
- `lib/features/actions/settings/actions_settings_store.dart`
- `lib/core/notifications/review_reminder_in_app_fallback_prefs.dart`
- `lib/core/desktop/desktop_boot_prefs.dart`
- `lib/core/desktop/desktop_quick_capture_hotkey_prefs.dart`
- `lib/features/settings/about_page.dart`
- `lib/features/settings/diagnostics_page.dart`
- `lib/features/welcome/welcome_page.dart`

## Proposed Information Architecture

Approved IA: add a first `General` tab before the existing domain tabs.

`General` owns app-level preferences:

- Appearance: theme mode and language.
- Reminders: in-app reminder fallback, morning review, day-end review, weekly
  review.
- Desktop: start with system, silent startup, keep running in background, Quick
  Capture hotkey.
- Support: About / updates, reopen welcome guide, diagnostics.

Existing tabs keep their current domain meaning:

- Account: profile, plan, billing, account security.
- Connection: runtime mode and connection health.
- Permissions: allowed assistant actions and approval boundaries.
- Memory: memory behavior and digest settings.
- Activity: transparency, diagnostics/activity-oriented details.

The alternative of distributing rows into existing tabs was rejected because it
would scatter language, desktop startup, updates, and reminder scheduling across
unrelated assistant/runtime tabs.

## Stitch Design Gate

Implementation must not start until there is a Stitch Settings design artifact
for the `General` tab.

The preferred approach is to edit or variant the existing Stitch
`Settings (Production HTML)` screen in project `5004109454348309607`, because
it already carries the correct settings density, typography, tab treatment, and
surface rhythm. A prior blank generation attempt timed out, so editing the
existing screen is lower risk than creating a separate design from scratch.

Manual visual audit checklist:

- Required controls present:
  - Theme.
  - Language.
  - In-app reminders.
  - Morning review.
  - Day-end review.
  - Weekly review.
  - Start with system.
  - Silent startup.
  - Keep running in background.
  - Quick Capture hotkey.
  - About SecondLoop / update indicator.
  - Reopen welcome guide.
  - Diagnostics.
- Required controls absent from `General`:
  - Runtime mode / connection setup.
  - Account billing/security/profile details.
  - Permission table.
  - Memory behavior controls.
  - Activity timeline.
  - Media annotation, sync, reset/debug, or unrelated new settings.
- Visual checks:
  - `General` is the first selected tab.
  - Existing Account / Connection / Permissions / Memory / Activity tabs remain
    visible and unchanged in meaning.
  - Section grouping is app-level: Appearance, Reminders, Desktop, Support.
  - Row spacing, border treatment, typography, blue active underline, and
    neutral operational palette match the existing Stitch settings screens.
  - No overflow or clipped trailing values on mobile-width layout.

Record the audit result in the planning artifacts before `task.py start`.

### Final Stitch Artifact And Manual Audit

Final artifact:

- Project: `5004109454348309607`
- Screen: `3de1ffbf59494fd1a342825c9bf12ff0`
- Title: `Settings: General (Final Production Refinement)`
- Device type: `MOBILE`
- Size: `780 x 3630`
- Local audit files:
  - `/tmp/stitch-settings-general-final.png`
  - `/tmp/stitch-settings-general-final.html`

Manual visual audit result: **passed for implementation**.

Required visible controls are present exactly once in the `General` tab:

- Theme.
- Language.
- In-app reminders.
- Morning review.
- Day-end review.
- Weekly review.
- Start with system.
- Silent startup.
- Keep running in background.
- Quick Capture hotkey.
- About SecondLoop with the update dot.
- Reopen welcome guide.
- Diagnostics.

Excluded controls are not present as `General` tab functionality:

- Runtime mode / connection setup.
- Account billing/security/profile details.
- Permission table.
- Memory behavior controls.
- Activity timeline.
- Media annotation.
- Sync.
- Reset/debug.
- Subscription upsells.
- Diagnostics export details beyond the Diagnostics entry row.

Visual audit notes:

- `General` is first and selected.
- Account, Connection, Permissions, Memory, and Activity remain present only as
  tabs in the HTML. On the mobile screenshot, the tab strip scrolls
  horizontally and the viewport crops later tabs at the right edge.
- Sections are grouped as Appearance, Reminders, Desktop, and Support.
- The refined artifact removed the visible extra bottom footnote/callout from
  the first Stitch version.
- Text separators were corrected to ASCII (`System / English`,
  `Sunday / 9:00 PM`) after a bad-glyph Stitch pass.
- The visible layout uses compact row rhythm, 1px bordered surfaces, neutral
  operational palette, and blue active state consistent with the existing
  settings references.
- No row text or trailing values visually overflow in the audited mobile
  screenshot.
- The top app bar and bottom navigation are treated as shell context, not
  additional `General` settings functionality.

## Component Design

Create reusable app-level settings sections rather than duplicating the legacy
page wholesale:

- A stateful `AgentSettingsPage` should load the same preferences currently
  loaded by `SettingsPage`.
- Extract small private widgets/helpers when `agent_settings_page.dart` starts
  to grow, and move substantial shared app-setting logic to a sibling file such
  as `agent_general_settings_page.dart` or `general_settings_panel.dart`.
- Prefer reusing existing private behavior from `SettingsPage` only after it is
  moved to a shared helper/widget with clear ownership. Avoid large copy-paste
  of dialogs or hotkey logic.
- Keep `SettingsThemeModeRow` as the source of truth for theme mode.
- Keep language selection behavior equivalent to legacy `SettingsPage`, using
  `setLocaleOverride(...)` and the existing generated i18n labels.
- Keep time selection through native `showTimePicker` and existing
  `ActionsSettingsStore` methods.
- Keep About, Diagnostics, and Welcome navigation using inherited-scope helpers
  (`pushPageWithInheritedScopes`) so scopes survive across nested pages.

## Visual Contract

Use the approved settings storyboard / golden language as the target:

- `Settings` title and compact horizontal tabs.
- Dense grouped surfaces with 1px borders and restrained row padding.
- `SettingsSection`, `SettingsRow`, and `SettingsSwitchRow` for list sections.
- Icons in rows where they help scanning, using Material iconography already in
  the app.
- Blue active tab / action accent, neutral slate text, semantic green/orange/red
  only for status/destructive/update signals.
- No decorative gradients, hero layout, nested cards, or marketing copy.

The new General tab should feel like it was part of the same Stitch pass as the
existing Account / Connection / Permissions / Memory / Activity settings
screens.

## State And Persistence Flow

Data flow for each migrated preference:

- SharedPreferences-backed source (`LocalePrefs`, `ActionsSettingsStore`,
  `ReviewReminderInAppFallbackPrefs`, `DesktopBootPrefs`,
  `DesktopQuickCaptureHotkeyPrefs`) loads into the owning settings state.
- The row displays the current value through local state or the existing
  `ValueNotifier`.
- User interaction opens an existing dialog or native picker.
- Persist via the existing domain helper.
- Reload or update local state after success.
- On failure, restore the previous state when optimistic updates are used and
  show a localized snackbar.

No new preference keys should be introduced for already existing settings.

## Compatibility

- Web/cloud-session capability rules must remain respected. Rows that the
  legacy settings hid for cloud session or unsupported platforms should remain
  hidden or disabled for the same reasons.
- Generated i18n should not be hand-edited; edit source JSON and run the
  project generation command only if new keys are necessary.
- Existing tests that target `SettingsPage` should keep passing unless they
  assert a legacy-only surface that is intentionally superseded.
- Existing `AgentSettingsPage` tab tests may need updates for a new `General`
  enum value and tab order.

## Testing Strategy

Focused widget coverage:

- General tab renders the migrated rows with default preference values.
- Language dialog persists a selected locale.
- Review reminder fallback switch persists to SharedPreferences.
- Reminder time rows show stored values; a full picker interaction can be
  covered if stable in widget tests, otherwise keep the display path and store
  methods covered separately.
- Desktop rows appear only when platform capabilities allow them.
- About update badge appears when `UpdateBadgePrefs` has a value.
- Existing domain tabs still render their owned content.

Visual checks:

- Run focused settings tests.
- Capture or inspect desktop and mobile settings surfaces after implementation
  and compare row density, tab rhythm, and overflow against current golden
  references.

## Rollback

The main rollback point is the new app-level settings panel. Existing legacy
settings behavior should remain intact during the migration, so rollback can
restore `AgentSettingsPage` to the previous five-tab layout while keeping
underlying preference helpers untouched.
