import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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

      final bubble = find.byKey(const ValueKey('message_bubble_m1'));
      expect(bubble, findsOneWidget);
      expect(find.byKey(const ValueKey('message_edit_m1')), findsNothing);

      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      await tester.pump();
      await mouse.moveTo(tester.getCenter(bubble));
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

      final bubble = find.byKey(const ValueKey('message_bubble_m1'));
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      await tester.pump();
      await mouse.moveTo(tester.getCenter(bubble));
      await _pumpUi(tester);

      expect(find.byKey(const ValueKey('message_delete_m1')), findsOneWidget);
      expect(find.byKey(const ValueKey('message_edit_m1')), findsOneWidget);
    } finally {
      debugDefaultTargetPlatformOverride = originalPlatformOverride;
    }
  });

  testWidgets('Copy action uses attachment detail text when message text empty',
      (tester) async {
    String? clipboardText;
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      switch (call.method) {
        case 'Clipboard.setData':
          clipboardText = (call.arguments as Map)['text'] as String?;
          return null;
        case 'Clipboard.getData':
          return <String, dynamic>{'text': clipboardText};
      }
      return null;
    });
    addTearDown(
      () => messenger.setMockMethodCallHandler(SystemChannels.platform, null),
    );

    final originalPlatformOverride = debugDefaultTargetPlatformOverride;
    debugDefaultTargetPlatformOverride = TargetPlatform.android;

    try {
      final backend = _AttachmentChatBackend(
        initialMessages: const [
          Message(
            id: 'm1',
            conversationId: 'loop_home',
            role: 'user',
            content: '',
            createdAtMs: 1,
            isMemory: true,
          ),
        ],
        attachmentsByMessageId: const {
          'm1': [
            Attachment(
              sha256: 'a1',
              mimeType: 'image/png',
              path: 'attachments/a1.png',
              byteLen: 1024,
              createdAtMs: 1,
            ),
            Attachment(
              sha256: 'a2',
              mimeType: 'image/png',
              path: 'attachments/a2.png',
              byteLen: 1024,
              createdAtMs: 1,
            ),
          ],
        },
        placeBySha256: const {
          'a1': 'Shanghai',
        },
        captionBySha256: const {
          'a1': 'Night skyline',
          'a2': 'Street food',
        },
      );

      await _pumpChatPage(tester, backend);

      await tester.longPress(find.byKey(const ValueKey('message_bubble_m1')));
      await _pumpUi(tester);

      await tester.tap(find.byKey(const ValueKey('message_action_copy')));
      await _pumpUi(tester);

      expect(
        clipboardText,
        'Shanghai\n\nNight skyline\n\n----------\n\nStreet food',
      );
    } finally {
      debugDefaultTargetPlatformOverride = originalPlatformOverride;
    }
  });

  testWidgets(
      'Copy action keeps message text only when message has text and attachments',
      (tester) async {
    String? clipboardText;
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      switch (call.method) {
        case 'Clipboard.setData':
          clipboardText = (call.arguments as Map)['text'] as String?;
          return null;
        case 'Clipboard.getData':
          return <String, dynamic>{'text': clipboardText};
      }
      return null;
    });
    addTearDown(
      () => messenger.setMockMethodCallHandler(SystemChannels.platform, null),
    );

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
              sha256: 'a1',
              mimeType: 'image/png',
              path: 'attachments/a1.png',
              byteLen: 1024,
              createdAtMs: 1,
            ),
          ],
        },
        placeBySha256: const {
          'a1': 'Shanghai',
        },
        captionBySha256: const {
          'a1': 'Night skyline',
        },
      );

      await _pumpChatPage(tester, backend);

      await tester.longPress(find.byKey(const ValueKey('message_bubble_m1')));
      await _pumpUi(tester);

      await tester.tap(find.byKey(const ValueKey('message_action_copy')));
      await _pumpUi(tester);

      expect(clipboardText, 'Review this document');
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
    this.placeBySha256 = const <String, String>{},
    this.captionBySha256 = const <String, String>{},
  });

  final Map<String, List<Attachment>> attachmentsByMessageId;
  final Map<String, String> placeBySha256;
  final Map<String, String> captionBySha256;

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
      placeBySha256[sha256];

  @override
  Future<String?> readAttachmentAnnotationCaptionLong(
    Uint8List key, {
    required String sha256,
  }) async =>
      captionBySha256[sha256];
}
