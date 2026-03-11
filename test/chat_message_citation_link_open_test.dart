import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:secondloop/core/backend/app_backend.dart';
import 'package:secondloop/core/backend/attachments_backend.dart';
import 'package:secondloop/core/session/session_scope.dart';
import 'package:secondloop/features/chat/chat_markdown_preview.dart';
import 'package:secondloop/features/chat/chat_page.dart';
import 'package:secondloop/features/chat/message_deeplink.dart';
import 'package:secondloop/src/rust/db.dart';

import 'test_backend.dart';
import 'test_i18n.dart';

void main() {
  test(
      'normalizeChatMarkdownForPreview linkifies bare secondloop message links',
      () {
    final normalized = normalizeChatMarkdownForPreview(
      'Relevant note: secondloop://message/history-1',
    );

    expect(
      normalized,
      contains(
        '[secondloop://message/history-1](secondloop://message/history-1)',
      ),
    );
  });

  test('parseMessageDeepLink parses secondloop message deeplinks', () {
    final parsed = parseMessageDeepLink(
      'secondloop://message/history-1?ignored=true',
    );

    expect(parsed, isNotNull);
    expect(parsed!.messageId, 'history-1');
  });

  test(
      'normalizeChatMarkdownForPreview does not relink bare secondloop links inside brackets',
      () {
    const original = '[secondloop://message/history-1]';

    final normalized = normalizeChatMarkdownForPreview(original);

    expect(normalized, original);
  });

  testWidgets('chat citation secondloop message link opens message viewer',
      (tester) async {
    final backend = _Backend(
      initialMessages: const [
        Message(
          id: 'history-1',
          conversationId: 'loop_home',
          role: 'user',
          content: 'Project kickoff moved to Friday afternoon.',
          createdAtMs: 1,
          isMemory: true,
        ),
        Message(
          id: 'm1',
          conversationId: 'loop_home',
          role: 'assistant',
          content: 'See [Project kickoff note](secondloop://message/history-1)',
          createdAtMs: 2,
          isMemory: false,
        ),
      ],
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

    await tester.tap(
      find.textContaining('Project kickoff note', findRichText: true),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byKey(const ValueKey('message_viewer_page')), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('message_viewer_page')),
        matching: find.text(
          'Project kickoff moved to Friday afternoon.',
          findRichText: true,
        ),
      ),
      findsWidgets,
    );
  });
}

final class _Backend extends TestAppBackend implements AttachmentsBackend {
  _Backend({required List<Message> initialMessages})
      : super(initialMessages: initialMessages);

  @override
  Future<Attachment?> readAttachmentBySha256(String attachmentSha256) async =>
      null;

  @override
  Future<List<Attachment>> listMessageAttachments(
    Uint8List key,
    String messageId,
  ) async =>
      const <Attachment>[];

  @override
  Future<void> linkAttachmentToMessage(
    Uint8List key,
    String messageId, {
    required String attachmentSha256,
  }) async {}

  @override
  Future<List<Attachment>> listRecentAttachments(
    Uint8List key, {
    int limit = 50,
  }) async =>
      const <Attachment>[];

  @override
  Future<String?> readAttachmentAnnotationCaptionLong(
    Uint8List key, {
    required String sha256,
  }) async =>
      null;

  @override
  Future<Uint8List> readAttachmentBytes(
    Uint8List key, {
    required String sha256,
  }) async =>
      Uint8List.fromList(const <int>[1, 2, 3]);

  @override
  Future<AttachmentExifMetadata?> readAttachmentExifMetadata(
    Uint8List key, {
    required String sha256,
  }) async =>
      null;

  @override
  Future<String?> readAttachmentPlaceDisplayName(
    Uint8List key, {
    required String sha256,
  }) async =>
      null;
}
