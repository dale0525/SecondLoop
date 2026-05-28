# Implementation Plan: UI i18n and English Font Rendering

## Checklist

1. Run the existing i18n analyzer and inspect its output.
2. Build a focused hard-coded-copy inventory for production Dart UI files,
   prioritizing recent Stitch/workbench/settings files.
3. Read `trellis-before-dev` and the relevant frontend specs before code edits.
4. Add or update i18n JSON keys for extracted production copy.
5. Replace user-facing literals in targeted UI files with generated accessors.
6. Update the app typography baseline to Inter with zero default letter spacing,
   preserving locale fallbacks.
7. Regenerate i18n output with `pixi run i18n-refresh` or the matching project
   task.
8. Add focused tests for typography and any high-risk i18n replacements.
9. Run targeted tests and `pixi run i18n-analyze`.
10. Run `pixi run verify-changed`.
11. Update specs only if the work discovers a reusable new rule.

## Validation Commands

- `pixi run i18n-analyze`
- `pixi run i18n-refresh`
- `pixi run flutter test <targeted tests>`
- `pixi run verify-changed`

## Risky Files

- `lib/i18n/strings.g.dart` is generated and should not be hand-edited.
- Large `lib/features/agent_ui/*storyboard*.dart` files are close to the
  1000-line limit; avoid increasing them materially and refactor only if a
  touched file crosses the limit.
- Theme changes affect the whole app; keep the change minimal and test the
  locale-specific fallback contract.

## Rollback Points

- After typography changes, revert `lib/app/theme.dart` independently if the
  localized copy work is sound but the font change causes failures.
- After i18n JSON additions, rerun generation immediately so generated output
  does not drift from source files.
