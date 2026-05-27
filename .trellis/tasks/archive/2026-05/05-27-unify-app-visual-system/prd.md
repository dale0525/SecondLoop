# Unify SecondLoop app visual system

## Goal

Make the whole SecondLoop app feel like one coherent product surface by moving
the default visual system away from the legacy studio indigo/violet palette and
onto the current SecondLoop shell language: quiet, operational, light blue-gray
surfaces, deep ink text, restrained blue action accents, and compact reusable
controls.

The immediate user pain is that even after polishing the SecondLoop Pro login
page, other corners of the app may still inherit old purple styling from global
theme defaults. The value of this task is to fix the root tokens and shared UI
contracts so new and existing pages do not need one-off visual patches.

## Confirmed Facts

- `lib/app/theme.dart` still defines the default studio palette with
  `0xFF6366F1` indigo, `0xFFA78BFA` violet, `0xFF7C3AED`, purple containers,
  and indigo inverse primary colors.
- `lib/app/theme_specs.dart` sets `AppThemePalette.studio` to an indigo seed
  and violet ring, so default `SlTokens.ring`, focus borders, navigation
  indicators, button overlays, markdown styling, settings badges, and many
  feature cards can still inherit old purple tones.
- `lib/app/app_shell_style.dart` already defines the newer shell palette:
  `AppShellPalette.blue`, `ink`, `muted`, `line`, `panel`, `soft`, and
  `selected`.
- The current login-page polish added `CloudAccountVisualTheme` as a local
  override because the global default still leaked purple into auth controls.
  That is a short-term fix, not the desired long-term architecture.
- Existing docs under `docs/superpowers/specs/2026-05-21-settings-ui-unification-design.md`
  already unified Settings and the welcome guide around shared Settings UI
  primitives, but explicitly excluded replacing the app-wide theme or changing
  palette behavior.
- The app currently has user-selectable palettes in `AppThemePalette`:
  `studio`, `forest`, `ocean`, `sunset`, and `monochrome`. The user decision
  for this task is to remove this palette choice and keep a single SecondLoop
  product palette.
- The app also has `AppThemeModePrefs`, which persists `ThemeMode.system`,
  `ThemeMode.light`, and `ThemeMode.dark`. The user decision is to keep this
  light/dark/system appearance choice.
- The local Stitch export uses approved light screenshots. The exported HTML
  includes Tailwind `darkMode: "class"` and some `dark:*` utility classes, but
  the screens are rooted as `html class="light"` and the docs/QA evidence do
  not define an approved dark-mode visual language.
- The user decision is to include dark mode in this same task as a first-class
  derived SecondLoop visual system, not defer it to follow-up work.
- Some visual areas intentionally own stronger local themes, including
  `AgentConversationPage`, `WelcomePage`, `SelfManagedSetupPage`, and operating
  system cards. These should be audited before being flattened into the global
  palette.
- A direct color search finds remaining hard-coded purple in
  `agent_memory_projects_storyboard.dart`, plus the global theme files.

## Requirements

- Replace the default SecondLoop visual baseline with the current shell
  language rather than legacy purple/indigo.
- Keep app behavior, navigation, data flow, persistence, and feature state
  machines unchanged.
- Prefer root-token and shared primitive fixes over page-by-page color
  overrides.
- Audit all app-level surfaces that use `Theme.of(context).colorScheme`,
  `SlTokens`, `SlBackground`, `SlSurface`, `SlButton`, `Settings*` primitives,
  and default Material controls.
- Preserve intentional local design systems unless they are explicitly
  classified as legacy or inconsistent.
- Keep existing stable `ValueKey`s and test-facing widget structure unless a
  test is purely asserting obsolete implementation detail.
- Remove or hide the palette/style selector from Settings while preserving the
  light/dark/system selector.
- Existing saved palette preferences must not keep affecting the app after this
  migration.
- Update copy/i18n for the removed palette/style setting.
- Treat dark mode as an in-scope product-quality deliverable: it should be
  coherent, usable, and free of the old purple studio palette on the most
  exposed app surfaces.
- Add regression coverage proving the default palette no longer exposes purple
  as the primary/ring/default container identity.
- No touched non-document Dart file may exceed 1000 lines.
- Use `pixi` commands for formatting, tests, and verification.

## Acceptance Criteria

- [ ] The default `AppThemePalette.studio` no longer uses indigo/violet as its
      seed, ring, primary, secondary, primary container, secondary container, or
      inverse primary identity.
- [ ] Shared controls using default app theme (`SlButton`, `SlSurface`,
      `SlBackground`, input fields, navigation, progress indicators, Settings
      badges/messages, markdown defaults) render with the SecondLoop shell
      palette or an explicitly documented semantic color.
- [ ] The palette/style selector is removed or hidden from Settings, while the
      light/dark/system selector remains available and functional.
- [ ] Existing saved non-default palette preferences no longer alter the app's
      visual system after the migration.
- [ ] The dark theme uses a cohesive SecondLoop-derived dark palette rather
      than the old purple studio palette.
- [ ] Dark mode is manually/visually checked on the primary exposed surfaces:
      Settings, welcome/onboarding, cloud account, self-managed setup, common
      dialogs, and representative agent/workbench screens.
- [ ] Login/auth pages no longer require broad local color overrides solely to
      avoid global purple leakage.
- [ ] Settings, welcome/onboarding, cloud account, self-managed setup, common
      dialogs, attachment/review surfaces, and agent workbench are visually
      audited against the new baseline.
- [ ] Any remaining purple or saturated non-shell accent is documented as
      intentional, domain-specific, and not inherited from the old studio
      default.
- [ ] Focused widget tests cover the global default palette and at least the
      most exposed flows: welcome, cloud account, settings shell, and one
      agent/workbench surface.
- [ ] `pixi run verify-changed` passes before implementation is reported done.

## Out Of Scope

- Rewriting feature behavior, cloud auth, billing, runtime deployment, sync, AI
  routing, media processing, or storage logic.
- Replacing the entire Flutter component hierarchy or introducing a second
  design framework.
- Redesigning product copy beyond removing/updating palette/style labels.
- Pixel-perfect recreation of every historical Stitch screen. Stitch output can
  inform visual direction, but the implementation should use native Flutter
  primitives and existing app components.

## Open Questions

- None blocking planning.

## Notes

- Keep `prd.md` focused on requirements, constraints, and acceptance criteria.
- Lightweight tasks can remain PRD-only.
- For complex tasks, add `design.md` for technical design and `implement.md` for execution planning before `task.py start`.
