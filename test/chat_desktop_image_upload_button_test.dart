import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:secondloop/core/backend/app_backend.dart';
import 'package:secondloop/core/backend/native_backend.dart';
import 'package:secondloop/core/session/session_scope.dart';
import 'package:secondloop/features/chat/chat_page.dart';
import 'package:secondloop/src/rust/db.dart';

import 'test_i18n.dart';

void main() {
  testWidgets('Desktop: attach button uploads image attachment',
      (tester) async {
    final oldPlatform = debugDefaultTargetPlatformOverride;
    FilePicker? oldPicker;
    try {
      oldPicker = FilePicker.platform;
    } catch (_) {
      oldPicker = null;
    }
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    try {
      final backend = _TestBackend();
      FilePicker.platform = _TestFilePicker(
        result: FilePickerResult([
          PlatformFile(
            name: 'photo.png',
            size: _tinyPngBytes().length,
            bytes: _tinyPngBytes(),
          ),
        ]),
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
                    title: 'Chat',
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

      expect(find.byKey(const ValueKey('chat_attach')), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('chat_attach')));
      await tester.pumpAndSettle();

      expect(
          find.byKey(const ValueKey('chat_attach_pick_media')), findsNothing);

      expect(backend.insertAttachmentCalls, 1);
      expect(backend.linkCalls, 1);
      expect(backend.insertMessageCalls, 1);
    } finally {
      FilePicker.platform = oldPicker ?? _TestFilePicker(result: null);
      debugDefaultTargetPlatformOverride = oldPlatform;
    }
  });
}

Uint8List _tinyPngBytes() {
  // 1x1 transparent PNG.
  const b64 =
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMBApGq4QAAAABJRU5ErkJggg==';
  return Uint8List.fromList(base64Decode(b64));
}

final class _TestFilePicker extends FilePicker {
  _TestFilePicker({required this.result});

  final FilePickerResult? result;

  @override
  Future<FilePickerResult?> pickFiles({
    Function(FilePickerStatus)? onFileLoading,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    bool allowMultiple = false,
    bool withData = false,
    bool withReadStream = false,
    bool allowCompression = true,
    int compressionQuality = 30,
    String? dialogTitle,
    String? initialDirectory,
    bool lockParentWindow = false,
    bool readSequential = false,
  }) async {
    return result;
  }
}

final class _TestBackend extends NativeAppBackend {
  _TestBackend() : super(appDirProvider: () async => '/tmp/secondloop_test');

  int insertAttachmentCalls = 0;
  int insertMessageCalls = 0;
  int linkCalls = 0;

  int _messageSeq = 0;
  int _attachmentSeq = 0;

  final List<Message> _messages = <Message>[];
  final Map<String, List<Attachment>> _attachmentsByMessageId =
      <String, List<Attachment>>{};
  final Map<String, Uint8List> _attachmentBytesBySha = <String, Uint8List>{};

  @override
  Future<List<Message>> listMessages(
      Uint8List key, String conversationId) async {
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
    final bytes = _attachmentBytesBySha[attachmentSha256];
    const mimeType = 'image/png';
    final attachment = Attachment(
      sha256: attachmentSha256,
      mimeType: mimeType,
      path: 'attachments/$attachmentSha256.bin',
      byteLen: bytes?.length ?? 0,
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
    return _attachmentBytesBySha[sha256] ?? Uint8List(0);
  }
}
