import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:secondloop/app/theme_mode_prefs.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    AppThemeModePrefs.resetForTests();
  });

  test('AppThemeModePrefs loads from SharedPreferences', () async {
    SharedPreferences.setMockInitialValues({
      'app_theme_mode_v1': 'dark',
    });
    AppThemeModePrefs.resetForTests();

    await AppThemeModePrefs.ensureInitialized();

    expect(AppThemeModePrefs.value.value, ThemeMode.dark);
  });

  test('AppThemeModePrefs persists ThemeMode.system by clearing pref',
      () async {
    SharedPreferences.setMockInitialValues({
      'app_theme_mode_v1': 'dark',
    });
    AppThemeModePrefs.resetForTests();
    await AppThemeModePrefs.ensureInitialized();

    await AppThemeModePrefs.setThemeMode(ThemeMode.system);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('app_theme_mode_v1'), isNull);
    expect(AppThemeModePrefs.value.value, ThemeMode.system);
  });

  test('AppThemeModePrefs persists light/dark', () async {
    await AppThemeModePrefs.ensureInitialized();

    await AppThemeModePrefs.setThemeMode(ThemeMode.light);
    var prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('app_theme_mode_v1'), 'light');
    expect(AppThemeModePrefs.value.value, ThemeMode.light);

    await AppThemeModePrefs.setThemeMode(ThemeMode.dark);
    prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('app_theme_mode_v1'), 'dark');
    expect(AppThemeModePrefs.value.value, ThemeMode.dark);
  });
}
