import 'dart:convert';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';

import 'package:secondloop/core/backend/app_backend.dart';
import 'package:secondloop/core/backend/native_backend.dart';
import 'package:secondloop/core/session/session_scope.dart';
import 'package:secondloop/features/actions/todo/todo_detail_page.dart';
import 'package:secondloop/features/chat/chat_page.dart';
import 'package:secondloop/src/rust/db.dart';

import 'test_i18n.dart';

void main() {
  testWidgets('Offstage chat drop target ignores drag when todo detail is top',
      (tester) async {
    final oldPlatform = debugDefaultTargetPlatformOverride;
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    try {
      final backend = _Backend();
      final navigatorKey = GlobalKey<NavigatorState>();
      await tester.pumpWidget(
        wrapWithI18n(
          MaterialApp(
            navigatorKey: navigatorKey,
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

      navigatorKey.currentState!.push(
        MaterialPageRoute<void>(
          builder: (_) => const TodoDetailPage(
            initialTodo: Todo(
              id: 't1',
              title: 'Task',
              status: 'open',
              createdAtMs: 0,
              updatedAtMs: 0,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final chatDropTarget = tester.widget<DropTarget>(
        find.byKey(
          const ValueKey('chat_desktop_drop_target'),
          skipOffstage: false,
        ),
      );
      chatDropTarget.onDragDone?.call(
        DropDoneDetails(
          files: [
            XFile.fromData(
              Uint8List.fromList(utf8.encode('hidden-route')),
              name: 'hidden.txt',
            ),
          ],
          localPosition: Offset.zero,
          globalPosition: Offset.zero,
        ),
      );
      await tester.pumpAndSettle();

      navigatorKey.currentState!.pop();
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('chat_draft_attachment_list')),
          findsNothing);
      expect(find.byType(InputChip), findsNothing);
    } finally {
      debugDefaultTargetPlatformOverride = oldPlatform;
    }
  });
}

final class _Backend extends NativeAppBackend {
  _Backend() : super(appDirProvider: () async => '/tmp/secondloop_test');

  final List<Message> _messages = <Message>[];
  final Map<String, Uint8List> _attachmentBytesBySha = <String, Uint8List>{};
  int _messageSeq = 0;
  int _attachmentSeq = 0;

  @override
  Future<String?> getTodoRecurrenceRuleJson(
    Uint8List key, {
    required String todoId,
  }) async =>
      null;

  @override
  Future<List<TodoActivity>> listTodoActivities(
    Uint8List key,
    String todoId,
  ) async =>
      const <TodoActivity>[];

  @override
  Future<List<Attachment>> listTodoActivityAttachments(
    Uint8List key,
    String activityId,
  ) async =>
      const <Attachment>[];

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
  }) async {}

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
