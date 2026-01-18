import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:secondloop/i18n/locale_prefs.dart';
import 'package:secondloop/i18n/strings.g.dart';

import 'test_i18n.dart';

void main() {
  testWidgets('Locale override uses persisted setting', (tester) async {
    SharedPreferences.setMockInitialValues({
      kAppLocaleOverridePrefsKey: 'en',
    });
    tester.binding.platformDispatcher.localeTestValue =
        const Locale('zh', 'CN');
    addTearDown(tester.binding.platformDispatcher.clearLocaleTestValue);

    await AppLocaleBootstrap.ensureInitialized();

    await tester.pumpWidget(
      wrapWithI18n(
        MaterialApp(
          home: Builder(
            builder: (context) => Text(context.t.app.tabs.settings),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Settings'), findsOneWidget);
  });

  testWidgets('No locale override follows device locale', (tester) async {
    SharedPreferences.setMockInitialValues({});
    tester.binding.platformDispatcher.localeTestValue =
        const Locale('zh', 'CN');
    addTearDown(tester.binding.platformDispatcher.clearLocaleTestValue);

    await AppLocaleBootstrap.ensureInitialized();

    await tester.pumpWidget(
      wrapWithI18n(
        MaterialApp(
          home: Builder(
            builder: (context) => Text(context.t.app.tabs.settings),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('设置'), findsOneWidget);
  });
}
