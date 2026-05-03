import 'dart:convert';
import 'dart:typed_data';

import '../backend/secretary_backend.dart';
import '../cloud/cloud_secretary_client.dart';
import '../../src/rust/db.dart';
import '../../src/rust/platform_int.dart';
import 'internal_tool_registry.dart';
import 'memory_proposal_detector.dart';
import 'rule_based_planning_engine.dart';
import 'secretary_ai_service.dart';
import 'secretary_models.dart';

class SecretaryController {
  SecretaryController({
    MemoryProposalDetector detector = const MemoryProposalDetector(),
    SecretaryBackend? backend,
    SecretaryAiService? aiService,
    SecretaryAiRouteConfig aiRouteConfig =
        const SecretaryAiRouteConfig.localOnly(),
    Duration aiTimeout = const Duration(seconds: 8),
    required RuleBasedPlanningEngine planningEngine,
  })  : _detector = detector,
        _backend = backend,
        _aiService = aiService,
        _aiRouteConfig = aiRouteConfig,
        _aiTimeout = aiTimeout,
        _planningEngine = planningEngine;

  final MemoryProposalDetector _detector;
  final SecretaryBackend? _backend;
  final SecretaryAiService? _aiService;
  final SecretaryAiRouteConfig _aiRouteConfig;
  final Duration _aiTimeout;
  final RuleBasedPlanningEngine _planningEngine;
  final Set<String> _acceptedProposalSourceIds = <String>{};
  final Set<String> _dismissedProposalSourceIds = <String>{};
  final Set<String> _acceptedProposalSignatures = <String>{};
  final Set<String> _dismissedProposalSignatures = <String>{};
  final Set<String> _dismissedPlanIds = <String>{};
  static const double _localMemoryHighConfidence = 0.82;
  static const double _localMemoryPersistConfidence = 0.70;
  static const int _digestMaxSectionItems = 40;
  static const int _digestMaxCaptureItems = 20;
  static const int _digestTitleMaxChars = 160;
  static const int _digestBodyMaxChars = 700;

  List<SecretaryMemoryProposal> pendingMemoryProposalsForMessages(
    List<Message> messages,
  ) {
    final proposalsBySignature = <String, SecretaryMemoryProposal>{};
    for (final message in messages) {
      if (message.role != 'user') continue;
      if (_acceptedProposalSourceIds.contains(message.id)) continue;
      if (_dismissedProposalSourceIds.contains(message.id)) continue;
      final proposal = _detector.detect(
        messageId: message.id,
        text: message.content,
        createdAtMs: platformIntToInt(message.createdAtMs),
      );
      if (proposal == null) continue;
      final signature = secretaryMemoryProposalSignature(proposal);
      if (_acceptedProposalSignatures.contains(signature)) continue;
      if (_dismissedProposalSignatures.contains(signature)) continue;
      final existing = proposalsBySignature[signature];
      if (existing == null || proposal.createdAtMs > existing.createdAtMs) {
        proposalsBySignature[signature] = proposal;
      }
    }
    final proposals = proposalsBySignature.values.toList(growable: false);
    proposals.sort((a, b) => b.createdAtMs.compareTo(a.createdAtMs));
    return proposals;
  }

  Future<SecretaryMemoryProposal?> persistMemoryProposalForMessage(
    Uint8List key,
    Message message, {
    required int nowMs,
  }) async {
    if (message.role != 'user') return null;
    final canUseAi = _canEnhanceMemoryWithAi;
    final detected = _detector.detect(
      messageId: message.id,
      text: message.content,
      createdAtMs: platformIntToInt(message.createdAtMs),
      includeWeakSignals: canUseAi,
    );
    if (detected == null) return null;

    final backend = _backend;
    if (backend == null) {
      if (_acceptedProposalSourceIds.contains(message.id) ||
          _dismissedProposalSourceIds.contains(message.id)) {
        return null;
      }
      return _routedMemoryProposal(key, detected);
    }

    final existing = await backend.listSecretaryMemoryProposals(key);
    final existingPages = await backend.listMemoryPages(key);
    if (existing.any((proposal) => proposal.sourceMessageId == message.id)) {
      return null;
    }

    final routed = await _routedMemoryProposal(key, detected);
    if (routed == null) return null;

    final routedSignature = secretaryMemoryProposalSignature(routed);
    final alreadyTracked = existing.any(
      (proposal) =>
          secretaryMemoryProposalSignature(_proposalFromRecord(proposal)) ==
          routedSignature,
    );
    if (alreadyTracked) return null;
    final alreadySaved = existingPages.any(
      (page) =>
          secretaryMemoryPageSignature(_memoryPageFromRecord(page)) ==
          routedSignature,
    );
    if (alreadySaved) return null;

    final record = await backend.createSecretaryMemoryProposal(
      key,
      sourceMessageId: routed.sourceMessageId,
      kind: routed.kind,
      title: routed.title,
      body: routed.body,
      confidence: routed.confidence,
      sourceRefsJson: jsonEncode({
        'message_ids': [routed.sourceMessageId],
      }),
      actionHint: routed.actionHint,
      nowMs: nowMs,
    );
    return _proposalFromRecord(record);
  }

  bool get _canEnhanceMemoryWithAi =>
      _aiService != null && _aiRouteConfig.canCallAi;

  Future<SecretaryMemoryProposal?> _routedMemoryProposal(
    Uint8List key,
    SecretaryMemoryProposal detected,
  ) async {
    if (!_canEnhanceMemoryWithAi ||
        detected.confidence >= _localMemoryHighConfidence) {
      return _canPersistLocalMemoryProposal(detected) ? detected : null;
    }

    final draft = await _aiService!.tryEnhanceMemoryProposal(
      key,
      proposal: detected,
      routeConfig: _aiRouteConfig,
      timeout: _aiTimeout,
    );
    if (draft != null) {
      return SecretaryMemoryProposal(
        id: detected.id,
        sourceMessageId: detected.sourceMessageId,
        kind: draft.kind,
        title: draft.title,
        body: draft.body,
        confidence: draft.confidence,
        createdAtMs: detected.createdAtMs,
        actionHint: detected.actionHint,
      );
    }

    return _canPersistLocalMemoryProposal(detected) ? detected : null;
  }

  bool _canPersistLocalMemoryProposal(SecretaryMemoryProposal proposal) {
    return proposal.confidence >= _localMemoryPersistConfidence;
  }

  Future<List<SecretaryMemoryProposal>> pendingMemoryProposals(
    Uint8List key,
  ) async {
    final backend = _backend;
    if (backend == null) return const <SecretaryMemoryProposal>[];
    final records = await backend.listSecretaryMemoryProposals(
      key,
      state: 'pending',
    );
    return _dedupeMemoryProposals(
      records.map(_proposalFromRecord),
    );
  }

  Future<SecretaryMemoryPage> acceptMemoryProposal(
    Uint8List key,
    SecretaryMemoryProposal proposal, {
    required int nowMs,
  }) async {
    final backend = _backend;
    if (backend != null) {
      final record = await backend.acceptSecretaryMemoryProposal(
        key,
        proposalId: proposal.id,
        nowMs: nowMs,
      );
      _acceptedProposalSourceIds.add(proposal.sourceMessageId);
      _acceptedProposalSignatures
          .add(secretaryMemoryProposalSignature(proposal));
      return _memoryPageFromRecord(record);
    }

    _acceptedProposalSourceIds.add(proposal.sourceMessageId);
    _acceptedProposalSignatures.add(secretaryMemoryProposalSignature(proposal));
    return SecretaryMemoryPage(
      id: 'memory-${proposal.sourceMessageId}',
      title: proposal.title,
      body: proposal.body,
      state: SecretaryMemoryState.active,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
      kind: proposal.kind,
      sourceMessageId: proposal.sourceMessageId,
    );
  }

  Future<void> dismissMemoryProposal(
    Uint8List key,
    SecretaryMemoryProposal proposal, {
    required int nowMs,
  }) async {
    final backend = _backend;
    if (backend != null) {
      await backend.dismissSecretaryMemoryProposal(
        key,
        proposalId: proposal.id,
        nowMs: nowMs,
      );
    }
    _dismissedProposalSourceIds.add(proposal.sourceMessageId);
    _dismissedProposalSignatures
        .add(secretaryMemoryProposalSignature(proposal));
  }

  SecretaryPlan generatePlan(List<Todo> todos) {
    final plan = _planningEngine.generateDailyPlan(todos);
    if (_dismissedPlanIds.contains(plan.id)) {
      return const SecretaryPlan(
        id: 'dismissed',
        title: 'Daily plan',
        generatedAtMs: 0,
        route: 'local_rules',
        sections: SecretaryPlanSections.empty(),
      );
    }
    return plan;
  }

  Future<SecretaryPlan> generateAndPersistPlan(
    Uint8List key,
    List<Todo> todos, {
    required int nowMs,
    SecretaryAiRouteConfig? aiRouteConfig,
    String localeTag = 'en-US',
  }) async {
    var plan = generatePlan(todos);
    final aiService = _aiService;
    final routeConfig = aiRouteConfig ?? _aiRouteConfig;
    if (aiService != null && !plan.sections.isEmpty && routeConfig.canCallAi) {
      final enhancement = await aiService.tryEnhancePlan(
        key,
        localPlan: plan,
        routeConfig: routeConfig,
        localeTag: localeTag,
        timeout: _aiTimeout,
      );
      plan = enhancement?.applyToPlan(plan) ?? plan;
    }
    final backend = _backend;
    if (backend == null || plan.sections.isEmpty) return plan;

    final existing = await backend.listPlanningOutputs(
      key,
      kind: 'daily_plan',
      nowMs: nowMs,
      includeExpired: true,
    );
    for (final record in existing) {
      if (record.id == plan.id || record.state == 'expired') continue;
      await backend.upsertPlanningOutput(
        key,
        id: record.id,
        kind: record.kind,
        title: record.title,
        body: record.body,
        itemsJson: record.itemsJson,
        sourceRefsJson: record.sourceRefsJson,
        route: record.route,
        state: 'expired',
        createdAtMs: platformIntToInt(record.createdAtMs),
        updatedAtMs: nowMs,
        expiresAtMs: platformIntToNullableInt(record.expiresAtMs),
      );
    }

    await backend.upsertPlanningOutput(
      key,
      id: plan.id,
      kind: 'daily_plan',
      title: plan.title,
      body: _planBody(plan),
      itemsJson: _planItemsJson(plan),
      sourceRefsJson: _planSourceRefsJson(plan),
      route: plan.route,
      state: 'active',
      createdAtMs: plan.generatedAtMs,
      updatedAtMs: nowMs,
      expiresAtMs: _endOfLocalDayMs(nowMs),
    );
    return plan;
  }

  Future<SecretaryAuditTrail> recordSecretaryRun(
    Uint8List key, {
    required String triggerKind,
    required String route,
    required String status,
    String? inputSummary,
    String? outputSummary,
    String? error,
    required int nowMs,
    List<SecretaryToolCallDraft> toolCalls = const <SecretaryToolCallDraft>[],
  }) async {
    final backend = _backend;
    if (backend == null) {
      throw StateError('SecretaryBackend is required to record audit runs.');
    }
    final run = await backend.createSecretaryRun(
      key,
      triggerKind: triggerKind,
      route: route,
      status: status,
      inputSummary: inputSummary,
      outputSummary: outputSummary,
      error: error,
      nowMs: nowMs,
    );
    final records = <SecretaryToolCallRecord>[];
    for (final call in toolCalls) {
      records.add(
        await backend.createSecretaryToolCall(
          key,
          runId: run.id,
          toolName: call.toolName,
          status: call.status,
          requiresConfirmation: call.requiresConfirmation,
          inputJson: call.inputJson,
          outputJson: call.outputJson,
          nowMs: nowMs,
        ),
      );
    }
    return SecretaryAuditTrail(run: run, toolCalls: records);
  }

  Future<SecretaryAgentDigest> buildAgentDigest(
    Uint8List key, {
    required List<Todo> todos,
    required String deviceId,
    required String localeTag,
    required int nowMs,
  }) async {
    final backend = _backend;
    final memoryPages = backend == null
        ? const <MemoryPageRecord>[]
        : await backend.listMemoryPages(key, state: 'active');
    final pendingProposals = backend == null
        ? const <SecretaryMemoryProposalRecord>[]
        : await backend.listSecretaryMemoryProposals(key, state: 'pending');

    final memories = <Map<String, Object?>>[];
    final preferences = <Map<String, Object?>>[];
    for (final page in memoryPages.take(_digestMaxSectionItems)) {
      final item = _digestMemoryPage(page);
      memories.add(item);
      if (_isPreferenceMemory(page)) {
        preferences.add(item);
      }
    }

    final commitments = <Map<String, Object?>>[];
    final upcomingDeadlines = <Map<String, Object?>>[];
    final staleTasks = <Map<String, Object?>>[];
    for (final todo in todos) {
      if (!_isOpenTodo(todo)) continue;

      final item = _digestTodo(todo);
      if (commitments.length < _digestMaxSectionItems) {
        commitments.add(item);
      }

      if (_isUpcomingDeadline(todo, nowMs) &&
          upcomingDeadlines.length < _digestMaxSectionItems) {
        upcomingDeadlines.add(item);
      }

      if (_isStaleTodo(todo, nowMs) &&
          staleTasks.length < _digestMaxSectionItems) {
        staleTasks.add(item);
      }
    }

    return SecretaryAgentDigest(
      version: 'agent-digest-$nowMs',
      generatedAtMs: nowMs,
      deviceId: _boundedText(deviceId, 96),
      locale: _boundedText(localeTag, 32),
      memories: List.unmodifiable(memories),
      preferences: List.unmodifiable(preferences.take(_digestMaxSectionItems)),
      commitments: List.unmodifiable(commitments),
      upcomingDeadlines: List.unmodifiable(upcomingDeadlines),
      staleTasks: List.unmodifiable(staleTasks),
      recentUnresolvedCaptures: List.unmodifiable(
        pendingProposals
            .take(_digestMaxCaptureItems)
            .map(_digestPendingProposal),
      ),
    );
  }

  SecretaryPlan planFromCloudResult(CloudSecretaryPlanningResult result) {
    final focus = <SecretaryPlanItem>[];
    final dueSoon = <SecretaryPlanItem>[];
    final needsDecision = <SecretaryPlanItem>[];
    final missingNextAction = <SecretaryPlanItem>[];

    for (final item in result.items) {
      final planItem = SecretaryPlanItem(
        id: item.id,
        todoId: item.todoId,
        title: item.title,
        reason: item.reason,
        dueAtMs: item.dueAtMs,
        requiresConfirmation: item.requiresConfirmation,
      );
      switch (item.section) {
        case 'due_soon':
          dueSoon.add(planItem);
          break;
        case 'needs_decision':
          needsDecision.add(planItem);
          break;
        case 'missing_next_action':
          missingNextAction.add(planItem);
          break;
        default:
          focus.add(planItem);
          break;
      }
    }

    return SecretaryPlan(
      id: result.id,
      title: result.title,
      generatedAtMs: result.generatedAtMs,
      route: 'cloud_agent_digest',
      sections: SecretaryPlanSections(
        focus: focus,
        dueSoon: dueSoon,
        needsDecision: needsDecision,
        missingNextAction: missingNextAction,
      ),
      explanation: result.body,
      generatedBy: 'cloud',
      digestGeneratedAtMs: result.digestGeneratedAtMs,
      skipReason: result.skipReason,
    );
  }

  void dismissPlan(SecretaryPlan plan) {
    _dismissedPlanIds.add(plan.id);
  }

  SecretaryMemoryProposal _proposalFromRecord(
    SecretaryMemoryProposalRecord record,
  ) {
    return SecretaryMemoryProposal(
      id: record.id,
      sourceMessageId: record.sourceMessageId ?? record.id,
      kind: record.kind,
      title: record.title,
      body: record.body,
      confidence: record.confidence,
      createdAtMs: platformIntToInt(record.createdAtMs),
      actionHint: record.actionHint ?? 'propose',
    );
  }

  List<SecretaryMemoryProposal> _dedupeMemoryProposals(
    Iterable<SecretaryMemoryProposal> proposals,
  ) {
    final bySignature = <String, SecretaryMemoryProposal>{};
    for (final proposal in proposals) {
      final signature = secretaryMemoryProposalSignature(proposal);
      final existing = bySignature[signature];
      if (existing == null || proposal.createdAtMs > existing.createdAtMs) {
        bySignature[signature] = proposal;
      }
    }
    final result = bySignature.values.toList(growable: false);
    result.sort((a, b) => b.createdAtMs.compareTo(a.createdAtMs));
    return result;
  }

  SecretaryMemoryPage _memoryPageFromRecord(MemoryPageRecord record) {
    return SecretaryMemoryPage(
      id: record.pageId,
      title: record.title,
      body: record.body,
      state: _memoryStateFromWire(record.state),
      updatedAtMs: platformIntToInt(record.updatedAtMs),
      kind: record.pageType,
    );
  }

  SecretaryMemoryState _memoryStateFromWire(String state) {
    return switch (state) {
      'archived' => SecretaryMemoryState.archived,
      'stale' || 'needs_review' => SecretaryMemoryState.needsReview,
      _ => SecretaryMemoryState.active,
    };
  }

  String _planBody(SecretaryPlan plan) {
    final summary = '${plan.itemCount} suggestions, '
        '${plan.requiresConfirmationCount} need confirmation.';
    final explanation = plan.explanation?.trim();
    if (explanation == null || explanation.isEmpty) return summary;
    return '$explanation\n\n$summary';
  }

  String _planItemsJson(SecretaryPlan plan) {
    final items = <Map<String, Object?>>[];
    void addItems(String section, List<SecretaryPlanItem> sectionItems) {
      for (final item in sectionItems) {
        items.add({
          'id': item.id,
          'todo_id': item.todoId,
          'section': section,
          'title': item.title,
          'reason': item.reason,
          'due_at_ms': item.dueAtMs,
          'requires_confirmation': item.requiresConfirmation,
        });
      }
    }

    addItems('focus', plan.sections.focus);
    addItems('due_soon', plan.sections.dueSoon);
    addItems('needs_decision', plan.sections.needsDecision);
    addItems('missing_next_action', plan.sections.missingNextAction);
    return jsonEncode(items);
  }

  String _planSourceRefsJson(SecretaryPlan plan) {
    return jsonEncode({
      'todo_ids': [
        for (final item in plan.sections.allItems) item.todoId,
      ],
    });
  }

  int _endOfLocalDayMs(int nowMs) {
    final now = DateTime.fromMillisecondsSinceEpoch(nowMs);
    return DateTime(now.year, now.month, now.day + 1).millisecondsSinceEpoch;
  }

  Map<String, Object?> _digestMemoryPage(MemoryPageRecord page) {
    return <String, Object?>{
      'page_id': page.pageId,
      'kind': _boundedText(page.pageType, 48),
      'title': _boundedText(page.title, _digestTitleMaxChars),
      'body': _boundedText(page.body, _digestBodyMaxChars),
      'updated_at_ms': platformIntToInt(page.updatedAtMs),
    };
  }

  Map<String, Object?> _digestPendingProposal(
    SecretaryMemoryProposalRecord proposal,
  ) {
    return <String, Object?>{
      'proposal_id': proposal.id,
      'source_message_id': proposal.sourceMessageId,
      'kind': _boundedText(proposal.kind, 48),
      'title': _boundedText(proposal.title, _digestTitleMaxChars),
      'body': _boundedText(proposal.body, _digestBodyMaxChars),
      'created_at_ms': platformIntToInt(proposal.createdAtMs),
    };
  }

  Map<String, Object?> _digestTodo(Todo todo) {
    return <String, Object?>{
      'todo_id': todo.id,
      'title': _boundedText(todo.title, _digestTitleMaxChars),
      'status': _boundedText(todo.status, 32),
      'due_at_ms': platformIntToNullableInt(todo.dueAtMs),
      'updated_at_ms': platformIntToInt(todo.updatedAtMs),
      'review_stage': platformIntToNullableInt(todo.reviewStage),
    };
  }

  bool _isPreferenceMemory(MemoryPageRecord page) {
    final haystack =
        '${page.pageType} ${page.title} ${page.body}'.toLowerCase().trim();
    return haystack.contains('preference') ||
        haystack.contains('prefer') ||
        haystack.contains('偏好') ||
        haystack.contains('喜欢') ||
        haystack.contains('更喜欢');
  }

  bool _isOpenTodo(Todo todo) {
    final status = todo.status.toLowerCase();
    return status != 'done' &&
        status != 'completed' &&
        status != 'archived' &&
        status != 'deleted';
  }

  bool _isUpcomingDeadline(Todo todo, int nowMs) {
    final dueAtMs = platformIntToNullableInt(todo.dueAtMs);
    if (dueAtMs == null) return false;
    if (dueAtMs < nowMs) return true;
    return dueAtMs - nowMs <= const Duration(days: 14).inMilliseconds;
  }

  bool _isStaleTodo(Todo todo, int nowMs) {
    final reviewStage = platformIntToNullableInt(todo.reviewStage) ?? 0;
    if (reviewStage >= 2) return true;
    final nextReviewAtMs = platformIntToNullableInt(todo.nextReviewAtMs);
    if (nextReviewAtMs != null && nextReviewAtMs <= nowMs) return true;
    final updatedAtMs = platformIntToInt(todo.updatedAtMs);
    return nowMs - updatedAtMs >= const Duration(days: 7).inMilliseconds;
  }

  String _boundedText(String value, int maxChars) {
    final normalized = value.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (normalized.length <= maxChars) return normalized;
    return normalized.substring(0, maxChars);
  }
}
