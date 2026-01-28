import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:secondloop/core/backend/app_backend.dart';
import 'package:secondloop/core/backend/attachments_backend.dart';
import 'package:secondloop/core/session/session_scope.dart';
import 'package:secondloop/features/chat/chat_page.dart';
import 'package:secondloop/src/rust/db.dart';

import 'test_backend.dart';
import 'test_i18n.dart';

void main() {
  testWidgets(
    'Chat image thumbnail state is not recreated when a new message is inserted (main stream)',
    (tester) async {
      SharedPreferences.setMockInitialValues({});

      final backend = _Backend(
        initialMessages: const [
          Message(
            id: 'm1',
            conversationId: 'main_stream',
            role: 'user',
            content: 'Photo',
            createdAtMs: 0,
            isMemory: true,
          ),
        ],
        attachmentsByMessageId: const {
          'm1': [
            Attachment(
              sha256: 'abc',
              mimeType: 'image/png',
              path: 'attachments/abc.bin',
              byteLen: 67,
              createdAtMs: 0,
            ),
          ],
        },
      );

      const conversation = Conversation(
        id: 'main_stream',
        title: 'Main Stream',
        createdAtMs: 0,
        updatedAtMs: 0,
      );

      await tester.pumpWidget(
        AppBackendScope(
          backend: backend,
          child: SessionScope(
            sessionKey: Uint8List.fromList(List<int>.filled(32, 1)),
            lock: () {},
            child: wrapWithI18n(
              const MaterialApp(home: ChatPage(conversation: conversation)),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      final thumbnailFinder =
          find.byKey(const ValueKey('chat_attachment_image_abc'));
      expect(thumbnailFinder, findsOneWidget);

      final stateBefore = tester.state(thumbnailFinder);

      await tester.enterText(find.byKey(const ValueKey('chat_input')), 'Hello');
      await tester.tap(find.byKey(const ValueKey('chat_send')));
      await tester.pumpAndSettle();

      expect(thumbnailFinder, findsOneWidget);
      final stateAfter = tester.state(thumbnailFinder);

      expect(identical(stateBefore, stateAfter), isTrue);
    },
  );
}

final class _Backend extends TestAppBackend implements AttachmentsBackend {
  _Backend({
    required List<Message> initialMessages,
    required this.attachmentsByMessageId,
  }) : super(initialMessages: initialMessages);

  final Map<String, List<Attachment>> attachmentsByMessageId;

  @override
  Future<List<Attachment>> listRecentAttachments(
    Uint8List key, {
    int limit = 50,
  }) async =>
      const <Attachment>[];

  @override
  Future<void> linkAttachmentToMessage(
    Uint8List key,
    String messageId, {
    required String attachmentSha256,
  }) async {}

  @override
  Future<List<Attachment>> listMessageAttachments(
    Uint8List key,
    String messageId,
  ) async {
    return List<Attachment>.from(
      attachmentsByMessageId[messageId] ?? const <Attachment>[],
    );
  }

  @override
  Future<Uint8List> readAttachmentBytes(
    Uint8List key, {
    required String sha256,
  }) async {
    // Not needed for this regression (we only care about State identity).
    return Uint8List(0);
  }
}
