import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:secondloop/core/backend/app_backend.dart';
import 'package:secondloop/core/session/session_scope.dart';
import 'package:secondloop/features/chat/message_viewer_page.dart';

import 'test_backend.dart';
import 'test_i18n.dart';

void main() {
  testWidgets('message viewer hides legacy memory-only evidence payloads',
      (tester) async {
    await tester.pumpWidget(
      wrapWithI18n(
        MaterialApp(
          home: AppBackendScope(
            backend: TestAppBackend(),
            child: SessionScope(
              sessionKey: Uint8List.fromList(List<int>.filled(32, 9)),
              lock: () {},
              child: const MessageViewerPage(
                content: 'Answer with evidence.',
                citationsJson: '''
{
  "direct_sources": [],
  "memory_cards": [
    {
      "document_id": "page:old-memory",
      "title": "Old memory",
      "summary": "Legacy knowledge evidence.",
      "source_kind": "summary",
      "role": "summary",
      "created_at_ms": 1,
      "updated_at_ms": 2,
      "status": "confirmed",
      "source_count": 2
    }
  ]
}
''',
              ),
            ),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.byType(ActionChip), findsNothing);
    expect(find.text('Open evidence'), findsNothing);
    expect(find.text('Inspect page'), findsNothing);
  });

  testWidgets(
      'message viewer mixed legacy payload only exposes direct-source evidence',
      (tester) async {
    await tester.pumpWidget(
      wrapWithI18n(
        MaterialApp(
          home: AppBackendScope(
            backend: TestAppBackend(),
            child: SessionScope(
              sessionKey: Uint8List.fromList(List<int>.filled(32, 9)),
              lock: () {},
              child: const MessageViewerPage(
                content: 'Answer with evidence.',
                citationsJson: '''
{
  "direct_sources": [
    {
      "id": "message:source-1",
      "href": "secondloop://message/source-1",
      "source_type": "message",
      "label": "History",
      "source_type_label": "chat_message",
      "scope_label": "this_thread",
      "confidence_label": "high_relevance",
      "title": "Kickoff notes",
      "snippet": "Reply in Chinese.",
      "highlighted_text": "Reply in Chinese.",
      "created_at_ms": 1,
      "updated_at_ms": 1
    }
  ],
  "memory_cards": [
    {
      "document_id": "page:preferences",
      "title": "Preferences",
      "summary": "Reply in Chinese.",
      "source_kind": "summary",
      "role": "summary",
      "created_at_ms": 1,
      "updated_at_ms": 2,
      "status": "confirmed",
      "source_count": 2
    }
  ]
}
''',
              ),
            ),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    await tester.tap(find.text('Open evidence'));
    await tester.pumpAndSettle();

    expect(find.text('Kickoff notes'), findsOneWidget);
    expect(find.text('Inspect page'), findsNothing);
    expect(find.text('Stop using in answers'), findsNothing);
    expect(find.text('View original'), findsOneWidget);
  });
}
