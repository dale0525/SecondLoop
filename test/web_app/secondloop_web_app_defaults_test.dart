import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:secondloop/app/theme_mode_prefs.dart';
import 'package:secondloop/app/theme_palette_prefs.dart';
import 'package:secondloop/web_app/secondloop_web_app.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    AppThemeModePrefs.resetForTests();
    AppThemePalettePrefs.resetForTests();
  });

  testWidgets('SecondLoopWebApp defaults to system SecondLoop styling on web',
      (tester) async {
    await AppThemeModePrefs.ensureInitialized();
    await AppThemePalettePrefs.ensureInitialized();

    await tester.pumpWidget(
      SecondLoopWebApp(
        bootstrapLoader: () => Completer<WebAppBootstrapData>().future,
      ),
    );
    await tester.pump();

    final materialApp = tester.widget<MaterialApp>(find.byType(MaterialApp));

    expect(materialApp.themeMode, ThemeMode.system);
    expect(materialApp.darkTheme, isNotNull);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(AppThemeModePrefs.prefsKey), isNull);
    expect(
      AppThemePalettePrefs.value.value,
      AppThemePalette.studio,
    );
  });

  testWidgets('SecondLoopWebApp honors persisted theme mode on web',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      AppThemeModePrefs.prefsKey: 'dark',
    });
    AppThemeModePrefs.resetForTests();
    AppThemePalettePrefs.resetForTests();
    await AppThemeModePrefs.ensureInitialized();
    await AppThemePalettePrefs.ensureInitialized();

    await tester.pumpWidget(
      SecondLoopWebApp(
        bootstrapLoader: () => Completer<WebAppBootstrapData>().future,
      ),
    );
    await tester.pump();

    final materialApp = tester.widget<MaterialApp>(find.byType(MaterialApp));

    expect(materialApp.themeMode, ThemeMode.dark);
  });
}
