import 'dart:convert';
import 'dart:io';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:secondloop/core/backend/app_backend.dart';
import 'package:secondloop/core/backend/attachments_backend.dart';
import 'package:secondloop/core/backend/native_backend.dart';
import 'package:secondloop/core/session/session_scope.dart';
import 'package:secondloop/features/chat/chat_page.dart';
import 'package:secondloop/features/share/share_ingest.dart';
import 'package:secondloop/src/rust/db.dart';

import '../test/test_backend.dart';
import '../test/test_i18n.dart';

void main() {
  testWidgets('Chat desktop drop sends one message with multi attachments',
      (tester) async {
    final oldPlatform = debugDefaultTargetPlatformOverride;
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    try {
      final backend = _ChatIntegrationBackend();
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

      expect(backend.insertAttachmentCalls, 0);
      expect(backend.insertMessageCalls, 0);
      expect(backend.linkCalls, 0);
      expect(find.byType(InputChip), findsNWidgets(2));

      await tester.tap(find.byKey(const ValueKey('chat_send')));
      await tester.pump();
      await _pumpUntil(tester, () => backend.linkCalls >= 2);

      expect(backend.insertMessageCalls, 1);
      expect(backend.insertAttachmentCalls, 2);
      expect(backend.linkCalls, 2);
    } finally {
      debugDefaultTargetPlatformOverride = oldPlatform;
    }
  });

  testWidgets('Share drain batches multi files into one message',
      (tester) async {
    SharedPreferences.setMockInitialValues({});

    final backend = _ShareIntegrationBackend();
    final sessionKey = Uint8List.fromList(List<int>.filled(32, 7));

    final dir = await Directory.systemTemp.createTemp('secondloop_share_it_');
    addTearDown(() async => dir.delete(recursive: true));

    final fileA = File('${dir.path}/a.txt');
    await fileA.writeAsString('A');
    final fileB = File('${dir.path}/b.txt');
    await fileB.writeAsString('B');

    await ShareIngest.enqueueText('from-share');
    await ShareIngest.enqueueFile(
      tempPath: fileA.path,
      mimeType: 'text/plain',
      filename: 'a.txt',
    );
    await ShareIngest.enqueueFile(
      tempPath: fileB.path,
      mimeType: 'text/plain',
      filename: 'b.txt',
    );

    final processed = await ShareIngest.drainQueue(
      backend,
      sessionKey,
      onFile: (path, _, __) async {
        if (path.endsWith('a.txt')) return 'sha_a';
        if (path.endsWith('b.txt')) return 'sha_b';
        return 'sha_unknown';
      },
    );

    expect(processed, 3);
    expect(backend.insertedContents, const <String>['from-share']);
    expect(backend.linkCalls, const <String>['m1:sha_a', 'm1:sha_b']);
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

final class _ChatIntegrationBackend extends NativeAppBackend {
  _ChatIntegrationBackend()
      : super(appDirProvider: () async => '/tmp/secondloop_test');

  int insertAttachmentCalls = 0;
  int insertMessageCalls = 0;
  int linkCalls = 0;

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
    insertAttachmentCalls++;
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
  ) async =>
      const <Attachment>[];

  @override
  Future<Uint8List> readAttachmentBytes(
    Uint8List key, {
    required String sha256,
  }) async =>
      _attachmentBytesBySha[sha256] ?? Uint8List(0);
}

final class _ShareIntegrationBackend extends TestAppBackend
    implements AttachmentsBackend {
  final List<String> insertedContents = <String>[];
  final List<String> linkCalls = <String>[];

  @override
  Future<Message> insertMessage(
    Uint8List key,
    String conversationId, {
    required String role,
    required String content,
  }) async {
    final message = await super.insertMessage(
      key,
      conversationId,
      role: role,
      content: content,
    );
    insertedContents.add(content);
    return message;
  }

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
  }) async {
    linkCalls.add('$messageId:$attachmentSha256');
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
