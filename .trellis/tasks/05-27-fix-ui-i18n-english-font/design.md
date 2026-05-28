# Technical Design: UI i18n and English Font Rendering

## Boundary

Primary implementation areas:

- `lib/app/theme.dart`
- `lib/web_app/web_app_theme.dart` if web-only typography needs the same fix
- `lib/i18n/*_en.i18n.json`
- `lib/i18n/*_zh_CN.i18n.json`
- `lib/i18n/strings.g.dart`
- Production UI files under `lib/features/agent_ui/`, `lib/features/settings/`,
  and related shell/shared UI surfaces that contain user-visible hard-coded
  copy from the recent Stitch migration

Out of scope:

- Translating runtime assistant/user content, memory records, API payload
  fields, analytics/debug IDs, semantic keys, protocol constants, fixture-only
  test copy, and developer-only tool output.
- Redesigning layouts beyond what is necessary to keep localized copy fitting.
- Adding new font assets or installing system fonts.

## Localization Approach

Use the existing slang namespace model. Prefer placing extracted copy into the
namespace that owns the feature surface:

- `chat` / `actions` for conversation and operating-shell cards.
- `settings` for production settings rows, labels, dialogs, and snackbars.
- `common` for repeated short labels such as generic action verbs only when the
  key is clearly shared by multiple features.
- Existing narrower namespaces such as `memory`, `attachments`, or `sync` when
  the surface already belongs there.

For large Stitch/workbench surfaces, use nested groups that mirror the widget
owner rather than adding a flat pile of keys. Keep key names semantic rather
than tied to exact visual placement.

When replacing literals:

- Use `final t = context.t.<namespace>...` in build methods with many strings.
- Use direct `context.t...` for one-off short replacements.
- Pass translated strings down to helper widgets when a helper lacks context or
  when doing so avoids making model classes depend on Flutter context.
- Leave raw strings that come from runtime records, generated summaries, test
  ids, URLs, file names, enums, and recognized technical labels.

## Typography Approach

The canonical Stitch HTML uses Inter throughout. The native app already bundles
Inter, so the lowest-risk fix is to make Inter the app UI primary font and keep
locale-specific fallback lists for scripts Inter does not cover.

Implementation direction:

- Set the main app theme primary font family to `Inter` across supported
  platforms.
- Keep emoji and locale fallback families in `fontFamilyFallback`.
- Put CJK fallback families ahead of generic platform/system fallbacks for
  zh-CN so Chinese text remains well shaped.
- Normalize default Material text theme letter spacing to `0` so English does
  not inherit Material's label/title tracking or web-theme negative tracking.
- Keep feature-specific typography intact only when it already explicitly
  matches local design intent and does not create the reported abnormal spacing.
- If the web app theme is still used for production app surfaces, replace Sora
  heading usage and negative spacing with Inter/zero spacing for consistency
  with Stitch.

## Compatibility

- Existing locale preference storage remains unchanged.
- Existing generated i18n API style remains unchanged.
- Font assets are already declared in `pubspec.yaml`; no asset manifest change
  is expected.
- Runtime cards must keep fail-closed labels truthful and must not translate
  machine evidence into claims that are not backed by runtime fields.

## Verification

Verification should combine static scanning with tests:

- Run the existing slang analyzer.
- Add or update a focused typography test for `AppTheme.light(locale: en)` and
  `AppTheme.light(locale: zh_CN)`.
- Run targeted widget/unit tests for surfaces that receive many copy changes.
- Run `pixi run verify-changed` as the final changed-file gate.

## Rollback

Rollback is straightforward:

- Revert the i18n JSON/generated file changes.
- Revert string accessor replacements in touched UI files.
- Revert the font/theme changes in `lib/app/theme.dart` and any web theme
  adjustments.

Because generated i18n output is derived from JSON, avoid manual edits to
`strings.g.dart` except through the project generation command.
