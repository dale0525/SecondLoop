import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart';

import '../../src/rust/db.dart';
import 'attachments_backend.dart';
import 'app_backend.dart';

abstract interface class CloudWebChatClient {
  Future<String> sendMessages({
    required String idToken,
    required String gatewayBaseUrl,
    required String modelName,
    required List<Map<String, String>> messages,
  });
}

final class UnsupportedCloudWebChatClient implements CloudWebChatClient {
  const UnsupportedCloudWebChatClient();

  @override
  Future<String> sendMessages({
    required String idToken,
    required String gatewayBaseUrl,
    required String modelName,
    required List<Map<String, String>> messages,
  }) {
    throw UnsupportedError('cloud chat is not available in web');
  }
}

final class CloudWebBackend extends AppBackend implements AttachmentsBackend {
  CloudWebBackend({
    required this.chatClient,
    int Function()? nowMs,
  }) : _nowMs = nowMs ?? (() => DateTime.now().millisecondsSinceEpoch);

  final CloudWebChatClient chatClient;
  final int Function() _nowMs;

  final List<Conversation> _conversations = <Conversation>[];
  final Map<String, List<Message>> _messagesByConversation =
      <String, List<Message>>{};
  final Map<String, Attachment> _attachmentsBySha = <String, Attachment>{};
  final Map<String, Uint8List> _attachmentBytesBySha = <String, Uint8List>{};
  final Map<String, List<String>> _attachmentShasByMessageId =
      <String, List<String>>{};
  var _idCounter = 0;

  Future<T> _unsupportedFuture<T>(String feature) {
    return Future<T>.error(
        UnsupportedError('$feature is not available in web'));
  }

  Stream<T> _unsupportedStream<T>(String feature) {
    return Stream<T>.error(
        UnsupportedError('$feature is not available in web'));
  }

  String _nextId(String prefix) {
    _idCounter += 1;
    return '$prefix-$_idCounter';
  }

  int _touchNow() => _nowMs();

  PlatformInt64 _asPlatformInt64(int value) => PlatformInt64Util.from(value);

  Conversation _replaceConversation(Conversation next) {
    final index = _conversations.indexWhere((item) => item.id == next.id);
    if (index >= 0) {
      _conversations[index] = next;
    } else {
      _conversations.add(next);
    }
    return next;
  }

  Conversation? _conversationById(String id) {
    for (final conversation in _conversations) {
      if (conversation.id == id) return conversation;
    }
    return null;
  }

  void _ensureConversationExists(String conversationId) {
    if (_conversationById(conversationId) == null) {
      throw StateError('unknown_conversation:$conversationId');
    }
  }

  void rememberAttachment(Attachment attachment, {Uint8List? bytes}) {
    _attachmentsBySha[attachment.sha256] = attachment;
    if (bytes != null) {
      _attachmentBytesBySha[attachment.sha256] = Uint8List.fromList(bytes);
    }
  }

  List<Message> _messageBucket(String conversationId) {
    return _messagesByConversation.putIfAbsent(
      conversationId,
      () => <Message>[],
    );
  }

  @override
  Future<void> init() async {}

  @override
  Future<bool> isMasterPasswordSet() async => false;

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
  Future<Uint8List> initMasterPassword(String password) {
    return _unsupportedFuture<Uint8List>('master password setup');
  }

  @override
  Future<Uint8List> unlockWithPassword(String password) {
    return _unsupportedFuture<Uint8List>('password unlock');
  }

  @override
  Future<List<Conversation>> listConversations(Uint8List key) async {
    final copy = List<Conversation>.of(_conversations);
    copy.sort((left, right) => right.updatedAtMs.compareTo(left.updatedAtMs));
    return copy;
  }

  @override
  Future<Conversation> createConversation(Uint8List key, String title) async {
    final now = _touchNow();
    final conversation = Conversation(
      id: _nextId('conversation'),
      title: title,
      createdAtMs: _asPlatformInt64(now),
      updatedAtMs: _asPlatformInt64(now),
    );
    _messageBucket(conversation.id);
    return _replaceConversation(conversation);
  }

  @override
  Future<Conversation> getOrCreateLoopHomeConversation(Uint8List key) async {
    const loopHomeId = 'loop-home';
    final existing = _conversationById(loopHomeId);
    if (existing != null) return existing;

    final now = _touchNow();
    final conversation = Conversation(
      id: loopHomeId,
      title: 'Loop Home',
      createdAtMs: _asPlatformInt64(now),
      updatedAtMs: _asPlatformInt64(now),
    );
    _messageBucket(conversation.id);
    return _replaceConversation(conversation);
  }

  @override
  Future<List<Message>> listMessages(
      Uint8List key, String conversationId) async {
    _ensureConversationExists(conversationId);
    return List<Message>.of(_messageBucket(conversationId));
  }

  @override
  Future<Message> insertMessage(
    Uint8List key,
    String conversationId, {
    required String role,
    required String content,
  }) async {
    _ensureConversationExists(conversationId);
    final now = _touchNow();
    final message = Message(
      id: _nextId('message'),
      conversationId: conversationId,
      role: role,
      content: content,
      createdAtMs: _asPlatformInt64(now),
      isMemory: false,
    );
    _messageBucket(conversationId).add(message);

    final conversation = _conversationById(conversationId)!;
    _replaceConversation(
      Conversation(
        id: conversation.id,
        title: conversation.title,
        createdAtMs: conversation.createdAtMs,
        updatedAtMs: _asPlatformInt64(now),
      ),
    );
    return message;
  }

  @override
  Future<void> editMessage(
      Uint8List key, String messageId, String content) async {
    for (final entry in _messagesByConversation.entries) {
      final index =
          entry.value.indexWhere((message) => message.id == messageId);
      if (index < 0) continue;
      final current = entry.value[index];
      entry.value[index] = Message(
        id: current.id,
        conversationId: current.conversationId,
        role: current.role,
        content: content,
        createdAtMs: current.createdAtMs,
        isMemory: current.isMemory,
      );
      return;
    }
    throw StateError('unknown_message:$messageId');
  }

  @override
  Future<void> setMessageDeleted(
    Uint8List key,
    String messageId,
    bool isDeleted,
  ) async {
    for (final entry in _messagesByConversation.entries) {
      entry.value
          .removeWhere((message) => message.id == messageId && isDeleted);
    }
  }

  @override
  Future<void> resetVaultDataPreservingLlmProfiles(Uint8List key) async {
    _conversations.clear();
    _messagesByConversation.clear();
    _attachmentsBySha.clear();
    _attachmentBytesBySha.clear();
    _attachmentShasByMessageId.clear();
  }

  @override
  Future<Attachment?> readAttachmentBySha256(String attachmentSha256) async {
    final normalizedSha = attachmentSha256.trim();
    if (normalizedSha.isEmpty) return null;
    return _attachmentsBySha[normalizedSha];
  }

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

  @override
  Future<AttachmentExifMetadata?> readAttachmentExifMetadata(
    Uint8List key, {
    required String sha256,
  }) async =>
      null;

  @override
  Future<List<Attachment>> listRecentAttachments(
    Uint8List key, {
    int limit = 50,
  }) async {
    final items = _attachmentsBySha.values.toList(growable: false)
      ..sort((left, right) => right.createdAtMs.compareTo(left.createdAtMs));
    return items.take(limit).toList(growable: false);
  }

  @override
  Future<void> linkAttachmentToMessage(
    Uint8List key,
    String messageId, {
    required String attachmentSha256,
  }) async {
    final bucket =
        _attachmentShasByMessageId.putIfAbsent(messageId, () => <String>[]);
    if (!bucket.contains(attachmentSha256)) {
      bucket.add(attachmentSha256);
    }
  }

  @override
  Future<List<Attachment>> listMessageAttachments(
    Uint8List key,
    String messageId,
  ) async {
    final shas = _attachmentShasByMessageId[messageId] ?? const <String>[];
    return shas
        .map((sha) => _attachmentsBySha[sha])
        .whereType<Attachment>()
        .toList(growable: false);
  }

  @override
  Future<Uint8List> readAttachmentBytes(
    Uint8List key, {
    required String sha256,
  }) async {
    final normalizedSha = sha256.trim();
    final bytes = _attachmentBytesBySha[normalizedSha];
    if (bytes == null) {
      throw StateError('missing_attachment_bytes:$normalizedSha');
    }
    return Uint8List.fromList(bytes);
  }

  @override
  Future<int> processPendingMessageEmbeddings(
    Uint8List key, {
    int limit = 32,
  }) async =>
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
      const <String>[];

  @override
  Future<String> getActiveEmbeddingModelName(Uint8List key) {
    return _unsupportedFuture<String>('embedding model selection');
  }

  @override
  Future<bool> setActiveEmbeddingModelName(
          Uint8List key, String modelName) async =>
      false;

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
  }) {
    return _unsupportedFuture<LlmProfile>('llm profile creation');
  }

  @override
  Future<void> setActiveLlmProfile(Uint8List key, String profileId) {
    return _unsupportedFuture<void>('llm profile selection');
  }

  @override
  Future<void> deleteLlmProfile(Uint8List key, String profileId) {
    return _unsupportedFuture<void>('llm profile deletion');
  }

  @override
  Stream<String> askAiStream(
    Uint8List key,
    String conversationId, {
    required String question,
    int topK = 10,
    bool thisThreadOnly = false,
  }) {
    return _unsupportedStream<String>('local ask ai');
  }

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
  }) async* {
    _ensureConversationExists(conversationId);
    await insertMessage(
      key,
      conversationId,
      role: 'user',
      content: question,
    );
    final history = await listMessages(key, conversationId);
    final replyText = await chatClient.sendMessages(
      idToken: idToken,
      gatewayBaseUrl: gatewayBaseUrl,
      modelName: modelName,
      messages: history
          .map(
            (message) => <String, String>{
              'role': message.role,
              'content': message.content,
            },
          )
          .toList(growable: false),
    );
    await insertMessage(
      key,
      conversationId,
      role: 'assistant',
      content: replyText,
    );
    yield replyText;
  }

  @override
  Future<String> taskPriorityRerankAiCloudGateway(
    Uint8List key, {
    required String prompt,
    required String gatewayBaseUrl,
    required String idToken,
    required String modelName,
  }) {
    return chatClient.sendMessages(
      idToken: idToken,
      gatewayBaseUrl: gatewayBaseUrl,
      modelName: modelName,
      messages: <Map<String, String>>[
        <String, String>{'role': 'user', 'content': prompt},
      ],
    );
  }

  @override
  Future<Uint8List> deriveSyncKey(String passphrase) {
    return _unsupportedFuture<Uint8List>('sync key derivation');
  }

  @override
  Future<void> syncWebdavTestConnection({
    required String baseUrl,
    String? username,
    String? password,
    required String remoteRoot,
  }) {
    return _unsupportedFuture<void>('webdav sync');
  }

  @override
  Future<void> syncWebdavClearRemoteRoot({
    required String baseUrl,
    String? username,
    String? password,
    required String remoteRoot,
  }) {
    return _unsupportedFuture<void>('webdav sync');
  }

  @override
  Future<int> syncWebdavPush(
    Uint8List key,
    Uint8List syncKey, {
    required String baseUrl,
    String? username,
    String? password,
    required String remoteRoot,
  }) {
    return _unsupportedFuture<int>('webdav sync');
  }

  @override
  Future<int> syncWebdavPull(
    Uint8List key,
    Uint8List syncKey, {
    required String baseUrl,
    String? username,
    String? password,
    required String remoteRoot,
  }) {
    return _unsupportedFuture<int>('webdav sync');
  }

  @override
  Future<void> syncLocaldirTestConnection({
    required String localDir,
    required String remoteRoot,
  }) {
    return _unsupportedFuture<void>('local dir sync');
  }

  @override
  Future<void> syncLocaldirClearRemoteRoot({
    required String localDir,
    required String remoteRoot,
  }) {
    return _unsupportedFuture<void>('local dir sync');
  }

  @override
  Future<int> syncLocaldirPush(
    Uint8List key,
    Uint8List syncKey, {
    required String localDir,
    required String remoteRoot,
  }) {
    return _unsupportedFuture<int>('local dir sync');
  }

  @override
  Future<int> syncLocaldirPull(
    Uint8List key,
    Uint8List syncKey, {
    required String localDir,
    required String remoteRoot,
  }) {
    return _unsupportedFuture<int>('local dir sync');
  }
}
