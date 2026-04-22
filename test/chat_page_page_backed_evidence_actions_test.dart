import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:secondloop/core/backend/app_backend.dart';
import 'package:secondloop/core/session/session_scope.dart';
import 'package:secondloop/features/chat/chat_page.dart';
import 'package:secondloop/src/rust/db.dart';

import 'test_backend.dart';
import 'test_i18n.dart';

void main() {
  testWidgets(
    'chat page hides legacy memory-only evidence payloads',
    (tester) async {
      final backend = _ChatEvidenceBackend(
        citationsJson: '''
{
  "direct_sources": [],
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
      );

      await tester.pumpWidget(
        wrapWithI18n(
          MaterialApp(
            home: AppBackendScope(
              backend: backend,
              child: SessionScope(
                sessionKey: Uint8List.fromList(List<int>.filled(32, 7)),
                lock: () {},
                child: const ChatPage(
                  conversation: Conversation(
                    id: 'loop_home',
                    title: 'Loop',
                    createdAtMs: 0,
                    updatedAtMs: 0,
                  ),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('1 sources'), findsNothing);
      expect(find.byType(ActionChip), findsNothing);
      expect(find.text('Inspect page'), findsNothing);
    },
  );

  testWidgets(
    'chat page mixed legacy payload keeps message direct sources read-only',
    (tester) async {
      final backend = _ChatEvidenceBackend(
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
      );

      await tester.pumpWidget(
        wrapWithI18n(
          MaterialApp(
            home: AppBackendScope(
              backend: backend,
              child: SessionScope(
                sessionKey: Uint8List.fromList(List<int>.filled(32, 7)),
                lock: () {},
                child: const ChatPage(
                  conversation: Conversation(
                    id: 'loop_home',
                    title: 'Loop',
                    createdAtMs: 0,
                    updatedAtMs: 0,
                  ),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      await tester.tap(find.text('1 sources'));
      await tester.pumpAndSettle();

      expect(find.text('Reply in Chinese.'), findsOneWidget);
      expect(find.text('Inspect page'), findsNothing);
      expect(find.text('Stop using in answers'), findsNothing);
      expect(find.text('View original'), findsNothing);
    },
  );
}

final class _ChatEvidenceBackend extends TestAppBackend {
  _ChatEvidenceBackend({
    required String citationsJson,
  }) : super(
          initialMessages: <Message>[
            Message(
              id: 'm1',
              conversationId: 'loop_home',
              role: 'assistant',
              content: 'Answer with page-backed evidence.',
              createdAtMs: 1,
              isMemory: false,
              citationsJson: citationsJson,
            ),
          ],
        );
}
