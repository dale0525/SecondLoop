import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:secondloop/features/welcome/welcome_page.dart';

import 'test_i18n.dart';

void main() {
  testWidgets('renders cards and footer actions', (tester) async {
    var skipped = false;
    var finished = false;

    await tester.pumpWidget(
      wrapWithI18n(
        MaterialApp(
          home: Scaffold(
            body: WelcomePage(
              statusLoader: (_) async => const WelcomeGuideStatus(
                aiReady: true,
                syncReady: false,
              ),
              onSkip: () => skipped = true,
              onFinish: () => finished = true,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('welcome_page')), findsOneWidget);
    expect(find.byKey(const ValueKey('welcome_card_ai')), findsOneWidget);
    expect(find.byKey(const ValueKey('welcome_card_sync')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('welcome_card_permissions')),
      findsOneWidget,
    );

    final skipFinder = find.byKey(const ValueKey('welcome_skip'));
    await tester.scrollUntilVisible(skipFinder, 220);
    await tester.pumpAndSettle();

    await tester.tap(skipFinder);
    await tester.pumpAndSettle();
    expect(skipped, isTrue);

    final finishFinder = find.byKey(const ValueKey('welcome_finish'));
    await tester.tap(finishFinder);
    await tester.pumpAndSettle();
    expect(finished, isTrue);
  });

  testWidgets('shows snackbar when permission settings open fails',
      (tester) async {
    await tester.pumpWidget(
      wrapWithI18n(
        MaterialApp(
          home: Scaffold(
            body: WelcomePage(
              statusLoader: (_) async =>
                  const WelcomeGuideStatus(aiReady: false, syncReady: false),
              onSkip: () {},
              onFinish: () {},
              externalUriLauncher: (_) async => false,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester
        .tap(find.byKey(const ValueKey('welcome_permission_microphone')));
    await tester.pump();

    expect(find.byType(SnackBar), findsOneWidget);
  });
}
