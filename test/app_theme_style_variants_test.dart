import 'package:flutter_test/flutter_test.dart';
import 'package:secondloop/app/theme.dart';
import 'package:secondloop/app/theme_palette_prefs.dart';
import 'package:secondloop/ui/sl_tokens.dart';

void main() {
  test('Theme styles change structural surfaces and radii', () {
    final studioLight = AppTheme.light(palette: AppThemePalette.studio);
    final oceanLight = AppTheme.light(palette: AppThemePalette.ocean);

    final studioTokens = studioLight.extension<SlTokens>()!;
    final oceanTokens = oceanLight.extension<SlTokens>()!;

    expect(
        oceanLight.colorScheme.primary, isNot(studioLight.colorScheme.primary));
    expect(
        oceanLight.colorScheme.surface, isNot(studioLight.colorScheme.surface));
    expect(oceanTokens.background, isNot(studioTokens.background));
    expect(oceanTokens.radiusLg, isNot(studioTokens.radiusLg));
  });

  test('Theme style affects dark-mode structural layers', () {
    final studioDark = AppTheme.dark(palette: AppThemePalette.studio);
    final forestDark = AppTheme.dark(palette: AppThemePalette.forest);

    final studioTokens = studioDark.extension<SlTokens>()!;
    final forestTokens = forestDark.extension<SlTokens>()!;

    expect(
        forestDark.colorScheme.surface, isNot(studioDark.colorScheme.surface));
    expect(
      forestDark.colorScheme.background,
      isNot(studioDark.colorScheme.background),
    );
    expect(forestTokens.surface2, isNot(studioTokens.surface2));
    expect(forestTokens.radiusMd, isNot(studioTokens.radiusMd));
  });
}
