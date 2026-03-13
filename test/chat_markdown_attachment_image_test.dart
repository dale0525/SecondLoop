import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:secondloop/core/backend/app_backend.dart';
import 'package:secondloop/core/backend/attachments_backend.dart';
import 'package:secondloop/core/session/session_scope.dart';
import 'package:secondloop/features/attachments/attachment_draft_send_contract.dart';
import 'package:secondloop/features/chat/chat_markdown_attachment_image.dart';
import 'package:secondloop/features/chat/chat_markdown_preview.dart';
import 'package:secondloop/src/rust/db.dart';

import 'test_backend.dart';
import 'test_i18n.dart';

void main() {
  testWidgets('markdown preview renders draft attachment images',
      (tester) async {
    await tester.pumpWidget(
      wrapWithI18n(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => buildChatMarkdownPreviewBody(
                context,
                text: '![draft](secondloop-draft://image/draft_1)',
                draftAttachments: <AttachmentDraftPayload>[
                  AttachmentDraftPayload(
                    localId: 'draft_1',
                    filename: 'draft.png',
                    mimeType: 'image/png',
                    bytes: _pngBytes(),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.byType(Image), findsOneWidget);
  });

  testWidgets('markdown preview renders persisted attachment images',
      (tester) async {
    await tester.pumpWidget(
      wrapWithI18n(
        MaterialApp(
          home: AppBackendScope(
            backend: _FakeAttachmentBackend(),
            child: SessionScope(
              sessionKey: Uint8List.fromList(List<int>.filled(32, 1)),
              lock: () {},
              child: Scaffold(
                body: Builder(
                  builder: (context) => buildChatMarkdownPreviewBody(
                    context,
                    text: '![saved](secondloop://attachment/sha_1)',
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.byType(Image), findsOneWidget);
  });

  testWidgets('persisted attachment bytes are reused across widget rebuilds',
      (tester) async {
    final backend = _CountingAttachmentBackend();
    final rebuildTick = ValueNotifier<int>(0);

    await tester.pumpWidget(
      wrapWithI18n(
        MaterialApp(
          home: AppBackendScope(
            backend: backend,
            child: SessionScope(
              sessionKey: Uint8List.fromList(List<int>.filled(32, 1)),
              lock: () {},
              child: Scaffold(
                body: ValueListenableBuilder<int>(
                  valueListenable: rebuildTick,
                  builder: (context, _, __) => ChatMarkdownAttachmentImage(
                    uri: Uri.parse('secondloop://attachment/sha_1'),
                    draftAttachments: const <AttachmentDraftPayload>[],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();
    expect(backend.readAttachmentBytesCallCount, 1);

    rebuildTick.value += 1;
    await tester.pump();
    expect(backend.readAttachmentBytesCallCount, 1);

    rebuildTick.value += 1;
    await tester.pump();
    expect(backend.readAttachmentBytesCallCount, 1);
  });
}

class _FakeAttachmentBackend extends TestAppBackend
    implements AttachmentsBackend {
  @override
  Future<String?> readAttachmentPlaceDisplayName(Uint8List key,
          {required String sha256}) async =>
      null;

  @override
  Future<String?> readAttachmentAnnotationCaptionLong(Uint8List key,
          {required String sha256}) async =>
      null;

  @override
  Future<AttachmentExifMetadata?> readAttachmentExifMetadata(Uint8List key,
          {required String sha256}) async =>
      null;

  @override
  Future<List<Attachment>> listRecentAttachments(Uint8List key,
          {int limit = 50}) async =>
      const [];

  @override
  Future<void> linkAttachmentToMessage(Uint8List key, String messageId,
      {required String attachmentSha256}) async {}

  @override
  Future<List<Attachment>> listMessageAttachments(
          Uint8List key, String messageId) async =>
      const [];

  @override
  Future<Uint8List> readAttachmentBytes(Uint8List key,
          {required String sha256}) async =>
      _pngBytes();
}

class _CountingAttachmentBackend extends _FakeAttachmentBackend {
  int readAttachmentBytesCallCount = 0;

  @override
  Future<Uint8List> readAttachmentBytes(Uint8List key,
      {required String sha256}) async {
    readAttachmentBytesCallCount += 1;
    return _pngBytes();
  }
}

Uint8List _pngBytes() => Uint8List.fromList(const <int>[
      0x89,
      0x50,
      0x4e,
      0x47,
      0x0d,
      0x0a,
      0x1a,
      0x0a,
      0x00,
      0x00,
      0x00,
      0x0d,
      0x49,
      0x48,
      0x44,
      0x52,
      0x00,
      0x00,
      0x00,
      0x01,
      0x00,
      0x00,
      0x00,
      0x01,
      0x08,
      0x06,
      0x00,
      0x00,
      0x00,
      0x1f,
      0x15,
      0xc4,
      0x89,
      0x00,
      0x00,
      0x00,
      0x0a,
      0x49,
      0x44,
      0x41,
      0x54,
      0x78,
      0x9c,
      0x63,
      0xf8,
      0xcf,
      0xc0,
      0x00,
      0x00,
      0x03,
      0x01,
      0x01,
      0x00,
      0x18,
      0xdd,
      0x8d,
      0xb1,
      0x00,
      0x00,
      0x00,
      0x00,
      0x49,
      0x45,
      0x4e,
      0x44,
      0xae,
      0x42,
      0x60,
      0x82,
    ]);
