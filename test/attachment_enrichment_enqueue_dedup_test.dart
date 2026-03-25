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
  testWidgets('Draft audio enrichment enqueue happens only after link success',
      (tester) async {
    final oldPlatform = debugDefaultTargetPlatformOverride;
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    try {
      final sessionKey = Uint8List.fromList(List<int>.filled(32, 1));
      final backend = _Backend(failLink: true);
      await tester.pumpWidget(
        wrapWithI18n(
          MaterialApp(
            home: AppBackendScope(
              backend: backend,
              child: SessionScope(
                sessionKey: sessionKey,
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
            XFile.fromData(_tinyAudioBytes(), name: 'one.mp3'),
          ],
          localPosition: Offset.zero,
          globalPosition: Offset.zero,
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('chat_send')));
      await tester.pump();
      await _pumpUntil(tester, () => backend.linkCalls >= 1);

      expect(backend.linkCalls, 1);
      expect(backend.enqueueAnnotationCalls, 0);
    } finally {
      debugDefaultTargetPlatformOverride = oldPlatform;
    }
  });

  testWidgets('Draft duplicate audio files enqueue enrichment once',
      (tester) async {
    final oldPlatform = debugDefaultTargetPlatformOverride;
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    try {
      final sessionKey = Uint8List.fromList(List<int>.filled(32, 2));
      final backend = _Backend();
      await tester.pumpWidget(
        wrapWithI18n(
          MaterialApp(
            home: AppBackendScope(
              backend: backend,
              child: SessionScope(
                sessionKey: sessionKey,
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

      final bytes = _tinyAudioBytes();
      final dropTarget = tester.widget<DropTarget>(find.byType(DropTarget));
      dropTarget.onDragDone?.call(
        DropDoneDetails(
          files: [
            XFile.fromData(bytes, name: 'dup.mp3'),
            XFile.fromData(bytes, name: 'dup.mp3'),
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
        () => backend.linkCalls >= 1,
      );

      expect(backend.insertAttachmentCalls, 1);
      expect(backend.linkCalls, 1);
      expect(backend.enqueueAnnotationCalls, 1);
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
    this.failLink = false,
  }) : super(appDirProvider: () async => '/tmp/secondloop_test');

  final bool failLink;
  final List<Message> _messages = <Message>[];
  final Map<String, Uint8List> _attachmentBytesBySha = <String, Uint8List>{};

  int _messageSeq = 0;
  int _attachmentSeq = 0;
  int insertAttachmentCalls = 0;
  int linkCalls = 0;
  int enqueueAnnotationCalls = 0;

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
    int? manualImportanceNudgeScore,
    int? manualUrgencyNudgeScore,
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
      manualImportanceNudgeScore: manualImportanceNudgeScore ?? 0,
      manualUrgencyNudgeScore: manualUrgencyNudgeScore ?? 0,
    );
  }

  @override
  Future<Attachment> insertAttachment(
    Uint8List key, {
    required Uint8List bytes,
    required String mimeType,
  }) async {
    insertAttachmentCalls += 1;
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
    linkCalls += 1;
    if (failLink) {
      throw StateError('link_failed');
    }
    enqueueAnnotationCalls += 1;
  }

  @override
  Future<void> enqueueAttachmentAnnotation(
    Uint8List key, {
    required String attachmentSha256,
    required String lang,
    required int nowMs,
  }) async {
    enqueueAnnotationCalls += 1;
  }

  @override
  Future<List<Attachment>> listMessageAttachments(
    Uint8List key,
    String messageId,
  ) async =>
      const <Attachment>[];

  @override
  Future<Uint8List> readAttachmentBytes(
    Uint8List key, {
    required String sha256,
  }) async {
    return _attachmentBytesBySha[sha256] ?? Uint8List(0);
  }
}

Uint8List _tinyAudioBytes() {
  return Uint8List.fromList(<int>[0x49, 0x44, 0x33, 0x04, 0x00, 0x00, 0x00]);
}
