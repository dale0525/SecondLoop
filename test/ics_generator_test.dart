import 'package:flutter_test/flutter_test.dart';

import 'package:secondloop/features/actions/calendar/ics_generator.dart';

void main() {
  test('generates minimal ics content with UTC times', () {
    final ics = IcsGenerator.generateEvent(
      uid: 'uid123',
      title: 'Lunch',
      startUtc: DateTime.utc(2026, 1, 24, 12, 0),
      endUtc: DateTime.utc(2026, 1, 24, 13, 0),
      dtStampUtc: DateTime.utc(2026, 1, 20, 0, 0),
    );

    expect(ics, contains('BEGIN:VCALENDAR\r\n'));
    expect(ics, contains('BEGIN:VEVENT\r\n'));
    expect(ics, contains('UID:uid123\r\n'));
    expect(ics, contains('SUMMARY:Lunch\r\n'));
    expect(ics, contains('DTSTART:20260124T120000Z\r\n'));
    expect(ics, contains('DTEND:20260124T130000Z\r\n'));
    expect(ics, contains('DTSTAMP:20260120T000000Z\r\n'));
    expect(ics, contains('END:VEVENT\r\n'));
    expect(ics.trim().endsWith('END:VCALENDAR'), isTrue);
  });
}
