import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:secondloop/features/actions/calendar/event_viewer_page.dart';
import 'package:secondloop/src/rust/db.dart';

import 'test_i18n.dart';

void main() {
  testWidgets('event viewer labels local rendered time with local timezone',
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

    final localStart =
        DateTime.fromMillisecondsSinceEpoch(event.startAtMs.toInt()).toLocal();
    final expectedLocalTimezone =
        _formatTimeZoneOffset(localStart.timeZoneOffset);

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
    expect(rendered.data, contains(expectedLocalTimezone));
    expect(rendered.data, isNot(contains(event.tz)));
  });
}

String _formatTimeZoneOffset(Duration offset) {
  final totalMinutes = offset.inMinutes;
  final sign = totalMinutes >= 0 ? '+' : '-';
  final absoluteMinutes = totalMinutes.abs();
  final hours = absoluteMinutes ~/ 60;
  final minutes = absoluteMinutes % 60;
  return 'UTC$sign${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}';
}
