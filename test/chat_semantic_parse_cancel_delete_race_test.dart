import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:secondloop/core/ai/semantic_parse_auto_actions_gate.dart';
import 'package:secondloop/core/backend/app_backend.dart';
import 'package:secondloop/core/backend/native_backend.dart';
import 'package:secondloop/core/session/session_scope.dart';
import 'package:secondloop/core/sync/sync_engine.dart';
import 'package:secondloop/core/sync/sync_engine_gate.dart';
import 'package:secondloop/features/actions/todo/todo_thread_match.dart';
import 'package:secondloop/features/chat/chat_page.dart';
import 'package:secondloop/src/rust/db.dart';
import 'package:secondloop/src/rust/semantic_parse.dart' as rust_semantic;

import 'noop_sync_runner.dart';
import 'test_i18n.dart';

void main() {
  testWidgets(
    'deleting message while semantic parse is running prevents late followup mutation',
    (tester) async {
      const pendingText = '把这个完成';
      SharedPreferences.setMockInitialValues({
        'semantic_parse_data_consent_v1': true,
        'embeddings_source_preference_v1': 'local',
      });

      final backend = _RaceBackend(
        initialTodos: const <Todo>[
          Todo(
            id: 'todo:1',
            title: '报销',
            dueAtMs: null,
            status: 'open',
            sourceEntryId: null,
            reviewStage: null,
            nextReviewAtMs: null,
            lastReviewAtMs: null,
            createdAtMs: 1,
            updatedAtMs: 1,
          ),
          Todo(
            id: 'todo:2',
            title: '回访客户',
            dueAtMs: null,
            status: 'open',
            sourceEntryId: null,
            reviewStage: null,
            nextReviewAtMs: null,
            lastReviewAtMs: null,
            createdAtMs: 2,
            updatedAtMs: 2,
          ),
        ],
      );
      final engine = SyncEngine(
        syncRunner: NoopSyncRunner(),
        loadConfig: () async => null,
        pullOnStart: false,
      );

      await tester.pumpWidget(
        wrapWithI18n(
          MaterialApp(
            locale: const Locale('zh', 'CN'),
            home: SyncEngineScope(
              engine: engine,
              child: AppBackendScope(
                backend: backend,
                child: SessionScope(
                  sessionKey: Uint8List.fromList(List<int>.filled(32, 1)),
                  lock: () {},
                  child: const SemanticParseAutoActionsGate(
                    child: ChatPage(
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
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.enterText(
          find.byKey(const ValueKey('chat_input')), pendingText);
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('chat_send')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text(pendingText), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      await tester.pump(const Duration(seconds: 3));
      await backend.parseStarted.future.timeout(const Duration(seconds: 1));

      final sessionKey = Uint8List.fromList(List<int>.filled(32, 1));
      await backend.purgeMessageAttachments(sessionKey, 'm1');
      await backend.markSemanticParseJobCanceled(
        sessionKey,
        messageId: 'm1',
        nowMs: DateTime.now().millisecondsSinceEpoch,
      );
      engine.notifyLocalMutation();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.text(pendingText), findsNothing);
      expect(backend.deletedMessageIds, contains('m1'));
      expect(backend.canceledMessageIds, contains('m1'));

      backend.releaseLateParseFollowup();
      await tester.pump(const Duration(milliseconds: 50));
      await tester.pump(const Duration(milliseconds: 50));

      expect(backend.createdTodos, isEmpty);
      expect(backend.completedFollowupTodoIds, isEmpty);
      expect(backend.markedSucceededMessageIds, isEmpty);
      expect(backend.currentJobStatus('m1'), 'canceled');
      expect(backend.todoStatus('todo:1'), 'open');
      expect(backend.todoStatus('todo:2'), 'open');
    },
  );
}

SemanticParseJob _job({
  required String messageId,
  required String status,
  required int createdAtMs,
  int attemptId = 0,
  int updatedAtMs = 0,
}) {
  return SemanticParseJob(
    messageId: messageId,
    status: status,
    attemptId: PlatformInt64Util.from(attemptId),
    attempts: PlatformInt64Util.from(0),
    nextRetryAtMs: null,
    lastError: null,
    appliedActionKind: null,
    appliedTodoId: null,
    appliedTodoTitle: null,
    appliedPrevTodoStatus: null,
    appliedDueChanged: false,
    suggestedTags: null,
    suggestedTagConfidence: null,
    tagSuggestionState: null,
    appliedTagIds: null,
    undoneAtMs: null,
    createdAtMs: PlatformInt64Util.from(createdAtMs),
    updatedAtMs:
        PlatformInt64Util.from(updatedAtMs == 0 ? createdAtMs : updatedAtMs),
  );
}

final class _RaceBackend extends NativeAppBackend {
  _RaceBackend({
    List<Todo> initialTodos = const <Todo>[],
  })  : _todos = List<Todo>.from(initialTodos),
        super(appDirProvider: () async => '/tmp/secondloop-test');

  final List<Message> _messages = <Message>[];
  final List<Todo> _todos;
  final Map<String, SemanticParseJob> _jobsByMessageId =
      <String, SemanticParseJob>{};

  final Completer<void> parseStarted = Completer<void>();
  final Completer<String> _lateParseResponse = Completer<String>();

  final List<String> canceledMessageIds = <String>[];
  final List<String> deletedMessageIds = <String>[];
  final List<String> markedSucceededMessageIds = <String>[];
  final List<String> completedFollowupTodoIds = <String>[];
  final List<Todo> createdTodos = <Todo>[];

  void releaseLateParseFollowup() {
    if (_lateParseResponse.isCompleted) return;
    _lateParseResponse.complete(
      '{"kind":"followup","confidence":0.91,"todo_id":"todo:2","new_status":"done","due_local_iso":null}',
    );
  }

  String? currentJobStatus(String messageId) =>
      _jobsByMessageId[messageId]?.status;

  String? todoStatus(String todoId) {
    for (final todo in _todos) {
      if (todo.id == todoId) return todo.status;
    }
    return null;
  }

  @override
  Future<List<Message>> listMessages(
      Uint8List key, String conversationId) async {
    return List<Message>.from(_messages);
  }

  @override
  Future<List<Message>> listMessagesPage(
    Uint8List key,
    String conversationId, {
    int limit = 60,
    int? beforeCreatedAtMs,
    String? beforeId,
  }) async {
    final messages = List<Message>.from(_messages)
      ..sort((a, b) => b.createdAtMs.compareTo(a.createdAtMs));
    if (beforeId == null) {
      return messages.take(limit).toList(growable: false);
    }
    final index = messages.indexWhere(
      (message) => message.id == beforeId,
    );
    if (index < 0) {
      return messages.take(limit).toList(growable: false);
    }
    return messages.skip(index + 1).take(limit).toList(growable: false);
  }

  @override
  Future<Message?> getMessageById(Uint8List key, String messageId) async {
    for (final message in _messages) {
      if (message.id == messageId) return message;
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
    final message = Message(
      id: 'm${_messages.length + 1}',
      conversationId: conversationId,
      role: role,
      content: content,
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
      isMemory: true,
    );
    _messages.add(message);
    return message;
  }

  @override
  Future<void> setMessageDeleted(
    Uint8List key,
    String messageId,
    bool isDeleted,
  ) async {
    deletedMessageIds.add(messageId);
    _messages.removeWhere((message) => message.id == messageId);
  }

  @override
  Future<void> purgeMessageAttachments(Uint8List key, String messageId) async {
    await setMessageDeleted(key, messageId, true);
  }

  @override
  Future<void> enqueueSemanticParseJob(
    Uint8List key, {
    required String messageId,
    required int nowMs,
  }) async {
    final createdAtMs = nowMs - 5000;
    _jobsByMessageId[messageId] = _job(
      messageId: messageId,
      status: 'pending',
      createdAtMs: createdAtMs,
    );
  }

  @override
  Future<List<SemanticParseJob>> listSemanticParseJobsByMessageIds(
    Uint8List key, {
    required List<String> messageIds,
  }) async {
    return messageIds
        .map((id) => _jobsByMessageId[id])
        .whereType<SemanticParseJob>()
        .toList(growable: false);
  }

  @override
  Future<List<SemanticParseJob>> listDueSemanticParseJobs(
    Uint8List key, {
    required int nowMs,
    int limit = 5,
  }) async {
    return _jobsByMessageId.values
        .where(
          (job) =>
              job.status == 'pending' ||
              job.status == 'failed' ||
              job.status == 'running',
        )
        .take(limit)
        .toList(growable: false);
  }

  @override
  Future<void> markSemanticParseJobRunning(
    Uint8List key, {
    required String messageId,
    required int nowMs,
  }) async {
    await claimSemanticParseJobRunning(key, messageId: messageId, nowMs: nowMs);
  }

  @override
  Future<int?> claimSemanticParseJobRunning(
    Uint8List key, {
    required String messageId,
    required int nowMs,
  }) async {
    final job = _jobsByMessageId[messageId];
    if (job == null) return 0;
    final nextAttemptId = job.attemptId.toInt() + 1;
    _jobsByMessageId[messageId] = _job(
      messageId: messageId,
      status: 'running',
      createdAtMs: job.createdAtMs.toInt(),
      attemptId: nextAttemptId,
      updatedAtMs: nowMs,
    );
    return nextAttemptId;
  }

  @override
  Future<int> requeueRunningSemanticParseJobs(
    Uint8List key, {
    required int nowMs,
  }) async =>
      0;

  @override
  Future<void> markSemanticParseJobCanceled(
    Uint8List key, {
    required String messageId,
    required int nowMs,
  }) async {
    canceledMessageIds.add(messageId);
    final job = _jobsByMessageId[messageId];
    if (job == null || job.status == 'succeeded') return;
    _jobsByMessageId[messageId] = _job(
      messageId: messageId,
      status: 'canceled',
      createdAtMs: job.createdAtMs.toInt(),
      attemptId: job.attemptId.toInt(),
      updatedAtMs: nowMs,
    );
  }

  @override
  Future<bool> markSemanticParseJobCanceledIfCurrentAttempt(
    Uint8List key, {
    required String messageId,
    required int expectedAttemptId,
    required int nowMs,
  }) async {
    final job = _jobsByMessageId[messageId];
    if (job == null || job.attemptId.toInt() != expectedAttemptId) {
      return false;
    }
    await markSemanticParseJobCanceled(key, messageId: messageId, nowMs: nowMs);
    return true;
  }

  @override
  Future<void> markSemanticParseJobFailed(
    Uint8List key, {
    required String messageId,
    required int attempts,
    required int nextRetryAtMs,
    required String lastError,
    required int nowMs,
  }) async {
    final job = _jobsByMessageId[messageId];
    if (job == null || job.status == 'canceled') return;
    _jobsByMessageId[messageId] = _job(
      messageId: messageId,
      status: 'failed',
      createdAtMs: job.createdAtMs.toInt(),
      attemptId: job.attemptId.toInt(),
      updatedAtMs: nowMs,
    );
  }

  @override
  Future<bool> markSemanticParseJobFailedIfCurrentAttempt(
    Uint8List key, {
    required String messageId,
    required int expectedAttemptId,
    required int attempts,
    required int nextRetryAtMs,
    required String lastError,
    required int nowMs,
  }) async {
    final job = _jobsByMessageId[messageId];
    if (job == null || job.attemptId.toInt() != expectedAttemptId) {
      return false;
    }
    await markSemanticParseJobFailed(
      key,
      messageId: messageId,
      attempts: attempts,
      nextRetryAtMs: nextRetryAtMs,
      lastError: lastError,
      nowMs: nowMs,
    );
    return true;
  }

  @override
  Future<void> markSemanticParseJobSucceeded(
    Uint8List key, {
    required String messageId,
    required String appliedActionKind,
    String? appliedTodoId,
    String? appliedTodoTitle,
    String? appliedPrevTodoStatus,
    List<String>? suggestedTags,
    double? suggestedTagConfidence,
    String? tagSuggestionState,
    List<String>? appliedTagIds,
    required int nowMs,
  }) async {
    final job = _jobsByMessageId[messageId];
    if (job == null || job.status == 'canceled') return;
    markedSucceededMessageIds.add(messageId);
    _jobsByMessageId[messageId] = SemanticParseJob(
      messageId: messageId,
      status: 'succeeded',
      attemptId: job.attemptId,
      attempts: PlatformInt64Util.from(0),
      nextRetryAtMs: null,
      lastError: null,
      appliedActionKind: appliedActionKind,
      appliedTodoId: appliedTodoId,
      appliedTodoTitle: appliedTodoTitle,
      appliedPrevTodoStatus: appliedPrevTodoStatus,
      appliedDueChanged: false,
      suggestedTags: suggestedTags,
      suggestedTagConfidence: suggestedTagConfidence,
      tagSuggestionState: tagSuggestionState,
      appliedTagIds: appliedTagIds,
      undoneAtMs: null,
      createdAtMs: PlatformInt64Util.from(job.createdAtMs.toInt()),
      updatedAtMs: PlatformInt64Util.from(nowMs),
    );
  }

  @override
  Future<bool> markSemanticParseJobSucceededIfCurrentAttempt(
    Uint8List key, {
    required String messageId,
    required int expectedAttemptId,
    required String appliedActionKind,
    String? appliedTodoId,
    String? appliedTodoTitle,
    String? appliedPrevTodoStatus,
    List<String>? suggestedTags,
    double? suggestedTagConfidence,
    String? tagSuggestionState,
    List<String>? appliedTagIds,
    required int nowMs,
  }) async {
    final job = _jobsByMessageId[messageId];
    if (job == null || job.attemptId.toInt() != expectedAttemptId) {
      return false;
    }
    await markSemanticParseJobSucceeded(
      key,
      messageId: messageId,
      appliedActionKind: appliedActionKind,
      appliedTodoId: appliedTodoId,
      appliedTodoTitle: appliedTodoTitle,
      appliedPrevTodoStatus: appliedPrevTodoStatus,
      suggestedTags: suggestedTags,
      suggestedTagConfidence: suggestedTagConfidence,
      tagSuggestionState: tagSuggestionState,
      appliedTagIds: appliedTagIds,
      nowMs: nowMs,
    );
    return true;
  }

  @override
  Future<List<Todo>> listTodos(Uint8List key) async {
    return List<Todo>.from(_todos);
  }

  @override
  Future<List<SecretaryMemoryProposalRecord>> listSecretaryMemoryProposals(
    Uint8List key, {
    String? state,
  }) async =>
      const <SecretaryMemoryProposalRecord>[];

  @override
  Future<List<PlanningOutputRecord>> listPlanningOutputs(
    Uint8List key, {
    String? kind,
    required int nowMs,
    bool includeExpired = false,
  }) async =>
      const <PlanningOutputRecord>[];

  @override
  Future<PlanningOutputRecord> upsertPlanningOutput(
    Uint8List key, {
    required String id,
    required String kind,
    required String title,
    required String body,
    required String itemsJson,
    String? sourceRefsJson,
    required String route,
    required String state,
    required int createdAtMs,
    required int updatedAtMs,
    int? expiresAtMs,
  }) async {
    return PlanningOutputRecord(
      id: id,
      kind: kind,
      title: title,
      body: body,
      itemsJson: itemsJson,
      sourceRefsJson: sourceRefsJson,
      route: route,
      state: state,
      createdAtMs: PlatformInt64Util.from(createdAtMs),
      updatedAtMs: PlatformInt64Util.from(updatedAtMs),
      expiresAtMs:
          expiresAtMs == null ? null : PlatformInt64Util.from(expiresAtMs),
    );
  }

  @override
  Future<Todo> upsertTodoFromSemanticCreate(
    Uint8List key, {
    required String id,
    required String title,
    int? dueAtMs,
    required String status,
    String? sourceEntryId,
    int? reviewStage,
    int? nextReviewAtMs,
    int? lastReviewAtMs,
    String? followupTaskTypeHint,
  }) async {
    final todo = Todo(
      id: id,
      title: title,
      dueAtMs: dueAtMs,
      status: status,
      sourceEntryId: sourceEntryId,
      reviewStage: reviewStage,
      nextReviewAtMs: nextReviewAtMs,
      lastReviewAtMs: lastReviewAtMs,
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
    );
    createdTodos.removeWhere((existing) => existing.id == id);
    createdTodos.add(todo);
    _todos.removeWhere((existing) => existing.id == id);
    _todos.add(todo);
    return todo;
  }

  @override
  Future<bool> completeSemanticParseFollowupIfCurrentAttempt(
    Uint8List key, {
    required String messageId,
    required int expectedAttemptId,
    required String todoId,
    String? todoTitle,
    String? newStatus,
    int? dueAtMs,
    List<String>? pendingSuggestedTags,
    List<String>? autoApplySuggestedTags,
    double? suggestedTagConfidence,
    required int nowMs,
  }) async {
    final job = _jobsByMessageId[messageId];
    if (job == null ||
        job.attemptId.toInt() != expectedAttemptId ||
        job.status == 'canceled') {
      return false;
    }

    final index = _todos.indexWhere((todo) => todo.id == todoId);
    if (index >= 0) {
      final existing = _todos[index];
      _todos[index] = Todo(
        id: existing.id,
        title: todoTitle ?? existing.title,
        dueAtMs: dueAtMs ?? existing.dueAtMs,
        status: (newStatus?.trim().isNotEmpty ?? false)
            ? newStatus!.trim()
            : existing.status,
        sourceEntryId: existing.sourceEntryId,
        reviewStage: existing.reviewStage,
        nextReviewAtMs: existing.nextReviewAtMs,
        lastReviewAtMs: existing.lastReviewAtMs,
        createdAtMs: existing.createdAtMs,
        updatedAtMs: nowMs,
      );
    }
    completedFollowupTodoIds.add(todoId);
    await markSemanticParseJobSucceeded(
      key,
      messageId: messageId,
      appliedActionKind: 'followup',
      appliedTodoId: todoId,
      appliedTodoTitle: todoTitle,
      appliedPrevTodoStatus: null,
      nowMs: nowMs,
    );
    return true;
  }

  @override
  Future<String?> upsertTodoFromSemanticParseIfCurrentAttempt(
    Uint8List key, {
    required String messageId,
    required int expectedAttemptId,
    required String todoId,
    required String title,
    int? dueAtMs,
    required String status,
    int? reviewStage,
    int? nextReviewAtMs,
    int? lastReviewAtMs,
    String? taskTypeHint,
    String? recurrenceRuleJson,
    required int nowMs,
  }) async {
    final job = _jobsByMessageId[messageId];
    if (job == null || job.attemptId.toInt() != expectedAttemptId) {
      return null;
    }
    await upsertTodoFromSemanticCreate(
      key,
      id: todoId,
      title: title,
      dueAtMs: dueAtMs,
      status: status,
      sourceEntryId: messageId,
      reviewStage: reviewStage,
      nextReviewAtMs: nextReviewAtMs,
      lastReviewAtMs: lastReviewAtMs,
      followupTaskTypeHint: taskTypeHint,
    );
    return todoId;
  }

  @override
  Future<List<LlmProfile>> listLlmProfiles(Uint8List key) async {
    return const <LlmProfile>[
      LlmProfile(
        id: 'llm:active',
        name: 'BYOK',
        providerType: 'openai-compatible',
        modelName: 'gpt-4.1-mini',
        isActive: true,
        createdAtMs: 0,
        updatedAtMs: 0,
      ),
    ];
  }

  @override
  Future<List<EmbeddingProfile>> listEmbeddingProfiles(Uint8List key) async {
    return const <EmbeddingProfile>[];
  }

  @override
  Future<int> processPendingTodoThreadEmbeddings(
    Uint8List key, {
    int todoLimit = 16,
    int activityLimit = 32,
  }) async {
    return 0;
  }

  @override
  Future<List<TodoThreadMatch>> searchSimilarTodoThreads(
    Uint8List key,
    String query, {
    int topK = 8,
  }) async {
    return const <TodoThreadMatch>[];
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
    if (!parseStarted.isCompleted) {
      parseStarted.complete();
    }
    return _lateParseResponse.future;
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
    required List<rust_semantic.TodoCandidate> candidates,
  }) async {
    if (!parseStarted.isCompleted) {
      parseStarted.complete();
    }
    return _lateParseResponse.future;
  }

  Future<String> runAiPrompt(
    Uint8List key, {
    required String prompt,
  }) async {
    return '{"suggestions":[]}';
  }

  @override
  Future<bool> releaseLocalEmbeddingModelIfIdle(
    Uint8List key, {
    int maxIdleMs = 180000,
  }) async {
    return false;
  }
}
