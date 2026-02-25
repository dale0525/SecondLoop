import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:secondloop/features/welcome/first_launch_welcome_gate.dart';
import 'package:secondloop/features/welcome/welcome_page.dart';

import 'test_i18n.dart';

void main() {
  Future<void> pumpGate(WidgetTester tester) async {
    await tester.pumpWidget(
      wrapWithI18n(
        const MaterialApp(
          home: FirstLaunchWelcomeGate(
            child: Scaffold(
              body: Center(child: Text('app shell child')),
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('shows welcome when first launch flag is missing',
      (tester) async {
    SharedPreferences.setMockInitialValues({});

    await pumpGate(tester);
    await tester.pumpAndSettle();

    expect(find.byType(WelcomePage), findsOneWidget);
    expect(find.text('app shell child'), findsNothing);
  });

  testWidgets('shows child when first launch flag is already seen',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      FirstLaunchWelcomeGate.seenPrefsKey: true,
    });

    await pumpGate(tester);
    await tester.pumpAndSettle();

    expect(find.byType(WelcomePage), findsNothing);
    expect(find.text('app shell child'), findsOneWidget);
  });

  testWidgets('skip writes seen flag and exits welcome page', (tester) async {
    SharedPreferences.setMockInitialValues({});

    await pumpGate(tester);
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('welcome_guide_skip')));
    await tester.pumpAndSettle();

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool(FirstLaunchWelcomeGate.seenPrefsKey), isTrue);
    expect(find.byType(WelcomePage), findsNothing);
    expect(find.text('app shell child'), findsOneWidget);
  });

  testWidgets('finish writes seen flag and exits welcome page', (tester) async {
    SharedPreferences.setMockInitialValues({});

    await pumpGate(tester);
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('welcome_guide_finish')));
    await tester.pumpAndSettle();

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool(FirstLaunchWelcomeGate.seenPrefsKey), isTrue);
    expect(find.byType(WelcomePage), findsNothing);
    expect(find.text('app shell child'), findsOneWidget);
  });
}
