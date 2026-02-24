import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:secondloop/features/welcome/welcome_page.dart';
import 'package:secondloop/i18n/strings.g.dart';

import 'test_i18n.dart';

void main() {
  testWidgets('welcome page copy comes from i18n keys', (tester) async {
    await tester.pumpWidget(
      wrapWithI18n(
        MaterialApp(
          home: Scaffold(
            body: WelcomePage(
              statusLoader: (_) async =>
                  const WelcomeGuideStatus(aiReady: false, syncReady: false),
              onSkip: () {},
              onFinish: () {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text(LocaleSettings.currentLocale.build().welcomeGuide.title),
        findsOneWidget);
    expect(
        find.text(LocaleSettings.currentLocale.build().welcomeGuide.subtitle),
        findsOneWidget);
  });
}
