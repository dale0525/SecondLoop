import 'dart:convert';
import 'dart:typed_data';

import '../backend/secretary_backend.dart';
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
  final Set<String> _dismissedPlanIds = <String>{};

  List<SecretaryMemoryProposal> pendingMemoryProposalsForMessages(
    List<Message> messages,
  ) {
    final proposals = <SecretaryMemoryProposal>[];
    for (final message in messages) {
      if (message.role != 'user') continue;
      if (_acceptedProposalSourceIds.contains(message.id)) continue;
      if (_dismissedProposalSourceIds.contains(message.id)) continue;
      final proposal = _detector.detect(
        messageId: message.id,
        text: message.content,
        createdAtMs: platformIntToInt(message.createdAtMs),
      );
      if (proposal != null) proposals.add(proposal);
    }
    return proposals;
  }

  Future<SecretaryMemoryProposal?> persistMemoryProposalForMessage(
    Uint8List key,
    Message message, {
    required int nowMs,
  }) async {
    if (message.role != 'user') return null;
    final detected = _detector.detect(
      messageId: message.id,
      text: message.content,
      createdAtMs: platformIntToInt(message.createdAtMs),
    );
    if (detected == null) return null;

    final backend = _backend;
    if (backend == null) {
      if (_acceptedProposalSourceIds.contains(message.id) ||
          _dismissedProposalSourceIds.contains(message.id)) {
        return null;
      }
      return detected;
    }

    final existing = await backend.listSecretaryMemoryProposals(key);
    final alreadyTracked = existing.any(
      (proposal) => proposal.sourceMessageId == message.id,
    );
    if (alreadyTracked) return null;

    final record = await backend.createSecretaryMemoryProposal(
      key,
      sourceMessageId: detected.sourceMessageId,
      kind: detected.kind,
      title: detected.title,
      body: detected.body,
      confidence: detected.confidence,
      sourceRefsJson: jsonEncode({
        'message_ids': [detected.sourceMessageId],
      }),
      actionHint: detected.actionHint,
      nowMs: nowMs,
    );
    return _proposalFromRecord(record);
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
    return records.map(_proposalFromRecord).toList(growable: false);
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
      return _memoryPageFromRecord(record);
    }

    _acceptedProposalSourceIds.add(proposal.sourceMessageId);
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
}
