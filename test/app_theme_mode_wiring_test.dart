import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:secondloop/app/app.dart';
import 'package:secondloop/app/theme.dart';
import 'package:secondloop/app/theme_palette_prefs.dart';
import 'package:secondloop/app/theme_mode_prefs.dart';

import 'test_backend.dart';

Future<void> _pumpUntil(
  WidgetTester tester,
  bool Function() condition, {
  Duration step = const Duration(milliseconds: 32),
  int maxPumps = 120,
}) async {
  for (var i = 0; i < maxPumps; i += 1) {
    await tester.pump(step);
    if (condition()) return;
  }
  expect(condition(), isTrue);
}

void main() {
  testWidgets('SecondLoopApp uses theme mode and ignores legacy palette prefs',
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
    final prefs = await SharedPreferences.getInstance();
    expect(app.themeMode, ThemeMode.dark);
    expect(prefs.getString('app_theme_palette_v1'), isNull);
    expect(AppThemePalettePrefs.value.value, AppThemePalette.studio);
    expect(
      app.theme?.colorScheme.primary,
      AppTheme.light().colorScheme.primary,
    );
    expect(
      app.darkTheme?.colorScheme.primary,
      AppTheme.dark().colorScheme.primary,
    );
    final appSource = File('lib/app/app.dart').readAsStringSync();
    expect(appSource, isNot(contains('KnowledgeIndexGate(')));
  });

  testWidgets('SecondLoopApp loads persisted theme prefs without prewarming',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      'app_theme_mode_v1': 'dark',
      'welcome_guide_seen_v1': true,
    });
    AppThemeModePrefs.resetForTests();
    AppThemePalettePrefs.resetForTests();

    await tester.pumpWidget(SecondLoopApp(backend: TestAppBackend()));
    await _pumpUntil(tester, () {
      final apps = find.byType(MaterialApp).evaluate();
      if (apps.isEmpty) return false;
      return tester.widget<MaterialApp>(find.byType(MaterialApp)).themeMode ==
          ThemeMode.dark;
    });

    final app = tester.widget<MaterialApp>(find.byType(MaterialApp));
    expect(app.themeMode, ThemeMode.dark);
    expect(AppThemeModePrefs.value.value, ThemeMode.dark);
  });
}
