# Technical Design: Unify SecondLoop App Visual System

## Architecture Boundary

The migration should happen at the visual-system boundary first:

- `lib/app/theme.dart`
- `lib/app/theme_specs.dart`
- `lib/app/app_shell_style.dart`
- `lib/ui/sl_tokens.dart`
- `lib/ui/sl_background.dart`
- `lib/ui/sl_button.dart`
- `lib/ui/sl_surface.dart`
- `lib/ui/sl_focus_ring.dart`
- `lib/features/settings/settings_ui.dart`

Feature pages should only receive local edits when they are either:

- relying on old global purple through semantic Material colors;
- carrying hard-coded legacy purple;
- using a local theme that conflicts with the new product baseline; or
- covered by high-traffic visual QA flows.

This keeps the task from becoming an unbounded page rewrite.

## Proposed Visual Contract

Default product palette:

- Primary action/link/focus: `AppShellPalette.blue` (`0xFF0B5CF6`).
- Primary text / filled button emphasis: `AppShellPalette.ink`
  (`0xFF101936`) where the UI needs a grounded operational action.
- Muted text/icons: `AppShellPalette.muted`.
- Borders/dividers: `AppShellPalette.line`.
- Main panels: `AppShellPalette.panel`.
- Page and low-emphasis surfaces: `AppShellPalette.soft`.
- Selected/active backgrounds: `AppShellPalette.selected`.

The app should expose one SecondLoop product palette. The user-facing Settings
surface should keep only the appearance mode selector: follow system, light, or
dark.

The Stitch evidence is strongest for light mode. Exported HTML includes
`darkMode: "class"` and `dark:*` Tailwind utilities, but the approved
screenshots are light-mode artifacts. Treat dark mode as a native SecondLoop
derivative of the light design, not as a pixel-copy from Stitch. Dark mode is
in scope for this task and must be good enough to ship as part of the unified
visual system.

## Theme Changes

Update the default `studio` branch in `AppTheme` and `AppThemeStyleSpec` so the
default `ColorScheme` and `SlTokens` are blue-gray/ink instead of purple:

- Replace `_primary`, `_accent`, studio light/dark `primary`, `secondary`,
  containers, outline, inverse primary, and ring values.
- Align `kAppThemeStyleSpecs[AppThemePalette.studio]` with
  `AppShellPalette`.
- Remove non-studio palette selection from user-facing Settings.
- Make app theme construction ignore any persisted non-default palette after
  migration, or clear/normalize the legacy preference during startup.
- Ensure `SlTokens._fallback` remains consistent with the new default.

## Dark Mode Direction

Dark mode should preserve the same information hierarchy as light mode:

- Page background: near-black blue-gray, not purple-black.
- Panels/cards: slightly elevated dark navy/slate surfaces.
- Text: high-contrast off-white primary text and muted blue-gray secondary
  text.
- Action/focus accent: SecondLoop blue, tuned for contrast on dark surfaces.
- Borders/dividers: low-chroma blue-gray.
- Semantic colors: keep error/warning/success recognizable without turning
  broad surfaces into saturated color blocks.

Because Stitch does not provide approved dark screenshots, implementation must
include actual dark-mode visual QA rather than assuming the light token mapping
is sufficient. The minimum dark-mode surface set is:

- Settings root and one representative Settings subpage.
- SecondLoop Pro login / cloud account.
- Welcome/onboarding.
- Self-managed setup.
- One common dialog or sheet.
- One representative Agent/workbench screen.

Any dark-mode issue found in those surfaces that comes from shared tokens,
shared primitives, or old purple residue is in scope. Deep per-feature layout
redesign remains out of scope unless necessary for readability or contrast.

## Shared Primitive Changes

Audit the primitives that amplify theme colors:

- `SlBackground`: dark-mode radial gradients should not reintroduce purple from
  secondary.
- `SlButton`: overlay color should come from the new primary or a documented
  semantic override.
- `SlFocusRing`: token ring should be blue.
- `SlMarkdownStyle`: default links, quote borders, highlights, and code block
  backgrounds should use the new palette.
- `SettingsStatusBadge` / `SettingsInlineMessage`: success/info/warning/error
  tones should use semantic colors without reading as purple.

## Local Theme Treatment

Local themes should be classified before editing:

- `WelcomePage`: currently forces a light theme using selected app palette.
  It should either naturally inherit the new studio palette or keep a small
  light wrapper only for onboarding readability.
- `SelfManagedSetupPage`: uses `_SetupColors`; preserve domain-specific setup
  styling unless it conflicts with the new shell language.
- `AgentConversationPage`: intentionally owns an operating-workbench theme
  seeded from `AppShellPalette.blue`; audit but do not flatten into generic
  Settings styling.
- `CloudAccountVisualTheme`: after the global fix, reassess whether this local
  wrapper can be removed or reduced to auth-specific button emphasis only.
- `agent_memory_projects_storyboard.dart`: replace hard-coded purple unless it
  is confirmed as an intentional storyboard accent.

## Compatibility Notes

- Existing saved `app_theme_palette_v1` values should no longer alter visuals.
  Prefer normalizing to the single product palette and removing the user-facing
  palette row.
- `AppThemeModePrefs` and `app_theme_mode_v1` must remain compatible.
- Palette Settings UI copy should be removed from visible flows; source i18n
  cleanup can be included when safe.
- Generated i18n (`lib/i18n/strings.g.dart`) must be updated only through the
  project's i18n flow if user-facing palette labels change.

## Testing Strategy

Add or update tests for:

- default studio colors in `AppTheme.light()` and `AppTheme.dark()`;
- `SlTokens.of(context)` default ring/surfaces;
- legacy palette preference normalization / ignored behavior;
- light, dark, and system theme mode selection still working;
- welcome page and cloud account visual palette expectations;
- a representative agent/workbench surface that should stay on the new shell
  palette;
- color-regression search or unit expectations proving old purple constants are
  gone from default theme files, except documented intentional locations.

## Rollback Strategy

The safest rollback is token-level:

- Revert `theme.dart`, `theme_specs.dart`, and shared primitive changes to the
  previous palette values.
- Leave page behavior files untouched wherever possible.
- Avoid broad page refactors in the same changeset unless the visual audit
  proves they are necessary.
