import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

import 'package:secondloop/features/actions/calendar/event_viewer_page.dart';
import 'package:secondloop/core/models/app_models.dart';

import 'test_i18n.dart';

void main() {
  setUpAll(() {
    tz_data.initializeTimeZones();
  });

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
    final originalRendered = tester.widget<SelectableText>(
      find.byKey(const ValueKey('event_viewer_original_time_range')),
    );
    expect(originalRendered.data, contains(event.tz));
    expect(originalRendered.data, isNot(equals(rendered.data)));
    expect(find.byKey(const ValueKey('event_viewer_timezone')), findsNothing);
  });

  testWidgets(
      'event viewer renders original range for IANA timezone identifiers',
      (tester) async {
    const event = Event(
      id: 'event:iana-zone',
      title: 'West coast sync',
      startAtMs: 1710000000000,
      endAtMs: 1710003600000,
      tz: 'America/Los_Angeles',
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

    final context = tester.element(find.byType(EventViewerPage));
    final localizations = MaterialLocalizations.of(context);
    final location = tz.getLocation(event.tz);
    final originalStart = tz.TZDateTime.fromMillisecondsSinceEpoch(
      location,
      event.startAtMs.toInt(),
    );
    final originalEnd = tz.TZDateTime.fromMillisecondsSinceEpoch(
      location,
      event.endAtMs.toInt(),
    );
    final expectedOriginalRange = originalStart.year == originalEnd.year &&
            originalStart.month == originalEnd.month &&
            originalStart.day == originalEnd.day
        ? '${localizations.formatFullDate(originalStart)} '
            '${localizations.formatTimeOfDay(TimeOfDay.fromDateTime(originalStart))} - '
            '${localizations.formatTimeOfDay(TimeOfDay.fromDateTime(originalEnd))}'
        : '${localizations.formatFullDate(originalStart)} '
            '${localizations.formatTimeOfDay(TimeOfDay.fromDateTime(originalStart))} -> '
            '${localizations.formatFullDate(originalEnd)} '
            '${localizations.formatTimeOfDay(TimeOfDay.fromDateTime(originalEnd))}';

    final originalRendered = tester.widget<SelectableText>(
      find.byKey(const ValueKey('event_viewer_original_time_range')),
    );
    expect(originalRendered.data, contains(event.tz));
    expect(originalRendered.data, contains(expectedOriginalRange));
  });
}
