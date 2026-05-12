import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:secondloop/features/conversation_cards/calendar_email_card.dart';

import 'test_i18n.dart';

void main() {
  testWidgets('CalendarEmailCard shows safe calendar read and gated sends',
      (tester) async {
    await tester.pumpWidget(
      wrapWithI18n(
        MaterialApp(
          home: Scaffold(
            body: CalendarEmailCard(data: CalendarEmailData.demo()),
          ),
        ),
      ),
    );

    expect(find.text('Calendar read is safe'), findsOneWidget);
    expect(find.text('Invite requires approval'), findsOneWidget);
    expect(find.text('Passport renewal prep'), findsOneWidget);
    expect(find.text('Save draft'), findsOneWidget);
    expect(find.text('Draft: travel checklist follow-up'), findsOneWidget);
    expect(find.text('Email not connected'), findsOneWidget);
    expect(find.text('Approval required before send'), findsOneWidget);
  });
}
