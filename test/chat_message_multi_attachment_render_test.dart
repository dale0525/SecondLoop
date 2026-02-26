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
  testWidgets('Chat renders one attachment area for multi-attachment message',
      (tester) async {
    final oldPlatform = debugDefaultTargetPlatformOverride;
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    try {
      final backend = _Backend(
        initialMessages: const <Message>[
          Message(
            id: 'm1',
            conversationId: 'c1',
            role: 'user',
            content: 'hello',
            createdAtMs: 1,
            isMemory: true,
          ),
        ],
        initialAttachmentsByMessageId: {
          'm1': <Attachment>[
            const Attachment(
              sha256: 'sha1',
              mimeType: 'image/png',
              path: 'attachments/sha1.png',
              byteLen: 10,
              createdAtMs: 1,
            ),
            const Attachment(
              sha256: 'sha2',
              mimeType: 'image/png',
              path: 'attachments/sha2.png',
              byteLen: 10,
              createdAtMs: 1,
            ),
          ],
        },
      );

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

      expect(find.byKey(const ValueKey('chat_message_row_m1')), findsOneWidget);
      expect(
        find.byKey(const ValueKey('chat_message_attachments_m1')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('chat_attachment_image_sha1')),
          findsOneWidget);
      expect(find.byKey(const ValueKey('chat_attachment_image_sha2')),
          findsOneWidget);
    } finally {
      debugDefaultTargetPlatformOverride = oldPlatform;
    }
  });

  testWidgets('Chat shows failed attachment retry banner after partial send',
      (tester) async {
    final oldPlatform = debugDefaultTargetPlatformOverride;
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    try {
      final backend = _Backend(
        failIngestForPayloadContains: 'bad',
      );
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
              Uint8List.fromList(utf8.encode('good')),
              name: 'good.txt',
            ),
            XFile.fromData(
              Uint8List.fromList(utf8.encode('bad')),
              name: 'bad.txt',
            ),
          ],
          localPosition: Offset.zero,
          globalPosition: Offset.zero,
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('chat_send')));
      await tester.pump();
      await _pumpUntil(
        tester,
        () => find
            .byKey(const ValueKey('chat_attachment_failed_retry_banner'))
            .evaluate()
            .isNotEmpty,
      );

      expect(
        find.byKey(const ValueKey('chat_attachment_failed_retry_banner')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('chat_retry_failed_attachments')),
        findsOneWidget,
      );
      expect(find.byType(InputChip), findsOneWidget);
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

final class _Backend extends NativeAppBackend {
  _Backend({
    List<Message>? initialMessages,
    Map<String, List<Attachment>>? initialAttachmentsByMessageId,
    this.failIngestForPayloadContains,
  })  : _messages = List<Message>.from(initialMessages ?? const <Message>[]),
        _attachmentsByMessageId = <String, List<Attachment>>{
          for (final entry in (initialAttachmentsByMessageId ??
                  const <String, List<Attachment>>{})
              .entries)
            entry.key: List<Attachment>.from(entry.value),
        },
        super(appDirProvider: () async => '/tmp/secondloop_test');

  final String? failIngestForPayloadContains;
  final List<Message> _messages;
  final Map<String, List<Attachment>> _attachmentsByMessageId;
  final Map<String, Uint8List> _attachmentBytesBySha = <String, Uint8List>{};
  int _messageSeq = 1;
  int _attachmentSeq = 0;

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
    final message = Message(
      id: 'm${++_messageSeq}',
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
    final failNeedle = failIngestForPayloadContains?.trim() ?? '';
    if (failNeedle.isNotEmpty &&
        utf8.decode(bytes, allowMalformed: true).contains(failNeedle)) {
      throw StateError('ingest_failed');
    }
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
    final attachment = Attachment(
      sha256: attachmentSha256,
      mimeType: 'image/png',
      path: 'attachments/$attachmentSha256.bin',
      byteLen: _attachmentBytesBySha[attachmentSha256]?.length ?? 0,
      createdAtMs: 0,
    );
    (_attachmentsByMessageId[messageId] ??= <Attachment>[]).add(attachment);
  }

  @override
  Future<List<Attachment>> listMessageAttachments(
    Uint8List key,
    String messageId,
  ) async {
    return List<Attachment>.from(
      _attachmentsByMessageId[messageId] ?? const <Attachment>[],
    );
  }

  @override
  Future<Uint8List> readAttachmentBytes(
    Uint8List key, {
    required String sha256,
  }) async {
    return _attachmentBytesBySha[sha256] ?? _tinyPngBytes();
  }
}

Uint8List _tinyPngBytes() {
  const b64 =
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMBApGq4QAAAABJRU5ErkJggg==';
  return Uint8List.fromList(base64Decode(b64));
}
