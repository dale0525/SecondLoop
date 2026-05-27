# Implementation Plan: Unify SecondLoop App Visual System

## Preconditions

- Review final `prd.md` / `design.md` with the user.
- Only then run `python3 ./.trellis/scripts/task.py start 05-27-unify-app-visual-system`.

## Ordered Checklist

- [ ] Record baseline visual audit.
  - Search for old purple constants and semantic theme usage:
    `rg -n "6366F1|A78BFA|7C3AED|4F46E5|purple|indigo|violet" lib test`.
  - Search for broad theme-derived accent usage:
    `rg -n "scheme\\.primary|colorScheme\\.primary|primaryContainer|secondaryContainer|tokens\\.ring" lib/app lib/ui lib/features -g'*.dart'`.
  - Classify local themes as product baseline, intentional local system, or
    legacy residue.

- [ ] Add failing/locking tests for the default palette.
  - Assert `AppTheme.light().colorScheme.primary` is `AppShellPalette.blue`.
  - Assert `AppTheme.dark().colorScheme.primary` is a contrast-safe
    SecondLoop blue and not legacy purple.
  - Assert default studio ring is `AppShellPalette.blue`.
  - Assert default studio surfaces align with `AppShellPalette.soft/panel/line`.
  - Assert legacy purple constants do not appear in default theme specs.

- [ ] Remove user-facing palette selection while preserving theme mode.
  - Hide/remove `settings_theme_palette` row.
  - Keep the existing light/dark/system row and dialog.
  - Normalize or ignore `app_theme_palette_v1` so saved `forest/ocean/sunset`
    no longer changes the app.
  - Update `app_theme_palette_prefs_test.dart` or replace it with a migration
    test proving legacy palette prefs are ignored/cleared.

- [ ] Update app-level theme tokens.
  - Change default studio values in `theme.dart`.
  - Change `kAppThemeStyleSpecs[AppThemePalette.studio]` in
    `theme_specs.dart`.
  - Update both light and dark schemes.
  - Keep `SlTokens._fallback` aligned with the product palette.
  - Re-run focused theme tests.

- [ ] Audit and adjust shared primitives.
  - `SlBackground`
  - `SlButton`
  - `SlFocusRing`
  - `SlMarkdownStyle`
  - `SettingsStatusBadge`
  - `SettingsInlineMessage`
  - Add tests where behavior is not already covered.

- [ ] Reassess local visual wrappers.
  - Remove or reduce `CloudAccountVisualTheme` if global tokens now solve the
    leakage.
  - Keep auth-specific emphasis only when needed for product hierarchy.
  - Audit `WelcomePage`, `SelfManagedSetupPage`, and `AgentConversationPage`
    without flattening intentional local systems.

- [ ] Replace hard-coded legacy purple.
  - Handle `agent_memory_projects_storyboard.dart` purple accents.
  - Search again for old constants after replacement.
  - Document any intentionally retained non-shell accents.

- [ ] Update user-facing palette labels/settings copy.
  - Edit source i18n JSON files, not generated `strings.g.dart` by hand.
  - Run the project's i18n generation/refresh task when needed.
  - Remove visible palette/style copy from Settings if no longer used.

- [ ] Run focused verification.
  - Theme tests.
  - Welcome tests.
  - Cloud account tests.
  - Settings shell tests.
  - Representative agent/workbench tests.
  - Dark-mode widget/visual checks for Settings, cloud account, welcome,
    self-managed setup, common dialogs/sheets, and representative workbench.

- [ ] Run final verification.
  - `pixi run dart format "<changed paths>"`
  - `pixi run flutter analyze "<changed paths>"`
  - `pixi run verify-changed`
  - `git status --short --untracked-files=all`
  - `wc -l <touched Dart files>`

## Risky Files / Rollback Points

- `lib/app/theme.dart`: root theme behavior; rollback reverts most visual
  behavior.
- `lib/app/theme_specs.dart`: persisted default palette visual meaning.
- `lib/ui/*`: changes fan out across the app.
- `lib/features/settings/cloud_account_visual_theme.dart`: may become redundant
  after root palette changes, but removing it too early could regress login.
- `lib/i18n/*`: only touch if palette labels change.

## Review Gates

- Gate 1: User approves final PRD/design/implement before `task.py start`.
- Gate 2: Focused visual/manual QA on the most exposed light and dark surfaces
  before final verification.
- Gate 3: Final verification passes before reporting implementation complete.
