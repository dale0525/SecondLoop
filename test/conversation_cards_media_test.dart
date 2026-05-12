import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:secondloop/features/conversation_cards/media_summary_card.dart';

import 'test_i18n.dart';

void main() {
  testWidgets('MediaSummaryCard switches isolated media tab bodies',
      (tester) async {
    await tester.pumpWidget(
      wrapWithI18n(
        MaterialApp(
          home: Scaffold(
            body: MediaSummaryCard(data: MediaSummaryData.demo()),
          ),
        ),
      ),
    );

    expect(find.text('passport-scan.pdf'), findsOneWidget);
    expect(find.text('meeting-audio.m4a'), findsOneWidget);
    expect(find.text('Summary'), findsOneWidget);
    expect(find.text('Transcript'), findsOneWidget);
    expect(find.text('Fields'), findsOneWidget);
    expect(find.text('Actions'), findsOneWidget);
    expect(find.text('Sources'), findsOneWidget);
    expect(
      find.text(
        'SecondLoop found identity-document metadata and a meeting transcript candidate.',
      ),
      findsOneWidget,
    );
    expect(find.text('Extracted fields'), findsNothing);

    await tester.tap(find.text('Fields'));
    await tester.pumpAndSettle();

    expect(find.text('Extracted fields'), findsOneWidget);
    expect(find.text('Expiry date'), findsOneWidget);
    expect(find.text('Source: passport-scan.pdf'), findsOneWidget);
    expect(find.text('Confidence 92%'), findsOneWidget);
    expect(find.text('Suggested review items'), findsNothing);

    await tester.tap(find.text('Actions'));
    await tester.pumpAndSettle();

    expect(find.text('Suggested review items'), findsOneWidget);
    expect(find.text('Create expiry reminder'), findsOneWidget);
    expect(find.text('Extracted fields'), findsNothing);
  });
}
