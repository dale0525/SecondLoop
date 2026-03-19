part of 'native_backend.dart';

mixin _NativeAppBackendPromptAi on _NativeAppBackendAccess {
  @override
  Stream<String> askAiStream(
    Uint8List key,
    String conversationId, {
    required String question,
    int topK = 10,
    bool thisThreadOnly = false,
  }) async* {
    final appDir = await _getAppDir();
    final localDay = NativeAppBackend._formatLocalDayKey(DateTime.now());
    yield* rust_core.ragAskAiStream(
      appDir: appDir,
      key: key,
      conversationId: conversationId,
      question: question,
      topK: topK,
      thisThreadOnly: thisThreadOnly,
      localDay: localDay,
    );
  }

  @override
  Stream<String> askAiStreamTimeWindow(
    Uint8List key,
    String conversationId, {
    required String question,
    required int timeStartMs,
    required int timeEndMs,
    int topK = 10,
    bool thisThreadOnly = false,
  }) async* {
    final appDir = await _getAppDir();
    final localDay = NativeAppBackend._formatLocalDayKey(DateTime.now());
    yield* rust_core.ragAskAiStreamTimeWindow(
      appDir: appDir,
      key: key,
      conversationId: conversationId,
      question: question,
      topK: topK,
      thisThreadOnly: thisThreadOnly,
      timeStartMs: PlatformInt64Util.from(timeStartMs),
      timeEndMs: PlatformInt64Util.from(timeEndMs),
      localDay: localDay,
    );
  }

  @override
  Stream<String> askAiStreamWithBrokEmbeddings(
    Uint8List key,
    String conversationId, {
    required String question,
    int topK = 10,
    bool thisThreadOnly = false,
  }) async* {
    final appDir = await _getAppDir();
    final localDay = NativeAppBackend._formatLocalDayKey(DateTime.now());
    yield* rust_core.ragAskAiStreamWithBrokEmbeddings(
      appDir: appDir,
      key: key,
      conversationId: conversationId,
      question: question,
      topK: topK,
      thisThreadOnly: thisThreadOnly,
      localDay: localDay,
    );
  }

  @override
  Stream<String> askAiStreamWithBrokEmbeddingsTimeWindow(
    Uint8List key,
    String conversationId, {
    required String question,
    required int timeStartMs,
    required int timeEndMs,
    int topK = 10,
    bool thisThreadOnly = false,
  }) async* {
    final appDir = await _getAppDir();
    final localDay = NativeAppBackend._formatLocalDayKey(DateTime.now());
    yield* rust_core.ragAskAiStreamWithBrokEmbeddingsTimeWindow(
      appDir: appDir,
      key: key,
      conversationId: conversationId,
      question: question,
      topK: topK,
      thisThreadOnly: thisThreadOnly,
      timeStartMs: PlatformInt64Util.from(timeStartMs),
      timeEndMs: PlatformInt64Util.from(timeEndMs),
      localDay: localDay,
    );
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
    final appDir = await _getAppDir();
    yield* rust_core.ragAskAiStreamCloudGateway(
      appDir: appDir,
      key: key,
      conversationId: conversationId,
      question: question,
      topK: topK,
      thisThreadOnly: thisThreadOnly,
      gatewayBaseUrl: gatewayBaseUrl,
      firebaseIdToken: idToken,
      modelName: modelName,
    );
  }

  @override
  Stream<String> askAiStreamCloudGatewayTimeWindow(
    Uint8List key,
    String conversationId, {
    required String question,
    required int timeStartMs,
    required int timeEndMs,
    int topK = 10,
    bool thisThreadOnly = false,
    required String gatewayBaseUrl,
    required String idToken,
    required String modelName,
  }) async* {
    final appDir = await _getAppDir();
    yield* rust_core.ragAskAiStreamCloudGatewayTimeWindow(
      appDir: appDir,
      key: key,
      conversationId: conversationId,
      question: question,
      topK: topK,
      thisThreadOnly: thisThreadOnly,
      timeStartMs: PlatformInt64Util.from(timeStartMs),
      timeEndMs: PlatformInt64Util.from(timeEndMs),
      gatewayBaseUrl: gatewayBaseUrl,
      firebaseIdToken: idToken,
      modelName: modelName,
    );
  }

  @override
  Stream<String> askAiStreamCloudGatewayWithEmbeddings(
    Uint8List key,
    String conversationId, {
    required String question,
    int topK = 10,
    bool thisThreadOnly = false,
    required String gatewayBaseUrl,
    required String idToken,
    required String modelName,
    required String embeddingsModelName,
  }) async* {
    final appDir = await _getAppDir();
    yield* rust_core.ragAskAiStreamCloudGatewayWithEmbeddings(
      appDir: appDir,
      key: key,
      conversationId: conversationId,
      question: question,
      topK: topK,
      thisThreadOnly: thisThreadOnly,
      gatewayBaseUrl: gatewayBaseUrl,
      firebaseIdToken: idToken,
      modelName: modelName,
      embeddingsModelName: embeddingsModelName,
    );
  }

  @override
  Stream<String> askAiStreamCloudGatewayWithEmbeddingsTimeWindow(
    Uint8List key,
    String conversationId, {
    required String question,
    required int timeStartMs,
    required int timeEndMs,
    int topK = 10,
    bool thisThreadOnly = false,
    required String gatewayBaseUrl,
    required String idToken,
    required String modelName,
    required String embeddingsModelName,
  }) async* {
    final appDir = await _getAppDir();
    yield* rust_core.ragAskAiStreamCloudGatewayWithEmbeddingsTimeWindow(
      appDir: appDir,
      key: key,
      conversationId: conversationId,
      question: question,
      topK: topK,
      thisThreadOnly: thisThreadOnly,
      timeStartMs: PlatformInt64Util.from(timeStartMs),
      timeEndMs: PlatformInt64Util.from(timeEndMs),
      gatewayBaseUrl: gatewayBaseUrl,
      firebaseIdToken: idToken,
      modelName: modelName,
      embeddingsModelName: embeddingsModelName,
    );
  }

  @override
  Stream<String> askAiStreamScoped(
    Uint8List key,
    String conversationId, {
    required String question,
    required int topK,
    required bool thisThreadOnly,
    int? timeStartMs,
    int? timeEndMs,
    required List<String> includeTagIds,
    required List<String> excludeTagIds,
    required bool strictMode,
    required String localeLanguage,
    required String localDay,
  }) async* {
    final appDir = await _getAppDir();
    yield* _askAiStreamScoped(
      appDir: appDir,
      key: key,
      conversationId: conversationId,
      question: question,
      topK: topK,
      thisThreadOnly: thisThreadOnly,
      timeStartMs: timeStartMs,
      timeEndMs: timeEndMs,
      includeTagIds: includeTagIds,
      excludeTagIds: excludeTagIds,
      strictMode: strictMode,
      localeLanguage: localeLanguage,
      localDay: localDay,
    );
  }

  @override
  Stream<String> askAiStreamCloudGatewayScoped(
    Uint8List key,
    String conversationId, {
    required String question,
    required int topK,
    required bool thisThreadOnly,
    int? timeStartMs,
    int? timeEndMs,
    required List<String> includeTagIds,
    required List<String> excludeTagIds,
    required bool strictMode,
    required String localeLanguage,
    required String gatewayBaseUrl,
    required String idToken,
    required String modelName,
  }) async* {
    final appDir = await _getAppDir();
    yield* _askAiStreamCloudGatewayScoped(
      appDir: appDir,
      key: key,
      conversationId: conversationId,
      question: question,
      topK: topK,
      thisThreadOnly: thisThreadOnly,
      timeStartMs: timeStartMs,
      timeEndMs: timeEndMs,
      includeTagIds: includeTagIds,
      excludeTagIds: excludeTagIds,
      strictMode: strictMode,
      localeLanguage: localeLanguage,
      gatewayBaseUrl: gatewayBaseUrl,
      firebaseIdToken: idToken,
      modelName: modelName,
    );
  }

  @override
  Future<String> taskPriorityRerankAi(
    Uint8List key, {
    required String prompt,
  }) async {
    final appDir = await _getAppDir();
    final localDay = NativeAppBackend._formatLocalDayKey(DateTime.now());
    return rust_core.aiTaskPriorityRerank(
      appDir: appDir,
      key: key,
      prompt: prompt,
      localDay: localDay,
    );
  }

  @override
  Future<String> taskPriorityRerankAiCloudGateway(
    Uint8List key, {
    required String prompt,
    required String gatewayBaseUrl,
    required String idToken,
    required String modelName,
  }) async {
    final appDir = await _getAppDir();
    return rust_core.aiTaskPriorityRerankCloudGateway(
      appDir: appDir,
      key: key,
      prompt: prompt,
      gatewayBaseUrl: gatewayBaseUrl,
      firebaseIdToken: idToken,
      modelName: modelName,
    );
  }

  @override
  Future<String> semanticParseMessageAction(
    Uint8List key, {
    required String text,
    required String nowLocalIso,
    required Locale locale,
    required int dayEndMinutes,
    required List<TodoCandidate> candidates,
  }) async {
    final appDir = await _getAppDir();
    final localDay = NativeAppBackend._formatLocalDayKey(DateTime.now());
    return rust_core.aiSemanticParseMessageAction(
      appDir: appDir,
      key: key,
      text: text,
      nowLocalIso: nowLocalIso,
      locale: locale.toLanguageTag(),
      dayEndMinutes: dayEndMinutes,
      candidates: candidates,
      localDay: localDay,
    );
  }

  @override
  Future<String> semanticParseMessageActionCloudGateway(
    Uint8List key, {
    required String text,
    required String nowLocalIso,
    required Locale locale,
    required int dayEndMinutes,
    required List<TodoCandidate> candidates,
    required String gatewayBaseUrl,
    required String idToken,
    required String modelName,
  }) async {
    final appDir = await _getAppDir();
    return rust_core.aiSemanticParseMessageActionCloudGateway(
      appDir: appDir,
      key: key,
      text: text,
      nowLocalIso: nowLocalIso,
      locale: locale.toLanguageTag(),
      dayEndMinutes: dayEndMinutes,
      candidates: candidates,
      gatewayBaseUrl: gatewayBaseUrl,
      firebaseIdToken: idToken,
      modelName: modelName,
    );
  }

  @override
  Future<String> semanticParseAskAiTimeWindow(
    Uint8List key, {
    required String question,
    required String nowLocalIso,
    required Locale locale,
    required int firstDayOfWeekIndex,
  }) async {
    final appDir = await _getAppDir();
    final localDay = NativeAppBackend._formatLocalDayKey(DateTime.now());
    return rust_core.aiSemanticParseAskAiTimeWindow(
      appDir: appDir,
      key: key,
      question: question,
      nowLocalIso: nowLocalIso,
      locale: locale.toLanguageTag(),
      firstDayOfWeekIndex: firstDayOfWeekIndex,
      localDay: localDay,
    );
  }

  @override
  Future<String> semanticParseAskAiTimeWindowCloudGateway(
    Uint8List key, {
    required String question,
    required String nowLocalIso,
    required Locale locale,
    required int firstDayOfWeekIndex,
    required String gatewayBaseUrl,
    required String idToken,
    required String modelName,
  }) async {
    final appDir = await _getAppDir();
    return rust_core.aiSemanticParseAskAiTimeWindowCloudGateway(
      appDir: appDir,
      key: key,
      question: question,
      nowLocalIso: nowLocalIso,
      locale: locale.toLanguageTag(),
      firstDayOfWeekIndex: firstDayOfWeekIndex,
      gatewayBaseUrl: gatewayBaseUrl,
      firebaseIdToken: idToken,
      modelName: modelName,
    );
  }
}
