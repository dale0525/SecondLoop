import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:secondloop/core/backend/app_backend.dart';
import 'package:secondloop/core/backend/native_backend.dart';
import 'package:secondloop/core/session/session_scope.dart';
import 'package:secondloop/features/actions/todo/todo_detail_page.dart';
import 'package:secondloop/features/attachments/attachment_card.dart';
import 'package:secondloop/src/rust/db.dart';

import 'test_i18n.dart';

void main() {
  testWidgets(
      'Todo detail deduplicates message and activity attachments by sha',
      (tester) async {
    final backend = _Backend();

    await tester.pumpWidget(
      wrapWithI18n(
        MaterialApp(
          home: AppBackendScope(
            backend: backend,
            child: SessionScope(
              sessionKey: Uint8List.fromList(List<int>.filled(32, 1)),
              lock: () {},
              child: const TodoDetailPage(
                initialTodo: Todo(
                  id: 't1',
                  title: 'Task',
                  status: 'open',
                  createdAtMs: 0,
                  updatedAtMs: 0,
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await _pumpUntil(
      tester,
      () => find.byType(AttachmentCard).evaluate().isNotEmpty,
    );

    expect(find.byType(AttachmentCard), findsOneWidget);
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
  _Backend() : super(appDirProvider: () async => '/tmp/secondloop_test');

  static const Attachment _sharedAttachment = Attachment(
    sha256: 'sha_shared',
    mimeType: 'application/pdf',
    path: 'attachments/sha_shared.bin',
    byteLen: 128,
    createdAtMs: 0,
  );

  static const Message _sourceMessage = Message(
    id: 'm1',
    conversationId: 'loop_home',
    role: 'user',
    content: 'same file from message + activity',
    createdAtMs: 1,
    isMemory: true,
  );

  static const TodoActivity _noteActivity = TodoActivity(
    id: 'a1',
    todoId: 't1',
    activityType: 'note',
    content: 'attached file',
    sourceMessageId: 'm1',
    createdAtMs: 1,
  );

  @override
  Future<List<TodoActivity>> listTodoActivities(
    Uint8List key,
    String todoId,
  ) async {
    return const <TodoActivity>[_noteActivity];
  }

  @override
  Future<String?> getTodoRecurrenceRuleJson(
    Uint8List key, {
    required String todoId,
  }) async {
    return null;
  }

  @override
  Future<Message?> getMessageById(
    Uint8List key,
    String messageId,
  ) async {
    if (messageId == _sourceMessage.id) return _sourceMessage;
    return null;
  }

  @override
  Future<List<Attachment>> listMessageAttachments(
    Uint8List key,
    String messageId,
  ) async {
    if (messageId == _sourceMessage.id) {
      return const <Attachment>[_sharedAttachment];
    }
    return const <Attachment>[];
  }

  @override
  Future<List<Attachment>> listTodoActivityAttachments(
    Uint8List key,
    String activityId,
  ) async {
    if (activityId == _noteActivity.id) {
      return const <Attachment>[_sharedAttachment];
    }
    return const <Attachment>[];
  }
}
