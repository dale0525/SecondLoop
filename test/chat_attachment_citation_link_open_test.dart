import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:secondloop/core/backend/app_backend.dart';
import 'package:secondloop/core/backend/attachments_backend.dart';
import 'package:secondloop/core/session/session_scope.dart';
import 'package:secondloop/features/chat/chat_page.dart';
import 'package:secondloop/src/rust/db.dart';

import 'test_backend.dart';
import 'test_i18n.dart';

void main() {
  testWidgets(
      'chat citation secondloop attachment link opens attachment viewer',
      (tester) async {
    const attachment = Attachment(
      sha256: 'abc123sha',
      mimeType: 'text/plain',
      path: 'attachments/abc123sha.bin',
      byteLen: 12,
      createdAtMs: 1,
    );

    final backend = _Backend(
      attachment: attachment,
      initialMessages: const [
        Message(
          id: 'm1',
          conversationId: 'loop_home',
          role: 'assistant',
          content:
              'See [Quarterly Notes](secondloop://attachment/abc123sha?kind=readable_text_full&chunk=2)',
          createdAtMs: 1,
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

    await tester
        .tap(find.textContaining('Quarterly Notes', findRichText: true));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(
        find.byKey(const ValueKey('attachment_detail_action_open_with_system')),
        findsOneWidget);
  });
}

final class _Backend extends TestAppBackend implements AttachmentsBackend {
  _Backend({
    required this.attachment,
    required List<Message> initialMessages,
  }) : super(initialMessages: initialMessages);

  final Attachment attachment;

  @override
  Future<Attachment?> readAttachmentBySha256(String attachmentSha256) async {
    if (attachmentSha256 == attachment.sha256) {
      return attachment;
    }
    return null;
  }

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
      <Attachment>[attachment];

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
      Uint8List.fromList(<int>[1, 2, 3, 4]);

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
