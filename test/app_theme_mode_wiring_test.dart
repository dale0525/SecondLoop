import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:secondloop/app/app.dart';
import 'package:secondloop/app/theme.dart';
import 'package:secondloop/app/theme_palette_prefs.dart';
import 'package:secondloop/app/theme_mode_prefs.dart';

import 'test_backend.dart';

void main() {
  testWidgets('SecondLoopApp uses theme prefs for mode and palette',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      'app_theme_mode_v1': 'dark',
      'app_theme_palette_v1': 'ocean',
      'welcome_guide_seen_v1': true,
    });
    AppThemeModePrefs.resetForTests();
    AppThemePalettePrefs.resetForTests();
    await AppThemeModePrefs.ensureInitialized();
    await AppThemePalettePrefs.ensureInitialized();

    await tester.pumpWidget(SecondLoopApp(backend: TestAppBackend()));
    await tester.pumpAndSettle();

    final app = tester.widget<MaterialApp>(find.byType(MaterialApp));
    expect(app.themeMode, ThemeMode.dark);
    expect(
      app.theme?.colorScheme.primary,
      AppTheme.light(palette: AppThemePalette.ocean).colorScheme.primary,
    );
    expect(
      app.darkTheme?.colorScheme.primary,
      AppTheme.dark(palette: AppThemePalette.ocean).colorScheme.primary,
    );
    final appSource = File('lib/app/app.dart').readAsStringSync();
    expect(appSource, isNot(contains('KnowledgeIndexGate(')));
  });
}
