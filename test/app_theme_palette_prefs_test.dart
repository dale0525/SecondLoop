import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:secondloop/app/theme_palette_prefs.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    AppThemePalettePrefs.resetForTests();
  });

  test('AppThemePalettePrefs clears legacy stored palettes on load', () async {
    SharedPreferences.setMockInitialValues({
      'app_theme_palette_v1': 'ocean',
    });
    AppThemePalettePrefs.resetForTests();

    await AppThemePalettePrefs.ensureInitialized();

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('app_theme_palette_v1'), isNull);
    expect(AppThemePalettePrefs.value.value, AppThemePalette.studio);
  });

  test('AppThemePalettePrefs persists default palette by clearing pref key',
      () async {
    SharedPreferences.setMockInitialValues({
      'app_theme_palette_v1': 'sunset',
    });
    AppThemePalettePrefs.resetForTests();
    await AppThemePalettePrefs.ensureInitialized();

    await AppThemePalettePrefs.setPalette(AppThemePalette.studio);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('app_theme_palette_v1'), isNull);
    expect(AppThemePalettePrefs.value.value, AppThemePalette.studio);
  });

  test('AppThemePalettePrefs normalizes non-default palettes to studio',
      () async {
    await AppThemePalettePrefs.ensureInitialized();

    await AppThemePalettePrefs.setPalette(AppThemePalette.forest);
    var prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('app_theme_palette_v1'), isNull);
    expect(AppThemePalettePrefs.value.value, AppThemePalette.studio);

    await AppThemePalettePrefs.setPalette(AppThemePalette.sunset);
    prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('app_theme_palette_v1'), isNull);
    expect(AppThemePalettePrefs.value.value, AppThemePalette.studio);

    await AppThemePalettePrefs.setPalette(AppThemePalette.monochrome);
    prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('app_theme_palette_v1'), isNull);
    expect(AppThemePalettePrefs.value.value, AppThemePalette.studio);
  });
}
