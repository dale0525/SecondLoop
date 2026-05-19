part of 'native_backend.dart';

mixin _NativeAppBackendEmbeddings on _NativeAppBackendAccess {
  @override
  Future<List<Event>> listEvents(Uint8List key) async {
    final appDir = await _getAppDir();
    return _dartDbListEvents(appDir: appDir, key: key);
  }

  @override
  Future<Event?> getEventById(Uint8List key, String eventId) async {
    final appDir = await _getAppDir();
    return _dartDbGetEventById(appDir: appDir, key: key, eventId: eventId);
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
    final appDir = await _getAppDir();
    return _dartDbUpsertEvent(
      appDir: appDir,
      key: key,
      id: id,
      title: title,
      startAtMs: PlatformInt64Util.from(startAtMs),
      endAtMs: PlatformInt64Util.from(endAtMs),
      tz: tz,
      sourceEntryId: sourceEntryId,
    );
  }

  @override
  Future<int> processPendingMessageEmbeddings(
    Uint8List key, {
    int limit = 32,
  }) async {
    final appDir = await _getAppDir();
    return _dbProcessPendingMessageEmbeddings(
      appDir: appDir,
      key: key,
      limit: limit,
    );
  }

  @override
  Future<bool> releaseLocalEmbeddingModelIfIdle(
    Uint8List key, {
    int maxIdleMs = 180000,
  }) async {
    final appDir = await _getAppDir();
    return _dbReleaseLocalEmbeddingModelIfIdle(
      appDir: appDir,
      key: key,
      maxIdleMs: maxIdleMs,
    );
  }

  @override
  Future<int> processPendingTodoThreadEmbeddings(
    Uint8List key, {
    int todoLimit = 32,
    int activityLimit = 64,
  }) async {
    final appDir = await _getAppDir();
    return _dartDbNoopEmbeddingBatch(appDir: appDir, key: key);
  }

  @override
  Future<int> processPendingTodoThreadEmbeddingsCloudGateway(
    Uint8List key, {
    int todoLimit = 32,
    int activityLimit = 64,
    required String gatewayBaseUrl,
    required String idToken,
    required String modelName,
  }) async {
    final appDir = await _getAppDir();
    return _dartDbNoopEmbeddingBatch(appDir: appDir, key: key);
  }

  @override
  Future<int> processPendingTodoThreadEmbeddingsBrok(
    Uint8List key, {
    int todoLimit = 32,
    int activityLimit = 64,
  }) async {
    final appDir = await _getAppDir();
    return _dartDbNoopEmbeddingBatch(appDir: appDir, key: key);
  }

  @override
  Future<List<SimilarMessage>> searchSimilarMessages(
    Uint8List key,
    String query, {
    int topK = 10,
  }) async {
    final appDir = await _getAppDir();
    return _dartDbSearchSimilarMessages(appDir: appDir, key: key);
  }

  @override
  Future<List<SimilarMessage>> searchSimilarMessagesCloudGateway(
    Uint8List key,
    String query, {
    int topK = 10,
    required String gatewayBaseUrl,
    required String idToken,
    required String modelName,
  }) async {
    final appDir = await _getAppDir();
    return _dartDbSearchSimilarMessages(appDir: appDir, key: key);
  }

  @override
  Future<List<SimilarMessage>> searchSimilarMessagesBrok(
    Uint8List key,
    String query, {
    int topK = 10,
  }) async {
    final appDir = await _getAppDir();
    return _dartDbSearchSimilarMessages(appDir: appDir, key: key);
  }

  @override
  Future<List<TodoThreadMatch>> searchSimilarTodoThreads(
    Uint8List key,
    String query, {
    int topK = 10,
  }) async {
    final appDir = await _getAppDir();
    return _dartDbSearchSimilarTodoThreads(appDir: appDir, key: key);
  }

  @override
  Future<List<TodoThreadMatch>> searchSimilarTodoThreadsCloudGateway(
    Uint8List key,
    String query, {
    int topK = 10,
    required String gatewayBaseUrl,
    required String idToken,
    required String modelName,
  }) async {
    final appDir = await _getAppDir();
    return _dartDbSearchSimilarTodoThreads(appDir: appDir, key: key);
  }

  @override
  Future<List<TodoThreadMatch>> searchSimilarTodoThreadsBrok(
    Uint8List key,
    String query, {
    int topK = 10,
  }) async {
    final appDir = await _getAppDir();
    return _dartDbSearchSimilarTodoThreads(appDir: appDir, key: key);
  }

  @override
  Future<int> rebuildMessageEmbeddings(
    Uint8List key, {
    int batchLimit = 256,
  }) async {
    final appDir = await _getAppDir();
    return _dartDbNoopEmbeddingBatch(appDir: appDir, key: key);
  }

  @override
  Future<List<String>> listEmbeddingModelNames(Uint8List key) async {
    final appDir = await _getAppDir();
    return _dartDbListEmbeddingModelNames(appDir: appDir, key: key);
  }

  @override
  Future<String> getActiveEmbeddingModelName(Uint8List key) async {
    final appDir = await _getAppDir();
    return _dartDbGetActiveEmbeddingModelName(appDir: appDir, key: key);
  }

  @override
  Future<bool> setActiveEmbeddingModelName(
    Uint8List key,
    String modelName,
  ) async {
    final appDir = await _getAppDir();
    return _dartDbSetActiveEmbeddingModelName(
      appDir: appDir,
      key: key,
      modelName: modelName,
    );
  }

  @override
  Future<List<EmbeddingProfile>> listEmbeddingProfiles(Uint8List key) async {
    final appDir = await _getAppDir();
    return _dartDbListEmbeddingProfiles(appDir: appDir, key: key);
  }

  @override
  Future<EmbeddingProfile> createEmbeddingProfile(
    Uint8List key, {
    required String name,
    required String providerType,
    String? baseUrl,
    String? apiKey,
    required String modelName,
    bool setActive = true,
  }) async {
    final appDir = await _getAppDir();
    return _dartDbCreateEmbeddingProfile(
      appDir: appDir,
      key: key,
      name: name,
      providerType: providerType,
      baseUrl: baseUrl,
      apiKey: apiKey,
      modelName: modelName,
      setActive: setActive,
    );
  }

  @override
  Future<void> setActiveEmbeddingProfile(
      Uint8List key, String profileId) async {
    final appDir = await _getAppDir();
    return _dartDbSetActiveEmbeddingProfile(
      appDir: appDir,
      key: key,
      profileId: profileId,
    );
  }

  @override
  Future<void> deleteEmbeddingProfile(Uint8List key, String profileId) async {
    final appDir = await _getAppDir();
    return _dartDbDeleteEmbeddingProfile(
      appDir: appDir,
      key: key,
      profileId: profileId,
    );
  }

  @override
  Future<List<LlmProfile>> listLlmProfiles(Uint8List key) async {
    final appDir = await _getAppDir();
    return _dartDbListLlmProfiles(appDir: appDir, key: key);
  }

  @override
  Future<LlmProfile> createLlmProfile(
    Uint8List key, {
    required String name,
    required String providerType,
    String? baseUrl,
    String? apiKey,
    required String modelName,
    bool setActive = true,
  }) async {
    final appDir = await _getAppDir();
    return _dartDbCreateLlmProfile(
      appDir: appDir,
      key: key,
      name: name,
      providerType: providerType,
      baseUrl: baseUrl,
      apiKey: apiKey,
      modelName: modelName,
      setActive: setActive,
    );
  }

  @override
  Future<void> setActiveLlmProfile(Uint8List key, String profileId) async {
    final appDir = await _getAppDir();
    return _dartDbSetActiveLlmProfile(
      appDir: appDir,
      key: key,
      profileId: profileId,
    );
  }

  @override
  Future<void> deleteLlmProfile(Uint8List key, String profileId) async {
    final appDir = await _getAppDir();
    return _dartDbDeleteLlmProfile(
      appDir: appDir,
      key: key,
      profileId: profileId,
    );
  }

  @override
  bool get supportsScopedAskAi => true;

  @override
  Future<List<LlmUsageAggregate>> sumLlmUsageDailyByPurpose(
    Uint8List key,
    String profileId, {
    required String startDay,
    required String endDay,
  }) async {
    final appDir = await _getAppDir();
    return _dartDbSumLlmUsageDailyByPurpose(appDir: appDir, key: key);
  }
}
