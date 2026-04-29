import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:secondloop/core/backend/secretary_backend.dart';
import 'package:secondloop/core/secretary/rule_based_planning_engine.dart';
import 'package:secondloop/core/secretary/secretary_controller.dart';
import 'package:secondloop/core/secretary/secretary_models.dart';
import 'package:secondloop/src/rust/db.dart';
import 'package:secondloop/src/rust/platform_int.dart';

void main() {
  test('persists pending memory proposal once for a saved user message',
      () async {
    final backend = _FakeSecretaryBackend();
    final controller = SecretaryController(
      backend: backend,
      planningEngine: const RuleBasedPlanningEngine(nowLocal: DateTime.now),
    );
    final key = Uint8List(32);
    const message = Message(
      id: 'm1',
      conversationId: 'loop_home',
      role: 'user',
      content: 'Remember that I prefer morning meetings.',
      createdAtMs: 100,
      isMemory: true,
    );

    final first = await controller.persistMemoryProposalForMessage(
      key,
      message,
      nowMs: 110,
    );
    final second = await controller.persistMemoryProposalForMessage(
      key,
      message,
      nowMs: 120,
    );

    expect(first, isNotNull);
    expect(second, isNull);
    expect(backend.createdProposalCount, 1);
    expect(first!.sourceMessageId, 'm1');
    expect(first.kind, 'preference');

    final pending = await controller.pendingMemoryProposals(key);
    expect(pending.single.title, contains('morning meetings'));
  });

  test('accepts and dismisses memory proposals through the backend', () async {
    final backend = _FakeSecretaryBackend();
    final controller = SecretaryController(
      backend: backend,
      planningEngine: const RuleBasedPlanningEngine(nowLocal: DateTime.now),
    );
    final key = Uint8List(32);
    final proposal = await controller.persistMemoryProposalForMessage(
      key,
      const Message(
        id: 'm2',
        conversationId: 'loop_home',
        role: 'user',
        content: 'Actually, I no longer work with Alice.',
        createdAtMs: 100,
        isMemory: true,
      ),
      nowMs: 130,
    );

    final page = await controller.acceptMemoryProposal(
      key,
      proposal!,
      nowMs: 140,
    );
    expect(page.state, SecretaryMemoryState.active);
    expect(backend.acceptedProposalIds, [proposal.id]);

    await controller.dismissMemoryProposal(key, proposal, nowMs: 150);
    expect(backend.dismissedProposalIds, [proposal.id]);
  });
}

final class _FakeSecretaryBackend implements SecretaryBackend {
  final Map<String, SecretaryMemoryProposalRecord> _proposals =
      <String, SecretaryMemoryProposalRecord>{};
  final List<String> acceptedProposalIds = <String>[];
  final List<String> dismissedProposalIds = <String>[];

  int get createdProposalCount => _proposals.length;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);

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
      id: 'proposal-${_proposals.length + 1}',
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
    );
    _proposals[record.id] = record;
    return record;
  }

  @override
  Future<List<SecretaryMemoryProposalRecord>> listSecretaryMemoryProposals(
    Uint8List key, {
    String? state,
  }) async {
    return _proposals.values
        .where((proposal) => state == null || proposal.state == state)
        .toList(growable: false);
  }

  @override
  Future<MemoryPageRecord> acceptSecretaryMemoryProposal(
    Uint8List key, {
    required String proposalId,
    required int nowMs,
  }) async {
    acceptedProposalIds.add(proposalId);
    final proposal = _proposals[proposalId]!;
    return MemoryPageRecord(
      pageId: 'memory-$proposalId',
      pageType: 'memory',
      state: 'active',
      sourceCount: platformIntFromInt(1),
      title: proposal.title,
      summary: proposal.body,
      body: proposal.body,
      primaryEvidenceJson: proposal.sourceRefsJson ?? '[]',
      sourceDocumentIdsJson: '["${proposal.sourceMessageId}"]',
      confidenceLevel: proposal.confidence,
      humanCorrected: false,
      createdAtMs: platformIntFromInt(nowMs),
      updatedAtMs: platformIntFromInt(nowMs),
    );
  }

  @override
  Future<SecretaryMemoryProposalRecord> dismissSecretaryMemoryProposal(
    Uint8List key, {
    required String proposalId,
    required int nowMs,
  }) async {
    dismissedProposalIds.add(proposalId);
    final existing = _proposals[proposalId]!;
    final dismissed = SecretaryMemoryProposalRecord(
      id: existing.id,
      sourceMessageId: existing.sourceMessageId,
      kind: existing.kind,
      title: existing.title,
      body: existing.body,
      confidence: existing.confidence,
      state: 'dismissed',
      sourceRefsJson: existing.sourceRefsJson,
      actionHint: existing.actionHint,
      createdAtMs: existing.createdAtMs,
      updatedAtMs: platformIntFromInt(nowMs),
      dismissedAtMs: platformIntFromInt(nowMs),
    );
    _proposals[proposalId] = dismissed;
    return dismissed;
  }

  @override
  Future<MemoryPageRecord> archiveMemoryPage(Uint8List key,
      {required String pageId, required int nowMs}) {
    throw UnimplementedError();
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
  }) {
    throw UnimplementedError();
  }

  @override
  Future<MemoryPageRecord> getMemoryPage(Uint8List key,
      {required String pageId}) {
    throw UnimplementedError();
  }

  @override
  Future<List<MemoryPageRecord>> listMemoryPages(Uint8List key,
      {String? state}) async {
    return const <MemoryPageRecord>[];
  }

  @override
  Future<List<PlanningOutputRecord>> listPlanningOutputs(
    Uint8List key, {
    String? kind,
    required int nowMs,
    bool includeExpired = false,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<MemoryPageRecord> restoreMemoryPage(Uint8List key,
      {required String pageId, required int nowMs}) {
    throw UnimplementedError();
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
  }) {
    throw UnimplementedError();
  }
}
