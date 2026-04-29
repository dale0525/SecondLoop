import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:secondloop/core/backend/secretary_backend.dart';
import 'package:secondloop/core/secretary/rule_based_planning_engine.dart';
import 'package:secondloop/core/secretary/secretary_controller.dart';
import 'package:secondloop/src/rust/db.dart';
import 'package:secondloop/src/rust/platform_int.dart';

void main() {
  test('local plan persists without AI or Cloud and expires older drafts',
      () async {
    final now = DateTime(2026, 4, 29, 9);
    final backend = _PlanningBackend(
      [
        _planningOutput(
          id: 'old-plan',
          state: 'active',
          nowMs: now.subtract(const Duration(days: 1)).millisecondsSinceEpoch,
        ),
      ],
    );
    final controller = SecretaryController(
      backend: backend,
      planningEngine: RuleBasedPlanningEngine(nowLocal: () => now),
    );
    final key = Uint8List(32);

    final plan = await controller.generateAndPersistPlan(
      key,
      [
        Todo(
          id: 't1',
          title: 'Submit app review',
          dueAtMs: platformIntFromInt(
            now.subtract(const Duration(hours: 1)).millisecondsSinceEpoch,
          ),
          status: 'open',
          createdAtMs: platformIntFromInt(100),
          updatedAtMs: platformIntFromInt(100),
        ),
      ],
      nowMs: now.millisecondsSinceEpoch,
    );

    expect(plan.route, 'local_rules');
    expect(plan.itemCount, 1);
    expect(backend.records['old-plan']!.state, 'expired');

    final persisted = backend.records[plan.id]!;
    expect(persisted.kind, 'daily_plan');
    expect(persisted.route, 'local_rules');
    expect(persisted.state, 'active');
    final items = jsonDecode(persisted.itemsJson) as List<dynamic>;
    expect(items.single['todo_id'], 't1');
  });
}

final class _PlanningBackend implements SecretaryBackend {
  _PlanningBackend(List<PlanningOutputRecord> initial) {
    for (final record in initial) {
      records[record.id] = record;
    }
  }

  final Map<String, PlanningOutputRecord> records =
      <String, PlanningOutputRecord>{};

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);

  @override
  Future<List<PlanningOutputRecord>> listPlanningOutputs(
    Uint8List key, {
    String? kind,
    required int nowMs,
    bool includeExpired = false,
  }) async {
    return records.values
        .where((record) => kind == null || record.kind == kind)
        .where((record) => includeExpired || record.state != 'expired')
        .toList(growable: false);
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
      dismissedAtMs:
          state == 'dismissed' ? platformIntFromInt(updatedAtMs) : null,
    );
    records[id] = record;
    return record;
  }

  @override
  Future<MemoryPageRecord> acceptSecretaryMemoryProposal(
    Uint8List key, {
    required String proposalId,
    required int nowMs,
  }) {
    throw UnimplementedError();
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
  }) {
    throw UnimplementedError();
  }

  @override
  Future<SecretaryMemoryProposalRecord> dismissSecretaryMemoryProposal(
    Uint8List key, {
    required String proposalId,
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
  Future<List<SecretaryMemoryProposalRecord>> listSecretaryMemoryProposals(
    Uint8List key, {
    String? state,
  }) async {
    return const <SecretaryMemoryProposalRecord>[];
  }

  @override
  Future<MemoryPageRecord> restoreMemoryPage(Uint8List key,
      {required String pageId, required int nowMs}) {
    throw UnimplementedError();
  }
}

PlanningOutputRecord _planningOutput({
  required String id,
  required String state,
  required int nowMs,
}) {
  return PlanningOutputRecord(
    id: id,
    kind: 'daily_plan',
    title: 'Daily plan',
    body: 'Old plan',
    itemsJson: '[]',
    route: 'local_rules',
    state: state,
    createdAtMs: platformIntFromInt(nowMs),
    updatedAtMs: platformIntFromInt(nowMs),
  );
}
