import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:secondloop/features/conversation_cards/daily_brief_card.dart';

import 'test_i18n.dart';

void main() {
  testWidgets('DailyBriefCard shows brief sections and birthday candidates',
      (tester) async {
    await tester.pumpWidget(
      wrapWithI18n(
        MaterialApp(
          home: Scaffold(
            body: DailyBriefCard(data: DailyBriefData.demo()),
          ),
        ),
      ),
    );

    expect(find.text('Top priorities'), findsOneWidget);
    expect(find.text('Calendar windows'), findsOneWidget);
    expect(find.text('Reminders'), findsOneWidget);
    expect(find.text('Commitments owed'), findsOneWidget);
    expect(find.text('Pending reviews'), findsOneWidget);
    expect(find.text('Memory candidate: child birthday'), findsOneWidget);
    expect(
      find.text('Recurring reminder candidate: buy gift before birthday'),
      findsOneWidget,
    );
  });
}
