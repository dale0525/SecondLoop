import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:secondloop/core/backend/app_backend.dart';
import 'package:secondloop/core/backend/attachments_backend.dart';
import 'package:secondloop/core/session/session_scope.dart';
import 'package:secondloop/core/sync/sync_engine.dart';
import 'package:secondloop/core/sync/sync_engine_gate.dart';
import 'package:secondloop/features/chat/chat_page.dart';
import 'package:secondloop/src/rust/db.dart';

import 'test_backend.dart';
import 'test_i18n.dart';

void main() {
  testWidgets(
    'Chat image thumbnail stays visible during sync refresh',
    (tester) async {
      final backend = _Backend(
        initialMessages: const [
          Message(
            id: 'm1',
            conversationId: 'main_stream',
            role: 'user',
            content: 'Photo',
            createdAtMs: 0,
            isMemory: true,
          ),
        ],
        listMessagesDelay: const Duration(milliseconds: 120),
        listMessageAttachmentsDelay: const Duration(milliseconds: 120),
        attachmentsByMessageId: const {
          'm1': [
            Attachment(
              sha256: 'abc',
              mimeType: 'image/png',
              path: 'attachments/abc.bin',
              byteLen: 67,
              createdAtMs: 0,
            ),
          ],
        },
        attachmentBytesBySha: {
          'abc': _tinyPngBytes(),
        },
      );

      final engine = SyncEngine(
        syncRunner: _NoopRunner(),
        loadConfig: () async => null,
        pushDebounce: const Duration(days: 1),
        pullInterval: const Duration(days: 1),
        pullJitter: Duration.zero,
        pullOnStart: false,
      );

      const conversation = Conversation(
        id: 'main_stream',
        title: 'Main Stream',
        createdAtMs: 0,
        updatedAtMs: 0,
      );

      await tester.pumpWidget(
        AppBackendScope(
          backend: backend,
          child: SessionScope(
            sessionKey: Uint8List.fromList(List<int>.filled(32, 1)),
            lock: () {},
            child: SyncEngineScope(
              engine: engine,
              child: wrapWithI18n(
                const MaterialApp(home: ChatPage(conversation: conversation)),
              ),
            ),
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pumpAndSettle();

      final thumbnailFinder =
          find.byKey(const ValueKey('chat_attachment_image_abc'));
      expect(thumbnailFinder, findsOneWidget);

      engine.notifyExternalChange();
      await tester.pump();

      expect(thumbnailFinder, findsOneWidget);

      await tester.pump(const Duration(milliseconds: 200));
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pumpAndSettle();
      expect(thumbnailFinder, findsOneWidget);
    },
  );
}

Uint8List _tinyPngBytes() {
  // 1x1 transparent PNG.
  const b64 =
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMBApGq4QAAAABJRU5ErkJggg==';
  return Uint8List.fromList(base64Decode(b64));
}

final class _NoopRunner implements SyncRunner {
  @override
  Future<int> pull(SyncConfig config) async => 0;

  @override
  Future<int> push(SyncConfig config) async => 0;
}

final class _Backend extends TestAppBackend implements AttachmentsBackend {
  _Backend({
    required super.initialMessages,
    required this.attachmentsByMessageId,
    required Map<String, Uint8List> attachmentBytesBySha,
    this.listMessagesDelay = Duration.zero,
    this.listMessageAttachmentsDelay = Duration.zero,
  }) : _attachmentBytesBySha =
            Map<String, Uint8List>.from(attachmentBytesBySha);

  final Map<String, List<Attachment>> attachmentsByMessageId;
  final Map<String, Uint8List> _attachmentBytesBySha;
  final Duration listMessagesDelay;
  final Duration listMessageAttachmentsDelay;

  @override
  Future<List<Message>> listMessages(
      Uint8List key, String conversationId) async {
    final delay = listMessagesDelay;
    if (delay > Duration.zero) {
      await Future<void>.delayed(delay);
    }
    return super.listMessages(key, conversationId);
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
  }) async {}

  @override
  Future<List<Attachment>> listMessageAttachments(
    Uint8List key,
    String messageId,
  ) async {
    final delay = listMessageAttachmentsDelay;
    if (delay > Duration.zero) {
      await Future<void>.delayed(delay);
    }
    return List<Attachment>.from(
      attachmentsByMessageId[messageId] ?? const <Attachment>[],
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
