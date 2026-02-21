import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
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
  testWidgets('Desktop hover actions hide edit for attachment messages',
      (tester) async {
    final originalPlatformOverride = debugDefaultTargetPlatformOverride;
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;

    try {
      final backend = _AttachmentChatBackend(
        initialMessages: const [
          Message(
            id: 'm1',
            conversationId: 'loop_home',
            role: 'user',
            content: 'Review this document',
            createdAtMs: 1,
            isMemory: true,
          ),
        ],
        attachmentsByMessageId: const {
          'm1': [
            Attachment(
              sha256: 'pdf_sha',
              mimeType: 'application/pdf',
              path: 'attachments/pdf_sha.bin',
              byteLen: 1024,
              createdAtMs: 1,
            ),
          ],
        },
      );

      await _pumpChatPage(tester, backend);

      final messageRow = find.byKey(const ValueKey('chat_message_row_m1'));
      expect(messageRow, findsOneWidget);
      expect(find.byKey(const ValueKey('message_edit_m1')), findsNothing);

      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      await tester.pump();
      await mouse.moveTo(tester.getCenter(messageRow));
      await _pumpUi(tester);

      expect(find.byKey(const ValueKey('message_delete_m1')), findsOneWidget);
      expect(find.byKey(const ValueKey('message_edit_m1')), findsNothing);
    } finally {
      debugDefaultTargetPlatformOverride = originalPlatformOverride;
    }
  });

  testWidgets('Long-press actions hide edit for attachment messages',
      (tester) async {
    final originalPlatformOverride = debugDefaultTargetPlatformOverride;
    debugDefaultTargetPlatformOverride = TargetPlatform.android;

    try {
      final backend = _AttachmentChatBackend(
        initialMessages: const [
          Message(
            id: 'm1',
            conversationId: 'loop_home',
            role: 'user',
            content: 'Review this document',
            createdAtMs: 1,
            isMemory: true,
          ),
        ],
        attachmentsByMessageId: const {
          'm1': [
            Attachment(
              sha256: 'pdf_sha',
              mimeType: 'application/pdf',
              path: 'attachments/pdf_sha.bin',
              byteLen: 1024,
              createdAtMs: 1,
            ),
          ],
        },
      );

      await _pumpChatPage(tester, backend);

      await tester.longPress(find.byKey(const ValueKey('message_bubble_m1')));
      await _pumpUi(tester);

      expect(
          find.byKey(const ValueKey('message_actions_sheet')), findsOneWidget);
      expect(
          find.byKey(const ValueKey('message_action_delete')), findsOneWidget);
      expect(find.byKey(const ValueKey('message_action_copy')), findsOneWidget);
      expect(find.byKey(const ValueKey('message_action_edit')), findsNothing);
    } finally {
      debugDefaultTargetPlatformOverride = originalPlatformOverride;
    }
  });

  testWidgets('Right-click context menu hides edit for attachment messages',
      (tester) async {
    final originalPlatformOverride = debugDefaultTargetPlatformOverride;
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;

    try {
      final backend = _AttachmentChatBackend(
        initialMessages: const [
          Message(
            id: 'm1',
            conversationId: 'loop_home',
            role: 'user',
            content: 'Review this document',
            createdAtMs: 1,
            isMemory: true,
          ),
        ],
        attachmentsByMessageId: const {
          'm1': [
            Attachment(
              sha256: 'pdf_sha',
              mimeType: 'application/pdf',
              path: 'attachments/pdf_sha.bin',
              byteLen: 1024,
              createdAtMs: 1,
            ),
          ],
        },
      );

      await _pumpChatPage(tester, backend);

      final bubble = find.byKey(const ValueKey('message_bubble_m1'));
      final gesture = await tester.startGesture(
        tester.getCenter(bubble),
        kind: PointerDeviceKind.mouse,
        buttons: kSecondaryMouseButton,
      );
      await gesture.up();
      await _pumpUi(tester);

      expect(
          find.byKey(const ValueKey('message_context_delete')), findsOneWidget);
      expect(
          find.byKey(const ValueKey('message_context_copy')), findsOneWidget);
      expect(find.byKey(const ValueKey('message_context_edit')), findsNothing);
    } finally {
      debugDefaultTargetPlatformOverride = originalPlatformOverride;
    }
  });

  testWidgets('Desktop hover actions still show edit for plain text messages',
      (tester) async {
    final originalPlatformOverride = debugDefaultTargetPlatformOverride;
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;

    try {
      final backend = _AttachmentChatBackend(
        initialMessages: const [
          Message(
            id: 'm1',
            conversationId: 'loop_home',
            role: 'user',
            content: 'Plain text only',
            createdAtMs: 1,
            isMemory: true,
          ),
        ],
        attachmentsByMessageId: const {},
      );

      await _pumpChatPage(tester, backend);

      final messageRow = find.byKey(const ValueKey('chat_message_row_m1'));
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      await tester.pump();
      await mouse.moveTo(tester.getCenter(messageRow));
      await _pumpUi(tester);

      expect(find.byKey(const ValueKey('message_delete_m1')), findsOneWidget);
      expect(find.byKey(const ValueKey('message_edit_m1')), findsOneWidget);
    } finally {
      debugDefaultTargetPlatformOverride = originalPlatformOverride;
    }
  });
}

Future<void> _pumpChatPage(WidgetTester tester, AppBackend backend) async {
  await tester.pumpWidget(
    wrapWithI18n(
      MaterialApp(
        home: AppBackendScope(
          backend: backend,
          child: SessionScope(
            sessionKey: Uint8List.fromList(List<int>.filled(32, 1)),
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
  await _pumpUi(tester);
}

Future<void> _pumpUi(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 200));
  await tester.pump(const Duration(milliseconds: 200));
}

final class _AttachmentChatBackend extends TestAppBackend
    implements AttachmentsBackend {
  _AttachmentChatBackend({
    required super.initialMessages,
    required this.attachmentsByMessageId,
  });

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
  }) async =>
      Uint8List(0);

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

  @override
  Future<String?> readAttachmentAnnotationCaptionLong(
    Uint8List key, {
    required String sha256,
  }) async =>
      null;
}
