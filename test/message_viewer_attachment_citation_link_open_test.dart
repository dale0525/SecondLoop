import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:secondloop/core/backend/app_backend.dart';
import 'package:secondloop/core/backend/attachments_backend.dart';
import 'package:secondloop/core/session/session_scope.dart';
import 'package:secondloop/features/attachments/attachment_viewer_page.dart';
import 'package:secondloop/features/chat/message_viewer_page.dart';
import 'package:secondloop/src/rust/db.dart';

import 'test_backend.dart';
import 'test_i18n.dart';

void main() {
  testWidgets(
      'message viewer citation secondloop attachment link opens attachment viewer',
      (tester) async {
    const attachment = Attachment(
      sha256: 'sha-for-viewer',
      mimeType: 'text/plain',
      path: 'attachments/sha-for-viewer.bin',
      byteLen: 8,
      createdAtMs: 2,
    );

    final backend = _Backend(attachment: attachment);

    await tester.pumpWidget(
      wrapWithI18n(
        MaterialApp(
          home: AppBackendScope(
            backend: backend,
            child: SessionScope(
              sessionKey: Uint8List.fromList(List<int>.filled(32, 9)),
              lock: () {},
              child: const MessageViewerPage(
                content:
                    '[Open Evidence](secondloop://attachment/sha-for-viewer?kind=readable_text_full&chunk=1)',
              ),
            ),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    await tester.tap(find.text('Open Evidence', findRichText: true));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(
        find.byKey(const ValueKey('attachment_detail_action_open_with_system')),
        findsOneWidget);
    final page = tester.widget<AttachmentViewerPage>(
      find.byType(AttachmentViewerPage),
    );
    expect(page.initialContentKind, 'readable_text_full');
    expect(page.initialChunkIndex, 1);
  });

  testWidgets('message viewer ignores knowledge-document links after removal',
      (tester) async {
    final launchedUrls = <String>[];
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    const channel = MethodChannel('plugins.flutter.io/url_launcher');
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'launch') {
        launchedUrls.add((call.arguments as Map)['url'] as String);
      }
      return true;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));

    await tester.pumpWidget(
      wrapWithI18n(
        MaterialApp(
          home: AppBackendScope(
            backend: TestAppBackend(),
            child: SessionScope(
              sessionKey: Uint8List.fromList(List<int>.filled(32, 9)),
              lock: () {},
              child: const MessageViewerPage(
                content:
                    '[Open Knowledge](secondloop://knowledge-document/external%3Adoc-1?chunk=7&unit=external%3Adoc-1%3Achunk%3A0007)',
              ),
            ),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    await tester.tap(find.text('Open Knowledge', findRichText: true));
    await tester.pump();

    expect(find.byKey(const ValueKey('message_viewer_page')), findsOneWidget);
    expect(find.byType(AttachmentViewerPage), findsNothing);
    expect(launchedUrls, isEmpty);
  });
}

final class _Backend extends TestAppBackend implements AttachmentsBackend {
  _Backend({required this.attachment});

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
      Uint8List.fromList(<int>[5, 6, 7]);

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
