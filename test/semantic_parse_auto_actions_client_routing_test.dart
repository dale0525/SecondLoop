import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:secondloop/core/ai/ai_routing.dart';
import 'package:secondloop/core/ai/embeddings_source_prefs.dart';
import 'package:secondloop/core/ai/semantic_parse_auto_actions_runner.dart';
import 'package:secondloop/features/actions/todo/todo_thread_match.dart';
import 'package:secondloop/src/rust/semantic_parse.dart' as rust_semantic;

import 'test_backend.dart';

void main() {
  test('retrieve uses cloud embeddings route even when ask-ai route is byok',
      () async {
    final backend = _RoutingBackend(
      cloudMatches: const [
        TodoThreadMatch(todoId: 'todo:cloud', distance: 0.12),
      ],
    );

    final client = BackendSemanticParseAutoActionsClient(
      backend: backend,
      sessionKey: _sessionKey,
      askAiRoute: AskAiRouteKind.byok,
      embeddingsRoute: EmbeddingsSourceRouteKind.cloudGateway,
      gatewayBaseUrl: 'https://gateway.example',
      idToken: 'token',
      modelName: 'baai/bge-m3',
    );

    final ids = await client.retrieveTodoCandidateIds(
      query: '狗不理包子',
      topK: 4,
    );

    expect(ids, const ['todo:cloud']);
    expect(backend.processCloudCalls, 1);
    expect(backend.searchCloudCalls, 1);
    expect(backend.processByokCalls, 0);
    expect(backend.searchByokCalls, 0);
    expect(backend.processLocalCalls, 0);
    expect(backend.searchLocalCalls, 0);
  });

  test('retrieve uses local embeddings route even when ask-ai route is cloud',
      () async {
    final backend = _RoutingBackend(
      localMatches: const [
        TodoThreadMatch(todoId: 'todo:local', distance: 0.21),
      ],
    );

    final client = BackendSemanticParseAutoActionsClient(
      backend: backend,
      sessionKey: _sessionKey,
      askAiRoute: AskAiRouteKind.cloudGateway,
      embeddingsRoute: EmbeddingsSourceRouteKind.local,
      gatewayBaseUrl: 'https://gateway.example',
      idToken: 'token',
      modelName: 'baai/bge-m3',
    );

    final ids = await client.retrieveTodoCandidateIds(
      query: '狗不理包子',
      topK: 4,
    );

    expect(ids, const ['todo:local']);
    expect(backend.processLocalCalls, 1);
    expect(backend.searchLocalCalls, 1);
    expect(backend.processCloudCalls, 0);
    expect(backend.searchCloudCalls, 0);
    expect(backend.processByokCalls, 0);
    expect(backend.searchByokCalls, 0);
  });

  test('retrieve falls back to byok when cloud embeddings route fails',
      () async {
    final backend = _RoutingBackend(
      byokMatches: const [
        TodoThreadMatch(todoId: 'todo:byok', distance: 0.31),
      ],
      throwCloudOnProcess: true,
    );

    final client = BackendSemanticParseAutoActionsClient(
      backend: backend,
      sessionKey: _sessionKey,
      askAiRoute: AskAiRouteKind.cloudGateway,
      embeddingsRoute: EmbeddingsSourceRouteKind.cloudGateway,
      gatewayBaseUrl: 'https://gateway.example',
      idToken: 'token',
      modelName: 'gpt-4o-mini',
    );

    final ids = await client.retrieveTodoCandidateIds(
      query: '狗不理包子',
      topK: 4,
    );

    expect(ids, const ['todo:byok']);
    expect(backend.processCloudCalls, 1);
    expect(backend.processByokCalls, 1);
    expect(backend.searchByokCalls, 1);
    expect(backend.processLocalCalls, 0);
    expect(backend.searchLocalCalls, 0);
  });

  test('retrieve falls back to local when byok embeddings route fails',
      () async {
    final backend = _RoutingBackend(
      localMatches: const [
        TodoThreadMatch(todoId: 'todo:local-fallback', distance: 0.37),
      ],
      throwByokOnSearch: true,
    );

    final client = BackendSemanticParseAutoActionsClient(
      backend: backend,
      sessionKey: _sessionKey,
      askAiRoute: AskAiRouteKind.byok,
      embeddingsRoute: EmbeddingsSourceRouteKind.byok,
      gatewayBaseUrl: 'https://gateway.example',
      idToken: 'token',
      modelName: 'gpt-4o-mini',
    );

    final ids = await client.retrieveTodoCandidateIds(
      query: '狗不理包子',
      topK: 4,
    );

    expect(ids, const ['todo:local-fallback']);
    expect(backend.processByokCalls, 1);
    expect(backend.searchByokCalls, 1);
    expect(backend.processLocalCalls, 1);
    expect(backend.searchLocalCalls, 1);
  });

  test('parse uses ask-ai route and does not follow embeddings route',
      () async {
    final backend = _RoutingBackend();

    final client = BackendSemanticParseAutoActionsClient(
      backend: backend,
      sessionKey: _sessionKey,
      askAiRoute: AskAiRouteKind.cloudGateway,
      embeddingsRoute: EmbeddingsSourceRouteKind.local,
      gatewayBaseUrl: 'https://gateway.example',
      idToken: 'token',
      modelName: 'gpt-4o-mini',
    );

    await client.parseMessageActionJson(
      text: '狗不理包子',
      nowLocalIso: '2026-02-18T10:00:00',
      localeTag: 'zh-CN',
      dayEndMinutes: 21 * 60,
      candidates: const <SemanticParseTodoCandidate>[],
      timeout: const Duration(seconds: 1),
    );

    expect(backend.parseCloudCalls, 1);
    expect(backend.parseLocalCalls, 0);
  });
}

final _sessionKey = Uint8List.fromList(List<int>.filled(32, 7));

final class _RoutingBackend extends TestAppBackend {
  _RoutingBackend({
    this.cloudMatches = const <TodoThreadMatch>[],
    this.byokMatches = const <TodoThreadMatch>[],
    this.localMatches = const <TodoThreadMatch>[],
    this.throwCloudOnProcess = false,
    this.throwByokOnSearch = false,
  });

  final List<TodoThreadMatch> cloudMatches;
  final List<TodoThreadMatch> byokMatches;
  final List<TodoThreadMatch> localMatches;
  final bool throwCloudOnProcess;
  final bool throwByokOnSearch;

  int processCloudCalls = 0;
  int processByokCalls = 0;
  int processLocalCalls = 0;

  int searchCloudCalls = 0;
  int searchByokCalls = 0;
  int searchLocalCalls = 0;

  int parseCloudCalls = 0;
  int parseLocalCalls = 0;

  @override
  Future<int> processPendingTodoThreadEmbeddingsCloudGateway(
    Uint8List key, {
    int todoLimit = 32,
    int activityLimit = 64,
    required String gatewayBaseUrl,
    required String idToken,
    required String modelName,
  }) async {
    processCloudCalls += 1;
    if (throwCloudOnProcess) {
      throw StateError('cloud process failed');
    }
    return 0;
  }

  @override
  Future<int> processPendingTodoThreadEmbeddingsBrok(
    Uint8List key, {
    int todoLimit = 32,
    int activityLimit = 64,
  }) async {
    processByokCalls += 1;
    return 0;
  }

  @override
  Future<int> processPendingTodoThreadEmbeddings(
    Uint8List key, {
    int todoLimit = 32,
    int activityLimit = 64,
  }) async {
    processLocalCalls += 1;
    return 0;
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
    searchCloudCalls += 1;
    return cloudMatches.take(topK).toList(growable: false);
  }

  @override
  Future<List<TodoThreadMatch>> searchSimilarTodoThreadsBrok(
    Uint8List key,
    String query, {
    int topK = 10,
  }) async {
    searchByokCalls += 1;
    if (throwByokOnSearch) {
      throw StateError('byok search failed');
    }
    return byokMatches.take(topK).toList(growable: false);
  }

  @override
  Future<List<TodoThreadMatch>> searchSimilarTodoThreads(
    Uint8List key,
    String query, {
    int topK = 10,
  }) async {
    searchLocalCalls += 1;
    return localMatches.take(topK).toList(growable: false);
  }

  @override
  Future<String> semanticParseMessageAction(
    Uint8List key, {
    required String text,
    required String nowLocalIso,
    required Locale locale,
    required int dayEndMinutes,
    required List<rust_semantic.TodoCandidate> candidates,
  }) async {
    parseLocalCalls += 1;
    return '{"kind":"none","confidence":1.0}';
  }

  @override
  Future<String> semanticParseMessageActionCloudGateway(
    Uint8List key, {
    required String text,
    required String nowLocalIso,
    required Locale locale,
    required int dayEndMinutes,
    required List<rust_semantic.TodoCandidate> candidates,
    required String gatewayBaseUrl,
    required String idToken,
    required String modelName,
  }) async {
    parseCloudCalls += 1;
    return '{"kind":"none","confidence":1.0}';
  }
}
