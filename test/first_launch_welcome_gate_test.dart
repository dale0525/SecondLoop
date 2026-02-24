import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:secondloop/features/welcome/first_launch_welcome_gate.dart';

import 'test_i18n.dart';

void main() {
  Future<void> pumpGate(WidgetTester tester) {
    return tester.pumpWidget(
      wrapWithI18n(
        const MaterialApp(
          home: FirstLaunchWelcomeGate(
            child: Scaffold(
              body: Center(child: Text('home')),
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('shows welcome page when not seen', (tester) async {
    SharedPreferences.setMockInitialValues({});

    await pumpGate(tester);
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('welcome_page')), findsOneWidget);
    expect(find.text('home'), findsNothing);
  });

  testWidgets('skip marks seen and enters home', (tester) async {
    SharedPreferences.setMockInitialValues({});

    await pumpGate(tester);
    await tester.pumpAndSettle();

    final skipFinder = find.byKey(const ValueKey('welcome_skip'));
    await tester.scrollUntilVisible(skipFinder, 220);
    await tester.pumpAndSettle();

    await tester.tap(skipFinder);
    await tester.pumpAndSettle();

    expect(find.text('home'), findsOneWidget);
    final prefs = await SharedPreferences.getInstance();
    expect(
      prefs.getBool(FirstLaunchWelcomeGate.seenPrefsKey),
      isTrue,
    );
  });

  testWidgets('does not show welcome when already seen', (tester) async {
    SharedPreferences.setMockInitialValues({
      FirstLaunchWelcomeGate.seenPrefsKey: true,
    });

    await pumpGate(tester);
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('welcome_page')), findsNothing);
    expect(find.text('home'), findsOneWidget);
  });
}
