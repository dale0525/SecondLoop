import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:secondloop/core/backend/app_backend.dart';
import 'package:secondloop/core/backend/attachments_backend.dart';
import 'package:secondloop/core/session/session_scope.dart';
import 'package:secondloop/features/chat/chat_page.dart';
import 'package:secondloop/features/chat/message_viewer_page.dart';
import 'package:secondloop/src/rust/db.dart';

import 'test_backend.dart';
import 'test_i18n.dart';

void main() {
  const attachment = Attachment(
    sha256: 'sha_doc',
    mimeType: 'application/pdf',
    path: 'attachments/sha_doc.bin',
    byteLen: 9,
    createdAtMs: 0,
  );

  testWidgets('chat markdown citation link opens attachment viewer',
      (tester) async {
    final backend = _CitationBackend(
      initialMessages: const [
        Message(
          id: 'm1',
          conversationId: 'main_stream',
          role: 'assistant',
          content: 'Please check [Source](secondloop://attachment/sha_doc).',
          createdAtMs: 0,
          isMemory: false,
        ),
      ],
      recentAttachments: const [attachment],
    );
    final observer = _RecordingNavigatorObserver();

    await tester.pumpWidget(
      wrapWithI18n(
        AppBackendScope(
          backend: backend,
          child: SessionScope(
            sessionKey: Uint8List.fromList(List<int>.filled(32, 1)),
            lock: () {},
            child: MaterialApp(
              navigatorObservers: [observer],
              home: const ChatPage(
                conversation: Conversation(
                  id: 'main_stream',
                  title: 'Main Stream',
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

    final markdownBodies = tester.widgetList<MarkdownBody>(
      find.byType(MarkdownBody),
    );
    final assistantMarkdown = markdownBodies.firstWhere(
      (widget) => widget.data.contains('secondloop://attachment/sha_doc'),
    );
    final onTapLink = assistantMarkdown.onTapLink;
    expect(onTapLink, isNotNull);

    final baselinePushes = observer.pushedRoutes.length;
    onTapLink!.call('Source', 'secondloop://attachment/sha_doc', '');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(observer.pushedRoutes.length, baselinePushes + 1);
  });

  testWidgets('message viewer citation link opens attachment viewer',
      (tester) async {
    final backend = _CitationBackend(
      initialMessages: const [],
      recentAttachments: const [attachment],
    );
    final observer = _RecordingNavigatorObserver();

    await tester.pumpWidget(
      wrapWithI18n(
        AppBackendScope(
          backend: backend,
          child: SessionScope(
            sessionKey: Uint8List.fromList(List<int>.filled(32, 1)),
            lock: () {},
            child: MaterialApp(
              navigatorObservers: [observer],
              home: const MessageViewerPage(
                content: 'Evidence: [Doc](secondloop://attachment/sha_doc)',
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final markdown = tester.widget<Markdown>(find.byType(Markdown));
    final onTapLink = markdown.onTapLink;
    expect(onTapLink, isNotNull);

    final baselinePushes = observer.pushedRoutes.length;
    onTapLink!.call('Doc', 'secondloop://attachment/sha_doc', '');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(observer.pushedRoutes.length, baselinePushes + 1);
  });
}

final class _RecordingNavigatorObserver extends NavigatorObserver {
  final List<Route<dynamic>> pushedRoutes = <Route<dynamic>>[];

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    pushedRoutes.add(route);
    super.didPush(route, previousRoute);
  }
}

final class _CitationBackend extends TestAppBackend
    implements AttachmentsBackend {
  _CitationBackend({
    required super.initialMessages,
    required this.recentAttachments,
  });

  final List<Attachment> recentAttachments;

  @override
  Future<List<Attachment>> listRecentAttachments(
    Uint8List key, {
    int limit = 50,
  }) async {
    return List<Attachment>.from(recentAttachments.take(limit));
  }

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
    return const <Attachment>[];
  }

  @override
  Future<Uint8List> readAttachmentBytes(
    Uint8List key, {
    required String sha256,
  }) async {
    return Uint8List.fromList(<int>[1, 2, 3]);
  }

  @override
  Future<AttachmentExifMetadata?> readAttachmentExifMetadata(
    Uint8List key, {
    required String sha256,
  }) async {
    return null;
  }

  @override
  Future<String?> readAttachmentPlaceDisplayName(
    Uint8List key, {
    required String sha256,
  }) async {
    return null;
  }

  @override
  Future<String?> readAttachmentAnnotationCaptionLong(
    Uint8List key, {
    required String sha256,
  }) async {
    return null;
  }
}
