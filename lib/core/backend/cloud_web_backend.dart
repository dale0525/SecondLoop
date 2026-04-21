import 'dart:convert';
import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart';

import '../../src/rust/db.dart';
import 'attachments_backend.dart';
import 'app_backend.dart';

part 'cloud_web_backend_tasks_recurrence_mixin.dart';
part 'cloud_web_backend_tasks_mixin.dart';

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

final class CloudWebBackend extends AppBackend
    with _CloudWebBackendTasksRecurrenceMixin, _CloudWebBackendTasksMixin
    implements
        AttachmentsBackend,
        AssistantCitationWriteBackend,
        DetachedAskCompletionRecoveryBackend {
  CloudWebBackend({
    required this.chatClient,
    Future<Map<String, Object?>> Function({
      required String idToken,
      required String cacheScopeKey,
    })? fetchTaskPriorityAssessments,
    Future<void> Function({
      required String idToken,
      required Map<String, Object?> payload,
    })? upsertTaskPriorityAssessments,
    int Function()? nowMs,
  })  : _fetchTaskPriorityAssessments = fetchTaskPriorityAssessments,
        _upsertTaskPriorityAssessments = upsertTaskPriorityAssessments,
        _nowMs = nowMs ?? (() => DateTime.now().millisecondsSinceEpoch);

  final CloudWebChatClient chatClient;
  final Future<Map<String, Object?>> Function({
    required String idToken,
    required String cacheScopeKey,
  })? _fetchTaskPriorityAssessments;
  final Future<void> Function({
    required String idToken,
    required Map<String, Object?> payload,
  })? _upsertTaskPriorityAssessments;
  final int Function() _nowMs;

  final List<Conversation> _conversations = <Conversation>[];
  final Map<String, List<Message>> _messagesByConversation =
      <String, List<Message>>{};
  final Map<String, Event> _eventsById = <String, Event>{};
  @override
  final Map<String, Attachment> _attachmentsBySha = <String, Attachment>{};
  final Map<String, Uint8List> _attachmentBytesBySha = <String, Uint8List>{};
  final Map<String, List<String>> _attachmentShasByMessageId =
      <String, List<String>>{};
  final Map<String, _DeletedMessageSnapshot> _deletedMessagesById =
      <String, _DeletedMessageSnapshot>{};
  final Set<String> _detachedAskCompletionClaims = <String>{};
  var _idCounter = 0;

  Future<T> _unsupportedFuture<T>(String feature) {
    return Future<T>.error(
        UnsupportedError('$feature is not available in web'));
  }

  Stream<T> _unsupportedStream<T>(String feature) {
    return Stream<T>.error(
        UnsupportedError('$feature is not available in web'));
  }

  @override
  String _nextId(String prefix) {
    _idCounter += 1;
    return '$prefix-$_idCounter';
  }

  @override
  int _touchNow() => _nowMs();

  @override
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

  int _compareEventOrder(Event left, Event right) {
    final byStart = left.startAtMs.compareTo(right.startAtMs);
    if (byStart != 0) {
      return byStart;
    }
    final byEnd = left.endAtMs.compareTo(right.endAtMs);
    if (byEnd != 0) {
      return byEnd;
    }
    return left.id.compareTo(right.id);
  }

  void clearWebSessionState() {
    _conversations.clear();
    _messagesByConversation.clear();
    _eventsById.clear();
    _attachmentsBySha.clear();
    _attachmentBytesBySha.clear();
    _attachmentShasByMessageId.clear();
    _todosById.clear();
    _todoActivitiesById.clear();
    _checklistItemsByTodoId.clear();
    _todoChecklistSuggestionsByTodoId.clear();
    _attachmentShasByTodoActivityId.clear();
    _todoRecurrenceRuleJsonByTodoId.clear();
    _todoRecurrenceSeriesIdByTodoId.clear();
    _todoRecurrenceOccurrenceIndexByTodoId.clear();
    _deletedMessagesById.clear();
    _detachedAskCompletionClaims.clear();
    _idCounter = 0;
  }

  List<Message> _messageBucket(String conversationId) {
    return _messagesByConversation.putIfAbsent(
      conversationId,
      () => <Message>[],
    );
  }

  Message _appendMessage(
    String conversationId, {
    required String role,
    required String content,
    required bool isMemory,
    String? citationsJson,
  }) {
    _ensureConversationExists(conversationId);
    final now = _touchNow();
    final message = Message(
      id: _nextId('message'),
      conversationId: conversationId,
      role: role,
      content: content,
      createdAtMs: _asPlatformInt64(now),
      isMemory: isMemory,
      citationsJson: citationsJson,
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
  Future<List<Event>> listEvents(Uint8List key) async {
    final events = _eventsById.values.toList(growable: false)
      ..sort(_compareEventOrder);
    return events;
  }

  @override
  Future<Event?> getEventById(Uint8List key, String eventId) async {
    return _eventsById[eventId];
  }

  @override
  Future<Event> upsertEvent(
    Uint8List key, {
    required String id,
    required String title,
    required int startAtMs,
    required int endAtMs,
    required String tz,
    String? sourceEntryId,
  }) async {
    final now = _touchNow();
    final existing = _eventsById[id];
    final event = Event(
      id: id,
      title: title,
      startAtMs: _asPlatformInt64(startAtMs),
      endAtMs: _asPlatformInt64(endAtMs),
      tz: tz,
      sourceEntryId: sourceEntryId,
      createdAtMs: existing?.createdAtMs ?? _asPlatformInt64(now),
      updatedAtMs: _asPlatformInt64(now),
    );
    _eventsById[id] = event;
    return event;
  }

  @override
  Future<List<Message>> listMessages(
      Uint8List key, String conversationId) async {
    _ensureConversationExists(conversationId);
    return List<Message>.of(_messageBucket(conversationId));
  }

  @override
  Future<Message?> getMessageById(Uint8List key, String messageId) async {
    for (final messages in _messagesByConversation.values) {
      for (final message in messages) {
        if (message.id == messageId) {
          return message;
        }
      }
    }
    return null;
  }

  @override
  Future<Message> insertMessage(
    Uint8List key,
    String conversationId, {
    required String role,
    required String content,
  }) async {
    return _appendMessage(
      conversationId,
      role: role,
      content: content,
      isMemory: false,
    );
  }

  @override
  Future<Message> insertAssistantMessageWithCitations(
    Uint8List key,
    String conversationId, {
    required String content,
    String? citationsJson,
  }) async {
    return _appendMessage(
      conversationId,
      role: 'assistant',
      content: content,
      isMemory: false,
      citationsJson: citationsJson,
    );
  }

  @override
  Future<bool> applyDetachedAskCompletionOnce(
    Uint8List key, {
    required String requestId,
    required String conversationId,
    required String question,
    required String answer,
    String? citationsJson,
  }) async {
    final normalizedRequestId = requestId.trim();
    final normalizedConversationId = conversationId.trim();
    final normalizedQuestion = question.trim();
    final normalizedAnswer = answer.trim();
    if (normalizedRequestId.isEmpty ||
        normalizedConversationId.isEmpty ||
        normalizedQuestion.isEmpty ||
        normalizedAnswer.isEmpty) {
      return false;
    }

    final claimKey = '$normalizedConversationId::$normalizedRequestId';
    if (!_detachedAskCompletionClaims.add(claimKey)) {
      return false;
    }

    _appendMessage(
      normalizedConversationId,
      role: 'user',
      content: normalizedQuestion,
      isMemory: false,
    );
    _appendMessage(
      normalizedConversationId,
      role: 'assistant',
      content: normalizedAnswer,
      isMemory: false,
      citationsJson: citationsJson,
    );
    return true;
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
      final index =
          entry.value.indexWhere((message) => message.id == messageId);
      if (index < 0) continue;

      if (isDeleted) {
        final deleted = entry.value.removeAt(index);
        _deletedMessagesById[messageId] = _DeletedMessageSnapshot(
          message: deleted,
          index: index,
        );
      }
      return;
    }

    if (!isDeleted) {
      final deleted = _deletedMessagesById.remove(messageId);
      if (deleted == null) return;

      final bucket = _messageBucket(deleted.message.conversationId);
      final restoreIndex = deleted.index.clamp(0, bucket.length);
      bucket.insert(restoreIndex, deleted.message);
    }
  }

  @override
  Future<void> resetVaultDataPreservingLlmProfiles(Uint8List key) async {
    clearWebSessionState();
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
  Future<String> fetchTaskPriorityAiAssessmentsCloudGateway(
    Uint8List key, {
    required String gatewayBaseUrl,
    required String idToken,
    required String cacheScopeKey,
  }) async {
    final fetcher = _fetchTaskPriorityAssessments;
    if (fetcher == null) {
      throw UnsupportedError(
          'task priority shared assessments are not available in web');
    }
    final json = await fetcher(
      idToken: idToken,
      cacheScopeKey: cacheScopeKey,
    );
    return jsonEncode(json);
  }

  @override
  Future<void> upsertTaskPriorityAiAssessmentsCloudGateway(
    Uint8List key, {
    required String gatewayBaseUrl,
    required String idToken,
    required String cacheScopeKey,
    required String payloadJson,
  }) async {
    final upserter = _upsertTaskPriorityAssessments;
    if (upserter == null) {
      throw UnsupportedError(
          'task priority shared assessments are not available in web');
    }
    final decoded = jsonDecode(payloadJson);
    if (decoded is! Map) {
      throw const FormatException('invalid_task_priority_assessment_payload');
    }
    await upserter(
      idToken: idToken,
      payload: decoded.map((key, value) => MapEntry(key.toString(), value)),
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

  @override
  Future<int> syncManagedVaultPush(
    Uint8List key,
    Uint8List syncKey, {
    required String baseUrl,
    required String vaultId,
    required String idToken,
  }) async {
    // The shared web shell is already backed by cloud session state, so
    // explicit managed-vault sync actions are treated as no-ops.
    return 0;
  }

  @override
  Future<int> syncManagedVaultPull(
    Uint8List key,
    Uint8List syncKey, {
    required String baseUrl,
    required String vaultId,
    required String idToken,
  }) async {
    return 0;
  }

  @override
  Future<int> syncManagedVaultPushOpsOnly(
    Uint8List key,
    Uint8List syncKey, {
    required String baseUrl,
    required String vaultId,
    required String idToken,
  }) async {
    return 0;
  }
}

final class _DeletedMessageSnapshot {
  const _DeletedMessageSnapshot({
    required this.message,
    required this.index,
  });

  final Message message;
  final int index;
}
