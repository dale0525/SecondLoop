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
import 'package:secondloop/features/attachments/attachment_ingest_pipeline.dart';
import 'package:secondloop/src/rust/db.dart';

import 'test_i18n.dart';

void main() {
  testWidgets('Todo detail sends text and drafts in one linked message',
      (tester) async {
    final oldPlatform = debugDefaultTargetPlatformOverride;
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    try {
      final backend = _TodoDetailTestBackend();
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
      await tester.pumpAndSettle();

      final dropTarget = tester.widget<DropTarget>(
        find.byKey(const ValueKey('todo_detail_desktop_drop_target')),
      );
      dropTarget.onDragDone?.call(
        DropDoneDetails(
          files: [
            XFile.fromData(
              Uint8List.fromList(utf8.encode('alpha')),
              name: 'one.txt',
            ),
            XFile.fromData(
              Uint8List.fromList(utf8.encode('beta')),
              name: 'two.txt',
            ),
          ],
          localPosition: Offset.zero,
          globalPosition: Offset.zero,
        ),
      );
      await tester.pumpAndSettle();

      expect(backend.appendTodoNoteCalls, 0);
      expect(find.byType(InputChip), findsNWidgets(2));

      await tester.enterText(
        find.byKey(const ValueKey('todo_detail_input')),
        'follow-up',
      );
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('todo_detail_send')));
      await tester.pump();
      await _pumpUntil(tester, () => backend.linkTodoActivityCalls.length >= 2);

      expect(backend.appendTodoNoteCalls, 1);
      expect(backend.appendTodoNoteContents, const <String>['follow-up']);
      expect(backend.createdActivities.length, 1);
      expect(backend.createdActivities.single.sourceMessageId, isNotEmpty);
      expect(backend.linkTodoActivityCalls.length, 2);
      expect(backend.linkMessageCalls.length, 2);
      expect(find.byType(InputChip), findsNothing);
    } finally {
      debugDefaultTargetPlatformOverride = oldPlatform;
    }
  });

  testWidgets('Todo detail keeps failed drafts for retry after partial success',
      (tester) async {
    final oldPlatform = debugDefaultTargetPlatformOverride;
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    try {
      final backend = _TodoDetailTestBackend(
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
      await tester.pumpAndSettle();

      final dropTarget = tester.widget<DropTarget>(
        find.byKey(const ValueKey('todo_detail_desktop_drop_target')),
      );
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

      await tester.enterText(
        find.byKey(const ValueKey('todo_detail_input')),
        'follow-up',
      );
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('todo_detail_send')));
      await tester.pump();
      await _pumpUntil(tester, () => backend.appendTodoNoteCalls >= 1);
      await tester.pump(const Duration(milliseconds: 200));

      expect(backend.appendTodoNoteCalls, 1);
      expect(backend.linkTodoActivityCalls.length, 1);
      expect(backend.linkMessageCalls.length, 1);
      expect(find.byType(InputChip), findsOneWidget);
    } finally {
      debugDefaultTargetPlatformOverride = oldPlatform;
    }
  });

  testWidgets('Todo detail attachment-only send keeps empty note text',
      (tester) async {
    final oldPlatform = debugDefaultTargetPlatformOverride;
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    try {
      final backend = _TodoDetailTestBackend();
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
      await tester.pumpAndSettle();

      final dropTarget = tester.widget<DropTarget>(
        find.byKey(const ValueKey('todo_detail_desktop_drop_target')),
      );
      dropTarget.onDragDone?.call(
        DropDoneDetails(
          files: [
            XFile.fromData(
              Uint8List.fromList(utf8.encode('alpha')),
              name: 'one.txt',
            ),
          ],
          localPosition: Offset.zero,
          globalPosition: Offset.zero,
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('todo_detail_send')));
      await tester.pump();
      await _pumpUntil(tester, () => backend.linkTodoActivityCalls.isNotEmpty);

      expect(backend.appendTodoNoteCalls, 1);
      expect(backend.appendTodoNoteContents, const <String>['']);
      expect(backend.linkTodoActivityCalls.length, 1);
      expect(backend.linkMessageCalls.length, 1);
    } finally {
      debugDefaultTargetPlatformOverride = oldPlatform;
    }
  });

  testWidgets('Todo detail pure URL text sends linked url attachment',
      (tester) async {
    final oldPlatform = debugDefaultTargetPlatformOverride;
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    try {
      final backend = _TodoDetailTestBackend();
      const url = 'https://example.com/docs';
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
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const ValueKey('todo_detail_input')),
        url,
      );
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('todo_detail_send')));
      await tester.pump();
      await _pumpUntil(tester, () => backend.linkTodoActivityCalls.isNotEmpty);

      expect(backend.appendTodoNoteCalls, 1);
      expect(backend.appendTodoNoteContents, const <String>[url]);
      expect(backend.linkTodoActivityCalls.length, 1);
      expect(backend.linkMessageCalls.length, 1);
      expect(
          backend.insertedMimeTypes, contains(kSecondLoopUrlManifestMimeType));
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

final class _TodoDetailTestBackend extends NativeAppBackend {
  _TodoDetailTestBackend({
    this.failIngestForPayloadContains,
  }) : super(appDirProvider: () async => '/tmp/secondloop_test');

  final String? failIngestForPayloadContains;
  final List<TodoActivity> createdActivities = <TodoActivity>[];
  final List<String> appendTodoNoteContents = <String>[];
  final List<String> linkMessageCalls = <String>[];
  final List<String> linkTodoActivityCalls = <String>[];
  final List<String> insertedMimeTypes = <String>[];
  final Map<String, Message> _messagesById = <String, Message>{};
  final Map<String, Uint8List> _attachmentBytesBySha = <String, Uint8List>{};
  final Map<String, String> _attachmentMimeTypeBySha = <String, String>{};
  final Map<String, List<Attachment>> _attachmentsByMessageId =
      <String, List<Attachment>>{};

  int appendTodoNoteCalls = 0;
  int _messageSeq = 0;
  int _activitySeq = 0;
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
  ) async {
    return createdActivities
        .where((activity) => activity.todoId == todoId)
        .toList(growable: false);
  }

  @override
  Future<List<Attachment>> listTodoActivityAttachments(
    Uint8List key,
    String activityId,
  ) async =>
      const <Attachment>[];

  @override
  Future<TodoActivity> appendTodoNote(
    Uint8List key, {
    required String todoId,
    required String content,
    String? sourceMessageId,
  }) async {
    appendTodoNoteCalls++;
    appendTodoNoteContents.add(content);
    final resolvedSourceMessageId = 'm${++_messageSeq}';
    _messagesById[resolvedSourceMessageId] = Message(
      id: resolvedSourceMessageId,
      conversationId: 'loop_home',
      role: 'user',
      content: content,
      createdAtMs: appendTodoNoteCalls,
      isMemory: true,
    );
    final activity = TodoActivity(
      id: 'a${++_activitySeq}',
      todoId: todoId,
      activityType: 'note',
      content: content,
      sourceMessageId: resolvedSourceMessageId,
      createdAtMs: appendTodoNoteCalls,
    );
    createdActivities.add(activity);
    return activity;
  }

  @override
  Future<Message?> getMessageById(Uint8List key, String messageId) async {
    return _messagesById[messageId];
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
    _attachmentMimeTypeBySha[sha] = mimeType;
    insertedMimeTypes.add(mimeType);
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
    linkMessageCalls.add('$messageId:$attachmentSha256');
    final bytes = _attachmentBytesBySha[attachmentSha256];
    final attachment = Attachment(
      sha256: attachmentSha256,
      mimeType: _attachmentMimeTypeBySha[attachmentSha256] ??
          'application/octet-stream',
      path: 'attachments/$attachmentSha256.bin',
      byteLen: bytes?.length ?? 0,
      createdAtMs: 0,
    );
    (_attachmentsByMessageId[messageId] ??= <Attachment>[]).add(attachment);
  }

  @override
  Future<void> linkAttachmentToTodoActivity(
    Uint8List key, {
    required String activityId,
    required String attachmentSha256,
  }) async {
    linkTodoActivityCalls.add('$activityId:$attachmentSha256');
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
    return _attachmentBytesBySha[sha256] ?? Uint8List(0);
  }
}
