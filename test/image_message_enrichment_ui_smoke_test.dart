import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:secondloop/core/backend/app_backend.dart';
import 'package:secondloop/core/backend/attachments_backend.dart';
import 'package:secondloop/core/session/session_scope.dart';
import 'package:secondloop/features/chat/chat_page.dart';
import 'package:secondloop/src/rust/db.dart';

import 'test_i18n.dart';

void main() {
  testWidgets('Image message shows location + caption enrichment',
      (tester) async {
    const longCaption =
        '浦东的屋檐漫动了工作或学习空间。前景中，一个透明塑料杯充当笔筒，里面塞满了各种文具，包括一支标有“Surgical skin marker”（手术皮肤标记笔）的黑笔。'
        '浦东的屋檐漫动了工作或学习空间。前景中，一个透明塑料杯充当笔筒，里面塞满了各种文具，包括一支标有“Surgical skin marker”（手术皮肤标记笔）的黑笔。';
    final backend = _Backend(
      messages: const [
        Message(
          id: 'm1',
          conversationId: 'loop_home',
          role: 'user',
          content: '',
          createdAtMs: 123,
          isMemory: true,
        ),
      ],
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
      placeDisplayNameBySha: const {
        'abc': 'Seattle',
      },
      captionLongBySha: const {
        'abc': longCaption,
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
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('chat_image_enrichment_location_abc')),
      findsOneWidget,
    );
    expect(find.text('Seattle'), findsOneWidget);

    expect(
      find.byKey(const ValueKey('chat_image_enrichment_caption_abc')),
      findsOneWidget,
    );
    expect(find.text(longCaption), findsOneWidget);

    final thumbSize =
        tester.getSize(find.byKey(const ValueKey('chat_attachment_image_abc')));
    final captionSize = tester.getSize(
        find.byKey(const ValueKey('chat_image_enrichment_caption_abc')));
    expect(captionSize.width, thumbSize.width);
  });
}

Uint8List _tinyPngBytes() {
  // 1x1 transparent PNG.
  const b64 =
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMBApGq4QAAAABJRU5ErkJggg==';
  return Uint8List.fromList(base64Decode(b64));
}

final class _Backend extends AppBackend implements AttachmentsBackend {
  _Backend({
    required List<Message> messages,
    required Map<String, List<Attachment>> attachmentsByMessageId,
    required Map<String, Uint8List> attachmentBytesBySha,
    required Map<String, String?> placeDisplayNameBySha,
    required Map<String, String?> captionLongBySha,
  })  : _messages = List<Message>.from(messages),
        _attachmentsByMessageId = Map<String, List<Attachment>>.fromEntries(
          attachmentsByMessageId.entries.map(
            (e) => MapEntry(e.key, List<Attachment>.from(e.value)),
          ),
        ),
        _attachmentBytesBySha =
            Map<String, Uint8List>.from(attachmentBytesBySha),
        _placeDisplayNameBySha =
            Map<String, String?>.from(placeDisplayNameBySha),
        _captionLongBySha = Map<String, String?>.from(captionLongBySha);

  final List<Message> _messages;
  final Map<String, List<Attachment>> _attachmentsByMessageId;
  final Map<String, Uint8List> _attachmentBytesBySha;
  final Map<String, String?> _placeDisplayNameBySha;
  final Map<String, String?> _captionLongBySha;

  @override
  Future<void> init() async {}

  @override
  Future<bool> isMasterPasswordSet() async => true;

  @override
  Future<bool> readAutoUnlockEnabled() async => true;

  @override
  Future<void> persistAutoUnlockEnabled({required bool enabled}) async {}

  @override
  Future<Uint8List?> loadSavedSessionKey() async => null;

  @override
  Future<void> saveSessionKey(Uint8List key) async {}

  @override
  Future<void> clearSavedSessionKey() async {}

  @override
  Future<void> validateKey(Uint8List key) async {}

  @override
  Future<Uint8List> initMasterPassword(String password) async =>
      Uint8List.fromList(List<int>.filled(32, 1));

  @override
  Future<Uint8List> unlockWithPassword(String password) async =>
      Uint8List.fromList(List<int>.filled(32, 1));

  @override
  Future<List<Conversation>> listConversations(Uint8List key) async => const [];

  @override
  Future<Conversation> createConversation(Uint8List key, String title) =>
      throw UnimplementedError();

  @override
  Future<Conversation> getOrCreateLoopHomeConversation(Uint8List key) =>
      throw UnimplementedError();

  @override
  Future<List<Message>> listMessages(
          Uint8List key, String conversationId) async =>
      List<Message>.from(_messages);

  @override
  Future<Message> insertMessage(
    Uint8List key,
    String conversationId, {
    required String role,
    required String content,
  }) =>
      throw UnimplementedError();

  @override
  Future<void> editMessage(Uint8List key, String messageId, String content) =>
      throw UnimplementedError();

  @override
  Future<void> setMessageDeleted(
          Uint8List key, String messageId, bool isDeleted) =>
      throw UnimplementedError();

  @override
  Future<void> resetVaultDataPreservingLlmProfiles(Uint8List key) async {}

  @override
  Future<int> processPendingMessageEmbeddings(Uint8List key,
          {int limit = 32}) async =>
      0;

  @override
  Future<List<SimilarMessage>> searchSimilarMessages(
    Uint8List key,
    String query, {
    int topK = 10,
  }) async =>
      const <SimilarMessage>[];

  @override
  Future<int> rebuildMessageEmbeddings(
    Uint8List key, {
    int batchLimit = 256,
  }) async =>
      0;

  @override
  Future<List<String>> listEmbeddingModelNames(Uint8List key) async =>
      const <String>['secondloop-default-embed-v0'];

  @override
  Future<String> getActiveEmbeddingModelName(Uint8List key) async =>
      'secondloop-default-embed-v0';

  @override
  Future<bool> setActiveEmbeddingModelName(Uint8List key, String modelName) =>
      Future<bool>.value(modelName != 'secondloop-default-embed-v0');

  @override
  Future<List<LlmProfile>> listLlmProfiles(Uint8List key) async =>
      const <LlmProfile>[];

  @override
  Future<LlmProfile> createLlmProfile(
    Uint8List key, {
    required String name,
    required String providerType,
    String? baseUrl,
    String? apiKey,
    required String modelName,
    bool setActive = true,
  }) async =>
      throw UnimplementedError();

  @override
  Future<void> setActiveLlmProfile(Uint8List key, String profileId) async {}

  @override
  Future<void> deleteLlmProfile(Uint8List key, String profileId) async {}

  @override
  Stream<String> askAiStream(
    Uint8List key,
    String conversationId, {
    required String question,
    int topK = 10,
    bool thisThreadOnly = false,
  }) =>
      const Stream<String>.empty();

  @override
  Stream<String> askAiStreamCloudGateway(
    Uint8List key,
    String conversationId, {
    required String question,
    int topK = 10,
    bool thisThreadOnly = false,
    required String gatewayBaseUrl,
    required String idToken,
    required String modelName,
  }) =>
      const Stream<String>.empty();

  @override
  Future<Uint8List> deriveSyncKey(String passphrase) async =>
      Uint8List.fromList(List<int>.filled(32, 9));

  @override
  Future<void> syncWebdavTestConnection({
    required String baseUrl,
    String? username,
    String? password,
    required String remoteRoot,
  }) async {}

  @override
  Future<void> syncWebdavClearRemoteRoot({
    required String baseUrl,
    String? username,
    String? password,
    required String remoteRoot,
  }) async {}

  @override
  Future<int> syncWebdavPush(
    Uint8List key,
    Uint8List syncKey, {
    required String baseUrl,
    String? username,
    String? password,
    required String remoteRoot,
  }) async =>
      0;

  @override
  Future<int> syncWebdavPull(
    Uint8List key,
    Uint8List syncKey, {
    required String baseUrl,
    String? username,
    String? password,
    required String remoteRoot,
  }) async =>
      0;

  @override
  Future<void> syncLocaldirTestConnection({
    required String localDir,
    required String remoteRoot,
  }) async {}

  @override
  Future<void> syncLocaldirClearRemoteRoot({
    required String localDir,
    required String remoteRoot,
  }) async {}

  @override
  Future<int> syncLocaldirPush(
    Uint8List key,
    Uint8List syncKey, {
    required String localDir,
    required String remoteRoot,
  }) async =>
      0;

  @override
  Future<int> syncLocaldirPull(
    Uint8List key,
    Uint8List syncKey, {
    required String localDir,
    required String remoteRoot,
  }) async =>
      0;

  @override
  Future<int> syncManagedVaultPush(
    Uint8List key,
    Uint8List syncKey, {
    required String baseUrl,
    required String vaultId,
    required String idToken,
  }) async =>
      0;

  @override
  Future<int> syncManagedVaultPull(
    Uint8List key,
    Uint8List syncKey, {
    required String baseUrl,
    required String vaultId,
    required String idToken,
  }) async =>
      0;

  @override
  Future<AttachmentExifMetadata?> readAttachmentExifMetadata(
    Uint8List key, {
    required String sha256,
  }) async =>
      null;

  @override
  Future<List<Attachment>> listRecentAttachments(Uint8List key,
          {int limit = 50}) async =>
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
  ) async =>
      List<Attachment>.from(_attachmentsByMessageId[messageId] ?? const []);

  @override
  Future<Uint8List> readAttachmentBytes(
    Uint8List key, {
    required String sha256,
  }) async {
    final bytes = _attachmentBytesBySha[sha256];
    if (bytes == null) {
      throw StateError('missing_bytes:$sha256');
    }
    return bytes;
  }

  @override
  Future<String?> readAttachmentPlaceDisplayName(
    Uint8List key, {
    required String sha256,
  }) async =>
      _placeDisplayNameBySha[sha256];

  @override
  Future<String?> readAttachmentAnnotationCaptionLong(
    Uint8List key, {
    required String sha256,
  }) async =>
      _captionLongBySha[sha256];
}
