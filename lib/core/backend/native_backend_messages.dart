part of 'native_backend.dart';

mixin _NativeAppBackendMessages on _NativeAppBackendAccess {
  @override
  Future<List<Conversation>> listConversations(Uint8List key) async {
    final appDir = await _getAppDir();
    return rust_core.dbListConversations(appDir: appDir, key: key);
  }

  @override
  Future<Conversation> getOrCreateLoopHomeConversation(Uint8List key) async {
    final appDir = await _getAppDir();
    return rust_core.dbGetOrCreateLoopHomeConversation(
      appDir: appDir,
      key: key,
    );
  }

  @override
  Future<Conversation> createConversation(Uint8List key, String title) async {
    final appDir = await _getAppDir();
    return rust_core.dbCreateConversation(
      appDir: appDir,
      key: key,
      title: title,
    );
  }

  @override
  Future<List<Message>> listMessages(
    Uint8List key,
    String conversationId,
  ) async {
    final appDir = await _getAppDir();
    return rust_core.dbListMessages(
      appDir: appDir,
      key: key,
      conversationId: conversationId,
    );
  }

  @override
  Future<Message?> getMessageById(Uint8List key, String messageId) async {
    final appDir = await _getAppDir();
    return rust_core.dbGetMessageById(
      appDir: appDir,
      key: key,
      messageId: messageId,
    );
  }

  @override
  Future<List<Message>> listMessagesPage(
    Uint8List key,
    String conversationId, {
    int? beforeCreatedAtMs,
    String? beforeId,
    int limit = 60,
  }) async {
    final appDir = await _getAppDir();
    return rust_core.dbListMessagesPage(
      appDir: appDir,
      key: key,
      conversationId: conversationId,
      beforeCreatedAtMs: beforeCreatedAtMs == null
          ? null
          : PlatformInt64Util.from(beforeCreatedAtMs),
      beforeId: beforeId,
      limit: limit,
    );
  }

  @override
  Future<Message> insertMessage(
    Uint8List key,
    String conversationId, {
    required String role,
    required String content,
  }) async {
    final appDir = await _getAppDir();
    return _dbInsertMessage(
      appDir: appDir,
      key: key,
      conversationId: conversationId,
      role: role,
      content: content,
    );
  }

  @override
  Future<Message> insertAssistantMessageWithCitations(
    Uint8List key,
    String conversationId, {
    required String content,
    String? citationsJson,
  }) async {
    final appDir = await _getAppDir();
    return _dbInsertMessage(
      appDir: appDir,
      key: key,
      conversationId: conversationId,
      role: 'assistant',
      content: content,
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
    final appDir = await _getAppDir();
    return rust_detached_ask.dbApplyDetachedAskCompletionOnce(
      appDir: appDir,
      key: key,
      requestId: requestId,
      conversationId: conversationId,
      question: question,
      answer: answer,
      citationsJson: citationsJson,
    );
  }
}
