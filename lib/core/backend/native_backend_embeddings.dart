part of 'native_backend.dart';

mixin _NativeAppBackendEmbeddings on _NativeAppBackendAccess {
  @override
  Future<List<Event>> listEvents(Uint8List key) async {
    final appDir = await _getAppDir();
    return rust_core.dbListEvents(appDir: appDir, key: key);
  }

  @override
  Future<Event?> getEventById(Uint8List key, String eventId) async {
    final appDir = await _getAppDir();
    return rust_core.dbGetEventById(
      appDir: appDir,
      key: key,
      eventId: eventId,
    );
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
    return rust_core.dbUpsertEvent(
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
    return rust_core.dbProcessPendingTodoThreadEmbeddings(
      appDir: appDir,
      key: key,
      todoLimit: todoLimit,
      activityLimit: activityLimit,
    );
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
    return rust_core.dbProcessPendingTodoThreadEmbeddingsCloudGateway(
      appDir: appDir,
      key: key,
      todoLimit: todoLimit,
      activityLimit: activityLimit,
      gatewayBaseUrl: gatewayBaseUrl,
      firebaseIdToken: idToken,
      modelName: modelName,
    );
  }

  @override
  Future<int> processPendingTodoThreadEmbeddingsBrok(
    Uint8List key, {
    int todoLimit = 32,
    int activityLimit = 64,
  }) async {
    final appDir = await _getAppDir();
    return rust_core.dbProcessPendingTodoThreadEmbeddingsBrok(
      appDir: appDir,
      key: key,
      todoLimit: todoLimit,
      activityLimit: activityLimit,
    );
  }

  @override
  Future<List<SimilarMessage>> searchSimilarMessages(
    Uint8List key,
    String query, {
    int topK = 10,
  }) async {
    final appDir = await _getAppDir();
    return rust_core.dbSearchSimilarMessages(
      appDir: appDir,
      key: key,
      query: query,
      topK: topK,
    );
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
    return rust_core.dbSearchSimilarMessagesCloudGateway(
      appDir: appDir,
      key: key,
      query: query,
      topK: topK,
      gatewayBaseUrl: gatewayBaseUrl,
      firebaseIdToken: idToken,
      modelName: modelName,
    );
  }

  @override
  Future<List<SimilarMessage>> searchSimilarMessagesBrok(
    Uint8List key,
    String query, {
    int topK = 10,
  }) async {
    final appDir = await _getAppDir();
    return rust_core.dbSearchSimilarMessagesBrok(
      appDir: appDir,
      key: key,
      query: query,
      topK: topK,
    );
  }

  @override
  Future<List<TodoThreadMatch>> searchSimilarTodoThreads(
    Uint8List key,
    String query, {
    int topK = 10,
  }) async {
    final appDir = await _getAppDir();
    final matches = await rust_core.dbSearchSimilarTodoThreads(
      appDir: appDir,
      key: key,
      query: query,
      topK: topK,
    );
    return matches
        .map(
          (m) => TodoThreadMatch(
            todoId: m.todoId,
            distance: m.distance,
          ),
        )
        .toList(growable: false);
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
    final matches = await rust_core.dbSearchSimilarTodoThreadsCloudGateway(
      appDir: appDir,
      key: key,
      query: query,
      topK: topK,
      gatewayBaseUrl: gatewayBaseUrl,
      firebaseIdToken: idToken,
      modelName: modelName,
    );
    return matches
        .map(
          (m) => TodoThreadMatch(
            todoId: m.todoId,
            distance: m.distance,
          ),
        )
        .toList(growable: false);
  }

  @override
  Future<List<TodoThreadMatch>> searchSimilarTodoThreadsBrok(
    Uint8List key,
    String query, {
    int topK = 10,
  }) async {
    final appDir = await _getAppDir();
    final matches = await rust_core.dbSearchSimilarTodoThreadsBrok(
      appDir: appDir,
      key: key,
      query: query,
      topK: topK,
    );
    return matches
        .map(
          (m) => TodoThreadMatch(
            todoId: m.todoId,
            distance: m.distance,
          ),
        )
        .toList(growable: false);
  }

  @override
  Future<int> rebuildMessageEmbeddings(
    Uint8List key, {
    int batchLimit = 256,
  }) async {
    final appDir = await _getAppDir();
    return rust_core.dbRebuildMessageEmbeddings(
      appDir: appDir,
      key: key,
      batchLimit: batchLimit,
    );
  }

  @override
  Future<List<String>> listEmbeddingModelNames(Uint8List key) async {
    final appDir = await _getAppDir();
    return rust_core.dbListEmbeddingModelNames(appDir: appDir, key: key);
  }

  @override
  Future<String> getActiveEmbeddingModelName(Uint8List key) async {
    final appDir = await _getAppDir();
    return rust_core.dbGetActiveEmbeddingModelName(appDir: appDir, key: key);
  }

  @override
  Future<bool> setActiveEmbeddingModelName(
    Uint8List key,
    String modelName,
  ) async {
    final appDir = await _getAppDir();
    return rust_core.dbSetActiveEmbeddingModelName(
      appDir: appDir,
      key: key,
      modelName: modelName,
    );
  }

  @override
  Future<List<EmbeddingProfile>> listEmbeddingProfiles(Uint8List key) async {
    final appDir = await _getAppDir();
    return rust_core.dbListEmbeddingProfiles(appDir: appDir, key: key);
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
    return rust_core.dbCreateEmbeddingProfile(
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
    return rust_core.dbSetActiveEmbeddingProfile(
      appDir: appDir,
      key: key,
      profileId: profileId,
    );
  }

  @override
  Future<void> deleteEmbeddingProfile(Uint8List key, String profileId) async {
    final appDir = await _getAppDir();
    return rust_core.dbDeleteEmbeddingProfile(
      appDir: appDir,
      key: key,
      profileId: profileId,
    );
  }

  @override
  Future<List<LlmProfile>> listLlmProfiles(Uint8List key) async {
    final appDir = await _getAppDir();
    return rust_core.dbListLlmProfiles(appDir: appDir, key: key);
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
    return rust_core.dbCreateLlmProfile(
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
    return rust_core.dbSetActiveLlmProfile(
      appDir: appDir,
      key: key,
      profileId: profileId,
    );
  }

  @override
  Future<void> deleteLlmProfile(Uint8List key, String profileId) async {
    final appDir = await _getAppDir();
    return rust_core.dbDeleteLlmProfile(
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
    return rust_core.dbSumLlmUsageDailyByPurpose(
      appDir: appDir,
      key: key,
      profileId: profileId,
      startDay: startDay,
      endDay: endDay,
    );
  }
}
