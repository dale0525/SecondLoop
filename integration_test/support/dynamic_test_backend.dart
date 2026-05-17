import 'dart:convert';
import 'dart:typed_data';

import 'package:secondloop/core/backend/secretary_backend.dart';
import 'package:secondloop/core/models/app_models.dart';
import 'package:secondloop/core/models/platform_int.dart';

import '../../test/test_backend.dart';

final class DynamicTestBackend extends TestAppBackend
    implements SecretaryBackend {
  DynamicTestBackend({
    List<Message> initialMessages = const <Message>[],
    List<Todo> todos = const <Todo>[],
  })  : _messagesByConversation = <String, List<Message>>{
          'loop_home': List<Message>.from(initialMessages),
        },
        _todosById = <String, Todo>{
          for (final todo in todos) todo.id: todo,
        },
        super(initialMessages: initialMessages);

  final Map<String, List<Message>> _messagesByConversation;
  final Map<String, Todo> _todosById;
  final List<SecretaryMemoryProposalRecord> _memoryProposals =
      <SecretaryMemoryProposalRecord>[];
  final List<MemoryPageRecord> _memoryPages = <MemoryPageRecord>[];
  final Map<String, PlanningOutputRecord> _planningOutputs =
      <String, PlanningOutputRecord>{};
  final List<SecretaryRunRecord> _secretaryRuns = <SecretaryRunRecord>[];
  final List<SecretaryToolCallRecord> _secretaryToolCalls =
      <SecretaryToolCallRecord>[];

  final List<String> debugTrace = <String>[];
  var listTodosCalls = 0;
  var upsertTodoCalls = 0;
  var transitionTodoCalls = 0;
  var setTodoStatusCalls = 0;
  var acceptMemoryProposalCalls = 0;
  var dismissMemoryProposalCalls = 0;
  var upsertPlanningOutputCalls = 0;

  List<Message> get insertedUserMessages {
    return _messagesByConversation.values
        .expand((messages) => messages)
        .where((message) => message.role == 'user')
        .toList(growable: false);
  }

  List<MemoryPageRecord> get memoryPages =>
      List<MemoryPageRecord>.from(_memoryPages);

  List<SecretaryMemoryProposalRecord> get memoryProposals =>
      List<SecretaryMemoryProposalRecord>.from(_memoryProposals);

  List<PlanningOutputRecord> get planningOutputs =>
      _planningOutputs.values.toList(growable: false);

  List<SecretaryRunRecord> get secretaryRuns =>
      _secretaryRuns.toList(growable: false);

  List<SecretaryToolCallRecord> get secretaryToolCalls =>
      _secretaryToolCalls.toList(growable: false);

  Todo? todoById(String id) => _todosById[id];

  static Todo todo({
    required String id,
    required String title,
    String status = 'open',
    int? dueAtMs,
    int createdAtMs = 1000,
    int updatedAtMs = 1000,
    int manualImportanceNudgeScore = 0,
    int manualUrgencyNudgeScore = 0,
  }) {
    return Todo(
      id: id,
      title: title,
      dueAtMs: dueAtMs == null ? null : platformIntFromInt(dueAtMs),
      status: status,
      sourceEntryId: null,
      createdAtMs: platformIntFromInt(createdAtMs),
      updatedAtMs: platformIntFromInt(updatedAtMs),
      reviewStage: null,
      nextReviewAtMs: null,
      lastReviewAtMs: null,
      manualImportanceNudgeScore: platformIntFromInt(
        manualImportanceNudgeScore,
      ),
      manualUrgencyNudgeScore: platformIntFromInt(
        manualUrgencyNudgeScore,
      ),
    );
  }

  @override
  Future<List<Message>> listMessages(
    Uint8List key,
    String conversationId,
  ) async {
    debugTrace.add('listMessages:$conversationId');
    return List<Message>.from(
      _messagesByConversation[conversationId] ?? const <Message>[],
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
    debugTrace.add('listMessagesPage:$conversationId');
    final messages = List<Message>.from(
      _messagesByConversation[conversationId] ?? const <Message>[],
    )..sort((a, b) => b.createdAtMs.compareTo(a.createdAtMs));
    if (beforeCreatedAtMs == null || beforeId == null) {
      return messages.take(limit).toList(growable: false);
    }
    final cursor = messages.indexWhere((message) => message.id == beforeId);
    if (cursor < 0) return const <Message>[];
    return messages.skip(cursor + 1).take(limit).toList(growable: false);
  }

  @override
  Future<Message?> getMessageById(Uint8List key, String messageId) async {
    for (final message
        in _messagesByConversation.values.expand((list) => list)) {
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
    final messages =
        _messagesByConversation.putIfAbsent(conversationId, () => <Message>[]);
    final message = Message(
      id: 'm${messages.length + 1}',
      conversationId: conversationId,
      role: role,
      content: content,
      createdAtMs: platformIntFromInt(messages.length + 1),
      isMemory: true,
    );
    messages.add(message);
    debugTrace.add('insertMessage:${message.id}:$role:$content');
    return message;
  }

  @override
  Future<void> editMessage(
    Uint8List key,
    String messageId,
    String content,
  ) async {
    for (final entry in _messagesByConversation.entries) {
      final messages = entry.value;
      for (var i = 0; i < messages.length; i++) {
        final message = messages[i];
        if (message.id != messageId) continue;
        messages[i] = Message(
          id: message.id,
          conversationId: message.conversationId,
          role: message.role,
          content: content,
          createdAtMs: message.createdAtMs,
          isMemory: message.isMemory,
        );
        debugTrace.add('editMessage:$messageId');
        return;
      }
    }
  }

  @override
  Future<void> setMessageDeleted(
    Uint8List key,
    String messageId,
    bool isDeleted,
  ) async {
    for (final messages in _messagesByConversation.values) {
      messages.removeWhere((message) => message.id == messageId);
    }
    debugTrace.add('setMessageDeleted:$messageId:$isDeleted');
  }

  @override
  Future<List<Todo>> listTodos(Uint8List key) async {
    listTodosCalls += 1;
    debugTrace.add('listTodos');
    return _todosById.values.toList(growable: false);
  }

  @override
  Future<Todo?> getTodoById(Uint8List key, String todoId) async {
    debugTrace.add('getTodoById:$todoId');
    return _todosById[todoId];
  }

  @override
  Future<List<Todo>> listTodosCreatedInRange(
    Uint8List key, {
    required int startAtMsInclusive,
    required int endAtMsExclusive,
  }) async {
    return _todosById.values.where((todo) {
      final createdAtMs = platformIntToInt(todo.createdAtMs);
      return createdAtMs >= startAtMsInclusive &&
          createdAtMs < endAtMsExclusive;
    }).toList(growable: false);
  }

  @override
  Future<Todo> upsertTodo(
    Uint8List key, {
    required String id,
    required String title,
    int? dueAtMs,
    required String status,
    String? sourceEntryId,
    int? reviewStage,
    int? nextReviewAtMs,
    int? lastReviewAtMs,
    int? manualImportanceNudgeScore,
    int? manualUrgencyNudgeScore,
  }) async {
    upsertTodoCalls += 1;
    final existing = _todosById[id];
    final todo = _copyTodo(
      existing,
      id: id,
      title: title,
      dueAtMs: dueAtMs,
      status: status,
      sourceEntryId: sourceEntryId,
      reviewStage: reviewStage,
      nextReviewAtMs: nextReviewAtMs,
      lastReviewAtMs: lastReviewAtMs,
      manualImportanceNudgeScore: manualImportanceNudgeScore,
      manualUrgencyNudgeScore: manualUrgencyNudgeScore,
    );
    _todosById[id] = todo;
    debugTrace.add('upsertTodo:$id:$title:$status');
    return todo;
  }

  @override
  Future<Todo> setTodoStatus(
    Uint8List key, {
    required String todoId,
    required String newStatus,
    String? sourceMessageId,
  }) async {
    setTodoStatusCalls += 1;
    return transitionTodo(
      key,
      todoId: todoId,
      newStatus: newStatus,
      sourceMessageId: sourceMessageId,
    );
  }

  @override
  Future<Todo> transitionTodo(
    Uint8List key, {
    required String todoId,
    String? newStatus,
    int? dueAtMs,
    bool clearDueAtMs = false,
    int? reviewStage,
    bool clearReviewStage = false,
    int? nextReviewAtMs,
    bool clearNextReviewAtMs = false,
    int? lastReviewAtMs,
    bool clearLastReviewAtMs = false,
    int? manualImportanceNudgeScore,
    bool clearManualImportanceNudgeScore = false,
    int? manualUrgencyNudgeScore,
    bool clearManualUrgencyNudgeScore = false,
    String? sourceMessageId,
  }) async {
    transitionTodoCalls += 1;
    final existing = _todosById[todoId];
    if (existing == null) {
      throw StateError('Missing todo $todoId');
    }
    final todo = _copyTodo(
      existing,
      id: existing.id,
      title: existing.title,
      dueAtMs: clearDueAtMs
          ? null
          : dueAtMs ?? platformIntToNullableInt(existing.dueAtMs),
      status: newStatus ?? existing.status,
      sourceEntryId: existing.sourceEntryId,
      reviewStage: clearReviewStage
          ? null
          : reviewStage ?? platformIntToNullableInt(existing.reviewStage),
      nextReviewAtMs: clearNextReviewAtMs
          ? null
          : nextReviewAtMs ?? platformIntToNullableInt(existing.nextReviewAtMs),
      lastReviewAtMs: clearLastReviewAtMs
          ? null
          : lastReviewAtMs ?? platformIntToNullableInt(existing.lastReviewAtMs),
      manualImportanceNudgeScore: clearManualImportanceNudgeScore
          ? 0
          : manualImportanceNudgeScore ??
              platformIntToNullableInt(existing.manualImportanceNudgeScore) ??
              0,
      manualUrgencyNudgeScore: clearManualUrgencyNudgeScore
          ? 0
          : manualUrgencyNudgeScore ??
              platformIntToNullableInt(existing.manualUrgencyNudgeScore) ??
              0,
    );
    _todosById[todoId] = todo;
    debugTrace.add('transitionTodo:$todoId:${todo.status}');
    return todo;
  }

  @override
  Future<SecretaryMemoryProposalRecord> createSecretaryMemoryProposal(
    Uint8List key, {
    String? sourceMessageId,
    required String kind,
    required String title,
    required String body,
    required double confidence,
    String? sourceRefsJson,
    String? actionHint,
    required int nowMs,
  }) async {
    final record = SecretaryMemoryProposalRecord(
      id: 'memory-proposal-${sourceMessageId ?? _memoryProposals.length + 1}',
      sourceMessageId: sourceMessageId,
      kind: kind,
      title: title,
      body: body,
      confidence: confidence,
      state: 'pending',
      sourceRefsJson: sourceRefsJson,
      actionHint: actionHint,
      createdAtMs: platformIntFromInt(nowMs),
      updatedAtMs: platformIntFromInt(nowMs),
      acceptedAtMs: null,
      dismissedAtMs: null,
    );
    _memoryProposals.add(record);
    debugTrace.add('createSecretaryMemoryProposal:${record.id}');
    return record;
  }

  @override
  Future<List<SecretaryMemoryProposalRecord>> listSecretaryMemoryProposals(
    Uint8List key, {
    String? state,
  }) async {
    return _memoryProposals
        .where((record) => state == null || record.state == state)
        .toList(growable: false);
  }

  @override
  Future<MemoryPageRecord> acceptSecretaryMemoryProposal(
    Uint8List key, {
    required String proposalId,
    required int nowMs,
  }) async {
    acceptMemoryProposalCalls += 1;
    final index = _memoryProposals.indexWhere((record) {
      return record.id == proposalId;
    });
    if (index < 0) throw StateError('Missing memory proposal $proposalId');
    final proposal = _memoryProposals[index];
    _memoryProposals[index] = _copyProposal(
      proposal,
      state: 'accepted',
      updatedAtMs: nowMs,
      acceptedAtMs: nowMs,
    );
    final page = MemoryPageRecord(
      pageId: 'memory-${proposal.sourceMessageId ?? proposal.id}',
      pageType: proposal.kind,
      state: 'active',
      sourceCount: platformIntFromInt(1),
      title: proposal.title,
      summary: proposal.title,
      body: proposal.body,
      primaryEvidenceJson: jsonEncode({
        'message_ids': [
          if (proposal.sourceMessageId != null) proposal.sourceMessageId,
        ],
      }),
      sourceDocumentIdsJson: '[]',
      confidenceLevel: proposal.confidence,
      humanCorrected: false,
      createdAtMs: platformIntFromInt(nowMs),
      updatedAtMs: platformIntFromInt(nowMs),
    );
    _memoryPages.add(page);
    debugTrace.add('acceptSecretaryMemoryProposal:$proposalId');
    return page;
  }

  @override
  Future<SecretaryMemoryProposalRecord> dismissSecretaryMemoryProposal(
    Uint8List key, {
    required String proposalId,
    required int nowMs,
  }) async {
    dismissMemoryProposalCalls += 1;
    final index = _memoryProposals.indexWhere((record) {
      return record.id == proposalId;
    });
    if (index < 0) throw StateError('Missing memory proposal $proposalId');
    final updated = _copyProposal(
      _memoryProposals[index],
      state: 'dismissed',
      updatedAtMs: nowMs,
      dismissedAtMs: nowMs,
    );
    _memoryProposals[index] = updated;
    debugTrace.add('dismissSecretaryMemoryProposal:$proposalId');
    return updated;
  }

  @override
  Future<List<MemoryPageRecord>> listMemoryPages(
    Uint8List key, {
    String? state,
  }) async {
    return _memoryPages
        .where((record) => state == null || record.state == state)
        .toList(growable: false);
  }

  @override
  Future<MemoryPageRecord> getMemoryPage(
    Uint8List key, {
    required String pageId,
  }) async {
    return _memoryPages.firstWhere((record) => record.pageId == pageId);
  }

  @override
  Future<MemoryPageRecord> correctMemoryPage(
    Uint8List key, {
    required String pageId,
    required String title,
    required String summary,
    required String body,
    String? reason,
    required int nowMs,
  }) async {
    final index = _memoryPages.indexWhere((record) => record.pageId == pageId);
    if (index < 0) throw StateError('Missing memory page $pageId');
    final existing = _memoryPages[index];
    final updated = MemoryPageRecord(
      pageId: existing.pageId,
      pageType: existing.pageType,
      state: existing.state,
      sourceCount: existing.sourceCount,
      title: title,
      summary: summary,
      body: body,
      primaryEvidenceJson: existing.primaryEvidenceJson,
      sourceDocumentIdsJson: existing.sourceDocumentIdsJson,
      confidenceLevel: existing.confidenceLevel,
      humanCorrected: true,
      createdAtMs: existing.createdAtMs,
      updatedAtMs: platformIntFromInt(nowMs),
    );
    _memoryPages[index] = updated;
    return updated;
  }

  @override
  Future<MemoryPageRecord> archiveMemoryPage(
    Uint8List key, {
    required String pageId,
    required int nowMs,
  }) async {
    return _setMemoryPageState(pageId, 'archived', nowMs);
  }

  @override
  Future<MemoryPageRecord> restoreMemoryPage(
    Uint8List key, {
    required String pageId,
    required int nowMs,
  }) async {
    return _setMemoryPageState(pageId, 'active', nowMs);
  }

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
    upsertPlanningOutputCalls += 1;
    final record = PlanningOutputRecord(
      id: id,
      kind: kind,
      title: title,
      body: body,
      itemsJson: itemsJson,
      sourceRefsJson: sourceRefsJson,
      route: route,
      state: state,
      createdAtMs: platformIntFromInt(createdAtMs),
      updatedAtMs: platformIntFromInt(updatedAtMs),
      expiresAtMs: expiresAtMs == null ? null : platformIntFromInt(expiresAtMs),
      dismissedAtMs: null,
    );
    _planningOutputs[id] = record;
    debugTrace.add('upsertPlanningOutput:$id');
    return record;
  }

  @override
  Future<List<PlanningOutputRecord>> listPlanningOutputs(
    Uint8List key, {
    String? kind,
    required int nowMs,
    bool includeExpired = false,
  }) async {
    return _planningOutputs.values.where((record) {
      if (kind != null && record.kind != kind) return false;
      if (includeExpired) return true;
      final expiresAtMs = platformIntToNullableInt(record.expiresAtMs);
      return expiresAtMs == null || expiresAtMs > nowMs;
    }).toList(growable: false);
  }

  @override
  Future<SecretaryRunRecord> createSecretaryRun(
    Uint8List key, {
    required String triggerKind,
    required String route,
    required String status,
    String? inputSummary,
    String? outputSummary,
    String? error,
    required int nowMs,
  }) async {
    final record = SecretaryRunRecord(
      id: 'secretary-run-${_secretaryRuns.length + 1}',
      triggerKind: triggerKind,
      route: route,
      status: status,
      inputSummary: inputSummary,
      outputSummary: outputSummary,
      error: error,
      createdAtMs: platformIntFromInt(nowMs),
      updatedAtMs: platformIntFromInt(nowMs),
    );
    _secretaryRuns.add(record);
    return record;
  }

  @override
  Future<SecretaryToolCallRecord> createSecretaryToolCall(
    Uint8List key, {
    required String runId,
    required String toolName,
    required String status,
    required bool requiresConfirmation,
    String? inputJson,
    String? outputJson,
    required int nowMs,
  }) async {
    final record = SecretaryToolCallRecord(
      id: 'secretary-tool-call-${_secretaryToolCalls.length + 1}',
      runId: runId,
      toolName: toolName,
      status: status,
      requiresConfirmation: requiresConfirmation,
      inputJson: inputJson,
      outputJson: outputJson,
      createdAtMs: platformIntFromInt(nowMs),
      updatedAtMs: platformIntFromInt(nowMs),
    );
    _secretaryToolCalls.add(record);
    return record;
  }

  @override
  Future<List<SecretaryToolCallRecord>> listSecretaryToolCallsForRun(
    Uint8List key, {
    required String runId,
  }) async {
    return _secretaryToolCalls
        .where((record) => record.runId == runId)
        .toList(growable: false);
  }

  Todo _copyTodo(
    Todo? existing, {
    required String id,
    required String title,
    int? dueAtMs,
    required String status,
    String? sourceEntryId,
    int? reviewStage,
    int? nextReviewAtMs,
    int? lastReviewAtMs,
    int? manualImportanceNudgeScore,
    int? manualUrgencyNudgeScore,
  }) {
    final nowMs = platformIntFromInt(DateTime.now().millisecondsSinceEpoch);
    return Todo(
      id: id,
      title: title,
      dueAtMs: dueAtMs == null ? null : platformIntFromInt(dueAtMs),
      status: status,
      sourceEntryId: sourceEntryId,
      createdAtMs: existing?.createdAtMs ?? nowMs,
      updatedAtMs: nowMs,
      reviewStage: reviewStage == null ? null : platformIntFromInt(reviewStage),
      nextReviewAtMs:
          nextReviewAtMs == null ? null : platformIntFromInt(nextReviewAtMs),
      lastReviewAtMs:
          lastReviewAtMs == null ? null : platformIntFromInt(lastReviewAtMs),
      manualImportanceNudgeScore: platformIntFromInt(
        manualImportanceNudgeScore ?? 0,
      ),
      manualUrgencyNudgeScore: platformIntFromInt(
        manualUrgencyNudgeScore ?? 0,
      ),
    );
  }

  SecretaryMemoryProposalRecord _copyProposal(
    SecretaryMemoryProposalRecord existing, {
    required String state,
    required int updatedAtMs,
    int? acceptedAtMs,
    int? dismissedAtMs,
  }) {
    return SecretaryMemoryProposalRecord(
      id: existing.id,
      sourceMessageId: existing.sourceMessageId,
      kind: existing.kind,
      title: existing.title,
      body: existing.body,
      confidence: existing.confidence,
      state: state,
      sourceRefsJson: existing.sourceRefsJson,
      actionHint: existing.actionHint,
      createdAtMs: existing.createdAtMs,
      updatedAtMs: platformIntFromInt(updatedAtMs),
      acceptedAtMs: acceptedAtMs == null
          ? existing.acceptedAtMs
          : platformIntFromInt(acceptedAtMs),
      dismissedAtMs: dismissedAtMs == null
          ? existing.dismissedAtMs
          : platformIntFromInt(dismissedAtMs),
    );
  }

  MemoryPageRecord _setMemoryPageState(
    String pageId,
    String state,
    int nowMs,
  ) {
    final index = _memoryPages.indexWhere((record) => record.pageId == pageId);
    if (index < 0) throw StateError('Missing memory page $pageId');
    final existing = _memoryPages[index];
    final updated = MemoryPageRecord(
      pageId: existing.pageId,
      pageType: existing.pageType,
      state: state,
      sourceCount: existing.sourceCount,
      title: existing.title,
      summary: existing.summary,
      body: existing.body,
      primaryEvidenceJson: existing.primaryEvidenceJson,
      sourceDocumentIdsJson: existing.sourceDocumentIdsJson,
      confidenceLevel: existing.confidenceLevel,
      humanCorrected: existing.humanCorrected,
      createdAtMs: existing.createdAtMs,
      updatedAtMs: platformIntFromInt(nowMs),
    );
    _memoryPages[index] = updated;
    return updated;
  }
}
