import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:secondloop/core/backend/app_backend.dart';
import 'package:secondloop/core/session/session_scope.dart';
import 'package:secondloop/features/actions/calendar/event_viewer_page.dart';
import 'package:secondloop/features/chat/message_viewer_page.dart';
import 'package:secondloop/src/rust/db.dart';

import 'test_backend.dart';
import 'test_i18n.dart';

void main() {
  testWidgets('message viewer secondloop event link opens event viewer',
      (tester) async {
    final backend = _Backend(
      events: const [
        Event(
          id: 'event:budget-review',
          title: 'Budget review with Alice',
          startAtMs: 1000,
          endAtMs: 2000,
          tz: 'UTC',
          createdAtMs: 1,
          updatedAtMs: 1,
        ),
      ],
    );

    await tester.pumpWidget(
      wrapWithI18n(
        MaterialApp(
          home: AppBackendScope(
            backend: backend,
            child: SessionScope(
              sessionKey: Uint8List.fromList(List<int>.filled(32, 9)),
              lock: () {},
              child: const MessageViewerPage(
                content: '[Open event](secondloop://event/event:budget-review)',
              ),
            ),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    await tester.tap(find.text('Open event', findRichText: true));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byType(EventViewerPage), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('event_viewer_page')),
        matching: find.text('Budget review with Alice'),
      ),
      findsWidgets,
    );
  });
}

final class _Backend extends TestAppBackend {
  _Backend({required List<Event> events}) : _events = List<Event>.from(events);

  final List<Event> _events;

  @override
  Future<List<Event>> listEvents(Uint8List key) async =>
      List<Event>.from(_events);
}
