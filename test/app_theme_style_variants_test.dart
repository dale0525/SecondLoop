import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:secondloop/app/app_shell_style.dart';
import 'package:secondloop/app/theme.dart';
import 'package:secondloop/app/theme_palette_prefs.dart';
import 'package:secondloop/app/theme_specs.dart';
import 'package:secondloop/ui/sl_tokens.dart';

void main() {
  const legacyStudioColors = <Color>[
    Color.fromARGB(0xFF, 0x63, 0x66, 0xF1),
    Color.fromARGB(0xFF, 0xA7, 0x8B, 0xFA),
    Color.fromARGB(0xFF, 0x7C, 0x3A, 0xED),
    Color.fromARGB(0xFF, 0x4F, 0x46, 0xE5),
  ];

  test('Default light theme uses the SecondLoop shell palette', () {
    final theme = AppTheme.light();
    final tokens = theme.extension<SlTokens>()!;
    final spec = kAppThemeStyleSpecs[AppThemePalette.studio]!;

    expect(theme.colorScheme.primary, AppShellPalette.blue);
    expect(theme.colorScheme.background, AppShellPalette.soft);
    expect(theme.colorScheme.surface, AppShellPalette.panel);
    expect(theme.colorScheme.outlineVariant, AppShellPalette.line);
    expect(tokens.background, AppShellPalette.soft);
    expect(tokens.surface, AppShellPalette.panel);
    expect(tokens.border, AppShellPalette.line);
    expect(tokens.ring, AppShellPalette.blue);
    expect(spec.seed, AppShellPalette.blue);
    expect(spec.ring, AppShellPalette.blue);
    expect(legacyStudioColors.contains(theme.colorScheme.primary), isFalse);
    expect(legacyStudioColors.contains(theme.colorScheme.secondary), isFalse);
    expect(
      legacyStudioColors.contains(theme.colorScheme.primaryContainer),
      isFalse,
    );
    expect(
      legacyStudioColors.contains(theme.colorScheme.secondaryContainer),
      isFalse,
    );
  });

  test('Default dark theme uses a SecondLoop-derived dark palette', () {
    final theme = AppTheme.dark();
    final tokens = theme.extension<SlTokens>()!;

    expect(theme.colorScheme.primary, AppShellPalette.darkBlue);
    expect(theme.colorScheme.background, AppShellPalette.darkSoft);
    expect(theme.colorScheme.surface, AppShellPalette.darkPanel);
    expect(theme.colorScheme.outlineVariant, AppShellPalette.darkLine);
    expect(tokens.background, AppShellPalette.darkSoft);
    expect(tokens.surface, AppShellPalette.darkPanel);
    expect(tokens.surface2, AppShellPalette.darkSurface);
    expect(tokens.ring, AppShellPalette.darkBlue);
    expect(legacyStudioColors.contains(theme.colorScheme.primary), isFalse);
    expect(legacyStudioColors.contains(theme.colorScheme.secondary), isFalse);
    expect(
        legacyStudioColors.contains(theme.colorScheme.inversePrimary), isFalse);
  });

  test('Legacy palette arguments no longer alter the product theme', () {
    final studioLight = AppTheme.light();
    final studioDark = AppTheme.dark();

    for (final palette in AppThemePalette.values) {
      final light = AppTheme.light(palette: palette);
      final dark = AppTheme.dark(palette: palette);
      final lightTokens = light.extension<SlTokens>()!;
      final darkTokens = dark.extension<SlTokens>()!;

      expect(light.colorScheme.primary, studioLight.colorScheme.primary);
      expect(light.colorScheme.surface, studioLight.colorScheme.surface);
      expect(lightTokens.background,
          studioLight.extension<SlTokens>()!.background);
      expect(lightTokens.radiusLg, studioLight.extension<SlTokens>()!.radiusLg);
      expect(dark.colorScheme.primary, studioDark.colorScheme.primary);
      expect(dark.colorScheme.surface, studioDark.colorScheme.surface);
      expect(
          darkTokens.background, studioDark.extension<SlTokens>()!.background);
      expect(darkTokens.radiusMd, studioDark.extension<SlTokens>()!.radiusMd);
    }
  });
}
