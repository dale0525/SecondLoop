part of 'native_backend.dart';

mixin _NativeAppBackendPromptAi on _NativeAppBackendAccess
    implements SemanticParseEnhancementBackend {
  @override
  Stream<String> askAiStream(
    Uint8List key,
    String conversationId, {
    required String question,
    int topK = 10,
    bool thisThreadOnly = false,
  }) async* {
    throw _retiredNativeRuntimeFeature('ragAskAiStream');
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
    throw _retiredNativeRuntimeFeature('ragAskAiStreamTimeWindow');
  }

  @override
  Stream<String> askAiStreamWithBrokEmbeddings(
    Uint8List key,
    String conversationId, {
    required String question,
    int topK = 10,
    bool thisThreadOnly = false,
  }) async* {
    throw _retiredNativeRuntimeFeature('ragAskAiStreamWithBrokEmbeddings');
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
    throw _retiredNativeRuntimeFeature(
      'ragAskAiStreamWithBrokEmbeddingsTimeWindow',
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
    throw _retiredNativeRuntimeFeature('ragAskAiStreamCloudGateway');
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
    throw _retiredNativeRuntimeFeature('ragAskAiStreamCloudGatewayTimeWindow');
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
    throw _retiredNativeRuntimeFeature(
      'ragAskAiStreamCloudGatewayWithEmbeddings',
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
    throw _retiredNativeRuntimeFeature(
      'ragAskAiStreamCloudGatewayWithEmbeddingsTimeWindow',
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
    throw _retiredNativeRuntimeFeature('aiTaskPriorityRerank');
  }

  @override
  Future<String> taskPriorityRerankAiCloudGateway(
    Uint8List key, {
    required String prompt,
    required String gatewayBaseUrl,
    required String idToken,
    required String modelName,
  }) async {
    throw _retiredNativeRuntimeFeature('aiTaskPriorityRerankCloudGateway');
  }

  Uri _taskPriorityAssessmentsUri(String gatewayBaseUrl, String cacheScopeKey) {
    final base = gatewayBaseUrl.trim().replaceAll(RegExp(r'/+$'), '');
    return Uri.parse('$base/v1/task-priority/assessments')
        .replace(queryParameters: <String, String>{'scope': cacheScopeKey});
  }

  Future<String> _sendTaskPriorityAssessmentRequest(
    String method, {
    required String gatewayBaseUrl,
    required String idToken,
    required String cacheScopeKey,
    String? payloadJson,
  }) async {
    final http.Client client = createPlatformHttpClient();
    try {
      final uri = _taskPriorityAssessmentsUri(gatewayBaseUrl, cacheScopeKey);
      final headers = <String, String>{
        'authorization': 'Bearer $idToken',
        'accept': 'application/json',
        if (method == 'POST') 'content-type': 'application/json',
      };
      final response = method == 'GET'
          ? await client.get(uri, headers: headers)
          : await client.post(uri, headers: headers, body: payloadJson ?? '{}');
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw StateError(
          'task_priority_assessment_http_${response.statusCode}',
        );
      }
      return response.body;
    } finally {
      client.close();
    }
  }

  @override
  Future<String> fetchTaskPriorityAiAssessmentsCloudGateway(
    Uint8List key, {
    required String gatewayBaseUrl,
    required String idToken,
    required String cacheScopeKey,
  }) {
    return _sendTaskPriorityAssessmentRequest(
      'GET',
      gatewayBaseUrl: gatewayBaseUrl,
      idToken: idToken,
      cacheScopeKey: cacheScopeKey,
    );
  }

  @override
  Future<void> upsertTaskPriorityAiAssessmentsCloudGateway(
    Uint8List key, {
    required String gatewayBaseUrl,
    required String idToken,
    required String cacheScopeKey,
    required String payloadJson,
  }) async {
    await _sendTaskPriorityAssessmentRequest(
      'POST',
      gatewayBaseUrl: gatewayBaseUrl,
      idToken: idToken,
      cacheScopeKey: cacheScopeKey,
      payloadJson: payloadJson,
    );
  }

  @override
  Future<String> todoFollowupRerankAiCloudGateway(
    Uint8List key, {
    required String prompt,
    required String gatewayBaseUrl,
    required String idToken,
    required String modelName,
  }) async {
    throw _retiredNativeRuntimeFeature('aiTodoFollowupRerankCloudGateway');
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
    throw _retiredNativeRuntimeFeature('aiSemanticParseMessageAction');
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
    throw _retiredNativeRuntimeFeature(
      'aiSemanticParseMessageActionCloudGateway',
    );
  }

  @override
  Future<String> semanticParseMessageActionEnhancement(
    Uint8List key, {
    required String text,
    required String nowLocalIso,
    required Locale locale,
    required int dayEndMinutes,
    required String localResultJson,
    required List<String> unresolvedFields,
    required List<TodoCandidate> candidates,
  }) async {
    throw _retiredNativeRuntimeFeature(
      'aiSemanticParseMessageActionEnhancement',
    );
  }

  @override
  Future<String> semanticParseMessageActionEnhancementCloudGateway(
    Uint8List key, {
    required String text,
    required String nowLocalIso,
    required Locale locale,
    required int dayEndMinutes,
    required String localResultJson,
    required List<String> unresolvedFields,
    required List<TodoCandidate> candidates,
    required String gatewayBaseUrl,
    required String idToken,
    required String modelName,
  }) async {
    throw _retiredNativeRuntimeFeature(
      'aiSemanticParseMessageActionEnhancementCloudGateway',
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
    throw _retiredNativeRuntimeFeature('aiSemanticParseAskAiTimeWindow');
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
    throw _retiredNativeRuntimeFeature(
      'aiSemanticParseAskAiTimeWindowCloudGateway',
    );
  }
}
