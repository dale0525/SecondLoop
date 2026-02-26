import 'dart:convert';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';

import 'package:secondloop/core/backend/app_backend.dart';
import 'package:secondloop/core/backend/native_backend.dart';
import 'package:secondloop/core/session/session_scope.dart';
import 'package:secondloop/features/chat/chat_page.dart';
import 'package:secondloop/src/rust/db.dart';

import 'test_i18n.dart';

void main() {
  testWidgets('Desktop drop queues drafts and sends only after tapping send',
      (tester) async {
    final oldPlatform = debugDefaultTargetPlatformOverride;
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    try {
      final backend = _TestBackend();
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
                    id: 'c1',
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

      final dropTarget = tester.widget<DropTarget>(find.byType(DropTarget));
      dropTarget.onDragDone?.call(
        DropDoneDetails(
          files: [
            XFile.fromData(
              Uint8List.fromList(utf8.encode('k=v\n')),
              name: 'drop.ini',
            ),
            XFile.fromData(_tinyPngBytes(), name: 'drop.png'),
          ],
          localPosition: Offset.zero,
          globalPosition: Offset.zero,
        ),
      );
      await tester.pumpAndSettle();

      expect(backend.insertAttachmentCalls, 0);
      expect(backend.linkCalls, 0);
      expect(backend.insertMessageCalls, 0);
      expect(find.byKey(const ValueKey('chat_draft_attachment_list')),
          findsOneWidget);
      expect(find.byType(InputChip), findsNWidgets(2));
      expect(find.byKey(const ValueKey('chat_send')), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('chat_send')));
      await tester.pump();
      await _pumpUntil(tester, () => backend.linkCalls >= 2);

      expect(backend.insertAttachmentCalls, 2);
      expect(backend.linkCalls, 2);
      expect(backend.insertMessageCalls, 1);
    } finally {
      debugDefaultTargetPlatformOverride = oldPlatform;
    }
  });

  testWidgets('Desktop send combines text and drafts into one message',
      (tester) async {
    final oldPlatform = debugDefaultTargetPlatformOverride;
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    try {
      final backend = _TestBackend();
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
                    id: 'c1',
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

      final dropTarget = tester.widget<DropTarget>(find.byType(DropTarget));
      dropTarget.onDragDone?.call(
        DropDoneDetails(
          files: [
            XFile.fromData(
              Uint8List.fromList(utf8.encode('doc')),
              name: 'one.txt',
            ),
            XFile.fromData(
              Uint8List.fromList(utf8.encode('doc2')),
              name: 'two.txt',
            ),
          ],
          localPosition: Offset.zero,
          globalPosition: Offset.zero,
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(InputChip), findsNWidgets(2));

      await tester.enterText(find.byKey(const ValueKey('chat_input')), 'hello');
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('chat_send')));
      await tester.pump();
      await _pumpUntil(tester, () => backend.linkCalls >= 2);

      expect(backend.insertMessageCalls, 1);
      expect(backend.insertedMessageContents, const <String>['hello']);
      expect(backend.insertAttachmentCalls, 2);
      expect(backend.linkCalls, 2);
    } finally {
      debugDefaultTargetPlatformOverride = oldPlatform;
    }
  });
}

Future<void> _pumpUntil(
  WidgetTester tester,
  bool Function() condition, {
  int maxTicks = 300,
  Duration step = const Duration(milliseconds: 20),
}) async {
  for (var i = 0; i < maxTicks; i++) {
    if (condition()) return;
    await tester.pump(step);
  }
}

Uint8List _tinyPngBytes() {
  const b64 =
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMBApGq4QAAAABJRU5ErkJggg==';
  return Uint8List.fromList(base64Decode(b64));
}

final class _TestBackend extends NativeAppBackend {
  _TestBackend() : super(appDirProvider: () async => '/tmp/secondloop_test');

  int insertAttachmentCalls = 0;
  int insertMessageCalls = 0;
  int linkCalls = 0;
  final List<String> insertedMessageContents = <String>[];
  final List<String> insertedAttachmentMimeTypes = <String>[];

  int _messageSeq = 0;
  int _attachmentSeq = 0;

  final List<Message> _messages = <Message>[];
  final Map<String, Uint8List> _attachmentBytesBySha = <String, Uint8List>{};

  @override
  Future<List<Message>> listMessages(
    Uint8List key,
    String conversationId,
  ) async {
    return _messages
        .where((m) => m.conversationId == conversationId)
        .toList(growable: false);
  }

  @override
  Future<List<Message>> listMessagesPage(
    Uint8List key,
    String conversationId, {
    int? beforeCreatedAtMs,
    String? beforeId,
    int limit = 60,
  }) async {
    return listMessages(key, conversationId);
  }

  @override
  Future<Message> insertMessage(
    Uint8List key,
    String conversationId, {
    required String role,
    required String content,
  }) async {
    insertMessageCalls++;
    insertedMessageContents.add(content);
    final id = 'm${++_messageSeq}';
    final message = Message(
      id: id,
      conversationId: conversationId,
      role: role,
      content: content,
      createdAtMs: _messageSeq,
      isMemory: true,
    );
    _messages.add(message);
    return message;
  }

  @override
  Future<List<Todo>> listTodos(Uint8List key) async => const <Todo>[];

  @override
  Future<Todo> upsertTodo(
    Uint8List key, {
    required String id,
    required String title,
    int? dueAtMs,
    required String status,
    String? sourceEntryId,
    int? reviewStage,
    int? nextReviewAtMs,
    int? lastReviewAtMs,
  }) async {
    return Todo(
      id: id,
      title: title,
      dueAtMs: dueAtMs,
      status: status,
      sourceEntryId: sourceEntryId,
      createdAtMs: 0,
      updatedAtMs: 0,
      reviewStage: reviewStage,
      nextReviewAtMs: nextReviewAtMs,
      lastReviewAtMs: lastReviewAtMs,
    );
  }

  @override
  Future<Attachment> insertAttachment(
    Uint8List key, {
    required Uint8List bytes,
    required String mimeType,
  }) async {
    insertAttachmentCalls++;
    insertedAttachmentMimeTypes.add(mimeType);
    final sha = 'sha${++_attachmentSeq}';
    _attachmentBytesBySha[sha] = bytes;
    return Attachment(
      sha256: sha,
      mimeType: mimeType,
      path: 'attachments/$sha.bin',
      byteLen: bytes.length,
      createdAtMs: 0,
    );
  }

  @override
  Future<void> linkAttachmentToMessage(
    Uint8List key,
    String messageId, {
    required String attachmentSha256,
  }) async {
    linkCalls++;
  }

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
    return _attachmentBytesBySha[sha256] ?? Uint8List(0);
  }
}
