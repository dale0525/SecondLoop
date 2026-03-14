part of 'semantic_parse_auto_actions_runner.dart';

final class BackendSemanticParseAutoActionsClient
    implements SemanticParseAutoActionsClient {
  BackendSemanticParseAutoActionsClient({
    required AppBackend backend,
    required Uint8List sessionKey,
    required this.askAiRoute,
    required this.embeddingsRoute,
    required this.gatewayBaseUrl,
    required this.idToken,
    required this.modelName,
    this.embeddingsModelName = 'baai/bge-m3',
    this.forceCandidatesLimit = 8,
  })  : _backend = backend,
        _sessionKey = Uint8List.fromList(sessionKey);

  final AppBackend _backend;
  final Uint8List _sessionKey;

  final AskAiRouteKind askAiRoute;
  final EmbeddingsSourceRouteKind embeddingsRoute;
  final String gatewayBaseUrl;
  final String idToken;
  final String modelName;
  final String embeddingsModelName;
  final int forceCandidatesLimit;

  static const int _kTodoSyncLimit = 16;
  static const int _kActivitySyncLimit = 32;

  @override
  Future<List<String>> retrieveTodoCandidateIds({
    required String query,
    required int topK,
  }) async {
    final trimmedQuery = query.trim();
    if (trimmedQuery.isEmpty || topK <= 0) {
      return const <String>[];
    }

    for (final route in _embeddingsRouteFallbackOrder()) {
      try {
        await _refreshTodoThreadEmbeddings(route);
        final matches = await _searchSimilarTodoThreads(
          trimmedQuery,
          topK,
          route,
        );
        return _extractTodoIds(matches, topK);
      } catch (_) {
        continue;
      }
    }

    return const <String>[];
  }

  List<EmbeddingsSourceRouteKind> _embeddingsRouteFallbackOrder() {
    return switch (embeddingsRoute) {
      EmbeddingsSourceRouteKind.cloudGateway =>
        const <EmbeddingsSourceRouteKind>[
          EmbeddingsSourceRouteKind.cloudGateway,
          EmbeddingsSourceRouteKind.byok,
          EmbeddingsSourceRouteKind.local,
        ],
      EmbeddingsSourceRouteKind.byok => const <EmbeddingsSourceRouteKind>[
          EmbeddingsSourceRouteKind.byok,
          EmbeddingsSourceRouteKind.local,
        ],
      EmbeddingsSourceRouteKind.local => const <EmbeddingsSourceRouteKind>[
          EmbeddingsSourceRouteKind.local,
        ],
    };
  }

  List<String> _extractTodoIds(List<TodoThreadMatch> matches, int topK) {
    if (matches.isEmpty) {
      return const <String>[];
    }

    final out = <String>[];
    final seen = <String>{};
    for (final match in matches) {
      final todoId = match.todoId.trim();
      if (todoId.isEmpty || !seen.add(todoId)) continue;
      out.add(todoId);
      if (out.length >= topK) break;
    }
    return out;
  }

  Future<void> _refreshTodoThreadEmbeddings(
    EmbeddingsSourceRouteKind route,
  ) async {
    switch (route) {
      case EmbeddingsSourceRouteKind.cloudGateway:
        await _backend.processPendingTodoThreadEmbeddingsCloudGateway(
          _sessionKey,
          todoLimit: _kTodoSyncLimit,
          activityLimit: _kActivitySyncLimit,
          gatewayBaseUrl: gatewayBaseUrl,
          idToken: idToken,
          modelName: embeddingsModelName,
        );
        break;
      case EmbeddingsSourceRouteKind.byok:
        await _backend.processPendingTodoThreadEmbeddingsBrok(
          _sessionKey,
          todoLimit: _kTodoSyncLimit,
          activityLimit: _kActivitySyncLimit,
        );
        break;
      case EmbeddingsSourceRouteKind.local:
        await _backend.processPendingTodoThreadEmbeddings(
          _sessionKey,
          todoLimit: _kTodoSyncLimit,
          activityLimit: _kActivitySyncLimit,
        );
        break;
    }
  }

  Future<List<TodoThreadMatch>> _searchSimilarTodoThreads(
    String query,
    int topK,
    EmbeddingsSourceRouteKind route,
  ) {
    switch (route) {
      case EmbeddingsSourceRouteKind.cloudGateway:
        return _backend.searchSimilarTodoThreadsCloudGateway(
          _sessionKey,
          query,
          topK: topK,
          gatewayBaseUrl: gatewayBaseUrl,
          idToken: idToken,
          modelName: embeddingsModelName,
        );
      case EmbeddingsSourceRouteKind.byok:
        return _backend.searchSimilarTodoThreadsBrok(
          _sessionKey,
          query,
          topK: topK,
        );
      case EmbeddingsSourceRouteKind.local:
        return _backend.searchSimilarTodoThreads(
          _sessionKey,
          query,
          topK: topK,
        );
    }
  }

  @override
  Future<String> parseMessageActionJson({
    required String text,
    required String nowLocalIso,
    required String localeTag,
    required int dayEndMinutes,
    required List<SemanticParseTodoCandidate> candidates,
    required Duration timeout,
  }) async {
    final locale = SemanticParseAutoActionsRunner._localeFromTag(localeTag);
    final rustCandidates = candidates
        .take(forceCandidatesLimit)
        .map(
          (c) => rust_semantic.TodoCandidate(
            id: c.id,
            title: c.title,
            status: c.status,
            dueLocalIso: c.dueLocalIso,
          ),
        )
        .toList(growable: false);

    final future = askAiRoute == AskAiRouteKind.cloudGateway
        ? _backend.semanticParseMessageActionCloudGateway(
            _sessionKey,
            text: text,
            nowLocalIso: nowLocalIso,
            locale: locale,
            dayEndMinutes: dayEndMinutes,
            candidates: rustCandidates,
            gatewayBaseUrl: gatewayBaseUrl,
            idToken: idToken,
            modelName: modelName,
          )
        : _backend.semanticParseMessageAction(
            _sessionKey,
            text: text,
            nowLocalIso: nowLocalIso,
            locale: locale,
            dayEndMinutes: dayEndMinutes,
            candidates: rustCandidates,
          );

    return future.timeout(timeout);
  }

  @override
  Future<String> generateChecklistSuggestionsJson({
    required String taskTitle,
    required String taskContext,
    required String localeTag,
    required Duration timeout,
  }) async {
    final suggestions = await requestTodoChecklistSuggestions(
      backend: _backend,
      sessionKey: _sessionKey,
      route: askAiRoute,
      gatewayBaseUrl: gatewayBaseUrl,
      idToken: idToken,
      modelName: modelName,
      taskTitle: taskTitle,
      taskContext: taskContext,
      localeTag: localeTag,
      timeout: timeout,
    );
    return jsonEncode(<String, Object?>{'suggestions': suggestions});
  }
}
