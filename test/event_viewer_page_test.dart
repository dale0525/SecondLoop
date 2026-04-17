import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:secondloop/features/actions/calendar/event_viewer_page.dart';
import 'package:secondloop/src/rust/db.dart';

import 'test_i18n.dart';

void main() {
  testWidgets('event viewer surfaces original timezone alongside local range',
      (tester) async {
    const event = Event(
      id: 'event:cross-zone',
      title: 'Cross-zone planning',
      startAtMs: 1710000000000,
      endAtMs: 1710003600000,
      tz: 'UTC+01:00',
      createdAtMs: 1,
      updatedAtMs: 1,
    );

    await tester.pumpWidget(
      wrapWithI18n(
        const MaterialApp(
          home: EventViewerPage(event: event),
        ),
      ),
    );

    await tester.pumpAndSettle();

    final rendered = tester.widget<SelectableText>(
      find.byKey(const ValueKey('event_viewer_time_range')),
    );
    expect(rendered.data, isNot(contains('UTC')));
    expect(find.byKey(const ValueKey('event_viewer_timezone')), findsOneWidget);
    expect(find.textContaining(event.tz), findsOneWidget);
  });
}
