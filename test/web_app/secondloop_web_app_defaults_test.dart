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

  testWidgets('SecondLoopWebApp defaults to light monochrome styling on web',
      (tester) async {
    await tester.pumpWidget(
      SecondLoopWebApp(
        bootstrapLoader: () => Completer<WebAppBootstrapData>().future,
      ),
    );
    await tester.pump();

    final materialApp = tester.widget<MaterialApp>(find.byType(MaterialApp));

    expect(materialApp.themeMode, ThemeMode.light);
    expect(
      AppThemePalettePrefs.value.value,
      AppThemePalette.monochrome,
    );
  });
}
