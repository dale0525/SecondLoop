# Fix UI i18n and English font rendering

## Goal

After the recent Stitch-driven UI migration, restore localization discipline
and English typography quality across user-visible app surfaces.

The app should not show newly introduced hard-coded English copy when the user
selects another language, and selecting English should render with normal
professional spacing that follows the approved Stitch screens as closely as the
native Flutter app allows.

## Confirmed Facts

- The app uses `slang` with namespaced JSON files in `lib/i18n/` and generated
  accessors in `lib/i18n/strings.g.dart`.
- Frontend guidelines require user-facing copy in app surfaces to prefer
  generated i18n access through `context.t`.
- The approved Stitch export under
  `docs/stitch-export/secondloop-operating-system/` declares Inter as the
  font family for canonical screens.
- The repository already bundles `assets/fonts/inter/Inter-Variable.ttf` and
  `assets/fonts/sora/Sora-Variable.ttf`.
- The main app theme currently chooses platform system fonts as the primary
  font family and only uses bundled fonts in specific storyboard/web surfaces.
- The web theme applies Sora to heading text with negative letter spacing,
  while the canonical Stitch HTML uses Inter for body, labels, code, and
  headings.
- Recent Stitch and workbench files under `lib/features/agent_ui/`,
  `lib/features/settings/`, and related shell/settings surfaces contain many
  user-facing `Text(...)`, tooltip, label, snackbar, dialog, and placeholder
  strings.

## Requirements

1. Replace user-visible hard-coded copy introduced by the Stitch migration with
   generated i18n keys and `context.t` accessors wherever the text is part of a
   production app surface.
2. Preserve runtime-provided content, test fixture literals, route/debug
   identifiers, semantic keys, enum names, code/protocol labels, file names,
   URLs, IDs, and other non-localizable machine text.
3. Add English and Simplified Chinese translations for newly extracted strings.
4. Regenerate `lib/i18n/strings.g.dart` through the project i18n flow.
5. Align the app's English typography baseline with the current Stitch source
   of truth by preferring bundled Inter for app UI text and avoiding negative
   letter spacing in normal app text.
6. Keep CJK and other locale fallback behavior intact so Chinese rendering does
   not regress when the language is zh-CN.
7. Avoid broad visual refactors unrelated to localization or typography.
8. Keep any touched Dart source under the 1000-line project limit.

## Acceptance Criteria

- [ ] A repository scan of production Dart UI files no longer reports obvious
      newly migrated user-facing `Text('...')` / label / tooltip literals in
      the targeted Stitch and settings surfaces, except documented
      non-localizable or runtime-provided values.
- [ ] New i18n keys exist in both `*_en.i18n.json` and
      `*_zh_CN.i18n.json`, and generated `strings.g.dart` is refreshed.
- [ ] `pixi run i18n-analyze` passes.
- [ ] Targeted Flutter tests covering affected settings/agent UI surfaces pass.
- [ ] A typography-focused test proves the English app theme uses Inter with
      normal letter spacing, while zh-CN keeps locale-aware fallback fonts.
- [ ] `pixi run verify-changed` passes or any failure is clearly unrelated and
      documented.
- [ ] The final diff does not add non-product copy, visible instructional
      scaffolding, or unapproved theme selectors.

## Notes

- This is a complex task because it touches generated i18n, multiple UI
  surfaces, typography/theme code, and broad verification.
