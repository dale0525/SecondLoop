import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:secondloop/app/app.dart';
import 'package:secondloop/app/theme_mode_prefs.dart';

import 'test_backend.dart';

void main() {
  testWidgets('SecondLoopApp uses AppThemeModePrefs for themeMode',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      'app_theme_mode_v1': 'dark',
    });
    AppThemeModePrefs.resetForTests();
    await AppThemeModePrefs.ensureInitialized();

    await tester.pumpWidget(SecondLoopApp(backend: TestAppBackend()));

    final app = tester.widget<MaterialApp>(find.byType(MaterialApp));
    expect(app.themeMode, ThemeMode.dark);
  });
}
